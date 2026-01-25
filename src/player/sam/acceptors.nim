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
  let matches = matchExpertCommands(model.expertModeInput)
  if matches.len == 0:
    model.expertPaletteSelection = -1
  else:
    model.expertPaletteSelection = 0

proc clampExpertPaletteSelection(model: var TuiModel) =
  let matches = matchExpertCommands(model.expertModeInput)
  if matches.len == 0:
    model.expertPaletteSelection = -1
    return
  if model.expertPaletteSelection < 0:
    model.expertPaletteSelection = 0
  elif model.expertPaletteSelection >= matches.len:
    model.expertPaletteSelection = matches.len - 1

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
      model.mode = selectedMode
      model.selectedIdx = 0 # Reset selection when switching modes
      model.resetBreadcrumbs(selectedMode)
      model.statusMessage = ""
      model.clearExpertFeedback()
  of ActionKind.switchView:
    # Primary view switch
    let newMode = viewModeFromInt(proposal.navMode)
    if newMode.isSome:
      let selectedMode = newMode.get()
      model.mode = selectedMode
      model.selectedIdx = 0
      model.resetBreadcrumbs(selectedMode)
      model.statusMessage = ""
      model.clearExpertFeedback()
      if selectedMode == ViewMode.Reports:
        model.reportFocus = ReportPaneFocus.TurnList
        model.reportTurnIdx = 0
        model.reportSubjectIdx = 0
        model.reportTurnScroll = initScrollState()
        model.reportSubjectScroll = initScrollState()
        model.reportBodyScroll = initScrollState()
  of ActionKind.breadcrumbBack:
    if model.popBreadcrumb():
      let current = model.currentBreadcrumb()
      model.mode = current.viewMode
      model.statusMessage = ""
  of ActionKind.moveCursor:
    if proposal.navMode >= 0:
      # Direction-based movement
      let dir = HexDirection(proposal.navMode)
      model.mapState.cursor = model.mapState.cursor.neighbor(dir)
    else:
      # Direct coordinate movement
      model.mapState.cursor = proposal.navCursor
  of ActionKind.jumpHome:
    if model.homeworld.isSome:
      model.mapState.cursor = model.homeworld.get
  of ActionKind.cycleColony:
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
  of ActionKind.switchPlanetTab:
    let tabValue = max(1, min(5, proposal.navMode))
    model.planetDetailTab = PlanetDetailTab(tabValue)
  of ActionKind.switchFleetView:
    if model.fleetViewMode == FleetViewMode.SystemView:
      model.fleetViewMode = FleetViewMode.ListView
    else:
      model.fleetViewMode = FleetViewMode.SystemView
  of ActionKind.cycleReportFilter:
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
  of ActionKind.reportFocusNext:
    case model.reportFocus
    of ReportPaneFocus.TurnList:
      model.reportFocus = ReportPaneFocus.SubjectList
    of ReportPaneFocus.SubjectList:
      model.reportFocus = ReportPaneFocus.BodyPane
    of ReportPaneFocus.BodyPane:
      model.reportFocus = ReportPaneFocus.TurnList
  of ActionKind.reportFocusPrev:
    case model.reportFocus
    of ReportPaneFocus.TurnList:
      model.reportFocus = ReportPaneFocus.BodyPane
    of ReportPaneFocus.SubjectList:
      model.reportFocus = ReportPaneFocus.TurnList
    of ReportPaneFocus.BodyPane:
      model.reportFocus = ReportPaneFocus.SubjectList
  of ActionKind.reportFocusLeft:
    case model.reportFocus
    of ReportPaneFocus.TurnList:
      discard
    of ReportPaneFocus.SubjectList:
      model.reportFocus = ReportPaneFocus.TurnList
    of ReportPaneFocus.BodyPane:
      model.reportFocus = ReportPaneFocus.SubjectList
  of ActionKind.reportFocusRight:
    case model.reportFocus
    of ReportPaneFocus.TurnList:
      model.reportFocus = ReportPaneFocus.SubjectList
    of ReportPaneFocus.SubjectList:
      model.reportFocus = ReportPaneFocus.BodyPane
    of ReportPaneFocus.BodyPane:
      discard
  of ActionKind.lobbySwitchPane:
    if proposal.navMode >= 0 and proposal.navMode <= 2:
      model.lobbyPane = LobbyPane(proposal.navMode)
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
        let nextMode = viewModeFromInt(target)
        if nextMode.isSome:
          let selectedMode = nextMode.get()
          model.mode = selectedMode
          model.resetBreadcrumbs(selectedMode)
          model.statusMessage = "Jumped to " & report.linkLabel
      model.clearExpertFeedback()
  of ActionKind.toggleFleetSelect:
    if model.mode == ViewMode.Fleets:
      if model.selectedIdx < model.fleets.len:
        let fleetId = model.fleets[model.selectedIdx].id
        model.toggleFleetSelection(fleetId)
  of ActionKind.deselect:
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
    elif model.mode == ViewMode.FleetDetail:
      # Return to fleet list
      model.mode = ViewMode.Fleets
      model.statusMessage = ""
      model.clearExpertFeedback()
    elif model.mode == ViewMode.PlanetDetail:
      # Return to colony list
      model.mode = ViewMode.Planets
      model.statusMessage = ""
      model.clearExpertFeedback()
    else:
      model.statusMessage = ""
      model.clearExpertFeedback()
  of ActionKind.listUp:
    if model.selectedIdx > 0:
      model.selectedIdx = max(0, model.selectedIdx - 1)
  of ActionKind.listDown:
    let maxIdx = model.currentListLength() - 1
    if model.selectedIdx < maxIdx:
      model.selectedIdx = min(maxIdx, model.selectedIdx + 1)
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
    model.mapState.viewportOrigin = (
      model.mapState.viewportOrigin.q + proposal.scrollDelta.dx,
      model.mapState.viewportOrigin.r + proposal.scrollDelta.dy,
    )
  of ActionKind.resize:
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
      model.previousMode = model.mode
      model.mode = ViewMode.PlanetDetail
      model.resetBreadcrumbs(model.mode)
      if model.selectedIdx < model.colonies.len:
        model.selectedColonyId = model.colonies[model.selectedIdx].colonyId
    elif target == 30:
      model.previousMode = model.mode
      model.mode = ViewMode.FleetDetail
      model.resetBreadcrumbs(model.mode)
      if model.selectedIdx < model.fleets.len:
        model.selectedFleetId = model.fleets[model.selectedIdx].id

  of ProposalKind.pkGameAction:
    case proposal.actionKind
    of ActionKind.lobbyGenerateKey:
      model.lobbySessionKeyActive = true
      model.lobbyWarning = "Session-only key: not saved"
      model.lobbyProfilePubkey = "session-" & $getTime().toUnix()
      model.statusMessage = "Generated session key (not stored)"
      # Active games populated from Nostr events, not filesystem
    of ActionKind.lobbyJoinRefresh:
      # Games now discovered via Nostr events (30400), not filesystem scan
      # This action triggers a UI refresh; actual data comes from Nostr
      model.lobbyJoinSelectedIdx = 0
      model.statusMessage = "Refreshing game list from relay..."
    of ActionKind.lobbyJoinSubmit:
      if model.lobbyInputMode == LobbyInputMode.Pubkey:
        let normalized = normalizePubkey(model.lobbyProfilePubkey)
        if normalized.isNone:
          model.lobbyJoinError = "Invalid pubkey"
          model.statusMessage = model.lobbyJoinError
        else:
          model.lobbyProfilePubkey = normalized.get()
          model.lobbyInputMode = LobbyInputMode.None
          saveProfile("data", model.lobbyProfilePubkey,
            model.lobbyProfileName, model.lobbySessionKeyActive)
          # Active games populated from TUI cache, not filesystem
      elif model.lobbyInputMode == LobbyInputMode.Name:
        model.lobbyInputMode = LobbyInputMode.None
        saveProfile("data", model.lobbyProfilePubkey,
          model.lobbyProfileName, model.lobbySessionKeyActive)
      elif model.lobbyJoinStatus == JoinStatus.SelectingGame:
        if model.lobbyJoinSelectedIdx < model.lobbyJoinGames.len:
          let game = model.lobbyJoinGames[model.lobbyJoinSelectedIdx]
          model.lobbyGameId = game.id
          model.lobbyJoinStatus = JoinStatus.EnteringPubkey
          model.statusMessage = "Enter Nostr pubkey"
        else:
          model.lobbyJoinError = "No game selected"
      elif model.lobbyJoinStatus == JoinStatus.EnteringPubkey:
        let normalized = normalizePubkey(model.lobbyProfilePubkey)
        if normalized.isNone:
          model.lobbyJoinError = "Invalid pubkey"
          model.statusMessage = model.lobbyJoinError
        else:
          model.lobbyProfilePubkey = normalized.get()
          model.lobbyJoinStatus = JoinStatus.EnteringName
          model.statusMessage = "Enter player name (optional)"
      elif model.lobbyJoinStatus == JoinStatus.EnteringName:
        let normalized = normalizePubkey(model.lobbyProfilePubkey)
        if normalized.isNone:
          model.lobbyJoinError = "Invalid pubkey"
          model.statusMessage = model.lobbyJoinError
        else:
          model.lobbyProfilePubkey = normalized.get()
          saveProfile("data", model.lobbyProfilePubkey,
            model.lobbyProfileName, model.lobbySessionKeyActive)
          let inviteCode = invite_code.normalizeInviteCode(
            model.entryModal.inviteCode()
          )
          if inviteCode.len == 0:
            model.lobbyJoinStatus = JoinStatus.Failed
            model.lobbyJoinError = "Invite code required"
            model.statusMessage = model.lobbyJoinError
          elif model.lobbyGameId.len == 0:
            model.lobbyJoinStatus = JoinStatus.Failed
            model.lobbyJoinError = "Game ID missing"
            model.statusMessage = model.lobbyJoinError
          else:
            model.nostrJoinRequested = true
            model.nostrJoinSent = false
            model.nostrJoinInviteCode = inviteCode
            model.nostrJoinGameId = model.lobbyGameId
            model.nostrJoinPubkey = model.lobbyProfilePubkey
            model.lobbyJoinStatus = JoinStatus.WaitingResponse
            model.statusMessage = "Submitting join request"
    of ActionKind.lobbyJoinPoll:
      if model.lobbyJoinStatus == JoinStatus.WaitingResponse:
        model.statusMessage = "Waiting for join response..."
    of ActionKind.lobbyReturn:
      model.appPhase = AppPhase.Lobby
      model.statusMessage = "Returned to lobby"
      # Active games already in model from TUI cache
    of ActionKind.lobbyEditPubkey:
      model.lobbyInputMode = LobbyInputMode.Pubkey
      model.statusMessage = "Enter Nostr pubkey"
      # Active games already in model from TUI cache
    of ActionKind.lobbyEditName:
      model.lobbyInputMode = LobbyInputMode.Name
      model.statusMessage = "Enter player name"
    of ActionKind.lobbyBackspace:
      case model.lobbyInputMode
      of LobbyInputMode.Pubkey:
        if model.lobbyProfilePubkey.len > 0:
          model.lobbyProfilePubkey.setLen(model.lobbyProfilePubkey.len - 1)
        # Active games filtered by pubkey from TUI cache
      of LobbyInputMode.Name:
        if model.lobbyProfileName.len > 0:
          model.lobbyProfileName.setLen(model.lobbyProfileName.len - 1)
      else:
        discard
    of ActionKind.lobbyInputAppend:
      case model.lobbyInputMode
      of LobbyInputMode.Pubkey:
        model.lobbyProfilePubkey.add(proposal.gameActionData)
      of LobbyInputMode.Name:
        model.lobbyProfileName.add(proposal.gameActionData)
      else:
        discard
    # Entry modal actions
    of ActionKind.entryUp:
      model.entryModal.moveUp()
    of ActionKind.entryDown:
      model.entryModal.moveDown()
    of ActionKind.entrySelect:
      # Enter selected game from game list
      let gameOpt = model.entryModal.selectedGame()
      if gameOpt.isSome:
        let game = gameOpt.get()
        model.loadGameRequested = true
        model.loadGameId = game.id
        model.loadHouseId = game.houseId
        model.statusMessage = "Loading game..."
    of ActionKind.entryImport:
      model.entryModal.startImport()
      model.statusMessage = "Enter nsec to import identity"
    of ActionKind.entryImportConfirm:
      if model.entryModal.confirmImport():
        model.statusMessage = "Identity imported successfully"
      else:
        model.statusMessage = "Import failed: " & model.entryModal.importError
    of ActionKind.entryImportCancel:
      model.entryModal.cancelImport()
      model.statusMessage = ""
    of ActionKind.entryImportAppend:
      if proposal.gameActionData.len > 0:
        discard model.entryModal.importInput.appendChar(
          proposal.gameActionData[0])
    of ActionKind.entryImportBackspace:
      model.entryModal.importInput.backspace()
    of ActionKind.entryInviteAppend:
      if proposal.gameActionData.len > 0:
        # Validate: allow lowercase letters, hyphen, @, :, ., and digits
        # Format: code@host:port (e.g., velvet-mountain@play.ec4x.io:8080)
        let ch = proposal.gameActionData[0].toLowerAscii()
        if ch in 'a'..'z' or ch in '0'..'9' or ch in {'-', '@', ':', '.'}:
          discard model.entryModal.inviteInput.appendChar(ch)
          model.entryModal.inviteError = ""
          # Focus invite code field when typing starts
          model.entryModal.focusInviteCode()
    of ActionKind.entryInviteBackspace:
      model.entryModal.inviteInput.backspace()
      model.entryModal.inviteError = ""
    of ActionKind.entryInviteSubmit:
      # Submit invite code to server
      # Format: code@host:port (e.g., velvet-mountain@play.ec4x.io:8080)
      if model.entryModal.inviteInput.isEmpty():
        model.entryModal.setInviteError("Enter an invite code")
      else:
        let input = model.entryModal.inviteCode()
        let parsed = parseInviteCode(input)

        if not isValidInviteCodeFormat(parsed.code):
          model.entryModal.setInviteError("Invalid code format")
        elif not parsed.hasRelay() and model.nostrRelayUrl.len == 0:
          model.entryModal.setInviteError("No relay in code, none configured")
        else:
          let identity = model.entryModal.identity
          model.nostrJoinRequested = true
          model.nostrJoinSent = false
          model.nostrJoinInviteCode = parsed.code
          model.nostrJoinRelayUrl = if parsed.hasRelay():
            parsed.relayUrl
          else:
            model.nostrRelayUrl
          model.nostrJoinGameId = "invite"
          model.nostrJoinPubkey = identity.npubHex
          logInfo("JOIN", "FLAGS SET: requested=true, inviteCode=", model.nostrJoinInviteCode,
            " relayUrl=", model.nostrJoinRelayUrl, " gameId=", model.nostrJoinGameId)
          model.entryModal.setInviteError("Join request sent")
          model.entryModal.clearInviteCode()
          model.lobbyJoinStatus = JoinStatus.WaitingResponse
          model.statusMessage = "Joining via " & model.nostrJoinRelayUrl

    of ActionKind.entryAdminSelect:
      # Dispatch based on selected admin menu item
      let menuItem = model.entryModal.selectedAdminMenuItem()
      if menuItem.isSome:
        case menuItem.get()
        of AdminMenuItem.CreateGame:
          # Switch to game creation mode
          model.entryModal.mode = EntryModalMode.CreateGame
          model.statusMessage = "Create a new game"
        of AdminMenuItem.ManageGames:
          # Switch to manage games mode
          model.entryModal.mode = EntryModalMode.ManageGames
          model.statusMessage = "Manage your games"
    of ActionKind.entryAdminCreateGame:
      # Direct action to enter game creation mode
      model.entryModal.mode = EntryModalMode.CreateGame
      model.statusMessage = "Create a new game"
    of ActionKind.entryAdminManageGames:
      # Direct action to enter manage games mode
      model.entryModal.mode = EntryModalMode.ManageGames
      model.statusMessage = "Manage your games"
    of ActionKind.entryRelayEdit:
      # Start editing relay URL
      model.entryModal.startEditingRelay()
      model.statusMessage = "Edit relay URL"
    of ActionKind.entryRelayAppend:
      # Append character to relay URL
      if proposal.gameActionData.len > 0:
        discard model.entryModal.relayInput.appendChar(
          proposal.gameActionData[0])
    of ActionKind.entryRelayBackspace:
      # Backspace in relay URL
      model.entryModal.relayInput.backspace()
    of ActionKind.entryRelayConfirm:
      # Confirm relay URL edit
      model.entryModal.stopEditingRelay()
      model.statusMessage = "Relay: " & model.entryModal.relayUrl()
    # Game creation actions
    of ActionKind.createGameUp:
      model.entryModal.createFieldUp()
    of ActionKind.createGameDown:
      model.entryModal.createFieldDown()
    of ActionKind.createGameLeft:
      if model.entryModal.createField == CreateGameField.PlayerCount:
        model.entryModal.decrementPlayerCount()
    of ActionKind.createGameRight:
      if model.entryModal.createField == CreateGameField.PlayerCount:
        model.entryModal.incrementPlayerCount()
    of ActionKind.createGameAppend:
      if model.entryModal.createField == CreateGameField.GameName:
        if proposal.gameActionData.len > 0:
          if model.entryModal.createNameInput.appendChar(
               proposal.gameActionData[0]):
            model.entryModal.createError = ""
    of ActionKind.createGameBackspace:
      if model.entryModal.createField == CreateGameField.GameName:
        model.entryModal.createNameInput.backspace()
        model.entryModal.createError = ""
    of ActionKind.createGameConfirm:
      if model.entryModal.createField == CreateGameField.ConfirmCreate:
        # Validate and create game
        if model.entryModal.createNameInput.isEmpty():
          model.entryModal.setCreateError("Game name is required")
        else:
          # TODO: Send kind 30400 event to create game
          model.statusMessage = "Creating game: " &
            model.entryModal.createGameName() &
            " (" & $model.entryModal.createPlayerCount & " players)"
          model.entryModal.cancelGameCreation()
      elif model.entryModal.createField == CreateGameField.PlayerCount:
        # Enter on player count field moves to next field
        model.entryModal.createFieldDown()
      elif model.entryModal.createField == CreateGameField.GameName:
        # Enter on game name field moves to next field
        model.entryModal.createFieldDown()
    of ActionKind.createGameCancel:
      model.entryModal.cancelGameCreation()
      model.statusMessage = "Game creation cancelled"
    of ActionKind.manageGamesCancel:
      model.entryModal.mode = EntryModalMode.Normal
      model.statusMessage = ""
    of ActionKind.enterExpertMode:
      model.enterExpertMode()
      model.statusMessage = "Expert mode active (type command, ESC to cancel)"
    of ActionKind.exitExpertMode:
      model.exitExpertMode()
      model.statusMessage = ""
    of ActionKind.expertSubmit:
      let matches = matchExpertCommands(model.expertModeInput)
      if matches.len > 0:
        clampExpertPaletteSelection(model)
        let selection = model.expertPaletteSelection
        if selection >= 0 and selection < matches.len:
          let chosen = matches[selection]
          let normalized = normalizeExpertInput(model.expertModeInput)
          let tokens = normalized.splitWhitespace()
          let commandToken = if tokens.len > 0: tokens[0] else: ""
          if commandToken.toLowerAscii() !=
              chosen.command.name.toLowerAscii():
            var newInput = chosen.command.name
            if tokens.len > 1:
              newInput.add(" " & tokens[1..^1].join(" "))
            model.expertModeInput = newInput
            model.clearExpertFeedback()
            model.expertPaletteSelection = 0
            return
      # Parse and execute expert mode command
      let result = parseExpertCommand(model.expertModeInput)
      if result.success:
        # Handle meta commands first
        case result.metaCommand
        of MetaCommandType.Help:
          model.setExpertFeedback(expertCommandHelpText())
          model.addToExpertHistory(model.expertModeInput)
        of MetaCommandType.Clear:
          let count = model.stagedCommandCount()
          model.stagedFleetCommands.setLen(0)
          model.stagedBuildCommands.setLen(0)
          model.stagedRepairCommands.setLen(0)
          model.stagedScrapCommands.setLen(0)
          model.turnSubmissionConfirmed = false
          model.setExpertFeedback("Cleared " & $count & " staged commands")
          model.addToExpertHistory(model.expertModeInput)
        of MetaCommandType.List:
          model.setExpertFeedback(model.stagedCommandsSummary())
          model.addToExpertHistory(model.expertModeInput)
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
                model.turnSubmissionConfirmed = false
                model.setExpertFeedback("Dropped command " & $dropIdx)
              else:
                model.setExpertFeedback("Failed to drop command")
          model.addToExpertHistory(model.expertModeInput)
        of MetaCommandType.Submit:
          if model.stagedCommandCount() > 0:
            model.turnSubmissionRequested = true
            model.turnSubmissionConfirmed = true  # Bypass confirmation
            let count = model.stagedCommandCount()
            model.setExpertFeedback("Submitting " & $count & " commands...")
          else:
            model.setExpertFeedback("No commands to submit")
          model.addToExpertHistory(model.expertModeInput)
        of MetaCommandType.None:
          # Regular command - add to staged commands
          if result.fleetCommand.isSome:
            model.stagedFleetCommands.add(result.fleetCommand.get())
            model.turnSubmissionConfirmed = false
            model.setExpertFeedback(
              "Fleet command staged (total: " &
              $model.stagedFleetCommands.len & ")"
            )
            model.addToExpertHistory(model.expertModeInput)
          elif result.buildCommand.isSome:
            model.stagedBuildCommands.add(result.buildCommand.get())
            model.turnSubmissionConfirmed = false
            model.setExpertFeedback(
              "Build command staged (total: " &
              $model.stagedBuildCommands.len & ")"
            )
            model.addToExpertHistory(model.expertModeInput)
          else:
            model.setExpertFeedback("No command generated")
      else:
        model.setExpertFeedback("Error: " & result.error)
      # Keep expert mode active after submit
      model.expertModeInput = ""
      resetExpertPaletteSelection(model)
    of ActionKind.expertInputAppend:
      # Append character to expert mode input
      model.expertModeInput.add(proposal.gameActionData)
      resetExpertPaletteSelection(model)
    of ActionKind.expertInputBackspace:
      # Remove last character
      if model.expertModeInput.len > 0:
        model.expertModeInput.setLen(model.expertModeInput.len - 1)
      resetExpertPaletteSelection(model)
    of ActionKind.expertHistoryPrev:
      clampExpertPaletteSelection(model)
      if model.expertPaletteSelection > 0:
        model.expertPaletteSelection -= 1
    of ActionKind.expertHistoryNext:
      clampExpertPaletteSelection(model)
      let matches = matchExpertCommands(model.expertModeInput)
      if matches.len == 0:
        model.expertPaletteSelection = -1
      elif model.expertPaletteSelection < matches.len - 1:
        model.expertPaletteSelection += 1
    of ActionKind.submitTurn:
      # Set flag for reactor/main loop to handle
      if model.stagedCommandCount() > 0:
        model.turnSubmissionRequested = true
      else:
        model.statusMessage = "No commands staged - nothing to submit"
        model.turnSubmissionConfirmed = false
    of ActionKind.quitConfirm:
      model.running = false
      model.quitConfirmationActive = false
      model.quitConfirmationChoice = QuitConfirmationChoice.QuitStay
      model.statusMessage = "Exiting..."
    of ActionKind.quitCancel:
      model.quitConfirmationActive = false
      model.quitConfirmationChoice = QuitConfirmationChoice.QuitStay
      model.statusMessage = "Quit cancelled"
    of ActionKind.quitToggle:
      if model.quitConfirmationChoice == QuitConfirmationChoice.QuitStay:
        model.quitConfirmationChoice = QuitConfirmationChoice.QuitExit
      else:
        model.quitConfirmationChoice = QuitConfirmationChoice.QuitStay
    else:
      model.statusMessage = "Action: " & actionKindToStr(proposal.actionKind)
  of ProposalKind.pkSelection:
    if proposal.actionKind == ActionKind.lobbyEnterGame:
      if model.lobbySelectedIdx < model.lobbyActiveGames.len:
        let game = model.lobbyActiveGames[model.lobbySelectedIdx]
        model.loadGameRequested = true
        model.loadGameId = game.id
        model.loadHouseId = game.houseId
        model.statusMessage = "Loading game..."
        model.lobbyInputMode = LobbyInputMode.None
    elif model.mode == ViewMode.Reports and proposal.selectIdx == -1:
      model.mode = ViewMode.ReportDetail
      let report = model.currentReport()
      if report.isSome:
        model.selectedReportId = report.get().id
    elif model.mode == ViewMode.Planets and proposal.selectIdx == -1:
      if model.selectedIdx >= 0 and model.selectedIdx < model.colonies.len:
        model.previousMode = model.mode
        model.mode = ViewMode.PlanetDetail
        model.selectedColonyId = model.colonies[model.selectedIdx].colonyId
        model.resetBreadcrumbs(model.mode)
      else:
        model.statusMessage = "No colony selected"
    elif model.mode == ViewMode.Fleets and proposal.selectIdx == -1:
      if model.selectedIdx >= 0 and model.selectedIdx < model.fleets.len:
        model.previousMode = model.mode
        model.mode = ViewMode.FleetDetail
        model.selectedFleetId = model.fleets[model.selectedIdx].id
        model.resetBreadcrumbs(model.mode)
      else:
        model.statusMessage = "No fleet selected"
    elif model.mode == ViewMode.ReportDetail and proposal.selectIdx == -1:
      let report = model.currentReport()
      if report.isSome:
        let nextMode = viewModeFromInt(report.get().linkView)
        if nextMode.isSome:
          model.previousMode = model.mode
          model.mode = nextMode.get()
          model.resetBreadcrumbs(model.mode)
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
    model.statusMessage = "Error: " & proposal.errorMsg

proc quitAcceptor*(model: var TuiModel, proposal: Proposal) =
  ## Handle quit proposals by showing confirmation
  if proposal.kind != ProposalKind.pkQuit:
    return
  model.quitConfirmationActive = true
  model.quitConfirmationChoice = QuitConfirmationChoice.QuitStay
  model.statusMessage = "Quit? (Y/N)"

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
      model.statusMessage = "Hold order queued for fleet " & $fleetId
  of ActionKind.confirmOrder:
    if model.orderEntryActive:
      # Look up system ID at cursor position
      let cursorCoord = model.mapState.cursor
      let sysOpt = model.systemAt(cursorCoord)
      if sysOpt.isSome:
        let targetSystemId = sysOpt.get().id
        model.confirmOrderEntry(targetSystemId)
        let cmdLabel = commandLabel(model.pendingFleetOrderCommandType)
        model.statusMessage = cmdLabel & " order queued to system " &
          sysOpt.get().name
      else:
        model.statusMessage = "No system at cursor position"
  of ActionKind.cancelOrder:
    if model.orderEntryActive:
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
