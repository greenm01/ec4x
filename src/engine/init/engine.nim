import std/[tables, monotimes, options, strutils]

import ../../common/logger
import ../[globals, starmap]
import ../config/engine
import ../state/[id_gen, entity_manager]
import ../types/[
  core, game_state, squadron, intelligence, diplomacy,
  espionage, resolution, starmap, command, fleet,
  house
]
import ./house as house_init
import ./colony
import ./fleet

export globals # Export globals for external use

# Game initialization functions

proc initGameSeed(configSeed: Option[int64]): int64 =
  result = configSeed.get(getMonoTime().ticks)

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
    state.houses.entities.addEntity(houseId, house)

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
    state.intelligence[houseId] = IntelligenceDatabase()

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
  setupPath: string = "game_setup/standard.kdl",
  configDir: string = "config",
  dataDir: string = "data"
): GameState =
  ## Create a new game - SINGLE ENTRY POINT
  ## All game parameters loaded from config files
  ## No CLI overrides - ensures reproducibility from config alone

  # Load configs
  gameConfig = loadGameConfig(configDir)
  gameSetup = loadGameSetup(setupPath)

  # Extract parameters
  var params = gameSetup.gameParameters
  var seed = params.gameSeed.get(initGameSeed(none(int64)))
  var playerCount = params.playerCount
  var gameId = params.gameId
  var numRings = gameSetup.mapGeneration.numRings

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

  # Initialize empty GameState
  result = GameState(
    gameId: gameId,
    seed: seed,
    turn: 1,
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
    intelligence: initTable[HouseId, IntelligenceDatabase](),
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

  # Initialize houses, homeworlds, and starting fleets
  initializeHousesAndHomeworlds(result)
