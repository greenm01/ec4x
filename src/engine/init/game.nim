import std/[tables]
import ../../common/logger
import ../types/[
  core, game_state, squadron, intelligence,
  diplomacy, espionage, resolution, starmap, command, fleet
]

# Game initialization functions

proc newGame*(gameId: int32, playerCount: int32, seed: int32): GameState =
  ## Create a new game with automatic setup
  ## Uses default parameters for map size, AI personalities, etc.
  ## Returns a fully initialized GameState object

  # TODO: Implement game creation logic:
  # 1. Load game parameters from config files (e.g., game_setup/standard.toml)
  # 2. Generate starMap based on seed and parameters
  # 3. Call newGameState to create the initial state with the generated starmap
  # 4. Call initializeHousesAndHomeworlds to populate houses, colonies, fleets

  logInfo("Initialization", "Creating new game with ID ", gameId, ", players ",
          playerCount, ", seed ", seed)

  # Initialize the ref object
  result = GameState(
    gameId: gameId,
    seed: seed,
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
      nextPopulationTransferId: 1
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

proc newGameState*(gameId, seed, playerCount: int32, starMap: StarMap): GameState =
  ## Create a new game state with an existing star map
  ## Used for loading games or custom map setups
  ## Requires player count to initialize house/AI configurations

  # TODO: Implement game state creation logic:
  # Initialize core GameState fields, set up initial indices,
  # but do NOT initialize houses/colonies/fleets here directly.
  # That will be handled by initializeHousesAndHomeworlds.

  logInfo("Initialization", "Creating new game state for game ID ", gameId,
          " with ", playerCount, " players.")

  let turn: int32 = 1
  
  result = GameState(
    gameId: gameId,
    seed: seed,
    turn: turn,
    starMap: starMap,
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
      nextPopulationTransferId: 1
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
    # ... other default initializations for a blank state
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
