## Join flow helpers for localhost TUI

import std/[json, jsonutils, options, os, strutils, times]
import db_connector/db_sqlite
import kdl

import ../../common/kdl_join
import ../../common/logger
import ../../daemon/persistence/reader
import ../../daemon/transport/nostr/nip19
import ../../engine/globals as engine_globals
import ../../engine/state/player_state
import ../../engine/types/[config, core, game_state, player_state as ps_types]
import ../sam/tui_model

const
  JoinCacheNode = "join-cache"

proc parsePlayerCount(gameSetupJson: string): int =
  let node = parseJson(gameSetupJson)
  if node.kind != JObject:
    raise newException(ValueError, "Invalid game setup JSON")
  if not node.hasKey("gameParameters"):
    raise newException(ValueError, "Missing gameParameters in setup")
  let params = node["gameParameters"]
  if not params.hasKey("playerCount"):
    raise newException(ValueError, "Missing playerCount in setup")
  params["playerCount"].getInt()

proc loadJoinGames*(dataDir: string): seq[JoinGameInfo] =
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

    try:
      let db = open(dbPath, "", "", "")
      defer: db.close()
      let row = db.getRow(sql"SELECT id, name, turn, phase, game_setup_json FROM games LIMIT 1")
      let assignedRow = db.getRow(sql"SELECT COUNT(*) FROM houses WHERE nostr_pubkey IS NOT NULL")
      let playerCount = parsePlayerCount(row[4])
      result.add(JoinGameInfo(
        id: row[0],
        name: row[1],
        turn: parseInt(row[2]),
        phase: row[3],
        playerCount: playerCount,
        assignedCount: parseInt(assignedRow[0])
      ))
    except CatchableError as e:
      logError("JoinFlow", "Failed to load game info: ", path, " ", e.msg)

proc writeJoinRequest*(gameDir: string, request: JoinRequest): string =
  let requestsDir = gameDir / "requests"
  createDir(requestsDir)
  let stamp = $getTime().toUnix() & "_" & $getCurrentProcessId()
  let requestPath = requestsDir / ("join_" & stamp & ".kdl")
  writeFile(requestPath, formatJoinRequest(request))
  requestPath

proc responsePathForRequest*(gameDir: string, requestPath: string): string =
  let base = requestPath.extractFilename
  let responseName = base.replace("join_", "join-response_")
  gameDir / "responses" / responseName

proc readJoinResponse*(gameDir: string, requestPath: string): Option[JoinResponse] =
  let responsePath = responsePathForRequest(gameDir, requestPath)
  if not fileExists(responsePath):
    return none(JoinResponse)
  let response = parseJoinResponseFile(responsePath)
  discard tryRemoveFile(responsePath)
  some(response)

proc normalizePubkey*(pubkey: string): Option[string] =
  try:
    some(normalizeNostrPubkey(pubkey))
  except CatchableError:
    none(string)

proc joinCachePath(dataDir: string, pubkey: string, gameId: string): string =
  let playersDir = dataDir / "players" / pubkey / "games"
  createDir(playersDir)
  playersDir / (gameId & ".kdl")

proc writeJoinCache*(dataDir: string, pubkey: string, gameId: string,
                     houseId: HouseId) =
  let cachePath = joinCachePath(dataDir, pubkey, gameId)
  let content = "join-cache game=\"" & gameId & "\" " &
    "house=(HouseId)" & $houseId.uint32 & " " &
    "pubkey=\"" & pubkey & "\"\n"
  writeFile(cachePath, content)

proc readJoinCache*(dataDir: string, pubkey: string, gameId: string): Option[HouseId] =
  let cachePath = joinCachePath(dataDir, pubkey, gameId)
  if not fileExists(cachePath):
    return none(HouseId)

  let content = readFile(cachePath)
  let doc = parseKdl(content)
  if doc.len == 0 or doc[0].name != JoinCacheNode:
    return none(HouseId)

  let node = doc[0]
  if not node.props.hasKey("house"):
    return none(HouseId)

  try:
    some(HouseId(node.props["house"].getInt().uint32))
  except CatchableError:
    none(HouseId)

proc loadGameConfigFromDb*(dbPath: string): tuple[setup: GameSetup, config: GameConfig] =
  let db = open(dbPath, "", "", "")
  defer: db.close()
  let row = db.getRow(sql"SELECT game_setup_json, game_config_json FROM games LIMIT 1")
  result.setup = parseJson(row[0]).jsonTo(GameSetup)
  result.config = parseJson(row[1]).jsonTo(GameConfig)

proc loadGameStateForHouse*(dbPath: string, houseId: HouseId): GameState =
  let configs = loadGameConfigFromDb(dbPath)
  engine_globals.gameSetup = configs.setup
  engine_globals.gameConfig = configs.config
  reader.loadFullState(dbPath)

proc loadPlayerState*(state: GameState, houseId: HouseId): ps_types.PlayerState =
  createPlayerState(state, houseId)
