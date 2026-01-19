## EC4X Moderator - Admin CLI Tool
##
## Provides administrative functions for game management:
## - new: Create a new game from a scenario file
## - list: List all games
## - status: Show game status
## - pause/resume: Control game state
## - winner: Declare game winner
##
## The moderator handles one-time setup operations.
## For ongoing game management, see the daemon.
##
## Usage:
##   ec4x new --name "Friday Game" --scenario scenarios/my-game.kdl
##   ec4x list
##   ec4x status <game-id>

import std/[os, strutils]
import cligen
import ../engine/init/game_state
import ../engine/types/game_state
import ../engine/state/engine
import ../daemon/persistence/init as db_init
import ../daemon/persistence/reader
import ../common/wordlist

proc newGame(
    name: string = "",
    scenario: string = "scenarios/standard-4-player.kdl",
    configDir: string = "config",
    dataDir: string = "data"
): int =
  ## Create a new EC4X game from a scenario file
  ##
  ## Args:
  ##   name: Human-readable game name (default: use scenario name)
  ##   scenario: Path to scenario KDL file
  ##   configDir: Directory containing config files
  ##   dataDir: Directory for game data

  if not fileExists(scenario):
    echo "Error: Scenario file not found: ", scenario
    return 1

  echo "Creating new EC4X game from scenario: ", scenario

  # Generate initial game state (pure function, no I/O)
  let state = initGameState(
    setupPath = scenario,
    gameName = name,
    configDir = configDir,
    dataDir = dataDir
  )

  echo "  Game ID: ", state.gameId
  echo "  Name: ", state.gameName
  echo "  Systems: ", state.systemsCount()
  echo "  Houses: ", state.housesCount()

  # Create database and persist initial state
  let dbPath = db_init.createGameDatabase(state, dataDir)

  echo ""
  echo "Game created successfully!"
  echo "Database: ", dbPath
  return 0

proc listGames(dataDir: string = "data"): int =
  ## List all games in the data directory
  let gamesDir = dataDir / "games"

  if not dirExists(gamesDir):
    echo "No games found in ", gamesDir
    return 0

  echo "Games in ", gamesDir, ":"
  echo ""

  for kind, path in walkDir(gamesDir):
    if kind == pcDir:
      let dbPath = path / "ec4x.db"
      if fileExists(dbPath):
        let gameId = path.lastPathPart
        # TODO: Query DB for game name and status
        echo "  ", gameId

  return 0

proc status(gameId: string, dataDir: string = "data"): int =
  ## Show status of a specific game
  if gameId.len == 0:
    echo "Error: Game ID is required"
    return 1

  let dbPath = dataDir / "games" / gameId / "ec4x.db"

  if not fileExists(dbPath):
    echo "Error: Game not found: ", gameId
    return 1

  # TODO: Load game state and display status
  echo "Game: ", gameId
  echo "Database: ", dbPath
  echo "Status: (not yet implemented)"

  return 0

proc pause(gameId: string, dataDir: string = "data"): int =
  ## Pause a game
  if gameId.len == 0:
    echo "Error: Game ID is required"
    return 1

  # TODO: Update game phase to 'Paused' in DB
  echo "Pausing game: ", gameId
  echo "(not yet implemented)"
  return 0

proc resume(gameId: string, dataDir: string = "data"): int =
  ## Resume a paused game
  if gameId.len == 0:
    echo "Error: Game ID is required"
    return 1

  # TODO: Update game phase to 'Active' in DB
  echo "Resuming game: ", gameId
  echo "(not yet implemented)"
  return 0

proc winner(gameId: string, houseId: string, dataDir: string = "data"): int =
  ## Declare the winner of a game
  if gameId.len == 0 or houseId.len == 0:
    echo "Error: Game ID and House ID are required"
    return 1

  # TODO: Update game phase to 'Completed', set winner
  echo "Declaring winner for game: ", gameId
  echo "Winner: ", houseId
  echo "(not yet implemented)"
  return 0

proc invite(GAMEID: string, dataDir = "data"): int =
  ## Query all invite codes for a game, show claimed status
  let dbPath = dataDir / "games" / gameId / "ec4x.db"
  if not fileExists(dbPath):
    echo "No game: ", gameId
    return 1
  
  let houses = dbGetHousesWithInvites(dbPath, gameId)
  if houses.len == 0:
    echo "No houses with invites found"
    return 0
  
  for h in houses:
    let status = if h.nostr_pubkey.len > 0:
      "CLAIMED " & h.nostr_pubkey[0..10] & "..."
    else:
      "PENDING"
    echo "House ", h.name, " (", $h.id.uint32, "): ", h.invite_code, " [", status, "]"
  0

proc version(): int =
  ## Display version information
  echo "EC4X Moderator v0.1.0"
  return 0

when isMainModule:
  dispatchMulti(
    [newGame, cmdName = "new", help = "Create a new game from scenario"],
    [listGames, cmdName = "list", help = "List all games"],
    [status, help = "Show game status"],
    [pause, help = "Pause a game"],
    [resume, help = "Resume a paused game"],
    [winner, help = "Declare game winner"],
    [invite, cmdName = "invite", help = "Query invite codes + status"],
    [version, help = "Show version"]
  )
