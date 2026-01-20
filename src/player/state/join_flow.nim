## Join flow state helpers for TUI

import std/[json, jsonutils, options, os, strutils]
import db_connector/db_sqlite
import kdl

import ../../common/logger
import ../../daemon/persistence/reader
import ../../daemon/transport/nostr/nip19
import ../../engine/globals as engine_globals
import ../../engine/state/player_state
import ../../engine/types/[config, core, game_state, player_state as ps_types]
import ../sam/tui_model
import ./delta_applicator
import ./player_state_cache

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

proc loadGameInfo*(dataDir: string, gameId: string): Option[JoinGameInfo] =
  let gamesDir = dataDir / "games"
  if not dirExists(gamesDir):
    return none(JoinGameInfo)
  
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
      if row[0] != gameId and row[1] != gameId:
        continue
      let assignedRow = db.getRow(sql"SELECT COUNT(*) FROM houses WHERE nostr_pubkey IS NOT NULL")
      let playerCount = parsePlayerCount(row[4])
      return some(JoinGameInfo(
        id: row[0],
        name: row[1],
        turn: parseInt(row[2]),
        phase: row[3],
        playerCount: playerCount,
        assignedCount: parseInt(assignedRow[0])
      ))
    except CatchableError as e:
      logError("JoinFlow", "Failed to load game: ", dbPath, " ", e.msg)
  none(JoinGameInfo)

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

proc cachePlayerState*(
  dataDir: string,
  pubkey: string,
  gameId: string,
  state: ps_types.PlayerState
) =
  savePlayerStateSnapshot(dataDir, pubkey, gameId, state.viewingHouse, state.turn, state)

proc loadCachedPlayerState*(
  dataDir: string,
  pubkey: string,
  gameId: string,
  houseId: HouseId
): Option[ps_types.PlayerState] =
  loadLatestPlayerState(dataDir, pubkey, gameId, houseId)

proc applyDeltaToCachedState*(
  dataDir: string,
  pubkey: string,
  gameId: string,
  state: var ps_types.PlayerState,
  deltaKdl: string
): Option[int32] =
  let turnOpt = applyDeltaToPlayerState(state, deltaKdl)
  if turnOpt.isSome:
    savePlayerStateSnapshot(dataDir, pubkey, gameId, state.viewingHouse, state.turn, state)
  turnOpt

proc parseFullStateKdl*(kdlState: string): Option[ps_types.PlayerState] =
  applyFullStateKdl(kdlState)
