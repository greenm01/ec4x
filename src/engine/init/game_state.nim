import std/[tables, monotimes, options]

import ../../common/logger
import ../[globals, starmap]
import ../config/engine
import ../types/[
  core, game_state, squadron, intelligence, diplomacy,
  espionage, resolution, starmap, command, fleet
]

export globals

# Game initialization functions

proc initGameSeed(configSeed: Option[int64]): int64 =
  result = configSeed.get(getMonoTime().ticks)

proc initStarMap*(playerCount: int32, seed: int64): StarMap =
  ## Create a complete, validated starmap
  result = newStarMap(playerCount, seed)
  result.populate()

proc initGameState*(
  setupPath: string = "game_setup/standard.kdl",              # Where to read game_setup configs
  configDir: string = "config",  # Base game rules (rarely changes)
  dataDir: string = "data"               # Where to write save data
): GameState =

  ## Create a new game with automatic setup
  # TODO: Implement game creation logic:
  # 1. populate houses, colonies, fleets

  gameConfig = loadGameConfig(configDir)
  gameSetup = loadGameSetup(setupPath)

  var params = gameSetup.gameParameters
  var seed = params.gameSeed.get(initGameSeed(none(int64)))
  var playerCount = params.playerCount
  var gameId = params.gameId
  var starMap = initStarMap(playerCount, seed) 

  logInfo(
    "Initialization", "Creating new game with ID ", gameId, ", players ", playerCount,
    ", seed ", seed,
  )
         
  # Initialize the ref object
  result = GameState(
    gameId: gameId,
    seed: seed,
    starMap: starMap,  
    turn: 1,
    # Start IDs at 1 so 0 can be used as a "None/Null" value if needed
    counters: IdCounters(
      nextPlayerId: 1,
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

proc initializeHousesAndHomeworlds*(state: var GameState) =
  ## Initialize houses, homeworlds, and starting fleets for all players
  ## Per game setup rules (e.g., docs/specs/05-gameplay.md:1.3)
  ##
  ## This function is called once after GameState creation by newGame:
  ## 1. Reads player count and homeworld settings from config
  ## 2. Creates House objects, assigns homeworlds, starting fleets, etc.
  ## 3. Populates `state.houses`, `state.fleets`, `state.colonies` indices

  logInfo("Initialization", "Initializing houses and homeworlds...")
  # TODO: Implement actual house/homeworld/fleet creation logic here.
  # This will likely involve calling initializeHouse, createHomeColony, and
  # fleet creation helpers.
