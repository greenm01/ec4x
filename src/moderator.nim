## EC4X Game Moderator
##
## This is the main moderator application for EC4X games, providing
## command-line tools for game creation, management, and maintenance.

import std/[os, strutils, exitprocs, sequtils]
import cligen
import ec4x_core
import moderator/[config, create]

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

EXAMPLES:
    moderator new ./my_game
    moderator start ./my_game
    moderator stats ./my_game

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
    [version, cmdName = "version"],
    [help, cmdName = "help"]
  )
