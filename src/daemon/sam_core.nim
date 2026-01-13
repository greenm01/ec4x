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
  sam.proposalQueue.add(proposal)

proc queueCmd*[M](sam: SamLoop[M], cmd: Cmd[M]) =
  sam.cmdQueue.add(cmd())

proc process*[M](sam: SamLoop[M]) =
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

  # Acceptors (Mutation)
  for proposal in sam.proposalQueue.mitems:
    for acceptor in sam.acceptors:
      if acceptor(sam.model, proposal):
        modelChanged = true

  sam.proposalQueue.setLen(0)

  # Reactors (Side effects)
  let dispatch = proc(p: Proposal[M]) = sam.present(p)
  for reactor in sam.reactors:
    reactor(sam.model, dispatch)