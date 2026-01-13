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
import ../daemon/persistence/reader

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

type DaemonCmd* = proc (): Future[Proposal[DaemonModel]]

# =============================================================================
# TEA Update (Pure State Transitions)
# =============================================================================

# Migrate to reactors later
# TEMP: Keep for cmd logic

# =============================================================================
# Command Execution (Async Effects)
# =============================================================================

proc executeCmd(cmd: DaemonCmd): Future[Proposal[DaemonModel]] {.async.} =
  await cmd()

# =============================================================================
# Global State
# =============================================================================

var daemonLoop* {.global.}: DaemonLoop

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
  # Add reactors (impl later)
  # result.addReactor(tickReactor)

proc collectOrdersCmd(gameId: GameId): DaemonCmd =
  proc (): Future[Proposal[DaemonModel]] {.async.} =
    # Stub for collecting orders
    logDebug("Daemon", "Collecting orders stub for game: ", gameId)
    # This should return a proposal like OrderReceived, or a discovery_complete type.
    # For now, just return a dummy proposal
    Proposal[DaemonModel](
      name: "collect_orders_complete",
      payload: proc(model: var DaemonModel) = discard
    )

proc scheduleNextTickCmd(delayMs: int): DaemonCmd =
  proc (): Future[Proposal[DaemonModel]] {.async.} =
    await sleepAsync(delayMs)
    tickProposal()

proc tickProposal(): Proposal[DaemonModel] =
  Proposal[DaemonModel](
    name: "tick",
    payload: proc(model: var DaemonModel) =
      logDebug("Daemon", "Tick")
      daemonLoop.queueCmd(discoverGamesCmd(model.dataDir))
      for id in daemonLoop.model.games.keys.toSeq:
        if id notin daemonLoop.model.resolving:
          daemonLoop.queueCmd(collectOrdersCmd(id))
      daemonLoop.queueCmd(scheduleNextTickCmd(daemonLoop.model.pollInterval * 1000))
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
            let gameId = path.splitFile.name
            let state = reader.loadGameState(dbPath)
            gameDiscoveredProposals.add Proposal[DaemonModel](
              name: "game_discovered",
              payload: proc(model: var DaemonModel) =
                model.games[gameId] = GameInfo(
                  id: gameId,
                  dbPath: dbPath,
                  turn: state.turn,
                  phase: state.phase,
                  transportMode: "localhost", # Stub
    )
            )
    Proposal[DaemonModel](
      name: "discovery_complete",
      payload: proc(model: var DaemonModel) =
        for p in gameDiscoveredProposals:
          daemonLoop.present(p)
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
