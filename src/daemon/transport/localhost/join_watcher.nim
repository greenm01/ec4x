## Localhost Join Watcher
##
## Polls requests/join_*.kdl -> parse -> apply join assignment

import std/[os, options, strutils, json]
import db_connector/db_sqlite

import ../../../common/logger
import ../../../common/kdl_join
import ../../../engine/types/core
import ../../transport/nostr/nip19

const
  JoinRequestPrefix = "join_"
  JoinRequestSuffix = ".kdl"

proc findJoinRequests(gameDir: string): seq[string] =
  let requestsDir = gameDir / "requests"
  if not dirExists(requestsDir):
    return @[]

  result = @[]
  for kind, path in walkDir(requestsDir):
    if kind == pcFile and path.extractFilename.startsWith(JoinRequestPrefix) and
        path.endsWith(JoinRequestSuffix):
      result.add(path)

proc writeJoinResponse(gameDir: string, requestPath: string,
                       response: JoinResponse) =
  let responsesDir = gameDir / "responses"
  createDir(responsesDir)

  let base = requestPath.extractFilename
  let responseName = base.replace(JoinRequestPrefix, "join-response_")
  let responsePath = responsesDir / responseName
  writeFile(responsePath, formatJoinResponse(response))

proc parseGameSetupPlayerCount(gameSetupJson: string): int =
  let node = parseJson(gameSetupJson)
  if node.kind != JObject:
    raise newException(ValueError, "Invalid game setup JSON")
  if not node.hasKey("gameParameters"):
    raise newException(ValueError, "Missing gameParameters in setup")
  let params = node["gameParameters"]
  if not params.hasKey("playerCount"):
    raise newException(ValueError, "Missing playerCount in setup")
  params["playerCount"].getInt()

proc findExistingHouseId(db: DbConn, pubkey: string): Option[HouseId] =
  let rows = db.getAllRows(sql"SELECT id FROM houses WHERE nostr_pubkey = ?",
    pubkey)
  if rows.len == 0:
    return none(HouseId)
  let idStr = rows[0][0]
  try:
    some(HouseId(parseInt(idStr).uint32))
  except ValueError:
    none(HouseId)

proc countAssignedHouses(db: DbConn): int =
  let rows = db.getAllRows(sql"SELECT COUNT(*) FROM houses WHERE nostr_pubkey IS NOT NULL")
  if rows.len == 0:
    return 0
  parseInt(rows[0][0])

proc findNextAvailableHouse(db: DbConn): Option[HouseId] =
  let rows = db.getAllRows(sql"SELECT id FROM houses WHERE nostr_pubkey IS NULL ORDER BY id LIMIT 1")
  if rows.len == 0:
    return none(HouseId)
  some(HouseId(parseInt(rows[0][0]).uint32))

proc assignHouse(db: DbConn, houseId: HouseId, pubkey: string) =
  db.exec(sql"UPDATE houses SET nostr_pubkey = ? WHERE id = ?",
    pubkey, $houseId.uint32)

proc loadPlayerLimit(db: DbConn): int =
  let row = db.getRow(sql"SELECT game_setup_json FROM games LIMIT 1")
  parseGameSetupPlayerCount(row[0])

proc handleJoinRequest(gameDir: string, requestPath: string) =
  let request = parseJoinRequestFile(requestPath)
  let normalizedPubkey = normalizeNostrPubkey(request.pubkey)

  let dbPath = gameDir / "ec4x.db"
  if not fileExists(dbPath):
    let response = JoinResponse(
      gameId: request.gameId,
      status: JoinResponseStatus.Rejected,
      reason: some("Game database not found")
    )
    writeJoinResponse(gameDir, requestPath, response)
    discard tryRemoveFile(requestPath)
    return

  let db = open(dbPath, "", "", "")
  defer: db.close()

  var response = JoinResponse(gameId: request.gameId)

  try:
    let existing = findExistingHouseId(db, normalizedPubkey)
    if existing.isSome:
      response.status = JoinResponseStatus.Accepted
      response.houseId = existing
    else:
      let playerLimit = loadPlayerLimit(db)
      let assignedCount = countAssignedHouses(db)
      if assignedCount >= playerLimit:
        response.status = JoinResponseStatus.Rejected
        response.reason = some("game is full")
      else:
        let available = findNextAvailableHouse(db)
        if available.isNone:
          response.status = JoinResponseStatus.Rejected
          response.reason = some("no available houses")
        else:
          assignHouse(db, available.get(), normalizedPubkey)
          response.status = JoinResponseStatus.Accepted
          response.houseId = available
  except CatchableError as e:
    logError("JoinWatcher", "Failed to handle join: ", e.msg)
    response.status = JoinResponseStatus.Rejected
    response.reason = some("join failed")

  writeJoinResponse(gameDir, requestPath, response)
  discard tryRemoveFile(requestPath)

proc collectJoinRequestsLocal*(gameDir: string) =
  let requests = findJoinRequests(gameDir)
  if requests.len == 0:
    return

  logInfo("JoinWatcher", "Processing join requests in ", gameDir)
  for path in requests:
    try:
      handleJoinRequest(gameDir, path)
    except CatchableError as e:
      logError("JoinWatcher", "Failed to process join request: ", path,
        " error: ", e.msg)
