## Per-Facility Queue Management System
##
## Manages construction and repair queues at individual facilities.
##
## **Facility Specialization:**
## - Spaceport: Construction only (5 docks) - ground-based launch facility
## - Shipyard: Construction only (10 docks) - orbital ship construction
## - Drydock: Repair only (10 docks) - orbital ship repair facility
##
## **FIFO Queue Model:**
## Each facility independently advances its own queues in order queued.
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
## Ships built at spaceports cost 2x PP (applied at order submission time)
## Exception: Shipyard/Starbase buildings (orbital construction, no penalty)

import std/[options, tables, algorithm]
import types
import ../gamestate
import ../economy/types as econ_types
import ../../common/types/core
import ../../common/logger

export types.CompletedProject

type
  QueueAdvancementResult* = object
    ## Results from advancing a facility's queues
    completedProjects*: seq[econ_types.CompletedProject]
    completedRepairs*: seq[econ_types.RepairProject]

proc advanceSpaceportQueue*(spaceport: var gamestate.Spaceport,
                             colonyId: core.SystemId): QueueAdvancementResult =
  ## Advance spaceport construction queue (FIFO)
  ## Spaceports handle multiple simultaneous construction (up to effective docks limit with CST scaling)
  result = QueueAdvancementResult(
    completedProjects: @[],
    completedRepairs: @[]
  )

  # Step 1: Advance all active construction projects
  var completedIndices: seq[int] = @[]
  for idx, project in spaceport.activeConstructions:
    var projectCopy = project
    projectCopy.turnsRemaining -= 1

    if projectCopy.turnsRemaining <= 0:
      # Construction complete
      result.completedProjects.add(econ_types.CompletedProject(
        colonyId: colonyId,
        projectType: projectCopy.projectType,
        itemId: projectCopy.itemId
      ))
      completedIndices.add(idx)
      logEconomy("Spaceport construction complete",
                "facility=", spaceport.id,
                " project=", projectCopy.itemId)
    else:
      # Still in progress - update in place
      spaceport.activeConstructions[idx] = projectCopy

  # Remove completed projects (reverse order to maintain indices)
  for idx in completedIndices.reversed:
    spaceport.activeConstructions.delete(idx)

  # Step 2: Pull new projects from queue to fill available docks
  let availableDocks = spaceport.effectiveDocks - spaceport.activeConstructions.len

  var pulled = 0
  while pulled < availableDocks and spaceport.constructionQueue.len > 0:
    var nextProject = spaceport.constructionQueue[0]
    spaceport.constructionQueue.delete(0)

    # CRITICAL: Decrement turnsRemaining immediately when starting
    # This ensures "1 turn" projects complete in the same turn cycle
    nextProject.turnsRemaining -= 1

    if nextProject.turnsRemaining <= 0:
      # Project completes immediately (0-turn projects)
      result.completedProjects.add(econ_types.CompletedProject(
        colonyId: colonyId,
        projectType: nextProject.projectType,
        itemId: nextProject.itemId
      ))
      logEconomy("Spaceport construction complete (instant)",
                "facility=", spaceport.id,
                " project=", nextProject.itemId)
      # Don't add to activeConstructions - dock remains free
      pulled += 1
    else:
      # Project still needs more turns
      spaceport.activeConstructions.add(nextProject)
      logEconomy("Spaceport started new construction",
                "facility=", spaceport.id,
                " project=", nextProject.itemId)
      pulled += 1

proc advanceDrydockQueue*(drydock: var gamestate.Drydock,
                          colonyId: core.SystemId): QueueAdvancementResult =
  ## Advance drydock repair queue (repair-only facility)
  ## Drydocks handle repairs only (effective docks with CST scaling, no construction)
  result = QueueAdvancementResult(
    completedProjects: @[],
    completedRepairs: @[]
  )

  # Crippled drydocks can't work
  if drydock.isCrippled:
    return

  # Step 1: Advance active repairs
  var completedRepairIndices: seq[int] = @[]
  for idx, repair in drydock.activeRepairs:
    var repairCopy = repair
    repairCopy.turnsRemaining -= 1

    if repairCopy.turnsRemaining <= 0:
      # Repair complete
      result.completedRepairs.add(repairCopy)
      completedRepairIndices.add(idx)
      logEconomy("Drydock repair complete",
                "facility=", drydock.id,
                " target=", $repairCopy.targetType)
    else:
      # Still in progress - update in place
      drydock.activeRepairs[idx] = repairCopy

  # Remove completed repairs (reverse order to maintain indices)
  for idx in completedRepairIndices.reversed:
    drydock.activeRepairs.delete(idx)

  # Step 2: Pull new repairs from queue to fill available docks
  let availableDocks = drydock.effectiveDocks - drydock.activeRepairs.len

  var pulled = 0
  while pulled < availableDocks and drydock.repairQueue.len > 0:
    # Pull repair project
    let nextRepair = drydock.repairQueue[0]
    drydock.repairQueue.delete(0)
    drydock.activeRepairs.add(nextRepair)
    logEconomy("Drydock started new repair",
              "facility=", drydock.id,
              " target=", $nextRepair.targetType)
    pulled += 1

proc advanceShipyardQueue*(shipyard: var gamestate.Shipyard,
                           colonyId: core.SystemId): QueueAdvancementResult =
  ## Advance shipyard construction queue (construction-only facility)
  ## Shipyards handle multiple simultaneous construction (effective docks with CST scaling)
  result = QueueAdvancementResult(
    completedProjects: @[],
    completedRepairs: @[]
  )

  # Crippled shipyards can't work
  if shipyard.isCrippled:
    return

  # Step 1: Advance all active construction projects
  var completedIndices: seq[int] = @[]
  for idx, project in shipyard.activeConstructions:
    var projectCopy = project
    projectCopy.turnsRemaining -= 1

    if projectCopy.turnsRemaining <= 0:
      # Construction complete
      result.completedProjects.add(econ_types.CompletedProject(
        colonyId: colonyId,
        projectType: projectCopy.projectType,
        itemId: projectCopy.itemId
      ))
      completedIndices.add(idx)
      logEconomy("Shipyard construction complete",
                "facility=", shipyard.id,
                " project=", projectCopy.itemId)
    else:
      # Still in progress - update in place
      shipyard.activeConstructions[idx] = projectCopy

  # Remove completed projects (reverse order to maintain indices)
  for idx in completedIndices.reversed:
    shipyard.activeConstructions.delete(idx)

  # Step 2: Pull new projects from queue to fill available docks
  let availableDocks = shipyard.effectiveDocks - shipyard.activeConstructions.len

  var pulled = 0
  while pulled < availableDocks and shipyard.constructionQueue.len > 0:
    var nextProject = shipyard.constructionQueue[0]
    shipyard.constructionQueue.delete(0)

    # CRITICAL: Decrement turnsRemaining immediately when starting
    # This ensures "1 turn" projects complete in the same turn cycle
    nextProject.turnsRemaining -= 1

    if nextProject.turnsRemaining <= 0:
      # Project completes immediately (0-turn projects)
      result.completedProjects.add(econ_types.CompletedProject(
        colonyId: colonyId,
        projectType: nextProject.projectType,
        itemId: nextProject.itemId
      ))
      logEconomy("Shipyard construction complete (instant)",
                "facility=", shipyard.id,
                " project=", nextProject.itemId)
      # Don't add to activeConstructions - dock remains free
      pulled += 1
    else:
      # Project still needs more turns
      shipyard.activeConstructions.add(nextProject)
      logEconomy("Shipyard started new construction",
                "facility=", shipyard.id,
                " project=", nextProject.itemId)
      pulled += 1

proc advanceColonyQueues*(colony: var gamestate.Colony): QueueAdvancementResult =
  ## Advance all facility queues at colony
  ## Returns combined results from all facilities
  ## NOTE: Uses pre-calculated effectiveDocks (updated on CST tech upgrade)
  result = QueueAdvancementResult(
    completedProjects: @[],
    completedRepairs: @[]
  )

  # Advance all spaceports
  for spaceport in colony.spaceports.mitems:
    let spaceportResult = advanceSpaceportQueue(spaceport, colony.systemId)
    result.completedProjects.add(spaceportResult.completedProjects)
    result.completedRepairs.add(spaceportResult.completedRepairs)

  # Advance all shipyards
  for shipyard in colony.shipyards.mitems:
    let shipyardResult = advanceShipyardQueue(shipyard, colony.systemId)
    result.completedProjects.add(shipyardResult.completedProjects)
    result.completedRepairs.add(shipyardResult.completedRepairs)

  # Advance all drydocks
  for drydock in colony.drydocks.mitems:
    let drydockResult = advanceDrydockQueue(drydock, colony.systemId)
    result.completedProjects.add(drydockResult.completedProjects)
    result.completedRepairs.add(drydockResult.completedRepairs)

proc advanceAllQueues*(state: var GameState): tuple[projects: seq[econ_types.CompletedProject], repairs: seq[econ_types.RepairProject]] =
  ## Advance all facility queues across all colonies
  ## Called during Maintenance phase
  ## Returns all completed projects and repairs
  ## NOTE: Uses pre-calculated effectiveDocks (updated on CST tech upgrade)
  result = (projects: @[], repairs: @[])

  for colonyId, colony in state.colonies.mpairs:
    let colonyResult = advanceColonyQueues(colony)
    result.projects.add(colonyResult.completedProjects)
    result.repairs.add(colonyResult.completedRepairs)

  logDebug("Economy",
          "Queue advancement complete",
          " completed_projects=", $result.projects.len,
          " completed_repairs=", $result.repairs.len)

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

proc startConstruction*(colony: var gamestate.Colony, project: econ_types.ConstructionProject): bool =
  ## Start new construction project at colony
  ## Returns true if started successfully
  ##
  ## NOTE: This function manages the legacy colony construction queue.
  ## Used for fighters, buildings, and IU investment (planet-side construction).
  ## Capital ships use the facility queue system (construction_docks.nim).

  # Set underConstruction for first project
  if colony.underConstruction.isNone:
    colony.underConstruction = some(project)

  # Always return true - actual capacity checking happens in resolution layer
  return true

proc advanceConstruction*(colony: var gamestate.Colony): Option[econ_types.CompletedProject] =
  ## Advance colony construction by one turn (upfront payment model)
  ## Returns completed project if finished
  ## Per economy.md:5.0 - full cost paid upfront, construction tracks turns

  if colony.underConstruction.isNone:
    return none(econ_types.CompletedProject)

  var project = colony.underConstruction.get()

  # Decrement turns remaining
  project.turnsRemaining -= 1

  # Check if complete
  if project.turnsRemaining <= 0:
    let completed = econ_types.CompletedProject(
      colonyId: colony.systemId,
      projectType: project.projectType,
      itemId: project.itemId
    )

    # Clear construction slot
    colony.underConstruction = none(econ_types.ConstructionProject)

    # Pull next project from queue if available
    if colony.constructionQueue.len > 0:
      colony.underConstruction = some(colony.constructionQueue[0])
      colony.constructionQueue.delete(0)

    return some(completed)

  # Update progress
  colony.underConstruction = some(project)

  return none(econ_types.CompletedProject)

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
## The 2x cost penalty for spaceports is applied at BUILD ORDER time (in order submission),
## not during queue advancement. This ensures the cost is deducted upfront.
##
## **Integration with Legacy System:**
## The old colony.underConstruction field is still used for colony-side construction.
## This is maintained for backwards compatibility with fighters, buildings, and IU investment.
## Capital ships use the per-facility queue system above.
