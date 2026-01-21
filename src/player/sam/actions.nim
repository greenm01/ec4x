## TUI Actions - Pure functions that create proposals
##
## Actions are the entry point for user input in the SAM pattern.
## They are pure functions that take event data and return proposals.
## Actions should NOT have side effects - they just compute intent.
##
## The action layer translates raw input (key events) into semantic proposals
## that the acceptors can process.

import std/[options, times]
import ./types
import ./tui_model

export types, tui_model

# ============================================================================
# Action Names (for allowed/disallowed filtering)
# ============================================================================

const
  ActionQuit* = "quit"
  ActionQuitConfirm* = "quitConfirm"
  ActionQuitCancel* = "quitCancel"
  ActionNavigateMode* = "navigateMode"
  ActionSwitchView* = "switchView"       ## Switch to primary view [1-9]
  ActionBreadcrumbBack* = "breadcrumbBack"  ## Navigate up breadcrumb
  ActionMoveCursor* = "moveCursor"
  ActionSelect* = "select"
  ActionDeselect* = "deselect"
  ActionListUp* = "listUp"
  ActionListDown* = "listDown"
  ActionEndTurn* = "endTurn"
  ActionScroll* = "scroll"
  ActionJumpHome* = "jumpHome"
  ActionCycleColony* = "cycleColony"
  ActionResize* = "resize"
  ActionExportMap* = "exportMap"
  ActionOpenMap* = "openMap"
  ActionEnterExpertMode* = "enterExpertMode"
  ActionExitExpertMode* = "exitExpertMode"
  ActionExpertInputAppend* = "expertInputAppend"
  ActionExpertInputBackspace* = "expertInputBackspace"
  ActionExpertHistoryPrev* = "expertHistoryPrev"
  ActionExpertHistoryNext* = "expertHistoryNext"
  ActionExpertSubmit* = "expertSubmit"
  ActionSubmitTurn* = "submitTurn"
  ActionToggleFleetSelect* = "toggleFleetSelect"
  ActionSwitchPlanetTab* = "switchPlanetTab"
  ActionSwitchFleetView* = "switchFleetView"
  ActionCycleReportFilter* = "cycleReportFilter"
  ActionReportFocusNext* = "reportFocusNext"
  ActionReportFocusPrev* = "reportFocusPrev"
  ActionReportFocusLeft* = "reportFocusLeft"
  ActionReportFocusRight* = "reportFocusRight"
  ActionJoinRefresh* = "joinRefresh"
  ActionJoinSelect* = "joinSelect"
  ActionJoinEditPubkey* = "joinEditPubkey"
  ActionJoinEditName* = "joinEditName"
  ActionJoinBackspace* = "joinBackspace"
  ActionJoinSubmit* = "joinSubmit"
  ActionJoinPoll* = "joinPoll"
  ActionLobbySwitchPane* = "lobbySwitchPane"
  ActionLobbyEnterGame* = "lobbyEnterGame"
  ActionLobbyEditPubkey* = "lobbyEditPubkey"
  ActionLobbyEditName* = "lobbyEditName"
  ActionLobbyGenerateKey* = "lobbyGenerateKey"
  ActionLobbyJoinRefresh* = "lobbyJoinRefresh"
  ActionLobbyJoinSubmit* = "lobbyJoinSubmit"
  ActionLobbyJoinPoll* = "lobbyJoinPoll"
  ActionLobbyBackspace* = "lobbyBackspace"
  ActionLobbyReturn* = "lobbyReturn"
  ActionLobbyInputAppend* = "lobbyInputAppend"
  # Order entry actions
  ActionStartOrderMove* = "startOrderMove"
  ActionStartOrderPatrol* = "startOrderPatrol"
  ActionStartOrderHold* = "startOrderHold"
  ActionConfirmOrder* = "confirmOrder"
  ActionCancelOrder* = "cancelOrder"
  # Entry modal actions
  ActionEntryUp* = "entryUp"
  ActionEntryDown* = "entryDown"
  ActionEntrySelect* = "entrySelect"
  ActionEntryImport* = "entryImport"
  ActionEntryImportConfirm* = "entryImportConfirm"
  ActionEntryImportCancel* = "entryImportCancel"
  ActionEntryImportAppend* = "entryImportAppend"
  ActionEntryImportBackspace* = "entryImportBackspace"
  ActionEntryInviteAppend* = "entryInviteAppend"
  ActionEntryInviteBackspace* = "entryInviteBackspace"
  ActionEntryInviteSubmit* = "entryInviteSubmit"
  # Admin actions
  ActionEntryAdminSelect* = "entryAdminSelect"
  ActionEntryAdminCreateGame* = "entryAdminCreateGame"
  ActionEntryAdminManageGames* = "entryAdminManageGames"
  # Relay URL actions
  ActionEntryRelayEdit* = "entryRelayEdit"
  ActionEntryRelayAppend* = "entryRelayAppend"
  ActionEntryRelayBackspace* = "entryRelayBackspace"
  ActionEntryRelayConfirm* = "entryRelayConfirm"
  # Game creation actions
  ActionCreateGameUp* = "createGameUp"
  ActionCreateGameDown* = "createGameDown"
  ActionCreateGameLeft* = "createGameLeft"
  ActionCreateGameRight* = "createGameRight"
  ActionCreateGameAppend* = "createGameAppend"
  ActionCreateGameBackspace* = "createGameBackspace"
  ActionCreateGameConfirm* = "createGameConfirm"
  ActionCreateGameCancel* = "createGameCancel"
  # Manage games actions
  ActionManageGamesCancel* = "manageGamesCancel"

# ============================================================================
# Navigation Actions
# ============================================================================

proc actionQuit*(): Proposal =
  ## Create quit action
  quitProposal()

proc actionQuitConfirm*(): Proposal =
  ## Confirm quit action
  gameActionProposal(ActionQuitConfirm, "")

proc actionQuitCancel*(): Proposal =
  ## Cancel quit action
  gameActionProposal(ActionQuitCancel, "")

proc actionSwitchMode*(mode: ViewMode): Proposal =
  ## Switch to a different view mode (legacy)
  Proposal(
    kind: ProposalKind.pkNavigation,
    timestamp: getTime().toUnix(),
    actionName: ActionNavigateMode,
    navMode: ord(mode),
    navCursor: (0, 0)  # Not used for mode switch
  )

proc actionSwitchView*(viewNum: int): Proposal =
  ## Switch to primary view by number [1-9]
  ## This resets breadcrumbs to the primary view level
  Proposal(
    kind: ProposalKind.pkNavigation,
    timestamp: getTime().toUnix(),
    actionName: ActionSwitchView,
    navMode: viewNum,
    navCursor: (0, 0)
  )

proc actionBreadcrumbBack*(): Proposal =
  ## Navigate up the breadcrumb trail
  Proposal(
    kind: ProposalKind.pkNavigation,
    timestamp: getTime().toUnix(),
    actionName: ActionBreadcrumbBack,
    navMode: 0,
    navCursor: (0, 0)
  )

proc actionMoveCursor*(dir: HexDirection): Proposal =
  ## Move map cursor in direction
  # We encode direction in navMode field (reused creatively)
  Proposal(
    kind: ProposalKind.pkNavigation,
    timestamp: getTime().toUnix(),
    actionName: ActionMoveCursor,
    navMode: ord(dir),  # Direction encoded here
    navCursor: (0, 0)   # Will be computed by acceptor
  )

proc actionMoveCursorTo*(coord: HexCoord): Proposal =
  ## Move cursor directly to a coordinate
  Proposal(
    kind: ProposalKind.pkNavigation,
    timestamp: getTime().toUnix(),
    actionName: ActionMoveCursor,
    navMode: -1,        # -1 means direct coordinate, not direction
    navCursor: coord
  )

proc actionJumpHome*(): Proposal =
  ## Jump cursor to homeworld
  Proposal(
    kind: ProposalKind.pkNavigation,
    timestamp: getTime().toUnix(),
    actionName: ActionJumpHome,
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
    actionName: ActionSelect,
    selectIdx: -1,      # -1 means "use current"
    selectCoord: none(tuple[q, r: int])
  )

proc actionSelectIndex*(idx: int): Proposal =
  ## Select specific index in list
  Proposal(
    kind: ProposalKind.pkSelection,
    timestamp: getTime().toUnix(),
    actionName: ActionSelect,
    selectIdx: idx,
    selectCoord: none(tuple[q, r: int])
  )

proc actionSelectCoord*(coord: HexCoord): Proposal =
  ## Select specific coordinate on map
  Proposal(
    kind: ProposalKind.pkSelection,
    timestamp: getTime().toUnix(),
    actionName: ActionSelect,
    selectIdx: -1,
    selectCoord: some(coord)
  )

proc actionDeselect*(): Proposal =
  ## Clear selection
  Proposal(
    kind: ProposalKind.pkSelection,
    timestamp: getTime().toUnix(),
    actionName: ActionDeselect,
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
    actionName: ActionListUp,
    selectIdx: -3,      # -3 means "move up"
    selectCoord: none(tuple[q, r: int])
  )

proc actionListDown*(): Proposal =
  ## Move selection down in list
  Proposal(
    kind: ProposalKind.pkSelection,
    timestamp: getTime().toUnix(),
    actionName: ActionListDown,
    selectIdx: -4,      # -4 means "move down"
    selectCoord: none(tuple[q, r: int])
  )

proc actionCycleColony*(reverse: bool = false): Proposal =
  ## Cycle to next/prev owned colony on map
  Proposal(
    kind: ProposalKind.pkNavigation,
    timestamp: getTime().toUnix(),
    actionName: ActionCycleColony,
    navMode: if reverse: 1 else: 0,
    navCursor: (0, 0)
  )

# ============================================================================
# Viewport Actions
# ============================================================================

proc actionScroll*(dx, dy: int): Proposal =
  ## Scroll viewport
  scrollProposal(dx, dy, ActionScroll)

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
  gameActionProposal(ActionExportMap, "")

proc actionOpenMap*(): Proposal =
  ## Export SVG starmap and open in viewer
  gameActionProposal(ActionOpenMap, "")

# ============================================================================
# Expert Mode Actions
# ============================================================================

proc actionEnterExpertMode*(): Proposal =
  ## Enter expert mode (: prompt)
  gameActionProposal(ActionEnterExpertMode, "")

proc actionExitExpertMode*(): Proposal =
  ## Exit expert mode
  gameActionProposal(ActionExitExpertMode, "")

proc actionExpertInputAppend*(value: string): Proposal =
  ## Append input to expert mode buffer
  gameActionProposal(ActionExpertInputAppend, value)

proc actionExpertInputBackspace*(): Proposal =
  ## Remove last character from expert mode buffer
  gameActionProposal(ActionExpertInputBackspace, "")

proc actionExpertSubmit*(): Proposal =
  ## Submit expert mode command
  gameActionProposal(ActionExpertSubmit, "")

proc actionExpertHistoryPrev*(): Proposal =
  ## Previous command from expert mode history
  gameActionProposal(ActionExpertHistoryPrev, "")

proc actionExpertHistoryNext*(): Proposal =
  ## Next command from expert mode history
  gameActionProposal(ActionExpertHistoryNext, "")

proc actionSubmitTurn*(): Proposal =
  ## Submit turn with all staged commands
  gameActionProposal(ActionSubmitTurn, "")

# ============================================================================
# Fleet Multi-Select Actions
# ============================================================================

proc actionToggleFleetSelect*(fleetId: int): Proposal =
  ## Toggle fleet selection for batch operations
  Proposal(
    kind: ProposalKind.pkSelection,
    timestamp: getTime().toUnix(),
    actionName: ActionToggleFleetSelect,
    selectIdx: fleetId,
    selectCoord: none(tuple[q, r: int])
  )

# ============================================================================
# Sub-View Navigation Actions
# ============================================================================

proc actionSwitchPlanetTab*(tab: int): Proposal =
  ## Switch planet detail tab (1-5)
  Proposal(
    kind: ProposalKind.pkNavigation,
    timestamp: getTime().toUnix(),
    actionName: ActionSwitchPlanetTab,
    navMode: tab,
    navCursor: (0, 0)
  )

proc actionSwitchFleetView*(): Proposal =
  ## Toggle between fleet System View and List View
  Proposal(
    kind: ProposalKind.pkNavigation,
    timestamp: getTime().toUnix(),
    actionName: ActionSwitchFleetView,
    navMode: 0,
    navCursor: (0, 0)
  )

proc actionCycleReportFilter*(): Proposal =
  ## Cycle the Reports view filter
  Proposal(
    kind: ProposalKind.pkNavigation,
    timestamp: getTime().toUnix(),
    actionName: ActionCycleReportFilter,
    navMode: 0,
    navCursor: (0, 0)
  )

proc actionReportFocusNext*(): Proposal =
  ## Cycle report focus forward
  Proposal(
    kind: ProposalKind.pkNavigation,
    timestamp: getTime().toUnix(),
    actionName: ActionReportFocusNext,
    navMode: 0,
    navCursor: (0, 0)
  )

proc actionReportFocusPrev*(): Proposal =
  ## Cycle report focus backward
  Proposal(
    kind: ProposalKind.pkNavigation,
    timestamp: getTime().toUnix(),
    actionName: ActionReportFocusPrev,
    navMode: 0,
    navCursor: (0, 0)
  )

proc actionReportFocusLeft*(): Proposal =
  ## Move report focus left
  Proposal(
    kind: ProposalKind.pkNavigation,
    timestamp: getTime().toUnix(),
    actionName: ActionReportFocusLeft,
    navMode: 0,
    navCursor: (0, 0)
  )

proc actionReportFocusRight*(): Proposal =
  ## Move report focus right
  Proposal(
    kind: ProposalKind.pkNavigation,
    timestamp: getTime().toUnix(),
    actionName: ActionReportFocusRight,
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
    actionName: ActionJoinRefresh,
    gameActionType: ActionJoinRefresh,
    gameActionData: ""
  )

proc actionJoinSelect*(): Proposal =
  Proposal(
    kind: ProposalKind.pkSelection,
    timestamp: getTime().toUnix(),
    actionName: ActionJoinSelect,
    selectIdx: -1,
    selectCoord: none(tuple[q, r: int])
  )

proc actionJoinEditPubkey*(): Proposal =
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionName: ActionJoinEditPubkey,
    gameActionType: ActionJoinEditPubkey,
    gameActionData: ""
  )

proc actionJoinEditName*(): Proposal =
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionName: ActionJoinEditName,
    gameActionType: ActionJoinEditName,
    gameActionData: ""
  )

proc actionJoinBackspace*(): Proposal =
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionName: ActionJoinBackspace,
    gameActionType: ActionJoinBackspace,
    gameActionData: ""
  )

proc actionJoinSubmit*(): Proposal =
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionName: ActionJoinSubmit,
    gameActionType: ActionJoinSubmit,
    gameActionData: ""
  )

proc actionJoinPoll*(): Proposal =
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionName: ActionJoinPoll,
    gameActionType: ActionJoinPoll,
    gameActionData: ""
  )

# ============================================================================
# Lobby Actions
# ============================================================================

proc actionLobbySwitchPane*(pane: LobbyPane): Proposal =
  Proposal(
    kind: ProposalKind.pkNavigation,
    timestamp: getTime().toUnix(),
    actionName: ActionLobbySwitchPane,
    navMode: int(pane),
    navCursor: (0, 0)
  )

proc actionLobbyEnterGame*(): Proposal =
  Proposal(
    kind: ProposalKind.pkSelection,
    timestamp: getTime().toUnix(),
    actionName: ActionLobbyEnterGame,
    selectIdx: -1,
    selectCoord: none(tuple[q, r: int])
  )

proc actionLobbyEditPubkey*(): Proposal =
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionName: ActionLobbyEditPubkey,
    gameActionType: ActionLobbyEditPubkey,
    gameActionData: ""
  )

proc actionLobbyEditName*(): Proposal =
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionName: ActionLobbyEditName,
    gameActionType: ActionLobbyEditName,
    gameActionData: ""
  )

proc actionLobbyGenerateKey*(): Proposal =
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionName: ActionLobbyGenerateKey,
    gameActionType: ActionLobbyGenerateKey,
    gameActionData: ""
  )

proc actionLobbyJoinRefresh*(): Proposal =
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionName: ActionLobbyJoinRefresh,
    gameActionType: ActionLobbyJoinRefresh,
    gameActionData: ""
  )

proc actionLobbyJoinSubmit*(): Proposal =
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionName: ActionLobbyJoinSubmit,
    gameActionType: ActionLobbyJoinSubmit,
    gameActionData: ""
  )

proc actionLobbyJoinPoll*(): Proposal =
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionName: ActionLobbyJoinPoll,
    gameActionType: ActionLobbyJoinPoll,
    gameActionData: ""
  )

proc actionLobbyBackspace*(): Proposal =
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionName: ActionLobbyBackspace,
    gameActionType: ActionLobbyBackspace,
    gameActionData: ""
  )

proc actionLobbyInputAppend*(value: string): Proposal =
  ## Append character to lobby input (pubkey or name)
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionName: ActionLobbyInputAppend,
    gameActionType: ActionLobbyInputAppend,
    gameActionData: value
  )

proc actionLobbyReturn*(): Proposal =
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionName: ActionLobbyReturn,
    gameActionType: ActionLobbyReturn,
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
    actionName: ActionEntryUp,
    gameActionType: ActionEntryUp,
    gameActionData: ""
  )

proc actionEntryDown*(): Proposal =
  ## Move selection down in entry modal
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionName: ActionEntryDown,
    gameActionType: ActionEntryDown,
    gameActionData: ""
  )

proc actionEntrySelect*(): Proposal =
  ## Select current game/lobby in entry modal
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionName: ActionEntrySelect,
    gameActionType: ActionEntrySelect,
    gameActionData: ""
  )

proc actionEntryImport*(): Proposal =
  ## Start nsec import in entry modal
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionName: ActionEntryImport,
    gameActionType: ActionEntryImport,
    gameActionData: ""
  )

proc actionEntryImportConfirm*(): Proposal =
  ## Confirm nsec import
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionName: ActionEntryImportConfirm,
    gameActionType: ActionEntryImportConfirm,
    gameActionData: ""
  )

proc actionEntryImportCancel*(): Proposal =
  ## Cancel nsec import
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionName: ActionEntryImportCancel,
    gameActionType: ActionEntryImportCancel,
    gameActionData: ""
  )

proc actionEntryImportAppend*(value: string): Proposal =
  ## Append character to import buffer
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionName: ActionEntryImportAppend,
    gameActionType: ActionEntryImportAppend,
    gameActionData: value
  )

proc actionEntryImportBackspace*(): Proposal =
  ## Backspace in import buffer
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionName: ActionEntryImportBackspace,
    gameActionType: ActionEntryImportBackspace,
    gameActionData: ""
  )

proc actionEntryInviteAppend*(value: string): Proposal =
  ## Append character to invite code
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionName: ActionEntryInviteAppend,
    gameActionType: ActionEntryInviteAppend,
    gameActionData: value
  )

proc actionEntryInviteBackspace*(): Proposal =
  ## Backspace in invite code
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionName: ActionEntryInviteBackspace,
    gameActionType: ActionEntryInviteBackspace,
    gameActionData: ""
  )

proc actionEntryInviteSubmit*(): Proposal =
  ## Submit invite code to join game
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionName: ActionEntryInviteSubmit,
    gameActionType: ActionEntryInviteSubmit,
    gameActionData: ""
  )

proc actionEntryAdminSelect*(): Proposal =
  ## Select current admin menu item
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionName: ActionEntryAdminSelect,
    gameActionType: ActionEntryAdminSelect,
    gameActionData: ""
  )

proc actionEntryAdminCreateGame*(): Proposal =
  ## Start creating a new game (admin only)
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionName: ActionEntryAdminCreateGame,
    gameActionType: ActionEntryAdminCreateGame,
    gameActionData: ""
  )

proc actionEntryAdminManageGames*(): Proposal =
  ## Open manage games panel (admin only)
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionName: ActionEntryAdminManageGames,
    gameActionType: ActionEntryAdminManageGames,
    gameActionData: ""
  )

proc actionEntryRelayEdit*(): Proposal =
  ## Start editing relay URL
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionName: ActionEntryRelayEdit,
    gameActionType: ActionEntryRelayEdit,
    gameActionData: ""
  )

proc actionEntryRelayAppend*(value: string): Proposal =
  ## Append character to relay URL
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionName: ActionEntryRelayAppend,
    gameActionType: ActionEntryRelayAppend,
    gameActionData: value
  )

proc actionEntryRelayBackspace*(): Proposal =
  ## Backspace in relay URL
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionName: ActionEntryRelayBackspace,
    gameActionType: ActionEntryRelayBackspace,
    gameActionData: ""
  )

proc actionEntryRelayConfirm*(): Proposal =
  ## Confirm relay URL edit
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionName: ActionEntryRelayConfirm,
    gameActionType: ActionEntryRelayConfirm,
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
    actionName: ActionCreateGameUp,
    gameActionType: ActionCreateGameUp,
    gameActionData: ""
  )

proc actionCreateGameDown*(): Proposal =
  ## Move down in create game form
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionName: ActionCreateGameDown,
    gameActionType: ActionCreateGameDown,
    gameActionData: ""
  )

proc actionCreateGameLeft*(): Proposal =
  ## Decrease value in create game form (player count)
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionName: ActionCreateGameLeft,
    gameActionType: ActionCreateGameLeft,
    gameActionData: ""
  )

proc actionCreateGameRight*(): Proposal =
  ## Increase value in create game form (player count)
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionName: ActionCreateGameRight,
    gameActionType: ActionCreateGameRight,
    gameActionData: ""
  )

proc actionCreateGameAppend*(value: string): Proposal =
  ## Append character to game name
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionName: ActionCreateGameAppend,
    gameActionType: ActionCreateGameAppend,
    gameActionData: value
  )

proc actionCreateGameBackspace*(): Proposal =
  ## Backspace in game name
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionName: ActionCreateGameBackspace,
    gameActionType: ActionCreateGameBackspace,
    gameActionData: ""
  )

proc actionCreateGameConfirm*(): Proposal =
  ## Confirm game creation
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionName: ActionCreateGameConfirm,
    gameActionType: ActionCreateGameConfirm,
    gameActionData: ""
  )

proc actionCreateGameCancel*(): Proposal =
  ## Cancel game creation
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionName: ActionCreateGameCancel,
    gameActionType: ActionCreateGameCancel,
    gameActionData: ""
  )

proc actionManageGamesCancel*(): Proposal =
  ## Cancel manage games mode
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionName: ActionManageGamesCancel,
    gameActionType: ActionManageGamesCancel,
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
    actionName: ActionStartOrderMove,
    gameActionType: ActionStartOrderMove,
    gameActionData: $fleetId
  )

proc actionStartOrderPatrol*(fleetId: int): Proposal =
  ## Start order entry for Patrol command
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionName: ActionStartOrderPatrol,
    gameActionType: ActionStartOrderPatrol,
    gameActionData: $fleetId
  )

proc actionStartOrderHold*(fleetId: int): Proposal =
  ## Start order entry for Hold command (immediate, no target)
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionName: ActionStartOrderHold,
    gameActionType: ActionStartOrderHold,
    gameActionData: $fleetId
  )

proc actionConfirmOrder*(targetSystemId: int): Proposal =
  ## Confirm order with target system
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionName: ActionConfirmOrder,
    gameActionType: ActionConfirmOrder,
    gameActionData: $targetSystemId
  )

proc actionCancelOrder*(): Proposal =
  ## Cancel order entry
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionName: ActionCancelOrder,
    gameActionType: ActionCancelOrder,
    gameActionData: ""
  )

# ============================================================================
# System Actions
# ============================================================================

proc actionResize*(width, height: int): Proposal =
  ## Handle terminal resize
  result = Proposal(
    kind: ProposalKind.pkViewportScroll,  # Reuse for resize data
    timestamp: getTime().toUnix(),
    actionName: ActionResize,
    scrollDelta: (width, height)  # Store new dimensions
  )

# ============================================================================
# Input Mapping Helper
# ============================================================================

type
  KeyCode* {.pure.} = enum
      ## Simplified key codes for mapping
      KeyNone
      # Number keys for view switching
      Key1, Key2, Key3, Key4, Key5, Key6, Key7, Key8, Key9
      # Letter keys
      KeyQ, KeyC, KeyF, KeyO, KeyM, KeyE, KeyH, KeyX, KeyS, KeyL
      KeyB, KeyG, KeyR, KeyJ, KeyD, KeyP, KeyV, KeyN, KeyW, KeyI, KeyT, KeyA
      KeyY, KeyU
      # Navigation
      KeyUp, KeyDown, KeyLeft, KeyRight
      KeyEnter, KeyEscape, KeyTab, KeyShiftTab
      KeyHome, KeyBackspace
      # Special
      KeyColon  # Expert mode trigger
      KeyCtrlE  # Turn submission
      KeyCtrlQ
      KeyCtrlL


proc mapKeyToAction*(key: KeyCode, model: TuiModel): Option[Proposal] =
  ## Map a key code to an action based on current model state
  ## Returns None if no action should be taken

  if model.quitConfirmationActive:
    case key
    of KeyCode.KeyY:
      return some(actionQuitConfirm())
    of KeyCode.KeyN, KeyCode.KeyEscape:
      return some(actionQuitCancel())
    else:
      return none(Proposal)

  if key == KeyCode.KeyCtrlQ:
    return some(actionQuit())
  
  # Order entry mode: target selection on map
  if model.orderEntryActive:
    case key
    of KeyCode.KeyEscape:
      return some(actionCancelOrder())
    of KeyCode.KeyEnter:
      # Confirm with current cursor position - need to look up system ID
      # The acceptor will resolve the cursor coord to system ID
      return some(actionConfirmOrder(-1))  # -1 = use cursor
    of KeyCode.KeyUp:
      return some(actionMoveCursor(HexDirection.NorthWest))
    of KeyCode.KeyDown:
      return some(actionMoveCursor(HexDirection.SouthEast))
    of KeyCode.KeyLeft:
      return some(actionMoveCursor(HexDirection.West))
    of KeyCode.KeyRight:
      return some(actionMoveCursor(HexDirection.East))
    of KeyCode.KeyQ:
      return some(actionCancelOrder())  # Q also cancels
    else:
      return none(Proposal)
  
  # Expert mode has its own input handling
  if model.expertModeActive:
    case key
    of KeyCode.KeyEscape:
      return some(actionExitExpertMode())
    of KeyCode.KeyEnter:
      return some(actionExpertSubmit())
    of KeyCode.KeyBackspace:
      return some(actionExpertInputBackspace())
    of KeyCode.KeyUp:
      return some(actionExpertHistoryPrev())
    of KeyCode.KeyDown:
      return some(actionExpertHistoryNext())
    else:
      # Other keys add to input buffer - handled by acceptor
      return none(Proposal)

  if model.appPhase == AppPhase.Lobby:
    # Entry modal keybindings
    if model.entryModal.mode == EntryModalMode.ImportNsec:
      # Import mode: typing nsec
      case key
      of KeyCode.KeyEnter:
        return some(actionEntryImportConfirm())
      of KeyCode.KeyEscape:
        return some(actionEntryImportCancel())
      of KeyCode.KeyBackspace:
        return some(actionEntryImportBackspace())
      else:
        return none(Proposal)  # Character input handled separately
    elif model.entryModal.editingRelay:
      # Relay URL editing mode
      case key
      of KeyCode.KeyEnter, KeyCode.KeyEscape:
        return some(actionEntryRelayConfirm())
      of KeyCode.KeyBackspace:
        return some(actionEntryRelayBackspace())
      else:
        return none(Proposal)  # Character input handled separately
    elif model.entryModal.mode == EntryModalMode.CreateGame:
      # Create game mode
      case key
      of KeyCode.KeyEscape:
        return some(actionCreateGameCancel())
      of KeyCode.KeyUp:
        return some(actionCreateGameUp())
      of KeyCode.KeyDown:
        return some(actionCreateGameDown())
      of KeyCode.KeyLeft:
        return some(actionCreateGameLeft())
      of KeyCode.KeyRight:
        return some(actionCreateGameRight())
      of KeyCode.KeyEnter:
        return some(actionCreateGameConfirm())
      of KeyCode.KeyBackspace:
        return some(actionCreateGameBackspace())
      else:
        return none(Proposal)  # Character input handled separately
    elif model.entryModal.mode == EntryModalMode.ManageGames:
      # Manage games mode - for now just allow escape to exit
      case key
      of KeyCode.KeyEscape:
        return some(actionManageGamesCancel())
      else:
        return none(Proposal)
    else:
      # Normal entry modal mode
      case key
      of KeyCode.KeyUp:
        return some(actionEntryUp())
      of KeyCode.KeyDown:
        return some(actionEntryDown())
      of KeyCode.KeyEnter:
        case model.entryModal.focus
        of EntryModalFocus.InviteCode:
          return some(actionEntryInviteSubmit())
        of EntryModalFocus.AdminMenu:
          return some(actionEntryAdminSelect())
        of EntryModalFocus.GameList:
          return some(actionEntrySelect())
        of EntryModalFocus.RelayUrl:
          return some(actionEntryRelayEdit())
      of KeyCode.KeyBackspace:
        if model.entryModal.focus == EntryModalFocus.InviteCode:
          return some(actionEntryInviteBackspace())
        elif model.entryModal.focus == EntryModalFocus.RelayUrl:
          return some(actionEntryRelayBackspace())
        else:
          return none(Proposal)
      of KeyCode.KeyI:
        return some(actionEntryImport())
      of KeyCode.KeyCtrlL:
        return none(Proposal)
      else:
        return none(Proposal)

  if model.appPhase == AppPhase.InGame:
    if key == KeyCode.KeyCtrlL:
      return some(actionLobbyReturn())

  # Global keys (work in any mode)
  case key
  # Number keys [1-9] switch primary views
  of KeyCode.Key1: return some(actionSwitchView(1))
  of KeyCode.Key2: return some(actionSwitchView(2))
  of KeyCode.Key3: return some(actionSwitchView(3))
  of KeyCode.Key4: return some(actionSwitchView(4))
  of KeyCode.Key5: return some(actionSwitchView(5))
  of KeyCode.Key6: return some(actionSwitchView(6))
  of KeyCode.Key7: return some(actionSwitchView(7))
  of KeyCode.Key8: return some(actionSwitchView(8))
  of KeyCode.Key9: return some(actionSwitchView(9))
  # Escape goes up breadcrumb
  of KeyCode.KeyEscape: return some(actionBreadcrumbBack())
  # Colon enters expert mode
  of KeyCode.KeyColon: return some(actionEnterExpertMode())
  # Ctrl+E submits turn
  of KeyCode.KeyCtrlE: return some(actionSubmitTurn())
  else:
    discard
  
  # Mode-specific keys
  case model.mode
  of ViewMode.Overview:
    case key
    of KeyCode.KeyL:
      return some(actionSwitchMode(ViewMode.Overview))
    of KeyCode.KeyUp:    return some(actionListUp())
    of KeyCode.KeyDown:  return some(actionListDown())
    of KeyCode.KeyEnter: return some(actionSelect())  # Jump to action item
    else: discard

  
  of ViewMode.Planets:
    case key
    of KeyCode.KeyUp:    return some(actionListUp())
    of KeyCode.KeyDown:  return some(actionListDown())
    of KeyCode.KeyEnter: return some(actionSelect())  # View colony
    of KeyCode.KeyB:
      return some(actionSelect())
    of KeyCode.KeyS:     return some(actionSelect())  # Sort - TODO
    of KeyCode.KeyF:     return some(actionSelect())  # Filter - TODO
    else: discard
  
  of ViewMode.Fleets:
    case key
    of KeyCode.KeyUp:    return some(actionListUp())
    of KeyCode.KeyDown:  return some(actionListDown())
    of KeyCode.KeyEnter: return some(actionSelect())  # Fleet details
    of KeyCode.KeyX:     return some(actionToggleFleetSelect(model.selectedIdx))
    of KeyCode.KeyL:
      return some(actionSwitchFleetView())
    of KeyCode.KeyM:     return some(actionSelect())  # Move
    of KeyCode.KeyP:     return some(actionSelect())  # Patrol
    of KeyCode.KeyH:     return some(actionSelect())  # Hold
    of KeyCode.KeyR:     return some(actionSelect())  # ROE
    else: discard
  
  of ViewMode.Research:
    case key
    of KeyCode.KeyE:     return some(actionSelect())  # Adjust ERP
    of KeyCode.KeyS:     return some(actionSelect())  # Adjust SRP
    of KeyCode.KeyT:     return some(actionSelect())  # Adjust TRP
    of KeyCode.KeyEnter: return some(actionSelect())  # Confirm allocation
    else: discard
  
  of ViewMode.Espionage:
    case key
    of KeyCode.KeyUp:    return some(actionListUp())
    of KeyCode.KeyDown:  return some(actionListDown())
    of KeyCode.KeyEnter: return some(actionSelect())  # Queue operation
    of KeyCode.KeyT:     return some(actionSelect())  # Select target
    of KeyCode.KeyB:     return some(actionSelect())  # Buy EBP
    of KeyCode.KeyC:     return some(actionSelect())  # Buy CIP
    else: discard
  
  of ViewMode.Economy:
    case key
    of KeyCode.KeyLeft:  return some(actionSelect())  # Decrease tax
    of KeyCode.KeyRight: return some(actionSelect())  # Increase tax
    of KeyCode.KeyEnter: return some(actionSelect())  # Confirm
    of KeyCode.KeyI:     return some(actionSelect())  # Industrial investment
    of KeyCode.KeyG:     return some(actionSelect())  # Guild transfer
    else: discard
  
  of ViewMode.Reports:
    case key
    of KeyCode.KeyUp:
      return some(actionListUp())
    of KeyCode.KeyDown:
      return some(actionListDown())
    of KeyCode.KeyEnter:
      return some(actionSelect())  # View report
    of KeyCode.KeyD:
      return some(actionSelect())  # Delete
    of KeyCode.KeyA:
      return some(actionSelect())  # Archive
    of KeyCode.KeyM:
      return some(actionSelect())  # Mark read/unread
    of KeyCode.KeyTab:
      return some(actionReportFocusNext())
    of KeyCode.KeyShiftTab:
      return some(actionReportFocusPrev())
    of KeyCode.KeyLeft:
      return some(actionReportFocusLeft())
    of KeyCode.KeyRight:
      return some(actionReportFocusRight())
    else: discard
  
  of ViewMode.Messages:
    case key
    of KeyCode.KeyUp:    return some(actionListUp())
    of KeyCode.KeyDown:  return some(actionListDown())
    of KeyCode.KeyL:     return some(actionSelect())  # Diplomatic matrix
    of KeyCode.KeyC:     return some(actionSelect())  # Compose
    of KeyCode.KeyP:     return some(actionSelect())  # Propose
    of KeyCode.KeyA:     return some(actionSelect())  # Accept
    of KeyCode.KeyR:     return some(actionSelect())  # Reject
    else: discard
  
  of ViewMode.Settings:
    case key
    of KeyCode.KeyUp:    return some(actionListUp())
    of KeyCode.KeyDown:  return some(actionListDown())
    of KeyCode.KeyEnter: return some(actionSelect())  # Change value
    of KeyCode.KeyR:     return some(actionSelect())  # Reset to defaults
    else: discard
  
  of ViewMode.PlanetDetail:
    case key
    of KeyCode.KeyTab:   return some(actionSelect())  # Next section
    of KeyCode.Key1:     return some(actionSwitchPlanetTab(1))  # Summary
    of KeyCode.Key2:     return some(actionSwitchPlanetTab(2))  # Economy
    of KeyCode.Key3:     return some(actionSwitchPlanetTab(3))  # Construction
    of KeyCode.Key4:     return some(actionSwitchPlanetTab(4))  # Defense
    of KeyCode.Key5:     return some(actionSwitchPlanetTab(5))  # Settings
    of KeyCode.KeyB:     return some(actionSelect())  # Build
    of KeyCode.KeyG:     return some(actionSelect())  # Garrison
    else: discard
  
  of ViewMode.FleetDetail:
    case key
    of KeyCode.KeyM:
      # Move command - start order entry with target selection
      if model.selectedFleetId > 0:
        return some(actionStartOrderMove(model.selectedFleetId))
    of KeyCode.KeyP:
      # Patrol command - start order entry with target selection
      if model.selectedFleetId > 0:
        return some(actionStartOrderPatrol(model.selectedFleetId))
    of KeyCode.KeyH:
      # Hold command - immediate, no target needed
      if model.selectedFleetId > 0:
        return some(actionStartOrderHold(model.selectedFleetId))
    of KeyCode.KeyG:     return some(actionSelect())  # Guard
    of KeyCode.KeyR:     return some(actionSelect())  # ROE
    of KeyCode.KeyJ:     return some(actionSelect())  # Join
    of KeyCode.KeyD:     return some(actionSelect())  # Detach ships
    else: discard
  
  of ViewMode.ReportDetail:
    case key
    of KeyCode.KeyBackspace:
      return some(actionBreadcrumbBack())
    of KeyCode.KeyN:
      return some(actionSelect())  # Next report
    of KeyCode.KeyEnter:
      return some(actionSelect())  # Jump to linked view
    else: discard

  none(Proposal)
