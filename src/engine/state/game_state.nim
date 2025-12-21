import std/macros
import ../types/[core, game_state, player_state, fleet, ship, squadron, ground_unit, facilities, production]

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
    lastTurnReportsd: initTable[HouseId, TurnResolutionReport](),
  )

# Generic getter that works for any collection using our EntityManager pattern
proc getEntity*[ID, T](collection: EntityManager[ID, T], id: ID): Option[T] =
  if collection.index.contains(id):
    let idx = collection.index[id]
    return some(collection.data[idx])
  return none(T)

# Generic adder that works for any collection using our EntityManager pattern
proc addEntity*[ID, T](collection: var EntityManager[ID, T], id: ID, entity: T) =
  collection.data.add(entity)
  collection.index[id] = collection.data.high # Store the index of the last element

proc removeEntity*[ID, T](collection: var EntityManager[ID, T], id: ID) =
  if not collection.index.contains(id): return

  let idxToRemove = collection.index[id]
  let lastIdx = collection.data.high
  let lastEntityId = collection.data[lastIdx].id # Assumes entity has an .id field

  # 1. Swap the element to delete with the very last element in the seq
  collection.data[idxToRemove] = collection.data[lastIdx]
  
  # 2. Update the index for the element that just moved
  collection.index[lastEntityId] = idxToRemove
  
  # 3. Remove the last element and the old index
  collection.data.setLen(lastIdx)
  collection.index.del(id)

# Usage within GameState convenience methods
proc getPlayerState*(state: GameState, id: HouseId): Option[PlayerState] =
  state.houses.getEntity(id)

proc getHouse*(state: GameState, id: HouseId): Option[House] =
  state.houses.getEntity(id)

proc getSystem*(state: GameState, id: SystemId): Option[System] =
  state.systems.getEntity(id)

proc getColony*(state: GameState, id: ColonyId): Option[Colony] =
  state.colonies.getEntity(id)

proc getFleet*(state: GameState, id: FleetId): Option[Fleet] =
  state.fleets.getEntity(id)

proc getShip*(state: GameState, id: ShipId): Option[Ship] =
  state.ships.getEntity(id)

proc getSquadrons*(state: GameState, id: SquadronId): Option[Squadron] =
  state.squadrons.getEntity(id)

proc getGroundUnit*(state: GameState, id: GroundUnitId): Option[GroundUnit] =
  state.groundUnits.getEntity(id)
  
proc getStarBase*(state: GameState, id: GroundUnitId): Option[StarBase] =
  state.starBases.getEntity(id)
  
proc getSpacePort*(state: GameState, id: GroundUnitId): Option[SpacePort] =
  state.spacePorts.getEntity(id)
  
proc getShipYard*(state: GameState, id: GroundUnitId): Option[ShipYard] =
  state.shipYards.getEntity(id)
  
proc getDryDock*(state: GameState, id: GroundUnitId): Option[DryDock] =
  state.dryDocks.getEntity(id)
  
proc getConstructionProject*(state: GameState, id: GroundUnitId): Option[ConstructionProject] =
  state.constructionProjects.getEntity(id)
  
proc getRepairProject*(state: GameState, id: GroundUnitId): Option[RepairProject] =
  state.repairProjects.getEntity(id)

proc spawnShip*(state: var GameState, owner: HouseId, shipClass: ShipClass) =
  let newId = state.generateShipId()
  # TODO: generate shipstats
  let ship = Ship(id: newId, owner: owner, shipClass: shipClass)
    # One line to add to both the sequence and the index
  state.ships.addEntity(newId, ship)
