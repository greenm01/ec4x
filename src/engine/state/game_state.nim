# src/engine/
# └── state/
#    ├── game_state.nim  # Data structure + Core Iterators (allShips, allFleets)
#    ├── id_gen.nim      # Counter logic
#    └── queries.nim     # Spatial/Complex Iterators (shipsInSystem, enemiesNear)

import std/[macros, tables, options]
import ./entity_manager
import ../types/[
  core, game_state, fleet, ship, squadron, ground_unit, house, colony, facilities,
  facilities, production, intelligence, diplomacy, espionage, resolution, starmap
]

proc initGameState*(): GameState =
  # Initialize the ref object
  result = GameState(
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
    turn: 1,
    phase: Command, 
    # Initialize Tables (Sequences initialize to @[] automatically)
    intelligence: initTable[HouseId, IntelligenceDatabase](),
    diplomaticRelation: initTable[(HouseId, HouseId), DiplomaticRelation](),
    diplomaticViolation: initTable[HouseId, ViolationHistory](),
    arrivedFleets: initTable[FleetId, SystemId](),
    activeSpyMissions: initTable[FleetId, ActiveSpyMission](),
    gracePeriodTimers: initTable[HouseId, GracePeriodTracker](),
    lastTurnReports: initTable[HouseId, TurnResolutionReport](),
  )

# Usage within GameState convenience methods
# proc getPlayerState*(state: GameState, id: HouseId): Option[PlayerState] =
#  state.houses.getEntity(id)

proc getHouse*(state: GameState, id: HouseId): Option[House] =
  state.houses.entities.getEntity(id)

proc getSystem*(state: GameState, id: SystemId): Option[System] =
  state.systems.entities.getEntity(id)

proc getColony*(state: GameState, id: ColonyId): Option[Colony] =
  state.colonies.entities.getEntity(id)

proc getFleet*(state: GameState, id: FleetId): Option[Fleet] =
  state.fleets.entities.getEntity(id)

proc getShip*(state: GameState, id: ShipId): Option[Ship] =
  state.ships.entities.getEntity(id)

proc getSquadrons*(state: GameState, id: SquadronId): Option[Squadron] =
  state.squadrons.entities.getEntity(id)

proc getGroundUnit*(state: GameState, id: GroundUnitId): Option[GroundUnit] =
  state.groundUnits.entities.getEntity(id)
  
proc getStarBase*(state: GameState, id: StarbaseId): Option[Starbase] =
  state.starBases.entities.getEntity(id)
  
proc getSpacePort*(state: GameState, id: SpaceportId): Option[Spaceport] =
  state.spacePorts.entities.getEntity(id)
  
proc getShipYard*(state: GameState, id: ShipyardId): Option[Shipyard] =
  state.shipYards.entities.getEntity(id)
  
proc getDryDock*(state: GameState, id: DrydockId): Option[Drydock] =
  state.dryDocks.entities.getEntity(id)
  
proc getConstructionProject*(state: GameState, id: ConstructionProjectId): Option[ConstructionProject] =
  state.constructionProjects.entities.getEntity(id)
  
proc getRepairProject*(state: GameState, id: RepairProjectId): Option[RepairProject] =
  state.repairProjects.entities.getEntity(id)

proc getIntel*(state: GameState, id: HouseId): Option[IntelligenceDatabase] =
  ## Direct table lookup for intelligence memory
  if state.intelligence.contains(id):
    return some(state.intelligence[id])
  return none(IntelligenceDatabase)

iterator allShips*(state: GameState): Ship =
  for ship in state.ships.entities.data:
    yield ship

iterator allHouses*(state: GameState): House =
  for house in state.houses.entities.data:
    yield house

# Mutable iterator for when you need to update values (AS, DS, combat state)
iterator mAllShips*(state: var GameState): var Ship =
  for ship in mitems(state.ships.entities.data):
    yield ship
