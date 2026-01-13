## EC4X Daemon - Autonomous Turn Processing Service
##
## The daemon monitors active games, collects player orders, resolves turns,
## and publishes results—all without human intervention.

import std/[os, tables, sets, times, asyncdispatch, options]
import cligen
import ../common/logger
import ./sam_core
import ./config
import ../daemon/persistence/reader
import ../daemon/persistence/writer
import ./transport/localhost/watcher
import ../engine/turn_cycle/engine
import ../engine/state/engine as state_ops
import ../engine/config/engine
import ../engine/globals

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
    transportMode*: string # e.g. "localhost", "nostr"

type
  DaemonModel* = object
    ## Central application state
    games*: Table[GameId, GameInfo]        # All managed games
    resolving*: HashSet[GameId]            # Currently resolving games
    pendingOrders*: Table[GameId, int]     # Count of pending orders per game
    running*: bool                         # Main loop control
    dataDir*: string                       # Root data directory
    pollInterval*: int                     # Seconds between polls

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

proc collectOrdersCmd(gameId: GameId): DaemonCmd =
  proc (): Future[Proposal[DaemonModel]] {.async.} =
    logInfo("Daemon", "Collecting orders for game: ", gameId)
    let gameInfo = daemonLoop.model.games[gameId]
    let packets = collectOrdersLocal(gameInfo.dbPath.parentDir)
    
    for packet in packets:
      saveCommandPacket(gameInfo.dbPath, gameId, packet)
    
    return Proposal[DaemonModel](
      name: "collect_orders_complete",
      payload: proc(model: var DaemonModel) =
        if packets.len > 0:
          if not model.pendingOrders.hasKey(gameId):
            model.pendingOrders[gameId] = 0
          model.pendingOrders[gameId] += packets.len
    )

proc resolveTurnCmd(gameId: GameId): DaemonCmd =
  proc (): Future[Proposal[DaemonModel]] {.async.} =
    logInfo("Daemon", "Resolving turn for game: ", gameId)
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
    
    return Proposal[DaemonModel](
      name: "turn_resolved",
      payload: proc(model: var DaemonModel) =
        model.games[gameId].turn = state.turn
        model.resolving.excl(gameId)
        model.pendingOrders[gameId] = 0
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
        transportMode: "localhost", # Stub
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
      logInfo("Daemon", "Tick - checking for updates. Managed games: ", $model.games.len)
      daemonLoop.queueCmd(discoverGamesCmd(model.dataDir))
      for id in model.games.keys:
        if id notin model.resolving:
          daemonLoop.queueCmd(collectOrdersCmd(id))
      daemonLoop.queueCmd(scheduleNextTickCmd(model.pollInterval * 1000))
  )

proc scheduleNextTickCmd(delayMs: int): DaemonCmd =
  proc (): Future[Proposal[DaemonModel]] {.async.} =
    await sleepAsync(delayMs)
    return tickProposal()

# =============================================================================
# Main Event Loop
# =============================================================================

proc initModel*(dataDir: string, pollInterval: int): DaemonModel =
  result = DaemonModel(
    games: initTable[GameId, GameInfo](),
    resolving: initHashSet[GameId](),
    pendingOrders: initTable[GameId, int](),
    running: true,
    dataDir: dataDir,
    pollInterval: pollInterval
  )

proc newDaemonLoop(dataDir: string, pollInterval: int): DaemonLoop =
  result = newSamLoop(initModel(dataDir, pollInterval))
  # Add generic acceptor to execute proposal payloads
  result.addAcceptor(proc(model: var DaemonModel, proposal: Proposal[DaemonModel]): bool =
    if proposal.payload == nil:
      logError("Daemon", "Received proposal with nil payload: ", proposal.name)
      return false
    proposal.payload(model)
    return true
  )

proc mainLoop(dataDir: string, pollInterval: int) {.async.} =
  ## SAM daemon loop
  daemonLoop = newDaemonLoop(dataDir, pollInterval)
  
  logInfo("Daemon", "Starting SAM daemon...")
  logInfo("Daemon", "Data directory: ", dataDir)
  logInfo("Daemon", "Poll interval: ", pollInterval, " seconds")

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

  if configKdl.len > 0:
    logInfo("Daemon", "Loading config from: ", configKdl)
    let cfg = parseDaemonKdl(configKdl)
    finalDataDir = cfg.data_dir
    finalPollInterval = cfg.poll_interval

  logInfo("Daemon", "EC4X Daemon starting...")

  if not dirExists(finalDataDir):
    logError("Daemon", "Data directory does not exist: ", finalDataDir)
    return 1

  waitFor mainLoop(finalDataDir, finalPollInterval)
  return 0

proc resolve(gameId: string, dataDir: string = "data"): int =
  ## Manually trigger turn resolution for a game
  let gamesDir = dataDir / "games"
  let gameDir = gamesDir / gameId
  let dbPath = gameDir / "ec4x.db"

  if not fileExists(dbPath):
    logError("Daemon", "Game database not found: ", dbPath)
    return 1

  logInfo("Daemon", "Manually resolving game: ", gameId)

  # Load game config (required for calculations)
  gameConfig = loadGameConfig("config")

  # Initialize global loop if needed (some cmds might use it)
  daemonLoop = newDaemonLoop(dataDir, 30)

  # Load state
  let state = loadFullState(dbPath)
  let commands = loadOrders(dbPath, state.turn)

  # Resolve
  let result = resolveTurnDeterministic(state, commands)
  
  # Save
  saveFullState(state)
  saveGameEvents(state, result.events)
  markCommandsProcessed(dbPath, gameId, state.turn - 1)
  
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
