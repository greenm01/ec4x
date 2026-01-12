import std/[tables, options]

# Generic SAM Pattern Types

type
  # A Proposal is a request to mutate the model (Action result)
  Proposal*[M] = object
    name*: string
    payload*: proc(m: var M)

  # An Acceptor mutates the model based on a proposal
  Acceptor*[M] = proc(model: var M, proposal: Proposal[M]): bool

  # A Reactor observes the model and triggers side effects
  Reactor*[M] = proc(model: M, dispatch: proc(p: Proposal[M]))

  # The SAM Container
  SamLoop*[M] = ref object
    model*: M
    acceptors*: seq[Acceptor[M]]
    reactors*: seq[Reactor[M]]
    proposalQueue*: seq[Proposal[M]]

proc newSamLoop*[M](initialModel: M): SamLoop[M] =
  result = SamLoop[M](
    model: initialModel,
    acceptors: @[],
    reactors: @[],
    proposalQueue: @[]
  )

proc addAcceptor*[M](sam: SamLoop[M], acceptor: Acceptor[M]) =
  sam.acceptors.add(acceptor)

proc addReactor*[M](sam: SamLoop[M], reactor: Reactor[M]) =
  sam.reactors.add(reactor)

proc present*[M](sam: SamLoop[M], proposal: Proposal[M]) =
  ## Present a proposal to the model
  ## This queues it for the next processing step
  sam.proposalQueue.add(proposal)

proc process*[M](sam: SamLoop[M]) =
  ## Process all queued proposals
  ## 1. Run Acceptors (mutate model)
  ## 2. Run Reactors (side effects)
  
  if sam.proposalQueue.len == 0:
    return

  var modelChanged = false
  
  # 1. Acceptors (Mutation Phase)
  for proposal in sam.proposalQueue:
    for acceptor in sam.acceptors:
      if acceptor(sam.model, proposal):
        modelChanged = true
  
  # Clear processed proposals
  sam.proposalQueue.setLen(0)

  # 2. Reactors (Side Effect Phase)
  # Only run if model changed or we want continuous checking? 
  # Usually SAM implies reactors run after mutation.
  if modelChanged:
    let dispatch = proc(p: Proposal[M]) = sam.present(p)
    for reactor in sam.reactors:
      reactor(sam.model, dispatch)
