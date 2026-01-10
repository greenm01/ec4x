## Game Engine Initialization (Pure)
##
## Main entry point for creating new games. Orchestrates house, colony,
## and fleet initialization with proper starmap generation.
##
## IMPORTANT: This module is PURE - no I/O, no database operations.
## Database persistence is handled by src/daemon/persistence/init.nim

import std/[tables, monotimes, options, strutils, random]

import ../../common/logger
import ../[globals, starmap]
import ../config/engine
import ../state/[engine, id_gen]
import ../types/[
  core, game_state, intel, diplomacy,
  resolution, starmap, house
]
import ./house
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

proc initializeHousesAndHomeworlds*(state: GameState) =
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
    let house = initHouse(houseId, houseName)
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
    state.coloniesCount(), " colonies, ",
    state.fleetsCount(), " fleets"
  )

proc createEmptyGameState(
    gameId: string,
    seed: int64,
    dataDir: string = ""
): GameState =
  ## Create an empty GameState with initialized collections
  ## This is a pure helper - no I/O
  result = GameState(
    gameId: gameId,
    seed: seed,
    turn: 1,
    dbPath: "",  # Set by daemon after DB creation
    dataDir: dataDir,
    counters: IdCounters(
      nextHouseId: 1,
      nextSystemId: 1,
      nextColonyId: 1,
      nextNeoriaId: 1,
      nextKastraId: 1,
      nextFleetId: 1,
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
    gracePeriodTimers: initTable[HouseId, GracePeriodTracker](),
    lastTurnReports: initTable[HouseId, TurnResolutionReport](),
  )

proc initGameState*(
  setupPath: string = "scenarios/standard-4-player.kdl",
  gameName: string = "",
  gameDescription: string = "",
  configDir: string = "config",
  dataDir: string = "data"
): GameState =
  ## Create a new game from a scenario file - PURE function, no I/O
  ##
  ## This is the scenario-based entry point, loading all parameters from
  ## the KDL scenario file.
  ##
  ## Args:
  ##   setupPath: Path to scenario KDL file
  ##   gameName: Human-readable game name (default: use scenarioName)
  ##   gameDescription: Optional game description
  ##   configDir: Directory containing config files
  ##   dataDir: Root data directory

  # Load configs
  gameConfig = loadGameConfig(configDir)
  gameSetup = loadGameSetup(setupPath)

  # Extract parameters
  let params = gameSetup.gameParameters
  let seed = params.gameSeed.get(initGameSeed(none(int64)))
  let playerCount = params.playerCount
  let numRings = gameSetup.mapGeneration.numRings

  # Generate UUID for game
  let gameId = generateGameId()

  # Use provided name or fall back to scenario name
  let finalGameName = if gameName != "": gameName else: params.scenarioName

  # Validate map configuration
  if numRings < 2 or numRings > 12:
    raise newException(ValueError,
      "numRings must be 2-12 (got " & $numRings & "). " &
      "See docs/guides/map-sizing-guide.md for systems-per-player guidance."
    )

  # Log setup
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

  # Create empty state
  result = createEmptyGameState(gameId, seed, dataDir)
  result.gameName = finalGameName
  result.gameDescription = gameDescription

  # Generate starmap
  result.starMap = generateStarMap(result, playerCount, numRings.uint32)
  logInfo("Initialization", "Generated map with ", result.systemsCount(),
          " systems")

  # Initialize dynamic multipliers
  let numSystems = result.systemsCount()
  initPrestigeMultiplier(numSystems, playerCount.int32)
  initPopulationGrowthMultiplier(numSystems, playerCount.int32)

  # Initialize houses, homeworlds, and starting fleets
  initializeHousesAndHomeworlds(result)
