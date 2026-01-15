## SAM Pattern Core Types
##
## Implementation of State-Action-Model pattern based on TLA+ semantics.
## Adapted from JavaScript sam-pattern library for Nim.
##
## The SAM pattern enforces a unidirectional data flow:
##   Event -> Action -> Present -> Model(Acceptors -> Reactors) -> State -> NAPs -> Render
##
## Key concepts:
## - Actions: Pure functions that compute proposals from events
## - Proposals: Data structures representing intent (no side effects)
## - Acceptors: Functions that mutate model state based on proposals
## - Reactors: Functions that derive/compute additional state after mutation
## - NAPs: Next-Action Predicates that can trigger automatic actions
## - Safety: Conditions that trigger rollback if violated

import std/[tables, options, times]

type
  # ============================================================================
  # Core SAM Types
  # ============================================================================
  
  ProposalKind* = enum
    ## Discriminator for proposal types
    pkNone           ## Empty/no-op proposal
    pkError          ## Error condition
    pkNavigation     ## UI navigation (mode switch, cursor move)
    pkSelection      ## Selection change
    pkGameAction     ## Game state modification
    pkViewportScroll ## Viewport/scroll change
    pkEndTurn        ## End turn action
    pkQuit           ## Application exit
  
  Proposal* = object
    ## A proposal represents an intent to change state.
    ## Proposals are immutable data - they don't cause side effects directly.
    timestamp*: int64           ## When proposal was created
    actionName*: string         ## Name of action that created this (for debugging)
    case kind*: ProposalKind
    of pkNone:
      discard
    of pkError:
      errorMsg*: string
    of pkNavigation:
      navMode*: int             ## ViewMode enum value
      navCursor*: tuple[q, r: int]  ## Hex coordinate for cursor
    of pkSelection:
      selectIdx*: int           ## Index in current list
      selectCoord*: Option[tuple[q, r: int]]  ## Hex coordinate if applicable
    of pkGameAction:
      gameActionType*: string   ## Type of game action
      gameActionData*: string   ## JSON-encoded action data
    of pkViewportScroll:
      scrollDelta*: tuple[dx, dy: int]
    of pkEndTurn:
      discard
    of pkQuit:
      discard

  AcceptorProc*[M] = proc(model: var M, proposal: Proposal) {.nimcall.}
    ## Acceptor: mutates model based on proposal
    ## Signature: (model, proposal) -> void (mutates model in place)
  
  ReactorProc*[M] = proc(model: var M) {.nimcall.}
    ## Reactor: derives additional state after acceptors run
    ## Signature: (model) -> void (can derive/compute state)
  
  NapProc*[M] = proc(model: M): Option[Proposal] {.nimcall.}
    ## NAP (Next-Action Predicate): returns next proposal if automatic action needed
    ## Returns Some(proposal) to trigger next action, None to allow render
  
  SafetyCondition*[M] = object
    ## Safety condition that triggers rollback if violated
    name*: string
    expression*: proc(model: M): bool {.nimcall.}  ## Returns true if UNSAFE (violation)
  
  RenderProc*[M] = proc(model: M) {.closure.}
    ## Render function: displays state representation (closure to capture state)

  # ============================================================================
  # History/Time Travel
  # ============================================================================
  
  HistoryEntry*[M] = object
    ## A snapshot of model state at a point in time
    state*: M
    timestamp*: int64
    actionName*: string
  
  History*[M] = object
    ## Time travel support - stores state snapshots
    entries*: seq[HistoryEntry[M]]
    currentIdx*: int
    maxEntries*: int

  # ============================================================================
  # SAM Instance
  # ============================================================================
  
  SamInstance*[M] = object
    ## A SAM instance manages the complete SAM lifecycle for a model
    model*: M
    acceptors*: seq[AcceptorProc[M]]
    reactors*: seq[ReactorProc[M]]
    naps*: seq[NapProc[M]]
    safety*: seq[SafetyCondition[M]]
    render*: RenderProc[M]
    history*: Option[History[M]]
    lastProposalTimestamp*: int64
    allowedActions*: seq[string]
    disallowedActions*: seq[string]
    blockUnexpectedActions*: bool
    shouldRender*: bool
    lastError*: Option[string]

# ============================================================================
# Proposal Constructors
# ============================================================================

proc emptyProposal*(): Proposal =
  ## Create an empty/no-op proposal
  Proposal(
    kind: pkNone,
    timestamp: getTime().toUnix(),
    actionName: "none"
  )

proc errorProposal*(msg: string): Proposal =
  ## Create an error proposal
  Proposal(
    kind: pkError,
    timestamp: getTime().toUnix(),
    actionName: "error",
    errorMsg: msg
  )

proc navigationProposal*(mode: int, name: string = "navigate"): Proposal =
  ## Create a navigation mode change proposal
  Proposal(
    kind: pkNavigation,
    timestamp: getTime().toUnix(),
    actionName: name,
    navMode: mode,
    navCursor: (0, 0)
  )

proc cursorProposal*(q, r: int, name: string = "cursor"): Proposal =
  ## Create a cursor move proposal
  Proposal(
    kind: pkNavigation,
    timestamp: getTime().toUnix(),
    actionName: name,
    navMode: -1,  # -1 means don't change mode
    navCursor: (q, r)
  )

proc selectionProposal*(idx: int, name: string = "select"): Proposal =
  ## Create a selection change proposal
  Proposal(
    kind: pkSelection,
    timestamp: getTime().toUnix(),
    actionName: name,
    selectIdx: idx,
    selectCoord: none(tuple[q, r: int])
  )

proc coordSelectionProposal*(q, r: int, name: string = "selectCoord"): Proposal =
  ## Create a coordinate selection proposal
  Proposal(
    kind: pkSelection,
    timestamp: getTime().toUnix(),
    actionName: name,
    selectIdx: -1,
    selectCoord: some((q, r))
  )

proc scrollProposal*(dx, dy: int, name: string = "scroll"): Proposal =
  ## Create a viewport scroll proposal
  Proposal(
    kind: pkViewportScroll,
    timestamp: getTime().toUnix(),
    actionName: name,
    scrollDelta: (dx, dy)
  )

proc endTurnProposal*(): Proposal =
  ## Create an end turn proposal
  Proposal(
    kind: pkEndTurn,
    timestamp: getTime().toUnix(),
    actionName: "endTurn"
  )

proc quitProposal*(): Proposal =
  ## Create a quit proposal
  Proposal(
    kind: pkQuit,
    timestamp: getTime().toUnix(),
    actionName: "quit"
  )

proc gameActionProposal*(actionType, data: string): Proposal =
  ## Create a game action proposal
  Proposal(
    kind: pkGameAction,
    timestamp: getTime().toUnix(),
    actionName: actionType,
    gameActionType: actionType,
    gameActionData: data
  )

# ============================================================================
# History Operations
# ============================================================================

proc initHistory*[M](maxEntries: int = 100): History[M] =
  ## Create a new history with specified max entries
  History[M](
    entries: @[],
    currentIdx: -1,
    maxEntries: maxEntries
  )

proc snap*[M](h: var History[M], state: M, actionName: string = "") =
  ## Take a snapshot of current state
  # If we're not at the end, truncate forward history
  if h.currentIdx >= 0 and h.currentIdx < h.entries.len - 1:
    h.entries.setLen(h.currentIdx + 1)
  
  let entry = HistoryEntry[M](
    state: state,
    timestamp: getTime().toUnix(),
    actionName: actionName
  )
  
  h.entries.add(entry)
  
  # Trim if over max
  if h.entries.len > h.maxEntries:
    h.entries.delete(0)
  
  h.currentIdx = h.entries.len - 1

proc hasNext*[M](h: History[M]): bool =
  ## Check if there's forward history
  h.currentIdx < h.entries.len - 1

proc hasPrev*[M](h: History[M]): bool =
  ## Check if there's backward history
  h.currentIdx > 0

proc travel*[M](h: var History[M], idx: int): Option[M] =
  ## Travel to specific history index
  if idx >= 0 and idx < h.entries.len:
    h.currentIdx = idx
    some(h.entries[idx].state)
  else:
    none(M)

proc next*[M](h: var History[M]): Option[M] =
  ## Move forward in history
  if h.hasNext:
    h.currentIdx += 1
    some(h.entries[h.currentIdx].state)
  else:
    none(M)

proc prev*[M](h: var History[M]): Option[M] =
  ## Move backward in history
  if h.hasPrev:
    h.currentIdx -= 1
    some(h.entries[h.currentIdx].state)
  else:
    none(M)

proc last*[M](h: var History[M]): Option[M] =
  ## Go to end of history
  if h.entries.len > 0:
    h.currentIdx = h.entries.len - 1
    some(h.entries[h.currentIdx].state)
  else:
    none(M)

proc first*[M](h: var History[M]): Option[M] =
  ## Go to beginning of history
  if h.entries.len > 0:
    h.currentIdx = 0
    some(h.entries[0].state)
  else:
    none(M)

proc reset*[M](h: var History[M]) =
  ## Reset history, keeping only first entry if present
  if h.entries.len > 0:
    let firstEntry = h.entries[0]
    h.entries = @[firstEntry]
    h.currentIdx = 0
  else:
    h.entries = @[]
    h.currentIdx = -1
