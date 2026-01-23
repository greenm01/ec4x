## Persistence Reader: Load GameState from DB
##
## Migration: Switched from JSON to msgpack for GameState persistence
## - Entity tables (houses, systems, colonies, fleets, ships) removed
## - GameState loaded directly from games.state_msgpack blob
## - Intel data included in GameState.intel
## - Faster deserialization and type safety

import std/[tables, options, json, strutils, jsonutils, os]
import db_connector/db_sqlite
import ../../common/logger
import ../../engine/types/[game_state, core, house, fleet, command, tech, production, diplomacy, espionage]
import ../../engine/state/engine
import ./msgpack_state
import ./player_state_snapshot

# Replay protection

type ReplayDirection* {.pure.} = enum
  Inbound = 0
  Outbound = 1

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
  
  # Group commands by house_id
  let rows = db.getAllRows(sql"""
    SELECT house_id, fleet_id, colony_id, command_type, target_system_id, target_fleet_id, params
    FROM commands
    WHERE turn = ? AND processed = 0
  """, $turn)
  
  for row in rows:
    let houseId = HouseId(parseInt(row[0]).uint32)
    if not result.hasKey(houseId):
      result[houseId] = CommandPacket(
        houseId: houseId,
        turn: turn.int32,
        fleetCommands: @[],
        buildCommands: @[],
        # ... init other fields
      )
    
    let fleetIdStr = row[1]
    let colonyIdStr = row[2]
    discard colonyIdStr
    let cmdType = row[3]
    let params = parseJson(row[6])
    
    if fleetIdStr != "":
      # Fleet command
      var cmd = FleetCommand(
        fleetId: FleetId(parseInt(fleetIdStr).uint32),
        commandType: parseEnum[FleetCommandType](cmdType)
      )
      if row[4] != "": cmd.targetSystem = some(SystemId(parseInt(row[4]).uint32))
      if row[5] != "": cmd.targetFleet = some(FleetId(parseInt(row[5]).uint32))
      if params.hasKey("roe") and params["roe"].kind != JNull:
        cmd.roe = some(params["roe"].getInt().int32)
      if params.hasKey("priority"):
        cmd.priority = params["priority"].getInt().int32
      result[houseId].fleetCommands.add(cmd)
    elif cmdType == "Build":
      # Build command
      let cmd = params.jsonTo(BuildCommand)
      result[houseId].buildCommands.add(cmd)
    elif cmdType == "Research":
      # Research allocation (manual deserialization for enum-keyed table)
      var alloc = ResearchAllocation(
        economic: params["economic"].getInt().int32,
        science: params["science"].getInt().int32,
        technology: initTable[TechField, int32]()
      )
      if params.hasKey("technology") and params["technology"].kind == JObject:
        for fieldStr, pointsNode in params["technology"].pairs:
          let field = parseEnum[TechField](fieldStr)
          alloc.technology[field] = pointsNode.getInt().int32
      result[houseId].researchAllocation = alloc
    elif cmdType == "EspionageBudget":
      # Espionage budget investment
      result[houseId].ebpInvestment = params["ebpInvestment"].getInt().int32
      result[houseId].cipInvestment = params["cipInvestment"].getInt().int32
    elif cmdType == "EspionageAction":
      # Espionage action
      let action = params.jsonTo(EspionageAttempt)
      result[houseId].espionageActions.add(action)
    elif cmdType == "Diplomatic":
      # Diplomatic command
      let cmd = params.jsonTo(DiplomaticCommand)
      result[houseId].diplomaticCommand.add(cmd)

  logInfo("Persistence", "Loaded ", $result.len, " command packets for turn ", $turn)

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

