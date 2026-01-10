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

# =============================================================================
# TEA Model (Application State)
# =============================================================================

type
  GameId* = string

  TransportMode* {.pure.} = enum
    Localhost
    Nostr

  GameInfo* = object
    id*: GameId
    name*: string
    dbPath*: string
    turn*: int
    phase*: string
    transportMode*: TransportMode
    turnDeadline*: Option[Time]

  DaemonModel* = object
    ## Central application state
    games*: Table[GameId, GameInfo]        # All managed games
    resolving*: HashSet[GameId]            # Currently resolving games
    pendingOrders*: Table[GameId, int]     # Count of pending orders per game
    running*: bool                         # Main loop control
    dataDir*: string                       # Root data directory
    pollInterval*: int                     # Seconds between polls

# =============================================================================
# TEA Messages (Events)
# =============================================================================

type
  MsgKind* {.pure.} = enum
    Tick                    # Periodic timer tick
    GameDiscovered          # New game found
    GameRemoved             # Game no longer exists
    OrderReceived           # Player submitted orders
    AllOrdersReceived       # All houses submitted orders
    DeadlineReached         # Turn deadline passed
    TurnResolving           # Turn resolution started
    TurnResolved            # Turn resolution completed
    ResultsPublished        # Results sent to players
    Shutdown                # Graceful shutdown requested
    Error                   # Error occurred

  DaemonMsg* = object
    case kind*: MsgKind
    of Tick:
      timestamp*: Time
    of GameDiscovered:
      gameDir*: string
    of GameRemoved, OrderReceived, AllOrdersReceived, DeadlineReached,
       TurnResolving, TurnResolved, ResultsPublished:
      gameId*: GameId
    of Shutdown:
      discard
    of Error:
      errorMsg*: string
      errorGameId*: Option[GameId]

# =============================================================================
# TEA Commands (Async Effects)
# =============================================================================

type
  CmdKind* {.pure.} = enum
    None
    DiscoverGames
    LoadGame
    CollectOrders
    ResolveTurn
    PublishResults
    ScheduleNextTick

  DaemonCmd* = object
    case kind*: CmdKind
    of None:
      discard
    of DiscoverGames:
      scanDir*: string
    of LoadGame:
      loadGameDir*: string
    of CollectOrders, ResolveTurn, PublishResults:
      cmdGameId*: GameId
    of ScheduleNextTick:
      delayMs*: int

# =============================================================================
# TEA Update (Pure State Transitions)
# =============================================================================

proc update*(msg: DaemonMsg, model: DaemonModel): (DaemonModel, seq[DaemonCmd]) =
  ## Pure function - no I/O, no side effects
  ## Returns new model state and commands to execute
  var newModel = model
  var cmds: seq[DaemonCmd] = @[]

  case msg.kind

  of MsgKind.Tick:
    logDebug("Daemon", "Tick at ", msg.timestamp)
    # Schedule game discovery and order collection
    cmds.add(DaemonCmd(kind: CmdKind.DiscoverGames, scanDir: model.dataDir))
    for gameId in model.games.keys:
      if gameId notin model.resolving:
        cmds.add(DaemonCmd(kind: CmdKind.CollectOrders, cmdGameId: gameId))
    # Schedule next tick
    cmds.add(DaemonCmd(kind: CmdKind.ScheduleNextTick,
                       delayMs: model.pollInterval * 1000))

  of MsgKind.GameDiscovered:
    logInfo("Daemon", "Game discovered: ", msg.gameDir)
    cmds.add(DaemonCmd(kind: CmdKind.LoadGame, loadGameDir: msg.gameDir))

  of MsgKind.GameRemoved:
    logInfo("Daemon", "Game removed: ", msg.gameId)
    if msg.gameId in newModel.games:
      newModel.games.del(msg.gameId)
    if msg.gameId in newModel.pendingOrders:
      newModel.pendingOrders.del(msg.gameId)

  of MsgKind.OrderReceived:
    logInfo("Daemon", "Order received for game: ", msg.gameId)
    if msg.gameId in newModel.pendingOrders:
      newModel.pendingOrders[msg.gameId] += 1

  of MsgKind.AllOrdersReceived:
    logInfo("Daemon", "All orders received for game: ", msg.gameId)
    if msg.gameId notin newModel.resolving:
      cmds.add(DaemonCmd(kind: CmdKind.ResolveTurn, cmdGameId: msg.gameId))

  of MsgKind.DeadlineReached:
    logInfo("Daemon", "Deadline reached for game: ", msg.gameId)
    if msg.gameId notin newModel.resolving:
      cmds.add(DaemonCmd(kind: CmdKind.ResolveTurn, cmdGameId: msg.gameId))

  of MsgKind.TurnResolving:
    logInfo("Daemon", "Turn resolving for game: ", msg.gameId)
    newModel.resolving.incl(msg.gameId)

  of MsgKind.TurnResolved:
    logInfo("Daemon", "Turn resolved for game: ", msg.gameId)
    newModel.resolving.excl(msg.gameId)
    newModel.pendingOrders[msg.gameId] = 0
    cmds.add(DaemonCmd(kind: CmdKind.PublishResults, cmdGameId: msg.gameId))

  of MsgKind.ResultsPublished:
    logInfo("Daemon", "Results published for game: ", msg.gameId)

  of MsgKind.Shutdown:
    logInfo("Daemon", "Shutdown requested")
    newModel.running = false

  of MsgKind.Error:
    if msg.errorGameId.isSome:
      logError("Daemon", "Error in game ", msg.errorGameId.get, ": ",
               msg.errorMsg)
    else:
      logError("Daemon", "Error: ", msg.errorMsg)

  return (newModel, cmds)

# =============================================================================
# Command Execution (Async Effects)
# =============================================================================

proc executeCmd*(cmd: DaemonCmd, model: DaemonModel): Future[Option[DaemonMsg]]
    {.async.} =
  ## Execute a command and return resulting message (if any)
  case cmd.kind

  of CmdKind.None:
    return none(DaemonMsg)

  of CmdKind.DiscoverGames:
    # Scan for game directories
    let gamesDir = cmd.scanDir / "games"
    if dirExists(gamesDir):
      for kind, path in walkDir(gamesDir):
        if kind == pcDir:
          let dbPath = path / "ec4x.db"
          if fileExists(dbPath):
            let gameId = path.lastPathPart
            if gameId notin model.games:
              return some(DaemonMsg(kind: MsgKind.GameDiscovered,
                                    gameDir: path))
    return none(DaemonMsg)

  of CmdKind.LoadGame:
    # TODO: Load game from database
    logInfo("Daemon", "Loading game from: ", cmd.loadGameDir)
    return none(DaemonMsg)

  of CmdKind.CollectOrders:
    # TODO: Check for pending orders (filesystem or Nostr)
    logDebug("Daemon", "Collecting orders for game: ", cmd.cmdGameId)
    return none(DaemonMsg)

  of CmdKind.ResolveTurn:
    # TODO: Run turn resolution engine
    logInfo("Daemon", "Resolving turn for game: ", cmd.cmdGameId)
    return some(DaemonMsg(kind: MsgKind.TurnResolving, gameId: cmd.cmdGameId))

  of CmdKind.PublishResults:
    # TODO: Publish results to players
    logInfo("Daemon", "Publishing results for game: ", cmd.cmdGameId)
    return some(DaemonMsg(kind: MsgKind.ResultsPublished,
                          gameId: cmd.cmdGameId))

  of CmdKind.ScheduleNextTick:
    await sleepAsync(cmd.delayMs)
    return some(DaemonMsg(kind: MsgKind.Tick, timestamp: getTime()))

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

proc mainLoop(dataDir: string, pollInterval: int) {.async.} =
  ## TEA-style event loop
  var model = initModel(dataDir, pollInterval)
  var pendingFutures: seq[Future[Option[DaemonMsg]]] = @[]

  logInfo("Daemon", "Starting daemon...")
  logInfo("Daemon", "Data directory: ", dataDir)
  logInfo("Daemon", "Poll interval: ", pollInterval, " seconds")

  # Initial tick to start discovery
  var (newModel, initialCmds) = update(
    DaemonMsg(kind: MsgKind.Tick, timestamp: getTime()),
    model
  )
  model = newModel

  # Execute initial commands
  for cmd in initialCmds:
    pendingFutures.add(executeCmd(cmd, model))

  # Main loop
  while model.running:
    # Check for completed futures - collect results first
    var completedIndices: seq[int] = @[]
    var completedMsgs: seq[DaemonMsg] = @[]

    for i in 0 ..< pendingFutures.len:
      if pendingFutures[i].finished:
        completedIndices.add(i)
        let resultOpt = pendingFutures[i].read()
        if resultOpt.isSome:
          completedMsgs.add(resultOpt.get)

    # Remove completed futures (in reverse order to preserve indices)
    for i in countdown(completedIndices.high, 0):
      pendingFutures.delete(completedIndices[i])

    # Now process completed messages and add new futures
    for msg in completedMsgs:
      let (updatedModel, newCmds) = update(msg, model)
      model = updatedModel
      for cmd in newCmds:
        pendingFutures.add(executeCmd(cmd, model))

    # Yield to async scheduler
    await sleepAsync(100)

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
