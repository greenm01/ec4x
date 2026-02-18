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
  # ActionKind Enum
  # ============================================================================

  ActionKind* {.pure.} = enum
    quit
    quitConfirm
    quitCancel
    quitToggle
    navigateMode
    switchView
    breadcrumbBack
    moveCursor
    select
    deselect
    listUp
    listDown
    listPageUp
    listPageDown
    endTurn
    scroll
    jumpHome
    cycleColony
    resize
    exportMap
    openMap
    enterExpertMode
    exitExpertMode
    expertInputAppend
    expertInputBackspace
    expertHistoryPrev
    expertHistoryNext
    expertSubmit
    submitTurn
    toggleHelpOverlay
    toggleFleetSelect
    switchFleetView
    fleetSortToggle
    fleetDigitJump
    intelDigitJump
    colonyDigitJump
    fleetBatchCommand
    fleetBatchROE
    fleetBatchZeroTurn
    joinRefresh
    joinSelect
    joinEditPubkey
    joinEditName
    joinBackspace
    joinSubmit
    joinPoll
    lobbySwitchPane
    lobbyEnterGame
    lobbyEditPubkey
    lobbyEditName
    lobbyGenerateKey
    lobbyJoinRefresh
    lobbyJoinSubmit
    lobbyJoinPoll
    lobbyBackspace
    lobbyCursorLeft
    lobbyCursorRight
    lobbyReturn
    lobbyInputAppend
    startOrderMove
    startOrderPatrol
    startOrderHold
    confirmOrder
    cancelOrder
    entryUp
    entryDown
    entrySelect
    entryImport
    entryImportConfirm
    entryImportCancel
    entryImportAppend
    entryImportBackspace
    entryInviteAppend
    entryInviteBackspace
    entryInviteSubmit
    entryAdminSelect
    entryAdminCreateGame
    entryAdminManageGames
    entryRelayEdit
    entryRelayAppend
    entryRelayBackspace
    entryCursorLeft
    entryCursorRight
    entryRelayConfirm
    createGameUp
    createGameDown
    createGameLeft
    createGameRight
    createGameAppend
    createGameBackspace
    createGameConfirm
    createGameCancel
    manageGamesCancel
    openBuildModal
    closeBuildModal
    toggleAutoRepair
    toggleAutoLoadMarines
    toggleAutoLoadFighters
    buildCategorySwitch
    buildCategoryPrev
    buildListUp
    buildListDown
    buildListPageUp
    buildListPageDown
    buildQueueUp
    buildQueueDown
    buildFocusSwitch
    buildAddToQueue
    buildRemoveFromQueue
    buildConfirmQueue
    buildQtyInc
    buildQtyDec
    openQueueModal
    closeQueueModal
    queueListUp
    queueListDown
    queueListPageUp
    queueListPageDown
    queueDelete
    fleetConsoleNextPane
    fleetConsolePrevPane
    openFleetDetailModal
    closeFleetDetailModal
    fleetDetailNextCategory
    fleetDetailPrevCategory
    fleetDetailListUp
    fleetDetailListDown
    fleetDetailSelectCommand
    fleetDetailOpenROE
    fleetDetailCloseROE
    fleetDetailROEUp
    fleetDetailROEDown
    fleetDetailSelectROE
    fleetDetailConfirm
    fleetDetailCancel
    fleetDetailPageUp
    fleetDetailPageDown
    fleetDetailDigitInput
    fleetDetailOpenZTC
    fleetDetailSelectZTC
    intelEditNote
    intelNoteAppend
    intelNoteBackspace
    intelNoteCursorLeft
    intelNoteCursorRight
    intelNoteCursorUp
    intelNoteCursorDown
    intelNoteInsertNewline
    intelNoteDelete
    intelNoteSave
    intelNoteCancel
    intelDetailNext
    intelDetailPrev
    intelFleetPopupClose
    messageFocusNext
    messageFocusPrev
    messageSelectHouse
    messageScrollUp
    messageScrollDown
    messageComposeToggle
    messageComposeAppend
    messageComposeBackspace
    messageComposeCursorLeft
    messageComposeCursorRight
    messageSend
    messageMarkRead
    inboxJumpMessages
    inboxJumpReports
    inboxExpandTurn
    inboxCollapseTurn
    inboxReportUp
    inboxReportDown
    researchAdjustInc
    researchAdjustDec
    researchAdjustFineInc
    researchAdjustFineDec
    researchClearAllocation
    researchDigitInput
    espionageFocusNext
    espionageFocusPrev
    espionageSelectEbp
    espionageSelectCip
    espionageBudgetAdjustInc
    espionageBudgetAdjustDec
    espionageQueueAdd
    espionageQueueDelete
    espionageClearBudget

  # ============================================================================
  # Core SAM Types
  # ============================================================================

  ProposalKind* {.pure.} = enum
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
    actionKind*: ActionKind     ## Enum-based action identifier
    case kind*: ProposalKind
    of ProposalKind.pkNone:
      discard
    of ProposalKind.pkError:
      errorMsg*: string
    of ProposalKind.pkNavigation:
      navMode*: int             ## ViewMode enum value
      navCursor*: tuple[q, r: int]  ## Hex coordinate for cursor
    of ProposalKind.pkSelection:
      selectIdx*: int           ## Index in current list
      selectCoord*: Option[tuple[q, r: int]]  ## Hex coordinate if applicable
    of ProposalKind.pkGameAction:
      gameActionData*: string   ## JSON-encoded action data
    of ProposalKind.pkViewportScroll:
      scrollDelta*: tuple[dx, dy: int]
    of ProposalKind.pkEndTurn:
      discard
    of ProposalKind.pkQuit:
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
    actionKind*: ActionKind
  
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
    allowedActions*: seq[ActionKind]
    disallowedActions*: seq[ActionKind]
    blockUnexpectedActions*: bool
    shouldRender*: bool
    lastError*: Option[string]

# ============================================================================
# ActionKind Conversion
# ============================================================================

proc actionKindToStr*(kind: ActionKind): string =
  $kind

# ============================================================================
# Proposal Constructors
# ============================================================================

proc emptyProposal*(): Proposal =
  ## Create an empty/no-op proposal
  Proposal(
    kind: ProposalKind.pkNone,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.navigateMode
  )

proc errorProposal*(msg: string): Proposal =
  ## Create an error proposal
  Proposal(
    kind: ProposalKind.pkError,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.navigateMode,
    errorMsg: msg
  )

proc navigationProposal*(mode: int): Proposal =
  ## Create a navigation mode change proposal
  Proposal(
    kind: ProposalKind.pkNavigation,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.navigateMode,
    navMode: mode,
    navCursor: (0, 0)
  )

proc cursorProposal*(q, r: int): Proposal =
  ## Create a cursor move proposal
  Proposal(
    kind: ProposalKind.pkNavigation,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.moveCursor,
    navMode: -1,
    navCursor: (q, r)
  )

proc selectionProposal*(idx: int): Proposal =
  ## Create a selection change proposal
  Proposal(
    kind: ProposalKind.pkSelection,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.select,
    selectIdx: idx,
    selectCoord: none(tuple[q, r: int])
  )

proc coordSelectionProposal*(q, r: int): Proposal =
  ## Create a coordinate selection proposal
  Proposal(
    kind: ProposalKind.pkSelection,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.select,
    selectIdx: -1,
    selectCoord: some((q, r))
  )

proc scrollProposal*(dx, dy: int): Proposal =
  ## Create a viewport scroll proposal
  Proposal(
    kind: ProposalKind.pkViewportScroll,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.scroll,
    scrollDelta: (dx, dy)
  )

proc endTurnProposal*(): Proposal =
  ## Create an end turn proposal
  Proposal(
    kind: ProposalKind.pkEndTurn,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.endTurn
  )

proc quitProposal*(): Proposal =
  ## Create a quit proposal
  Proposal(
    kind: ProposalKind.pkQuit,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.quit
  )

proc gameActionProposal*(actionKind: ActionKind, data: string): Proposal =
  ## Create a game action proposal
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: actionKind,
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

proc snap*[M](h: var History[M], state: M,
    actionKind: ActionKind = ActionKind.navigateMode) =
  ## Take a snapshot of current state
  # If we're not at the end, truncate forward history
  if h.currentIdx >= 0 and h.currentIdx < h.entries.len - 1:
    h.entries.setLen(h.currentIdx + 1)
  
  let entry = HistoryEntry[M](
    state: state,
    timestamp: getTime().toUnix(),
    actionKind: actionKind
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
