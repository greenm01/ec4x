## SAM Instance Implementation
##
## The core SAM loop implementation. This module provides:
## - Instance creation and configuration
## - The present() function (heart of SAM)
## - Acceptor, reactor, and NAP management
## - Safety condition checking with rollback
## - Time travel support
##
## Usage:
##   var sam = initSam[MyModel]()
##   sam.addAcceptor(myAcceptor)
##   sam.addReactor(myReactor)
##   sam.setRender(myRenderProc)
##   sam.setInitialState(myInitialModel)
##   
##   # Main loop
##   let proposal = actionFunc(event)
##   sam.present(proposal)

import std/[options, times]
import types

export types

# ============================================================================
# SAM Instance Creation
# ============================================================================

proc initSam*[M](): SamInstance[M] =
  ## Create a new SAM instance with default configuration
  SamInstance[M](
    acceptors: @[],
    reactors: @[],
    naps: @[],
    safety: @[],
    render: nil,
    history: none(History[M]),
    lastProposalTimestamp: 0,
    allowedActions: @[],
    disallowedActions: @[],
    blockUnexpectedActions: false,
    shouldRender: true,
    lastError: none(string)
  )

proc initSamWithHistory*[M](maxHistory: int = 100): SamInstance[M] =
  ## Create a new SAM instance with time travel support
  result = initSam[M]()
  result.history = some(initHistory[M](maxHistory))

# ============================================================================
# Configuration
# ============================================================================

proc setInitialState*[M](sam: var SamInstance[M], initialState: M) =
  ## Set the initial model state
  sam.model = initialState
  if sam.history.isSome:
    var h = sam.history.get
    h.snap(sam.model, "initialState")
    sam.history = some(h)

proc addAcceptor*[M](sam: var SamInstance[M], acceptor: AcceptorProc[M]) =
  ## Add an acceptor function to process proposals
  sam.acceptors.add(acceptor)

proc addReactor*[M](sam: var SamInstance[M], reactor: ReactorProc[M]) =
  ## Add a reactor function to derive state after mutations
  sam.reactors.add(reactor)

proc addNap*[M](sam: var SamInstance[M], nap: NapProc[M]) =
  ## Add a NAP (Next-Action Predicate)
  sam.naps.add(nap)

proc addSafetyCondition*[M](sam: var SamInstance[M], condition: SafetyCondition[M]) =
  ## Add a safety condition (rollback trigger)
  sam.safety.add(condition)

proc setRender*[M](sam: var SamInstance[M], render: RenderProc[M]) =
  ## Set the render function
  sam.render = render

proc allowActions*[M](sam: var SamInstance[M], actions: varargs[string]) =
  ## Set list of allowed action names
  for action in actions:
    if action notin sam.allowedActions:
      sam.allowedActions.add(action)

proc disallowActions*[M](sam: var SamInstance[M], actions: varargs[string]) =
  ## Set list of disallowed action names
  for action in actions:
    if action notin sam.disallowedActions:
      sam.disallowedActions.add(action)

proc clearAllowedActions*[M](sam: var SamInstance[M]) =
  ## Clear allowed actions list (allows all)
  sam.allowedActions = @[]

proc clearDisallowedActions*[M](sam: var SamInstance[M]) =
  ## Clear disallowed actions list
  sam.disallowedActions = @[]

proc setBlockUnexpected*[M](sam: var SamInstance[M], shouldBlock: bool) =
  ## Set whether to block unexpected actions when allowedActions is set
  sam.blockUnexpectedActions = shouldBlock

proc doNotRender*[M](sam: var SamInstance[M]) =
  ## Skip next render cycle
  sam.shouldRender = false

# ============================================================================
# Action Validation
# ============================================================================

proc isAllowed*[M](sam: SamInstance[M], actionName: string): bool =
  ## Check if an action is allowed to execute
  # If no restrictions, allow all
  if not sam.blockUnexpectedActions and sam.allowedActions.len == 0:
    return true
  
  # Check if explicitly disallowed
  if actionName in sam.disallowedActions:
    return false
  
  # If we have an allowed list and blocking is on, check against it
  if sam.allowedActions.len > 0:
    return actionName in sam.allowedActions
  
  true

# ============================================================================
# Safety Conditions & Rollback
# ============================================================================

proc checkSafety*[M](sam: var SamInstance[M]): bool =
  ## Check all safety conditions, rollback if violated
  ## Returns true if safe, false if violation occurred
  for condition in sam.safety:
    if condition.expression(sam.model):
      # Violation detected
      sam.lastError = some("Safety violation: " & condition.name)
      
      # Rollback if history available
      if sam.history.isSome:
        var h = sam.history.get
        let prevState = h.prev()
        if prevState.isSome:
          sam.model = prevState.get
          sam.history = some(h)
      
      return false
  
  true

# ============================================================================
# State Representation (Reactors)
# ============================================================================

proc computeState*[M](sam: var SamInstance[M]) =
  ## Run all reactors to compute derived state
  for reactor in sam.reactors:
    reactor(sam.model)

# ============================================================================
# NAPs (Next-Action Predicates)
# ============================================================================

proc checkNaps*[M](sam: var SamInstance[M]): Option[Proposal] =
  ## Check NAPs and return next proposal if automatic action needed
  for nap in sam.naps:
    let nextProposal = nap(sam.model)
    if nextProposal.isSome:
      return nextProposal
  none(Proposal)

# ============================================================================
# Present - The Heart of SAM
# ============================================================================

proc present*[M](sam: var SamInstance[M], proposal: Proposal) =
  ## Present a proposal to the model.
  ## This is the core SAM function that:
  ## 1. Validates the action
  ## 2. Runs acceptors to mutate state
  ## 3. Runs reactors to derive state
  ## 4. Checks safety conditions (rollback if violated)
  ## 5. Checks NAPs for automatic next actions
  ## 6. Renders if no NAP triggered
  
  # Check if action is allowed
  if not sam.isAllowed(proposal.actionName):
    sam.lastError = some("Action not allowed: " & proposal.actionName)
    return
  
  # Check for out-of-order proposals (optional timestamp check)
  if proposal.timestamp > 0 and proposal.timestamp < sam.lastProposalTimestamp:
    # Out of order, ignore
    return
  sam.lastProposalTimestamp = proposal.timestamp
  
  # Clear any previous error
  sam.lastError = none(string)
  
  # Run acceptors to mutate model
  for acceptor in sam.acceptors:
    acceptor(sam.model, proposal)
  
  # Run reactors to derive state
  sam.computeState()
  
  # Check safety conditions
  let safe = sam.checkSafety()
  if not safe:
    # Safety violation occurred, model was rolled back
    # Still render the rolled-back state
    if sam.render != nil and sam.shouldRender:
      sam.render(sam.model)
    sam.shouldRender = true
    return
  
  # Take history snapshot after successful mutation
  if sam.history.isSome:
    var h = sam.history.get
    h.snap(sam.model, proposal.actionName)
    sam.history = some(h)
  
  # Check NAPs - if any returns a proposal, call present recursively
  let nextProposal = sam.checkNaps()
  if nextProposal.isSome:
    # NAP triggered - recursive present, skip render
    sam.present(nextProposal.get)
    return
  
  # No NAP triggered - render state representation
  if sam.render != nil and sam.shouldRender:
    sam.render(sam.model)
  sam.shouldRender = true

# ============================================================================
# Time Travel
# ============================================================================

proc travelTo*[M](sam: var SamInstance[M], idx: int) =
  ## Travel to specific history index
  if sam.history.isSome:
    var h = sam.history.get
    let state = h.travel(idx)
    if state.isSome:
      sam.model = state.get
      sam.history = some(h)
      if sam.render != nil:
        sam.render(sam.model)

proc travelNext*[M](sam: var SamInstance[M]) =
  ## Move forward in history
  if sam.history.isSome:
    var h = sam.history.get
    let state = h.next()
    if state.isSome:
      sam.model = state.get
      sam.history = some(h)
      if sam.render != nil:
        sam.render(sam.model)

proc travelPrev*[M](sam: var SamInstance[M]) =
  ## Move backward in history
  if sam.history.isSome:
    var h = sam.history.get
    let state = h.prev()
    if state.isSome:
      sam.model = state.get
      sam.history = some(h)
      if sam.render != nil:
        sam.render(sam.model)

proc travelReset*[M](sam: var SamInstance[M]) =
  ## Reset to initial state
  if sam.history.isSome:
    var h = sam.history.get
    let state = h.first()
    if state.isSome:
      sam.model = state.get
      h.reset()
      sam.history = some(h)
      if sam.render != nil:
        sam.render(sam.model)

proc hasNext*[M](sam: SamInstance[M]): bool =
  ## Check if there's forward history
  if sam.history.isSome:
    sam.history.get.hasNext
  else:
    false

proc hasPrev*[M](sam: SamInstance[M]): bool =
  ## Check if there's backward history
  if sam.history.isSome:
    sam.history.get.hasPrev
  else:
    false

# ============================================================================
# Convenience Query Functions
# ============================================================================

proc hasError*[M](sam: SamInstance[M]): bool =
  ## Check if last operation had an error
  sam.lastError.isSome

proc errorMessage*[M](sam: SamInstance[M]): string =
  ## Get last error message
  sam.lastError.get("")

proc state*[M](sam: SamInstance[M]): M =
  ## Get current model state (read-only copy)
  sam.model
