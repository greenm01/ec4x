## Player-side PlayerState cache and persistence

import std/[options, os, json, jsonutils]
import db_connector/db_sqlite
import ../../common/logger
import ../../engine/types/[core, player_state, colony, fleet, ship, ground_unit,
  diplomacy, progression]

const SnapshotTable = "player_state_snapshots"

proc playerDbDir*(dataDir: string, pubkey: string, gameId: string): string =
  dataDir / "players" / pubkey / "games" / gameId

proc playerDbPath*(dataDir: string, pubkey: string, gameId: string): string =
  playerDbDir(dataDir, pubkey, gameId) / "player_state.db"

proc ensurePlayerStateDb*(dataDir: string, pubkey: string, gameId: string) =
  let dirPath = playerDbDir(dataDir, pubkey, gameId)
  createDir(dirPath)

  let dbPath = playerDbPath(dataDir, pubkey, gameId)
  let db = open(dbPath, "", "", "")
  defer: db.close()

  db.exec(sql"""
    CREATE TABLE IF NOT EXISTS player_state_snapshots (
      game_id TEXT NOT NULL,
      house_id TEXT NOT NULL,
      turn INTEGER NOT NULL,
      state_json TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      PRIMARY KEY (game_id, house_id, turn)
    )
  """)

  db.exec(sql"""
    CREATE INDEX IF NOT EXISTS idx_player_state_house
      ON player_state_snapshots(game_id, house_id)
  """)

proc savePlayerStateSnapshot*(
  dataDir: string,
  pubkey: string,
  gameId: string,
  houseId: HouseId,
  turn: int32,
  state: PlayerState
) =
  ensurePlayerStateDb(dataDir, pubkey, gameId)
  let dbPath = playerDbPath(dataDir, pubkey, gameId)
  let db = open(dbPath, "", "", "")
  defer: db.close()

  let payload = $toJson(state)
  db.exec(
    sql"""
    INSERT INTO player_state_snapshots (
      game_id, house_id, turn, state_json, created_at
    ) VALUES (?, ?, ?, ?, unixepoch())
    ON CONFLICT(game_id, house_id, turn) DO UPDATE SET
      state_json=excluded.state_json
    """,
    gameId,
    $houseId.uint32,
    $turn,
    payload
  )

proc loadPlayerStateSnapshot*(
  dataDir: string,
  pubkey: string,
  gameId: string,
  houseId: HouseId,
  turn: int32
): Option[PlayerState] =
  let dbPath = playerDbPath(dataDir, pubkey, gameId)
  if not fileExists(dbPath):
    return none(PlayerState)

  let db = open(dbPath, "", "", "")
  defer: db.close()

  let row = db.getRow(
    sql"""
    SELECT state_json
    FROM player_state_snapshots
    WHERE game_id = ? AND house_id = ? AND turn = ?
  """,
    gameId,
    $houseId.uint32,
    $turn
  )

  if row[0] == "":
    return none(PlayerState)

  try:
    return some(parseJson(row[0]).jsonTo(PlayerState))
  except CatchableError as e:
    logError("PlayerState", "Failed to parse snapshot: ", e.msg)
    return none(PlayerState)

proc loadLatestPlayerState*(
  dataDir: string,
  pubkey: string,
  gameId: string,
  houseId: HouseId
): Option[PlayerState] =
  let dbPath = playerDbPath(dataDir, pubkey, gameId)
  if not fileExists(dbPath):
    return none(PlayerState)

  let db = open(dbPath, "", "", "")
  defer: db.close()

  let row = db.getRow(
    sql"""
    SELECT state_json
    FROM player_state_snapshots
    WHERE game_id = ? AND house_id = ?
    ORDER BY turn DESC
    LIMIT 1
  """,
    gameId,
    $houseId.uint32
  )

  if row[0] == "":
    return none(PlayerState)

  try:
    return some(parseJson(row[0]).jsonTo(PlayerState))
  except CatchableError as e:
    logError("PlayerState", "Failed to parse snapshot: ", e.msg)
    return none(PlayerState)
