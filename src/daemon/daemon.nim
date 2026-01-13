## EC4X Daemon - Autonomous Turn Processing Service
##
## The daemon monitors active games, collects player orders, resolves turns,
## and publishes results—all without human intervention.
##
## Architecture: TEA (The Elm Architecture) pattern with async/await
## - Model: Application state (games, orders, transports)
## - Messages: Events that trigger state changes
## - Update: Pure function that transforms state
## - Commands: Async effects (I/O, network)
##
## See docs/architecture/daemon.md for full design.

import std/[os, tables, sets, times, asyncdispatch, options]
import cligen
import ../common/logger
import ./sam_core

# =============================================================================
# TEA Model (Application State)
# =============================================================================

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
# TEA Messages (Events)
# =============================================================================

# REMOVED: Msg → Proposal[DaemonModel]

# =============================================================================
# TEA Commands (Async Effects)
# =============================================================================

type DaemonCmd* = () -> Future[Proposal[DaemonModel]]

# =============================================================================
# TEA Update (Pure State Transitions)
# =============================================================================

# Migrate to reactors later
# TEMP: Keep for cmd logic

# =============================================================================
# Command Execution (Async Effects)
# =============================================================================

proc executeCmd(cmd: DaemonCmd): Future[Proposal[DaemonModel]] {.async.} =
  cmd()

# =============================================================================
# Main Event Loop
# =============================================================================

proc initModel(dataDir: string, pollInterval: int): DaemonModel =
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
  # Add reactors (impl later)
  # result.addReactor(tickReactor)

proc discoverGamesCmd(dir: string): DaemonCmd =
  () => async:
    let gamesDir = dir / \"games\"
    var proposals = newSeq[Proposal[DaemonModel]]()
    if dirExists(gamesDir):
      for kind, path in walkDir(gamesDir):
        if kind == pcDir:
          let dbPath = path / \"ec4x.db\"
          if fileExists(dbPath):
            let gameId = path.splitFile.name
            let reader = persistence.reader
            let state = reader.loadGameState(dbPath)
            proposals.add Proposal[DaemonModel](
              name: \"game_discovered\",
              payload: proc(model: var DaemonModel) =
                model.games[gameId] = GameInfo(
                  id: gameId,
                  dbPath: dbPath,
                  turn: state.turn,
                  phase: state.phase,
                  transportMode: Localhost,  # Stub
                )
            )
    let discoverP = Proposal[DaemonModel](
      name: \"discover_complete\",
      payload: proc(model: var DaemonModel) = discard
    )
    discoverP

proc tickProposal(pollInterval: int): Proposal[DaemonModel] =
  Proposal[DaemonModel](
    name: \"tick\",
    payload: proc(model: var DaemonModel) =
      logDebug(\"Daemon\", \"Tick\")
      model.loop.queueCmd(discoverGamesCmd(model.dataDir))
      for id in model.games.keys.toSeq:
        if id notin model.resolving:
          model.loop.queueCmd(collectOrdersCmd(id))
      model.loop.queueCmd(scheduleNextTickCmd(model.pollInterval * 1000))
  )

proc scheduleTickCmd(delayMs: int): DaemonCmd =
  () => async:
    await sleepAsync(delayMs)
    tickProposal(delayMs div 1000)

proc mainLoop(dataDir: string, pollInterval: int) {.async.} =
  ## SAM daemon loop
  var daemonLoop {.global.}: DaemonLoop
daemonLoop = newSamLoop(initModel(dataDir, pollInterval))
  
  logInfo("Daemon", "Starting SAM daemon...")
  logInfo("Daemon", "Data directory: ", dataDir)
  logInfo("Daemon", "Poll interval: ", pollInterval, " seconds")

  # Start tick chain
  loop.queueCmd(scheduleTickCmd(0, pollInterval))  # Initial immediate

  while loop.model.running:
    loop.process()
    await sleepAsync(100)  # Non-block poll

  logInfo("Daemon", "Daemon stopped")

# =============================================================================
# CLI Entry Point
# =============================================================================

proc start(
    dataDir: string = "data",
    pollInterval: int = 30
): int =
  ## Start the EC4X daemon
  ##
  ## Args:
  ##   dataDir: Root directory for game data
  ##   pollInterval: Seconds between polls for orders
  logInfo("Daemon", "EC4X Daemon starting...")

  if not dirExists(dataDir):
    logError("Daemon", "Data directory does not exist: ", dataDir)
    return 1

  waitFor mainLoop(dataDir, pollInterval)
  return 0

proc stop(): int =
  ## Stop the EC4X daemon (sends SIGTERM)
  echo "Stop command not yet implemented"
  echo "Use: kill -TERM <pid> or systemctl stop ec4x-daemon"
  return 0

proc status(): int =
  ## Show daemon status
  echo "Status command not yet implemented"
  return 0

proc version(): int =
  ## Display version information
  echo "EC4X Daemon v0.1.0"
  return 0

when isMainModule:
  dispatchMulti(
    [start, help = "Start the daemon"],
    [stop, help = "Stop the daemon"],
    [status, help = "Show daemon status"],
    [version, help = "Show version"]
  )
