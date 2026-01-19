import std/[tables, options, asyncdispatch]

# Generic SAM Pattern Types (async cmds)

type
  Proposal*[M] = object
    name*: string
    payload*: proc(m: var M)

  Acceptor*[M] = proc(model: var M, proposal: Proposal[M]): bool

  Reactor*[M] = proc(model: M, dispatch: proc(p: Proposal[M]))

  # Cmd is a thunk that returns Future[Proposal]
  Cmd*[M] = proc (): Future[Proposal[M]]

  # The SAM Container
  SamLoop*[M] = ref object
    model*: M
    acceptors*: seq[Acceptor[M]]
    reactors*: seq[Reactor[M]]
    proposalQueue*: seq[Proposal[M]]
    cmdQueue*: seq[Future[Proposal[M]]]

proc newSamLoop*[M](initialModel: M): SamLoop[M] =
  result = SamLoop[M](
    model: initialModel,
    acceptors: @[],
    reactors: @[],
    proposalQueue: @[],
    cmdQueue: @[]
  )

proc addAcceptor*[M](sam: SamLoop[M], acceptor: Acceptor[M]) =
  sam.acceptors.add(acceptor)

proc addReactor*[M](sam: SamLoop[M], reactor: Reactor[M]) =
  sam.reactors.add(reactor)

proc present*[M](sam: SamLoop[M], proposal: Proposal[M]) =
  ## Queue a proposal for processing in the next SAM loop iteration.
  ## Proposals are processed FIFO and trigger acceptors + reactors.
  sam.proposalQueue.add(proposal)

proc queueCmd*[M](sam: SamLoop[M], cmd: Cmd[M]) =
  ## Queue an async command (effect) for background execution.
  ## When the Cmd completes, its returned Proposal is automatically queued.
  ## Commands are polled each iteration and removed when finished.
  sam.cmdQueue.add(cmd())

proc process*[M](sam: SamLoop[M]) =
  ## Main SAM loop iteration - processes all pending work in order:
  ## 1. Poll async Cmds - collect completed Future[Proposal]s
  ## 2. Process all queued Proposals through Acceptors (model mutations)
  ## 3. Trigger Reactors (side effects like queueing new Cmds)
  ##
  ## This should be called repeatedly in your main loop (e.g., every 100ms).
  ## Safe to call even when no work is pending.

  # Poll completed cmds
  var i = 0
  while i < sam.cmdQueue.len:
    if sam.cmdQueue[i].finished:
      let p = sam.cmdQueue[i].read()
      sam.proposalQueue.add(p)
      sam.cmdQueue.delete(i)
    else:
      inc i

  if sam.proposalQueue.len == 0:
    return

  var modelChanged = false

  # Take a snapshot of the current queue to allow new proposals during processing
  let currentProposals = sam.proposalQueue
  sam.proposalQueue = @[]

  # Acceptors (Mutation)
  for proposal in currentProposals:
    var p = proposal # copy to allow mutation in acceptor if needed
    for acceptor in sam.acceptors:
      if acceptor(sam.model, p):
        modelChanged = true

  # Reactors (Side effects)
  let dispatch = proc(p: Proposal[M]) = sam.present(p)
  for reactor in sam.reactors:
    reactor(sam.model, dispatch)