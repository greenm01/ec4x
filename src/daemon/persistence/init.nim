## Database Initialization for EC4X Daemon
##
## Handles all database I/O operations for game persistence.
## This module is the ONLY place where database creation happens.
##
## The engine (src/engine/) is pure - it generates GameState in memory.
## This module persists that state to SQLite.

import std/[os, json, jsonutils]
import db_connector/db_sqlite

import ../../common/logger
import ../../common/wordlist
import ../../engine/types/game_state
import ../../engine/globals
import ./schema
import ./reader
import ./writer

proc createGameDatabase*(state: GameState, dataDir: string): string =
  ## Create per-game database and persist initial game state
  ##
  ## Args:
  ##   state: Fully initialized GameState from engine
  ##   dataDir: Root data directory
  ##
  ## Returns: Path to created database file

  let (dbPath, gameDir) = defaultDBConfig(state.gameId, dataDir)
  state.dbPath = dbPath # Set dbPath on state object

  # Create game directory
  createDir(gameDir)
  logInfo("Persistence", "Created game directory: ", gameDir)

  # Open database connection
  let db = open(dbPath, "", "", "")
  defer: db.close()

  # Create all tables
  createAllTables(db)

  # Serialize configs to JSON for storage
  let setupJson = $toJson(gameSetup)
  let configJson = $toJson(gameConfig)

  # Insert game metadata
  db.exec(sql"""
    INSERT INTO games (
      id, name, description, turn, year, month, phase, transport_mode,
      game_setup_json, game_config_json,
      created_at, updated_at
    ) VALUES (
      ?, ?, ?, 1, 2001, 1, 'Active', 'nostr',
      ?, ?,
      unixepoch(), unixepoch()
    )
  """, state.gameId, state.gameName, state.gameDescription,
       setupJson, configJson)

  logInfo("Persistence", "Initialized database: ", dbPath)
  logInfo("Persistence", "Game: ", state.gameName, " (", state.gameId, ")")

  # Persist full initial state (houses, systems, colonies, fleets, etc.)
  saveFullState(state)

  for house in state.houses.entities.data:
    var code = generateInviteCode()
    var retries = 0
    while isInviteCodeAssigned(dbPath, state.gameId, code) and retries < 5:
      code = generateInviteCode()
      retries += 1
    if retries == 5 and isInviteCodeAssigned(dbPath, state.gameId, code):
      logError("Persistence", "Failed to generate unique invite code for ",
        house.name)
      continue
    updateHouseInviteCode(dbPath, state.gameId, house.id, code)
    logInfo("Persistence", "Generated invite code for ", house.name, " (code hidden)")

  return dbPath
