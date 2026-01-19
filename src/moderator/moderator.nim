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

import std/[os, strutils, options]
import db_connector/db_sqlite
import cligen
import ../engine/init/game_state
import ../engine/types/game_state
import ../engine/state/engine
import ../daemon/persistence/init as db_init
import ../daemon/persistence/reader

type GameMeta = object
  id: string
  name: string
  slug: string
  turn: int
  phase: string
  dbPath: string

proc loadGameMeta(dbPath: string): Option[GameMeta] =
  let db = open(dbPath, "", "", "")
  defer: db.close()
  let row = db.getRow(
    sql"SELECT id, name, slug, turn, phase FROM games LIMIT 1"
  )
  if row[0].len == 0:
    return none(GameMeta)
  some(GameMeta(
    id: row[0],
    name: row[1],
    slug: row[2],
    turn: parseInt(row[3]),
    phase: row[4],
    dbPath: dbPath
  ))

proc collectGameMetas(dataDir: string): seq[GameMeta] =
  result = @[]
  let gamesDir = dataDir / "games"
  if not dirExists(gamesDir):
    return
  for kind, path in walkDir(gamesDir):
    if kind != pcDir:
      continue
    let dbPath = path / "ec4x.db"
    if not fileExists(dbPath):
      continue
    let metaOpt = loadGameMeta(dbPath)
    if metaOpt.isSome:
      result.add(metaOpt.get())

proc findGameMeta(dataDir: string, token: string): Option[GameMeta] =
  for meta in collectGameMetas(dataDir):
    if meta.id == token or meta.slug == token or meta.name == token:
      return some(meta)
  none(GameMeta)

proc newGame(
    scenario: string = "scenarios/standard-4-player.kdl",
    configDir: string = "config",
    dataDir: string = "data"
): int =
  ## Create a new EC4X game from a scenario file
  ##
  ## Name/slug is auto-generated from the wordlist.
  ##
  ## Args:
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
    configDir = configDir,
    dataDir = dataDir
  )

  echo "  Game ID: ", state.gameId
  echo "  Systems: ", state.systemsCount()
  echo "  Houses: ", state.housesCount()

  # Create database and persist initial state
  let dbPath = db_init.createGameDatabase(state, dataDir)

  echo ""
  echo "Game created successfully!"
  echo "Name: ", state.gameName
  echo "Slug: ", state.gameName
  echo "Database: ", dbPath
  return 0


proc listGames(dataDir: string = "data"): int =
  ## List all games in the data directory
  let gamesDir = dataDir / "games"

  if not dirExists(gamesDir):
    echo "No games found in ", gamesDir
    return 0

  let metas = collectGameMetas(dataDir)
  if metas.len == 0:
    echo "No games found in ", gamesDir
    return 0

  echo "Games in ", gamesDir, ":"
  echo ""

  for meta in metas:
    echo "  ", meta.slug, " (id: ", meta.id, ") turn ",
      meta.turn, " [", meta.phase, "]"

  return 0


proc status(gameId: string, dataDir: string = "data"): int =
  ## Show status of a specific game
  if gameId.len == 0:
    echo "Error: Game ID is required"
    return 1

  let metaOpt = findGameMeta(dataDir, gameId)
  if metaOpt.isNone:
    echo "Error: Game not found: ", gameId
    return 1

  let meta = metaOpt.get()
  echo "Game: ", meta.slug
  echo "ID: ", meta.id
  echo "Turn: ", meta.turn
  echo "Phase: ", meta.phase
  echo "Database: ", meta.dbPath
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

proc invite(GAMEID: seq[string], dataDir = "data"): int =
  ## Query all invite codes for a game, show claimed status
  if GAMEID.len == 0:
    echo "Error: Game ID required"
    return 1
  let gameToken = GAMEID[0]
  let metaOpt = findGameMeta(dataDir, gameToken)
  if metaOpt.isNone:
    echo "No game: ", gameToken
    return 1

  let meta = metaOpt.get()
  let dbPath = meta.dbPath

  let houses = dbGetHousesWithInvites(dbPath, meta.id)
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

proc ids(dataDir: string = "data"): int =
  ## Show slug and UUID mapping for all games
  let metas = collectGameMetas(dataDir)
  if metas.len == 0:
    echo "No games found in ", dataDir / "games"
    return 0

  echo "Game IDs:"
  echo ""
  for meta in metas:
    echo "  ", meta.slug, " -> ", meta.id
  0

proc version(): int =
  ## Display version information
  echo "EC4X Moderator v0.1.0"
  return 0

when isMainModule:
  dispatchMulti(
    [newGame, cmdName = "new", help = "Create a new game from scenario"],
    [listGames, cmdName = "list", help = "List all games"],
    [ids, cmdName = "ids", help = "Show slug to UUID mapping"],
    [status, help = "Show game status"],
    [pause, help = "Pause a game"],
    [resume, help = "Resume a paused game"],
    [winner, help = "Declare game winner"],
    [invite, cmdName = "invite", positional = "GAMEID", help = "Query invite codes + status"],
    [invite, cmdName = "i", positional = "GAMEID", help = "Query invite codes + status"],
    [version, help = "Show version"]
  )

