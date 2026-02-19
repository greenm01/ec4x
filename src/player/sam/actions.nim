## TUI Actions - Pure functions that create proposals
##
## Actions are the entry point for user input in the SAM pattern.
## They are pure functions that take event data and return proposals.
## Actions should NOT have side effects - they just compute intent.
##
## The action layer translates raw input (key events) into semantic proposals
## that the acceptors can process.
##
## NOTE: The main key mapping function `mapKeyToAction` has been moved to
## bindings.nim where it uses the binding registry as the single source of
## truth. This file still contains:
## - Proposal creation functions
## - KeyCode enum

import std/[options, times]
import ./types
import ./tui_model

export types, tui_model

# ============================================================================
# Navigation Actions
# ============================================================================

proc actionQuit*(): Proposal =
  ## Create quit action
  quitProposal()

proc actionQuitConfirm*(): Proposal =
  ## Confirm quit action
  gameActionProposal(ActionKind.quitConfirm, "")

proc actionQuitCancel*(): Proposal =
  ## Cancel quit action
  gameActionProposal(ActionKind.quitCancel, "")

proc actionQuitToggle*(): Proposal =
  ## Toggle quit confirmation selection
  gameActionProposal(ActionKind.quitToggle, "")

proc actionMessageComposeAppend*(ch: string): Proposal =
  ## Append a character to the message compose input
  gameActionProposal(ActionKind.messageComposeAppend, ch)

proc actionMessageComposeBackspace*(): Proposal =
  ## Backspace in message compose input
  gameActionProposal(ActionKind.messageComposeBackspace, "")

proc actionMessageComposeDelete*(): Proposal =
  ## Delete character at compose cursor
  gameActionProposal(ActionKind.messageComposeDelete, "")

proc actionMessageComposeCursorLeft*(): Proposal =
  ## Move compose cursor left
  gameActionProposal(ActionKind.messageComposeCursorLeft, "")

proc actionMessageComposeCursorRight*(): Proposal =
  ## Move compose cursor right
  gameActionProposal(ActionKind.messageComposeCursorRight, "")

proc actionMessageComposeToggle*(): Proposal =
  ## Toggle message compose mode
  gameActionProposal(ActionKind.messageComposeToggle, "")

proc actionMessageComposeStartWithChar*(ch: string): Proposal =
  ## Enter compose mode and seed first character from detail pane.
  gameActionProposal(ActionKind.messageComposeStartWithChar, ch)

proc actionMessageSend*(): Proposal =
  ## Send composed message
  gameActionProposal(ActionKind.messageSend, "")

proc actionMessageScrollUp*(): Proposal =
  ## Scroll message conversation up
  gameActionProposal(ActionKind.messageScrollUp, "")

proc actionMessageScrollDown*(): Proposal =
  ## Scroll message conversation down
  gameActionProposal(ActionKind.messageScrollDown, "")

proc actionMessageFocusNext*(): Proposal =
  ## Cycle message focus forward
  gameActionProposal(ActionKind.messageFocusNext, "")

proc actionMessageFocusPrev*(): Proposal =
  ## Cycle message focus backward
  gameActionProposal(ActionKind.messageFocusPrev, "")

proc actionMessageMarkRead*(): Proposal =
  ## Mark current thread as read
  gameActionProposal(ActionKind.messageMarkRead, "")

proc actionInboxJumpMessages*(): Proposal =
  ## Jump cursor to Messages section
  gameActionProposal(ActionKind.inboxJumpMessages, "")

proc actionInboxJumpReports*(): Proposal =
  ## Jump cursor to Reports section
  gameActionProposal(ActionKind.inboxJumpReports, "")

proc actionInboxExpandTurn*(): Proposal =
  ## Expand selected turn bucket to show reports
  gameActionProposal(ActionKind.inboxExpandTurn, "")

proc actionInboxCollapseTurn*(): Proposal =
  ## Collapse expanded turn bucket
  gameActionProposal(ActionKind.inboxCollapseTurn, "")

proc actionInboxReportUp*(): Proposal =
  ## Move up within expanded report list
  gameActionProposal(ActionKind.inboxReportUp, "")

proc actionInboxReportDown*(): Proposal =
  ## Move down within expanded report list
  gameActionProposal(ActionKind.inboxReportDown, "")

proc actionSwitchMode*(mode: ViewMode): Proposal =
  ## Switch to a different view mode (legacy)
  Proposal(
    kind: ProposalKind.pkNavigation,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.navigateMode,
    navMode: ord(mode),
    navCursor: (0, 0)  # Not used for mode switch
  )

proc actionSwitchView*(viewNum: int): Proposal =
  ## Switch to primary view (mapped from F-keys)
  ## This resets breadcrumbs to the primary view level
  Proposal(
    kind: ProposalKind.pkNavigation,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.switchView,
    navMode: viewNum,
    navCursor: (0, 0)
  )

proc actionBreadcrumbBack*(): Proposal =
  ## Navigate up the breadcrumb trail
  Proposal(
    kind: ProposalKind.pkNavigation,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.breadcrumbBack,
    navMode: 0,
    navCursor: (0, 0)
  )

proc actionMoveCursor*(dir: HexDirection): Proposal =
  ## Move map cursor in direction
  # We encode direction in navMode field (reused creatively)
  Proposal(
    kind: ProposalKind.pkNavigation,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.moveCursor,
    navMode: ord(dir),  # Direction encoded here
    navCursor: (0, 0)   # Will be computed by acceptor
  )

proc actionMoveCursorTo*(coord: HexCoord): Proposal =
  ## Move cursor directly to a coordinate
  Proposal(
    kind: ProposalKind.pkNavigation,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.moveCursor,
    navMode: -1,        # -1 means direct coordinate, not direction
    navCursor: coord
  )

proc actionJumpHome*(): Proposal =
  ## Jump cursor to homeworld
  Proposal(
    kind: ProposalKind.pkNavigation,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.jumpHome,
    navMode: -2,        # Special marker for jump home
    navCursor: (0, 0)   # Will be set by acceptor from model.homeworld
  )

# ============================================================================
# Selection Actions
# ============================================================================

proc actionSelect*(): Proposal =
  ## Select current item (cursor position in map, or list item)
  Proposal(
    kind: ProposalKind.pkSelection,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.select,
    selectIdx: -1,      # -1 means "use current"
    selectCoord: none(tuple[q, r: int])
  )

proc actionSelectIndex*(idx: int): Proposal =
  ## Select specific index in list
  Proposal(
    kind: ProposalKind.pkSelection,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.select,
    selectIdx: idx,
    selectCoord: none(tuple[q, r: int])
  )

proc actionSelectCoord*(coord: HexCoord): Proposal =
  ## Select specific coordinate on map
  Proposal(
    kind: ProposalKind.pkSelection,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.select,
    selectIdx: -1,
    selectCoord: some(coord)
  )

proc actionDeselect*(): Proposal =
  ## Clear selection
  Proposal(
    kind: ProposalKind.pkSelection,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.deselect,
    selectIdx: -2,      # -2 means deselect
    selectCoord: none(tuple[q, r: int])
  )

# ============================================================================
# List Navigation Actions
# ============================================================================

proc actionListUp*(): Proposal =
  ## Move selection up in list
  Proposal(
    kind: ProposalKind.pkSelection,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.listUp,
    selectIdx: -3,      # -3 means "move up"
    selectCoord: none(tuple[q, r: int])
  )

proc actionListDown*(): Proposal =
  ## Move selection down in list
  Proposal(
    kind: ProposalKind.pkSelection,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.listDown,
    selectIdx: -4,      # -4 means "move down"
    selectCoord: none(tuple[q, r: int])
  )

proc actionListPageUp*(): Proposal =
  ## Move selection up by page in list
  Proposal(
    kind: ProposalKind.pkSelection,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.listPageUp,
    selectIdx: -5,      # -5 means "page up"
    selectCoord: none(tuple[q, r: int])
  )

proc actionListPageDown*(): Proposal =
  ## Move selection down by page in list
  Proposal(
    kind: ProposalKind.pkSelection,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.listPageDown,
    selectIdx: -6,      # -6 means "page down"
    selectCoord: none(tuple[q, r: int])
  )

proc actionCycleColony*(reverse: bool = false): Proposal =
  ## Cycle to next/prev owned colony on map
  Proposal(
    kind: ProposalKind.pkNavigation,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.cycleColony,
    navMode: if reverse: 1 else: 0,
    navCursor: (0, 0)
  )

# ============================================================================
# Viewport Actions
# ============================================================================

proc actionScroll*(dx, dy: int): Proposal =
  ## Scroll viewport
  scrollProposal(dx, dy)

# ============================================================================
# Game Actions
# ============================================================================

proc actionEndTurn*(): Proposal =
  ## End the current turn
  endTurnProposal()

# ============================================================================
# Map Export Actions
# ============================================================================

proc actionExportMap*(): Proposal =
  ## Export SVG starmap to file
  gameActionProposal(ActionKind.exportMap, "")

proc actionOpenMap*(): Proposal =
  ## Export SVG starmap and open in viewer
  gameActionProposal(ActionKind.openMap, "")

# ============================================================================
# Expert Mode Actions
# ============================================================================

proc actionEnterExpertMode*(): Proposal =
  ## Enter expert mode (: prompt)
  gameActionProposal(ActionKind.enterExpertMode, "")

proc actionExitExpertMode*(): Proposal =
  ## Exit expert mode
  gameActionProposal(ActionKind.exitExpertMode, "")

proc actionExpertInputAppend*(value: string): Proposal =
  ## Append input to expert mode buffer
  gameActionProposal(ActionKind.expertInputAppend, value)

proc actionExpertInputBackspace*(): Proposal =
  ## Remove last character from expert mode buffer
  gameActionProposal(ActionKind.expertInputBackspace, "")

proc actionExpertCursorLeft*(): Proposal =
  ## Move expert mode cursor left
  gameActionProposal(ActionKind.expertCursorLeft, "")

proc actionExpertCursorRight*(): Proposal =
  ## Move expert mode cursor right
  gameActionProposal(ActionKind.expertCursorRight, "")

proc actionExpertSubmit*(): Proposal =
  ## Submit expert mode command
  gameActionProposal(ActionKind.expertSubmit, "")

proc actionExpertHistoryPrev*(): Proposal =
  ## Previous command from expert mode history
  gameActionProposal(ActionKind.expertHistoryPrev, "")

proc actionExpertHistoryNext*(): Proposal =
  ## Next command from expert mode history
  gameActionProposal(ActionKind.expertHistoryNext, "")

proc actionSubmitTurn*(): Proposal =
  ## Submit turn with all staged commands
  gameActionProposal(ActionKind.submitTurn, "")

proc actionToggleHelpOverlay*(): Proposal =
  ## Toggle help overlay
  gameActionProposal(ActionKind.toggleHelpOverlay, "")

# =============================================================================
# Research Actions
# =============================================================================

proc actionResearchAdjustInc*(): Proposal =
  ## Increase research allocation
  gameActionProposal(ActionKind.researchAdjustInc, "")

proc actionResearchAdjustDec*(): Proposal =
  ## Decrease research allocation
  gameActionProposal(ActionKind.researchAdjustDec, "")

proc actionResearchAdjustFineInc*(): Proposal =
  ## Increase research allocation (fine step)
  gameActionProposal(ActionKind.researchAdjustFineInc, "")

proc actionResearchAdjustFineDec*(): Proposal =
  ## Decrease research allocation (fine step)
  gameActionProposal(ActionKind.researchAdjustFineDec, "")

proc actionResearchClearAllocation*(): Proposal =
  ## Clear research allocation for selected item
  gameActionProposal(ActionKind.researchClearAllocation, "")

proc actionResearchDigitInput*(digit: char): Proposal =
  ## Append digit input for research allocation
  gameActionProposal(ActionKind.researchDigitInput, $digit)

# ============================================================================
# Espionage Actions
# ============================================================================

proc actionEspionageFocusNext*(): Proposal =
  gameActionProposal(ActionKind.espionageFocusNext, "")

proc actionEspionageFocusPrev*(): Proposal =
  gameActionProposal(ActionKind.espionageFocusPrev, "")

proc actionEspionageSelectEbp*(): Proposal =
  gameActionProposal(ActionKind.espionageSelectEbp, "")

proc actionEspionageSelectCip*(): Proposal =
  gameActionProposal(ActionKind.espionageSelectCip, "")

proc actionEspionageBudgetAdjustInc*(): Proposal =
  gameActionProposal(ActionKind.espionageBudgetAdjustInc, "")

proc actionEspionageBudgetAdjustDec*(): Proposal =
  gameActionProposal(ActionKind.espionageBudgetAdjustDec, "")

proc actionEspionageQueueAdd*(): Proposal =
  gameActionProposal(ActionKind.espionageQueueAdd, "")

proc actionEspionageQueueDelete*(): Proposal =
  gameActionProposal(ActionKind.espionageQueueDelete, "")

proc actionEspionageClearBudget*(): Proposal =
  gameActionProposal(ActionKind.espionageClearBudget, "")

# ============================================================================
# Fleet List Actions
# ============================================================================

proc actionFleetSortToggle*(): Proposal =
  ## Toggle fleet list sort direction (asc/desc)
  gameActionProposal(ActionKind.fleetSortToggle, "")

proc actionFleetDigitJump*(digit: char): Proposal =
  ## Jump to fleet by digit input
  gameActionProposal(ActionKind.fleetDigitJump, $digit)

proc actionIntelDigitJump*(digit: char): Proposal =
  ## Jump to intel system by digit input
  gameActionProposal(ActionKind.intelDigitJump, $digit)

proc actionColonyDigitJump*(digit: char): Proposal =
  ## Jump to colony by digit input
  gameActionProposal(ActionKind.colonyDigitJump, $digit)

proc actionFleetBatchCommand*(): Proposal =
  ## Open batch command picker for selected fleets
  gameActionProposal(ActionKind.fleetBatchCommand, "")

proc actionFleetBatchROE*(): Proposal =
  ## Open batch ROE picker for selected fleets
  gameActionProposal(ActionKind.fleetBatchROE, "")

proc actionFleetBatchZeroTurn*(): Proposal =
  ## Open batch zero-turn command picker for selected fleets
  gameActionProposal(ActionKind.fleetBatchZeroTurn, "")

proc actionFleetDetailOpenZTC*(): Proposal =
  ## Open ZTC picker from fleet detail modal
  gameActionProposal(ActionKind.fleetDetailOpenZTC, "")

proc actionFleetDetailSelectZTC*(): Proposal =
  ## Confirm ZTC selection in ZTC picker
  gameActionProposal(ActionKind.fleetDetailSelectZTC, "")

# ============================================================================
# Fleet Multi-Select Actions
# ============================================================================

proc actionToggleFleetSelect*(fleetId: int): Proposal =
  ## Toggle fleet selection for batch operations
  Proposal(
    kind: ProposalKind.pkSelection,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.toggleFleetSelect,
    selectIdx: fleetId,
    selectCoord: none(tuple[q, r: int])
  )

# ============================================================================
# Sub-View Navigation Actions
# ============================================================================

proc actionSwitchFleetView*(): Proposal =
  ## Toggle between fleet System View and List View
  Proposal(
    kind: ProposalKind.pkNavigation,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.switchFleetView,
    navMode: 0,
    navCursor: (0, 0)
  )


# ============================================================================
# Join Actions
# ============================================================================

proc actionJoinRefresh*(): Proposal =
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.joinRefresh,
    gameActionData: ""
  )

proc actionJoinSelect*(): Proposal =
  Proposal(
    kind: ProposalKind.pkSelection,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.joinSelect,
    selectIdx: -1,
    selectCoord: none(tuple[q, r: int])
  )

proc actionJoinEditPubkey*(): Proposal =
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.joinEditPubkey,
    gameActionData: ""
  )

proc actionJoinEditName*(): Proposal =
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.joinEditName,
    gameActionData: ""
  )

proc actionJoinBackspace*(): Proposal =
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.joinBackspace,
    gameActionData: ""
  )

proc actionJoinSubmit*(): Proposal =
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.joinSubmit,
    gameActionData: ""
  )

proc actionJoinPoll*(): Proposal =
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.joinPoll,
    gameActionData: ""
  )

# ============================================================================
# Lobby Actions
# ============================================================================

proc actionLobbySwitchPane*(pane: LobbyPane): Proposal =
  Proposal(
    kind: ProposalKind.pkNavigation,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.lobbySwitchPane,
    navMode: int(pane),
    navCursor: (0, 0)
  )

proc actionLobbyEnterGame*(): Proposal =
  Proposal(
    kind: ProposalKind.pkSelection,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.lobbyEnterGame,
    selectIdx: -1,
    selectCoord: none(tuple[q, r: int])
  )

proc actionLobbyEditPubkey*(): Proposal =
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.lobbyEditPubkey,
    gameActionData: ""
  )

proc actionLobbyEditName*(): Proposal =
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.lobbyEditName,
    gameActionData: ""
  )

proc actionLobbyGenerateKey*(): Proposal =
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.lobbyGenerateKey,
    gameActionData: ""
  )

proc actionLobbyJoinRefresh*(): Proposal =
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.lobbyJoinRefresh,
    gameActionData: ""
  )

proc actionLobbyJoinSubmit*(): Proposal =
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.lobbyJoinSubmit,
    gameActionData: ""
  )

proc actionLobbyJoinPoll*(): Proposal =
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.lobbyJoinPoll,
    gameActionData: ""
  )

proc actionLobbyBackspace*(): Proposal =
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.lobbyBackspace,
    gameActionData: ""
  )

proc actionLobbyDelete*(): Proposal =
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.lobbyDelete,
    gameActionData: ""
  )

proc actionLobbyCursorLeft*(): Proposal =
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.lobbyCursorLeft,
    gameActionData: ""
  )

proc actionLobbyCursorRight*(): Proposal =
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.lobbyCursorRight,
    gameActionData: ""
  )

proc actionLobbyInputAppend*(value: string): Proposal =
  ## Append character to lobby input (pubkey or name)
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.lobbyInputAppend,
    gameActionData: value
  )

proc actionLobbyReturn*(): Proposal =
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.lobbyReturn,
    gameActionData: ""
  )

# ============================================================================
# Entry Modal Actions
# ============================================================================

proc actionEntryUp*(): Proposal =
  ## Move selection up in entry modal
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.entryUp,
    gameActionData: ""
  )

proc actionEntryDown*(): Proposal =
  ## Move selection down in entry modal
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.entryDown,
    gameActionData: ""
  )

proc actionEntrySelect*(): Proposal =
  ## Select current game/lobby in entry modal
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.entrySelect,
    gameActionData: ""
  )

proc actionEntryImport*(): Proposal =
  ## Start nsec import in entry modal
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.entryImport,
    gameActionData: ""
  )

proc actionEntryImportConfirm*(): Proposal =
  ## Confirm nsec import
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.entryImportConfirm,
    gameActionData: ""
  )

proc actionEntryImportCancel*(): Proposal =
  ## Cancel nsec import
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.entryImportCancel,
    gameActionData: ""
  )

proc actionEntryImportAppend*(value: string): Proposal =
  ## Append character to import buffer
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.entryImportAppend,
    gameActionData: value
  )

proc actionEntryImportBackspace*(): Proposal =
  ## Backspace in import buffer
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.entryImportBackspace,
    gameActionData: ""
  )

proc actionEntryDelete*(): Proposal =
  ## Delete at cursor in entry text inputs
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.entryDelete,
    gameActionData: ""
  )

proc actionEntryInviteAppend*(value: string): Proposal =
  ## Append character to invite code
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.entryInviteAppend,
    gameActionData: value
  )

proc actionEntryInviteBackspace*(): Proposal =
  ## Backspace in invite code
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.entryInviteBackspace,
    gameActionData: ""
  )

proc actionEntryInviteSubmit*(): Proposal =
  ## Submit invite code to join game
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.entryInviteSubmit,
    gameActionData: ""
  )

proc actionEntryAdminSelect*(): Proposal =
  ## Select current admin menu item
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.entryAdminSelect,
    gameActionData: ""
  )

proc actionEntryAdminCreateGame*(): Proposal =
  ## Start creating a new game (admin only)
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.entryAdminCreateGame,
    gameActionData: ""
  )

proc actionEntryAdminManageGames*(): Proposal =
  ## Open manage games panel (admin only)
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.entryAdminManageGames,
    gameActionData: ""
  )

proc actionEntryRelayEdit*(): Proposal =
  ## Start editing relay URL
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.entryRelayEdit,
    gameActionData: ""
  )

proc actionEntryRelayAppend*(value: string): Proposal =
  ## Append character to relay URL
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.entryRelayAppend,
    gameActionData: value
  )

proc actionEntryRelayBackspace*(): Proposal =
  ## Backspace in relay URL
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.entryRelayBackspace,
    gameActionData: ""
  )

proc actionEntryCursorLeft*(): Proposal =
  ## Move cursor left in entry text input
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.entryCursorLeft,
    gameActionData: ""
  )

proc actionEntryCursorRight*(): Proposal =
  ## Move cursor right in entry text input
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.entryCursorRight,
    gameActionData: ""
  )

proc actionEntryRelayConfirm*(): Proposal =
  ## Confirm relay URL edit
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.entryRelayConfirm,
    gameActionData: ""
  )

# ============================================================================
# Game Creation Actions
# ============================================================================

proc actionCreateGameUp*(): Proposal =
  ## Move up in create game form
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.createGameUp,
    gameActionData: ""
  )

proc actionCreateGameDown*(): Proposal =
  ## Move down in create game form
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.createGameDown,
    gameActionData: ""
  )

proc actionCreateGameLeft*(): Proposal =
  ## Decrease value in create game form (player count)
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.createGameLeft,
    gameActionData: ""
  )

proc actionCreateGameRight*(): Proposal =
  ## Increase value in create game form (player count)
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.createGameRight,
    gameActionData: ""
  )

proc actionCreateGameAppend*(value: string): Proposal =
  ## Append character to game name
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.createGameAppend,
    gameActionData: value
  )

proc actionCreateGameBackspace*(): Proposal =
  ## Backspace in game name
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.createGameBackspace,
    gameActionData: ""
  )

proc actionCreateGameConfirm*(): Proposal =
  ## Confirm game creation
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.createGameConfirm,
    gameActionData: ""
  )

proc actionCreateGameCancel*(): Proposal =
  ## Cancel game creation
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.createGameCancel,
    gameActionData: ""
  )

proc actionManageGamesCancel*(): Proposal =
  ## Cancel manage games mode
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.manageGamesCancel,
    gameActionData: ""
  )

# ============================================================================
# Build Modal Actions
# ============================================================================

proc actionOpenBuildModal*(colonyId: int): Proposal =
  ## Open build modal for colony
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.openBuildModal,
    gameActionData: $colonyId
  )

proc actionToggleAutoRepair*(): Proposal =
  ## Toggle colony auto-repair (planet detail)
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.toggleAutoRepair,
    gameActionData: ""
  )

proc actionToggleAutoLoadMarines*(): Proposal =
  ## Toggle colony auto-load marines (planet detail)
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.toggleAutoLoadMarines,
    gameActionData: ""
  )

proc actionToggleAutoLoadFighters*(): Proposal =
  ## Toggle colony auto-load fighters (planet detail)
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.toggleAutoLoadFighters,
    gameActionData: ""
  )

proc actionCloseBuildModal*(): Proposal =
  ## Close build modal
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.closeBuildModal,
    gameActionData: ""
  )

proc actionBuildCategorySwitch*(): Proposal =
  ## Switch build category (Ships -> Facilities -> Ground -> Ships)
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.buildCategorySwitch,
    gameActionData: ""
  )

proc actionBuildCategoryPrev*(): Proposal =
  ## Switch build category in reverse direction
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.buildCategoryPrev,
    gameActionData: ""
  )

proc actionBuildListUp*(): Proposal =
  ## Navigate up in build list
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.buildListUp,
    gameActionData: ""
  )

proc actionBuildListDown*(): Proposal =
  ## Navigate down in build list
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.buildListDown,
    gameActionData: ""
  )

proc actionBuildListPageUp*(): Proposal =
  ## Page up in build list
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.buildListPageUp,
    gameActionData: ""
  )

proc actionBuildListPageDown*(): Proposal =
  ## Page down in build list
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.buildListPageDown,
    gameActionData: ""
  )

proc actionBuildQueueUp*(): Proposal =
  ## Navigate up in queue list
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.buildQueueUp,
    gameActionData: ""
  )

proc actionBuildQueueDown*(): Proposal =
  ## Navigate down in queue list
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.buildQueueDown,
    gameActionData: ""
  )

proc actionBuildFocusSwitch*(): Proposal =
  ## Switch focus between build list and queue list
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.buildFocusSwitch,
    gameActionData: ""
  )

proc actionBuildAddToQueue*(): Proposal =
  ## Add selected item to queue
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.buildAddToQueue,
    gameActionData: ""
  )

proc actionBuildRemoveFromQueue*(): Proposal =
  ## Remove selected item from queue
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.buildRemoveFromQueue,
    gameActionData: ""
  )

proc actionBuildConfirmQueue*(): Proposal =
  ## Confirm queue and stage build commands
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.buildConfirmQueue,
    gameActionData: ""
  )

proc actionBuildQtyInc*(): Proposal =
  ## Increase build quantity for selected row
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.buildQtyInc,
    gameActionData: ""
  )

proc actionBuildQtyDec*(): Proposal =
  ## Decrease build quantity for selected row
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.buildQtyDec,
    gameActionData: ""
  )

proc actionOpenQueueModal*(): Proposal =
  ## Open queue modal for selected colony
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.openQueueModal,
    gameActionData: ""
  )

proc actionCloseQueueModal*(): Proposal =
  ## Close queue modal
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.closeQueueModal,
    gameActionData: ""
  )

proc actionQueueListUp*(): Proposal =
  ## Move selection up in queue modal
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.queueListUp,
    gameActionData: ""
  )

proc actionQueueListDown*(): Proposal =
  ## Move selection down in queue modal
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.queueListDown,
    gameActionData: ""
  )

proc actionQueueListPageUp*(): Proposal =
  ## Page up in queue modal
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.queueListPageUp,
    gameActionData: ""
  )

proc actionQueueListPageDown*(): Proposal =
  ## Page down in queue modal
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.queueListPageDown,
    gameActionData: ""
  )

proc actionQueueDelete*(): Proposal =
  ## Delete queued item (decrement staged quantity)
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.queueDelete,
    gameActionData: ""
  )

# ============================================================================
# Order Entry Actions
# ============================================================================

proc actionStartOrderMove*(fleetId: int): Proposal =
  ## Start order entry for Move command
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.startOrderMove,
    gameActionData: $fleetId
  )

proc actionStartOrderPatrol*(fleetId: int): Proposal =
  ## Start order entry for Patrol command
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.startOrderPatrol,
    gameActionData: $fleetId
  )

proc actionStartOrderHold*(fleetId: int): Proposal =
  ## Start order entry for Hold command (immediate, no target)
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.startOrderHold,
    gameActionData: $fleetId
  )

proc actionConfirmOrder*(targetSystemId: int): Proposal =
  ## Confirm order with target system
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.confirmOrder,
    gameActionData: $targetSystemId
  )

proc actionCancelOrder*(): Proposal =
  ## Cancel order entry
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.cancelOrder,
    gameActionData: ""
  )

# ============================================================================
# Fleet Console Actions
# ============================================================================

proc actionFleetConsoleNextPane*(): Proposal =
  ## Move focus to next pane in fleet console (SystemView mode)
  Proposal(
    kind: ProposalKind.pkNavigation,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.fleetConsoleNextPane,
    navMode: 0,  # Not used for pane switching
    navCursor: (0, 0)  # Not used for pane switching
  )

proc actionFleetConsolePrevPane*(): Proposal =
  ## Move focus to previous pane in fleet console (SystemView mode)
  Proposal(
    kind: ProposalKind.pkNavigation,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.fleetConsolePrevPane,
    navMode: 0,  # Not used for pane switching
    navCursor: (0, 0)  # Not used for pane switching
  )

# ============================================================================
# Fleet Detail Modal Actions
# ============================================================================

proc actionOpenFleetDetailModal*(): Proposal =
  ## Open fleet detail modal
  gameActionProposal(ActionKind.openFleetDetailModal, "")

proc actionCloseFleetDetailModal*(): Proposal =
  ## Close fleet detail modal
  gameActionProposal(ActionKind.closeFleetDetailModal, "")

proc actionFleetDetailNextCategory*(): Proposal =
  ## Navigate to next command category in fleet detail modal
  gameActionProposal(ActionKind.fleetDetailNextCategory, "")

proc actionFleetDetailPrevCategory*(): Proposal =
  ## Navigate to previous command category in fleet detail modal
  gameActionProposal(ActionKind.fleetDetailPrevCategory, "")

proc actionFleetDetailListUp*(): Proposal =
  ## Move selection up in fleet detail modal
  gameActionProposal(ActionKind.fleetDetailListUp, "")

proc actionFleetDetailListDown*(): Proposal =
  ## Move selection down in fleet detail modal
  gameActionProposal(ActionKind.fleetDetailListDown, "")

proc actionFleetDetailSelectCommand*(): Proposal =
  ## Select command in fleet detail modal
  gameActionProposal(ActionKind.fleetDetailSelectCommand, "")

proc actionFleetDetailOpenROE*(): Proposal =
  ## Open ROE picker in fleet detail modal
  gameActionProposal(ActionKind.fleetDetailOpenROE, "")

proc actionFleetDetailCloseROE*(): Proposal =
  ## Close ROE picker in fleet detail modal
  gameActionProposal(ActionKind.fleetDetailCloseROE, "")

proc actionFleetDetailROEUp*(): Proposal =
  ## Increase ROE value in fleet detail modal
  gameActionProposal(ActionKind.fleetDetailROEUp, "")

proc actionFleetDetailROEDown*(): Proposal =
  ## Decrease ROE value in fleet detail modal
  gameActionProposal(ActionKind.fleetDetailROEDown, "")

proc actionFleetDetailSelectROE*(): Proposal =
  ## Confirm ROE selection in fleet detail modal
  gameActionProposal(ActionKind.fleetDetailSelectROE, "")

proc actionFleetDetailConfirm*(): Proposal =
  ## Confirm action in fleet detail modal
  gameActionProposal(ActionKind.fleetDetailConfirm, "")

proc actionFleetDetailCancel*(): Proposal =
  ## Cancel action in fleet detail modal
  gameActionProposal(ActionKind.fleetDetailCancel, "")

proc actionFleetDetailPageUp*(): Proposal =
  ## Page up in fleet detail ship list
  gameActionProposal(ActionKind.fleetDetailPageUp, "")

proc actionFleetDetailPageDown*(): Proposal =
  ## Page down in fleet detail ship list
  gameActionProposal(ActionKind.fleetDetailPageDown, "")

proc actionFleetDetailDigitInput*(digit: char): Proposal =
  ## Handle digit input for quick command selection (00-19)
  gameActionProposal(ActionKind.fleetDetailDigitInput, $digit)

# ============================================================================
# Intel Actions
# ============================================================================

proc actionIntelEditNote*(): Proposal =
  ## Start note edit for selected intel system
  gameActionProposal(ActionKind.intelEditNote, "")

proc actionIntelNoteAppend*(value: string): Proposal =
  ## Append text to intel note input
  gameActionProposal(ActionKind.intelNoteAppend, value)

proc actionIntelNoteBackspace*(): Proposal =
  ## Backspace in intel note input
  gameActionProposal(ActionKind.intelNoteBackspace, "")

proc actionIntelNoteCursorLeft*(): Proposal =
  ## Move intel note cursor left
  gameActionProposal(ActionKind.intelNoteCursorLeft, "")

proc actionIntelNoteCursorRight*(): Proposal =
  ## Move intel note cursor right
  gameActionProposal(ActionKind.intelNoteCursorRight, "")

proc actionIntelNoteCursorUp*(): Proposal =
  ## Move intel note cursor up
  gameActionProposal(ActionKind.intelNoteCursorUp, "")

proc actionIntelNoteCursorDown*(): Proposal =
  ## Move intel note cursor down
  gameActionProposal(ActionKind.intelNoteCursorDown, "")

proc actionIntelNoteInsertNewline*(): Proposal =
  ## Insert a newline in intel note input
  gameActionProposal(ActionKind.intelNoteInsertNewline, "")

proc actionIntelNoteDelete*(): Proposal =
  ## Delete character at cursor in intel note input
  gameActionProposal(ActionKind.intelNoteDelete, "")

proc actionIntelNoteSave*(): Proposal =
  ## Save edited intel note
  gameActionProposal(ActionKind.intelNoteSave, "")

proc actionIntelNoteCancel*(): Proposal =
  ## Cancel intel note edit
  gameActionProposal(ActionKind.intelNoteCancel, "")

proc actionIntelDetailNext*(): Proposal =
  ## Navigate to next intel system in detail view
  gameActionProposal(ActionKind.intelDetailNext, "")

proc actionIntelDetailPrev*(): Proposal =
  ## Navigate to previous intel system in detail view
  gameActionProposal(ActionKind.intelDetailPrev, "")

proc actionIntelFleetPopupClose*(): Proposal =
  ## Close intel fleet popup in intel detail view
  gameActionProposal(ActionKind.intelFleetPopupClose, "")

# ============================================================================
# System Actions
# ============================================================================

proc actionResize*(width, height: int): Proposal =
  ## Handle terminal resize
  result = Proposal(
    kind: ProposalKind.pkViewportScroll,  # Reuse for resize data
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.resize,
    scrollDelta: (width, height)  # Store new dimensions
  )

# ============================================================================
# Key Codes
# ============================================================================

type
  KeyCode* {.pure.} = enum
      ## Simplified key codes for mapping
      KeyNone
      # Number keys for view switching and quick entry
      Key0, Key1, Key2, Key3, Key4, Key5, Key6, Key7, Key8, Key9
      # Letter keys
      KeyQ, KeyC, KeyF, KeyO, KeyM, KeyE, KeyH, KeyX, KeyS, KeyL
      KeyB, KeyG, KeyR, KeyJ, KeyK, KeyD, KeyP, KeyV, KeyN, KeyW, KeyI, KeyT
      KeyA, KeyY, KeyU, KeyZ
      KeyPlus, KeyMinus
      # Navigation
      KeyUp, KeyDown, KeyLeft, KeyRight
      KeyEnter, KeyEscape, KeyTab, KeyShiftTab
      KeyHome, KeyBackspace, KeyDelete
      KeyPageUp, KeyPageDown
      KeyF1, KeyF2, KeyF3, KeyF4, KeyF5, KeyF6
      KeyF7, KeyF8, KeyF9, KeyF10, KeyF11, KeyF12
      # Special
      KeyColon  # Expert mode trigger
      KeySlash
      KeyCtrlL
