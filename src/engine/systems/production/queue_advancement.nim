## Per-Facility Queue Management System
##
## Manages construction and repair queues at individual facilities.
##
## **Architecture:**
## - Uses state layer APIs to read entities (state.constructionProject, state.neoria)
## - Directly mutates state for project updates (no entity_ops yet)
## - Follows three-layer pattern: State → Business Logic → Mutations
##
## **Facility Specialization:**
## - Spaceport: Construction only (5 docks) - ground-based launch facility
## - Shipyard: Construction only (10 docks) - orbital ship construction
## - Drydock: Repair only (10 docks) - orbital ship repair facility
##
## **FIFO Queue Model:**
## Each facility independently advances its own queues in command queued.
##
## **Facility Queue Structure:**
## - Spaceport: constructionQueue → activeConstructions (up to 5 docks)
## - Shipyard: constructionQueue → activeConstructions (up to 10 docks)
## - Drydock: repairQueue → activeRepairs (up to 10 docks)
##
## **Queue Advancement:**
## 1. Advance all active projects (decrement turnsRemaining)
## 2. Complete finished projects
## 3. Pull new projects from queues (FIFO) to fill available docks
##
## **Spaceport Construction Penalty:**
## Ships built at spaceports cost 2x PP (applied at command submission time)
## Exception: Shipyard/Starbase buildings (orbital construction, no penalty)

import std/[options, sequtils]
import ../../types/[core, production, facilities, colony, combat, game_state, ship]
import ../../state/[engine, iterators]
import ../../entities/project_ops
import ../../../common/logger

export production.CompletedProject

proc projectDesc*(p: ConstructionProject): string =
  ## Format project description from typed fields for logging
  if p.shipClass.isSome: return $p.shipClass.get()
  if p.facilityClass.isSome: return $p.facilityClass.get()
  if p.groundClass.isSome: return $p.groundClass.get()
  if p.industrialUnits > 0: return $p.industrialUnits & " IU"
  return "unknown"

type QueueAdvancementResult* = object ## Results from advancing a facility's queues
  completedProjects*: seq[production.CompletedProject]
  completedRepairs*: seq[production.RepairProject]

proc advanceSpaceportQueue*(
    state: GameState, spaceport: var Neoria, colonyId: ColonyId
): QueueAdvancementResult =
  ## Advance spaceport construction queue (FIFO)
  ## Uses state layer APIs to access construction projects by ID
  result = QueueAdvancementResult(completedProjects: @[], completedRepairs: @[])

  # Step 1: Advance all active construction projects
  var completedIds: seq[ConstructionProjectId] = @[]
  for projectId in spaceport.activeConstructions:
    let projectOpt = state.constructionProject(projectId)
    if projectOpt.isNone:
      continue # Project not found, skip

    var project = projectOpt.get()
    project.turnsRemaining -= 1

    if project.turnsRemaining <= 0:
      # Construction complete
      result.completedProjects.add(
        production.CompletedProject(
          colonyId: colonyId,
          projectType: project.projectType,
          shipClass: project.shipClass,
          facilityClass: project.facilityClass,
          groundClass: project.groundClass,
          industrialUnits: project.industrialUnits,
          neoriaId: some(spaceport.id),  # Track facility for vulnerability checking
        )
      )
      completedIds.add(projectId)
      logDebug("Facilities", "Spaceport construction complete: ",
               $spaceport.id, " project=", project.projectDesc)
      # Use entity ops for proper cleanup
      state.completeConstructionProject(projectId)
    else:
      # Still in progress - write back to entity manager
      state.updateConstructionProject(projectId, project)

  # Remove completed project IDs from active list
  spaceport.activeConstructions = spaceport.activeConstructions.filterIt(it notin completedIds)

  # Step 2: Pull new projects from queue to fill available docks
  let availableDocks = spaceport.effectiveDocks - spaceport.activeConstructions.len

  var pulled = 0
  while pulled < availableDocks and spaceport.constructionQueue.len > 0:
    let nextProjectId = spaceport.constructionQueue[0]
    spaceport.constructionQueue.delete(0)

    let projectOpt = state.constructionProject(nextProjectId)
    if projectOpt.isNone:
      continue # Project not found, skip

    var nextProject = projectOpt.get()

    # CRITICAL: Decrement turnsRemaining immediately when starting
    # This ensures "1 turn" projects complete in the same turn cycle
    nextProject.turnsRemaining -= 1

    if nextProject.turnsRemaining <= 0:
      # Project completes immediately (1-turn projects)
      result.completedProjects.add(
        production.CompletedProject(
          colonyId: colonyId,
          projectType: nextProject.projectType,
          shipClass: nextProject.shipClass,
          facilityClass: nextProject.facilityClass,
          groundClass: nextProject.groundClass,
          industrialUnits: nextProject.industrialUnits,
          neoriaId: some(spaceport.id),  # Track facility for vulnerability checking
        )
      )
      logDebug("Facilities", "Spaceport construction complete (instant): ",
               $spaceport.id, " project=", nextProject.projectDesc)
      # Use entity ops for proper cleanup
      state.completeConstructionProject(nextProjectId)
      # Don't add to activeConstructions - dock remains free
      pulled += 1
    else:
      # Project still needs more turns - write to entity manager and activate
      state.updateConstructionProject(nextProjectId, nextProject)
      spaceport.activeConstructions.add(nextProjectId)
      logDebug("Facilities", "Spaceport started new construction: ",
               $spaceport.id, " project=", nextProject.projectDesc)
      pulled += 1

proc advanceDrydockQueue*(
    state: GameState, drydock: var Neoria, colonyId: ColonyId
): QueueAdvancementResult =
  ## Advance drydock repair queue (repair-only facility)
  ## Uses state layer APIs to access repair projects by ID
  result = QueueAdvancementResult(completedProjects: @[], completedRepairs: @[])

  # Crippled drydocks can't work
  if drydock.state == CombatState.Crippled:
    return

  # Step 1: Advance active repairs
  var completedRepairIds: seq[RepairProjectId] = @[]
  for repairId in drydock.activeRepairs:
    let repairOpt = state.repairProject(repairId)
    if repairOpt.isNone:
      continue # Repair not found, skip

    var repair = repairOpt.get()
    repair.turnsRemaining -= 1

    if repair.turnsRemaining <= 0:
      # Repair complete
      result.completedRepairs.add(repair)
      completedRepairIds.add(repairId)
      logDebug("Facilities", "Drydock repair complete: ", $drydock.id, " target=", $repair.targetType)
      # Use entity ops for proper cleanup
      state.completeRepairProject(repairId)
    else:
      # Still in progress - write back to entity manager
      state.updateRepairProject(repairId, repair)

  # Remove completed repair IDs from active list
  drydock.activeRepairs = drydock.activeRepairs.filterIt(it notin completedRepairIds)

  # Step 2: Pull new repairs from queue to fill available docks
  let availableDocks = drydock.effectiveDocks - drydock.activeRepairs.len

  var pulled = 0
  while pulled < availableDocks and drydock.repairQueue.len > 0:
    let nextRepairId = drydock.repairQueue[0]
    drydock.repairQueue.delete(0)

    let repairOpt = state.repairProject(nextRepairId)
    if repairOpt.isNone:
      continue # Repair not found, skip

    # Add to active repairs
    drydock.activeRepairs.add(nextRepairId)
    let repair = repairOpt.get()
    logDebug("Facilities", "Drydock started new repair: ", $drydock.id, " target=", $repair.targetType)
    pulled += 1

proc advanceShipyardQueue*(
    state: GameState, shipyard: var Neoria, colonyId: ColonyId
): QueueAdvancementResult =
  ## Advance shipyard construction queue (construction-only facility)
  ## Uses state layer APIs to access construction projects by ID
  result = QueueAdvancementResult(completedProjects: @[], completedRepairs: @[])

  # Crippled shipyards can't work
  if shipyard.state == CombatState.Crippled:
    return

  # Step 1: Advance all active construction projects
  var completedIds: seq[ConstructionProjectId] = @[]
  for projectId in shipyard.activeConstructions:
    let projectOpt = state.constructionProject(projectId)
    if projectOpt.isNone:
      continue # Project not found, skip

    var project = projectOpt.get()
    project.turnsRemaining -= 1

    if project.turnsRemaining <= 0:
      # Construction complete
      result.completedProjects.add(
        production.CompletedProject(
          colonyId: colonyId,
          projectType: project.projectType,
          shipClass: project.shipClass,
          facilityClass: project.facilityClass,
          groundClass: project.groundClass,
          industrialUnits: project.industrialUnits,
        )
      )
      completedIds.add(projectId)
      logDebug("Facilities", "Shipyard construction complete: ",
               $shipyard.id, " project=", project.projectDesc)
      # Use entity ops for proper cleanup
      state.completeConstructionProject(projectId)
    else:
      # Still in progress - write back to entity manager
      state.updateConstructionProject(projectId, project)

  # Remove completed project IDs from active list
  shipyard.activeConstructions = shipyard.activeConstructions.filterIt(it notin completedIds)

  # Step 2: Pull new projects from queue to fill available docks
  let availableDocks = shipyard.effectiveDocks - shipyard.activeConstructions.len

  var pulled = 0
  while pulled < availableDocks and shipyard.constructionQueue.len > 0:
    let nextProjectId = shipyard.constructionQueue[0]
    shipyard.constructionQueue.delete(0)

    let projectOpt = state.constructionProject(nextProjectId)
    if projectOpt.isNone:
      continue # Project not found, skip

    var nextProject = projectOpt.get()

    # CRITICAL: Decrement turnsRemaining immediately when starting
    # This ensures "1 turn" projects complete in the same turn cycle
    nextProject.turnsRemaining -= 1

    if nextProject.turnsRemaining <= 0:
      # Project completes immediately (1-turn projects)
      result.completedProjects.add(
        production.CompletedProject(
          colonyId: colonyId,
          projectType: nextProject.projectType,
          shipClass: nextProject.shipClass,
          facilityClass: nextProject.facilityClass,
          groundClass: nextProject.groundClass,
          industrialUnits: nextProject.industrialUnits,
          neoriaId: some(shipyard.id),  # Track facility for vulnerability checking
        )
      )
      logDebug("Facilities", "Shipyard construction complete (instant): ",
               $shipyard.id, " project=", nextProject.projectDesc)
      # Use entity ops for proper cleanup
      state.completeConstructionProject(nextProjectId)
      # Don't add to activeConstructions - dock remains free
      pulled += 1
    else:
      # Project still needs more turns - write to entity manager and activate
      state.updateConstructionProject(nextProjectId, nextProject)
      shipyard.activeConstructions.add(nextProjectId)
      logDebug("Facilities", "Shipyard started new construction: ",
               $shipyard.id, " project=", nextProject.projectDesc)
      pulled += 1

proc isPlanetaryDefense*(project: production.CompletedProject): bool =
  ## Returns true if project should commission in Maintenance Phase
  ## Planetary assets: Facilities, ground forces, fighters (planetside)
  ## Military assets: Ships built in docks (Command Phase after combat)

  # Facilities (Starbase, Spaceport, Shipyard, Drydock) commission planetside
  if project.facilityClass.isSome:
    return true

  # Ground units are planetside, commission with planetary defense
  if project.groundClass.isSome:
    return true

  # Fighters are planetside, commission with planetary defense
  if project.shipClass == some(ShipClass.Fighter):
    return true

  # Industrial projects commission planetside
  if project.projectType in {BuildType.Industrial, BuildType.Infrastructure}:
    return false

  return false

## ==============================================================================
## Colony Queue Management (Legacy System)
## ==============================================================================
##
## These functions manage the legacy colony-side construction queue used for:
## - Fighters (planet-side production)
## - Ground units
## - Buildings
## - Industrial Unit (IU) investment
##
## Capital ships (non-fighters) use the facility queue system above.
##
## NOW REFACTORED to use entity managers properly.

proc startConstruction*(
    state: GameState, colony: var Colony, project: ConstructionProject
): bool =
  ## Start new construction project at colony using entity managers
  ## Returns true if started successfully
  ##
  ## NOTE: This function manages the legacy colony construction queue.
  ## Used for fighters, buildings, and IU investment (planet-side construction).
  ## Capital ships use the facility queue system (construction_docks.nim).

  # Add project to entity manager (generates ID)
  var mutableProject = project
  let finalProject = state.queueConstructionProject(colony.id, mutableProject)

  # Set underConstruction for first project if slot is empty
  if colony.underConstruction.isNone:
    colony.underConstruction = some(finalProject.id)
    # Remove from queue since it's now active
    if colony.constructionQueue.len > 0 and colony.constructionQueue[0] == finalProject.id:
      colony.constructionQueue.delete(0)

  # Always return true - actual capacity checking happens in resolution layer
  return true

proc advanceConstruction*(
    state: GameState, colony: var Colony
): Option[production.CompletedProject] =
  ## Advance colony construction by one turn using entity managers
  ## Returns completed project if finished
  ## Per economy.md:5.0 - full cost paid upfront, construction tracks turns

  if colony.underConstruction.isNone:
    return none(production.CompletedProject)

  let projectId = colony.underConstruction.get()
  let projectOpt = state.constructionProject(projectId)
  if projectOpt.isNone:
    # Project not found - clear slot
    colony.underConstruction = none(ConstructionProjectId)
    return none(production.CompletedProject)

  var project = projectOpt.get()

  # Decrement turns remaining
  project.turnsRemaining -= 1

  # Check if complete
  if project.turnsRemaining <= 0:
    let completed = production.CompletedProject(
      colonyId: colony.id,
      projectType: project.projectType,
      shipClass: project.shipClass,
      facilityClass: project.facilityClass,
      groundClass: project.groundClass,
      industrialUnits: project.industrialUnits,
      neoriaId: none(NeoriaId),  # Colony-level construction (no specific facility)
    )

    # Clear construction slot
    colony.underConstruction = none(ConstructionProjectId)

    # Use entity ops for proper cleanup
    state.completeConstructionProject(projectId)

    # Pull next project from queue if available
    if colony.constructionQueue.len > 0:
      let nextId = colony.constructionQueue[0]
      colony.constructionQueue.delete(0)
      colony.underConstruction = some(nextId)

    return some(completed)

  # Update progress in entity manager
  state.updateConstructionProject(projectId, project)

  return none(production.CompletedProject)

proc advanceColonyQueues*(
    state: GameState, colonyId: ColonyId
): QueueAdvancementResult =
  ## Advance all construction queues at a colony (colony-level + facility-level)
  ## Returns combined results from colony queue and all facilities
  result = QueueAdvancementResult(completedProjects: @[], completedRepairs: @[])

  # Get colony to access facility IDs
  let colonyOpt = state.colony(colonyId)
  if colonyOpt.isNone:
    return result

  var colony = colonyOpt.get()

  # Advance colony-level construction queue (facilities, fighters,
  # ground units, IU investment — planet-side builds)
  let colonyCompleted = state.advanceConstruction(colony)
  if colonyCompleted.isSome:
    result.completedProjects.add(colonyCompleted.get())
    logDebug(
      "Facilities",
      "Colony queue item completed at ", $colonyId,
    )
  # Write back colony (underConstruction slot may have been updated)
  state.updateColony(colonyId, colony)

  # Advance all neorias (spaceports, shipyards, drydocks)
  for neoriaId in colony.neoriaIds:
    let neoriaOpt = state.neoria(neoriaId)
    if neoriaOpt.isSome:
      var neoria = neoriaOpt.get()
      case neoria.neoriaClass:
      of NeoriaClass.Spaceport:
        let spaceportResult = state.advanceSpaceportQueue(neoria, colonyId)
        result.completedProjects.add(spaceportResult.completedProjects)
        result.completedRepairs.add(spaceportResult.completedRepairs)
        state.updateNeoria(neoriaId, neoria)
      of NeoriaClass.Shipyard:
        let shipyardResult = state.advanceShipyardQueue(neoria, colonyId)
        result.completedProjects.add(shipyardResult.completedProjects)
        result.completedRepairs.add(shipyardResult.completedRepairs)
        state.updateNeoria(neoriaId, neoria)
      of NeoriaClass.Drydock:
        let drydockResult = state.advanceDrydockQueue(neoria, colonyId)
        result.completedProjects.add(drydockResult.completedProjects)
        result.completedRepairs.add(drydockResult.completedRepairs)
        state.updateNeoria(neoriaId, neoria)

proc advanceAllQueues*(
    state: GameState
): tuple[
  projects: seq[production.CompletedProject],
  repairs: seq[production.RepairProject],
] =
  ## Advance all construction and repair queues across all colonies
  ## Called during Maintenance phase (PRD2)
  ## Returns all completed projects and repairs
  result = (projects: @[], repairs: @[])

  for (colonyId, colony) in state.allColoniesWithId():
    let colonyResult = advanceColonyQueues(state, colonyId)
    result.projects.add(colonyResult.completedProjects)
    result.repairs.add(colonyResult.completedRepairs)

  logDebug(
    "Facilities", "Queue advancement complete",
    " completed_projects=", result.projects.len,
    " completed_repairs=", result.repairs.len,
  )

## ==============================================================================
## Design Notes
## ==============================================================================
##
## **Clean Separation of Concerns:**
## Shipyards = Construction only, Drydocks = Repair only.
## This eliminates dock contention between construction and repair projects.
## Players build more Shipyards for production capacity, Drydocks for repair capacity.
##
## **Multi-Dock Facility Behavior:**
## ALL facilities can run multiple projects simultaneously up to their dock limit:
## - Spaceports: Up to 5 simultaneous construction projects
## - Shipyards: Up to 10 simultaneous construction projects
## - Drydocks: Up to 10 simultaneous repair projects
##
## This allows efficient batch operations and maximizes facility utilization.
##
## **Spaceport Cost Penalty:**
## The 2x cost penalty for spaceports is applied at BUILD ORDER time (in command submission),
## not during queue advancement. This ensures the cost is deducted upfront.
##
## **Integration with Legacy System:**
## The old colony.underConstruction field is still used for colony-side construction.
## This is maintained for backwards compatibility with fighters, buildings, and IU investment.
## Capital ships use the per-facility queue system above.
