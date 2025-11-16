## JSON storage for game state persistence
##
## MILESTONE 1 - Simple JSON file storage
## Loads and saves game state to/from JSON files

import std/[json, tables, options, os]
import ../engine/[gamestate, fleet, ship, starmap]
import ../common/[hex, system]

type
  StorageError* = object of CatchableError

## Save game state to JSON

proc saveGameState*(state: GameState, filePath: string): bool =
  ## Save game state to JSON file
  ## Returns true on success, false on failure
  ##
  ## TODO M1: Implement JSON serialization
  ## TODO M1: Write to file atomically (temp file + rename)
  ## TODO M1: Add error handling
  ## TODO M1: Validate directory exists
  ##
  ## STUB: Create placeholder JSON file
  try:
    let dir = filePath.parentDir()
    if dir != "" and not dirExists(dir):
      createDir(dir)

    # Create minimal JSON structure
    let jsonObj = %* {
      "gameId": state.gameId,
      "turn": state.turn,
      "year": state.year,
      "month": state.month,
      "phase": $state.phase,
      "houses": {},
      "colonies": {},
      "fleets": {},
      "systems": {},
      "diplomacy": {}
    }

    writeFile(filePath, jsonObj.pretty())
    return true
  except:
    return false

proc saveOrders*(orders: seq[string], filePath: string): bool =
  ## Save player orders to JSON file
  ## Returns true on success, false on failure
  ##
  ## TODO M1: Implement order serialization
  ## TODO M1: Validate order format
  ## TODO M1: Add error handling
  ##
  ## STUB: Save orders as JSON array
  try:
    let dir = filePath.parentDir()
    if dir != "" and not dirExists(dir):
      createDir(dir)

    let jsonArray = %* orders
    writeFile(filePath, jsonArray.pretty())
    return true
  except:
    return false

## Load game state from JSON

proc loadGameState*(filePath: string): Option[GameState] =
  ## Load game state from JSON file
  ## Returns None if file doesn't exist or parsing fails
  ##
  ## TODO M1: Implement JSON deserialization
  ## TODO M1: Validate JSON structure
  ## TODO M1: Add error handling and reporting
  ## TODO M1: Migrate old save format if needed
  ##
  ## STUB: Return empty game state for M1
  if not fileExists(filePath):
    return none(GameState)

  try:
    let jsonData = parseFile(filePath)

    # Create minimal game state from JSON
    var state = GameState(
      gameId: jsonData["gameId"].getStr(),
      turn: jsonData["turn"].getInt(),
      year: jsonData["year"].getInt(),
      month: jsonData["month"].getInt(),
      phase: GamePhase.Active,  # TODO: parse from string
      starMap: StarMap(
        systems: initTable[uint, System](),
        lanes: @[],
        adjacency: initTable[uint, seq[uint]](),
        playerCount: 0,
        numRings: 0
      ),  # TODO: deserialize
      houses: initTable[HouseId, House](),
      colonies: initTable[SystemId, Colony](),
      fleets: initTable[FleetId, Fleet](),
      diplomacy: initTable[(HouseId, HouseId), DiplomaticState]()
    )

    return some(state)
  except:
    return none(GameState)

proc loadOrders*(filePath: string): seq[string] =
  ## Load player orders from JSON file
  ## Returns empty seq if file doesn't exist or parsing fails
  ##
  ## TODO M1: Implement order deserialization
  ## TODO M1: Validate order format
  ## TODO M1: Add error handling and reporting
  ##
  ## STUB: Return empty orders for M1
  result = @[]

  if not fileExists(filePath):
    return

  try:
    let jsonData = parseFile(filePath)
    for item in jsonData.items:
      result.add(item.getStr())
  except:
    discard

## Game directory management

proc getGamePath*(gameId: string, baseDir: string = "games"): string =
  ## Get directory path for a game
  ## Creates directory if it doesn't exist
  ##
  ## Returns: games/{gameId}/
  result = baseDir / gameId
  if not dirExists(result):
    createDir(result)

proc getGameStatePath*(gameId: string, baseDir: string = "games"): string =
  ## Get path to game state file
  ## Returns: games/{gameId}/state.json
  result = getGamePath(gameId, baseDir) / "state.json"

proc getOrdersPath*(gameId: string, houseId: HouseId, baseDir: string = "games"): string =
  ## Get path to house orders file
  ## Returns: games/{gameId}/orders/{houseId}.json
  let ordersDir = getGamePath(gameId, baseDir) / "orders"
  if not dirExists(ordersDir):
    createDir(ordersDir)
  result = ordersDir / ($houseId & ".json")

proc listGames*(baseDir: string = "games"): seq[string] =
  ## List all game directories
  ## Returns list of game IDs
  ##
  ## TODO M1: Add error handling
  ## TODO M1: Validate game directories
  ##
  ## STUB: Return empty list for M1
  result = @[]

  if not dirExists(baseDir):
    return

  try:
    for kind, path in walkDir(baseDir):
      if kind == pcDir:
        result.add(path.lastPathPart)
  except:
    discard
