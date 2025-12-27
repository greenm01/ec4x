import std/[tables]
import ../../common/logger
import ../[globals, starmap]
import ../types/[
  core, game_state, squadron, intelligence, diplomacy, espionage, resolution, starmap,
  command, fleet,
]

# Game initialization functions

proc initStarMap*(playerCount: int32, seed: int64 = 2001): StarMap =
  ## Create and fully generate a validated starmap
  ##
  ## Args:
  ##   playerCount: Number of players (2-12)
  ##   seed: Random seed for deterministic generation
  ##
  ## Returns:
  ##   Fully populated StarMap with systems, lanes, and homeworlds
  ##
  ## Raises:
  ##   StarMapError: If validation fails or invalid player count

  result = newStarMap(playerCount, seed)  # newStarMap validates playerCount
  result.populate()
  
proc newGame*(gameId: int32, playerCount: int32, seed: int64): GameState =
  ## Create a new game with automatic setup
  ## Uses default parameters for map size, AI personalities, etc.
  ## Returns a fully initialized GameState object

  # TODO: Implement game creation logic:
  # 1. Load game parameters from config files (e.g., game_setup/standard.toml)
  # 2. Generate starMap based on seed and parameters
  # 3. Call newGameState to create the initial state with the generated starmap
  # 4. Call initializeHousesAndHomeworlds to populate houses, colonies, fleets

  logInfo(
    "Initialization", "Creating new game with ID ", gameId, ", players ", playerCount,
    ", seed ", seed,
  )

  # Initialize the ref object
  result = GameState(
    gameId: gameId,
    seed: seed,
    starMap: initStarMap(playerCount, seed),  
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
