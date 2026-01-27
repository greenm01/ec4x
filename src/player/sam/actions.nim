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
  ## Switch to primary view by number [1-9]
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

proc actionSwitchPlanetTab*(tab: int): Proposal =
  ## Switch planet detail tab (1-5)
  Proposal(
    kind: ProposalKind.pkNavigation,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.switchPlanetTab,
    navMode: tab,
    navCursor: (0, 0)
  )

proc actionSwitchFleetView*(): Proposal =
  ## Toggle between fleet System View and List View
  Proposal(
    kind: ProposalKind.pkNavigation,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.switchFleetView,
    navMode: 0,
    navCursor: (0, 0)
  )

proc actionCycleReportFilter*(): Proposal =
  ## Cycle the Reports view filter
  Proposal(
    kind: ProposalKind.pkNavigation,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.cycleReportFilter,
    navMode: 0,
    navCursor: (0, 0)
  )

proc actionReportFocusNext*(): Proposal =
  ## Cycle report focus forward
  Proposal(
    kind: ProposalKind.pkNavigation,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.reportFocusNext,
    navMode: 0,
    navCursor: (0, 0)
  )

proc actionReportFocusPrev*(): Proposal =
  ## Cycle report focus backward
  Proposal(
    kind: ProposalKind.pkNavigation,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.reportFocusPrev,
    navMode: 0,
    navCursor: (0, 0)
  )

proc actionReportFocusLeft*(): Proposal =
  ## Move report focus left
  Proposal(
    kind: ProposalKind.pkNavigation,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.reportFocusLeft,
    navMode: 0,
    navCursor: (0, 0)
  )

proc actionReportFocusRight*(): Proposal =
  ## Move report focus right
  Proposal(
    kind: ProposalKind.pkNavigation,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.reportFocusRight,
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

proc actionBuildQuantityInc*(): Proposal =
  ## Increase build quantity
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.buildQuantityInc,
    gameActionData: ""
  )

proc actionBuildQuantityDec*(): Proposal =
  ## Decrease build quantity
  Proposal(
    kind: ProposalKind.pkGameAction,
    timestamp: getTime().toUnix(),
    actionKind: ActionKind.buildQuantityDec,
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
      KeyPageUp, KeyPageDown
      # Special
      KeyColon  # Expert mode trigger
      KeyCtrlE  # Turn submission
      KeyCtrlQ
      KeyCtrlL
