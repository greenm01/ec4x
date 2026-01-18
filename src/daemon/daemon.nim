## EC4X Daemon - Autonomous Turn Processing Service
##
## The daemon monitors active games, collects player orders, resolves turns,
## and publishes results—all without human intervention.

import std/[os, tables, sets, times, asyncdispatch, strutils, options]
import cligen
import ../common/logger
import ./sam_core
import ./config
import ./identity
import ./transport/nostr/[types, client, wire, events, filter, crypto]
import ../daemon/persistence/reader
import ../daemon/persistence/writer
import ../daemon/parser/kdl_commands
import ./transport/nostr/delta_kdl
import ./transport/nostr/state_kdl
import ../engine/turn_cycle/engine
import ../engine/config/engine
import ../engine/globals
import ../engine/types/[core, house, command, event, game_state]
import ../engine/state/iterators

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
    identity*: DaemonIdentity              # Nostr keypair
    nostrClient*: NostrClient              # Nostr relay client
    relayUrls*: seq[string]                # Relay URLs from config

type
  DaemonLoop* = SamLoop[DaemonModel]

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
proc publishFullState(gameId: string, state: GameState, houseId: HouseId) {.async.}
proc publishTurnResults(gameId: string, state: GameState) {.async.}
proc resolveTurnCmd(gameId: GameId): DaemonCmd

proc checkAndTriggerResolution(gameId: GameId) =
  ## Check if all expected players have submitted orders
  ## If so, automatically queue turn resolution
  let gameInfo = daemonLoop.model.games[gameId]
  let currentTurn = gameInfo.turn

  # Only auto-resolve games in Active phase
  if gameInfo.phase != "Active":
    logDebug("Daemon", "Game ", gameId, " in phase ", gameInfo.phase, " - skipping auto-resolve")
    return

  let expectedPlayers = countExpectedPlayers(gameInfo.dbPath, gameId)

  # Edge case: No human players yet (all slots unclaimed)
  if expectedPlayers == 0:
    logDebug("Daemon", "No human players assigned yet for game ", gameId)
    return

  let submittedPlayers = countPlayersSubmitted(gameInfo.dbPath, gameId, currentTurn.int32)

  logDebug("Daemon", "Turn readiness check: ", $submittedPlayers, "/", $expectedPlayers,
           " players submitted for game=", gameId, " turn=", $currentTurn)

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
      await publishTurnResults(gameId, state)

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
          daemonLoop.present(p)
    )

proc scheduleNextTickCmd(delayMs: int): DaemonCmd

proc tickProposal(): Proposal[DaemonModel] =
  return Proposal[DaemonModel](
    name: "tick",
    payload: proc(model: var DaemonModel) =
      logInfo("Daemon", "Tick - checking for updates. Managed games: ",
        $model.games.len)
      daemonLoop.queueCmd(discoverGamesCmd(model.dataDir))
      
      # Subscribe to commands for all active games
      for gameId, gameInfo in model.games:
        if model.nostrClient != nil and model.nostrClient.isConnected():
          let subId = "daemon:" & gameId
          if subId notin model.nostrClient.subscriptions:
            asyncCheck model.nostrClient.subscribeDaemon(gameId, model.identity.publicKeyHex)
            logDebug("Nostr", "Subscribed to commands for game: ", gameId)
      
      daemonLoop.queueCmd(scheduleNextTickCmd(model.pollInterval * 1000))
  )

proc scheduleNextTickCmd(delayMs: int): DaemonCmd =
  proc (): Future[Proposal[DaemonModel]] {.async.} =
    await sleepAsync(delayMs)
    return tickProposal()

# =============================================================================
# Nostr Event Processing Helpers
# =============================================================================

proc hexToBytes32(hexStr: string): array[32, byte] =
  ## Convert hex string to 32-byte array
  if hexStr.len != 64:
    raise newException(ValueError, "Invalid hex length: expected 64, got " & $hexStr.len)
  for i in 0..<32:
    let hexByte = hexStr[i*2..i*2+1]
    result[i] = byte(parseHexInt(hexByte))

proc getPlayerPubkey(gameInfo: GameInfo, houseId: HouseId): string =
  ## Get player's Nostr pubkey for a house
  let pubkeyOpt = getHousePubkey(gameInfo.dbPath, gameInfo.id, houseId)
  if pubkeyOpt.isSome:
    return pubkeyOpt.get()
  else:
    return ""

proc buildDeltaKdl(gameInfo: GameInfo, state: GameState, houseId: HouseId): string =
  ## Build fog-of-war filtered delta KDL for a house
  let previousTurn = state.turn - 1
  let previousSnapshot = loadPlayerStateSnapshot(
    gameInfo.dbPath,
    gameInfo.id,
    houseId,
    previousTurn
  )

  let currentSnapshot = buildPlayerStateSnapshot(state, houseId)
  let delta = diffPlayerState(previousSnapshot, currentSnapshot)

  savePlayerStateSnapshot(
    gameInfo.dbPath,
    gameInfo.id,
    houseId,
    state.turn,
    currentSnapshot
  )

  formatPlayerStateDeltaKdl(gameInfo.id, delta)

proc publishFullState(gameId: string, state: GameState, houseId: HouseId) {.async.} =
  ## Publish full state (30405) to a specific house
  try:
    let gameInfo = daemonLoop.model.games[gameId]
    let playerPubkey = getPlayerPubkey(gameInfo, houseId)
    if playerPubkey.len == 0:
      logWarn("Nostr", "No player pubkey for house ", $houseId, " - skipping state publish")
      return

    let daemonPriv = hexToBytes32(daemonLoop.model.identity.privateKeyHex)
    let playerPub = hexToBytes32(playerPubkey)
    let stateKdl = formatPlayerStateKdl(gameId, state, houseId)
    let encryptedPayload = encodePayload(stateKdl, daemonPriv, playerPub)

    var event = createGameState(
      gameId = gameId,
      turn = state.turn.int,
      encryptedPayload = encryptedPayload,
      playerPubkey = playerPubkey,
      daemonPubkey = daemonLoop.model.identity.publicKeyHex
    )
    signEvent(event, daemonPriv)

    let published = await daemonLoop.model.nostrClient.publish(event)
    if published:
      logInfo("Nostr", "Published full state for house ", $houseId)
    else:
      logError("Nostr", "Failed to publish full state for house ", $houseId)

  except CatchableError as e:
    logError("Nostr", "Failed to publish full state: ", e.msg)

proc publishTurnResults(gameId: string, state: GameState) {.async.} =
  ## Publish turn results to all players via Nostr
  try:
    let gameInfo = daemonLoop.model.games[gameId]
    let daemonPriv = hexToBytes32(daemonLoop.model.identity.privateKeyHex)
    
    # Publish delta for each house
    for (houseId, house) in state.allHousesWithId():
      let playerPubkey = getPlayerPubkey(gameInfo, houseId)
      if playerPubkey.len == 0:
        logWarn("Nostr", "No player pubkey for house ", $houseId, " - skipping delta publish")
        continue
      
      # Build fog-of-war filtered delta
      let deltaKdl = buildDeltaKdl(gameInfo, state, houseId)
      
      # Encrypt and encode
      let playerPub = hexToBytes32(playerPubkey)
      let encryptedPayload = encodePayload(deltaKdl, daemonPriv, playerPub)
      
      # Create and sign event
      var event = createTurnResults(
        gameId = gameId,
        turn = state.turn.int,
        encryptedPayload = encryptedPayload,
        playerPubkey = playerPubkey,
        daemonPubkey = daemonLoop.model.identity.publicKeyHex
      )
      signEvent(event, daemonPriv)
      
      # Publish to relays
      let published = await daemonLoop.model.nostrClient.publish(event)
      if published:
        logInfo("Nostr", "Published turn ", $state.turn, " delta for house ", $houseId)
      else:
        logError("Nostr", "Failed to publish delta for house ", $houseId)
    
  except CatchableError as e:
    logError("Nostr", "Failed to publish turn results: ", e.msg)

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
    
    # Get game info
    if not daemonLoop.model.games.hasKey(gameId):
      logWarn("Nostr", "Command for unknown game: ", gameId)
      return
    
    let gameInfo = daemonLoop.model.games[gameId]

    # Validate turn matches current game turn
    if turn != gameInfo.turn:
      logWarn("Nostr", "Command for wrong turn: event has turn=", $turn,
              " but game is on turn=", $gameInfo.turn, " - ignoring")
      return

    # Decrypt command payload
    let daemonPriv = hexToBytes32(daemonLoop.model.identity.privateKeyHex)
    let senderPub = hexToBytes32(event.pubkey)
    let kdlCommands = decodePayload(event.content, daemonPriv, senderPub)

    # Parse KDL into CommandPacket
    let commandPacket = parseOrdersString(kdlCommands)

    # Save to database
    saveCommandPacket(gameInfo.dbPath, gameId, commandPacket)

    logInfo("Nostr", "Received and saved commands for game=", gameId,
            " turn=", $turn, " house=", $commandPacket.houseId)

    # Check if all players have submitted, trigger turn resolution
    checkAndTriggerResolution(gameId)
    
  except CatchableError as e:
    logError("Nostr", "Failed to process command: ", e.msg)

proc processSlotClaim(event: NostrEvent) {.async.} =
  ## Process a slot claim event (30401) from a player
  try:
    let gameIdOpt = event.getGameId()
    let inviteCodeOpt = event.getInviteCode()
    
    if gameIdOpt.isNone or inviteCodeOpt.isNone:
      logError("Nostr", "Slot claim event missing game ID or invite code")
      return
    
    let gameId = gameIdOpt.get()
    let inviteCode = inviteCodeOpt.get()
    let playerPubkey = event.pubkey
    
    # Get game info
    if not daemonLoop.model.games.hasKey(gameId):
      logWarn("Nostr", "Slot claim for unknown game: ", gameId)
      return
    
    let gameInfo = daemonLoop.model.games[gameId]
    
    # TODO: Validate invite code against stored codes
    # For now, assign player to first available house
    # This is a simplified implementation - full version should:
    # 1. Validate invite code hash
    # 2. Check if already claimed
    # 3. Assign specific house based on invite code
    # 4. Publish updated game definition (30400)
    
    # Load current state to find an available house
    let state = loadFullState(gameInfo.dbPath)
    
    # Find first house without a pubkey
    var assignedHouse: Option[HouseId] = none(HouseId)
    for (houseId, house) in state.allHousesWithId():
      let existingPubkey = getPlayerPubkey(gameInfo, houseId)
      if existingPubkey.len == 0:
        assignedHouse = some(houseId)
        break
    
    if assignedHouse.isNone:
      logWarn("Nostr", "No available houses for game: ", gameId)
      return
    
    let houseId = assignedHouse.get()
    
    # Update house with player pubkey
    updateHousePubkey(gameInfo.dbPath, gameId, houseId, playerPubkey)

    # Publish full state immediately after slot claim
    let updatedState = loadFullState(gameInfo.dbPath)
    await publishFullState(gameId, updatedState, houseId)
    
    logInfo("Nostr", "Slot claimed for game=", gameId,
            " house=", $houseId, " player=", playerPubkey[0..7], "...")
    
  except CatchableError as e:
    logError("Nostr", "Failed to process slot claim: ", e.msg)

# =============================================================================
# Main Event Loop
# =============================================================================

proc initModel*(dataDir: string, pollInterval: int, relayUrls: seq[string]): DaemonModel =
  result = DaemonModel(
    games: initTable[GameId, GameInfo](),
    resolving: initHashSet[GameId](),
    pendingOrders: initTable[GameId, int](),
    running: true,
    dataDir: dataDir,
    pollInterval: pollInterval,
    identity: ensureIdentity(),
    nostrClient: nil,  # Will be initialized in mainLoop
    relayUrls: relayUrls
  )
  logInfo("Daemon", "Initialized with identity: ", result.identity.npub())

proc newDaemonLoop(dataDir: string, pollInterval: int, relayUrls: seq[string]): DaemonLoop =
  result = newSamLoop(initModel(dataDir, pollInterval, relayUrls))
  # Add generic acceptor to execute proposal payloads
  result.addAcceptor(proc(model: var DaemonModel, proposal: Proposal[DaemonModel]): bool =
    if proposal.payload == nil:
      logError("Daemon", "Received proposal with nil payload: ", proposal.name)
      return false
    proposal.payload(model)
    return true
  )

proc mainLoop(dataDir: string, pollInterval: int, relayUrls: seq[string]) {.async.} =
  ## SAM daemon loop
  daemonLoop = newDaemonLoop(dataDir, pollInterval, relayUrls)
  
  logInfo("Daemon", "Starting SAM daemon...")
  logInfo("Daemon", "Data directory: ", dataDir)
  logInfo("Daemon", "Poll interval: ", pollInterval, " seconds")
  logInfo("Daemon", "Daemon pubkey: ", daemonLoop.model.identity.npub())

  # Initialize and connect Nostr client
  daemonLoop.model.nostrClient = newNostrClient(relayUrls)
  
  # Set up event callback for incoming commands
  daemonLoop.model.nostrClient.onEvent = proc(subId: string, event: NostrEvent) =
    logDebug("Nostr", "Received event: kind=", $event.kind, " from=", event.pubkey[0..7])
    
    # Handle slot claim events (30401)
    if event.kind == EventKindPlayerSlotClaim:
      asyncCheck processSlotClaim(event)
    
    # Handle turn command events (30402)
    elif event.kind == EventKindTurnCommands:
      let gameIdOpt = event.getGameId()
      if gameIdOpt.isNone:
        logError("Nostr", "Command event missing game ID")
        return
      
      let gameId = gameIdOpt.get()
      if not daemonLoop.model.games.hasKey(gameId):
        logWarn("Nostr", "Received commands for unknown game: ", gameId)
        return
      
      # Queue async command processing
      asyncCheck processIncomingCommand(event)
  
  # Connect to relays
  await daemonLoop.model.nostrClient.connect()
  
  if not daemonLoop.model.nostrClient.isConnected():
    logError("Daemon", "Failed to connect to any relay")
    return
  
  # Start listening for events (non-blocking)
  asyncCheck daemonLoop.model.nostrClient.listen()

  # Start tick chain
  daemonLoop.queueCmd(scheduleNextTickCmd(0))  # Initial immediate

  while daemonLoop.model.running:
    daemonLoop.process()
    await sleepAsync(100)  # Non-block poll

  logInfo("Daemon", "Daemon stopped")

# =============================================================================
# CLI Entry Point
# =============================================================================

proc start(
    dataDir: string = "data",
    pollInterval: int = 30,
    configKdl: string = ""
): int =
  ## Start the EC4X daemon
  var finalDataDir = dataDir
  var finalPollInterval = pollInterval
  var finalRelayUrls: seq[string] = @[]

  if configKdl.len > 0:
    logInfo("Daemon", "Loading config from: ", configKdl)
    let cfg = parseDaemonKdl(configKdl)
    finalDataDir = cfg.data_dir
    finalPollInterval = cfg.poll_interval
    finalRelayUrls = cfg.relay_urls
  else:
    # Default relay
    finalRelayUrls = @["ws://localhost:8080"]

  logInfo("Daemon", "EC4X Daemon starting...")

  if not dirExists(finalDataDir):
    logError("Daemon", "Data directory does not exist: ", finalDataDir)
    return 1

  waitFor mainLoop(finalDataDir, finalPollInterval, finalRelayUrls)
  return 0

proc resolve(gameId: string, dataDir: string = "data"): int =
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
  daemonLoop = newDaemonLoop(dataDir, 30, @["ws://localhost:8080"])

  # Load state
  let state = loadFullState(dbPath)
  let commands = loadOrders(dbPath, state.turn)

  # Resolve
  let result = resolveTurnDeterministic(state, commands)
  
  # Save
  saveFullState(state)
  saveGameEvents(state, result.events)
  markCommandsProcessed(dbPath, gameId, state.turn - 1)

  # Publish turn results via Nostr (if connected)
  if daemonLoop.model.nostrClient != nil:
    waitFor publishTurnResults(gameId, state)
  else:
    logWarn("Daemon", "No Nostr client - skipping result publishing")
  
  logInfo("Daemon", "Resolution complete. Now at turn ", $state.turn)
  return 0

proc stop(): int =
  echo "Stop command not yet implemented"
  return 0

proc status(): int =
  echo "Status command not yet implemented"
  return 0

proc version(): int =
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
