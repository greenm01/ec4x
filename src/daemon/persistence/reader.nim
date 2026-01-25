## Persistence Reader: Load GameState from DB
##
## Migration: Switched from JSON to msgpack for GameState persistence
## - Entity tables (houses, systems, colonies, fleets, ships) removed
## - GameState loaded directly from games.state_msgpack blob
## - Intel data included in GameState.intel
## - Faster deserialization and type safety

import std/[tables, options, strutils, os, base64]
import db_connector/db_sqlite
import ../../common/logger
import ../../engine/types/[game_state, core, command]
import ../../engine/state/engine
import ../parser/msgpack_commands
import ./msgpack_state
import ./player_state_snapshot
import ./replay

export ReplayDirection

# Replay protection

# Forward declaration for loadFullState (defined later)
proc loadFullState*(dbPath: string): GameState

# Note: House pubkey and invite code queries now load from GameState
# These procs are kept for backward compatibility and query the msgpack blob.

proc getHousePubkey*(dbPath: string, gameId: string, houseId: HouseId): Option[string] =
  ## Get a house's Nostr pubkey from GameState
  ## Note: Now loads from msgpack blob instead of houses table
  let state = loadFullState(dbPath)
  if state.houses.entities.index.hasKey(houseId):
    let idx = state.houses.entities.index[houseId]
    let house = state.houses.entities.data[idx]
    if house.nostrPubkey.len > 0:
      return some(house.nostrPubkey)
  return none(string)

proc getHouseByInviteCode*(dbPath: string, gameId: string,
  inviteCode: string): Option[HouseId] =
  ## Get house id by invite code from GameState
  let state = loadFullState(dbPath)
  for house in state.houses.entities.data:
    if house.inviteCode == inviteCode:
      return some(house.id)
  return none(HouseId)

proc inviteCodeMatches*(dbPath: string, inviteCode: string): bool =
  ## Check if invite code exists in this game database
  let state = loadFullState(dbPath)
  for house in state.houses.entities.data:
    if house.inviteCode == inviteCode:
      return true
  return false

proc getHouseInviteCode*(dbPath: string, gameId: string,
  houseId: HouseId): Option[string] =
  ## Get invite code for a house from GameState
  let state = loadFullState(dbPath)
  if state.houses.entities.index.hasKey(houseId):
    let idx = state.houses.entities.index[houseId]
    let house = state.houses.entities.data[idx]
    if house.inviteCode.len > 0:
      return some(house.inviteCode)
  return none(string)

proc isInviteCodeClaimed*(dbPath: string, gameId: string,
  inviteCode: string): bool =
  ## Returns true if invite code already assigned a pubkey
  let state = loadFullState(dbPath)
  for house in state.houses.entities.data:
    if house.inviteCode == inviteCode and house.nostrPubkey.len > 0:
      return true
  return false

proc isInviteCodeAssigned*(dbPath: string, gameId: string,
  inviteCode: string): bool =
  ## Returns true if invite code is already assigned to a house
  let state = loadFullState(dbPath)
  for house in state.houses.entities.data:
    if house.inviteCode == inviteCode:
      return true
  return false

type
  HouseInvite* = object
    id*: HouseId
    name*: string
    invite_code*: string
    nostr_pubkey*: string

proc dbGetHousesWithInvites*(dbPath, gameId: string): seq[HouseInvite] =
  ## Get all houses with invite codes and claim status for a game
  let state = loadFullState(dbPath)
  for house in state.houses.entities.data:
    result.add HouseInvite(
      id: house.id,
      name: house.name,
      invite_code: house.inviteCode,
      nostr_pubkey: house.nostrPubkey
    )

proc loadPlayerStateSnapshot*(
  dbPath: string,
  gameId: string,
  houseId: HouseId,
  turn: int32
): Option[PlayerStateSnapshot] =
  ## Load a per-house PlayerState snapshot from the database
  let db = open(dbPath, "", "", "")
  defer: db.close()

  let row = db.getRow(
    sql"""
    SELECT state_msgpack
    FROM player_state_snapshots
    WHERE game_id = ? AND house_id = ? AND turn = ?
  """,
    gameId,
    $houseId.uint32,
    $turn
  )

  if row[0] == "":
    return none(PlayerStateSnapshot)

  try:
    return some(snapshotFromMsgpack(row[0]))
  except CatchableError:
    logError("Persistence", "Failed to parse player state snapshot: ", getCurrentExceptionMsg())
    return none(PlayerStateSnapshot)

proc hasProcessedEvent*(dbPath: string, gameId: string, kind: int,
  eventId: string, direction: ReplayDirection): bool =
  ## Returns true if an event id was already processed
  let db = open(dbPath, "", "", "")
  defer: db.close()

  let row = db.getRow(
    sql"""
    SELECT event_id
    FROM nostr_event_log
    WHERE game_id = ? AND kind = ? AND event_id = ? AND direction = ?
  """,
    gameId,
    $kind,
    eventId,
    $(direction.ord)
  )

  return row[0] != ""

# Entity loading functions removed - entities now loaded from msgpack blob

proc loadGameState*(dbPath: string): GameState =
  ## Load lightweight GameState (metadata only) from per-game DB
  ## Used for daemon discovery - loads minimal metadata without full state
  let db = open(dbPath, "", "", "")
  defer: db.close()

  # Load only basic metadata (id, name, description, turn)
  let metadata = db.getRow(sql"SELECT id, name, description, turn FROM games LIMIT 1")
  result = GameState(
    gameId: metadata[0],
    gameName: metadata[1],
    gameDescription: metadata[2],
    turn: int32(parseInt(metadata[3])),
    phase: GamePhase.Conflict,
    dbPath: dbPath
  )

proc loadGameDeadline*(dbPath: string): Option[int64] =
  ## Load turn deadline timestamp (unix seconds) for a game
  let db = open(dbPath, "", "", "")
  defer: db.close()

  let row = db.getRow(sql"SELECT turn_deadline FROM games LIMIT 1")
  if row[0] == "" or row[0] == "NULL":
    return none(int64)

  try:
    return some(parseInt(row[0]).int64)
  except CatchableError:
    logError("Persistence", "Failed to parse turn_deadline")
    none(int64)

proc loadGamePhase*(dbPath: string): string =
  ## Load game phase string
  let db = open(dbPath, "", "", "")
  defer: db.close()

  let row = db.getRow(sql"SELECT phase FROM games LIMIT 1")
  if row[0].len == 0:
    return ""
  row[0]

# Diplomacy and intel loading removed - included in GameState msgpack blob

proc loadOrders*(dbPath: string, turn: int): Table[HouseId, CommandPacket] =
  ## Load all command packets for a specific turn from the database
  let db = open(dbPath, "", "", "")
  defer: db.close()

  result = initTable[HouseId, CommandPacket]()

  let rows = db.getAllRows(sql"""
    SELECT house_id, command_msgpack
    FROM commands
    WHERE turn = ? AND processed = 0
  """, $turn)

  for row in rows:
    let houseId = HouseId(parseInt(row[0]).uint32)
    let binary = decode(row[1])
    let packet = parseOrdersMsgpack(binary)
    result[houseId] = packet

  logInfo(
    "Persistence",
    "Loaded ",
    $result.len,
    " command packets for turn ",
    $turn
  )

proc loadFullState*(dbPath: string): GameState =
  ## Load full GameState from per-game DB
  ## Deserializes complete state from msgpack blob
  let db = open(dbPath, "", "", "")
  defer: db.close()

  try:
    # Load msgpack blob from database
    let row = db.getRow(sql"SELECT state_msgpack FROM games LIMIT 1")
    if row[0] == "":
      logError("Persistence", "No state_msgpack found in database")
      raise newException(ValueError, "Empty state_msgpack in database")

    # Deserialize GameState from msgpack
    result = deserializeGameState(row[0])

    # Restore runtime fields not serialized
    result.dbPath = dbPath
    result.dataDir = dbPath.parentDir.parentDir.parentDir # ../../../data

    logInfo("Persistence", "Loaded full state (msgpack)", "turn=", $result.turn, " size=", $row[0].len, " bytes")
  except:
    logError("Persistence", "Failed to load full state: ", getCurrentExceptionMsg())
    raise

proc countExpectedPlayers*(dbPath: string, gameId: string): int =
  ## Count houses with assigned Nostr pubkeys (human players)
  let state = loadFullState(dbPath)
  for house in state.houses.entities.data:
    if house.nostrPubkey.len > 0:
      result += 1

proc countPlayersSubmitted*(dbPath: string, gameId: string, turn: int32): int =
  ## Count distinct houses that have submitted commands for a turn
  ## Returns number of houses with at least one unprocessed command
  let db = open(dbPath, "", "", "")
  defer: db.close()

  let row = db.getRow(
    sql"""
    SELECT COUNT(DISTINCT house_id)
    FROM commands
    WHERE game_id = ? AND turn = ? AND processed = 0
    """,
    gameId,
    $turn
  )
  result = parseInt(row[0])
