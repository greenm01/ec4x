## Persistence Reader: Load GameState from DB

import std/[tables, options, json]
import db_connector/db_sqlite
import ../../engine/types/game_state
import ./schema

proc loadGameState*(dbPath: string): GameState =
  ## Load full GameState from per-game DB (stub for now)
  ## TODO: Query all tables → populate Tables[Id, Entity]
  let db = open(dbPath, '', '', '')
  defer: db.close()

  # Stub: Load metadata, empty entities
  let metadata = db.getRow(sql\"SELECT * FROM games LIMIT 1\")  # First game
  result = GameState(
    gameId: metadata[0],
    gameName: metadata[1],
    turn: parseInt(metadata[3]),
    # colonies: initTable[ColonyId, Colony](), etc.
  )
  logInfo(\"Persistence\", \"Loaded stub state from \", dbPath)