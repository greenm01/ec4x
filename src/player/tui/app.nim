## TUI application entry
##
## Main SAM-based TUI loop and event handling.

import std/[options, strformat, tables, strutils, parseopt, os,
  asyncdispatch, sequtils, sets]

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

  # Initialize player state (TUI now uses PlayerState only, not GameState)
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

  # Create SAM instance (history disabled)
  var sam = initTuiSam()

  # ============================================================================
  # Proposal Queue (async-safe)
  # ============================================================================
 
  type ProposalSignature = tuple[
    kind: ProposalKind,
    actionKind: ActionKind,
    timestamp: int64
  ]

  var proposalQueue: seq[Proposal] = @[]
  var recentProposals = initHashSet[ProposalSignature]()
  const MaxProposalQueue = 100
  
  proc proposalSignature(p: Proposal): ProposalSignature =
    (
      kind: p.kind,
      actionKind: p.actionKind,
      timestamp: p.timestamp
    )
 
  proc enqueueProposal(p: Proposal) =
    let sig = proposalSignature(p)
    if sig in recentProposals:
      return
    if proposalQueue.len >= MaxProposalQueue:
      let old = proposalQueue[0]
      let oldSig = proposalSignature(old)
      recentProposals.excl(oldSig)
      proposalQueue.delete(0)
    proposalQueue.add(p)
    recentProposals.incl(sig)
 
  proc drainProposalQueue() =
    while proposalQueue.len > 0:
      let p = proposalQueue[0]
      proposalQueue.delete(0)
      sam.present(p)

  # Create initial model
  var initialModel = initTuiModel()
  initialModel.ui.termWidth = termWidth
  initialModel.ui.termHeight = termHeight
  initialModel.view.viewingHouse = int(viewingHouse)
  initialModel.ui.mode = ViewMode.Overview

  if gameId.len > 0:
    initialModel.ui.appPhase = AppPhase.InGame
    activeGameId = gameId
    # Load game info from cache instead of daemon's DB
    let cachedGame = tuiCache.getGame(gameId)
    if cachedGame.isSome:
      let gameInfo = cachedGame.get()
      initialModel.view.turn = gameInfo.turn
      initialModel.view.houseName = gameInfo.name
    else:
      initialModel.ui.statusMessage = "Game not found in cache"

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

  if initialModel.ui.lobbyProfilePubkey.len > 0:
    # Run migration from old KDL join cache files
    tuiCache.runMigrations("data", initialModel.ui.lobbyProfilePubkey)
    tuiCache.pruneStaleGames(30)

    # Load games from cache instead of daemon's DB
    let cachedGames = tuiCache.listPlayerGames(
      initialModel.ui.lobbyProfilePubkey
    )
    for (game, houseId) in cachedGames:
      if isPlaceholderGame(game, houseId):
        if isRemovablePlaceholder(game):
          tuiCache.deletePlayerSlot(game.id,
            initialModel.ui.lobbyProfilePubkey)
          tuiCache.deleteGame(game.id)
        continue
      initialModel.view.lobbyActiveGames.add(ActiveGameInfo(
        id: game.id,
        name: game.name,
        turn: game.turn,
        phase: game.status,
        houseId: houseId
      ))
  else:
    let profiles = loadProfiles("data")
    if profiles.len > 0:
      initialModel.ui.lobbyProfilePubkey = profiles[0]
      let profileInfo = loadProfile("data",
        initialModel.ui.lobbyProfilePubkey)
      initialModel.ui.lobbyProfileName = profileInfo.name
      initialModel.ui.lobbySessionKeyActive = profileInfo.session

      # Run migration and load from cache
      tuiCache.runMigrations("data", initialModel.ui.lobbyProfilePubkey)
      tuiCache.pruneStaleGames(30)
      let cachedGames = tuiCache.listPlayerGames(
        initialModel.ui.lobbyProfilePubkey
      )
      for (game, houseId) in cachedGames:
        if isPlaceholderGame(game, houseId):
          if isRemovablePlaceholder(game):
            tuiCache.deletePlayerSlot(game.id,
              initialModel.ui.lobbyProfilePubkey)
            tuiCache.deleteGame(game.id)
          continue
        initialModel.view.lobbyActiveGames.add(ActiveGameInfo(
          id: game.id,
          name: game.name,
          turn: game.turn,
          phase: game.status,
          houseId: houseId
        ))

  # Sync lobbyActiveGames to entryModal.activeGames (includes houseId)
  for game in initialModel.view.lobbyActiveGames:
    initialModel.ui.entryModal.activeGames.add(EntryActiveGameInfo(
      id: game.id,
      name: game.name,
      turn: game.turn,
      houseName: "",
      houseId: game.houseId,
      status: game.phase
    ))

  # Note: lobbyJoinGames (available games to join) comes from Nostr events
  # games appear when their definition events arrive from the relay

  # Set default relay URL from config if not provided via entry modal
  if initialModel.ui.entryModal.relayUrl().len > 0:
    initialModel.ui.nostrRelayUrl = initialModel.ui.entryModal.relayUrl()
  elif tuiConfig.defaultRelay.len > 0:
    initialModel.ui.nostrRelayUrl = tuiConfig.defaultRelay

  # Sync player state to model (only after joining a game)
  if initialModel.ui.appPhase == AppPhase.InGame:
    syncPlayerStateToModel(initialModel, playerState)
    syncBuildModalData(initialModel, playerState)
    initialModel.resetBreadcrumbs(initialModel.ui.mode)

    if initialModel.view.homeworld.isSome:
      initialModel.ui.mapState.cursor = initialModel.view.homeworld.get

  if initialModel.ui.nostrRelayUrl.len > 0:
    try:
      let identity = initialModel.ui.entryModal.identity
      let relayList = @[initialModel.ui.nostrRelayUrl]

      nostrHandlers.onDelta = proc(event: NostrEvent, payload: string) =
        try:
          let turnOpt = event.getTurn()
          if turnOpt.isNone:
            sam.model.ui.statusMessage = "Ignored event: missing turn"
            return
          if sam.model.view.playerStateLoaded and
              turnOpt.get() <= sam.model.view.turn:
            sam.model.ui.statusMessage = "Ignored event: stale turn"
            return
          if event.pubkey.len > 0 and
              nostrDaemonPubkey.len > 0 and
              event.pubkey != nostrDaemonPubkey:
            sam.model.ui.statusMessage = "Ignored event: unknown server"
            return
          let appliedTurnOpt = applyDeltaMsgpack(playerState, payload)
          if appliedTurnOpt.isSome:
            sam.model.view.turn = int(appliedTurnOpt.get())
            sam.model.view.playerStateLoaded = true
            sam.model.ui.statusMessage = "Delta applied"
            # Sync PlayerState to model after delta
            syncPlayerStateToModel(sam.model, playerState)
            # Sync build modal data if active
            syncBuildModalData(sam.model, playerState)
            # Cache the updated state
            if activeGameId.len > 0:
              tuiCache.savePlayerState(activeGameId, int(viewingHouse),
                playerState.turn, playerState)
          else:
            sam.model.ui.statusMessage = "Invalid delta payload"
          enqueueProposal(emptyProposal())
        except CatchableError as e:
          sam.model.ui.nostrLastError = e.msg
          sam.model.ui.nostrStatus = "error"
          sam.model.ui.nostrEnabled = false
          enqueueProposal(emptyProposal())

      nostrHandlers.onFullState = proc(event: NostrEvent, payload: string) =
        try:
          logDebug("TUI/State", "onFullState called",
            "eventId=", event.id[0..min(15, event.id.len-1)],
            "payloadLen=", $payload.len)
          let turnOpt = event.getTurn()
          if turnOpt.isNone:
            sam.model.ui.statusMessage = "Ignored event: missing turn"
            logDebug("TUI/State", "Missing turn tag in event")
            return
          if sam.model.view.playerStateLoaded and
              turnOpt.get() <= sam.model.view.turn:
            sam.model.ui.statusMessage = "Ignored event: stale turn"
            return
          if event.pubkey.len > 0 and
              nostrDaemonPubkey.len > 0 and
              event.pubkey != nostrDaemonPubkey:
            sam.model.ui.statusMessage = "Ignored event: unknown server"
            return
          logDebug("TUI/State", "Parsing full state msgpack",
            "payloadLen=", $payload.len)
          let stateOpt = parseFullStateMsgpack(payload)
          if stateOpt.isSome:
            logDebug("TUI/State", "State parsed successfully",
              "turn=", $stateOpt.get().turn,
              "houseId=", $stateOpt.get().viewingHouse)
            playerState = stateOpt.get()
            sam.model.view.playerStateLoaded = true
            viewingHouse = playerState.viewingHouse
            sam.model.view.viewingHouse = int(viewingHouse)
            sam.model.view.turn = int(playerState.turn)
            sam.model.ui.statusMessage = "Full state received"
            if sam.model.ui.nostrEnabled:
              sam.model.ui.nostrStatus = "connected"
            # Sync PlayerState to model
            syncPlayerStateToModel(sam.model, playerState)
            syncBuildModalData(sam.model, playerState)
            sam.model.resetBreadcrumbs(sam.model.ui.mode)
            if sam.model.view.homeworld.isSome:
              sam.model.ui.mapState.cursor = sam.model.view.homeworld.get
            if sam.model.ui.appPhase == AppPhase.Lobby:
              sam.model.ui.appPhase = AppPhase.InGame
              sam.model.ui.mode = ViewMode.Overview
            # Cache the received state for future sessions
            if activeGameId.len > 0:
              tuiCache.savePlayerState(activeGameId, int(viewingHouse),
                playerState.turn, playerState)
          else:
            sam.model.ui.statusMessage = "Invalid full state payload"
            logDebug("TUI/State", "Failed to parse state msgpack",
              "payloadLen=", $payload.len)
          enqueueProposal(emptyProposal())
        except CatchableError as e:
          sam.model.ui.nostrLastError = e.msg
          sam.model.ui.nostrStatus = "error"
          sam.model.ui.nostrEnabled = false
          enqueueProposal(emptyProposal())

      nostrHandlers.onEvent = proc(subId: string, event: NostrEvent) =
        logInfo("EVENT", "Received event: subId=", subId, " kind=", event.kind,
          " id=", event.id[0..min(8, event.id.len-1)])
        try:
          if event.kind == EventKindGameDefinition:
            let joinRequested = sam.model.ui.nostrJoinRequested
            let joinSent = sam.model.ui.nostrJoinSent
            let joinGameId = sam.model.ui.nostrJoinGameId
            let joinPubkey = sam.model.ui.nostrJoinPubkey
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
                sam.model.ui.statusMessage =
                  "Ignored game definition: stale"
                return
              nostrGameDefinitionSeen[gameId] = event.created_at

              if event.pubkey.len > 0 and
                  nostrDaemonPubkey.len > 0 and
                  event.pubkey != nostrDaemonPubkey:
                sam.model.ui.statusMessage =
                  "Ignored game definition: unknown server"
                return

              let nameTag = event.getTagValue(TagName)
              let statusTag = event.getStatus()
              let turnOpt = event.getTurn()
              let gameNameStr = if nameTag.isSome: nameTag.get() else: gameId
              let turnNum = if turnOpt.isSome: turnOpt.get() else: 0
              let gameStatus = if statusTag.isSome: statusTag.get() else: "active"

              if gameStatus == GameStatusCancelled or
                  gameStatus == GameStatusRemoved:
                tuiCache.deletePlayerSlot(gameId,
                  sam.model.ui.lobbyProfilePubkey)
                tuiCache.deleteGame(gameId)
                sam.model.view.lobbyActiveGames =
                  sam.model.view.lobbyActiveGames.filterIt(it.id != gameId)
                sam.model.ui.entryModal.activeGames =
                  sam.model.ui.entryModal.activeGames.filterIt(it.id != gameId)
                if gameId == activeGameId:
                  sam.model.ui.statusMessage = "Game removed"
                return

              # Update cache with game metadata from Nostr event
              tuiCache.upsertGame(gameId, gameNameStr, turnNum, gameStatus,
                sam.model.ui.nostrRelayUrl, event.pubkey)

              # Check if player has a slot in this game
              let slotOpt = tuiCache.getPlayerSlot(gameId,
                sam.model.ui.lobbyProfilePubkey)
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
                for idx in 0..<sam.model.ui.entryModal.activeGames.len:
                  if sam.model.ui.entryModal.activeGames[idx].id == gameId:
                    # Preserve houseId if we had one
                    let existingHouseId =
                      sam.model.ui.entryModal.activeGames[idx].houseId
                    sam.model.ui.entryModal.activeGames[idx] = gameInfo
                    if existingHouseId != 0:
                      sam.model.ui.entryModal.activeGames[idx].houseId =
                        existingHouseId
                    sam.model.ui.entryModal.activeGames[idx].status =
                      gameStatus
                    updated = true
                    break
                if not updated:
                  sam.model.ui.entryModal.activeGames.add(gameInfo)

                var lobbyUpdated = false
                for idx in 0..<sam.model.view.lobbyActiveGames.len:
                  if sam.model.view.lobbyActiveGames[idx].id == gameId:
                    sam.model.view.lobbyActiveGames[idx] = ActiveGameInfo(
                      id: gameId,
                      name: gameNameStr,
                      turn: turnNum,
                      phase: gameStatus,
                      houseId: houseIdFromCache
                    )
                    lobbyUpdated = true
                    break
                if not lobbyUpdated:
                  sam.model.view.lobbyActiveGames.add(ActiveGameInfo(
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
            logInfo("JOIN", "GameDef event: gameId=",
              if gameIdOpt.isSome: gameIdOpt.get() else: "none",
              " joinReq=", sam.model.ui.nostrJoinRequested,
              " joinSent=", sam.model.ui.nostrJoinSent,
              " joinGameId=", sam.model.ui.nostrJoinGameId,
              " joinPubkey=",
              sam.model.ui.nostrJoinPubkey[0..min(16,
              sam.model.ui.nostrJoinPubkey.len-1)])
            if (sam.model.ui.nostrJoinRequested or
                sam.model.ui.nostrJoinSent) and
                sam.model.ui.nostrJoinGameId.len > 0 and
                event.pubkey.len > 0 and
                sam.model.ui.nostrJoinPubkey.len > 0 and
                gameIdOpt.isSome:
              logInfo("JOIN", "Passed join handler checks, looking for claimed slot...")
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
                  if sam.model.ui.nostrJoinPubkey.len > 0:
                    sam.model.ui.nostrJoinPubkey[0..<min(16,
                      sam.model.ui.nostrJoinPubkey.len)]
                  else:
                    ""
                let pubkeyMatch = slot.pubkey == sam.model.ui.nostrJoinPubkey
                logDebug("TUI/Join", "Slot candidate",
                  "idx=", $slot.index,
                  "status=", $slot.status,
                  "pk=", slotPk,
                  "jpk=", joinPk,
                  "match=", $pubkeyMatch)
                if slot.status == SlotStatusClaimed and
                    slot.pubkey == sam.model.ui.nostrJoinPubkey:
                  let joinPubkey = sam.model.ui.nostrJoinPubkey
                  # Use actual game ID from event, not the "invite" placeholder
                  let joinGameId = gameIdOpt.get()
                  let gameName = event.getTagValue(TagName)
                  let turnOpt = event.getTurn()
                  let houseId = HouseId(slot.index.uint32)
                  logInfo("JOIN", "★★★ FOUND MATCH! Adding game to cache",
                    " game=", joinGameId, " house=", $houseId)

                  # Update TUI cache with joined game
                  let gameNameStr = if gameName.isSome: gameName.get()
                                    else: joinGameId
                  let turnNum = if turnOpt.isSome: turnOpt.get() else: 0
                  logInfo("JOIN", "Writing to cache: game=", joinGameId,
                    " name=", gameNameStr, " turn=", turnNum,
                    " relay=", sam.model.ui.nostrRelayUrl)
                  tuiCache.upsertGame(joinGameId, gameNameStr, turnNum,
                    "active", sam.model.ui.nostrRelayUrl, event.pubkey)
                  tuiCache.insertPlayerSlot(joinGameId, joinPubkey,
                    int(houseId))
                  logInfo("JOIN", "Cache updated successfully")

                  # Also write legacy join cache for backward compat
                  writeJoinCache("data", joinPubkey, joinGameId, houseId)
                  if gameName.isSome:
                    saveProfile("data", joinPubkey,
                      sam.model.ui.lobbyProfileName,
                      sam.model.ui.lobbySessionKeyActive)

                  # Update in-memory model from cache
                  sam.model.view.lobbyActiveGames.add(ActiveGameInfo(
                    id: joinGameId,
                    name: gameNameStr,
                    turn: turnNum,
                    phase: "active",
                    houseId: int(houseId)
                  ))

                  # Update entry modal with houseId (or add if not present)
                  var foundGame = false
                  for idx in 0..<sam.model.ui.entryModal.activeGames.len:
                    if sam.model.ui.entryModal.activeGames[idx].id ==
                        joinGameId:
                      sam.model.ui.entryModal.activeGames[idx].houseId =
                        int(houseId)
                      sam.model.ui.entryModal.activeGames[idx].status =
                        "active"
                      foundGame = true
                      logInfo("JOIN", "Updated existing game in entryModal")
                      break
                  if not foundGame:
                    logInfo("JOIN", "Adding new game to entryModal")
                    # Add the game if not already in entry modal
                    sam.model.ui.entryModal.activeGames.add(
                      EntryActiveGameInfo(
                      id: joinGameId,
                      name: gameNameStr,
                      turn: turnNum,
                      houseName: "",
                      houseId: int(houseId),
                      status: "active"
                    ))
                  sam.model.ui.lobbyJoinStatus = JoinStatus.Joined
                  sam.model.ui.lobbyJoinError = ""
                  sam.model.ui.statusMessage = "Joined game " & joinGameId
                  sam.model.ui.nostrJoinRequested = false
                  sam.model.ui.nostrJoinSent = false
                  sam.model.ui.nostrJoinInviteCode = ""
                  sam.model.ui.nostrJoinRelayUrl = ""
                  sam.model.ui.nostrJoinGameId = ""
                  sam.model.ui.nostrJoinPubkey = ""
                  sam.model.ui.entryModal.inviteInput.clear()
                  sam.model.ui.entryModal.inviteError = ""
                  logInfo("JOIN", "★★★ JOIN COMPLETE! Game should now appear in YOUR GAMES")
                  break
            enqueueProposal(emptyProposal())
        except CatchableError as e:
          sam.model.ui.nostrLastError = e.msg
          sam.model.ui.nostrStatus = "error"
          sam.model.ui.nostrEnabled = false
          enqueueProposal(emptyProposal())

      nostrHandlers.onJoinError = proc(message: string) =
        if sam.model.ui.lobbyJoinStatus == JoinStatus.WaitingResponse:
          sam.model.ui.lobbyJoinStatus = JoinStatus.Failed
          sam.model.ui.lobbyJoinError = message
          sam.model.ui.statusMessage = message
          sam.model.ui.nostrJoinRequested = false
          sam.model.ui.nostrJoinSent = false
          sam.model.ui.nostrJoinInviteCode = ""
          sam.model.ui.nostrJoinGameId = ""
        enqueueProposal(emptyProposal())

      nostrHandlers.onError = proc(message: string) =
        # Log error but don't disable the entire client
        # Individual event decode errors shouldn't kill the connection
        logWarn("Nostr/Error", message)
        sam.model.ui.nostrLastError = message
        # Don't change status or disable - keep processing other events
        enqueueProposal(emptyProposal())

      nostrClient = newPlayerNostrClient(
        relayList,
        activeGameId,
        identity.nsecHex,
        identity.npubHex,
        nostrDaemonPubkey,
        nostrHandlers
      )

      asyncCheck nostrClient.start()
      initialModel.ui.nostrStatus = "connecting"
      initialModel.ui.nostrEnabled = true
      
      # Wait for connection to establish (up to 5 seconds)
      for i in 0..50:
        poll(100)
        if nostrClient.isConnected():
          logInfo("Nostr", "Connection established after ", $((i+1)*100), "ms")
          initialModel.ui.nostrStatus = "connected"

          # Start listening and subscribe to lobby games
          asyncCheck nostrClient.listen()
          nostrListenerStarted = true
          let lobbyFilter = newFilter().withKinds(@[EventKindGameDefinition])
          asyncCheck nostrClient.subscribe("lobby:games", @[lobbyFilter])
          nostrSubscriptions.add("lobby:games")
          logInfo("Nostr", "Subscribed to lobby:games")

          # Subscribe to join errors for this player
          if identity.npubHex.len > 0:
            let joinErrorFilter = newFilter()
              .withKinds(@[EventKindJoinError])
              .withTag(TagP, @[identity.npubHex])
            asyncCheck nostrClient.subscribe("lobby:join-errors", @[joinErrorFilter])
            nostrSubscriptions.add("lobby:join-errors")
            logInfo("Nostr", "Subscribed to lobby:join-errors")
          break

      if not nostrClient.isConnected():
        logWarn("Nostr", "Connection not established within timeout")
        initialModel.ui.nostrStatus = "error"
    except CatchableError as e:
      initialModel.ui.nostrLastError = e.msg
      initialModel.ui.nostrStatus = "error"
      initialModel.ui.nostrEnabled = false
  
  # Sync initial nostr status to entry modal
  initialModel.ui.entryModal.nostrStatus = initialModel.ui.nostrStatus

  # Set render function (closure captures buf and gameState)
  sam.setRender(
    proc(model: TuiModel) =
      buf.clear()
      renderDashboard(buf, model, playerState)
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
    # DEBUG: Check join state
    if sam.model.ui.nostrJoinRequested:
      logInfo("JOIN", "processNostr: joinRequested=true, inviteCode=",
        sam.model.ui.nostrJoinInviteCode,
        " relayUrl=", sam.model.ui.nostrJoinRelayUrl,
        " client=", if nostrClient == nil: "nil" else: "exists",
        " status=", sam.model.ui.nostrStatus)

    # Handle disconnected client that needs reconnection
    if sam.model.ui.nostrJoinRequested and
        sam.model.ui.nostrJoinRelayUrl.len > 0 and
        nostrClient != nil and
        not nostrClient.isConnected():
      logInfo("Nostr/Join", "Reconnecting for invite: ",
        sam.model.ui.nostrJoinRelayUrl)
      asyncCheck nostrClient.stop()
      nostrListenerStarted = false
      nostrSubscriptions.setLen(0)
      nostrDaemonPubkey = ""
      nostrClient = nil
      sam.model.ui.nostrEnabled = false
      sam.model.ui.nostrStatus = "idle"

    # Handle invite join when no client exists
    if sam.model.ui.nostrJoinRequested and
        sam.model.ui.nostrJoinRelayUrl.len > 0 and
        nostrClient == nil:
      logInfo("Nostr/Join", "Creating client for invite relay: ",
        sam.model.ui.nostrJoinRelayUrl)
      sam.model.ui.nostrRelayUrl = sam.model.ui.nostrJoinRelayUrl

      let identity = sam.model.ui.entryModal.identity
      let relayList = @[sam.model.ui.nostrJoinRelayUrl]
      nostrClient = newPlayerNostrClient(
        relayList, activeGameId,
        identity.nsecHex, identity.npubHex,
        nostrDaemonPubkey, nostrHandlers)
      asyncCheck nostrClient.start()
      sam.model.ui.nostrStatus = "connecting"
      sam.model.ui.nostrEnabled = true

      # Wait for connection (up to 3 seconds)
      for i in 0..30:
        poll(100)
        if nostrClient.isConnected():
          logInfo("Nostr/Join", "Connected after ", $((i+1)*100), "ms")
          sam.model.ui.nostrStatus = "connected"
          asyncCheck nostrClient.listen()
          nostrListenerStarted = true
          let lobbyFilter = newFilter().withKinds(@[EventKindGameDefinition])
          asyncCheck nostrClient.subscribe("lobby:games", @[lobbyFilter])
          nostrSubscriptions.add("lobby:games")
          let joinPubkey = identity.npubHex
          if joinPubkey.len > 0:
            let joinErrorFilter = newFilter()
              .withKinds(@[EventKindJoinError])
              .withTag(TagP, @[joinPubkey])
            asyncCheck nostrClient.subscribe("lobby:join-errors",
              @[joinErrorFilter])
            nostrSubscriptions.add("lobby:join-errors")
          break

      if not nostrClient.isConnected():
        logWarn("Nostr/Join", "Failed to connect: ",
          sam.model.ui.nostrJoinRelayUrl)
        sam.model.ui.nostrStatus = "error"
        sam.model.ui.nostrLastError = "Failed to connect to " &
          sam.model.ui.nostrJoinRelayUrl
        sam.model.ui.lobbyJoinStatus = JoinStatus.Failed
        sam.model.ui.lobbyJoinError = "Failed to connect to relay"
        sam.model.ui.statusMessage = sam.model.ui.lobbyJoinError
        sam.model.ui.entryModal.setInviteError(sam.model.ui.lobbyJoinError)
        sam.model.ui.nostrJoinRequested = false
        sam.model.ui.nostrJoinSent = false
        sam.model.ui.nostrJoinInviteCode = ""
        sam.model.ui.nostrJoinRelayUrl = ""
        nostrClient = nil
        sam.model.ui.nostrEnabled = false
        return

    if sam.model.ui.nostrEnabled and nostrClient != nil:
      if sam.model.ui.nostrStatus == "connecting" and
          nostrClient.isConnected():
        if not nostrListenerStarted:
          asyncCheck nostrClient.listen()
          nostrListenerStarted = true
        let lobbyFilter = newFilter()
          .withKinds(@[EventKindGameDefinition])
        asyncCheck nostrClient.subscribe("lobby:games", @[lobbyFilter])
        nostrSubscriptions.add("lobby:games")
        let joinPubkey = sam.model.ui.entryModal.identity.npubHex
        if joinPubkey.len > 0:
          let joinErrorFilter = newFilter()
            .withKinds(@[EventKindJoinError])
            .withTag(TagP, @[joinPubkey])
          asyncCheck nostrClient.subscribe("lobby:join-errors",
            @[joinErrorFilter])
          nostrSubscriptions.add("lobby:join-errors")
        sam.model.ui.nostrStatus = "connected"
        sam.model.ui.statusMessage = "Nostr connected"

      if sam.model.ui.nostrStatus == "connected" and
          sam.model.ui.entryModal.relayUrl() != sam.model.ui.nostrRelayUrl:
        sam.model.ui.nostrRelayUrl = sam.model.ui.entryModal.relayUrl()
        sam.model.ui.nostrStatus = "error"
        sam.model.ui.nostrLastError = "Relay URL changed - restart required"
        sam.model.ui.nostrEnabled = false
        nostrListenerStarted = false
        nostrSubscriptions.setLen(0)
        nostrDaemonPubkey = ""

      # Subscribe to game events when we have an activeGameId
      # (either in-game or waiting for state in lobby)
      if sam.model.ui.nostrStatus == "connected" and
          activeGameId.len > 0 and
          ("game:" & activeGameId) notin nostrSubscriptions:
        asyncCheck nostrClient.subscribeGame(activeGameId)
        nostrSubscriptions.add("game:" & activeGameId)
        sam.model.ui.statusMessage = "Subscribed to game updates"

      if sam.model.ui.nostrJoinRequested and
          not sam.model.ui.nostrJoinSent and
          sam.model.ui.nostrJoinInviteCode.len > 0:
        # Check if we need to connect to a different relay for this join
        let joinRelay = sam.model.ui.nostrJoinRelayUrl
        if joinRelay.len > 0 and joinRelay != sam.model.ui.nostrRelayUrl:
          # Need to reconnect to the relay specified in the invite code
          logInfo("Nostr/Join", "Switching relay for join: ",
            sam.model.ui.nostrRelayUrl, " -> ", joinRelay)
          sam.model.ui.statusMessage = "Connecting to " & joinRelay
          sam.model.ui.nostrRelayUrl = joinRelay
          
          # Stop existing client
          if nostrClient != nil:
            asyncCheck nostrClient.stop()
          nostrListenerStarted = false
          nostrSubscriptions.setLen(0)
          nostrDaemonPubkey = ""
          
          # Create new client for the new relay
          let identity = sam.model.ui.entryModal.identity
          let relayList = @[joinRelay]
          nostrClient = newPlayerNostrClient(
            relayList,
            activeGameId,
            identity.nsecHex,
            identity.npubHex,
            nostrDaemonPubkey,
            nostrHandlers
          )
          asyncCheck nostrClient.start()
          sam.model.ui.nostrStatus = "connecting"
          sam.model.ui.nostrEnabled = true
          
          # Wait for connection (up to 3 seconds)
          for i in 0..30:
            poll(100)
            if nostrClient.isConnected():
              logInfo("Nostr/Join", "Connected to new relay after ",
                $((i+1)*100), "ms")
              sam.model.ui.nostrStatus = "connected"
              # Start listener and subscribe
              asyncCheck nostrClient.listen()
              nostrListenerStarted = true
              let lobbyFilter = newFilter()
                .withKinds(@[EventKindGameDefinition])
              asyncCheck nostrClient.subscribe("lobby:games", @[lobbyFilter])
              nostrSubscriptions.add("lobby:games")
              let joinPubkey = identity.npubHex
              if joinPubkey.len > 0:
                let joinErrorFilter = newFilter()
                  .withKinds(@[EventKindJoinError])
                  .withTag(TagP, @[joinPubkey])
                asyncCheck nostrClient.subscribe("lobby:join-errors",
                  @[joinErrorFilter])
                nostrSubscriptions.add("lobby:join-errors")
              break
          
          if not nostrClient.isConnected():
            logWarn("Nostr/Join", "Failed to connect to ", joinRelay)
            sam.model.ui.nostrStatus = "error"
            sam.model.ui.nostrLastError = "Failed to connect to " & joinRelay
            sam.model.ui.lobbyJoinStatus = JoinStatus.Failed
            sam.model.ui.lobbyJoinError = "Failed to connect to relay"
            sam.model.ui.statusMessage = sam.model.ui.lobbyJoinError
            sam.model.ui.nostrJoinRequested = false
            sam.model.ui.nostrJoinSent = false
            sam.model.ui.nostrJoinInviteCode = ""
            sam.model.ui.nostrJoinRelayUrl = ""
            # Don't proceed with slot claim
          # If connected, fall through to publish slot claim on next iteration
          
        elif sam.model.ui.nostrStatus == "connected":
          let identity = sam.model.ui.entryModal.identity
          let privOpt = hexToBytes32Safe(identity.nsecHex)
          if privOpt.isSome:
            let gameId =
              if sam.model.ui.nostrJoinGameId.len > 0:
                sam.model.ui.nostrJoinGameId
              elif sam.model.ui.entryModal.selectedGame().isSome:
                sam.model.ui.entryModal.selectedGame().get().id
              else:
                ""
            let joinTarget = if gameId.len > 0: gameId else: "invite"
            var event = createSlotClaim(
              gameId = joinTarget,
              inviteCode = sam.model.ui.nostrJoinInviteCode,
              playerPubkey = identity.npubHex
            )
            signEvent(event, privOpt.get())
            
            logInfo("Nostr/Join", "Publishing slot claim",
              " gameId=", joinTarget,
              " inviteCode=", sam.model.ui.nostrJoinInviteCode,
              " eventId=", event.id[0..min(15, event.id.len-1)])
            
            # Publish and wait for result
            let publishFuture = nostrClient.publish(event)
            var published = false
            # Poll for up to 3 seconds for publish result
            for i in 0..30:
              poll(100)
              if publishFuture.finished:
                published = publishFuture.read()
                break
            
            if published:
              logInfo("Nostr/Join", "Slot claim published successfully")
              sam.model.ui.statusMessage = "Join request sent"
              sam.model.ui.nostrJoinSent = true
              sam.model.ui.nostrJoinRequested = false
              sam.model.ui.nostrJoinGameId = if gameId.len > 0:
                gameId else: "invite"
              sam.model.ui.nostrJoinInviteCode = ""
              sam.model.ui.nostrJoinRelayUrl = ""
            else:
              logWarn("Nostr/Join", "Failed to publish slot claim")
              sam.model.ui.lobbyJoinStatus = JoinStatus.Failed
              sam.model.ui.lobbyJoinError = "Failed to send join request"
              sam.model.ui.statusMessage =
                "Join failed - check relay connection"
              sam.model.ui.nostrJoinRequested = false
              sam.model.ui.nostrJoinSent = false
              # Keep invite code so user can retry
          else:
            sam.model.ui.lobbyJoinStatus = JoinStatus.Failed
            sam.model.ui.lobbyJoinError = "Invalid signing key"
            sam.model.ui.statusMessage = sam.model.ui.lobbyJoinError
            sam.model.ui.nostrJoinRequested = false
            sam.model.ui.nostrJoinSent = false
            sam.model.ui.nostrJoinInviteCode = ""
            sam.model.ui.nostrJoinRelayUrl = ""
            sam.model.ui.nostrJoinGameId = ""
            sam.model.ui.nostrJoinPubkey = ""

      if sam.model.ui.nostrStatus == "connected" and
          not nostrClient.isConnected():
        sam.model.ui.nostrStatus = "error"
        sam.model.ui.nostrLastError = "Relay disconnected"
        sam.model.ui.nostrEnabled = false
        nostrListenerStarted = false
        nostrSubscriptions.setLen(0)
        nostrDaemonPubkey = ""

  # =========================================================================
  # Main Loop (SAM-based)
  # =========================================================================

  while sam.state.ui.running:
    # Drain async proposals first (prevents reentrancy)
    drainProposalQueue()

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
    sam.model.ui.entryModal.nostrStatus = sam.model.ui.nostrStatus

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
          # Sync build modal data if modal is active (populates options and dock info)
          if sam.model.ui.buildModal.active:
            syncBuildModalData(sam.model, playerState)

    # Poll for join response when waiting
    if sam.model.ui.appPhase == AppPhase.Lobby and
        sam.model.ui.lobbyJoinStatus == JoinStatus.WaitingResponse:
      sam.present(actionLobbyJoinPoll())

    let selectedId =
      if sam.model.ui.entryModal.selectedIdx >= 0 and
          sam.model.ui.entryModal.selectedIdx <
          sam.model.ui.entryModal.activeGames.len:
        sam.model.ui.entryModal.activeGames[
          sam.model.ui.entryModal.selectedIdx
        ].id
      else:
        ""
    var joinedGames: seq[EntryActiveGameInfo] = @[]
    for game in sam.model.ui.entryModal.activeGames:
      if game.houseId > 0:
        joinedGames.add(game)
    if joinedGames.len != sam.model.ui.entryModal.activeGames.len:
      sam.model.ui.entryModal.activeGames = joinedGames
      if joinedGames.len == 0:
        sam.model.ui.entryModal.selectedIdx = 0
      else:
        var newIdx = 0
        if selectedId.len > 0:
          for idx, game in joinedGames:
            if game.id == selectedId:
              newIdx = idx
              break
        sam.model.ui.entryModal.selectedIdx = newIdx

    if sam.model.ui.entryModal.activeGames.len > 0 and
        sam.model.ui.entryModal.selectedIdx >=
        sam.model.ui.entryModal.activeGames.len:
      sam.model.ui.entryModal.selectedIdx =
        sam.model.ui.entryModal.activeGames.len - 1

    if sam.model.ui.loadGameRequested:
      let gameId = sam.model.ui.loadGameId
      sam.model.view.playerStateLoaded = false

      # Check for valid houseId
      if sam.model.ui.loadHouseId == 0:
        sam.model.ui.statusMessage = "Cannot load: no house assigned yet"
        sam.model.ui.loadGameRequested = false
      else:
        let houseId = HouseId(sam.model.ui.loadHouseId.uint32)
        
        # Try to load from TUI cache first (for Nostr games)
        let cachedStateOpt = tuiCache.loadLatestPlayerState(gameId,
          int(houseId))
        if cachedStateOpt.isSome:
          playerState = cachedStateOpt.get()
          viewingHouse = houseId
          sam.model.view.playerStateLoaded = true
          sam.model.ui.appPhase = AppPhase.InGame
          sam.model.view.viewingHouse = int(houseId)
          sam.model.view.turn = playerState.turn
          sam.model.ui.mode = ViewMode.Overview
          # Sync PlayerState to model (for Nostr games)
          syncPlayerStateToModel(sam.model, playerState)
          syncBuildModalData(sam.model, playerState)
          sam.model.resetBreadcrumbs(sam.model.ui.mode)
          if sam.model.view.homeworld.isSome:
            sam.model.ui.mapState.cursor = sam.model.view.homeworld.get
          let cachedGame = tuiCache.getGame(gameId)
          let gameName = if cachedGame.isSome: cachedGame.get().name
                         else: gameId
          sam.model.ui.statusMessage = "Loaded game " & gameName
          activeGameId = gameId
        else:
          # No cached state - set up for Nostr subscription
          # The game will load when full state arrives via onFullState handler
          activeGameId = gameId
          viewingHouse = houseId
          sam.model.view.viewingHouse = int(houseId)
          let cachedGame = tuiCache.getGame(gameId)
          let gameName = if cachedGame.isSome: cachedGame.get().name
                         else: gameId
          sam.model.view.houseName = gameName
          sam.model.ui.statusMessage = "Waiting for game state..."
          # Don't switch to InGame yet - wait for state via Nostr
        sam.model.ui.loadGameRequested = false

      # Re-render to show status
      sam.present(emptyProposal())

    # Handle map export requests (disabled - requires full GameState)
    if sam.model.ui.exportMapRequested:
      sam.model.ui.statusMessage = "Map export requires local game (not available in Nostr mode)"
      sam.model.ui.exportMapRequested = false
      sam.model.ui.openMapRequested = false

      # Re-render to show status
      sam.present(emptyProposal())

    # Handle pending fleet orders (send via msgpack)
    if sam.model.ui.pendingFleetOrderReady and activeGameId.len > 0:
      if sam.model.ui.nostrEnabled and nostrClient != nil and
          nostrClient.isConnected():
        if nostrDaemonPubkey.len > 0:
          let msgpackCommands = formatFleetOrderMsgpack(
            FleetId(sam.model.ui.pendingFleetOrderFleetId.uint32),
            FleetCommandType(sam.model.ui.pendingFleetOrderCommandType),
            SystemId(sam.model.ui.pendingFleetOrderTargetSystemId.uint32),
            sam.model.view.turn,
            sam.model.view.viewingHouse)
          asyncCheck nostrClient.submitCommands(msgpackCommands,
            sam.model.view.turn)
          let cmdLabel = commandLabel(
            sam.model.ui.pendingFleetOrderCommandType)
          sam.model.ui.statusMessage = cmdLabel & " order submitted"
        else:
          sam.model.ui.statusMessage = "Waiting for daemon pubkey"
      else:
        let gameDir = "data/games/" & sam.model.view.houseName
        let orderPath = writeFleetOrderFromModel(gameDir, sam.model)
        if orderPath.len > 0:
          let cmdLabel = commandLabel(sam.model.ui.pendingFleetOrderCommandType)
          sam.model.ui.statusMessage = cmdLabel & " order written: " &
            extractFilename(orderPath)
          logInfo("TUI Player SAM", "Fleet order written: " & orderPath)
      sam.model.clearPendingOrder()

      # Re-render to show status
      sam.present(emptyProposal())

    # Handle turn submission (Ctrl+E pressed)
    if sam.model.ui.turnSubmissionPending:
      # Build command packet from staged commands
      let packet = sam.model.buildCommandPacket(
        playerState.turn,
        viewingHouse
      )

      # Send via Nostr (only supported transport)
      if sam.model.ui.nostrEnabled and nostrClient != nil and
          nostrClient.isConnected():
        let msgpack = serializeCommandPacket(packet)
        asyncCheck nostrClient.submitCommands(msgpack, sam.model.view.turn)
        sam.model.ui.statusMessage = "Turn submitted"
        logInfo("TUI Player SAM", "Turn submitted via Nostr")
        # Clear staged commands on successful submission
        sam.model.ui.stagedFleetCommands.setLen(0)
        sam.model.ui.stagedBuildCommands.setLen(0)
        sam.model.ui.stagedRepairCommands.setLen(0)
        sam.model.ui.stagedScrapCommands.setLen(0)
      else:
        sam.model.ui.statusMessage =
          "Cannot submit: not connected to relay"

      sam.model.ui.turnSubmissionPending = false

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
    F1-F8    Switch views
    F12      Quit
    Ctrl-C   Quit
    Ctrl-Q   Quit
    Esc      Back
    :        Expert mode (vim-style commands)

See docs/tools/ec4x-play.md for full documentation.
""")
