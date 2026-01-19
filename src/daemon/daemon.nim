## EC4X Daemon - Autonomous Turn Processing Service
##
## The daemon monitors active games, collects player orders, resolves turns,
## and publishes results—all without human intervention.

import std/[os, tables, sets, asyncdispatch, strutils, options]
import cligen
import ../common/logger
import ./sam_core
import ./config
import ./identity
import ./transport/nostr/[types, client, wire, events, crypto]
import ./subscriber
import ./publisher
import ../daemon/persistence/reader
import ../daemon/persistence/writer
import ../common/wordlist

# Replay protection

import ../daemon/parser/kdl_commands
import ../engine/turn_cycle/engine
import ../engine/config/engine
import ../engine/globals
import ../engine/types/[core, command, game_state]

# =============================================================================
# Core Types
# =============================================================================
type
  GameId* = string
  GameInfo* = object
    id*: GameId
    dbPath*: string
    turn*: int
    phase*: string
    transportMode*: string # e.g. "nostr"

type
  DaemonModel* = object
    ## Central application state
    games*: Table[GameId, GameInfo]        # All managed games
    resolving*: HashSet[GameId]            # Currently resolving games
    pendingOrders*: Table[GameId, int]     # Count of pending orders per game
    running*: bool                         # Main loop control
    dataDir*: string                       # Root data directory
    pollInterval*: int                     # Seconds between polls
    replayRetentionTurns*: int             # Replay log turns retention
    replayRetentionDays*: int              # Replay log days retention
    replayRetentionDaysDefinition*: int    # Game definition retention
    replayRetentionDaysState*: int         # State publish retention
    identity*: DaemonIdentity              # Nostr keypair
    nostrClient*: NostrClient              # Nostr relay client
    nostrSubscriber*: Subscriber           # Nostr subscriber wrapper
    nostrPublisher*: Publisher             # Nostr publisher wrapper
    relayUrls*: seq[string]                # Relay URLs from config
    readyLogged*: bool                     # Ready log emitted


type
  DaemonLoop* = SamLoop[DaemonModel]

var shutdownRequested {.global.}: bool = false

# =============================================================================
# Global State
# =============================================================================

var daemonLoop* {.global.}: DaemonLoop

# =============================================================================
# TEA Commands (Async Effects)
# =============================================================================

type DaemonCmd* = proc (): Future[Proposal[DaemonModel]]

# =============================================================================
# Command Helpers
# =============================================================================

# Forward declarations
proc resolveTurnCmd(gameId: GameId): DaemonCmd


proc checkAndTriggerResolution(gameId: GameId) =
  ## Check if all expected players have submitted orders
  ## If so, automatically queue turn resolution
  let gameInfo = daemonLoop.model.games[gameId]
  let currentTurn = gameInfo.turn

  # Only auto-resolve games in Active phase
  if gameInfo.phase != "Active":
    logDebug("Daemon", "Game ", gameId, " in phase ", gameInfo.phase,
      " - skipping auto-resolve")
    return

  let expectedPlayers = countExpectedPlayers(gameInfo.dbPath, gameId)

  # Edge case: No human players yet (all slots unclaimed)
  if expectedPlayers == 0:
    logDebug("Daemon", "No human players assigned yet for game ", gameId)
    return

  let submittedPlayers = countPlayersSubmitted(gameInfo.dbPath, gameId,
    currentTurn.int32)

  logDebug("Daemon", "Turn readiness check: ", $submittedPlayers, "/",
    $expectedPlayers, " players submitted for game=", gameId,
    " turn=", $currentTurn)

  # Check if all players ready
  if submittedPlayers >= expectedPlayers:
    logInfo("Daemon", "All players submitted! Auto-triggering resolution for game=",
      gameId, " turn=", $currentTurn)

    # Guard: Don't queue if already resolving
    if gameId in daemonLoop.model.resolving:
      logWarn("Daemon", "Turn already resolving for game ", gameId, " - skipping")
      return

    daemonLoop.queueCmd(resolveTurnCmd(gameId))
  else:
    logDebug("Daemon", "Waiting for ", $(expectedPlayers - submittedPlayers),
      " more player(s) for turn ", $currentTurn)

proc resolveTurnCmd(gameId: GameId): DaemonCmd =
  proc (): Future[Proposal[DaemonModel]] {.async.} =
    logInfo("Daemon", "Resolving turn for game: ", gameId)

    # Mark as resolving
    daemonLoop.model.resolving.incl(gameId)

    try:
      let gameInfo = daemonLoop.model.games[gameId]

      # 1. Load state and orders
      let state = loadFullState(gameInfo.dbPath)
      let commands = loadOrders(gameInfo.dbPath, state.turn)

      # 2. Resolve turn (deterministic)
      let result = resolveTurnDeterministic(state, commands)

      # 3. Persist results
      saveFullState(state) # Saves NEW turn number and updated entities
      saveGameEvents(state, result.events)
      markCommandsProcessed(gameInfo.dbPath, gameId, state.turn - 1)

      # 4. Publish turn results via Nostr
      if daemonLoop.model.nostrPublisher != nil:
        await daemonLoop.model.nostrPublisher.publishTurnResults(
          gameInfo.id,
          gameInfo.dbPath,
          state
        )

      writer.cleanupProcessedEvents(gameInfo.dbPath, gameId, state.turn.int32,
        daemonLoop.model.replayRetentionTurns,
        daemonLoop.model.replayRetentionDays,
        daemonLoop.model.replayRetentionDaysDefinition,
        daemonLoop.model.replayRetentionDaysState)

      return Proposal[DaemonModel](
        name: "turn_resolved",
        payload: proc(model: var DaemonModel) =
          model.games[gameId].turn = state.turn
          model.resolving.excl(gameId)
          model.pendingOrders[gameId] = 0
      )

    except CatchableError as e:
      logError("Daemon", "Turn resolution failed for game ", gameId, ": ", e.msg)
      # Critical: Clear resolving flag even on failure
      return Proposal[DaemonModel](
        name: "resolution_failed",
        payload: proc(model: var DaemonModel) =
          model.resolving.excl(gameId)
      )

proc createGameDiscoveredProposal(gameId, dbPath, phase: string, turn: int32): Proposal[DaemonModel] =
  let gId = gameId
  let dbP = dbPath
  let turnNum = turn
  let phaseStr = phase
  return Proposal[DaemonModel](
    name: "game_discovered",
    payload: proc(model: var DaemonModel) =
      logDebug("Daemon", "Applying game_discovered for ID: ", gId)
      model.games[gId] = GameInfo(
        id: gId,
        dbPath: dbP,
        turn: turnNum.int,
        phase: phaseStr,
        transportMode: "nostr",
      )
  )

proc discoverGamesCmd(dir: string): DaemonCmd =
  proc (): Future[Proposal[DaemonModel]] {.async.} =
    let gamesDir = dir / "games"
    var gameDiscoveredProposals = newSeq[Proposal[DaemonModel]]()
    if dirExists(gamesDir):
      for kind, path in walkDir(gamesDir):
        if kind == pcDir:
          let dbPath = path / "ec4x.db"
          if fileExists(dbPath):
            let gameId = path.extractFilename
            let state = reader.loadGameState(dbPath)
            if state == nil:
              logError("Daemon", "Failed to load game state for: ", path)
              continue
            
            logInfo("Daemon", "Discovered game: ", state.gameName, " (ID: ", gameId, ") turn: ", $state.turn)
            
            gameDiscoveredProposals.add createGameDiscoveredProposal(
              gameId, dbPath, $state.phase, state.turn
            )
    return Proposal[DaemonModel](
      name: "discovery_complete",
      payload: proc(model: var DaemonModel) =
        for p in gameDiscoveredProposals:
          if p.payload != nil:
            p.payload(model)
        if not model.readyLogged and model.nostrClient != nil and
            model.nostrClient.isConnected():
          if model.games.len > 0:
            logInfo("Daemon", "Ready - managing ", $model.games.len, " games")
            model.readyLogged = true
    )

proc scheduleNextTickCmd(delayMs: int): DaemonCmd

proc tickProposal(): Proposal[DaemonModel] =
  return Proposal[DaemonModel](
    name: "tick",
    payload: proc(model: var DaemonModel) =
      logInfo("Daemon", "Tick - checking for updates. Managed games: ",
        $model.games.len)
      daemonLoop.queueCmd(discoverGamesCmd(model.dataDir))
      
      for gameId, gameInfo in model.games:
        writer.cleanupProcessedEvents(gameInfo.dbPath, gameId,
          gameInfo.turn.int32, model.replayRetentionTurns,
          model.replayRetentionDays, model.replayRetentionDaysDefinition,
          model.replayRetentionDaysState)

      # Subscribe to commands for all active games
      for gameId, gameInfo in model.games:
        if model.nostrSubscriber != nil and model.nostrClient.isConnected():
          let subId = "daemon:" & gameId
          if subId notin model.nostrClient.subscriptions:
            asyncCheck model.nostrSubscriber.subscribeDaemon(gameId,
              model.identity.publicKeyHex)
            logDebug("Nostr", "Subscribed to commands for game: ", gameId)

      daemonLoop.queueCmd(scheduleNextTickCmd(model.pollInterval * 1000))
  )

proc scheduleNextTickCmd(delayMs: int): DaemonCmd =
  proc (): Future[Proposal[DaemonModel]] {.async.} =
    await sleepAsync(delayMs)
    return tickProposal()

proc requestShutdown() {.noconv.} =
  shutdownRequested = true

# =============================================================================
# Nostr Event Processing Helpers
# =============================================================================


proc processIncomingCommand(event: NostrEvent) {.async.} =
  ## Process a turn command event (30402) from a player
  try:
    let gameIdOpt = event.getGameId()
    let turnOpt = event.getTurn()
    
    if gameIdOpt.isNone or turnOpt.isNone:
      logError("Nostr", "Command event missing game ID or turn")
      return
    
    let gameId = gameIdOpt.get()
    let turn = turnOpt.get()

    if not verifyEvent(event):
      let eventId = if event.id.len >= 8: event.id[0..7] else: "unknown"
      logWarn("Nostr", "Invalid command signature for game=", gameId,
        " event=", eventId)
      return
    
    # Get game info
    if not daemonLoop.model.games.hasKey(gameId):
      logWarn("Nostr", "Command for unknown game: ", gameId)
      return
    
    let gameInfo = daemonLoop.model.games[gameId]

    if reader.hasProcessedEvent(gameInfo.dbPath, gameId,
        event.kind, event.id, reader.ReplayDirection.Inbound):
      logWarn("Nostr", "Duplicate command event ignored: ", event.id[0..7])
      return

    # Validate turn matches current game turn
    if turn != gameInfo.turn:
      logWarn("Nostr", "Command for wrong turn: event has turn=", $turn,
        " but game is on turn=", $gameInfo.turn, " - ignoring")
      return

    # Decrypt command payload
    let daemonPriv = crypto.hexToBytes32(daemonLoop.model.identity.privateKeyHex)
    let senderPub = crypto.hexToBytes32(event.pubkey)
    let kdlCommands = decodePayload(event.content, daemonPriv, senderPub)

    # Parse KDL into CommandPacket
    let commandPacket = parseOrdersString(kdlCommands)

    # Save to database
    saveCommandPacket(gameInfo.dbPath, gameId, commandPacket)

    logInfo("Nostr", "Received and saved commands for game=", gameId,
            " turn=", $turn, " house=", $commandPacket.houseId)

    # Check if all players have submitted, trigger turn resolution
    checkAndTriggerResolution(gameId)

    writer.insertProcessedEvent(gameInfo.dbPath, gameId,
      turn.int32, event.kind, event.id, reader.ReplayDirection.Inbound)
    
  except CatchableError as e:
    logError("Nostr", "Failed to process command: ", e.msg)

proc processSlotClaim*(event: NostrEvent) {.async.} =
  ## Process a slot claim event (30401) from a player
  try:
    let gameIdOpt = event.getGameId()
    let inviteCodeOpt = event.getInviteCode()
    
    if gameIdOpt.isNone or inviteCodeOpt.isNone:
      logError("Nostr", "Slot claim event missing game ID or invite code")
      return
    
    let gameId = gameIdOpt.get()
    let inviteCodeRaw = inviteCodeOpt.get()
    let inviteCode = normalizeInviteCode(inviteCodeRaw)
    let playerPubkey = event.pubkey

    if not verifyEvent(event):
      let eventId = if event.id.len >= 8: event.id[0..7] else: "unknown"
      logWarn("Nostr", "Invalid slot claim signature for game=", gameId,
        " event=", eventId)
      return

    # Get game info
    if not daemonLoop.model.games.hasKey(gameId):
      logWarn("Nostr", "Slot claim for unknown game: ", gameId)
      return
    
    let gameInfo = daemonLoop.model.games[gameId]

    if reader.hasProcessedEvent(gameInfo.dbPath, gameId,
        event.kind, event.id, reader.ReplayDirection.Inbound):
      logWarn("Nostr", "Duplicate slot claim ignored: ", event.id[0..7])
      return

    if not isValidInviteCode(inviteCode):
      let eventId = if event.id.len >= 8: event.id[0..7] else: "unknown"
      logWarn("Nostr", "Invalid invite code for game=", gameId,
        " event=", eventId)
      return

    let houseOpt = getHouseByInviteCode(gameInfo.dbPath, gameId, inviteCode)
    if houseOpt.isNone:
      let eventId = if event.id.len >= 8: event.id[0..7] else: "unknown"
      logWarn("Nostr", "Unknown invite code for game=", gameId,
        " event=", eventId)
      return

    if isInviteCodeClaimed(gameInfo.dbPath, gameId, inviteCode):
      let eventId = if event.id.len >= 8: event.id[0..7] else: "unknown"
      logWarn("Nostr", "Invite code already claimed for game=", gameId,
        " event=", eventId)
      return

    let houseId = houseOpt.get()
    
    # Update house with player pubkey
    updateHousePubkey(gameInfo.dbPath, gameId, houseId, playerPubkey)

    # Publish full state immediately after slot claim
    let updatedState = loadFullState(gameInfo.dbPath)
    if daemonLoop.model.nostrPublisher != nil:
      await daemonLoop.model.nostrPublisher.publishFullState(
        gameInfo.id,
        gameInfo.dbPath,
        updatedState,
        houseId
      )
      await daemonLoop.model.nostrPublisher.publishGameDefinition(
        gameInfo.id,
        gameInfo.dbPath,
        gameInfo.phase,
        updatedState
      )
    
    logInfo("Nostr", "Slot claimed for game=", gameId,
            " house=", $houseId, " player=", playerPubkey[0..7], "...")

    writer.insertProcessedEvent(gameInfo.dbPath, gameId,
      0, event.kind, event.id, reader.ReplayDirection.Inbound)
    
  except CatchableError as e:
    logError("Nostr", "Failed to process slot claim: ", e.msg)

# =============================================================================
# Main Event Loop
# =============================================================================

proc initModel*(dataDir: string, pollInterval: int, relayUrls: seq[string],
  replayRetentionTurns: int, replayRetentionDays: int,
  replayRetentionDaysDefinition: int, replayRetentionDaysState: int,
  allowIdentityRegen: bool): DaemonModel =
  result = DaemonModel(
    games: initTable[GameId, GameInfo](),
    resolving: initHashSet[GameId](),
    pendingOrders: initTable[GameId, int](),
    running: true,
    dataDir: dataDir,
    pollInterval: pollInterval,
    replayRetentionTurns: replayRetentionTurns,
    replayRetentionDays: replayRetentionDays,
    replayRetentionDaysDefinition: replayRetentionDaysDefinition,
    replayRetentionDaysState: replayRetentionDaysState,
    identity: ensureIdentity(allowIdentityRegen),
    nostrClient: nil,  # Will be initialized in mainLoop
    nostrSubscriber: nil,
    nostrPublisher: nil,
    relayUrls: relayUrls,
    readyLogged: false
  )
  logInfo("Daemon", "Initialized with identity: ", result.identity.npub())

proc newDaemonLoop(dataDir: string, pollInterval: int, relayUrls: seq[string],
  replayRetentionTurns: int, replayRetentionDays: int,
  replayRetentionDaysDefinition: int, replayRetentionDaysState: int,
  allowIdentityRegen: bool): DaemonLoop =
  result = newSamLoop(initModel(dataDir, pollInterval, relayUrls,
    replayRetentionTurns, replayRetentionDays,
    replayRetentionDaysDefinition, replayRetentionDaysState, allowIdentityRegen))
  # Add generic acceptor to execute proposal payloads
  result.addAcceptor(proc(model: var DaemonModel, proposal: Proposal[DaemonModel]): bool =
    if proposal.payload == nil:
      logError("Daemon", "Received proposal with nil payload: ", proposal.name)
      return false
    proposal.payload(model)
    return true
  )

proc initTestDaemonLoop*(dataDir: string): DaemonLoop =
  result = newDaemonLoop(dataDir, 30, @[], 2, 7, 30, 14, true)

proc mainLoop(dataDir: string, pollInterval: int, relayUrls: seq[string],
  replayRetentionTurns: int, replayRetentionDays: int,
  replayRetentionDaysDefinition: int, replayRetentionDaysState: int,
  allowIdentityRegen: bool) {.async.} =
  ## SAM daemon loop
  daemonLoop = newDaemonLoop(dataDir, pollInterval, relayUrls,
    replayRetentionTurns, replayRetentionDays,
    replayRetentionDaysDefinition, replayRetentionDaysState, allowIdentityRegen)
  
  logInfo("Daemon", "Starting SAM daemon...")
  logInfo("Daemon", "Data directory: ", dataDir)
  logInfo("Daemon", "Poll interval: ", pollInterval, " seconds")
  logInfo("Daemon", "Daemon pubkey: ", daemonLoop.model.identity.npub())

  # Initialize and connect Nostr client
  daemonLoop.model.nostrClient = newNostrClient(relayUrls)
  daemonLoop.model.nostrPublisher = newPublisher(
    daemonLoop.model.nostrClient,
    daemonLoop.model.identity.publicKeyHex,
    crypto.hexToBytes32(daemonLoop.model.identity.privateKeyHex)
  )

  # Set up event callback for incoming commands
  daemonLoop.model.nostrSubscriber = newSubscriber(daemonLoop.model.nostrClient)
  daemonLoop.model.nostrSubscriber.onSlotClaim = proc(event: NostrEvent) =
    try:
      asyncCheck processSlotClaim(event)
    except CatchableError as e:
      let eventId = if event.id.len >= 8: event.id[0..7] else: "unknown"
      logError("Nostr", "Slot claim handler failed: kind=", $event.kind,
        " id=", eventId, " error=", e.msg)
  daemonLoop.model.nostrSubscriber.onCommand = proc(event: NostrEvent) =
    try:
      let gameIdOpt = event.getGameId()
      if gameIdOpt.isNone:
        logError("Nostr", "Command event missing game ID")
        return

      let gameId = gameIdOpt.get()
      if not daemonLoop.model.games.hasKey(gameId):
        logWarn("Nostr", "Received commands for unknown game: ", gameId)
        return

      asyncCheck processIncomingCommand(event)
    except CatchableError as e:
      let eventId = if event.id.len >= 8: event.id[0..7] else: "unknown"
      logError("Nostr", "Event handler failed: kind=", $event.kind,
        " id=", eventId, " error=", e.msg)
  daemonLoop.model.nostrSubscriber.attachHandlers()

  
  # Connect to relays with backoff
  var backoffMs = 1000
  let maxBackoffMs = 10000
  logInfo("Daemon", "Connecting to relays (backoff enabled)")
  while not shutdownRequested:
    await daemonLoop.model.nostrClient.connect()
    if daemonLoop.model.nostrClient.isConnected():
      break
    logWarn("Daemon", "Failed to connect to any relay; retrying in ",
      $backoffMs, "ms")
    await sleepAsync(backoffMs)
    backoffMs = min(backoffMs * 2, maxBackoffMs)

  if not daemonLoop.model.nostrClient.isConnected():
    logError("Daemon", "Failed to connect to any relay")
    return
  
  # Start listening for events (non-blocking)
  asyncCheck daemonLoop.model.nostrClient.listen()

  # Start tick chain
  daemonLoop.queueCmd(scheduleNextTickCmd(0))  # Initial immediate

  while daemonLoop.model.running and not shutdownRequested:
    daemonLoop.process()
    await sleepAsync(100)  # Non-block poll

  if shutdownRequested:
    logInfo("Daemon", "Shutdown requested")
    daemonLoop.model.running = false

  if daemonLoop.model.nostrClient != nil:
    await daemonLoop.model.nostrClient.disconnect()

  logInfo("Daemon", "Daemon stopped")

  shutdownRequested = false

# =============================================================================
# CLI Entry Point
# =============================================================================

proc start*(
    dataDir: string = "data",
    pollInterval: int = 30,
    configKdl: string = ""
): int =
  ## Start the EC4X daemon
  var finalDataDir = dataDir
  var finalPollInterval = pollInterval
  var finalRelayUrls: seq[string] = @[]
  var replayRetentionTurns = 2
  var replayRetentionDays = 7
  var replayRetentionDaysDefinition = 30
  var replayRetentionDaysState = 14

  if configKdl.len > 0:
    logInfo("Daemon", "Loading config from: ", configKdl)
    let cfg = parseDaemonKdl(configKdl)
    finalDataDir = cfg.data_dir
    finalPollInterval = cfg.poll_interval
    finalRelayUrls = cfg.relay_urls
    replayRetentionTurns = cfg.replay_retention_turns
    replayRetentionDays = cfg.replay_retention_days
    replayRetentionDaysDefinition = cfg.replay_retention_days_definition
    replayRetentionDaysState = cfg.replay_retention_days_state
  else:
    # Default relay
    finalRelayUrls = @["ws://localhost:8080"]

  logInfo("Daemon", "EC4X Daemon starting...")

  if finalDataDir.len == 0:
    logError("Daemon", "Data directory is empty")
    return 1

  if not dirExists(finalDataDir):
    logError("Daemon", "Data directory does not exist: ", finalDataDir)
    return 1

  if finalRelayUrls.len == 0:
    logError("Daemon", "No relay URLs configured")
    return 1

  for url in finalRelayUrls:
    if url.len == 0:
      logError("Daemon", "Relay URL is empty")
      return 1

  setControlCHook(requestShutdown)

  let allowIdentityRegen = getEnv("EC4X_REGEN_IDENTITY") == "1"
  if allowIdentityRegen:
    logWarn("DaemonIdentity", "Regenerating identity enabled via env")

  try:
    waitFor mainLoop(finalDataDir, finalPollInterval, finalRelayUrls,
      replayRetentionTurns, replayRetentionDays,
      replayRetentionDaysDefinition, replayRetentionDaysState,
      allowIdentityRegen)
  except CatchableError as e:
    logError("Daemon", "Failed to start daemon: ", e.msg)
    return 1

  return 0

proc resolve*(gameId: string, dataDir: string = "data"): int =
  ## Manually trigger turn resolution for a game
  let gamesDir = dataDir / "games"
  let dbPath = gamesDir / gameId / "ec4x.db"

  if not fileExists(dbPath):
    logError("Daemon", "Game database not found: ", dbPath)
    return 1

  logInfo("Daemon", "Manually resolving game: ", gameId)

  # Load game config (required for calculations)
  gameConfig = loadGameConfig("config")

  # Initialize global loop if needed (some cmds might use it)
  let daemonConfig = parseDaemonKdl("config/daemon.kdl")
  daemonLoop = newDaemonLoop(dataDir, 30, daemonConfig.relay_urls,
    daemonConfig.replay_retention_turns, daemonConfig.replay_retention_days,
    daemonConfig.replay_retention_days_definition,
    daemonConfig.replay_retention_days_state, true)
  daemonLoop.model.nostrClient = newNostrClient(daemonConfig.relay_urls)
  daemonLoop.model.nostrPublisher = newPublisher(
    daemonLoop.model.nostrClient,
    daemonLoop.model.identity.publicKeyHex,
    crypto.hexToBytes32(daemonLoop.model.identity.privateKeyHex)
  )

  # Load state
  let state = loadFullState(dbPath)
  let commands = loadOrders(dbPath, state.turn)

  # Resolve
  let resolution = resolveTurnDeterministic(state, commands)
  
  # Save
  saveFullState(state)
  saveGameEvents(state, resolution.events)
  markCommandsProcessed(dbPath, gameId, state.turn - 1)

  # Publish turn results via Nostr (if connected)
  if daemonLoop.model.nostrPublisher != nil:
    let gameInfo = daemonLoop.model.games[gameId]
    waitFor daemonLoop.model.nostrPublisher.publishTurnResults(
      gameInfo.id,
      gameInfo.dbPath,
      state
    )
  else:
    logWarn("Daemon", "No Nostr publisher - skipping result publishing")
  
  logInfo("Daemon", "Resolution complete. Now at turn ", $state.turn)
  return 0

proc stop*(): int =
  echo "Stop command not yet implemented"
  return 0

proc status*(): int =
  echo "Status command not yet implemented"
  return 0

proc version*(): int =
  echo "EC4X Daemon v0.1.0"
  return 0

when isMainModule:
  dispatchMulti(
    [start, help = "Start the daemon"],
    [stop, help = "Stop the daemon"],
    [status, help = "Show daemon status"],
    [resolve, help = "Manually resolve a turn"],
    [version, help = "Show version"]
  )
