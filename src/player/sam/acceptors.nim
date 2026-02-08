## TUI Acceptors - Functions that mutate model state
##
## Acceptors receive proposals and mutate the model accordingly.
## They are the ONLY place where model mutation happens.
## Each acceptor handles specific proposal types or aspects of state.
##
## Acceptor signature: proc(model: var M, proposal: Proposal)

import std/[options, times, strutils, tables]
import ./types
import ./tui_model
import ./actions
import ./command_parser
import ../tui/widget/scroll_state
import ../state/join_flow
import ../state/lobby_profile
import ../../common/invite_code
import ../../common/logger
import ../../engine/types/[core, production, ship, facilities, ground_unit, fleet]

export types, tui_model, actions

const DigitBufferTimeout = 1.0  ## Seconds to wait for a second keystroke in multi-char input

proc viewModeFromInt(value: int): Option[ViewMode] =
  case value
  of 1:
    some(ViewMode.Overview)
  of 2:
    some(ViewMode.Planets)
  of 3:
    some(ViewMode.Fleets)
  of 4:
    some(ViewMode.Research)
  of 5:
    some(ViewMode.Espionage)
  of 6:
    some(ViewMode.Economy)
  of 7:
    some(ViewMode.Reports)
  of 9:
    some(ViewMode.Settings)
  of 20:
    some(ViewMode.PlanetDetail)
  of 30:
    some(ViewMode.FleetDetail)
  of 70:
    some(ViewMode.ReportDetail)
  else:
    none(ViewMode)

proc updateFleetDetailScroll(model: var TuiModel): tuple[
    pageSize, maxOffset: int] =
  let pageSize = max(1, fleetDetailMaxRows(model.ui.termHeight))
  model.ui.fleetDetailModal.shipScroll.contentLength =
    model.ui.fleetDetailModal.shipCount
  model.ui.fleetDetailModal.shipScroll.viewportLength = pageSize
  model.ui.fleetDetailModal.shipScroll.clampOffsets()
  let maxOffset = model.ui.fleetDetailModal.shipScroll.maxVerticalOffset()
  (pageSize, maxOffset)

proc resetFleetDetailSubModal(model: var TuiModel) =
  model.ui.fleetDetailModal.subModal = FleetSubModal.None
  model.ui.fleetDetailModal.confirmPending = false
  model.ui.fleetDetailModal.confirmMessage = ""
  model.ui.fleetDetailModal.pendingCommandType = FleetCommandType.Hold
  model.ui.fleetDetailModal.noticeMessage = ""
  model.ui.fleetDetailModal.noticeReturnSubModal = FleetSubModal.None
  model.ui.fleetDetailModal.fleetPickerCandidates = @[]
  model.ui.fleetDetailModal.fleetPickerIdx = 0
  model.ui.fleetDetailModal.systemPickerIdx = 0
  model.ui.fleetDetailModal.systemPickerSystems = @[]
  model.ui.fleetDetailModal.systemPickerFilter = ""
  model.ui.fleetDetailModal.systemPickerFilterTime = 0.0

proc openSystemPickerForCommand(
    model: var TuiModel,
    cmdType: FleetCommandType,
    returnSubModal: FleetSubModal
) =
  let filtered = model.buildSystemPickerListForCommand(
    cmdType
  )
  if filtered.systems.len == 0 and
      filtered.emptyMessage.len > 0:
    model.ui.fleetDetailModal.noticeMessage =
      filtered.emptyMessage
    model.ui.fleetDetailModal.noticeReturnSubModal =
      returnSubModal
    model.ui.fleetDetailModal.subModal =
      FleetSubModal.NoticePrompt
    return
  model.ui.fleetDetailModal.systemPickerSystems =
    filtered.systems
  model.ui.fleetDetailModal.systemPickerIdx = 0
  model.ui.fleetDetailModal.systemPickerFilter = ""
  model.ui.fleetDetailModal.systemPickerFilterTime = 0.0
  model.ui.fleetDetailModal.systemPickerCommandType = cmdType
  model.ui.fleetDetailModal.subModal =
    FleetSubModal.SystemPicker

proc commandIndexForCode(
    commands: seq[FleetCommandType],
    code: int
): int =
  let allCommands = allFleetCommands()
  if code < 0 or code >= allCommands.len:
    return -1
  let cmdType = allCommands[code]
  for idx, cmd in commands:
    if cmd == cmdType:
      return idx
  -1

proc openCommandPicker(model: var TuiModel) =
  let commands = model.buildCommandPickerList()
  if commands.len == 0:
    model.ui.fleetDetailModal.noticeMessage =
      "No valid commands available"
    model.ui.fleetDetailModal.noticeReturnSubModal =
      FleetSubModal.None
    model.ui.fleetDetailModal.subModal =
      FleetSubModal.NoticePrompt
    return
  model.ui.fleetDetailModal.commandPickerCommands = commands
  model.ui.fleetDetailModal.commandIdx = 0
  model.ui.fleetDetailModal.commandDigitBuffer = ""
  model.ui.fleetDetailModal.commandDigitTime = 0.0
  model.ui.fleetDetailModal.subModal =
    FleetSubModal.CommandPicker

proc advanceSortColumn*(state: var TableSortState) =
  ## Move to next sort column, reset to ascending
  state.columnIdx =
    (state.columnIdx + 1) mod state.columnCount
  state.ascending = true

proc retreatSortColumn*(state: var TableSortState) =
  ## Move to previous sort column, reset to ascending
  state.columnIdx =
    (state.columnIdx - 1 + state.columnCount) mod
    state.columnCount
  state.ascending = true

proc toggleSortDirection*(
    state: var TableSortState) =
  ## Toggle ascending/descending on current column
  state.ascending = not state.ascending

proc resetExpertPaletteSelection(model: var TuiModel) =
  let matches = matchExpertCommands(model.ui.expertModeInput)
  if matches.len == 0:
    model.ui.expertPaletteSelection = -1
  else:
    model.ui.expertPaletteSelection = 0

proc clampExpertPaletteSelection(model: var TuiModel) =
  let matches = matchExpertCommands(model.ui.expertModeInput)
  if matches.len == 0:
    model.ui.expertPaletteSelection = -1
    return
  if model.ui.expertPaletteSelection < 0:
    model.ui.expertPaletteSelection = 0
  elif model.ui.expertPaletteSelection >= matches.len:
    model.ui.expertPaletteSelection = matches.len - 1

# ============================================================================
# Navigation Acceptor
# ============================================================================

proc navigationAcceptor*(model: var TuiModel, proposal: Proposal) =
  ## Handle navigation proposals (mode changes, cursor movement)
  if proposal.kind != ProposalKind.pkNavigation:
    return

  model.clearExpertFeedback()
  case proposal.actionKind
  of ActionKind.navigateMode:
    # Mode switch
    let newMode = viewModeFromInt(proposal.navMode)
    if newMode.isSome:
      let selectedMode = newMode.get()
      model.ui.mode = selectedMode
      model.ui.selectedIdx = 0 # Reset selection when switching modes
      model.resetBreadcrumbs(selectedMode)
      model.ui.statusMessage = ""
      model.clearExpertFeedback()
  of ActionKind.switchView:
    # Primary view switch
    let newMode = viewModeFromInt(proposal.navMode)
    if newMode.isSome:
      let selectedMode = newMode.get()
      model.ui.mode = selectedMode
      model.ui.selectedIdx = 0
      model.resetBreadcrumbs(selectedMode)
      model.ui.statusMessage = ""
      model.clearExpertFeedback()
      if selectedMode == ViewMode.Reports:
        model.ui.reportFocus = ReportPaneFocus.TurnList
        model.ui.reportTurnIdx = 0
        model.ui.reportSubjectIdx = 0
        model.ui.reportTurnScroll = initScrollState()
        model.ui.reportSubjectScroll = initScrollState()
        model.ui.reportBodyScroll = initScrollState()
  of ActionKind.breadcrumbBack:
    if model.popBreadcrumb():
      let current = model.currentBreadcrumb()
      model.ui.mode = current.viewMode
      model.ui.statusMessage = ""
  of ActionKind.moveCursor:
    if proposal.navMode >= 0:
      # Direction-based movement
      let dir = HexDirection(proposal.navMode)
      model.ui.mapState.cursor = model.ui.mapState.cursor.neighbor(dir)
    else:
      # Direct coordinate movement
      model.ui.mapState.cursor = proposal.navCursor
  of ActionKind.jumpHome:
    if model.view.homeworld.isSome:
      model.ui.mapState.cursor = model.view.homeworld.get
  of ActionKind.cycleColony:
    let coords = model.ownedColonyCoords()
    if coords.len > 0:
      # Find current cursor in owned colonies
      var currentIdx = -1
      for i, coord in coords:
        if coord == model.ui.mapState.cursor:
          currentIdx = i
          break

      # Cycle to next/prev
      let reverse = proposal.navMode == 1
      if reverse:
        if currentIdx <= 0:
          model.ui.mapState.cursor = coords[coords.len - 1]
        else:
          model.ui.mapState.cursor = coords[currentIdx - 1]
      else:
        if currentIdx < 0 or currentIdx >= coords.len - 1:
          model.ui.mapState.cursor = coords[0]
        else:
          model.ui.mapState.cursor = coords[currentIdx + 1]
  of ActionKind.switchPlanetTab:
    # navMode: -1 = prev tab, 0/1 = next tab, 2-5 = direct tab selection
    let currentTab = ord(model.ui.planetDetailTab)
    let nextTab =
      if proposal.navMode == -1:
        # Previous tab (left arrow) - wrap from 1 back to 5
        if currentTab <= 1:
          5
        else:
          currentTab - 1
      elif proposal.navMode == 0 or proposal.navMode == 1:
        # Next tab (right arrow, tab key) - wrap from 5 back to 1
        if currentTab >= 5:
          1
        else:
          currentTab + 1
      else:
        # Direct tab selection (2-5)
        max(1, min(5, proposal.navMode))
    model.ui.planetDetailTab = PlanetDetailTab(nextTab)
  of ActionKind.switchFleetView:
    if model.ui.fleetViewMode == FleetViewMode.SystemView:
      model.ui.fleetViewMode = FleetViewMode.ListView
    else:
      model.ui.fleetViewMode = FleetViewMode.SystemView
  
  of ActionKind.fleetConsoleNextPane:
    # Only active in SystemView mode
    if model.ui.fleetViewMode == FleetViewMode.SystemView:
      case model.ui.fleetConsoleFocus
      of FleetConsoleFocus.SystemsPane:
        model.ui.fleetConsoleFocus = FleetConsoleFocus.FleetsPane
      of FleetConsoleFocus.FleetsPane:
        model.ui.fleetConsoleFocus = FleetConsoleFocus.ShipsPane
      of FleetConsoleFocus.ShipsPane:
        model.ui.fleetConsoleFocus = FleetConsoleFocus.SystemsPane
  
  of ActionKind.fleetConsolePrevPane:
    # Only active in SystemView mode
    if model.ui.fleetViewMode == FleetViewMode.SystemView:
      case model.ui.fleetConsoleFocus
      of FleetConsoleFocus.SystemsPane:
        model.ui.fleetConsoleFocus = FleetConsoleFocus.ShipsPane
      of FleetConsoleFocus.FleetsPane:
        model.ui.fleetConsoleFocus = FleetConsoleFocus.SystemsPane
      of FleetConsoleFocus.ShipsPane:
        model.ui.fleetConsoleFocus = FleetConsoleFocus.FleetsPane
  
  of ActionKind.cycleReportFilter:
    let nextFilter = (ord(model.ui.reportFilter) + 1) mod
      (ord(ReportCategory.Other) + 1)
    model.ui.reportFilter = ReportCategory(nextFilter)
    model.ui.selectedIdx = 0
    model.ui.selectedReportId = 0
    model.ui.reportTurnIdx = 0
    model.ui.reportSubjectIdx = 0
    model.ui.reportTurnScroll = initScrollState()
    model.ui.reportSubjectScroll = initScrollState()
    model.ui.reportBodyScroll = initScrollState()
    model.ui.statusMessage = ""
  of ActionKind.reportFocusNext:
    case model.ui.reportFocus
    of ReportPaneFocus.TurnList:
      model.ui.reportFocus = ReportPaneFocus.SubjectList
    of ReportPaneFocus.SubjectList:
      model.ui.reportFocus = ReportPaneFocus.BodyPane
    of ReportPaneFocus.BodyPane:
      model.ui.reportFocus = ReportPaneFocus.TurnList
  of ActionKind.reportFocusPrev:
    case model.ui.reportFocus
    of ReportPaneFocus.TurnList:
      model.ui.reportFocus = ReportPaneFocus.BodyPane
    of ReportPaneFocus.SubjectList:
      model.ui.reportFocus = ReportPaneFocus.TurnList
    of ReportPaneFocus.BodyPane:
      model.ui.reportFocus = ReportPaneFocus.SubjectList
  of ActionKind.reportFocusLeft:
    case model.ui.reportFocus
    of ReportPaneFocus.TurnList:
      discard
    of ReportPaneFocus.SubjectList:
      model.ui.reportFocus = ReportPaneFocus.TurnList
    of ReportPaneFocus.BodyPane:
      model.ui.reportFocus = ReportPaneFocus.SubjectList
  of ActionKind.reportFocusRight:
    case model.ui.reportFocus
    of ReportPaneFocus.TurnList:
      model.ui.reportFocus = ReportPaneFocus.SubjectList
    of ReportPaneFocus.SubjectList:
      model.ui.reportFocus = ReportPaneFocus.BodyPane
    of ReportPaneFocus.BodyPane:
      discard
  of ActionKind.lobbySwitchPane:
    if proposal.navMode >= 0 and proposal.navMode <= 2:
      model.ui.lobbyPane = LobbyPane(proposal.navMode)
  else:
    discard

# ============================================================================
# Selection Acceptor
# ============================================================================

proc selectionAcceptor*(model: var TuiModel, proposal: Proposal) =
  ## Handle selection proposals (list selection, map selection)
  if proposal.kind != ProposalKind.pkSelection:
    return

  model.clearExpertFeedback()
  case proposal.actionKind
  of ActionKind.select:
    case model.ui.mode
    of ViewMode.Overview:
      # Overview selection (action queue items)
      if proposal.selectIdx >= 0:
        model.ui.selectedIdx = proposal.selectIdx
    of ViewMode.Planets, ViewMode.Fleets, ViewMode.Research,
       ViewMode.Espionage, ViewMode.Economy, ViewMode.Reports,
       ViewMode.Settings, ViewMode.PlanetDetail,
       ViewMode.FleetDetail, ViewMode.ReportDetail,
       ViewMode.IntelDb:
      # Select current list item (idx is already set)
      if proposal.selectIdx >= 0:
        model.ui.selectedIdx = proposal.selectIdx

    if model.ui.mode == ViewMode.Reports:
      let reports = model.currentTurnReports()
      if model.ui.reportSubjectIdx < reports.len:
        model.ui.selectedReportId = reports[model.ui.reportSubjectIdx].id
        model.ui.mode = ViewMode.ReportDetail
        model.pushBreadcrumb(
          "Report " & $(model.ui.reportSubjectIdx + 1),
          ViewMode.ReportDetail,
          model.ui.selectedReportId,
        )
        model.ui.statusMessage = ""
        model.clearExpertFeedback()
      else:
        model.ui.statusMessage = "No reports in this turn"
    elif model.ui.mode == ViewMode.ReportDetail:
      let reportOpt = model.selectedReport()
      if reportOpt.isSome:
        let report = reportOpt.get()
        let target = report.linkView
        let nextMode = viewModeFromInt(target)
        if nextMode.isSome:
          let selectedMode = nextMode.get()
          model.ui.mode = selectedMode
          model.resetBreadcrumbs(selectedMode)
          model.ui.statusMessage = "Jumped to " & report.linkLabel
      model.clearExpertFeedback()
  of ActionKind.toggleFleetSelect:
    if model.ui.mode == ViewMode.Fleets:
      if model.ui.fleetViewMode == FleetViewMode.ListView:
        let fleets = model.filteredFleets()
        if model.ui.selectedIdx < fleets.len:
          let fleetId = fleets[model.ui.selectedIdx].id
          model.toggleFleetSelection(fleetId)
      elif model.ui.fleetViewMode == FleetViewMode.SystemView:
        if model.ui.fleetConsoleFocus == FleetConsoleFocus.FleetsPane:
          let systems = model.ui.fleetConsoleSystems
          if systems.len > 0:
            let sysIdx = clamp(model.ui.fleetConsoleSystemIdx, 0, systems.len - 1)
            let systemId = systems[sysIdx].systemId
            if model.ui.fleetConsoleFleetsBySystem.hasKey(systemId):
              let fleets = model.ui.fleetConsoleFleetsBySystem[systemId]
              let fleetIdx = model.ui.fleetConsoleFleetIdx
              if fleetIdx >= 0 and fleetIdx < fleets.len:
                let fleetId = fleets[fleetIdx].fleetId
                model.toggleFleetSelection(fleetId)
  of ActionKind.deselect:
    model.ui.mapState.selected = none(HexCoord)
    if model.ui.mode == ViewMode.ReportDetail:
      if model.popBreadcrumb():
        let current = model.currentBreadcrumb()
        model.ui.mode = current.viewMode
        model.ui.statusMessage = ""
        model.clearExpertFeedback()
      else:
        model.ui.statusMessage = ""
        model.clearExpertFeedback()
    elif model.ui.mode == ViewMode.FleetDetail:
      # Return to fleet list
      model.ui.mode = ViewMode.Fleets
      model.ui.statusMessage = ""
      model.clearExpertFeedback()
    elif model.ui.mode == ViewMode.PlanetDetail:
      # Return to colony list
      model.ui.mode = ViewMode.Planets
      model.ui.statusMessage = ""
      model.clearExpertFeedback()
    else:
      model.ui.statusMessage = ""
      model.clearExpertFeedback()
  of ActionKind.listUp:
    # Fleet console per-pane navigation
    if model.ui.mode == ViewMode.Fleets and
        model.ui.fleetViewMode == FleetViewMode.SystemView:
      case model.ui.fleetConsoleFocus
      of FleetConsoleFocus.SystemsPane:
        if model.ui.fleetConsoleSystemIdx > 0:
          model.ui.fleetConsoleSystemIdx -= 1
          # Update scroll state to keep selection visible
          let viewportHeight = 15  # Reasonable default viewport
          model.ui.fleetConsoleSystemScroll.contentLength = model.ui.fleetConsoleSystems.len
          model.ui.fleetConsoleSystemScroll.viewportLength = viewportHeight
          model.ui.fleetConsoleSystemScroll.ensureVisible(model.ui.fleetConsoleSystemIdx)
      of FleetConsoleFocus.FleetsPane:
        if model.ui.fleetConsoleFleetIdx > 0:
          model.ui.fleetConsoleFleetIdx -= 1
          # Update scroll state
          if model.ui.fleetConsoleSystems.len > 0:
            let sysIdx = clamp(model.ui.fleetConsoleSystemIdx, 0, 
              model.ui.fleetConsoleSystems.len - 1)
            let systemId = model.ui.fleetConsoleSystems[sysIdx].systemId
            if model.ui.fleetConsoleFleetsBySystem.hasKey(systemId):
              let fleets = model.ui.fleetConsoleFleetsBySystem[systemId]
              let viewportHeight = 15
              model.ui.fleetConsoleFleetScroll.contentLength = fleets.len
              model.ui.fleetConsoleFleetScroll.viewportLength = viewportHeight
              model.ui.fleetConsoleFleetScroll.ensureVisible(model.ui.fleetConsoleFleetIdx)
      of FleetConsoleFocus.ShipsPane:
        if model.ui.fleetConsoleShipIdx > 0:
          model.ui.fleetConsoleShipIdx -= 1
    else:
      # Default list navigation
      if model.ui.selectedIdx > 0:
        model.ui.selectedIdx = max(0, model.ui.selectedIdx - 1)
  
  of ActionKind.listDown:
    # Fleet console per-pane navigation
    if model.ui.mode == ViewMode.Fleets and
        model.ui.fleetViewMode == FleetViewMode.SystemView:
      # Use cached data for proper bounds checking
      case model.ui.fleetConsoleFocus
      of FleetConsoleFocus.SystemsPane:
        let maxIdx = max(0, model.ui.fleetConsoleSystems.len - 1)
        if model.ui.fleetConsoleSystemIdx < maxIdx:
          model.ui.fleetConsoleSystemIdx += 1
          # Update scroll state to keep selection visible
          let viewportHeight = 15
          model.ui.fleetConsoleSystemScroll.contentLength = model.ui.fleetConsoleSystems.len
          model.ui.fleetConsoleSystemScroll.viewportLength = viewportHeight
          model.ui.fleetConsoleSystemScroll.ensureVisible(model.ui.fleetConsoleSystemIdx)
      of FleetConsoleFocus.FleetsPane:
        # Get fleets for current system to check bounds
        if model.ui.fleetConsoleSystems.len > 0:
          let sysIdx = clamp(model.ui.fleetConsoleSystemIdx, 0, 
            model.ui.fleetConsoleSystems.len - 1)
          let systemId = model.ui.fleetConsoleSystems[sysIdx].systemId
          if model.ui.fleetConsoleFleetsBySystem.hasKey(systemId):
            let fleets = model.ui.fleetConsoleFleetsBySystem[systemId]
            let maxIdx = max(0, fleets.len - 1)
            if model.ui.fleetConsoleFleetIdx < maxIdx:
              model.ui.fleetConsoleFleetIdx += 1
              # Update scroll state
              let viewportHeight = 15
              model.ui.fleetConsoleFleetScroll.contentLength = fleets.len
              model.ui.fleetConsoleFleetScroll.viewportLength = viewportHeight
              model.ui.fleetConsoleFleetScroll.ensureVisible(model.ui.fleetConsoleFleetIdx)
      of FleetConsoleFocus.ShipsPane:
        model.ui.fleetConsoleShipIdx += 1  # Ships bounds checked at render
    else:
      # Default list navigation
      let maxIdx = model.currentListLength() - 1
      if model.ui.selectedIdx < maxIdx:
        model.ui.selectedIdx = min(maxIdx, model.ui.selectedIdx + 1)
  of ActionKind.listPageUp:
    let pageSize = max(1, model.ui.termHeight - 10)
    model.ui.selectedIdx = max(0, model.ui.selectedIdx - pageSize)
  of ActionKind.listPageDown:
    let maxIdx = model.currentListLength() - 1
    let pageSize = max(1, model.ui.termHeight - 10)
    model.ui.selectedIdx = min(maxIdx, model.ui.selectedIdx + pageSize)
  else:
    discard

# ============================================================================
# Viewport Acceptor
# ============================================================================

proc viewportAcceptor*(model: var TuiModel, proposal: Proposal) =
  ## Handle viewport/scroll proposals
  if proposal.kind != ProposalKind.pkViewportScroll:
    return

  model.clearExpertFeedback()
  case proposal.actionKind
  of ActionKind.scroll:
    model.ui.mapState.viewportOrigin = (
      model.ui.mapState.viewportOrigin.q + proposal.scrollDelta.dx,
      model.ui.mapState.viewportOrigin.r + proposal.scrollDelta.dy,
    )
  of ActionKind.resize:
    model.ui.termWidth = proposal.scrollDelta.dx
    model.ui.termHeight = proposal.scrollDelta.dy
    model.ui.needsResize = true
  else:
    discard

# ============================================================================
# Game Action Acceptor
# ============================================================================

proc gameActionAcceptor*(model: var TuiModel, proposal: Proposal) =
  ## Handle game action proposals
  model.clearExpertFeedback()
  case proposal.kind
  of ProposalKind.pkNavigation:
    # Skip - navigation is handled by navigationAcceptor
    # Only process detail view transitions triggered by game actions
    if proposal.actionKind in [ActionKind.switchView, ActionKind.navigateMode,
        ActionKind.breadcrumbBack, ActionKind.moveCursor, ActionKind.jumpHome,
        ActionKind.cycleColony]:
      return
    let target = proposal.navMode
    # Special handling for detail views (mode 20/30 are dynamic)
    if target == 20:
      model.ui.previousMode = model.ui.mode
      model.ui.mode = ViewMode.PlanetDetail
      model.resetBreadcrumbs(model.ui.mode)
      if model.ui.selectedIdx < model.view.colonies.len:
        model.ui.selectedColonyId =
          model.view.colonies[model.ui.selectedIdx].colonyId
    # NOTE: target == 30 (FleetDetail) removed - now uses popup modal instead of full view

  of ProposalKind.pkGameAction:
    case proposal.actionKind
    of ActionKind.lobbyGenerateKey:
      model.ui.lobbySessionKeyActive = true
      model.ui.lobbyWarning = "Session-only key: not saved"
      model.ui.lobbyProfilePubkey = "session-" & $getTime().toUnix()
      model.ui.statusMessage = "Generated session key (not stored)"
      # Active games populated from Nostr events, not filesystem
    of ActionKind.lobbyJoinRefresh:
      # Games now discovered via Nostr events (30400), not filesystem scan
      # This action triggers a UI refresh; actual data comes from Nostr
      model.ui.lobbyJoinSelectedIdx = 0
      model.ui.statusMessage = "Refreshing game list from relay..."
    of ActionKind.lobbyJoinSubmit:
      if model.ui.lobbyInputMode == LobbyInputMode.Pubkey:
        let normalized = normalizePubkey(model.ui.lobbyProfilePubkey)
        if normalized.isNone:
          model.ui.lobbyJoinError = "Invalid pubkey"
          model.ui.statusMessage = model.ui.lobbyJoinError
        else:
          model.ui.lobbyProfilePubkey = normalized.get()
          model.ui.lobbyInputMode = LobbyInputMode.None
          saveProfile("data", model.ui.lobbyProfilePubkey,
            model.ui.lobbyProfileName, model.ui.lobbySessionKeyActive)
          # Active games populated from TUI cache, not filesystem
      elif model.ui.lobbyInputMode == LobbyInputMode.Name:
        model.ui.lobbyInputMode = LobbyInputMode.None
        saveProfile("data", model.ui.lobbyProfilePubkey,
          model.ui.lobbyProfileName, model.ui.lobbySessionKeyActive)
      elif model.ui.lobbyJoinStatus == JoinStatus.SelectingGame:
        if model.ui.lobbyJoinSelectedIdx < model.view.lobbyJoinGames.len:
          let game = model.view.lobbyJoinGames[
            model.ui.lobbyJoinSelectedIdx
          ]
          model.ui.lobbyGameId = game.id
          model.ui.lobbyJoinStatus = JoinStatus.EnteringPubkey
          model.ui.statusMessage = "Enter Nostr pubkey"
        else:
          model.ui.lobbyJoinError = "No game selected"
      elif model.ui.lobbyJoinStatus == JoinStatus.EnteringPubkey:
        let normalized = normalizePubkey(model.ui.lobbyProfilePubkey)
        if normalized.isNone:
          model.ui.lobbyJoinError = "Invalid pubkey"
          model.ui.statusMessage = model.ui.lobbyJoinError
        else:
          model.ui.lobbyProfilePubkey = normalized.get()
          model.ui.lobbyJoinStatus = JoinStatus.EnteringName
          model.ui.statusMessage = "Enter player name (optional)"
      elif model.ui.lobbyJoinStatus == JoinStatus.EnteringName:
        let normalized = normalizePubkey(model.ui.lobbyProfilePubkey)
        if normalized.isNone:
          model.ui.lobbyJoinError = "Invalid pubkey"
          model.ui.statusMessage = model.ui.lobbyJoinError
        else:
          model.ui.lobbyProfilePubkey = normalized.get()
          saveProfile("data", model.ui.lobbyProfilePubkey,
            model.ui.lobbyProfileName, model.ui.lobbySessionKeyActive)
          let inviteCode = invite_code.normalizeInviteCode(
            model.ui.entryModal.inviteCode()
          )
          if inviteCode.len == 0:
            model.ui.lobbyJoinStatus = JoinStatus.Failed
            model.ui.lobbyJoinError = "Invite code required"
            model.ui.statusMessage = model.ui.lobbyJoinError
          elif model.ui.lobbyGameId.len == 0:
            model.ui.lobbyJoinStatus = JoinStatus.Failed
            model.ui.lobbyJoinError = "Game ID missing"
            model.ui.statusMessage = model.ui.lobbyJoinError
          else:
            model.ui.nostrJoinRequested = true
            model.ui.nostrJoinSent = false
            model.ui.nostrJoinInviteCode = inviteCode
            model.ui.nostrJoinGameId = model.ui.lobbyGameId
            model.ui.nostrJoinPubkey = model.ui.lobbyProfilePubkey
            model.ui.lobbyJoinStatus = JoinStatus.WaitingResponse
            model.ui.statusMessage = "Submitting join request"
    of ActionKind.lobbyJoinPoll:
      if model.ui.lobbyJoinStatus == JoinStatus.WaitingResponse:
        model.ui.statusMessage = "Waiting for join response..."
    of ActionKind.lobbyReturn:
      model.ui.appPhase = AppPhase.Lobby
      model.ui.statusMessage = "Returned to lobby"
      # Active games already in model from TUI cache
    of ActionKind.lobbyEditPubkey:
      model.ui.lobbyInputMode = LobbyInputMode.Pubkey
      model.ui.statusMessage = "Enter Nostr pubkey"
      # Active games already in model from TUI cache
    of ActionKind.lobbyEditName:
      model.ui.lobbyInputMode = LobbyInputMode.Name
      model.ui.statusMessage = "Enter player name"
    of ActionKind.lobbyBackspace:
      case model.ui.lobbyInputMode
      of LobbyInputMode.Pubkey:
        if model.ui.lobbyProfilePubkey.len > 0:
          model.ui.lobbyProfilePubkey.setLen(
            model.ui.lobbyProfilePubkey.len - 1
          )
        # Active games filtered by pubkey from TUI cache
      of LobbyInputMode.Name:
        if model.ui.lobbyProfileName.len > 0:
          model.ui.lobbyProfileName.setLen(
            model.ui.lobbyProfileName.len - 1
          )
      else:
        discard
    of ActionKind.lobbyInputAppend:
      case model.ui.lobbyInputMode
      of LobbyInputMode.Pubkey:
        model.ui.lobbyProfilePubkey.add(proposal.gameActionData)
      of LobbyInputMode.Name:
        model.ui.lobbyProfileName.add(proposal.gameActionData)
      else:
        discard
    # Entry modal actions
    of ActionKind.entryUp:
      model.ui.entryModal.moveUp()
    of ActionKind.entryDown:
      model.ui.entryModal.moveDown()
    of ActionKind.entrySelect:
      # Enter selected game from game list
      let gameOpt = model.ui.entryModal.selectedGame()
      if gameOpt.isSome:
        let game = gameOpt.get()
        model.ui.loadGameRequested = true
        model.ui.loadGameId = game.id
        model.ui.loadHouseId = game.houseId
        model.ui.statusMessage = "Loading game..."
    of ActionKind.entryImport:
      model.ui.entryModal.startImport()
      model.ui.statusMessage = "Enter nsec to import identity"
    of ActionKind.entryImportConfirm:
      if model.ui.entryModal.confirmImport():
        model.ui.statusMessage = "Identity imported successfully"
      else:
        model.ui.statusMessage =
          "Import failed: " & model.ui.entryModal.importError
    of ActionKind.entryImportCancel:
      model.ui.entryModal.cancelImport()
      model.ui.statusMessage = ""
    of ActionKind.entryImportAppend:
      if proposal.gameActionData.len > 0:
        discard model.ui.entryModal.importInput.appendChar(
          proposal.gameActionData[0])
    of ActionKind.entryImportBackspace:
      model.ui.entryModal.importInput.backspace()
    of ActionKind.entryInviteAppend:
      if proposal.gameActionData.len > 0:
        # Validate: allow lowercase letters, hyphen, @, :, ., and digits
        # Format: code@host:port (e.g., velvet-mountain@play.ec4x.io:8080)
        let ch = proposal.gameActionData[0].toLowerAscii()
        if ch in 'a'..'z' or ch in '0'..'9' or ch in {'-', '@', ':', '.'}:
          discard model.ui.entryModal.inviteInput.appendChar(ch)
          model.ui.entryModal.inviteError = ""
          # Focus invite code field when typing starts
          model.ui.entryModal.focusInviteCode()
    of ActionKind.entryInviteBackspace:
      model.ui.entryModal.inviteInput.backspace()
      model.ui.entryModal.inviteError = ""
    of ActionKind.entryInviteSubmit:
      # Submit invite code to server
      # Format: code@host:port (e.g., velvet-mountain@play.ec4x.io:8080)
      if model.ui.entryModal.inviteInput.isEmpty():
        model.ui.entryModal.setInviteError("Enter an invite code")
      else:
        let input = model.ui.entryModal.inviteCode()
        let parsed = parseInviteCode(input)

        if not isValidInviteCodeFormat(parsed.code):
          model.ui.entryModal.setInviteError("Invalid code format")
        elif not parsed.hasRelay() and model.ui.nostrRelayUrl.len == 0:
          model.ui.entryModal.setInviteError("No relay in code, none configured")
        else:
          let identity = model.ui.entryModal.identity
          model.ui.nostrJoinRequested = true
          model.ui.nostrJoinSent = false
          model.ui.nostrJoinInviteCode = parsed.code
          model.ui.nostrJoinRelayUrl = if parsed.hasRelay():
            parsed.relayUrl
          else:
            model.ui.nostrRelayUrl
          model.ui.nostrJoinGameId = "invite"
          model.ui.nostrJoinPubkey = identity.npubHex
          logInfo("JOIN", "FLAGS SET: requested=true, inviteCode=",
            model.ui.nostrJoinInviteCode,
            " relayUrl=", model.ui.nostrJoinRelayUrl,
            " gameId=", model.ui.nostrJoinGameId)
          model.ui.entryModal.setInviteError("Join request sent")
          model.ui.entryModal.clearInviteCode()
          model.ui.lobbyJoinStatus = JoinStatus.WaitingResponse
          model.ui.statusMessage = "Joining via " &
            model.ui.nostrJoinRelayUrl

    of ActionKind.entryAdminSelect:
      # Dispatch based on selected admin menu item
      let menuItem = model.ui.entryModal.selectedAdminMenuItem()
      if menuItem.isSome:
        case menuItem.get()
        of AdminMenuItem.CreateGame:
          # Switch to game creation mode
          model.ui.entryModal.mode = EntryModalMode.CreateGame
          model.ui.statusMessage = "Create a new game"
        of AdminMenuItem.ManageGames:
          # Switch to manage games mode
          model.ui.entryModal.mode = EntryModalMode.ManageGames
          model.ui.statusMessage = "Manage your games"
    of ActionKind.entryAdminCreateGame:
      # Direct action to enter game creation mode
      model.ui.entryModal.mode = EntryModalMode.CreateGame
      model.ui.statusMessage = "Create a new game"
    of ActionKind.entryAdminManageGames:
      # Direct action to enter manage games mode
      model.ui.entryModal.mode = EntryModalMode.ManageGames
      model.ui.statusMessage = "Manage your games"
    of ActionKind.entryRelayEdit:
      # Start editing relay URL
      model.ui.entryModal.startEditingRelay()
      model.ui.statusMessage = "Edit relay URL"
    of ActionKind.entryRelayAppend:
      # Append character to relay URL
      if proposal.gameActionData.len > 0:
        discard model.ui.entryModal.relayInput.appendChar(
          proposal.gameActionData[0])
    of ActionKind.entryRelayBackspace:
      # Backspace in relay URL
      model.ui.entryModal.relayInput.backspace()
    of ActionKind.entryRelayConfirm:
      # Confirm relay URL edit
      model.ui.entryModal.stopEditingRelay()
      model.ui.statusMessage = "Relay: " & model.ui.entryModal.relayUrl()
    # Game creation actions
    of ActionKind.createGameUp:
      model.ui.entryModal.createFieldUp()
    of ActionKind.createGameDown:
      model.ui.entryModal.createFieldDown()
    of ActionKind.createGameLeft:
      if model.ui.entryModal.createField == CreateGameField.PlayerCount:
        model.ui.entryModal.decrementPlayerCount()
    of ActionKind.createGameRight:
      if model.ui.entryModal.createField == CreateGameField.PlayerCount:
        model.ui.entryModal.incrementPlayerCount()
    of ActionKind.createGameAppend:
      if model.ui.entryModal.createField == CreateGameField.GameName:
        if proposal.gameActionData.len > 0:
          if model.ui.entryModal.createNameInput.appendChar(
               proposal.gameActionData[0]):
            model.ui.entryModal.createError = ""
    of ActionKind.createGameBackspace:
      if model.ui.entryModal.createField == CreateGameField.GameName:
        model.ui.entryModal.createNameInput.backspace()
        model.ui.entryModal.createError = ""
    of ActionKind.createGameConfirm:
      if model.ui.entryModal.createField == CreateGameField.ConfirmCreate:
        # Validate and create game
        if model.ui.entryModal.createNameInput.isEmpty():
          model.ui.entryModal.setCreateError("Game name is required")
        else:
          # TODO: Send kind 30400 event to create game
          model.ui.statusMessage = "Creating game: " &
            model.ui.entryModal.createGameName() &
            " (" & $model.ui.entryModal.createPlayerCount & " players)"
          model.ui.entryModal.cancelGameCreation()
      elif model.ui.entryModal.createField == CreateGameField.PlayerCount:
        # Enter on player count field moves to next field
        model.ui.entryModal.createFieldDown()
      elif model.ui.entryModal.createField == CreateGameField.GameName:
        # Enter on game name field moves to next field
        model.ui.entryModal.createFieldDown()
    of ActionKind.createGameCancel:
      model.ui.entryModal.cancelGameCreation()
      model.ui.statusMessage = "Game creation cancelled"
    of ActionKind.manageGamesCancel:
      model.ui.entryModal.mode = EntryModalMode.Normal
      model.ui.statusMessage = ""
    of ActionKind.enterExpertMode:
      model.enterExpertMode()
      model.ui.statusMessage =
        "Expert mode active (type command, ESC to cancel)"
    of ActionKind.exitExpertMode:
      model.exitExpertMode()
      model.ui.statusMessage = ""
    of ActionKind.expertSubmit:
      let matches = matchExpertCommands(model.ui.expertModeInput)
      if matches.len > 0:
        clampExpertPaletteSelection(model)
        let selection = model.ui.expertPaletteSelection
        if selection >= 0 and selection < matches.len:
          let chosen = matches[selection]
          let normalized = normalizeExpertInput(model.ui.expertModeInput)
          let tokens = normalized.splitWhitespace()
          let commandToken = if tokens.len > 0: tokens[0] else: ""
          if commandToken.toLowerAscii() !=
              chosen.command.name.toLowerAscii():
            var newInput = chosen.command.name
            if tokens.len > 1:
              newInput.add(" " & tokens[1..^1].join(" "))
            model.ui.expertModeInput = newInput
            model.clearExpertFeedback()
            model.ui.expertPaletteSelection = 0
            return
      # Parse and execute expert mode command
      let result = parseExpertCommand(model.ui.expertModeInput)
      if result.success:
        # Handle meta commands first
        case result.metaCommand
        of MetaCommandType.Help:
          model.setExpertFeedback(expertCommandHelpText())
          model.addToExpertHistory(model.ui.expertModeInput)
        of MetaCommandType.Clear:
          let count = model.stagedCommandCount()
          model.ui.stagedFleetCommands.clear()
          model.ui.stagedBuildCommands.setLen(0)
          model.ui.stagedRepairCommands.setLen(0)
          model.ui.stagedScrapCommands.setLen(0)
          model.ui.turnSubmissionConfirmed = false
          model.setExpertFeedback("Cleared " & $count & " staged commands")
          model.addToExpertHistory(model.ui.expertModeInput)
        of MetaCommandType.List:
          model.setExpertFeedback(model.stagedCommandsSummary())
          model.addToExpertHistory(model.ui.expertModeInput)
        of MetaCommandType.Drop:
          if result.metaIndex.isNone:
            model.setExpertFeedback("Usage: :drop <index>")
          else:
            let dropIdx = result.metaIndex.get()
            let entries = model.stagedCommandEntries()
            if dropIdx <= 0 or dropIdx > entries.len:
              model.setExpertFeedback("Invalid command index")
            else:
              let entry = entries[dropIdx - 1]
              if model.dropStagedCommand(entry):
                model.ui.turnSubmissionConfirmed = false
                model.setExpertFeedback("Dropped command " & $dropIdx)
              else:
                model.setExpertFeedback("Failed to drop command")
          model.addToExpertHistory(model.ui.expertModeInput)
        of MetaCommandType.Submit:
          if model.stagedCommandCount() > 0:
            model.ui.turnSubmissionRequested = true
            model.ui.turnSubmissionConfirmed = true  # Bypass confirmation
            let count = model.stagedCommandCount()
            model.setExpertFeedback("Submitting " & $count & " commands...")
          else:
            model.setExpertFeedback("No commands to submit")
          model.addToExpertHistory(model.ui.expertModeInput)
        of MetaCommandType.None:
          # Regular command - add to staged commands
          if result.fleetCommand.isSome:
            model.stageFleetCommand(result.fleetCommand.get())
            model.ui.turnSubmissionConfirmed = false
            model.setExpertFeedback(
              "Fleet command staged (total: " &
              $model.ui.stagedFleetCommands.len & ")"
            )
            model.addToExpertHistory(model.ui.expertModeInput)
          elif result.buildCommand.isSome:
            model.ui.stagedBuildCommands.add(result.buildCommand.get())
            model.ui.turnSubmissionConfirmed = false
            model.setExpertFeedback(
              "Build command staged (total: " &
              $model.ui.stagedBuildCommands.len & ")"
            )
            model.addToExpertHistory(model.ui.expertModeInput)
          else:
            model.setExpertFeedback("No command generated")
      else:
        model.setExpertFeedback("Error: " & result.error)
      # Keep expert mode active after submit
      model.ui.expertModeInput = ""
      resetExpertPaletteSelection(model)
    of ActionKind.expertInputAppend:
      # Append character to expert mode input
      model.ui.expertModeInput.add(proposal.gameActionData)
      resetExpertPaletteSelection(model)
    of ActionKind.expertInputBackspace:
      # Remove last character
      if model.ui.expertModeInput.len > 0:
        model.ui.expertModeInput.setLen(model.ui.expertModeInput.len - 1)
      resetExpertPaletteSelection(model)
    of ActionKind.expertHistoryPrev:
      clampExpertPaletteSelection(model)
      if model.ui.expertPaletteSelection > 0:
        model.ui.expertPaletteSelection -= 1
    of ActionKind.expertHistoryNext:
      clampExpertPaletteSelection(model)
      let matches = matchExpertCommands(model.ui.expertModeInput)
      if matches.len == 0:
        model.ui.expertPaletteSelection = -1
      elif model.ui.expertPaletteSelection < matches.len - 1:
        model.ui.expertPaletteSelection += 1
    of ActionKind.submitTurn:
      # Set flag for reactor/main loop to handle
      if model.stagedCommandCount() > 0:
        model.ui.turnSubmissionRequested = true
      else:
        model.ui.statusMessage = "No commands staged - nothing to submit"
        model.ui.turnSubmissionConfirmed = false
    of ActionKind.quitConfirm:
      model.ui.running = false
      model.ui.quitConfirmationActive = false
      model.ui.quitConfirmationChoice = QuitConfirmationChoice.QuitStay
      model.ui.statusMessage = "Exiting..."
    of ActionKind.quitCancel:
      model.ui.quitConfirmationActive = false
      model.ui.quitConfirmationChoice = QuitConfirmationChoice.QuitStay
      model.ui.statusMessage = "Quit cancelled"
    of ActionKind.quitToggle:
      if model.ui.quitConfirmationChoice == QuitConfirmationChoice.QuitStay:
        model.ui.quitConfirmationChoice = QuitConfirmationChoice.QuitExit
      else:
        model.ui.quitConfirmationChoice = QuitConfirmationChoice.QuitStay
    of ActionKind.fleetBatchCommand:
      if model.ui.mode == ViewMode.Fleets:
        if model.ui.fleetViewMode == FleetViewMode.SystemView and
           model.ui.fleetConsoleFocus != FleetConsoleFocus.FleetsPane:
          discard  # No-op when system pane is focused
        # Cursor-implicit selection: if no X-selection exists, use cursor-row fleet
        elif model.ui.selectedFleetIds.len == 0:
          let fleetIdOpt = model.getCursorFleetId()
          if fleetIdOpt.isSome:
            let fleetId = fleetIdOpt.get()
            let roe = model.getCursorFleetRoe()
            # Open FleetDetail modal in CommandPicker sub-modal
            model.ui.mode = ViewMode.FleetDetail
            model.resetBreadcrumbs(ViewMode.FleetDetail)
            model.ui.fleetDetailModal.fleetId = fleetId
            model.ui.fleetDetailModal.roeValue = roe
            model.openCommandPicker()
            model.ui.fleetDetailModal.directSubModal = true
        else:
          # Batch mode: act on all X-selected fleets
          model.ui.mode = ViewMode.FleetDetail
          model.resetBreadcrumbs(ViewMode.FleetDetail)
          model.ui.fleetDetailModal.fleetId = 0
          model.openCommandPicker()
          model.ui.fleetDetailModal.directSubModal = true
    of ActionKind.fleetBatchROE:
      if model.ui.mode == ViewMode.Fleets:
        if model.ui.fleetViewMode == FleetViewMode.SystemView and
           model.ui.fleetConsoleFocus != FleetConsoleFocus.FleetsPane:
          discard  # No-op when system pane is focused
        # Cursor-implicit selection: if no X-selection exists, use cursor-row fleet
        elif model.ui.selectedFleetIds.len == 0:
          let fleetIdOpt = model.getCursorFleetId()
          if fleetIdOpt.isSome:
            let fleetId = fleetIdOpt.get()
            let roe = model.getCursorFleetRoe()
            # Open FleetDetail modal in ROEPicker sub-modal
            model.ui.mode = ViewMode.FleetDetail
            model.resetBreadcrumbs(ViewMode.FleetDetail)
            model.ui.fleetDetailModal.fleetId = fleetId
            model.ui.fleetDetailModal.roeValue = roe
            model.ui.fleetDetailModal.subModal = FleetSubModal.ROEPicker
            model.ui.fleetDetailModal.directSubModal = true
        else:
          # Batch mode: act on all X-selected fleets
          model.ui.mode = ViewMode.FleetDetail
          model.resetBreadcrumbs(ViewMode.FleetDetail)
          model.ui.fleetDetailModal.subModal = FleetSubModal.ROEPicker
          model.ui.fleetDetailModal.fleetId = 0
          model.ui.fleetDetailModal.roeValue = 6
          model.ui.fleetDetailModal.directSubModal = true
    of ActionKind.fleetBatchZeroTurn:
      if model.ui.mode == ViewMode.Fleets:
        if model.ui.fleetViewMode == FleetViewMode.SystemView and
           model.ui.fleetConsoleFocus != FleetConsoleFocus.FleetsPane:
          discard  # No-op when system pane is focused
        # Cursor-implicit selection: if no X-selection exists, use cursor-row fleet
        elif model.ui.selectedFleetIds.len == 0:
          let fleetIdOpt = model.getCursorFleetId()
          if fleetIdOpt.isSome:
            let fleetId = fleetIdOpt.get()
            # Open FleetDetail modal in ZTCPicker sub-modal
            model.ui.mode = ViewMode.FleetDetail
            model.resetBreadcrumbs(ViewMode.FleetDetail)
            model.ui.fleetDetailModal.fleetId = fleetId
            model.ui.fleetDetailModal.subModal = FleetSubModal.ZTCPicker
            model.ui.fleetDetailModal.ztcIdx = 0
            model.ui.fleetDetailModal.ztcDigitBuffer = ""
            model.ui.fleetDetailModal.directSubModal = true
        else:
          # Batch mode: act on all X-selected fleets
          model.ui.mode = ViewMode.FleetDetail
          model.resetBreadcrumbs(ViewMode.FleetDetail)
          model.ui.fleetDetailModal.subModal = FleetSubModal.ZTCPicker
          model.ui.fleetDetailModal.fleetId = 0
          model.ui.fleetDetailModal.ztcIdx = 0
          model.ui.fleetDetailModal.ztcDigitBuffer = ""
          model.ui.fleetDetailModal.directSubModal = true
    else:
      model.ui.statusMessage = "Action: " & actionKindToStr(proposal.actionKind)
  of ProposalKind.pkSelection:
    if proposal.actionKind == ActionKind.lobbyEnterGame:
      if model.ui.lobbySelectedIdx < model.view.lobbyActiveGames.len:
        let game = model.view.lobbyActiveGames[model.ui.lobbySelectedIdx]
        model.ui.loadGameRequested = true
        model.ui.loadGameId = game.id
        model.ui.loadHouseId = game.houseId
        model.ui.statusMessage = "Loading game..."
        model.ui.lobbyInputMode = LobbyInputMode.None
    elif model.ui.mode == ViewMode.Reports and proposal.selectIdx == -1:
      model.ui.mode = ViewMode.ReportDetail
      let report = model.currentReport()
      if report.isSome:
        model.ui.selectedReportId = report.get().id
    elif model.ui.mode == ViewMode.Planets and proposal.selectIdx == -1:
      if model.ui.selectedIdx < 0 or
          model.ui.selectedIdx >= model.view.planetsRows.len:
        model.ui.statusMessage = "No colony selected"
      else:
        let row = model.view.planetsRows[model.ui.selectedIdx]
        if row.colonyId.isSome and row.isOwned:
          model.ui.previousMode = model.ui.mode
          model.ui.mode = ViewMode.PlanetDetail
          let colonyId = row.colonyId.get()
          model.ui.selectedColonyId = colonyId
          # Push breadcrumb with system name (colony at that location)
          model.pushBreadcrumb(row.systemName, ViewMode.PlanetDetail, colonyId)
        else:
          model.ui.statusMessage = "No colony selected"
    # NOTE: Fleet selection now handled by openFleetDetailModal action (Enter key)
    # Old ViewMode.FleetDetail inline view removed in favor of popup modal
    elif model.ui.mode == ViewMode.ReportDetail and proposal.selectIdx == -1:
      let report = model.currentReport()
      if report.isSome:
        let nextMode = viewModeFromInt(report.get().linkView)
        if nextMode.isSome:
          model.ui.previousMode = model.ui.mode
          model.ui.mode = nextMode.get()
          model.resetBreadcrumbs(model.ui.mode)
    else:
      discard
  else:
    discard


# ============================================================================
# Error Acceptor
# ============================================================================

proc errorAcceptor*(model: var TuiModel, proposal: Proposal) =
  ## Handle error proposals
  if proposal.kind == ProposalKind.pkError:
    model.ui.statusMessage = "Error: " & proposal.errorMsg

proc quitAcceptor*(model: var TuiModel, proposal: Proposal) =
  ## Handle quit proposals by showing confirmation
  if proposal.kind != ProposalKind.pkQuit:
    return
  model.ui.quitConfirmationActive = true
  model.ui.quitConfirmationChoice = QuitConfirmationChoice.QuitStay
  model.ui.statusMessage = "Quit? (Y/N)"

# ============================================================================
# Build Modal Acceptor
# ============================================================================

proc buildModalAcceptor*(model: var TuiModel, proposal: Proposal) =
  ## Handle build modal proposals
  if proposal.kind != ProposalKind.pkGameAction:
    return

  case proposal.actionKind
  of ActionKind.openBuildModal:
    # Open the build modal for the currently selected colony
    if model.ui.mode == ViewMode.PlanetDetail:
      model.ui.buildModal.active = true
      model.ui.buildModal.colonyId = model.ui.selectedColonyId
      model.ui.buildModal.category = BuildCategory.Ships
      model.ui.buildModal.focus = BuildModalFocus.BuildList
      model.ui.buildModal.selectedBuildIdx = 0
      model.ui.buildModal.selectedQueueIdx = 0
      model.ui.buildModal.pendingQueue = @[]
      model.ui.buildModal.quantityInput = 1
      # Note: availableOptions and dockSummary will be populated by the reactor
      model.ui.statusMessage = "Build modal opened"
  of ActionKind.closeBuildModal:
    model.ui.buildModal.active = false
    model.ui.buildModal.pendingQueue = @[]
    model.ui.statusMessage = "Build modal closed"
  of ActionKind.buildCategorySwitch:
    # Cycle through categories: Ships -> Facilities -> Ground -> Ships
    case model.ui.buildModal.category
    of BuildCategory.Ships:
      model.ui.buildModal.category = BuildCategory.Facilities
    of BuildCategory.Facilities:
      model.ui.buildModal.category = BuildCategory.Ground
    of BuildCategory.Ground:
      model.ui.buildModal.category = BuildCategory.Ships
    model.ui.buildModal.selectedBuildIdx = 0
    # Note: availableOptions will be refreshed by reactor
  of ActionKind.buildListUp:
    if model.ui.buildModal.focus == BuildModalFocus.BuildList:
      if model.ui.buildModal.selectedBuildIdx > 0:
        model.ui.buildModal.selectedBuildIdx -= 1
  of ActionKind.buildListDown:
    if model.ui.buildModal.focus == BuildModalFocus.BuildList:
      let maxIdx = model.ui.buildModal.availableOptions.len - 1
      if model.ui.buildModal.selectedBuildIdx < maxIdx:
        model.ui.buildModal.selectedBuildIdx += 1
    elif model.ui.buildModal.focus == BuildModalFocus.QueueList:
      if model.ui.buildModal.selectedQueueIdx > 0:
        model.ui.buildModal.selectedQueueIdx -= 1
  of ActionKind.buildQueueUp:
    if model.ui.buildModal.focus == BuildModalFocus.QueueList:
      if model.ui.buildModal.selectedQueueIdx > 0:
        model.ui.buildModal.selectedQueueIdx -= 1
  of ActionKind.buildQueueDown:
    if model.ui.buildModal.focus == BuildModalFocus.QueueList:
      let maxIdx = model.ui.buildModal.pendingQueue.len - 1
      if model.ui.buildModal.selectedQueueIdx < maxIdx:
        model.ui.buildModal.selectedQueueIdx += 1
  of ActionKind.buildFocusSwitch:
    # Toggle between BuildList and QueueList
    if model.ui.buildModal.focus == BuildModalFocus.BuildList:
      if model.ui.buildModal.pendingQueue.len > 0:
        model.ui.buildModal.focus = BuildModalFocus.QueueList
    else:
      model.ui.buildModal.focus = BuildModalFocus.BuildList
  of ActionKind.buildAddToQueue:
    # Add selected build option to pending queue
    if model.ui.buildModal.selectedBuildIdx < model.ui.buildModal.availableOptions.len:
      let option = model.ui.buildModal.availableOptions[model.ui.buildModal.selectedBuildIdx]
      var buildItem = PendingBuildItem(
        name: option.name,
        cost: option.cost,
        quantity: model.ui.buildModal.quantityInput
      )

      # Set build type and class based on option kind
      case option.kind
      of BuildOptionKind.Ship:
        buildItem.buildType = BuildType.Ship
        # Parse ship class from name
        try:
          buildItem.shipClass = some(parseEnum[ShipClass](option.name.replace(" ", "")))
        except:
          # If parsing fails, skip this item
          model.ui.statusMessage = "Failed to parse ship class: " & option.name
          return
      of BuildOptionKind.Facility:
        buildItem.buildType = BuildType.Facility
        buildItem.quantity = 1  # Facilities are always quantity 1
        # Parse facility class from name
        try:
          buildItem.facilityClass = some(parseEnum[FacilityClass](option.name.replace(" ", "")))
        except:
          model.ui.statusMessage = "Failed to parse facility class: " & option.name
          return
      of BuildOptionKind.Ground:
        buildItem.buildType = BuildType.Ground
        buildItem.quantity = 1  # Ground units are always quantity 1
        # Parse ground class from name
        try:
          buildItem.groundClass = some(parseEnum[GroundClass](option.name.replace(" ", "")))
        except:
          model.ui.statusMessage = "Failed to parse ground class: " & option.name
          return

      model.ui.buildModal.pendingQueue.add(buildItem)
      model.ui.statusMessage = "Added " & option.name & " to queue"
  of ActionKind.buildRemoveFromQueue:
    # Remove selected item from pending queue
    if model.ui.buildModal.focus == BuildModalFocus.QueueList and
       model.ui.buildModal.selectedQueueIdx < model.ui.buildModal.pendingQueue.len:
      let item = model.ui.buildModal.pendingQueue[model.ui.buildModal.selectedQueueIdx]
      model.ui.buildModal.pendingQueue.delete(model.ui.buildModal.selectedQueueIdx)
      model.ui.statusMessage = "Removed " & item.name & " from queue"
      # Adjust selection if needed
      if model.ui.buildModal.selectedQueueIdx >= model.ui.buildModal.pendingQueue.len:
        model.ui.buildModal.selectedQueueIdx = max(0, model.ui.buildModal.pendingQueue.len - 1)
      # Switch focus back to build list if queue is now empty
      if model.ui.buildModal.pendingQueue.len == 0:
        model.ui.buildModal.focus = BuildModalFocus.BuildList
  of ActionKind.buildConfirmQueue:
    # Convert pending queue to staged build commands
    for item in model.ui.buildModal.pendingQueue:
      let cmd = BuildCommand(
        colonyId: ColonyId(model.ui.buildModal.colonyId),
        buildType: item.buildType,
        quantity: int32(item.quantity),
        shipClass: item.shipClass,
        facilityClass: item.facilityClass,
        groundClass: item.groundClass,
        industrialUnits: 0
      )
      model.ui.stagedBuildCommands.add(cmd)

    let count = model.ui.buildModal.pendingQueue.len
    model.ui.statusMessage = "Staged " & $count & " build command(s)"
    model.ui.buildModal.active = false
    model.ui.buildModal.pendingQueue = @[]
  of ActionKind.buildQuantityInc:
    # Only for ships
    if model.ui.buildModal.category == BuildCategory.Ships:
      if model.ui.buildModal.quantityInput < 99:
        model.ui.buildModal.quantityInput += 1
  of ActionKind.buildQuantityDec:
    # Only for ships
    if model.ui.buildModal.category == BuildCategory.Ships:
      if model.ui.buildModal.quantityInput > 1:
        model.ui.buildModal.quantityInput -= 1
  else:
    discard

# ============================================================================
# Fleet Detail Modal Acceptor
# ============================================================================

proc fleetDetailModalAcceptor*(model: var TuiModel, proposal: Proposal) =
  ## Handle fleet detail modal interactions
  case proposal.actionKind
  of ActionKind.openFleetDetailModal:
    # Open fleet detail view for selected fleet
    if model.ui.mode == ViewMode.Fleets and model.ui.fleetViewMode == FleetViewMode.SystemView:
      # SystemView: Get fleet from cached console data
      let systems = model.ui.fleetConsoleSystems
      if systems.len > 0:
        let sysIdx = clamp(model.ui.fleetConsoleSystemIdx, 0, systems.len - 1)
        let systemId = systems[sysIdx].systemId
        # Get fleets for that system
        if model.ui.fleetConsoleFleetsBySystem.hasKey(systemId):
          let fleets = model.ui.fleetConsoleFleetsBySystem[systemId]
          let fleetIdx = model.ui.fleetConsoleFleetIdx
          if fleetIdx >= 0 and fleetIdx < fleets.len:
            let fleetId = fleets[fleetIdx].fleetId
            let fleetName = fleets[fleetIdx].name
            # Transition to FleetDetail ViewMode with breadcrumb
            model.ui.mode = ViewMode.FleetDetail
            model.pushBreadcrumb("Fleet " & fleetName, ViewMode.FleetDetail, fleetId)
            # Initialize fleet detail state
            model.ui.fleetDetailModal.fleetId = fleetId
            model.ui.fleetDetailModal.subModal = FleetSubModal.None
            model.ui.fleetDetailModal.commandCategory = CommandCategory.Movement
            model.ui.fleetDetailModal.commandIdx = 0
            model.ui.fleetDetailModal.roeValue = 6  # Standard
            model.ui.fleetDetailModal.confirmPending = false
            model.ui.fleetDetailModal.confirmMessage = ""
            model.ui.fleetDetailModal.pendingCommandType = FleetCommandType.Hold
            model.ui.fleetDetailModal.shipScroll = initScrollState()
            model.ui.fleetDetailModal.shipCount = fleets[fleetIdx].shipCount
            model.ui.fleetDetailModal.fleetPickerCandidates = @[]
            model.ui.fleetDetailModal.fleetPickerIdx = 0
            model.ui.fleetDetailModal.fleetPickerScroll = initScrollState()
            model.ui.fleetDetailModal.directSubModal = false
            discard model.updateFleetDetailScroll()
            model.ui.statusMessage = "Fleet detail opened"
          else:
            model.ui.statusMessage = "No fleet selected"
        else:
          model.ui.statusMessage = "No fleets at this system"
      else:
        model.ui.statusMessage = "No systems with fleets"
    elif model.ui.mode == ViewMode.Fleets and model.ui.fleetViewMode == FleetViewMode.ListView:
      # ListView: Get fleet from filtered list
      let fleets = model.filteredFleets()
      if model.ui.selectedIdx < fleets.len:
        let fleet = fleets[model.ui.selectedIdx]
        let fleetId = fleet.id
        # Transition to FleetDetail ViewMode with breadcrumb
        model.ui.mode = ViewMode.FleetDetail
        model.pushBreadcrumb("Fleet " & fleet.name, ViewMode.FleetDetail, fleetId)
        # Initialize fleet detail state
        model.ui.fleetDetailModal.fleetId = fleetId
        model.ui.fleetDetailModal.subModal = FleetSubModal.None
        model.ui.fleetDetailModal.commandCategory = CommandCategory.Movement
        model.ui.fleetDetailModal.commandIdx = 0
        model.ui.fleetDetailModal.roeValue = fleet.roe  # Use actual fleet ROE
        model.ui.fleetDetailModal.confirmPending = false
        model.ui.fleetDetailModal.confirmMessage = ""
        model.ui.fleetDetailModal.pendingCommandType = FleetCommandType.Hold
        model.ui.fleetDetailModal.shipScroll = initScrollState()
        model.ui.fleetDetailModal.shipCount = fleet.shipCount
        model.ui.fleetDetailModal.fleetPickerCandidates = @[]
        model.ui.fleetDetailModal.fleetPickerIdx = 0
        model.ui.fleetDetailModal.fleetPickerScroll = initScrollState()
        model.ui.fleetDetailModal.directSubModal = false
        discard model.updateFleetDetailScroll()
        model.ui.statusMessage = "Fleet detail opened"
  of ActionKind.closeFleetDetailModal:
    # Close fleet detail view (only if no sub-modal active)
    if model.ui.fleetDetailModal.subModal == FleetSubModal.None:
      # Always navigate back to Fleets view
      resetFleetDetailSubModal(model)
      model.ui.mode = ViewMode.Fleets
      model.resetBreadcrumbs(ViewMode.Fleets)
      model.ui.statusMessage = ""
  of ActionKind.fleetDetailNextCategory:
    # DEPRECATED: Category navigation removed, now using flat list
    discard
  of ActionKind.fleetDetailPrevCategory:
    # DEPRECATED: Category navigation removed, now using flat list
    discard
  of ActionKind.fleetDetailListUp:
    if model.ui.fleetDetailModal.subModal == FleetSubModal.CommandPicker:
      # Navigate filtered command list
      if model.ui.fleetDetailModal.commandIdx > 0:
        model.ui.fleetDetailModal.commandIdx -= 1
        model.ui.fleetDetailModal.commandDigitBuffer = ""  # Clear digit buffer on navigation
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.ROEPicker:
      if model.ui.fleetDetailModal.roeValue > 0:
        model.ui.fleetDetailModal.roeValue -= 1  # Up decreases value (moves toward 0)
        model.ui.fleetDetailModal.commandDigitBuffer = ""  # Clear digit buffer on navigation
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.ZTCPicker:
      if model.ui.fleetDetailModal.ztcIdx > 0:
        model.ui.fleetDetailModal.ztcIdx -= 1
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.FleetPicker:
      if model.ui.fleetDetailModal.fleetPickerIdx > 0:
        model.ui.fleetDetailModal.fleetPickerIdx -= 1
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.SystemPicker:
      if model.ui.fleetDetailModal.systemPickerIdx > 0:
        model.ui.fleetDetailModal.systemPickerIdx -= 1
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.None:
      discard model.updateFleetDetailScroll()
      let scroll = model.ui.fleetDetailModal.shipScroll
      model.ui.fleetDetailModal.shipScroll.verticalOffset = max(0,
        scroll.verticalOffset - 1)
  of ActionKind.fleetDetailListDown:
    if model.ui.fleetDetailModal.subModal == FleetSubModal.CommandPicker:
      # Navigate filtered command list
      let maxIdx =
        model.ui.fleetDetailModal.commandPickerCommands.len - 1
      if maxIdx >= 0 and
          model.ui.fleetDetailModal.commandIdx < maxIdx:
        model.ui.fleetDetailModal.commandIdx += 1
        model.ui.fleetDetailModal.commandDigitBuffer = ""  # Clear digit buffer on navigation
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.ROEPicker:
      if model.ui.fleetDetailModal.roeValue < 10:
        model.ui.fleetDetailModal.roeValue += 1  # Down increases value (moves toward 10)
        model.ui.fleetDetailModal.commandDigitBuffer = ""  # Clear digit buffer on navigation
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.ZTCPicker:
      let maxZtc = allZeroTurnCommands().len - 1  # 8 (indices 0-8)
      if model.ui.fleetDetailModal.ztcIdx < maxZtc:
        model.ui.fleetDetailModal.ztcIdx += 1
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.FleetPicker:
      let maxIdx = model.ui.fleetDetailModal.fleetPickerCandidates.len - 1
      if model.ui.fleetDetailModal.fleetPickerIdx < maxIdx:
        model.ui.fleetDetailModal.fleetPickerIdx += 1
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.SystemPicker:
      let maxIdx = model.ui.fleetDetailModal.systemPickerSystems.len - 1
      if model.ui.fleetDetailModal.systemPickerIdx < maxIdx:
        model.ui.fleetDetailModal.systemPickerIdx += 1
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.None:
      let (_, maxOffset) = model.updateFleetDetailScroll()
      let scroll = model.ui.fleetDetailModal.shipScroll
      model.ui.fleetDetailModal.shipScroll.verticalOffset = min(maxOffset,
        scroll.verticalOffset + 1)
  of ActionKind.fleetDetailSelectCommand:
    if model.ui.fleetDetailModal.subModal == FleetSubModal.CommandPicker:
      # Check if there's a pending single digit - map to command code
      if model.ui.fleetDetailModal.commandDigitBuffer.len == 1:
        let digit = model.ui.fleetDetailModal.commandDigitBuffer[0]
        if digit >= '0' and digit <= '9':
          let cmdNum = parseInt("0" & $digit)
          let commands =
            model.ui.fleetDetailModal.commandPickerCommands
          let idx = commandIndexForCode(commands, cmdNum)
          if idx >= 0:
            model.ui.fleetDetailModal.commandIdx = idx
          model.ui.fleetDetailModal.commandDigitBuffer = ""
          # Fall through to select the command
      
      let commands = model.ui.fleetDetailModal.commandPickerCommands
      let idx = model.ui.fleetDetailModal.commandIdx
      
      if idx >= 0 and idx < commands.len:
        let cmdType = commands[idx]

        # Batch command for selected fleets
        if model.ui.selectedFleetIds.len > 0:
          if cmdType == FleetCommandType.JoinFleet:
            model.ui.statusMessage = "JoinFleet: use single fleet mode"
            return
          # Validate all fleets in batch meet command requirements
          for fleetId in model.ui.selectedFleetIds:
            for fleet in model.view.fleets:
              if fleet.id == fleetId:
                let err = validateFleetCommand(fleet, cmdType)
                if err.len > 0:
                  model.ui.statusMessage = $cmdType & ": " & err &
                    " (fleet " & fleet.name & ")"
                  return
          # Hold: auto-target each fleet's current location
          if int(cmdType) == CmdHold:
            for fleetId in model.ui.selectedFleetIds:
              var loc = 0
              for fleet in model.view.fleets:
                if fleet.id == fleetId:
                  loc = fleet.location
                  break
              let cmd = FleetCommand(
                fleetId: FleetId(fleetId),
                commandType: cmdType,
                targetSystem: some(SystemId(loc.uint32)),
                targetFleet: none(FleetId),
                roe: some(int32(
                  model.ui.fleetDetailModal.roeValue))
              )
              model.stageFleetCommand(cmd)
            model.ui.statusMessage = "Staged " &
              $model.ui.selectedFleetIds.len &
              " Hold command(s)"
            resetFleetDetailSubModal(model)
            model.ui.mode = ViewMode.Fleets
            model.resetBreadcrumbs(ViewMode.Fleets)
            return
          # SeekHome: auto-target nearest drydock colony
          if int(cmdType) == CmdSeekHome:
            for fleetId in model.ui.selectedFleetIds:
              var target = none(int)
              for fleet in model.view.fleets:
                if fleet.id == fleetId:
                  target = fleet.seekHomeTarget
                  break
              if target.isNone:
                model.ui.statusMessage =
                  "SeekHome: no friendly colony found"
                return
              let cmd = FleetCommand(
                fleetId: FleetId(fleetId),
                commandType: cmdType,
                targetSystem: some(
                  SystemId(target.get().uint32)),
                targetFleet: none(FleetId),
                roe: some(int32(
                  model.ui.fleetDetailModal.roeValue))
              )
              model.stageFleetCommand(cmd)
            model.ui.statusMessage = "Staged " &
              $model.ui.selectedFleetIds.len &
              " Seek Home command(s)"
            resetFleetDetailSubModal(model)
            model.ui.mode = ViewMode.Fleets
            model.resetBreadcrumbs(ViewMode.Fleets)
            return
          if needsTargetSystem(int(cmdType)):
            # Open SystemPicker sub-modal for batch
            model.openSystemPickerForCommand(
              cmdType,
              FleetSubModal.CommandPicker
            )
            return
          for fleetId in model.ui.selectedFleetIds:
            let cmd = FleetCommand(
              fleetId: FleetId(fleetId),
              commandType: cmdType,
              targetSystem: none(SystemId),
              targetFleet: none(FleetId),
              roe: some(int32(model.ui.fleetDetailModal.roeValue))
            )
            model.stageFleetCommand(cmd)
          model.ui.statusMessage = "Staged " & $model.ui.selectedFleetIds.len &
            " fleet command(s)"
          resetFleetDetailSubModal(model)
          model.ui.mode = ViewMode.Fleets
          model.resetBreadcrumbs(ViewMode.Fleets)
          return
        
        # Look up fleet and validate command requirements
        var currentFleet: Option[FleetInfo]
        for fleet in model.view.fleets:
          if fleet.id == model.ui.fleetDetailModal.fleetId:
            currentFleet = some(fleet)
            break
        if currentFleet.isNone:
          model.ui.statusMessage = "Fleet not found"
          resetFleetDetailSubModal(model)
          return
        let current = currentFleet.get()
        let err = validateFleetCommand(current, cmdType)
        if err.len > 0:
          model.ui.statusMessage = $cmdType & ": " & err
          return
        
        # Hold: auto-target fleet's current location
        if int(cmdType) == CmdHold:
          let cmd = FleetCommand(
            fleetId: FleetId(current.id),
            commandType: cmdType,
            targetSystem: some(
              SystemId(current.location.uint32)),
            targetFleet: none(FleetId),
            roe: some(int32(
              model.ui.fleetDetailModal.roeValue))
          )
          model.stageFleetCommand(cmd)
          model.ui.statusMessage = "Staged command: Hold"
          resetFleetDetailSubModal(model)
          model.ui.mode = ViewMode.Fleets
          model.resetBreadcrumbs(ViewMode.Fleets)
          return
        # SeekHome: auto-target nearest drydock colony
        if int(cmdType) == CmdSeekHome:
          if current.seekHomeTarget.isNone:
            model.ui.statusMessage =
              "SeekHome: no friendly colony found"
            return
          let cmd = FleetCommand(
            fleetId: FleetId(current.id),
            commandType: cmdType,
            targetSystem: some(
              SystemId(current.seekHomeTarget.get().uint32)),
            targetFleet: none(FleetId),
            roe: some(int32(
              model.ui.fleetDetailModal.roeValue))
          )
          model.stageFleetCommand(cmd)
          model.ui.statusMessage = "Staged command: Seek Home"
          resetFleetDetailSubModal(model)
          model.ui.mode = ViewMode.Fleets
          model.resetBreadcrumbs(ViewMode.Fleets)
          return
        
        if cmdType == FleetCommandType.JoinFleet:
          model.ui.fleetDetailModal.fleetPickerCandidates = @[]
          for fleet in model.view.fleets:
            if fleet.id == current.id:
              continue
            if fleet.location == current.location and
                fleet.owner == current.owner:
              model.ui.fleetDetailModal.fleetPickerCandidates.add(
                FleetConsoleFleet(
                  fleetId: fleet.id,
                  name: fleet.name,
                  shipCount: fleet.shipCount,
                  attackStrength: fleet.attackStrength,
                  defenseStrength: fleet.defenseStrength,
                  troopTransports: 0,
                  etacs: 0,
                  commandLabel: fleet.commandLabel,
                  destinationLabel: fleet.destinationLabel,
                  eta: fleet.eta,
                  roe: fleet.roe,
                  status: fleet.statusLabel
                )
              )
          if model.ui.fleetDetailModal.fleetPickerCandidates.len == 0:
            model.ui.statusMessage = "JoinFleet: no fleets at system"
            resetFleetDetailSubModal(model)
            return
          model.ui.fleetDetailModal.fleetPickerIdx = 0
          model.ui.fleetDetailModal.subModal = FleetSubModal.FleetPicker
          return

        # Check if command requires target system selection
        if needsTargetSystem(int(cmdType)):
          # Open SystemPicker sub-modal for single fleet
          model.openSystemPickerForCommand(
            cmdType,
            FleetSubModal.CommandPicker
          )
        else:
          # Stage command immediately (no target needed)
          let cmd = FleetCommand(
            fleetId: FleetId(model.ui.fleetDetailModal.fleetId),
            commandType: cmdType,
            targetSystem: none(SystemId),
            targetFleet: none(FleetId),
            roe: some(int32(model.ui.fleetDetailModal.roeValue))
          )
          model.stageFleetCommand(cmd)
          model.ui.statusMessage = "Staged command: " & $cmdType
          resetFleetDetailSubModal(model)
          model.ui.mode = ViewMode.Fleets
          model.resetBreadcrumbs(ViewMode.Fleets)
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.ZTCPicker:
      # Select ZTC from the picker
      let ztcCommands = allZeroTurnCommands()
      let idx = model.ui.fleetDetailModal.ztcIdx
      if idx >= 0 and idx < ztcCommands.len:
        let ztcType = ztcCommands[idx]
        case ztcType
        of ZeroTurnCommandType.Reactivate:
          # Reactivate requires no sub-modal, stage immediately
          model.ui.statusMessage = "ZTC Reactivate - staged (placeholder)"
          model.ui.fleetDetailModal.subModal = FleetSubModal.None
        of ZeroTurnCommandType.DetachShips, ZeroTurnCommandType.TransferShips:
          # Need ship selection - placeholder
          model.ui.fleetDetailModal.subModal = FleetSubModal.ShipSelector
        of ZeroTurnCommandType.MergeFleets:
          # Need fleet selection - placeholder
          model.ui.fleetDetailModal.subModal = FleetSubModal.FleetPicker
        of ZeroTurnCommandType.LoadCargo, ZeroTurnCommandType.UnloadCargo:
          # Need cargo params - placeholder
          model.ui.fleetDetailModal.subModal = FleetSubModal.CargoParams
        of ZeroTurnCommandType.LoadFighters, ZeroTurnCommandType.UnloadFighters,
           ZeroTurnCommandType.TransferFighters:
          # Need fighter params - placeholder
          model.ui.fleetDetailModal.subModal = FleetSubModal.FighterParams
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.FleetPicker:
      let candidates = model.ui.fleetDetailModal.fleetPickerCandidates
      let idx = model.ui.fleetDetailModal.fleetPickerIdx
      if idx >= 0 and idx < candidates.len:
        let target = candidates[idx]
        let cmd = FleetCommand(
          fleetId: FleetId(model.ui.fleetDetailModal.fleetId),
          commandType: FleetCommandType.JoinFleet,
          targetSystem: none(SystemId),
          targetFleet: some(FleetId(target.fleetId)),
          roe: some(int32(model.ui.fleetDetailModal.roeValue))
        )
        model.stageFleetCommand(cmd)
        model.ui.statusMessage = "Staged JoinFleet: " & target.name
        resetFleetDetailSubModal(model)
        model.ui.mode = ViewMode.Fleets
        model.resetBreadcrumbs(ViewMode.Fleets)
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.SystemPicker:
      let systems = model.ui.fleetDetailModal.systemPickerSystems
      let idx = model.ui.fleetDetailModal.systemPickerIdx
      if idx >= 0 and idx < systems.len:
        let target = systems[idx]
        let cmdType = model.ui.fleetDetailModal.systemPickerCommandType
        # Validate target for starbase/colony-specific commands
        case cmdType
        of FleetCommandType.GuardStarbase:
          var hasStarbase = false
          for row in model.view.planetsRows:
            if row.systemId == target.systemId and row.isOwned and
                row.starbaseCount > 0:
              hasStarbase = true
              break
          if not hasStarbase:
            model.ui.statusMessage =
              "No friendly starbase in that system"
            return
        of FleetCommandType.GuardColony:
          var hasColony = false
          for row in model.view.planetsRows:
            if row.systemId == target.systemId and row.isOwned:
              hasColony = true
              break
          if not hasColony:
            model.ui.statusMessage =
              "No friendly colony in that system"
            return
        of FleetCommandType.HackStarbase:
          var hasKnownStarbase = false
          for row in model.view.intelRows:
            if row.systemId == target.systemId and
                row.starbaseCount.isSome and
                row.starbaseCount.get > 0:
              hasKnownStarbase = true
              break
          if not hasKnownStarbase:
            model.ui.statusMessage =
              "No known starbase in that system"
            return
        else:
          discard
        # Stage command for batch or single fleet
        if model.ui.selectedFleetIds.len > 0:
          for fleetId in model.ui.selectedFleetIds:
            let cmd = FleetCommand(
              fleetId: FleetId(fleetId),
              commandType: cmdType,
              targetSystem: some(
                SystemId(target.systemId.uint32)),
              targetFleet: none(FleetId),
              roe: some(int32(
                model.ui.fleetDetailModal.roeValue))
            )
            model.stageFleetCommand(cmd)
          model.ui.statusMessage = "Staged " &
            $model.ui.selectedFleetIds.len & " " &
            $cmdType & " to " & target.coordLabel
        else:
          let cmd = FleetCommand(
            fleetId: FleetId(
              model.ui.fleetDetailModal.fleetId),
            commandType: cmdType,
            targetSystem: some(
              SystemId(target.systemId.uint32)),
            targetFleet: none(FleetId),
            roe: some(int32(
              model.ui.fleetDetailModal.roeValue))
          )
          model.stageFleetCommand(cmd)
          model.ui.statusMessage = "Staged " &
            $cmdType & " to " & target.coordLabel
        resetFleetDetailSubModal(model)
        model.ui.mode = ViewMode.Fleets
        model.resetBreadcrumbs(ViewMode.Fleets)
  of ActionKind.fleetDetailOpenROE:
    if model.ui.fleetDetailModal.subModal == FleetSubModal.None:
      model.ui.fleetDetailModal.subModal = FleetSubModal.ROEPicker
      model.ui.fleetDetailModal.directSubModal = false
  of ActionKind.fleetDetailCloseROE:
    if model.ui.fleetDetailModal.subModal == FleetSubModal.ROEPicker:
      model.ui.fleetDetailModal.subModal = FleetSubModal.None
  of ActionKind.fleetDetailROEUp:
    if model.ui.fleetDetailModal.subModal == FleetSubModal.ROEPicker:
      if model.ui.fleetDetailModal.roeValue < 10:
        model.ui.fleetDetailModal.roeValue += 1
  of ActionKind.fleetDetailROEDown:
    if model.ui.fleetDetailModal.subModal == FleetSubModal.ROEPicker:
      if model.ui.fleetDetailModal.roeValue > 0:
        model.ui.fleetDetailModal.roeValue -= 1
  of ActionKind.fleetDetailSelectROE:
    if model.ui.fleetDetailModal.subModal == FleetSubModal.ROEPicker:
      model.ui.fleetDetailModal.subModal = FleetSubModal.None
      let newRoe = model.ui.fleetDetailModal.roeValue
      if model.ui.selectedFleetIds.len > 0:
        # Batch: update ROE on each fleet, preserving
        # whatever command is already staged or active.
        for fleetId in model.ui.selectedFleetIds:
          model.updateStagedROE(fleetId, newRoe)
        model.ui.statusMessage = "Staged ROE " &
          $newRoe & " for " &
          $model.ui.selectedFleetIds.len & " fleets"
        model.ui.mode = ViewMode.Fleets
        model.resetBreadcrumbs(ViewMode.Fleets)
      else:
        # Single fleet: update ROE, preserve command.
        model.updateStagedROE(
          model.ui.fleetDetailModal.fleetId, newRoe)
        model.ui.statusMessage = "Staged ROE " &
          $newRoe
        resetFleetDetailSubModal(model)
        model.ui.mode = ViewMode.Fleets
        model.resetBreadcrumbs(ViewMode.Fleets)
  of ActionKind.fleetDetailOpenZTC:
    if model.ui.fleetDetailModal.subModal == FleetSubModal.None:
      model.ui.fleetDetailModal.subModal = FleetSubModal.ZTCPicker
      model.ui.fleetDetailModal.ztcIdx = 0
      model.ui.fleetDetailModal.ztcDigitBuffer = ""
      model.ui.fleetDetailModal.directSubModal = false
  of ActionKind.fleetDetailSelectZTC:
    # Reserved for future use (direct ZTC selection from detail view)
    discard
  of ActionKind.fleetDetailConfirm:
    if model.ui.fleetDetailModal.subModal == FleetSubModal.ConfirmPrompt:
      # User confirmed destructive action
      let cmdType = model.ui.fleetDetailModal.pendingCommandType
      
      # Check if the confirmed command also requires a target
      if needsTargetSystem(int(cmdType)):
        # Open SystemPicker sub-modal for target selection
        model.openSystemPickerForCommand(
          cmdType,
          FleetSubModal.CommandPicker
        )
        return
      
      # Command doesn't need target, stage immediately
      if model.ui.selectedFleetIds.len > 0:
        for fleetId in model.ui.selectedFleetIds:
          let cmd = FleetCommand(
            fleetId: FleetId(fleetId),
            commandType: cmdType,
            targetSystem: none(SystemId),
            targetFleet: none(FleetId),
            roe: some(int32(model.ui.fleetDetailModal.roeValue))
          )
          model.stageFleetCommand(cmd)
        model.ui.statusMessage = "Staged " & $model.ui.selectedFleetIds.len &
          " fleet command(s)"
        resetFleetDetailSubModal(model)
        model.ui.mode = ViewMode.Fleets
        model.resetBreadcrumbs(ViewMode.Fleets)
        return
      let cmd = FleetCommand(
        fleetId: FleetId(model.ui.fleetDetailModal.fleetId),
        commandType: cmdType,
        targetSystem: none(SystemId),
        targetFleet: none(FleetId),
        roe: some(int32(model.ui.fleetDetailModal.roeValue))
      )
      model.stageFleetCommand(cmd)
      model.ui.statusMessage = "Staged command: " & $cmdType
      resetFleetDetailSubModal(model)
      model.ui.mode = ViewMode.Fleets
      model.resetBreadcrumbs(ViewMode.Fleets)
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.None:
      # C key from main detail view - open command picker
      model.openCommandPicker()
      model.ui.fleetDetailModal.directSubModal = false
  of ActionKind.fleetDetailCancel:
    if model.ui.fleetDetailModal.subModal == FleetSubModal.ConfirmPrompt:
      # Cancel confirmation, go back to main detail view
      resetFleetDetailSubModal(model)
      model.ui.statusMessage = "Action cancelled"
    elif model.ui.fleetDetailModal.subModal ==
        FleetSubModal.NoticePrompt:
      let returnSubModal =
        model.ui.fleetDetailModal.noticeReturnSubModal
      model.ui.fleetDetailModal.noticeMessage = ""
      model.ui.fleetDetailModal.noticeReturnSubModal =
        FleetSubModal.None
      model.ui.fleetDetailModal.subModal = returnSubModal
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.CommandPicker:
      if model.ui.fleetDetailModal.directSubModal:
        # Opened directly via C from fleet list — close entire modal
        resetFleetDetailSubModal(model)
        model.ui.mode = ViewMode.Fleets
        model.resetBreadcrumbs(ViewMode.Fleets)
        model.ui.statusMessage = ""
      else:
        # Cancel command picker, go back to main detail view
        model.ui.fleetDetailModal.subModal = FleetSubModal.None
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.ROEPicker:
      if model.ui.fleetDetailModal.directSubModal:
        # Opened directly via R from fleet list — close entire modal
        resetFleetDetailSubModal(model)
        model.ui.mode = ViewMode.Fleets
        model.resetBreadcrumbs(ViewMode.Fleets)
        model.ui.statusMessage = ""
      else:
        # Cancel ROE picker, go back to main detail view
        model.ui.fleetDetailModal.subModal = FleetSubModal.None
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.ZTCPicker:
      if model.ui.fleetDetailModal.directSubModal:
        # Opened directly via Z from fleet list — close entire modal
        resetFleetDetailSubModal(model)
        model.ui.mode = ViewMode.Fleets
        model.resetBreadcrumbs(ViewMode.Fleets)
        model.ui.statusMessage = ""
      else:
        # Cancel ZTC picker, go back to main detail view
        model.ui.fleetDetailModal.subModal = FleetSubModal.None
    elif model.ui.fleetDetailModal.subModal in {FleetSubModal.ShipSelector,
        FleetSubModal.CargoParams, FleetSubModal.FighterParams}:
      # Cancel placeholder sub-modal, go back to ZTC picker
      model.ui.fleetDetailModal.subModal = FleetSubModal.ZTCPicker
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.SystemPicker:
      # Cancel system picker, go back to command picker
      model.ui.fleetDetailModal.systemPickerSystems = @[]
      model.ui.fleetDetailModal.systemPickerFilter = ""
      model.ui.fleetDetailModal.subModal = FleetSubModal.CommandPicker
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.FleetPicker:
      # Cancel fleet picker (from ZTC Merge), go back to ZTC picker
      model.ui.fleetDetailModal.subModal = FleetSubModal.ZTCPicker
    else:
      # Fallback: treat cancel as close when no sub-modal is active
      # Always navigate back to Fleets view
      resetFleetDetailSubModal(model)
      model.ui.mode = ViewMode.Fleets
      model.resetBreadcrumbs(ViewMode.Fleets)
      model.ui.statusMessage = ""
  of ActionKind.fleetDetailPageUp:
    if model.ui.fleetDetailModal.subModal == FleetSubModal.None:
      let (pageSize, _) = model.updateFleetDetailScroll()
      let scroll = model.ui.fleetDetailModal.shipScroll
      model.ui.fleetDetailModal.shipScroll.verticalOffset = max(0,
        scroll.verticalOffset - pageSize)
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.SystemPicker:
      let pageSize = 20  # Match max visible rows
      model.ui.fleetDetailModal.systemPickerIdx = max(0,
        model.ui.fleetDetailModal.systemPickerIdx - pageSize)
  of ActionKind.fleetDetailPageDown:
    if model.ui.fleetDetailModal.subModal == FleetSubModal.None:
      let (pageSize, maxOffset) = model.updateFleetDetailScroll()
      let scroll = model.ui.fleetDetailModal.shipScroll
      model.ui.fleetDetailModal.shipScroll.verticalOffset = min(maxOffset,
        scroll.verticalOffset + pageSize)
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.SystemPicker:
      let pageSize = 20  # Match max visible rows
      let maxIdx = model.ui.fleetDetailModal.systemPickerSystems.len - 1
      model.ui.fleetDetailModal.systemPickerIdx = min(maxIdx,
        model.ui.fleetDetailModal.systemPickerIdx + pageSize)
  of ActionKind.fleetDetailDigitInput:
    if model.ui.fleetDetailModal.subModal == FleetSubModal.CommandPicker:
      # Handle two-digit quick entry for command selection (00-19)
      if proposal.kind == ProposalKind.pkGameAction:
        let digit = if proposal.gameActionData.len > 0:
          proposal.gameActionData[0] else: '\0'
        if digit >= '0' and digit <= '9':
          let now = epochTime()
          let buffer = model.ui.fleetDetailModal.commandDigitBuffer
          let lastTime = model.ui.fleetDetailModal.commandDigitTime
          let commands =
            model.ui.fleetDetailModal.commandPickerCommands
          
          if buffer.len == 1 and (now - lastTime) < DigitBufferTimeout:
            # Second digit - combine with first to get command code
            let cmdNum = parseInt(buffer & $digit)
            let idx = commandIndexForCode(commands, cmdNum)
            if idx >= 0:
              model.ui.fleetDetailModal.commandIdx = idx
            model.ui.fleetDetailModal.commandDigitBuffer = ""
          else:
            # First digit - jump immediately and wait for second
            let cmdNum = parseInt($digit)
            let idx = commandIndexForCode(commands, cmdNum)
            if idx >= 0:
              model.ui.fleetDetailModal.commandIdx = idx
            model.ui.fleetDetailModal.commandDigitBuffer = $digit
            model.ui.fleetDetailModal.commandDigitTime = now
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.ROEPicker:
      # Direct digit entry for ROE Picker (0-10) — jump only, Enter to confirm
      if proposal.kind == ProposalKind.pkGameAction:
        let ch = if proposal.gameActionData.len > 0: proposal.gameActionData[0] else: '\0'
        if ch >= '0' and ch <= '9':
          let digit = parseInt($ch)
          let now = epochTime()
          let buffer = model.ui.fleetDetailModal.commandDigitBuffer
          let lastTime = model.ui.fleetDetailModal.commandDigitTime
          
          if buffer.len == 1 and (now - lastTime) < DigitBufferTimeout:
            # Two digits: form number like "10"
            let roeNum = parseInt(buffer & $ch)
            if roeNum >= 0 and roeNum <= 10:
              model.ui.fleetDetailModal.roeValue = roeNum
            model.ui.fleetDetailModal.commandDigitBuffer = ""
          elif digit == 1:
            # First digit is '1' - jump immediately, wait for second digit for "10"
            model.ui.fleetDetailModal.roeValue = 1
            model.ui.fleetDetailModal.commandDigitBuffer = $ch
            model.ui.fleetDetailModal.commandDigitTime = now
          else:
            # Single digit 0, 2-9: jump to that ROE value
            model.ui.fleetDetailModal.roeValue = digit
            model.ui.fleetDetailModal.commandDigitBuffer = ""
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.ZTCPicker:
      # Single-digit quick entry for ZTC (1-9)
      if proposal.kind == ProposalKind.pkGameAction:
        let ch = if proposal.gameActionData.len > 0: proposal.gameActionData[0] else: '\0'
        if ch >= '1' and ch <= '9':
          let ztcNum = parseInt($ch) - 1  # Convert 1-9 to index 0-8
          let ztcCommands = allZeroTurnCommands()
          if ztcNum >= 0 and ztcNum < ztcCommands.len:
            model.ui.fleetDetailModal.ztcIdx = ztcNum
            # Auto-select: route same as Enter on ZTCPicker
            let ztcType = ztcCommands[ztcNum]
            case ztcType
            of ZeroTurnCommandType.Reactivate:
              model.ui.statusMessage = "ZTC Reactivate - staged (placeholder)"
              model.ui.fleetDetailModal.subModal = FleetSubModal.None
            of ZeroTurnCommandType.DetachShips, ZeroTurnCommandType.TransferShips:
              model.ui.fleetDetailModal.subModal = FleetSubModal.ShipSelector
            of ZeroTurnCommandType.MergeFleets:
              model.ui.fleetDetailModal.subModal = FleetSubModal.FleetPicker
            of ZeroTurnCommandType.LoadCargo, ZeroTurnCommandType.UnloadCargo:
              model.ui.fleetDetailModal.subModal = FleetSubModal.CargoParams
            of ZeroTurnCommandType.LoadFighters, ZeroTurnCommandType.UnloadFighters,
               ZeroTurnCommandType.TransferFighters:
              model.ui.fleetDetailModal.subModal = FleetSubModal.FighterParams
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.SystemPicker:
      # Letter/digit filter for SystemPicker: jump to matching coord
      if proposal.kind == ProposalKind.pkGameAction:
        let ch = if proposal.gameActionData.len > 0:
          proposal.gameActionData[0] else: '\0'
        if ch != '\0':
          let now = epochTime()
          let lastTime =
            model.ui.fleetDetailModal.systemPickerFilterTime
          let oldFilter =
            model.ui.fleetDetailModal.systemPickerFilter
          # Reset filter if timed out
          let filter = if oldFilter.len > 0 and
              (now - lastTime) < DigitBufferTimeout:
            oldFilter & $ch
          else:
            $ch
          model.ui.fleetDetailModal.systemPickerFilter = filter
          model.ui.fleetDetailModal.systemPickerFilterTime = now
          # Jump to first matching system by coordLabel prefix
          let systems =
            model.ui.fleetDetailModal.systemPickerSystems
          let upperFilter = filter.toUpperAscii()
          for i, sys in systems:
            if sys.coordLabel.toUpperAscii().startsWith(
                upperFilter):
              model.ui.fleetDetailModal.systemPickerIdx = i
              break
  else:
    discard

proc fleetListInputAcceptor*(model: var TuiModel, proposal: Proposal) =
  ## Handle fleet list sort and jump input
  if proposal.kind != ProposalKind.pkGameAction and
      proposal.kind != ProposalKind.pkNavigation:
    return
  case proposal.actionKind
  of ActionKind.fleetSortToggle:
    if model.ui.mode == ViewMode.Fleets and
        model.ui.fleetViewMode == FleetViewMode.ListView:
      toggleSortDirection(
        model.ui.fleetListState.sortState)
  of ActionKind.fleetConsoleNextPane:
    # Right arrow: next sort column in ListView
    if model.ui.mode == ViewMode.Fleets and
        model.ui.fleetViewMode == FleetViewMode.ListView:
      advanceSortColumn(
        model.ui.fleetListState.sortState)
      model.ui.selectedIdx = 0
      model.ui.fleetsScroll.verticalOffset = 0
  of ActionKind.fleetConsolePrevPane:
    # Left arrow: prev sort column in ListView
    if model.ui.mode == ViewMode.Fleets and
        model.ui.fleetViewMode == FleetViewMode.ListView:
      retreatSortColumn(
        model.ui.fleetListState.sortState)
      model.ui.selectedIdx = 0
      model.ui.fleetsScroll.verticalOffset = 0
  of ActionKind.fleetDigitJump:
    if model.ui.mode == ViewMode.Fleets and
        model.ui.fleetViewMode == FleetViewMode.ListView and
        proposal.gameActionData.len > 0:
      let ch = proposal.gameActionData[0]
      let now = epochTime()
      let buffer = model.ui.fleetListState.jumpBuffer
      let lastTime = model.ui.fleetListState.jumpTime
      # Build 2-char label buffer (e.g. "A" then "1" → "A1")
      var nextBuffer = ""
      if buffer.len == 1 and (now - lastTime) < DigitBufferTimeout:
        nextBuffer = buffer & $ch
      else:
        nextBuffer = $ch
      model.ui.fleetListState.jumpBuffer = nextBuffer
      model.ui.fleetListState.jumpTime = now
      # Only search when we have a full 2-char label
      if nextBuffer.len >= 2:
        let fleets = model.filteredFleets()
        let target = nextBuffer.toUpperAscii()
        var foundIdx = -1
        for idx, fleet in fleets:
          if fleet.name.toUpperAscii().startsWith(target):
            foundIdx = idx
            break
        if foundIdx >= 0:
          model.ui.selectedIdx = foundIdx
          var localScroll = model.ui.fleetsScroll
          localScroll.contentLength = fleets.len
          let maxVisibleRows = max(1, model.ui.termHeight - 10)
          localScroll.viewportLength = maxVisibleRows
          localScroll.ensureVisible(foundIdx)
          model.ui.fleetsScroll = localScroll
        model.ui.fleetListState.jumpBuffer = ""
  else:
    discard

# ============================================================================
# Create All Acceptors
# ============================================================================

proc createAcceptors*(): seq[AcceptorProc[TuiModel]] =
  ## Create the standard set of acceptors for the TUI
  @[
    navigationAcceptor, selectionAcceptor, viewportAcceptor, gameActionAcceptor,
    buildModalAcceptor, fleetDetailModalAcceptor,
    fleetListInputAcceptor, quitAcceptor, errorAcceptor,
  ]
