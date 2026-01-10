## Post-Combat Cleanup System
##
## Removes destroyed entities from game state after combat resolution.
## Clears construction/repair queues from destroyed facilities.
##
## Called after each combat resolution to maintain state consistency.

import std/options
import ../../../common/logger
import ../../types/[core, game_state, combat, ship, fleet, facilities, ground_unit, colony, event]
import ../../state/[engine, iterators]
import ../../entities/[ship_ops, fleet_ops, neoria_ops, ground_unit_ops, kastra_ops]
import ../../entities/project_ops
import ../../event_factory/init as event_factory

proc cleanupDestroyedShips*(state: var GameState, systemId: SystemId) =
  ## Remove all ships with CombatState.Destroyed from fleets in this system
  ## Called after combat resolution
  ##
  ## **Optimization:** Only checks ships in fleets at this system (not global scan)

  var destroyedShips: seq[ShipId] = @[]

  # Collect destroyed ships from fleets in this system only
  for fleet in state.fleetsInSystem(systemId):
    for (shipId, ship) in state.shipsInFleetWithId(fleet.id):
      if ship.state == CombatState.Destroyed:
        destroyedShips.add(shipId)

  # Destroy collected ships (mutation)
  for shipId in destroyedShips:
    logCombat("[CLEANUP] Destroying ship ", $shipId)
    ship_ops.destroyShip(state, shipId)

proc cleanupEmptyFleets*(state: var GameState, systemId: SystemId) =
  ## Remove fleets with no ships remaining at this system
  ## Called after ship cleanup
  ##
  ## **Optimization:** Only checks fleets at this system (not global scan)

  var emptyFleets: seq[FleetId] = @[]

  # Collect empty fleets at this system only
  for fleet in state.fleetsInSystem(systemId):
    if fleet.ships.len == 0:
      emptyFleets.add(fleet.id)

  # Destroy empty fleets (mutation)
  for fleetId in emptyFleets:
    logCombat("[CLEANUP] Destroying empty fleet ", $fleetId)
    fleet_ops.destroyFleet(state, fleetId)

proc cleanupCrippledNeorias*(state: var GameState, systemId: SystemId) =
  ## Clear construction/repair queues from crippled neorias
  ## Per spec: Crippled facilities lose all queued projects (not paused)
  ## Called after combat resolution
  ##
  ## **Optimization:** Only checks neorias at colonies in this system (not global scan)

  # Check if there's a colony in this system
  let colonyOpt = state.colonyBySystem(systemId)
  if colonyOpt.isNone:
    return # No colony = no neorias to clean

  let colonyId = colonyOpt.get().id

  # Process crippled neorias at this colony
  for neoria in state.neoriasAtColony(colonyId):
    if neoria.state == CombatState.Crippled:
      var neoriaToUpdate = neoria

      logCombat(
        "[CLEANUP] Clearing queues from crippled neoria ",
        $neoria.id,
        " (had ",
        $neoria.constructionQueue.len,
        " queued constructions, ",
        $neoria.activeConstructions.len,
        " active constructions, ",
        $neoria.repairQueue.len,
        " queued repairs, ",
        $neoria.activeRepairs.len,
        " active repairs)",
      )

      # Complete/cancel all active construction projects
      for projectId in neoriaToUpdate.activeConstructions:
        if state.constructionProject(projectId).isSome:
          project_ops.completeConstructionProject(state, projectId)

      # Complete/cancel all queued construction projects
      for projectId in neoriaToUpdate.constructionQueue:
        if state.constructionProject(projectId).isSome:
          project_ops.completeConstructionProject(state, projectId)

      # Complete/cancel all active repair projects
      for projectId in neoriaToUpdate.activeRepairs:
        if state.repairProject(projectId).isSome:
          project_ops.completeRepairProject(state, projectId)

      # Complete/cancel all queued repair projects
      for projectId in neoriaToUpdate.repairQueue:
        if state.repairProject(projectId).isSome:
          project_ops.completeRepairProject(state, projectId)

      # Clear the queues from neoria
      neoriaToUpdate.activeConstructions = @[]
      neoriaToUpdate.constructionQueue = @[]
      neoriaToUpdate.activeRepairs = @[]
      neoriaToUpdate.repairQueue = @[]
      state.updateNeoria(neoria.id, neoriaToUpdate)

proc cleanupDestroyedNeorias*(state: var GameState, systemId: SystemId) =
  ## Remove destroyed neorias and clear their construction/repair queues
  ## Called after combat resolution
  ##
  ## **Optimization:** Only checks neorias at colonies in this system (not global scan)

  var destroyedNeorias: seq[NeoriaId] = @[]

  # Check if there's a colony in this system
  let colonyOpt = state.colonyBySystem(systemId)
  if colonyOpt.isNone:
    return # No colony = no neorias to clean

  let colonyId = colonyOpt.get().id

  # Collect destroyed neorias at this colony only
  for neoria in state.neoriasAtColony(colonyId):
    if neoria.state == CombatState.Destroyed:
      destroyedNeorias.add(neoria.id)

  # Clear queues and destroy facilities (mutation)
  for neoriaId in destroyedNeorias:
    let neoriaOpt = state.neoria(neoriaId)
    if neoriaOpt.isNone:
      continue

    var neoria = neoriaOpt.get()

    logCombat(
      "[CLEANUP] Destroying neoria ",
      $neoriaId,
      " (had ",
      $neoria.constructionQueue.len,
      " queued constructions, ",
      $neoria.activeConstructions.len,
      " active constructions, ",
      $neoria.repairQueue.len,
      " queued repairs, ",
      $neoria.activeRepairs.len,
      " active repairs)",
    )

    # Complete/cancel all active construction projects
    for projectId in neoria.activeConstructions:
      if state.constructionProject(projectId).isSome:
        project_ops.completeConstructionProject(state, projectId)

    # Complete/cancel all queued construction projects
    for projectId in neoria.constructionQueue:
      if state.constructionProject(projectId).isSome:
        project_ops.completeConstructionProject(state, projectId)

    # Complete/cancel all active repair projects
    for projectId in neoria.activeRepairs:
      if state.repairProject(projectId).isSome:
        project_ops.completeRepairProject(state, projectId)

    # Complete/cancel all queued repair projects
    for projectId in neoria.repairQueue:
      if state.repairProject(projectId).isSome:
        project_ops.completeRepairProject(state, projectId)

    # Note: complete*Project functions already clear queues from neoria
    # Finally, destroy the facility (will remove from all indexes)
    neoria_ops.destroyNeoria(state, neoriaId)

proc cleanupDestroyedGroundUnits*(state: var GameState, systemId: SystemId) =
  ## Remove all ground units with CombatState.Destroyed at colonies in this system
  ## Called after combat resolution
  ##
  ## **Optimization:** Only checks ground units at colonies in this system (not global scan)

  var destroyedUnits: seq[GroundUnitId] = @[]

  # Check if there's a colony in this system
  let colonyOpt = state.colonyBySystem(systemId)
  if colonyOpt.isNone:
    return # No colony = no ground units to clean

  let colonyId = colonyOpt.get().id

  # Collect destroyed ground units at this colony only
  for unit in state.groundUnitsAtColony(colonyId):
    if unit.state == CombatState.Destroyed:
      destroyedUnits.add(unit.id)

  # Destroy collected units (mutation)
  for unitId in destroyedUnits:
    logCombat("[CLEANUP] Destroying ground unit ", $unitId)
    ground_unit_ops.destroyGroundUnit(state, unitId)

proc cleanupDestroyedKastras*(state: var GameState, systemId: SystemId) =
  ## Remove destroyed starbases at colonies in this system
  ## Called after combat resolution
  ##
  ## **Optimization:** Only checks kastras at colonies in this system (not global scan)

  var destroyedKastras: seq[KastraId] = @[]

  # Check if there's a colony in this system
  let colonyOpt = state.colonyBySystem(systemId)
  if colonyOpt.isNone:
    return # No colony = no kastras to clean

  let colonyId = colonyOpt.get().id

  # Collect destroyed kastras at this colony only
  for kastra in state.kastrasAtColony(colonyId):
    if kastra.state == CombatState.Destroyed:
      destroyedKastras.add(kastra.id)

  # Destroy starbases (mutation)
  # Note: Starbases don't have construction queues, so just remove them
  for kastraId in destroyedKastras:
    logCombat("[CLEANUP] Destroying starbase ", $kastraId)
    kastra_ops.destroyKastra(state, kastraId)

proc clearColonyConstructionQueue*(
  state: var GameState, colonyId: ColonyId, generateEvent: bool, events: var seq[GameEvent]
) =
  ## Clear all construction and repair projects from colony queue
  ## Used during bombardment (with event) or invasion (without event)
  ##
  ## **When to call:**
  ## - Bombardment: generateEvent = true (projects lost to damage)
  ## - Invasion/Conquest: generateEvent = false (projects inherited by conqueror)

  let colonyOpt = state.colony(colonyId)
  if colonyOpt.isNone:
    return

  var colony = colonyOpt.get()
  let originalOwner = colony.owner

  # Track project counts for event generation
  var lostConstructionCount = 0
  var lostRepairCount = 0

  # Complete/cancel active construction project
  if colony.underConstruction.isSome:
    let projectId = colony.underConstruction.get()
    if state.constructionProject(projectId).isSome:
      project_ops.completeConstructionProject(state, projectId)
      lostConstructionCount += 1

  # Complete/cancel all queued construction projects
  for projectId in colony.constructionQueue:
    if state.constructionProject(projectId).isSome:
      project_ops.completeConstructionProject(state, projectId)
      lostConstructionCount += 1

  # Complete/cancel all queued repair projects
  for projectId in colony.repairQueue:
    if state.repairProject(projectId).isSome:
      project_ops.completeRepairProject(state, projectId)
      lostRepairCount += 1

  # Clear queue references from colony
  colony.underConstruction = none(ConstructionProjectId)
  colony.constructionQueue = @[]
  colony.repairQueue = @[]
  state.updateColony(colonyId, colony)

  logCombat(
    "[CLEANUP] Cleared colony construction queue ",
    $colonyId,
    " (",
    $lostConstructionCount,
    " construction, ",
    $lostRepairCount,
    " repair)",
  )

  # Generate event if requested (bombardment case)
  if generateEvent and (lostConstructionCount > 0 or lostRepairCount > 0):
    events.add(
      event_factory.colonyProjectsLost(
        houseId = originalOwner,
        systemId = colony.systemId,
        constructionCount = lostConstructionCount,
        repairCount = lostRepairCount,
      )
    )

proc clearColonyConstructionOnConquest*(
  state: var GameState, colonyId: ColonyId, newOwner: HouseId
) =
  ## Clear colony construction queue when colony is conquered
  ## No event generated - conqueror inherits the colony without projects
  ##
  ## Called from planetary.nim after successful invasion

  var dummyEvents: seq[GameEvent] = @[]
  clearColonyConstructionQueue(state, colonyId, generateEvent = false, dummyEvents)

proc clearColonyConstructionOnBombardment*(
  state: var GameState, colonyId: ColonyId, events: var seq[GameEvent]
) =
  ## Clear colony construction queue when bombardment damages infrastructure
  ## Generates event indicating projects were lost
  ##
  ## Called from planetary.nim after bombardment hits

  clearColonyConstructionQueue(state, colonyId, generateEvent = true, events)

proc cleanupPostCombat*(state: var GameState, systemId: SystemId) =
  ## Master cleanup function - call after combat resolution in a system
  ## Handles all destroyed entities and queue cleanup
  ##
  ## **Order matters:**
  ## 1. Clean ships first (updates fleet.ships lists)
  ## 2. Clean empty fleets (now that ships are gone)
  ## 3. Clear queues from crippled facilities (per spec: CON2c)
  ## 4. Clean destroyed facilities (neorias, kastras) and their queues
  ## 5. Clean ground units

  logCombat("[CLEANUP] Post-combat cleanup starting for system ", $systemId)

  # Phase 1: Ships (only in fleets at this system)
  cleanupDestroyedShips(state, systemId)

  # Phase 2: Empty fleets (only at this system, after ships removed)
  cleanupEmptyFleets(state, systemId)

  # Phase 3: Crippled facilities (clear queues per spec)
  cleanupCrippledNeorias(state, systemId)

  # Phase 4: Destroyed facilities (only at colonies in this system, with queue clearing)
  cleanupDestroyedNeorias(state, systemId)
  cleanupDestroyedKastras(state, systemId)

  # Phase 5: Ground units (only at colonies in this system)
  cleanupDestroyedGroundUnits(state, systemId)

  logCombat("[CLEANUP] Post-combat cleanup complete for system ", $systemId)

## Design Notes:
##
## **Why separate from combat resolution:**
## - CombatState.Destroyed needed for after-action reports and telemetry
## - Stats collection needs to see what was destroyed
## - Event generation needs entity data
## - Cleanup happens after all reporting complete
##
## **Queue Clearing:**
## - Destroyed neorias lose all construction/repair projects
## - Projects are cancelled (refunds PP if applicable)
## - Empty queues prevent dangling references
##
## **Order Dependencies:**
## - Ships must be cleaned before fleets (fleet.ships updates)
## - Fleets checked after ships removed (empty fleet detection)
## - Facilities can be cleaned in any order
## - Ground units can be cleaned in any order
##
## **Performance:**
## - System-scoped iteration (only checks entities in combat system)
## - Ships: O(ships_in_fleets_at_system) instead of O(all_ships_in_game)
## - Fleets: O(fleets_at_system) instead of O(all_fleets_in_game)
## - Facilities: O(facilities_at_colony) instead of O(all_facilities_in_game)
## - Ground units: O(units_at_colony) instead of O(all_units_in_game)
## - Collects IDs first, then mutates (no iterator invalidation)
## - Major performance win in late-game with many systems
##
## **Future Enhancements:**
## - Batch cleanup for multiple systems (if needed)
## - Telemetry integration (track cleanup stats)
