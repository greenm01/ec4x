## Database Initialization for EC4X Daemon
##
## Handles all database I/O operations for game persistence.
## This module is the ONLY place where database creation happens.
##
## The engine (src/engine/) is pure - it generates GameState in memory.
## This module persists that state to SQLite using msgpack serialization.
##
## Migration: Switched from JSON to msgpack for state persistence
## - Faster serialization and deserialization
## - Smaller database size
## - Type-safe binary format

import std/[os, random, sets]
import db_connector/db_sqlite

import ../../common/logger
import ../../common/wordlist
import ../../engine/types/game_state
import ./schema
import ./msgpack_state
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

  var gameSlug = ""
  randomize()
  while true:
    gameSlug = generateGameSlug()
    let (_, gameDir) = defaultDBConfig(state.gameId, gameSlug, dataDir)
    if not dirExists(gameDir):
      break

  let (dbPath, gameDir) = defaultDBConfig(state.gameId, gameSlug, dataDir)
  state.dbPath = dbPath # Set dbPath on state object
  state.gameName = gameSlug

  # Create game directory
  createDir(gameDir)
  logInfo("Persistence", "Created game directory: ", gameDir)

  # Open database connection
  let db = open(dbPath, "", "", "")
  defer: db.close()

  # Create all tables
  createAllTables(db)

  # Serialize initial GameState to msgpack
  let stateMsgpack = serializeGameState(state)

  # Insert game metadata with msgpack blob
  db.exec(sql"""
    INSERT INTO games (
      id, name, description, slug, turn, year, month, phase, transport_mode,
      state_msgpack,
      created_at, updated_at
    ) VALUES (
      ?, ?, ?, ?, 1, 2001, 1, 'Active', 'nostr',
      ?,
      unixepoch(), unixepoch()
    )
  """, state.gameId, state.gameName, state.gameDescription, gameSlug,
       stateMsgpack)

  logInfo("Persistence", "Initialized database: ", dbPath)
  logInfo("Persistence", "Game: ", state.gameName, " (", state.gameId, ")")
  logInfo("Persistence", "Initial state size: ", $stateMsgpack.len, " bytes")

  # Generate unique invite codes for all houses
  var existingCodes = initHashSet[string]()
  let gamesDir = dataDir / "games"
  if dirExists(gamesDir):
    for kind, path in walkDir(gamesDir):
      if kind != pcDir:
        continue
      let otherDbPath = path / "ec4x.db"
      if not fileExists(otherDbPath):
        continue
      try:
        let otherState = loadFullState(otherDbPath)
        for house in otherState.houses.entities.data:
          if house.inviteCode.len > 0:
            existingCodes.incl(house.inviteCode)
      except:
        logWarn("Persistence", "Failed to scan invite codes from ",
          otherDbPath, ": ", getCurrentExceptionMsg())

  # Assign invite codes to houses in the state
  var needsUpdate = false
  for i in 0..<state.houses.entities.data.len:
    var code = generateInviteCode()
    var retries = 0
    while code in existingCodes and retries < 25:
      code = generateInviteCode()
      retries += 1
    if retries == 25 and code in existingCodes:
      logError("Persistence", "Failed to generate unique invite code for ",
        state.houses.entities.data[i].name)
      continue
    state.houses.entities.data[i].inviteCode = code
    existingCodes.incl(code)
    needsUpdate = true
    logInfo("Persistence", "Generated invite code for ", state.houses.entities.data[i].name, " (code hidden)")

  # Save updated state with invite codes
  if needsUpdate:
    saveFullState(state)

  return dbPath
