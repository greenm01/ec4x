## EC4X Game Moderator
##
## This is the main moderator application for EC4X games, providing
## command-line tools for game creation, management, and maintenance.

import std/[os, strutils, exitprocs, sequtils, options, tables]
import cligen
import ../core
import moderator/[config, create]
import ../storage/json_storage
import ../engine/gamestate

proc newGameCmd(dir: string): int =
  ## Initialize a new game in the specified directory
  echo "Creating new EC4X game in directory: ", dir

  if dir.len == 0:
    echo "Error: Directory path cannot be empty"
    return 1

  let absolutePath = if isAbsolute(dir): dir else: getCurrentDir() / dir

  if create.newGame(absolutePath):
    echo "Game created successfully!"
    return 0
  else:
    echo "Failed to create game"
    return 1

proc startGame(dir: string): int =
  ## Start the server for game located at the specified directory
  echo "Starting EC4X game server in directory: ", dir

  if dir.len == 0:
    echo "Error: Directory path cannot be empty"
    return 1

  let absolutePath = if isAbsolute(dir): dir else: getCurrentDir() / dir

  if not checkGamePath(absolutePath):
    echo "Error: Invalid game directory: ", absolutePath
    return 1

  try:
    let config = loadConfig(absolutePath)
    echo "Starting server on ", config.serverIp, ":", config.port
    echo "Game: ", config.gameName
    echo "Host: ", config.hostName
    echo "Players: ", config.numEmpires

    # TODO: Implement actual server startup
    echo "Server startup not yet implemented"
    return 0

  except Exception as e:
    echo "Error starting game: ", e.msg
    return 1

proc maintGame(dir: string): int =
  ## Run turn maintenance on game located at the specified directory
  echo "Running turn maintenance for game in directory: ", dir

  if dir.len == 0:
    echo "Error: Directory path cannot be empty"
    return 1

  let absolutePath = if isAbsolute(dir): dir else: getCurrentDir() / dir

  if not checkGamePath(absolutePath):
    echo "Error: Invalid game directory: ", absolutePath
    return 1

  try:
    let config = loadConfig(absolutePath)
    echo "Running maintenance for game: ", config.gameName

    # TODO: Implement turn maintenance logic
    echo "Turn maintenance not yet implemented"
    return 0

  except Exception as e:
    echo "Error in maintenance: ", e.msg
    return 1

proc statsGame(dir: string): int =
  ## Display game statistics for game located at the specified directory
  echo "Displaying statistics for game in directory: ", dir

  if dir.len == 0:
    echo "Error: Directory path cannot be empty"
    return 1

  let absolutePath = if isAbsolute(dir): dir else: getCurrentDir() / dir

  if not checkGamePath(absolutePath):
    echo "Error: Invalid game directory: ", absolutePath
    return 1

  try:
    let config = loadConfig(absolutePath)

    echo "\n" & "=".repeat(50)
    echo "EC4X GAME STATISTICS"
    echo "=".repeat(50)
    echo "Game Name: ", config.gameName
    echo "Host: ", config.hostName
    echo "Server: ", config.serverIp, ":", config.port
    echo "Players: ", config.numEmpires
    echo "Game Directory: ", absolutePath

    # Check for game data files
    let gameDataPath = absolutePath / "game_data"
    if dirExists(gameDataPath):
      echo "Game Data: Available"

      let systemsFile = gameDataPath / "systems.txt"
      let lanesFile = gameDataPath / "lanes.txt"

      if fileExists(systemsFile):
        let systemsContent = readFile(systemsFile)
        let systemCount = systemsContent.split('\n').filterIt(it.len > 0).len
        echo "Systems: ", systemCount

      if fileExists(lanesFile):
        let lanesContent = readFile(lanesFile)
        let laneCount = lanesContent.split('\n').filterIt(it.len > 0).len
        echo "Jump Lanes: ", laneCount
    else:
      echo "Game Data: Not found"

    echo "=".repeat(50)
    return 0

  except Exception as e:
    echo "Error displaying statistics: ", e.msg
    return 1

proc testGen(): int =
  ## Generate a test star map for development purposes
  echo "Generating test star map..."

  if create.genStarMap():
    return 0
  else:
    return 1

proc version(): int =
  ## Display version information
  echo gameInfo()
  return 0

proc ordersCmd(dir: string, ordersFile: string = "", house: string = ""): int =
  ## Load and validate order file for a house
  ## M1 Command: moderator orders <dir> <file> --house=<name>
  ##
  ## TODO M1: Parse TOML order file
  ## TODO M1: Load game state from JSON
  ## TODO M1: Validate orders against gamestate
  ## TODO M1: Save to orders/<house>_turn<N>.json
  ##
  ## STUB: Placeholder for M1
  echo "Processing orders for house: ", house
  echo "Orders file: ", ordersFile
  echo "Game directory: ", dir

  if dir.len == 0 or house.len == 0 or ordersFile.len == 0:
    echo "Error: Missing required parameters"
    echo "Usage: moderator orders <dir> <file> --house=<name>"
    return 1

  let absolutePath = if isAbsolute(dir): dir else: getCurrentDir() / dir

  # TODO M1: Actually parse and validate orders
  echo "Orders submitted for ", house
  return 0

proc resolveCmd(dir: string): int =
  ## Resolve current turn
  ## M1 Command: moderator resolve <dir>
  ##
  ## TODO M1: Load game state from JSON
  ## TODO M1: Load all orders from orders/
  ## TODO M1: Call engine.resolveTurn(state, orders)
  ## TODO M1: Save new state to JSON
  ## TODO M1: Write turn summary to results/
  ##
  ## STUB: Placeholder for M1
  echo "Resolving turn for game in directory: ", dir

  if dir.len == 0:
    echo "Error: Directory path cannot be empty"
    return 1

  let absolutePath = if isAbsolute(dir): dir else: getCurrentDir() / dir

  # Load game state
  let gameId = absolutePath.lastPathPart
  let statePath = getGameStatePath(gameId, absolutePath.parentDir())

  let stateOpt = loadGameState(statePath)
  if stateOpt.isNone:
    echo "Error: Could not load game state from: ", statePath
    return 1

  var state = stateOpt.get()

  echo "Turn ", state.turn, " - Resolving..."

  # TODO M1: Load orders and resolve turn
  # For now, just increment turn
  state.turn += 1

  # Save state
  if not saveGameState(state, statePath):
    echo "Error: Failed to save game state"
    return 1

  echo "Turn resolved successfully! Now turn ", state.turn
  return 0

proc viewCmd(dir: string): int =
  ## Display current game state
  ## M1 Command: moderator view <dir>
  ##
  ## TODO M1: Load game state from JSON
  ## TODO M1: Pretty-print turn, houses, fleets, colonies
  ##
  ## STUB: Placeholder for M1
  echo "Viewing game state in directory: ", dir

  if dir.len == 0:
    echo "Error: Directory path cannot be empty"
    return 1

  let absolutePath = if isAbsolute(dir): dir else: getCurrentDir() / dir

  # Load game state
  let gameId = absolutePath.lastPathPart
  let statePath = getGameStatePath(gameId, absolutePath.parentDir())

  let stateOpt = loadGameState(statePath)
  if stateOpt.isNone:
    echo "Error: Could not load game state from: ", statePath
    return 1

  let state = stateOpt.get()

  echo "\n" & "=".repeat(50)
  echo "EC4X GAME STATE"
  echo "=".repeat(50)
  echo "Game ID: ", state.gameId
  echo "Turn: ", state.turn, " (Strategic Cycle ", state.turn, ")"
  echo "Phase: ", state.phase
  echo "Houses: ", state.houses.len()
  echo "Colonies: ", state.colonies.len()
  echo "Fleets: ", state.fleets.len()
  echo "=".repeat(50)

  return 0

proc resultsCmd(dir: string, house: string = ""): int =
  ## Show turn results for specific house
  ## M1 Command: moderator results <dir> --house=<name>
  ##
  ## TODO M1: Load turn log from results/turn_N.json
  ## TODO M1: Filter to events visible to house
  ## TODO M1: Pretty-print movement, combat, construction, income
  ##
  ## STUB: Placeholder for M1
  echo "Displaying results for house: ", house
  echo "Game directory: ", dir

  if dir.len == 0 or house.len == 0:
    echo "Error: Missing required parameters"
    echo "Usage: moderator results <dir> --house=<name>"
    return 1

  let absolutePath = if isAbsolute(dir): dir else: getCurrentDir() / dir

  # TODO M1: Load and display turn results
  echo "No results available yet"
  return 0

proc help(): int =
  ## Display help information
  echo """
EC4X Game Moderator - Command Line Interface

USAGE:
    moderator <COMMAND> [OPTIONS]

COMMANDS:
    new <DIR>      Initialize a new game in <DIR>
    start <DIR>    Start the server for game located at <DIR>
    maint <DIR>    Run turn maintenance on game located at <DIR>
    stats <DIR>    Display game statistics for game located at <DIR>
    test-gen       Generate a test star map (development)
    version        Display version information
    help           Display this help message

M1 COMMANDS (Milestone 1):
    orders <DIR> <FILE> --house=<NAME>  Submit orders for a house
    resolve <DIR>                        Resolve current turn
    view <DIR>                           Display current game state
    results <DIR> --house=<NAME>         Show turn results for house

EXAMPLES:
    moderator new ./my_game
    moderator start ./my_game
    moderator stats ./my_game
    moderator orders ./my_game orders.toml --house=atreides
    moderator resolve ./my_game
    moderator view ./my_game
    moderator results ./my_game --house=atreides

For more information, visit: https://github.com/greenm01/ec4x
"""
  return 0

when isMainModule:
  # Set up proper exit handling
  addExitProc(proc() = discard)

  # Dispatch to appropriate command
  dispatchMulti(
    [newGameCmd, cmdName = "new"],
    [startGame, cmdName = "start"],
    [maintGame, cmdName = "maint"],
    [statsGame, cmdName = "stats"],
    [testGen, cmdName = "test-gen"],
    [ordersCmd, cmdName = "orders"],
    [resolveCmd, cmdName = "resolve"],
    [viewCmd, cmdName = "view"],
    [resultsCmd, cmdName = "results"],
    [version, cmdName = "version"],
    [help, cmdName = "help"]
  )
