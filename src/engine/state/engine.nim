import std/[tables, options]
import
  ../types/[
    core, game_state, fleet, ship, squadron, ground_unit, house, colony, facilities,
    production, intel, starmap, population,
  ]

include ./entity_manager

proc house*(state: GameState, id: HouseId): Option[House] {.inline.} =
  state.houses.entities.entity(id)

proc addHouse*(state: GameState, id: HouseId, house: House) {.inline.} =
  state.houses.entities.addEntity(id, house)
  
proc updateHouse*(state: GameState, id: HouseId, house: House) {.inline.} =
  state.houses.entities.updateEntity(id, house)

proc delHouse*(state: GameState, id: HouseId) {.inline.} =
  state.houses.entities.delEntity(id)

proc system*(state: GameState, id: SystemId): Option[System] {.inline.} =
  state.systems.entities.entity(id)

proc updateSystem*(state: GameState, id: SystemId, system: System) {.inline.} =
  state.systems.entities.updateEntity(id, system)

proc delSystem*(state: GameState, id: SystemId) {.inline.} =
  state.systems.entities.delEntity(id)

proc addSystem*(state: GameState, id: SystemId, system: System) {.inline.} =
  state.systems.entities.addEntity(id, system)

proc colony*(state: GameState, id: ColonyId): Option[Colony] {.inline.} =
  state.colonies.entities.entity(id)

proc updateColony*(state: GameState, id: ColonyId, colony: Colony) {.inline.} =
  state.colonies.entities.updateEntity(id, colony)
  
proc delColony*(state: GameState, id: ColonyId) {.inline.} =
  state.colonies.entities.delEntity(id)

proc addColony*(state: GameState, id: ColonyId, colony: Colony) {.inline.} =
  state.colonies.entities.addEntity(id, colony)
  
proc fleet*(state: GameState, id: FleetId): Option[Fleet] {.inline.} =
  state.fleets.entities.entity(id)

proc updateFleet*(state: GameState, id: FleetId, fleet: Fleet) {.inline.} =
  state.fleets.entities.updateEntity(id, fleet)

proc delFleet*(state: GameState, id: FleetId) {.inline.} =
  state.fleets.entities.delEntity(id)

proc addFleet*(state: GameState, id: FleetId, fleet: Fleet) {.inline.} =
  state.fleets.entities.addEntity(id, fleet)

proc ship*(state: GameState, id: ShipId): Option[Ship] {.inline.} =
  state.ships.entities.entity(id)

proc updateShip*(state: GameState, id: ShipId, ship: Ship) {.inline.} =
  state.ships.entities.updateEntity(id, ship)
  
proc delShip*(state: GameState, id: ShipId) {.inline.} =
  state.ships.entities.delEntity(id)

proc addShip*(state: GameState, id: ShipId, ship: Ship) {.inline.} =
  state.ships.entities.addEntity(id, ship)
  
proc squadron*(state: GameState, id: SquadronId): Option[Squadron] {.inline.} =
  state.squadrons.entities.entity(id)

proc updateSquadron*(state: GameState, id: SquadronId, squadron: Squadron) {.inline.} =
  state.squadrons.entities.updateEntity(id, squadron)

proc delSquadron*(state: GameState, id: SquadronId) {.inline.} =
  state.squadrons.entities.delEntity(id)

proc addSquadron*(state: GameState, id: SquadronId, squadron: Squadron) {.inline.} =
  state.squadrons.entities.addEntity(id, squadron)

proc groundUnit*(state: GameState, id: GroundUnitId): Option[GroundUnit] {.inline.} =
  state.groundUnits.entities.entity(id)

proc updateGroundUnit*(state: GameState, id: GroundUnitId, groundUnit: GroundUnit) {.inline.} =
  state.groundUnits.entities.updateEntity(id, groundUnit)

proc delGroundUnit*(state: GameState, id: GroundUnitId) {.inline.} =
  state.groundUnits.entities.delEntity(id)

proc addGroundUnit*(state: GameState, id: GroundUnitId, groundUnit: GroundUnit) {.inline.} =
  state.groundUnits.entities.addEntity(id, groundUnit)

proc neoria*(state: GameState, id: NeoriaId): Option[Neoria] {.inline.} =
  state.neorias.entities.entity(id)

proc updateNeoria*(state: GameState, id: NeoriaId, neoria: Neoria) {.inline.} =
  state.neorias.entities.updateEntity(id, neoria)

proc delNeoria*(state: GameState, id: NeoriaId) {.inline.} =
  state.neorias.entities.delEntity(id)

proc addNeoria*(state: GameState, id: NeoriaId, neoria: Neoria) {.inline.} =
  state.neorias.entities.addEntity(id, neoria)

proc kastra*(state: GameState, id: KastraId): Option[Kastra] {.inline.} =
  state.kastras.entities.entity(id)

proc updateKastra*(state: GameState, id: KastraId, kastra: Kastra) {.inline.} =
  state.kastras.entities.updateEntity(id, kastra)

proc delKastra*(state: GameState, id: KastraId) {.inline.} =
  state.kastras.entities.delEntity(id)

proc addKastra*(state: GameState, id: KastraId, kastra: Kastra) {.inline.} =
  state.kastras.entities.addEntity(id, kastra)

proc constructionProject*(
    state: GameState, id: ConstructionProjectId
): Option[ConstructionProject] =
  state.constructionProjects.entities.entity(id)

proc updateConstructionProject*(
    state: GameState, id: ConstructionProjectId, project: ConstructionProject
) {.inline.} =
  state.constructionProjects.entities.updateEntity(id, project)

proc delConstructionProject*(
    state: GameState, id: ConstructionProjectId
) {.inline.} =
  state.constructionProjects.entities.delEntity(id)

proc addConstructionProject*(
    state: GameState, id: ConstructionProjectId, project: ConstructionProject
) {.inline.} =
  state.constructionProjects.entities.addEntity(id, project)

proc repairProject*(state: GameState, id: RepairProjectId): Option[RepairProject] =
  state.repairProjects.entities.entity(id)

proc updateRepairProject*(
    state: GameState, id: RepairProjectId, project: RepairProject
) {.inline.} =
  state.repairProjects.entities.updateEntity(id, project)

proc delRepairProject*(
    state: GameState, id: RepairProjectId
) {.inline.} =
  state.repairProjects.entities.delEntity(id)

proc addRepairProject*(
    state: GameState, id: RepairProjectId, project: RepairProject
) {.inline.} =
  state.repairProjects.entities.addEntity(id, project)

proc populationTransfer*(
    state: GameState, id: PopulationTransferId
): Option[PopulationInTransit] =
  state.populationTransfers.entities.entity(id)

proc updatePopulationTransfer*(
    state: GameState, id: PopulationTransferId, transfer: PopulationInTransit
) {.inline.} =
  state.populationTransfers.entities.updateEntity(id, transfer)

proc delPopulationTransfer*(
    state: GameState, id: PopulationTransferId
) {.inline.} =
  state.populationTransfers.entities.delEntity(id)

proc addPopulationTransfer*(
    state: GameState, id: PopulationTransferId, transfer: PopulationInTransit
) {.inline.} =
  state.populationTransfers.entities.addEntity(id, transfer)

proc intel*(state: GameState, id: HouseId): Option[IntelDatabase] =
  ## Direct table lookup for intelligence memory
  if state.intel.contains(id):
    return some(state.intel[id])
  return none(IntelDatabase)

proc systemsCount*(state: GameState): int32 {.inline.} =
  ## Get the total number of systems in the game state
  state.systems.entities.data.len.int32

proc housesCount*(state: GameState): int32 {.inline.} =
  ## Get the total number of houses in the game state
  state.houses.entities.data.len.int32

proc coloniesCount*(state: GameState): int32 {.inline.} =
  ## Get the total number of colonies in the game state
  state.colonies.entities.data.len.int32

proc fleetsCount*(state: GameState): int32 {.inline.} =
  ## Get the total number of fleets in the game state
  state.fleets.entities.data.len.int32

proc shipsCount*(state: GameState): int32 {.inline.} =
  ## Get the total number of ships in the game state
  state.ships.entities.data.len.int32

proc squadronsCount*(state: GameState): int32 {.inline.} =
  ## Get the total number of squadrons in the game state
  state.squadrons.entities.data.len.int32

proc groundUnitsCount*(state: GameState): int32 {.inline.} =
  ## Get the total number of ground units in the game state
  state.groundUnits.entities.data.len.int32

proc neoriasCount*(state: GameState): int32 {.inline.} =
  ## Get the total number of neorias (production facilities) in the game state
  state.neorias.entities.data.len.int32

proc kastrasCount*(state: GameState): int32 {.inline.} =
  ## Get the total number of kastras (defensive facilities) in the game state
  state.kastras.entities.data.len.int32

proc constructionProjectsCount*(state: GameState): int32 {.inline.} =
  ## Get the total number of construction projects in the game state
  state.constructionProjects.entities.data.len.int32

proc repairProjectsCount*(state: GameState): int32 {.inline.} =
  ## Get the total number of repair projects in the game state
  state.repairProjects.entities.data.len.int32

proc populationTransfersCount*(state: GameState): int32 {.inline.} =
  ## Get the total number of population transfers in the game state
  state.populationTransfers.entities.data.len.int32

# ============================================================================
# Colony Accessors (bySystem: 1:1)
# ============================================================================

proc colonyBySystem*(state: GameState, systemId: SystemId): Option[Colony] =
  ## Look up colony at system (1:1 relationship)
  ## Returns: Some(colony) if exists, None if system uncolonized
  ##
  ## Replaces verbose pattern:
  ##   if state.colonies.bySystem.hasKey(systemId):
  ##     let colonyId = state.colonies.bySystem[systemId]
  ##     let colonyOpt = state.colonies.entities.entity(colonyId)
  ##
  ## Example:
  ##   let colonyOpt = state.colonyBySystem(systemId)
  ##   if colonyOpt.isSome:
  ##     echo "Colony population: ", colonyOpt.get().population
  if state.colonies.bySystem.hasKey(systemId):
    let colonyId = state.colonies.bySystem[systemId]
    return state.colonies.entities.entity(colonyId)
  return none(Colony)

# ============================================================================
# Squadron Accessors (byFleet: 1:many)
# ============================================================================

proc squadronsByFleet*(state: GameState, fleetId: FleetId): seq[Squadron] =
  ## Get all squadrons in a fleet (1:many relationship)
  ## Returns: seq of squadrons (empty if fleet has no squadrons)
  ##
  ## Note: For batch processing all squadrons, use iterator squadronsOwned()
  ## Use this helper when you need a seq for later use or non-iterator context
  ##
  ## Example:
  ##   let squadrons = state.squadronsByFleet(fleetId)
  ##   for squadron in squadrons:
  ##     echo "Squadron type: ", squadron.squadronType
  result = @[]
  if state.squadrons.byFleet.hasKey(fleetId):
    for squadronId in state.squadrons.byFleet[fleetId]:
      let squadronOpt = state.squadrons.entities.entity(squadronId)
      if squadronOpt.isSome:
        result.add(squadronOpt.get())

# ============================================================================
# Ship Accessors (bySquadron: 1:many)
# ============================================================================

proc shipsBySquadron*(state: GameState, squadronId: SquadronId): seq[Ship] =
  ## Get all ships in a squadron (1:many relationship)
  ## Returns: seq of ships (empty if squadron has no ships)
  ##
  ## Note: For batch processing all ships owned by house, use iterator shipsOwned()
  ## Use this helper when you need ships for a specific squadron
  ##
  ## Example:
  ##   let ships = state.shipsBySquadron(squadronId)
  ##   let totalAS = ships.mapIt(it.attackStrength).sum()
  result = @[]
  if state.ships.bySquadron.hasKey(squadronId):
    for shipId in state.ships.bySquadron[squadronId]:
      let shipOpt = state.ships.entities.entity(shipId)
      if shipOpt.isSome:
        result.add(shipOpt.get())

# ============================================================================
# Ground Unit Accessors (byColony: 1:many, byTransport: 1:many)
# ============================================================================

proc groundUnitsAtColony*(state: GameState, colonyId: ColonyId): seq[GroundUnit] =
  ## Get all ground units stationed at a colony (1:many relationship)
  ## Returns: seq of ground units (empty if colony has no units)
  ##
  ## Note: For batch processing all units owned by house, use iterator groundUnitsOwned()
  ## Use this helper when you need units for a specific colony
  ##
  ## Example:
  ##   let defenders = state.groundUnitsAtColony(colonyId)
  ##   let totalDefenseStrength = defenders.mapIt(it.defenseStrength).sum()
  result = @[]
  if state.groundUnits.byColony.hasKey(colonyId):
    for unitId in state.groundUnits.byColony[colonyId]:
      let unitOpt = state.groundUnits.entities.entity(unitId)
      if unitOpt.isSome:
        result.add(unitOpt.get())

proc groundUnitsOnTransport*(
    state: GameState, transportId: ShipId
): seq[GroundUnit] =
  ## Get all ground units loaded on a transport ship (1:many relationship)
  ## Returns: seq of ground units (empty if transport has no units)
  ##
  ## Example:
  ##   let marines = state.groundUnitsOnTransport(transportShipId)
  ##   echo "Marines aboard: ", marines.len
  result = @[]
  if state.groundUnits.byTransport.hasKey(transportId):
    for unitId in state.groundUnits.byTransport[transportId]:
      let unitOpt = state.groundUnits.entities.entity(unitId)
      if unitOpt.isSome:
        result.add(unitOpt.get())

# ============================================================================
# ============================================================================
# Production Accessors (byColony: 1:many)
# ============================================================================

proc constructionProjectsAtColony*(
    state: GameState, colonyId: ColonyId
): seq[ConstructionProject] =
  ## Get all construction projects at a colony (1:many relationship)
  ## Returns: seq of construction projects (empty if no active projects)
  ##
  ## Note: byFacility index (composite key) intentionally not wrapped - keep verbose pattern
  ##
  ## Example:
  ##   let projects = state.constructionProjectsAtColony(colonyId)
  ##   let queuedProduction = projects.mapIt(it.ppRemaining).sum()
  result = @[]
  if state.constructionProjects.byColony.hasKey(colonyId):
    for projectId in state.constructionProjects.byColony[colonyId]:
      let projectOpt = state.constructionProjects.entities.entity(projectId)
      if projectOpt.isSome:
        result.add(projectOpt.get())

proc repairProjectsAtColony*(
    state: GameState, colonyId: ColonyId
): seq[RepairProject] =
  ## Get all repair projects at a colony (1:many relationship)
  ## Returns: seq of repair projects (empty if no active repairs)
  ##
  ## Note: byFacility index (composite key) intentionally not wrapped - keep verbose pattern
  ##
  ## Example:
  ##   let repairs = state.repairProjectsAtColony(colonyId)
  ##   let shipsBeingRepaired = repairs.len
  result = @[]
  if state.repairProjects.byColony.hasKey(colonyId):
    for projectId in state.repairProjects.byColony[colonyId]:
      let projectOpt = state.repairProjects.entities.entity(projectId)
      if projectOpt.isSome:
        result.add(projectOpt.get())
