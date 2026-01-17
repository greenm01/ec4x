## TUI Acceptors - Functions that mutate model state
##
## Acceptors receive proposals and mutate the model accordingly.
## They are the ONLY place where model mutation happens.
## Each acceptor handles specific proposal types or aspects of state.
##
## Acceptor signature: proc(model: var M, proposal: Proposal)

import std/[options, strutils]
import ./types
import ./tui_model
import ./actions
import ../tui/widget/scroll_state
import ../state/join_flow
import ../../common/kdl_join

export types, tui_model, actions

# ============================================================================
# Navigation Acceptor
# ============================================================================

proc navigationAcceptor*(model: var TuiModel, proposal: Proposal) =
  ## Handle navigation proposals (mode changes, cursor movement)
  if proposal.kind != ProposalKind.pkNavigation:
    return

  model.clearExpertFeedback()
  case proposal.actionName
  of ActionNavigateMode:
    # Mode switch
    let newMode = ViewMode(proposal.navMode)
    model.mode = newMode
    model.selectedIdx = 0 # Reset selection when switching modes
    model.resetBreadcrumbs(newMode)
    model.statusMessage = ""
    model.clearExpertFeedback()
  of ActionSwitchView:
    # Primary view switch
    let newMode = ViewMode(proposal.navMode)
    model.mode = newMode
    model.selectedIdx = 0
    model.resetBreadcrumbs(newMode)
    model.statusMessage = ""
    model.clearExpertFeedback()
    if newMode == ViewMode.Reports:
      model.reportFocus = ReportPaneFocus.TurnList
      model.reportTurnIdx = 0
      model.reportSubjectIdx = 0
      model.reportTurnScroll = initScrollState()
      model.reportSubjectScroll = initScrollState()
      model.reportBodyScroll = initScrollState()
  of ActionBreadcrumbBack:
    if model.popBreadcrumb():
      let current = model.currentBreadcrumb()
      model.mode = current.viewMode
      model.statusMessage = ""
  of ActionMoveCursor:
    if proposal.navMode >= 0:
      # Direction-based movement
      let dir = HexDirection(proposal.navMode)
      model.mapState.cursor = model.mapState.cursor.neighbor(dir)
    else:
      # Direct coordinate movement
      model.mapState.cursor = proposal.navCursor
  of ActionJumpHome:
    if model.homeworld.isSome:
      model.mapState.cursor = model.homeworld.get
  of ActionCycleColony:
    let coords = model.ownedColonyCoords()
    if coords.len > 0:
      # Find current cursor in owned colonies
      var currentIdx = -1
      for i, coord in coords:
        if coord == model.mapState.cursor:
          currentIdx = i
          break

      # Cycle to next/prev
      let reverse = proposal.navMode == 1
      if reverse:
        if currentIdx <= 0:
          model.mapState.cursor = coords[coords.len - 1]
        else:
          model.mapState.cursor = coords[currentIdx - 1]
      else:
        if currentIdx < 0 or currentIdx >= coords.len - 1:
          model.mapState.cursor = coords[0]
        else:
          model.mapState.cursor = coords[currentIdx + 1]
  of ActionSwitchPlanetTab:
    let tabValue = max(1, min(5, proposal.navMode))
    model.planetDetailTab = PlanetDetailTab(tabValue)
  of ActionSwitchFleetView:
    if model.fleetViewMode == FleetViewMode.SystemView:
      model.fleetViewMode = FleetViewMode.ListView
    else:
      model.fleetViewMode = FleetViewMode.SystemView
  of ActionCycleReportFilter:
    let nextFilter = (ord(model.reportFilter) + 1) mod
      (ord(ReportCategory.Other) + 1)
    model.reportFilter = ReportCategory(nextFilter)
    model.selectedIdx = 0
    model.selectedReportId = 0
    model.reportTurnIdx = 0
    model.reportSubjectIdx = 0
    model.reportTurnScroll = initScrollState()
    model.reportSubjectScroll = initScrollState()
    model.reportBodyScroll = initScrollState()
    model.statusMessage = ""
  of ActionReportFocusNext:
    case model.reportFocus
    of ReportPaneFocus.TurnList:
      model.reportFocus = ReportPaneFocus.SubjectList
    of ReportPaneFocus.SubjectList:
      model.reportFocus = ReportPaneFocus.BodyPane
    of ReportPaneFocus.BodyPane:
      model.reportFocus = ReportPaneFocus.TurnList
  of ActionReportFocusPrev:
    case model.reportFocus
    of ReportPaneFocus.TurnList:
      model.reportFocus = ReportPaneFocus.BodyPane
    of ReportPaneFocus.SubjectList:
      model.reportFocus = ReportPaneFocus.TurnList
    of ReportPaneFocus.BodyPane:
      model.reportFocus = ReportPaneFocus.SubjectList
  of ActionReportFocusLeft:
    case model.reportFocus
    of ReportPaneFocus.TurnList:
      discard
    of ReportPaneFocus.SubjectList:
      model.reportFocus = ReportPaneFocus.TurnList
    of ReportPaneFocus.BodyPane:
      model.reportFocus = ReportPaneFocus.SubjectList
  of ActionReportFocusRight:
    case model.reportFocus
    of ReportPaneFocus.TurnList:
      model.reportFocus = ReportPaneFocus.SubjectList
    of ReportPaneFocus.SubjectList:
      model.reportFocus = ReportPaneFocus.BodyPane
    of ReportPaneFocus.BodyPane:
      discard
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
  case proposal.actionName
  of ActionSelect:
    case model.mode
    of ViewMode.Overview:
      # Overview selection (action queue items)
      if proposal.selectIdx >= 0:
        model.selectedIdx = proposal.selectIdx
    of ViewMode.Planets, ViewMode.Fleets, ViewMode.Research,
       ViewMode.Espionage, ViewMode.Economy, ViewMode.Reports,
       ViewMode.Messages, ViewMode.Settings, ViewMode.PlanetDetail,
       ViewMode.FleetDetail, ViewMode.ReportDetail:
      # Select current list item (idx is already set)
      if proposal.selectIdx >= 0:
        model.selectedIdx = proposal.selectIdx

    if model.mode == ViewMode.Reports:
      let reports = model.currentTurnReports()
      if model.reportSubjectIdx < reports.len:
        model.selectedReportId = reports[model.reportSubjectIdx].id
        model.mode = ViewMode.ReportDetail
        model.pushBreadcrumb(
          "Report " & $(model.reportSubjectIdx + 1),
          ViewMode.ReportDetail,
          model.selectedReportId,
        )
        model.statusMessage = ""
        model.clearExpertFeedback()
      else:
        model.statusMessage = "No reports in this turn"
    elif model.mode == ViewMode.ReportDetail:
      let reportOpt = model.selectedReport()
      if reportOpt.isSome:
        let report = reportOpt.get()
        let target = report.linkView
        if target >= 1 and target <= 9:
          let nextMode = ViewMode(target)
          model.mode = nextMode
          model.resetBreadcrumbs(nextMode)
          model.statusMessage = "Jumped to " & report.linkLabel
      model.clearExpertFeedback()
  of ActionToggleFleetSelect:
    if model.mode == ViewMode.Fleets:
      if model.selectedIdx < model.fleets.len:
        let fleetId = model.fleets[model.selectedIdx].id
        model.toggleFleetSelection(fleetId)
  of ActionDeselect:
    model.mapState.selected = none(HexCoord)
    if model.mode == ViewMode.ReportDetail:
      if model.popBreadcrumb():
        let current = model.currentBreadcrumb()
        model.mode = current.viewMode
        model.statusMessage = ""
        model.clearExpertFeedback()
      else:
        model.statusMessage = ""
        model.clearExpertFeedback()
    else:
      model.statusMessage = ""
      model.clearExpertFeedback()
  of ActionListUp:
    if model.joinStatus == JoinStatus.SelectingGame:
      if model.joinSelectedIdx > 0:
        model.joinSelectedIdx -= 1
    elif model.mode == ViewMode.Reports:
      case model.reportFocus
      of ReportPaneFocus.TurnList:
        if model.reportTurnIdx > 0:
          model.reportTurnIdx -= 1
          model.reportSubjectIdx = 0
          model.reportBodyScroll = initScrollState()
        model.reportTurnScroll.ensureVisible(model.reportTurnIdx)
      of ReportPaneFocus.SubjectList:
        if model.reportSubjectIdx > 0:
          model.reportSubjectIdx -= 1
          model.reportBodyScroll = initScrollState()
        model.reportSubjectScroll.ensureVisible(model.reportSubjectIdx)
      of ReportPaneFocus.BodyPane:
        if model.reportBodyScroll.verticalOffset > 0:
          model.reportBodyScroll.verticalOffset -= 1
    elif model.selectedIdx > 0:
      model.selectedIdx -= 1
  of ActionListDown:
    if model.joinStatus == JoinStatus.SelectingGame:
      let maxIdx = model.joinGames.len - 1
      if model.joinSelectedIdx < maxIdx:
        model.joinSelectedIdx += 1
    elif model.mode == ViewMode.Reports:
      case model.reportFocus
      of ReportPaneFocus.TurnList:
        let buckets = model.reportsByTurn()
        let maxIdx = buckets.len - 1
        if model.reportTurnIdx < maxIdx:
          model.reportTurnIdx += 1
          model.reportSubjectIdx = 0
          model.reportBodyScroll = initScrollState()
        model.reportTurnScroll.ensureVisible(model.reportTurnIdx)
      of ReportPaneFocus.SubjectList:
        let reports = model.currentTurnReports()
        let maxIdx = reports.len - 1
        if model.reportSubjectIdx < maxIdx:
          model.reportSubjectIdx += 1
          model.reportBodyScroll = initScrollState()
        model.reportSubjectScroll.ensureVisible(model.reportSubjectIdx)
      of ReportPaneFocus.BodyPane:
        model.reportBodyScroll.verticalOffset += 1
    else:
      let maxIdx = model.currentListLength() - 1
      if model.selectedIdx < maxIdx:
        model.selectedIdx += 1
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
  case proposal.actionName
  of ActionScroll:
    model.mapState.viewportOrigin = (
      model.mapState.viewportOrigin.q + proposal.scrollDelta.dx,
      model.mapState.viewportOrigin.r + proposal.scrollDelta.dy,
    )
  of ActionResize:
    model.termWidth = proposal.scrollDelta.dx
    model.termHeight = proposal.scrollDelta.dy
    model.needsResize = true
  else:
    discard

# ============================================================================
# Game Action Acceptor
# ============================================================================

proc gameActionAcceptor*(model: var TuiModel, proposal: Proposal) =
  ## Handle game action proposals
  model.clearExpertFeedback()
  case proposal.kind
  of ProposalKind.pkEndTurn:
    model.statusMessage = "Turn ended. Processing..."
    # Actual turn processing would be done elsewhere (integration with engine)
  of ProposalKind.pkQuit:
    model.running = false
  of ProposalKind.pkGameAction:
    # Handle game-specific actions
    case proposal.gameActionType
    of ActionExportMap:
      model.exportMapRequested = true
      model.statusMessage = "Exporting starmap..."
    of ActionOpenMap:
      model.exportMapRequested = true
      model.openMapRequested = true
      model.statusMessage = "Exporting and opening starmap..."
    of ActionEnterExpertMode:
      model.enterExpertMode()
    of ActionExitExpertMode:
      model.exitExpertMode()
    of ActionExpertInputAppend:
      if model.expertModeActive:
        model.expertModeInput.add(proposal.gameActionData)
      elif model.joinStatus == JoinStatus.EnteringPubkey:
        model.joinPubkeyInput.add(proposal.gameActionData)
      elif model.joinStatus == JoinStatus.EnteringName:
        model.joinPlayerName.add(proposal.gameActionData)
    of ActionExpertInputBackspace:
      if model.expertModeActive and model.expertModeInput.len > 0:
        model.expertModeInput.setLen(model.expertModeInput.len - 1)
    of ActionExpertSubmit:
      if model.expertModeActive:
        let command = model.expertModeInput.strip()
        model.addToExpertHistory(command)
        if command.len == 0:
          model.setExpertFeedback("Expert mode: no command entered")
        else:
          model.setExpertFeedback("Expert mode: " & command)
        model.exitExpertMode()
    of ActionJoinRefresh:
      model.joinGames = loadJoinGames("data")
      model.joinStatus = JoinStatus.SelectingGame
      model.joinSelectedIdx = 0
      model.joinError = ""
      model.statusMessage = "Select a game to join"
    of ActionJoinEditPubkey:
      model.joinStatus = JoinStatus.EnteringPubkey
      model.joinPubkeyInput = ""
      model.joinError = ""
      model.statusMessage = "Enter Nostr pubkey"
    of ActionJoinEditName:
      model.joinStatus = JoinStatus.EnteringName
      model.joinPlayerName = ""
      model.joinError = ""
      model.statusMessage = "Enter player name"
    of ActionJoinBackspace:
      case model.joinStatus
      of JoinStatus.EnteringPubkey:
        if model.joinPubkeyInput.len > 0:
          model.joinPubkeyInput.setLen(model.joinPubkeyInput.len - 1)
      of JoinStatus.EnteringName:
        if model.joinPlayerName.len > 0:
          model.joinPlayerName.setLen(model.joinPlayerName.len - 1)
      else:
        discard
    of ActionJoinSubmit:
      if model.joinStatus == JoinStatus.SelectingGame:
        if model.joinSelectedIdx < model.joinGames.len:
          let game = model.joinGames[model.joinSelectedIdx]
          model.joinGameId = game.id
          model.joinStatus = JoinStatus.EnteringPubkey
          model.statusMessage = "Enter Nostr pubkey"
        else:
          model.joinError = "No game selected"
      elif model.joinStatus == JoinStatus.EnteringPubkey:
        let normalized = normalizePubkey(model.joinPubkeyInput)
        if normalized.isNone:
          model.joinError = "Invalid pubkey"
          model.statusMessage = model.joinError
        else:
          model.joinPubkeyInput = normalized.get()
          model.joinStatus = JoinStatus.EnteringName
          model.statusMessage = "Enter player name (optional)"
      elif model.joinStatus == JoinStatus.EnteringName:
        let gameDir = "data/games/" & model.joinGameId
        let request = JoinRequest(
          gameId: model.joinGameId,
          pubkey: model.joinPubkeyInput,
          name: if model.joinPlayerName.len > 0: some(model.joinPlayerName)
                else: none(string)
        )
        model.joinRequestPath = writeJoinRequest(gameDir, request)
        model.joinStatus = JoinStatus.WaitingResponse
        model.statusMessage = "Waiting for join response..."
    of ActionJoinPoll:
      if model.joinStatus == JoinStatus.WaitingResponse:
        let gameDir = "data/games/" & model.joinGameId
        let responseOpt = readJoinResponse(gameDir, model.joinRequestPath)
        if responseOpt.isSome:
          let response = responseOpt.get()
          if response.status == JoinResponseStatus.Accepted:
            if response.houseId.isSome:
              let houseId = response.houseId.get()
              writeJoinCache("data", model.joinPubkeyInput,
                model.joinGameId, houseId)
              model.joinStatus = JoinStatus.Joined
              model.statusMessage = "Joined game as house " &
                $houseId.uint32
            else:
              model.joinError = "Join response missing house"
              model.joinStatus = JoinStatus.Failed
          else:
            model.joinError = response.reason.get("Join rejected")
            model.joinStatus = JoinStatus.Failed
            model.statusMessage = model.joinError
    else:
      model.statusMessage = "Action: " & proposal.gameActionType
  else:
    discard

# ============================================================================
# Error Acceptor
# ============================================================================

proc errorAcceptor*(model: var TuiModel, proposal: Proposal) =
  ## Handle error proposals
  if proposal.kind == ProposalKind.pkError:
    model.statusMessage = "Error: " & proposal.errorMsg

# ============================================================================
# Create All Acceptors
# ============================================================================

proc createAcceptors*(): seq[AcceptorProc[TuiModel]] =
  ## Create the standard set of acceptors for the TUI
  @[
    navigationAcceptor, selectionAcceptor, viewportAcceptor, gameActionAcceptor,
    errorAcceptor,
  ]
