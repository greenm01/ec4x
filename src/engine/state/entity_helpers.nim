## Entity Index Accessor Helpers
##
## Provides convenient 1-line accessors for index-based entity lookups.
## Reduces verbose 3-line pattern:
##   if state.collection.index.hasKey(key):
##     let id = state.collection.index[key]
##     let opt = state.collection.entities.entity(id)
##
## To concise 1-line call:
##   let opt = state.entityByIndex(key)
##
## Design Notes:
## - Only adds helpers where iterators don't already exist
## - Returns Option[T] for 1:1 indexes (colonyBySystem)
## - Returns seq[T] for 1:many indexes (squadronsByFleet, etc.)
## - Architecture-compliant: Follows DoD patterns from architecture.md

import std/[options, tables]
import
  ../types/[
    game_state, colony, squadron, ship, ground_unit, facilities, production, core,
  ]

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
  if state.squadrons[].byFleet.hasKey(fleetId):
    for squadronId in state.squadrons[].byFleet[fleetId]:
      let squadronOpt = state.squadrons[].entities.entity(squadronId)
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
# Facility Accessors (all byColony: 1:many)
# ============================================================================

proc starbasesAtColony*(state: GameState, colonyId: ColonyId): seq[Starbase] =
  ## Get all starbases at a colony (1:many relationship)
  ## Returns: seq of starbases (empty if colony has no starbases)
  ##
  ## Example:
  ##   let starbases = state.starbasesAtColony(colonyId)
  ##   let hasDefense = starbases.len > 0
  result = @[]
  if state.starbases.byColony.hasKey(colonyId):
    for starbaseId in state.starbases.byColony[colonyId]:
      let starbaseOpt = state.starbases.entities.entity(starbaseId)
      if starbaseOpt.isSome:
        result.add(starbaseOpt.get())

proc spaceportsAtColony*(state: GameState, colonyId: ColonyId): seq[Spaceport] =
  ## Get all spaceports at a colony (1:many relationship)
  ## Returns: seq of spaceports (empty if colony has no spaceports)
  ##
  ## Example:
  ##   let spaceports = state.spaceportsAtColony(colonyId)
  ##   let canLaunchFleets = spaceports.len > 0
  result = @[]
  if state.spaceports.byColony.hasKey(colonyId):
    for spaceportId in state.spaceports.byColony[colonyId]:
      let spaceportOpt = state.spaceports.entities.entity(spaceportId)
      if spaceportOpt.isSome:
        result.add(spaceportOpt.get())

proc shipyardsAtColony*(state: GameState, colonyId: ColonyId): seq[Shipyard] =
  ## Get all shipyards at a colony (1:many relationship)
  ## Returns: seq of shipyards (empty if colony has no shipyards)
  ##
  ## Example:
  ##   let shipyards = state.shipyardsAtColony(colonyId)
  ##   let totalBuildCapacity = shipyards.mapIt(it.buildCapacity).sum()
  result = @[]
  if state.shipyards.byColony.hasKey(colonyId):
    for shipyardId in state.shipyards.byColony[colonyId]:
      let shipyardOpt = state.shipyards.entities.entity(shipyardId)
      if shipyardOpt.isSome:
        result.add(shipyardOpt.get())

proc drydocksAtColony*(state: GameState, colonyId: ColonyId): seq[Drydock] =
  ## Get all drydocks at a colony (1:many relationship)
  ## Returns: seq of drydocks (empty if colony has no drydocks)
  ##
  ## Example:
  ##   let drydocks = state.drydocksAtColony(colonyId)
  ##   let canRepair = drydocks.len > 0
  result = @[]
  if state.drydocks.byColony.hasKey(colonyId):
    for drydockId in state.drydocks.byColony[colonyId]:
      let drydockOpt = state.drydocks.entities.entity(drydockId)
      if drydockOpt.isSome:
        result.add(drydockOpt.get())

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
