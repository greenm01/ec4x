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
    model.statusMessage = ""
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
      let reports = model.filteredReports()
      if model.selectedIdx < reports.len:
        model.selectedReportId = reports[model.selectedIdx].id
        model.mode = ViewMode.ReportDetail
        model.pushBreadcrumb(
          "Report " & $(model.selectedIdx + 1),
          ViewMode.ReportDetail,
          model.selectedReportId,
        )
        model.statusMessage = ""
        model.clearExpertFeedback()
      else:
        model.statusMessage = "No reports in this category"
    elif model.mode == ViewMode.ReportDetail:
      let reportOpt = model.selectedReport()
      let reports = model.filteredReports()
      if reportOpt.isSome:
        let report = reportOpt.get()
        let target = report.linkView
        if target >= 1 and target <= 9:
          let nextMode = ViewMode(target)
          model.mode = nextMode
          model.resetBreadcrumbs(nextMode)
          model.statusMessage = "Jumped to " & report.linkLabel
        else:
          if model.selectedIdx + 1 < reports.len:
            model.selectedIdx += 1
            model.selectedReportId = reports[model.selectedIdx].id
          model.statusMessage = ""
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
  of ActionListUp:
    if model.selectedIdx > 0:
      model.selectedIdx -= 1
  of ActionListDown:
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
