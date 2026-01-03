## Game Engine Initialization
##
## Main entry point for creating new games. Orchestrates house, colony,
## and fleet initialization with proper starmap generation.

import std/[tables, monotimes, options, strutils, os, random, json, jsonutils]
import db_connector/db_sqlite

import ../../common/logger
import ../[globals, starmap]
import ../config/engine
import ../state/[engine, id_gen]
import ../persistence/schema
import ../types/[
  core, game_state, squadron, intel, diplomacy,
  espionage, resolution, starmap, command, fleet,
  house
]
import ./house as house_init
import ./colony
import ./fleet
import ./multipliers

export globals # Export globals for external use

# Game initialization functions

proc initGameSeed(configSeed: Option[int64]): int64 =
  result = configSeed.get(getMonoTime().ticks)

proc generateGameId(): string =
  ## Generate a UUID v4 for game identification
  ## Format: 8-4-4-4-12 hex digits (e.g., "550e8400-e29b-41d4-a716-446655440000")
  randomize()

  proc hexByte(): string =
    result = toHex(rand(255), 2).toLowerAscii()

  proc hexBytes(n: int): string =
    for i in 0 ..< n:
      result.add hexByte()

  # UUID v4 format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
  # where y is 8, 9, A, or B
  result = hexBytes(4) & "-" & hexBytes(2) & "-4" & hexBytes(1)[1..1] &
           hexBytes(1) & "-" & ["8", "9", "a", "b"][rand(3)] &
           hexBytes(1)[1..1] & hexBytes(1) & "-" & hexBytes(6)

proc initPerGameDatabase(
    gameId: string,
    gameName: string,
    description: string,
    setupJson: string,
    configJson: string,
    dataDir: string
): string =
  ## Create per-game database directory and initialize schema
  ## Returns database path
  let (dbPath, gameDir) = defaultDBConfig(gameId, dataDir)

  # Create game directory
  createDir(gameDir)
  logInfo("Initialization", "Created game directory: ", gameDir)

  # Open database connection
  let db = open(dbPath, "", "", "")
  defer: db.close()

  # Create all tables
  createAllTables(db)

  # Insert game metadata with configs
  db.exec(sql"""
    INSERT INTO games (
      id, name, description, turn, year, month, phase, transport_mode,
      game_setup_json, game_config_json,
      created_at, updated_at
    ) VALUES (
      ?, ?, ?, 1, 2001, 1, 'Active', 'localhost',
      ?, ?,
      unixepoch(), unixepoch()
    )
  """, gameId, gameName, description, setupJson, configJson)

  logInfo("Initialization", "Initialized database: ", dbPath)
  logInfo("Initialization", "Game: ", gameName, " (", gameId, ")")

  return dbPath

proc initializeHousesAndHomeworlds*(state: var GameState) =
  ## Initialize houses, homeworlds, and starting fleets for all players
  ## Per game setup rules (e.g., docs/specs/05-gameplay.md:1.3)
  ##
  ## This function is called once after GameState creation by newGame:
  ## 1. Reads player count and homeworld settings from config
  ## 2. Creates House objects, assigns homeworlds, starting fleets, etc.
  ## 3. Populates `state.houses`, `state.fleets`, `state.colonies` indices

  logInfo("Initialization", "Initializing houses and homeworlds...")

  let playerCount = gameSetup.gameParameters.playerCount

  # Verify we have enough homeworld systems
  if state.starMap.houseSystemIds.len != playerCount:
    raise newException(
      ValueError,
      "Homeworld count mismatch: expected " & $playerCount &
      " but got " & $state.starMap.houseSystemIds.len
    )

  # Create each house with homeworld and starting forces
  for playerIndex in 0 ..< playerCount:
    let houseId = state.generateHouseId()
    let homeworldSystemId = state.starMap.houseSystemIds[playerIndex]

    # 1. Create House entity
    let houseName = "House " & $(playerIndex + 1)
    let house = house_init.initHouse(houseId, houseName)
    state.addHouse(houseId, house)

    logInfo(
      "Initialization",
      "Created ", houseName, " (ID: ", houseId, ") at system ",
      homeworldSystemId
    )

    # 2. Create homeworld colony
    let colonyId = createHomeWorld(state, homeworldSystemId, houseId)

    logInfo(
      "Initialization",
      "Established homeworld colony (ID: ", colonyId, ") for ", houseName
    )

    # 3. Create starting fleets
    let fleetConfigs = gameSetup.startingFleets.fleets
    createStartingFleets(state, houseId, homeworldSystemId, fleetConfigs)

    logInfo(
      "Initialization",
      "Created ", fleetConfigs.len, " starting fleets for ", houseName
    )

    # 4. Initialize empty intelligence database
    state.intel[houseId] = IntelDatabase()

    # 5. Initialize diplomatic relations (all start neutral)
    for otherPlayerIndex in 0 ..< playerCount:
      if otherPlayerIndex != playerIndex:
        let otherHouseId = (otherPlayerIndex + 1).uint32.HouseId
        let relationKey = (houseId, otherHouseId)
        state.diplomaticRelation[relationKey] = DiplomaticRelation(
          sourceHouse: houseId,
          targetHouse: otherHouseId,
          state: DiplomaticState.Neutral,
          sinceTurn: 1
        )

    # 6. Initialize violation history (empty at start)
    state.diplomaticViolation[houseId] = ViolationHistory()

  logInfo(
    "Initialization",
    "Game initialization complete: ", playerCount, " houses, ",
    state.colonies.entities.data.len, " colonies, ",
    state.fleets.entities.data.len, " fleets"
  )

proc initGameState*(
  setupPath: string = "scenarios/standard-4-player.kdl",
  gameName: string = "",
  gameDescription: string = "",
  configDir: string = "config",
  dataDir: string = "data"
): GameState =
  ## Create a new game - SINGLE ENTRY POINT
  ## All game parameters loaded from config files
  ##
  ## Args:
  ##   setupPath: Path to scenario KDL file (default: scenarios/standard-4-player.kdl)
  ##   gameName: Human-readable game name (default: use scenarioName from config)
  ##   gameDescription: Optional game description for admin notes
  ##   configDir: Directory containing config/*.kdl files
  ##   dataDir: Root directory for per-game databases

  # Load configs
  gameConfig = loadGameConfig(configDir)
  gameSetup = loadGameSetup(setupPath)

  # Extract parameters
  var params = gameSetup.gameParameters
  var seed = params.gameSeed.get(initGameSeed(none(int64)))
  var playerCount = params.playerCount
  var numRings = gameSetup.mapGeneration.numRings

  # Generate UUID for game
  var gameId = generateGameId()

  # Use provided name or fall back to scenario name
  var finalGameName = if gameName != "": gameName else: params.scenarioName
  var finalGameDescription = if gameDescription != "":
    gameDescription
  else:
    params.scenarioDescription

  # Validate map configuration (absolute bounds: 2-12 rings)
  if numRings < 2 or numRings > 12:
    raise newException(ValueError,
      "numRings must be 2-12 (got " & $numRings & "). " &
      "See docs/guides/map-sizing-guide.md for systems-per-player guidance."
    )

  # Log systems-per-player ratio for admin awareness
  let totalSystems = 3 * numRings * numRings + 3 * numRings + 1
  let systemsPerPlayer = totalSystems.float / playerCount.float
  logInfo(
    "Initialization",
    "Map size: ", numRings, " rings = ", totalSystems, " systems (",
    systemsPerPlayer.formatFloat(ffDecimal, 1), " per player)"
  ) 

  logInfo(
    "Initialization", "Creating game ", gameId, ": ", playerCount, " players, ",
    numRings, " rings, seed ", seed
  )

  # Serialize configs to JSON for database storage
  let setupJson = $toJson(gameSetup)
  let configJson = $toJson(gameConfig)

  # Initialize per-game database
  let dbPath = initPerGameDatabase(
    gameId, finalGameName, finalGameDescription,
    setupJson, configJson,
    dataDir
  )

  # Initialize empty GameState
  result = GameState(
    gameId: gameId,
    seed: seed,
    turn: 1,
    dbPath: dbPath,
    dataDir: dataDir,
    counters: IdCounters(
      nextHouseId: 1,
      nextSystemId: 1,
      nextColonyId: 1,
      nextStarbaseId: 1,
      nextSpaceportId: 1,
      nextShipyardId: 1,
      nextDrydockId: 1,
      nextFleetId: 1,
      nextSquadronId: 1,
      nextShipId: 1,
      nextGroundUnitId: 1,
      nextConstructionProjectId: 1,
      nextRepairProjectId: 1,
      nextPopulationTransferId: 1,
    ),
    # Initialize empty entity collections
    houses: Houses(
      entities: EntityManager[HouseId, House](
        data: @[],
        index: initTable[HouseId, int]()
      )
    ),
    systems: Systems(
      entities: EntityManager[SystemId, System](
        data: @[],
        index: initTable[SystemId, int]()
      )
    ),
    # Initialize Tables (Sequences initialize to @[] automatically)
    intel: initTable[HouseId, IntelDatabase](),
    diplomaticRelation: initTable[(HouseId, HouseId), DiplomaticRelation](),
    diplomaticViolation: initTable[HouseId, ViolationHistory](),
    fleetCommands: initTable[FleetId, FleetCommand](),
    standingCommands: initTable[FleetId, StandingCommand](),
    arrivedFleets: initTable[FleetId, SystemId](),
    activeSpyMissions: initTable[FleetId, ActiveSpyMission](),
    gracePeriodTimers: initTable[HouseId, GracePeriodTracker](),
    lastTurnReports: initTable[HouseId, TurnResolutionReport](),
  )

  # Initialize ref squadrons collection
  new(result.squadrons)
  result.squadrons[] = Squadrons(
    entities: EntityManager[SquadronId, Squadron](
      data: @[],
      index: initTable[SquadronId, int]()
    ),
    byFleet: initTable[FleetId, seq[SquadronId]](),
    byHouse: initTable[HouseId, seq[SquadronId]]()
  )

  # Generate starmap (populates result.systems)
  result.starMap = generateStarMap(result, playerCount, numRings.uint32)

  logInfo("Initialization", "Generated map with ", result.systems.entities.data.len, " systems")

  # Initialize dynamic multipliers based on map size and player count
  let numSystems = result.systems.entities.data.len.int32
  initPrestigeMultiplier(numSystems, playerCount.int32)
  initPopulationGrowthMultiplier(numSystems, playerCount.int32)

  # Initialize houses, homeworlds, and starting fleets
  initializeHousesAndHomeworlds(result)
