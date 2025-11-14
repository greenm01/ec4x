## EC4X Game Client
##
## This is the main client application for EC4X games, providing
## a command-line interface for players to interact with games.

import std/[os, strutils, net, times, tables]
import cligen
import ../core

type
  ClientError* = object of CatchableError

proc connectToServer(host: string, port: int): bool =
  ## Attempt to connect to the game server
  try:
    echo "Connecting to server at ", host, ":", port

    # TODO: Implement actual server connection
    echo "Server connection not yet implemented"
    return false

  except Exception as e:
    echo "Connection failed: ", e.msg
    return false

proc joinGame(host: string = "localhost", port: int = 8080, player: string = ""): int =
  ## Join an existing game on the specified server
  echo "Joining EC4X game..."
  echo "Server: ", host, ":", port

  if player.len == 0:
    echo "Error: Player name is required"
    return 1

  echo "Player: ", player

  if not connectToServer(host, port):
    echo "Failed to connect to server"
    return 1

  # TODO: Implement game joining logic
  echo "Game joining not yet implemented"
  return 0

proc listGames(host: string = "localhost", port: int = 8080): int =
  ## List available games on the server
  echo "Listing available games on ", host, ":", port

  if not connectToServer(host, port):
    echo "Failed to connect to server"
    return 1

  # TODO: Implement game listing
  echo "Game listing not yet implemented"
  return 0

proc submitTurn(host: string = "localhost", port: int = 8080,
               player: string = "", turnFile: string = ""): int =
  ## Submit a turn file to the game server
  echo "Submitting turn for player: ", player

  if player.len == 0:
    echo "Error: Player name is required"
    return 1

  if turnFile.len == 0:
    echo "Error: Turn file is required"
    return 1

  if not fileExists(turnFile):
    echo "Error: Turn file not found: ", turnFile
    return 1

  if not connectToServer(host, port):
    echo "Failed to connect to server"
    return 1

  # TODO: Implement turn submission
  echo "Turn submission not yet implemented"
  return 0

proc getTurnResults(host: string = "localhost", port: int = 8080,
                   player: string = "", outputFile: string = ""): int =
  ## Get turn results from the game server
  echo "Getting turn results for player: ", player

  if player.len == 0:
    echo "Error: Player name is required"
    return 1

  if not connectToServer(host, port):
    echo "Failed to connect to server"
    return 1

  # TODO: Implement turn results retrieval
  echo "Turn results retrieval not yet implemented"
  return 0

proc gameStatus(host: string = "localhost", port: int = 8080): int =
  ## Get current game status
  echo "Getting game status from ", host, ":", port

  if not connectToServer(host, port):
    echo "Failed to connect to server"
    return 1

  # TODO: Implement game status retrieval
  echo "Game status retrieval not yet implemented"
  return 0

proc createOfflineGame(players: int = 4, outputDir: string = ""): int =
  ## Create an offline game for testing/development
  echo "Creating offline game with ", players, " players"

  if not validatePlayerCount(players):
    echo "Error: Invalid player count. Must be between ", MIN_PLAYERS, " and ", MAX_PLAYERS
    return 1

  let gameDir = if outputDir.len > 0: outputDir else: "offline_game"

  try:
    let starMap = createGame(players)

    echo "Created offline game:"
    echo "- Players: ", players
    echo "- Systems: ", starMap.systems.len
    echo "- Jump Lanes: ", starMap.lanes.len
    echo "- Output Directory: ", gameDir

    # Create output directory if it doesn't exist
    if not dirExists(gameDir):
      createDir(gameDir)

    # Save basic game information
    let gameInfoFile = gameDir / "game_info.txt"
    let gameInfo = "EC4X Offline Game\n" &
                  "Players: " & $players & "\n" &
                  "Systems: " & $starMap.systems.len & "\n" &
                  "Jump Lanes: " & $starMap.lanes.len & "\n" &
                  "Created: " & $getTime()

    writeFile(gameInfoFile, gameInfo)
    echo "Game information saved to: ", gameInfoFile

    return 0

  except Exception as e:
    echo "Error creating offline game: ", e.msg
    return 1

proc version(): int =
  ## Display version information
  echo gameInfo()
  return 0

proc help(): int =
  ## Display help information
  echo """
EC4X Game Client - Command Line Interface

USAGE:
    client <COMMAND> [OPTIONS]

COMMANDS:
    join           Join an existing game
    list           List available games on server
    submit         Submit a turn file to the server
    results        Get turn results from the server
    status         Get current game status
    offline        Create an offline game for testing
    version        Display version information
    help           Display this help message

EXAMPLES:
    client join --host=game.server.com --port=8080 --player=PlayerName
    client list --host=game.server.com --port=8080
    client submit --player=PlayerName --turn-file=my_turn.txt
    client offline --players=6 --output-dir=my_offline_game

For more information, visit: https://github.com/greenm01/ec4x
"""
  return 0

when isMainModule:
  # Dispatch to appropriate command
  dispatchMulti(
    [joinGame, cmdName = "join"],
    [listGames, cmdName = "list"],
    [submitTurn, cmdName = "submit"],
    [getTurnResults, cmdName = "results"],
    [gameStatus, cmdName = "status"],
    [createOfflineGame, cmdName = "offline"],
    [version, cmdName = "version"],
    [help, cmdName = "help"]
  )
