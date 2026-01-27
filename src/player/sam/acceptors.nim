## TUI Acceptors - Functions that mutate model state
##
## Acceptors receive proposals and mutate the model accordingly.
## They are the ONLY place where model mutation happens.
## Each acceptor handles specific proposal types or aspects of state.
##
## Acceptor signature: proc(model: var M, proposal: Proposal)

import std/[options, times, strutils]
import ./types
import ./tui_model
import ./actions
import ./command_parser
import ../tui/widget/scroll_state
import ../state/join_flow
import ../state/lobby_profile
import ../../common/invite_code
import ../../common/logger

export types, tui_model, actions

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
  of 8:
    some(ViewMode.Messages)
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
       ViewMode.Messages, ViewMode.Settings, ViewMode.PlanetDetail,
       ViewMode.FleetDetail, ViewMode.ReportDetail:
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
      if model.ui.selectedIdx < model.view.fleets.len:
        let fleetId = model.view.fleets[model.ui.selectedIdx].id
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
    if model.ui.selectedIdx > 0:
      model.ui.selectedIdx = max(0, model.ui.selectedIdx - 1)
  of ActionKind.listDown:
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
    elif target == 30:
      model.ui.previousMode = model.ui.mode
      model.ui.mode = ViewMode.FleetDetail
      model.resetBreadcrumbs(model.ui.mode)
      if model.ui.selectedIdx < model.view.fleets.len:
        model.ui.selectedFleetId =
          model.view.fleets[model.ui.selectedIdx].id

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
          model.ui.stagedFleetCommands.setLen(0)
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
            model.ui.stagedFleetCommands.add(result.fleetCommand.get())
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
          model.ui.selectedColonyId = row.colonyId.get()
          model.resetBreadcrumbs(model.ui.mode)
        else:
          model.ui.statusMessage = "No colony selected"
    elif model.ui.mode == ViewMode.Fleets and proposal.selectIdx == -1:
      if model.ui.selectedIdx >= 0 and
          model.ui.selectedIdx < model.view.fleets.len:
        model.ui.previousMode = model.ui.mode
        model.ui.mode = ViewMode.FleetDetail
        model.ui.selectedFleetId = model.view.fleets[model.ui.selectedIdx].id
        model.resetBreadcrumbs(model.ui.mode)
      else:
        model.ui.statusMessage = "No fleet selected"
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
# Order Entry Acceptor
# ============================================================================

proc orderEntryAcceptor*(model: var TuiModel, proposal: Proposal) =
  ## Handle order entry proposals (Move/Patrol/Hold commands)
  if proposal.kind != ProposalKind.pkGameAction:
    return

  case proposal.actionKind
  of ActionKind.startOrderMove:
    let fleetId = try: parseInt(proposal.gameActionData) except: 0
    if fleetId > 0:
      model.startOrderEntry(fleetId, CmdMove)
  of ActionKind.startOrderPatrol:
    let fleetId = try: parseInt(proposal.gameActionData) except: 0
    if fleetId > 0:
      model.startOrderEntry(fleetId, CmdPatrol)
  of ActionKind.startOrderHold:
    let fleetId = try: parseInt(proposal.gameActionData) except: 0
    if fleetId > 0:
      # Hold is immediate - no target selection needed
      model.queueImmediateOrder(fleetId, CmdHold)
      model.ui.statusMessage = "Hold order queued for fleet " & $fleetId
  of ActionKind.confirmOrder:
    if model.ui.orderEntryActive:
      # Look up system ID at cursor position
      let cursorCoord = model.ui.mapState.cursor
      let sysOpt = model.systemAt(cursorCoord)
      if sysOpt.isSome:
        let targetSystemId = sysOpt.get().id
        model.confirmOrderEntry(targetSystemId)
        let cmdLabel = commandLabel(model.ui.pendingFleetOrderCommandType)
        model.ui.statusMessage = cmdLabel & " order queued to system " &
          sysOpt.get().name
      else:
        model.ui.statusMessage = "No system at cursor position"
  of ActionKind.cancelOrder:
    if model.ui.orderEntryActive:
      model.cancelOrderEntry()
  else:
    discard

# ============================================================================
# Create All Acceptors
# ============================================================================

proc createAcceptors*(): seq[AcceptorProc[TuiModel]] =
  ## Create the standard set of acceptors for the TUI
  @[
    navigationAcceptor, selectionAcceptor, viewportAcceptor, gameActionAcceptor,
    orderEntryAcceptor, quitAcceptor, errorAcceptor,
  ]
