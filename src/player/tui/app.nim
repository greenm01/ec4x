## TUI application entry
##
## Main SAM-based TUI loop and event handling.

import std/[options, strformat, tables, strutils, parseopt, os,
  asyncdispatch, sequtils]

import ../../common/logger
import ../../engine/types/[core, fleet, player_state as ps_types]
import ../../engine/state/engine
import ../../daemon/transport/nostr/[types, events, filter, crypto, nip01]
import ../nostr/client
import ../tui/term/term
import ../tui/buffer
import ../tui/events
import ../tui/input
import ../tui/tty
import ../tui/signals
import ../tui/widget/overview
import ../tui/widget/[hud, breadcrumb, command_dock]
import ../sam/sam_pkg
import ../sam/bindings
import ../state/join_flow
import ../state/lobby_profile
import ../state/order_builder
import ../state/msgpack_serializer
import ../state/msgpack_state
import ../state/tui_cache
import ../state/tui_config
import ../svg/svg_pkg
import ./sync
import ./input_map
import ./view_render
import ./output

proc runTui*(gameId: string = "") =
  ## Main TUI execution (called from player entry point)
  logInfo("TUI Player SAM", "Starting EC4X TUI Player with SAM pattern...")

  # Initialize keybinding registry (single source of truth)
  initBindings()

  # Initialize TUI cache (client-side SQLite)
  var tuiCache = openTuiCache()
  var tuiConfig = loadTuiConfig()
  
  # Enable file logging for TUI (stdout goes to terminal buffer)
  let logDir = getHomeDir() / ".config" / "ec4x"
  enableFileLogging(logDir / "tui.log")
  disableStdoutLogging()

  # Initialize game state
  var gameState = GameState()
  var playerState = ps_types.PlayerState()
  var viewingHouse = HouseId(1)
  var activeGameId = gameId
  var nostrClient: PlayerNostrClient = nil
  var nostrListenerStarted = false
  var nostrSubscriptions: seq[string] = @[]
  var nostrDaemonPubkey = ""
  var nostrGameDefinitionSeen = initTable[string, int64]()

  var nostrHandlers = PlayerNostrHandlers()

  # Initialize terminal
  var tty = openTty()
  if not tty.start():
    logError("TUI Player SAM", "Failed to enter raw mode")
    quit(1)

  setupResizeHandler()
  var (termWidth, termHeight) = tty.windowSize()
  logInfo("TUI Player SAM", &"Terminal size: {termWidth}x{termHeight}")

  var buf = initBuffer(termWidth, termHeight)

  # =========================================================================
  # SAM Setup
  # =========================================================================

  # Create SAM instance with history (for potential undo)
  var sam = initTuiSam(withHistory = true, maxHistory = 50)

  # Create initial model
  var initialModel = initTuiModel()
  initialModel.termWidth = termWidth
  initialModel.termHeight = termHeight
  initialModel.viewingHouse = int(viewingHouse)
  initialModel.mode = ViewMode.Overview

  if gameId.len > 0:
    initialModel.appPhase = AppPhase.InGame
    activeGameId = gameId
    # Load game info from cache instead of daemon's DB
    let cachedGame = tuiCache.getGame(gameId)
    if cachedGame.isSome:
      let gameInfo = cachedGame.get()
      initialModel.turn = gameInfo.turn
      initialModel.houseName = gameInfo.name
    else:
      initialModel.statusMessage = "Game not found in cache"

  proc isPlaceholderGame(game: CachedGame, houseId: int): bool =
    if game.id == "invite":
      return true
    if game.status == "placeholder" or game.status == "invite":
      return true
    if game.relayUrl.len == 0 and game.daemonPubkey.len == 0 and
        game.turn == 0 and houseId == 0:
      return true
    false

  proc isRemovablePlaceholder(game: CachedGame): bool =
    game.id == "invite" or game.status == "placeholder" or
      game.status == "invite"

  if initialModel.lobbyProfilePubkey.len > 0:
    # Run migration from old KDL join cache files
    tuiCache.runMigrations("data", initialModel.lobbyProfilePubkey)
    tuiCache.pruneStaleGames(30)

    # Load games from cache instead of daemon's DB
    let cachedGames = tuiCache.listPlayerGames(initialModel.lobbyProfilePubkey)
    for (game, houseId) in cachedGames:
      if isPlaceholderGame(game, houseId):
        if isRemovablePlaceholder(game):
          tuiCache.deletePlayerSlot(game.id, initialModel.lobbyProfilePubkey)
          tuiCache.deleteGame(game.id)
        continue
      initialModel.lobbyActiveGames.add(ActiveGameInfo(
        id: game.id,
        name: game.name,
        turn: game.turn,
        phase: game.status,
        houseId: houseId
      ))
  else:
    let profiles = loadProfiles("data")
    if profiles.len > 0:
      initialModel.lobbyProfilePubkey = profiles[0]
      let profileInfo = loadProfile("data", initialModel.lobbyProfilePubkey)
      initialModel.lobbyProfileName = profileInfo.name
      initialModel.lobbySessionKeyActive = profileInfo.session

      # Run migration and load from cache
      tuiCache.runMigrations("data", initialModel.lobbyProfilePubkey)
      tuiCache.pruneStaleGames(30)
      let cachedGames = tuiCache.listPlayerGames(initialModel.lobbyProfilePubkey)
      for (game, houseId) in cachedGames:
        if isPlaceholderGame(game, houseId):
          if isRemovablePlaceholder(game):
            tuiCache.deletePlayerSlot(game.id, initialModel.lobbyProfilePubkey)
            tuiCache.deleteGame(game.id)
          continue
        initialModel.lobbyActiveGames.add(ActiveGameInfo(
          id: game.id,
          name: game.name,
          turn: game.turn,
          phase: game.status,
          houseId: houseId
        ))

  # Sync lobbyActiveGames to entryModal.activeGames (includes houseId)
  for game in initialModel.lobbyActiveGames:
    initialModel.entryModal.activeGames.add(EntryActiveGameInfo(
      id: game.id,
      name: game.name,
      turn: game.turn,
      houseName: "",
      houseId: game.houseId,
      status: game.phase
    ))

  # Note: lobbyJoinGames (available games to join) now comes from Nostr events
  # We don't scan daemon's DB anymore - games appear when their definition
  # events arrive from the relay

  # Set default relay URL from config if not provided via entry modal
  if initialModel.entryModal.relayUrl().len > 0:
    initialModel.nostrRelayUrl = initialModel.entryModal.relayUrl()
  elif tuiConfig.defaultRelay.len > 0:
    initialModel.nostrRelayUrl = tuiConfig.defaultRelay

  # Sync game state to model (only after joining a game)
  if initialModel.appPhase == AppPhase.InGame:
    syncGameStateToModel(initialModel, gameState, viewingHouse)
    initialModel.resetBreadcrumbs(initialModel.mode)

    if initialModel.homeworld.isSome:
      initialModel.mapState.cursor = initialModel.homeworld.get

  if initialModel.nostrRelayUrl.len > 0:
    try:
      let identity = initialModel.entryModal.identity
      let relayList = @[initialModel.nostrRelayUrl]

      nostrHandlers.onDelta = proc(event: NostrEvent, payload: string) =
        try:
          let turnOpt = event.getTurn()
          if turnOpt.isNone:
            sam.model.statusMessage = "Ignored event: missing turn"
            return
          if sam.model.playerStateLoaded and
              turnOpt.get() <= sam.model.turn:
            sam.model.statusMessage = "Ignored event: stale turn"
            return
          if event.pubkey.len > 0 and
              nostrDaemonPubkey.len > 0 and
              event.pubkey != nostrDaemonPubkey:
            sam.model.statusMessage = "Ignored event: unknown server"
            return
          let appliedTurnOpt = applyDeltaMsgpack(playerState, payload)
          if appliedTurnOpt.isSome:
            sam.model.turn = int(appliedTurnOpt.get())
            sam.model.playerStateLoaded = true
            sam.model.statusMessage = "Delta applied"
            # Sync PlayerState to model after delta
            syncPlayerStateToModel(sam.model, playerState)
            # Cache the updated state
            if activeGameId.len > 0:
              tuiCache.savePlayerState(activeGameId, int(viewingHouse),
                playerState.turn, playerState)
          else:
            sam.model.statusMessage = "Invalid delta payload"
          sam.present(emptyProposal())
        except CatchableError as e:
          sam.model.nostrLastError = e.msg
          sam.model.nostrStatus = "error"
          sam.model.nostrEnabled = false
          sam.present(emptyProposal())

      nostrHandlers.onFullState = proc(event: NostrEvent, payload: string) =
        try:
          logDebug("TUI/State", "onFullState called",
            "eventId=", event.id[0..min(15, event.id.len-1)],
            "payloadLen=", $payload.len)
          let turnOpt = event.getTurn()
          if turnOpt.isNone:
            sam.model.statusMessage = "Ignored event: missing turn"
            logDebug("TUI/State", "Missing turn tag in event")
            return
          if sam.model.playerStateLoaded and
              turnOpt.get() <= sam.model.turn:
            sam.model.statusMessage = "Ignored event: stale turn"
            return
          if event.pubkey.len > 0 and
              nostrDaemonPubkey.len > 0 and
              event.pubkey != nostrDaemonPubkey:
            sam.model.statusMessage = "Ignored event: unknown server"
            return
          logDebug("TUI/State", "Parsing full state msgpack",
            "payloadLen=", $payload.len)
          let stateOpt = parseFullStateMsgpack(payload)
          if stateOpt.isSome:
            logDebug("TUI/State", "State parsed successfully",
              "turn=", $stateOpt.get().turn,
              "houseId=", $stateOpt.get().viewingHouse)
            playerState = stateOpt.get()
            sam.model.playerStateLoaded = true
            viewingHouse = playerState.viewingHouse
            sam.model.viewingHouse = int(viewingHouse)
            sam.model.turn = int(playerState.turn)
            sam.model.statusMessage = "Full state received"
            if sam.model.nostrEnabled:
              sam.model.nostrStatus = "connected"
            # Sync PlayerState to model
            syncPlayerStateToModel(sam.model, playerState)
            sam.model.resetBreadcrumbs(sam.model.mode)
            if sam.model.homeworld.isSome:
              sam.model.mapState.cursor = sam.model.homeworld.get
            if sam.model.appPhase == AppPhase.Lobby:
              sam.model.appPhase = AppPhase.InGame
              sam.model.mode = ViewMode.Overview
            # Cache the received state for future sessions
            if activeGameId.len > 0:
              tuiCache.savePlayerState(activeGameId, int(viewingHouse),
                playerState.turn, playerState)
          else:
            sam.model.statusMessage = "Invalid full state payload"
            logDebug("TUI/State", "Failed to parse state msgpack",
              "payloadLen=", $payload.len)
          sam.present(emptyProposal())
        except CatchableError as e:
          sam.model.nostrLastError = e.msg
          sam.model.nostrStatus = "error"
          sam.model.nostrEnabled = false
          sam.present(emptyProposal())

      nostrHandlers.onEvent = proc(subId: string, event: NostrEvent) =
        try:
          if event.kind == EventKindGameDefinition:
            let joinRequested = sam.model.nostrJoinRequested
            let joinSent = sam.model.nostrJoinSent
            let joinGameId = sam.model.nostrJoinGameId
            let joinPubkey = sam.model.nostrJoinPubkey
            let gameIdOpt = event.getGameId()
            logDebug("TUI/Join", "GameDef received",
              "gid=", if gameIdOpt.isSome: gameIdOpt.get() else: "",
              "req=", $joinRequested,
              "sent=", $joinSent,
              "jgid=", joinGameId,
              "jpkLen=", $joinPubkey.len,
              "evPkLen=", $event.pubkey.len)
            if gameIdOpt.isSome:
              let gameId = gameIdOpt.get()
              let lastSeen = if nostrGameDefinitionSeen.hasKey(gameId):
                nostrGameDefinitionSeen[gameId]
                else:
                  0'i64
              if event.created_at <= lastSeen:
                sam.model.statusMessage = "Ignored game definition: stale"
                return
              nostrGameDefinitionSeen[gameId] = event.created_at

              if event.pubkey.len > 0 and
                  nostrDaemonPubkey.len > 0 and
                  event.pubkey != nostrDaemonPubkey:
                sam.model.statusMessage = "Ignored game definition: unknown server"
                return

              let nameTag = event.getTagValue(TagName)
              let statusTag = event.getStatus()
              let turnOpt = event.getTurn()
              let gameNameStr = if nameTag.isSome: nameTag.get() else: gameId
              let turnNum = if turnOpt.isSome: turnOpt.get() else: 0
              let gameStatus = if statusTag.isSome: statusTag.get() else: "active"

              if gameStatus == GameStatusCancelled or
                  gameStatus == GameStatusRemoved:
                tuiCache.deletePlayerSlot(gameId, sam.model.lobbyProfilePubkey)
                tuiCache.deleteGame(gameId)
                sam.model.lobbyActiveGames =
                  sam.model.lobbyActiveGames.filterIt(it.id != gameId)
                sam.model.entryModal.activeGames =
                  sam.model.entryModal.activeGames.filterIt(it.id != gameId)
                if gameId == activeGameId:
                  sam.model.statusMessage = "Game removed"
                return

              # Update cache with game metadata from Nostr event
              tuiCache.upsertGame(gameId, gameNameStr, turnNum, gameStatus,
                sam.model.nostrRelayUrl, event.pubkey)

              # Check if player has a slot in this game
              let slotOpt = tuiCache.getPlayerSlot(gameId,
                sam.model.lobbyProfilePubkey)
              let houseIdFromCache = if slotOpt.isSome:
                slotOpt.get().houseId else: 0

              if houseIdFromCache > 0:
                let gameInfo = EntryActiveGameInfo(
                  id: gameId,
                  name: gameNameStr,
                  turn: turnNum,
                  houseName: "",
                  houseId: houseIdFromCache,
                  status: gameStatus
                )
                var updated = false
                for idx in 0..<sam.model.entryModal.activeGames.len:
                  if sam.model.entryModal.activeGames[idx].id == gameId:
                    # Preserve houseId if we had one
                    let existingHouseId =
                      sam.model.entryModal.activeGames[idx].houseId
                    sam.model.entryModal.activeGames[idx] = gameInfo
                    if existingHouseId != 0:
                      sam.model.entryModal.activeGames[idx].houseId =
                        existingHouseId
                    sam.model.entryModal.activeGames[idx].status = gameStatus
                    updated = true
                    break
                if not updated:
                  sam.model.entryModal.activeGames.add(gameInfo)

                var lobbyUpdated = false
                for idx in 0..<sam.model.lobbyActiveGames.len:
                  if sam.model.lobbyActiveGames[idx].id == gameId:
                    sam.model.lobbyActiveGames[idx] = ActiveGameInfo(
                      id: gameId,
                      name: gameNameStr,
                      turn: turnNum,
                      phase: gameStatus,
                      houseId: houseIdFromCache
                    )
                    lobbyUpdated = true
                    break
                if not lobbyUpdated:
                  sam.model.lobbyActiveGames.add(ActiveGameInfo(
                    id: gameId,
                    name: gameNameStr,
                    turn: turnNum,
                    phase: gameStatus,
                    houseId: houseIdFromCache
                  ))
              if gameId == activeGameId and
                  event.pubkey.len > 0 and
                  nostrDaemonPubkey.len == 0:
                nostrDaemonPubkey = event.pubkey
                if nostrClient != nil:
                  nostrClient.setDaemonPubkey(nostrDaemonPubkey)
            if (sam.model.nostrJoinRequested or sam.model.nostrJoinSent) and
                sam.model.nostrJoinGameId.len > 0 and
                event.pubkey.len > 0 and
                sam.model.nostrJoinPubkey.len > 0 and
                gameIdOpt.isSome:
              let slots = event.getSlots()
              logDebug("TUI/Join", "Slots received",
                "count=", $slots.len)
              for slot in slots:
                let slotPk =
                  if slot.pubkey.len > 0:
                    slot.pubkey[0..<min(16, slot.pubkey.len)]
                  else:
                    ""
                let joinPk =
                  if sam.model.nostrJoinPubkey.len > 0:
                    sam.model.nostrJoinPubkey[0..<min(16,
                      sam.model.nostrJoinPubkey.len)]
                  else:
                    ""
                let pubkeyMatch = slot.pubkey == sam.model.nostrJoinPubkey
                logDebug("TUI/Join", "Slot candidate",
                  "idx=", $slot.index,
                  "status=", $slot.status,
                  "pk=", slotPk,
                  "jpk=", joinPk,
                  "match=", $pubkeyMatch)
                if slot.status == SlotStatusClaimed and
                    slot.pubkey == sam.model.nostrJoinPubkey:
                  let joinPubkey = sam.model.nostrJoinPubkey
                  # Use actual game ID from event, not the "invite" placeholder
                  let joinGameId = gameIdOpt.get()
                  let gameName = event.getTagValue(TagName)
                  let turnOpt = event.getTurn()
                  let houseId = HouseId(slot.index.uint32)
                  logDebug("TUI/Join", "Join match",
                    "game=", joinGameId,
                    "house=", $houseId)

                  # Update TUI cache with joined game
                  let gameNameStr = if gameName.isSome: gameName.get()
                                    else: joinGameId
                  let turnNum = if turnOpt.isSome: turnOpt.get() else: 0
                  tuiCache.upsertGame(joinGameId, gameNameStr, turnNum,
                    "active", sam.model.nostrRelayUrl, event.pubkey)
                  tuiCache.insertPlayerSlot(joinGameId, joinPubkey,
                    int(houseId))

                  # Also write legacy join cache for backward compat
                  writeJoinCache("data", joinPubkey, joinGameId, houseId)
                  if gameName.isSome:
                    saveProfile("data", joinPubkey,
                      sam.model.lobbyProfileName,
                      sam.model.lobbySessionKeyActive)

                  # Update in-memory model from cache
                  sam.model.lobbyActiveGames.add(ActiveGameInfo(
                    id: joinGameId,
                    name: gameNameStr,
                    turn: turnNum,
                    phase: "active",
                    houseId: int(houseId)
                  ))

                  # Update entry modal with houseId (or add if not present)
                  var foundGame = false
                  for idx in 0..<sam.model.entryModal.activeGames.len:
                    if sam.model.entryModal.activeGames[idx].id == joinGameId:
                      sam.model.entryModal.activeGames[idx].houseId =
                        int(houseId)
                      sam.model.entryModal.activeGames[idx].status = "active"
                      foundGame = true
                      break
                  if not foundGame:
                    # Add the game if not already in entry modal
                    sam.model.entryModal.activeGames.add(EntryActiveGameInfo(
                      id: joinGameId,
                      name: gameNameStr,
                      turn: turnNum,
                      houseName: "",
                      houseId: int(houseId),
                      status: "active"
                    ))
                  sam.model.lobbyJoinStatus = JoinStatus.Joined
                  sam.model.lobbyJoinError = ""
                  sam.model.statusMessage = "Joined game " & joinGameId
                  sam.model.nostrJoinRequested = false
                  sam.model.nostrJoinSent = false
                  sam.model.nostrJoinInviteCode = ""
                  sam.model.nostrJoinRelayUrl = ""
                  sam.model.nostrJoinGameId = ""
                  sam.model.nostrJoinPubkey = ""
                  sam.model.entryModal.inviteInput.clear()
                  sam.model.entryModal.inviteError = ""
                  break
            sam.present(emptyProposal())
        except CatchableError as e:
          sam.model.nostrLastError = e.msg
          sam.model.nostrStatus = "error"
          sam.model.nostrEnabled = false
          sam.present(emptyProposal())

      nostrHandlers.onJoinError = proc(message: string) =
        if sam.model.lobbyJoinStatus == JoinStatus.WaitingResponse:
          sam.model.lobbyJoinStatus = JoinStatus.Failed
          sam.model.lobbyJoinError = message
          sam.model.statusMessage = message
          sam.model.nostrJoinRequested = false
          sam.model.nostrJoinSent = false
          sam.model.nostrJoinInviteCode = ""
          sam.model.nostrJoinGameId = ""
        sam.present(emptyProposal())

      nostrHandlers.onError = proc(message: string) =
        sam.model.nostrLastError = message
        sam.model.nostrStatus = "error"
        sam.model.nostrEnabled = false
        sam.present(emptyProposal())

      nostrClient = newPlayerNostrClient(
        relayList,
        activeGameId,
        identity.nsecHex,
        identity.npubHex,
        nostrDaemonPubkey,
        nostrHandlers
      )

      asyncCheck nostrClient.start()
      initialModel.nostrStatus = "connecting"
      initialModel.nostrEnabled = true
      
      # Wait for connection to establish (up to 5 seconds)
      for i in 0..50:
        poll(100)
        if nostrClient.isConnected():
          logInfo("Nostr", "Connection established after ", $((i+1)*100), "ms")
          initialModel.nostrStatus = "connected"
          break
      
      if not nostrClient.isConnected():
        logWarn("Nostr", "Connection not established within timeout")
        initialModel.nostrStatus = "error"
    except CatchableError as e:
      initialModel.nostrLastError = e.msg
      initialModel.nostrStatus = "error"
      initialModel.nostrEnabled = false
  
  # Sync initial nostr status to entry modal
  initialModel.entryModal.nostrStatus = initialModel.nostrStatus

  # Set render function (closure captures buf and gameState)
  sam.setRender(
    proc(model: TuiModel) =
      buf.clear()
      renderDashboard(buf, model, gameState, viewingHouse, playerState)
      outputBuffer(buf)
  )

  # Enter alternate screen before initial render
  stdout.write(altScreen())
  stdout.write(hideCursor())
  stdout.flushFile()

  # Set initial state (this triggers initial render)
  sam.setInitialState(initialModel)

  logInfo("TUI Player SAM", "SAM initialized, entering TUI mode...")

  # Create input parser
  var parser = initParser()

  # Initial render
  sam.present(emptyProposal())

  proc processNostr() =
    if sam.model.nostrEnabled and nostrClient != nil:
      if sam.model.nostrStatus == "connecting" and
          nostrClient.isConnected():
        if not nostrListenerStarted:
          asyncCheck nostrClient.listen()
          nostrListenerStarted = true
        let lobbyFilter = newFilter()
          .withKinds(@[EventKindGameDefinition])
        asyncCheck nostrClient.subscribe("lobby:games", @[lobbyFilter])
        nostrSubscriptions.add("lobby:games")
        let joinPubkey = sam.model.entryModal.identity.npubHex
        if joinPubkey.len > 0:
          let joinErrorFilter = newFilter()
            .withKinds(@[EventKindJoinError])
            .withTag(TagP, @[joinPubkey])
          asyncCheck nostrClient.subscribe("lobby:join-errors",
            @[joinErrorFilter])
          nostrSubscriptions.add("lobby:join-errors")
        sam.model.nostrStatus = "connected"
        sam.model.statusMessage = "Nostr connected"

      if sam.model.nostrStatus == "connected" and
          sam.model.entryModal.relayUrl() != sam.model.nostrRelayUrl:
        sam.model.nostrRelayUrl = sam.model.entryModal.relayUrl()
        sam.model.nostrStatus = "error"
        sam.model.nostrLastError = "Relay URL changed - restart required"
        sam.model.nostrEnabled = false
        nostrListenerStarted = false
        nostrSubscriptions.setLen(0)
        nostrDaemonPubkey = ""

      # Subscribe to game events when we have an activeGameId
      # (either in-game or waiting for state in lobby)
      if sam.model.nostrStatus == "connected" and
          activeGameId.len > 0 and
          ("game:" & activeGameId) notin nostrSubscriptions:
        asyncCheck nostrClient.subscribeGame(activeGameId)
        nostrSubscriptions.add("game:" & activeGameId)
        sam.model.statusMessage = "Subscribed to game updates"

      if sam.model.nostrJoinRequested and
          not sam.model.nostrJoinSent and
          sam.model.nostrJoinInviteCode.len > 0:
        # Check if we need to connect to a different relay for this join
        let joinRelay = sam.model.nostrJoinRelayUrl
        if joinRelay.len > 0 and joinRelay != sam.model.nostrRelayUrl:
          # Need to reconnect to the relay specified in the invite code
          sam.model.statusMessage = "Connecting to " & joinRelay
          sam.model.nostrRelayUrl = joinRelay
          # Trigger reconnection by resetting client state
          if nostrClient != nil:
            asyncCheck nostrClient.stop()
            nostrClient = nil
          nostrListenerStarted = false
          nostrSubscriptions.setLen(0)
          nostrDaemonPubkey = ""
          sam.model.nostrStatus = "idle"
          sam.model.nostrEnabled = false
          # Will reconnect on next loop iteration
        elif sam.model.nostrStatus == "connected":
          let identity = sam.model.entryModal.identity
          let privOpt = hexToBytes32Safe(identity.nsecHex)
          if privOpt.isSome:
            let gameId =
              if sam.model.nostrJoinGameId.len > 0:
                sam.model.nostrJoinGameId
              elif sam.model.entryModal.selectedGame().isSome:
                sam.model.entryModal.selectedGame().get().id
              else:
                ""
            let joinTarget = if gameId.len > 0: gameId else: "invite"
            var event = createSlotClaim(
              gameId = joinTarget,
              inviteCode = sam.model.nostrJoinInviteCode,
              playerPubkey = identity.npubHex
            )
            signEvent(event, privOpt.get())
            asyncCheck nostrClient.publish(event)
            sam.model.statusMessage = "Join request sent"
            sam.model.nostrJoinSent = true
            sam.model.nostrJoinRequested = false
            sam.model.nostrJoinGameId = gameId
            sam.model.nostrJoinInviteCode = ""
            sam.model.nostrJoinRelayUrl = ""
            if gameId.len == 0:
              sam.model.nostrJoinGameId = "invite"
          else:
            sam.model.lobbyJoinStatus = JoinStatus.Failed
            sam.model.lobbyJoinError = "Invalid signing key"
            sam.model.statusMessage = sam.model.lobbyJoinError
            sam.model.nostrJoinRequested = false
            sam.model.nostrJoinSent = false
            sam.model.nostrJoinInviteCode = ""
            sam.model.nostrJoinRelayUrl = ""
            sam.model.nostrJoinGameId = ""
            sam.model.nostrJoinPubkey = ""

      if sam.model.nostrStatus == "connected" and
          not nostrClient.isConnected():
        sam.model.nostrStatus = "error"
        sam.model.nostrLastError = "Relay disconnected"
        sam.model.nostrEnabled = false
        nostrListenerStarted = false
        nostrSubscriptions.setLen(0)
        nostrDaemonPubkey = ""

  # =========================================================================
  # Main Loop (SAM-based)
  # =========================================================================

  while sam.state.running:
    # Check for resize
    if checkResize():
      (termWidth, termHeight) = tty.windowSize()
      buf.resize(termWidth, termHeight)
      buf.invalidate()
      sam.present(actionResize(termWidth, termHeight))

    # Process async operations (Nostr events, etc.)
    if hasPendingOperations():
      poll(0)

    processNostr()
    
    # Sync nostr status to entry modal for display
    sam.model.entryModal.nostrStatus = sam.model.nostrStatus

    # Read input with timeout (non-blocking to allow async processing)
    let inputByte = tty.readByteTimeout(50)  # 50ms timeout
    if inputByte == -2:
      # Timeout - no input, but continue to process async events
      let pending = parser.flushPending()
      if pending.len == 0:
        continue
      for event in pending:
        if event.kind == EventKind.Key:
          let proposalOpt = mapKeyEvent(event.keyEvent, sam.model)
          if proposalOpt.isSome:
            sam.present(proposalOpt.get)
      continue
    if inputByte < 0:
      continue

    let events = parser.feedByte(inputByte.uint8)

    for event in events:
      if event.kind == EventKind.Key:
        # Map key event to SAM action
        let proposalOpt = mapKeyEvent(event.keyEvent, sam.model)
        if proposalOpt.isSome:
          sam.present(proposalOpt.get)

    # Poll for join response when waiting
    if sam.model.appPhase == AppPhase.Lobby and
        sam.model.lobbyJoinStatus == JoinStatus.WaitingResponse:
      sam.present(actionLobbyJoinPoll())

    let selectedId =
      if sam.model.entryModal.selectedIdx >= 0 and
          sam.model.entryModal.selectedIdx <
          sam.model.entryModal.activeGames.len:
        sam.model.entryModal.activeGames[sam.model.entryModal.selectedIdx].id
      else:
        ""
    var joinedGames: seq[EntryActiveGameInfo] = @[]
    for game in sam.model.entryModal.activeGames:
      if game.houseId > 0:
        joinedGames.add(game)
    if joinedGames.len != sam.model.entryModal.activeGames.len:
      sam.model.entryModal.activeGames = joinedGames
      if joinedGames.len == 0:
        sam.model.entryModal.selectedIdx = 0
      else:
        var newIdx = 0
        if selectedId.len > 0:
          for idx, game in joinedGames:
            if game.id == selectedId:
              newIdx = idx
              break
        sam.model.entryModal.selectedIdx = newIdx

    if sam.model.entryModal.activeGames.len > 0 and
        sam.model.entryModal.selectedIdx >=
        sam.model.entryModal.activeGames.len:
      sam.model.entryModal.selectedIdx =
        sam.model.entryModal.activeGames.len - 1

    if sam.model.loadGameRequested:
      let gameId = sam.model.loadGameId
      sam.model.playerStateLoaded = false

      # Check for valid houseId
      if sam.model.loadHouseId == 0:
        sam.model.statusMessage = "Cannot load: no house assigned yet"
        sam.model.loadGameRequested = false
      else:
        let houseId = HouseId(sam.model.loadHouseId.uint32)
        
        # Try to load from TUI cache first (for Nostr games)
        let cachedStateOpt = tuiCache.loadLatestPlayerState(gameId,
          int(houseId))
        if cachedStateOpt.isSome:
          playerState = cachedStateOpt.get()
          viewingHouse = houseId
          sam.model.playerStateLoaded = true
          sam.model.appPhase = AppPhase.InGame
          sam.model.viewingHouse = int(houseId)
          sam.model.turn = playerState.turn
          sam.model.mode = ViewMode.Overview
          # Sync PlayerState to model (for Nostr games)
          syncPlayerStateToModel(sam.model, playerState)
          sam.model.resetBreadcrumbs(sam.model.mode)
          if sam.model.homeworld.isSome:
            sam.model.mapState.cursor = sam.model.homeworld.get
          let cachedGame = tuiCache.getGame(gameId)
          let gameName = if cachedGame.isSome: cachedGame.get().name
                         else: gameId
          sam.model.statusMessage = "Loaded game " & gameName
          sam.model.houseName = gameName
          activeGameId = gameId
        else:
          # No cached state - set up for Nostr subscription
          # The game will load when full state arrives via onFullState handler
          activeGameId = gameId
          viewingHouse = houseId
          sam.model.viewingHouse = int(houseId)
          let cachedGame = tuiCache.getGame(gameId)
          let gameName = if cachedGame.isSome: cachedGame.get().name
                         else: gameId
          sam.model.houseName = gameName
          sam.model.statusMessage = "Waiting for game state..."
          # Don't switch to InGame yet - wait for state via Nostr
        sam.model.loadGameRequested = false

      # Re-render to show status
      sam.present(emptyProposal())

    # Handle map export requests (needs GameState access)
    if sam.model.exportMapRequested:
      let gameId = "game_" & $gameState.seed # Use seed as game ID
      let svg = generateStarmap(gameState, viewingHouse)
      let path = exportSvg(svg, gameId, gameState.turn)
      sam.model.lastExportPath = path
      sam.model.statusMessage = "Exported: " & path

      if sam.model.openMapRequested:
        discard openInViewer(path)
        sam.model.statusMessage = "Opened: " & path

      sam.model.exportMapRequested = false
      sam.model.openMapRequested = false

      # Re-render to show status
      sam.present(emptyProposal())

    # Handle pending fleet orders (send via msgpack)
    if sam.model.pendingFleetOrderReady and activeGameId.len > 0:
      if sam.model.nostrEnabled and nostrClient != nil and
          nostrClient.isConnected():
        if nostrDaemonPubkey.len > 0:
          let msgpackCommands = formatFleetOrderMsgpack(
            FleetId(sam.model.pendingFleetOrderFleetId.uint32),
            FleetCommandType(sam.model.pendingFleetOrderCommandType),
            SystemId(sam.model.pendingFleetOrderTargetSystemId.uint32),
            sam.model.turn,
            sam.model.viewingHouse)
          asyncCheck nostrClient.submitCommands(msgpackCommands, sam.model.turn)
          let cmdLabel = commandLabel(
            sam.model.pendingFleetOrderCommandType)
          sam.model.statusMessage = cmdLabel & " order submitted"
        else:
          sam.model.statusMessage = "Waiting for daemon pubkey"
      else:
        let gameDir = "data/games/" & sam.model.houseName
        let orderPath = writeFleetOrderFromModel(gameDir, sam.model)
        if orderPath.len > 0:
          let cmdLabel = commandLabel(sam.model.pendingFleetOrderCommandType)
          sam.model.statusMessage = cmdLabel & " order written: " &
            extractFilename(orderPath)
          logInfo("TUI Player SAM", "Fleet order written: " & orderPath)
      sam.model.clearPendingOrder()

      # Re-render to show status
      sam.present(emptyProposal())

    # Handle turn submission (Ctrl+E pressed)
    if sam.model.turnSubmissionPending:
      # Build command packet from staged commands
      let packet = sam.model.buildCommandPacket(
        gameState.turn.int32,
        viewingHouse
      )

      # Send via Nostr (only supported transport)
      if sam.model.nostrEnabled and nostrClient != nil and
          nostrClient.isConnected():
        let msgpack = serializeCommandPacket(packet)
        asyncCheck nostrClient.submitCommands(msgpack, sam.model.turn)
        sam.model.statusMessage = "Turn submitted"
        logInfo("TUI Player SAM", "Turn submitted via Nostr")
        # Clear staged commands on successful submission
        sam.model.stagedFleetCommands.setLen(0)
        sam.model.stagedBuildCommands.setLen(0)
        sam.model.stagedRepairCommands.setLen(0)
        sam.model.stagedScrapCommands.setLen(0)
      else:
        sam.model.statusMessage = "Cannot submit: not connected to relay"

      sam.model.turnSubmissionPending = false

      # Re-render to show status
      sam.present(emptyProposal())

  # =========================================================================
  # Cleanup
  # =========================================================================

  stdout.write(showCursor())
  stdout.write(exitAltScreen())
  stdout.flushFile()
  discard tty.stop()
  tty.close()

  logInfo("TUI Player SAM", "TUI Player exited.")

proc parseCommandLine*(): tuple[spawnWindow: bool, showHelp: bool,
    gameId: string, cleanCache: string] =
  ## Parse command line arguments
  result = (spawnWindow: true, showHelp: false, gameId: "",
    cleanCache: "")

  var p = initOptParser()
  while true:
    p.next()
    case p.kind
    of cmdEnd:
      break
    of cmdLongOption, cmdShortOption:
      case p.key
      of "no-spawn-window":
        result.spawnWindow = false
      of "spawn-window":
        result.spawnWindow =
          if p.val == "":
            true
          else:
            parseBool(p.val)
      of "game":
        result.gameId = p.val
      of "clean-cache":
        result.cleanCache = p.val
      of "help", "h":
        result.showHelp = true
      else:
        logWarn("TUI Player SAM", "Unknown option: --" & p.key)
        result.showHelp = true
    of cmdArgument:
      logWarn("TUI Player SAM", "Unexpected argument: " & p.key)
      result.showHelp = true

proc showHelp*() =
  logInfo("TUI Player SAM", "Showing help")
  stdout.write("""
EC4X TUI Player

Usage: ec4x-play [options]

Options:
  --spawn-window        Launch in new terminal window (default: true)
  --no-spawn-window     Run in current terminal
  --game <id>           Enter a game directly
  --clean-cache[=mode]  Clear cache (all|games|game:<id>)
  --help, -h            Show this help message

Controls:
  [1-9]    Switch views
  [Ctrl-Q] Quit
  [Esc]    Back
  [C]      Colonies view
  [F]      Fleets view
  [M]      Map view
  [:]      Expert mode (vim-style commands)

See docs/tools/ec4x-play.md for full documentation.
""")
