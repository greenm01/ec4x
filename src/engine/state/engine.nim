import std/[tables, options]
import
  ../types/[
    core, game_state, fleet, ship, ground_unit, house, colony, facilities,
    production, intel, starmap, population, combat,
  ]

export GameState

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
# Entity Existence Checks
# ============================================================================

proc hasSystem*(state: GameState, id: SystemId): bool {.inline.} =
  ## Check if a system with the given ID exists
  state.systems.entities.index.contains(id)

proc hasColony*(state: GameState, id: ColonyId): bool {.inline.} =
  ## Check if a colony with the given ID exists
  state.colonies.entities.index.contains(id)

proc hasFleet*(state: GameState, id: FleetId): bool {.inline.} =
  ## Check if a fleet with the given ID exists
  state.fleets.entities.index.contains(id)

proc hasShip*(state: GameState, id: ShipId): bool {.inline.} =
  ## Check if a ship with the given ID exists
  state.ships.entities.index.contains(id)

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

proc colonyIdBySystem*(state: GameState, systemId: SystemId): Option[ColonyId] =
  ## Look up colony ID at system (1:1 relationship)
  ## Returns: Some(colonyId) if exists, None if system uncolonized
  ##
  ## Use when you only need the ColonyId, not the full Colony object.
  ## NEVER use ColonyId(systemId) cast - that bypasses proper lookup!
  ##
  ## Example:
  ##   let colonyIdOpt = state.colonyIdBySystem(systemId)
  ##   if colonyIdOpt.isSome:
  ##     let colonyId = colonyIdOpt.get()
  if state.colonies.bySystem.hasKey(systemId):
    return some(state.colonies.bySystem[systemId])
  return none(ColonyId)

# ============================================================================
# Ship Accessors (byFleet: 1:many)
# ============================================================================

proc shipsByFleet*(state: GameState, fleetId: FleetId): seq[Ship] =
  ## Get all ships in a fleet (1:many relationship)
  ## Returns: seq of ships (empty if fleet has no ships)
  ##
  ## Note: For batch processing all ships owned by house, use iterator shipsOwned()
  ## Use this helper when you need ships for a specific fleet
  ##
  ## Example:
  ##   let ships = state.shipsByFleet(fleetId)
  ##   let totalAS = ships.mapIt(it.stats.attackStrength).sum()
  result = @[]
  if state.ships.byFleet.hasKey(fleetId):
    for shipId in state.ships.byFleet[fleetId]:
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
# Facility Accessors (byColony: 1:many)
# ============================================================================

proc neoriasAtColony*(state: GameState, colonyId: ColonyId): seq[Neoria] =
  ## Get all production facilities (Neorias) at a colony (1:many relationship)
  ## Returns: seq of Neoria (Spaceports, Shipyards, Drydocks)
  ##
  ## Note: For counting specific facility types, use count*AtColony() procs
  ##
  ## Example:
  ##   let facilities = state.neoriasAtColony(colonyId)
  ##   let totalDocks = facilities.mapIt(it.effectiveDocks).sum()
  result = @[]
  if state.neorias.byColony.hasKey(colonyId):
    for neoriaId in state.neorias.byColony[colonyId]:
      let neoriaOpt = state.neorias.entities.entity(neoriaId)
      if neoriaOpt.isSome:
        result.add(neoriaOpt.get())

proc kastrasAtColony*(state: GameState, colonyId: ColonyId): seq[Kastra] =
  ## Get all defensive facilities (Kastras) at a colony (1:many relationship)
  ## Returns: seq of Kastra (Starbases)
  ##
  ## Example:
  ##   let defenses = state.kastrasAtColony(colonyId)
  ##   let totalDefense = defenses.mapIt(it.stats.defenseStrength).sum()
  result = @[]
  if state.kastras.byColony.hasKey(colonyId):
    for kastraId in state.kastras.byColony[colonyId]:
      let kastraOpt = state.kastras.entities.entity(kastraId)
      if kastraOpt.isSome:
        result.add(kastraOpt.get())

proc countSpaceportsAtColony*(state: GameState, colonyId: ColonyId): int32 =
  ## Count Spaceports at a colony
  ## Returns: number of Spaceport facilities (includes crippled)
  result = 0
  for neoria in state.neoriasAtColony(colonyId):
    if neoria.neoriaClass == NeoriaClass.Spaceport:
      result += 1

proc countShipyardsAtColony*(state: GameState, colonyId: ColonyId): int32 =
  ## Count Shipyards at a colony
  ## Returns: number of Shipyard facilities (includes crippled)
  result = 0
  for neoria in state.neoriasAtColony(colonyId):
    if neoria.neoriaClass == NeoriaClass.Shipyard:
      result += 1

proc countDrydocksAtColony*(state: GameState, colonyId: ColonyId): int32 =
  ## Count Drydocks at a colony
  ## Returns: number of Drydock facilities (includes crippled)
  result = 0
  for neoria in state.neoriasAtColony(colonyId):
    if neoria.neoriaClass == NeoriaClass.Drydock:
      result += 1

proc countStarbasesAtColony*(state: GameState, colonyId: ColonyId): int32 =
  ## Count Starbases at a colony
  ## Returns: number of Starbase facilities (includes crippled)
  result = 0
  for kastra in state.kastrasAtColony(colonyId):
    if kastra.kastraClass == KastraClass.Starbase:
      result += 1

proc countOperationalNeoriasAtColony*(state: GameState, colonyId: ColonyId): int32 =
  ## Count operational (non-crippled) production facilities at a colony
  ## Returns: number of Neorias in Undamaged state
  result = 0
  for neoria in state.neoriasAtColony(colonyId):
    if neoria.state != CombatState.Crippled:
      result += 1

proc countOperationalKastrasAtColony*(state: GameState, colonyId: ColonyId): int32 =
  ## Count operational (non-crippled) defensive facilities at a colony
  ## Returns: number of Kastras in Undamaged state
  result = 0
  for kastra in state.kastrasAtColony(colonyId):
    if kastra.state != CombatState.Crippled:
      result += 1

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
