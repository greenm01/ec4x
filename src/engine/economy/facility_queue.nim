## Per-Facility Queue Management System
##
## Manages construction and repair queues at individual facilities (spaceports/shipyards).
##
## **FIFO Priority Model:**
## Construction and repair projects are processed in the order queued (first in, first out).
## Each facility independently advances its own queues.
##
## **Facility Queue Structure:**
## - Spaceport: constructionQueue → activeConstruction (1 project max)
## - Shipyard: constructionQueue + repairQueue → activeConstruction + activeRepairs (total ≤ 10 docks)
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
import ../../common/types/units
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
  ## Spaceports only handle construction (5 docks)
  result = QueueAdvancementResult(
    completedProjects: @[],
    completedRepairs: @[]
  )

  # Step 1: Advance active construction
  if spaceport.activeConstruction.isSome:
    var project = spaceport.activeConstruction.get()
    project.turnsRemaining -= 1

    if project.turnsRemaining <= 0:
      # Construction complete
      result.completedProjects.add(econ_types.CompletedProject(
        colonyId: colonyId,
        projectType: project.projectType,
        itemId: project.itemId
      ))
      spaceport.activeConstruction = none(econ_types.ConstructionProject)
      logEconomy("Spaceport construction complete",
                "facility=", spaceport.id,
                " project=", project.itemId)
    else:
      # Still in progress
      spaceport.activeConstruction = some(project)

  # Step 2: Pull next project from queue if slot available
  if spaceport.activeConstruction.isNone and spaceport.constructionQueue.len > 0:
    let nextProject = spaceport.constructionQueue[0]
    spaceport.constructionQueue.delete(0)
    spaceport.activeConstruction = some(nextProject)
    logEconomy("Spaceport started new construction",
              "facility=", spaceport.id,
              " project=", nextProject.itemId)

proc advanceShipyardQueue*(shipyard: var gamestate.Shipyard,
                           colonyId: core.SystemId): QueueAdvancementResult =
  ## Advance shipyard construction + repair queues (FIFO)
  ## Shipyards handle both construction and repair (10 docks total)
  result = QueueAdvancementResult(
    completedProjects: @[],
    completedRepairs: @[]
  )

  # Crippled shipyards can't work
  if shipyard.isCrippled:
    return

  # Step 1: Advance active construction
  if shipyard.activeConstruction.isSome:
    var project = shipyard.activeConstruction.get()
    project.turnsRemaining -= 1

    if project.turnsRemaining <= 0:
      # Construction complete
      result.completedProjects.add(econ_types.CompletedProject(
        colonyId: colonyId,
        projectType: project.projectType,
        itemId: project.itemId
      ))
      shipyard.activeConstruction = none(econ_types.ConstructionProject)
      logEconomy("Shipyard construction complete",
                "facility=", shipyard.id,
                " project=", project.itemId)
    else:
      # Still in progress
      shipyard.activeConstruction = some(project)

  # Step 2: Advance active repairs
  var completedRepairIndices: seq[int] = @[]
  for idx, repair in shipyard.activeRepairs:
    var repairCopy = repair
    repairCopy.turnsRemaining -= 1

    if repairCopy.turnsRemaining <= 0:
      # Repair complete
      result.completedRepairs.add(repairCopy)
      completedRepairIndices.add(idx)
      logEconomy("Shipyard repair complete",
                "facility=", shipyard.id,
                " target=", $repairCopy.targetType)
    else:
      # Still in progress - update in place
      shipyard.activeRepairs[idx] = repairCopy

  # Remove completed repairs (reverse order to maintain indices)
  for idx in completedRepairIndices.reversed:
    shipyard.activeRepairs.delete(idx)

  # Step 3: Pull new projects from queues to fill available docks (FIFO priority)
  # Calculate available docks
  var usedDocks = 0
  if shipyard.activeConstruction.isSome:
    usedDocks += 1
  usedDocks += shipyard.activeRepairs.len

  let availableDocks = shipyard.docks - usedDocks

  # Pull projects from queues (FIFO - alternate between construction and repair)
  # We'll use a simple approach: pull from queues in FIFO order considering both
  var pulled = 0
  while pulled < availableDocks:
    # Determine next project to pull (FIFO across both queues)
    # For now, simple approach: pull from construction queue first, then repair queue
    # (True FIFO would require timestamped queuing - future enhancement)

    if shipyard.activeConstruction.isNone and shipyard.constructionQueue.len > 0:
      # Pull construction project
      let nextProject = shipyard.constructionQueue[0]
      shipyard.constructionQueue.delete(0)
      shipyard.activeConstruction = some(nextProject)
      logEconomy("Shipyard started new construction",
                "facility=", shipyard.id,
                " project=", nextProject.itemId)
      pulled += 1
    elif shipyard.repairQueue.len > 0 and shipyard.activeRepairs.len < availableDocks:
      # Pull repair project
      let nextRepair = shipyard.repairQueue[0]
      shipyard.repairQueue.delete(0)
      shipyard.activeRepairs.add(nextRepair)
      logEconomy("Shipyard started new repair",
                "facility=", shipyard.id,
                " target=", $nextRepair.targetType)
      pulled += 1
    else:
      # No more projects to pull
      break

proc advanceColonyQueues*(colony: var gamestate.Colony): QueueAdvancementResult =
  ## Advance all facility queues at colony
  ## Returns combined results from all facilities
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

proc advanceAllQueues*(state: var GameState): tuple[projects: seq[econ_types.CompletedProject], repairs: seq[econ_types.RepairProject]] =
  ## Advance all facility queues across all colonies
  ## Called during Maintenance phase
  ## Returns all completed projects and repairs
  result = (projects: @[], repairs: @[])

  for colonyId, colony in state.colonies.mpairs:
    let colonyResult = advanceColonyQueues(colony)
    result.projects.add(colonyResult.completedProjects)
    result.repairs.add(colonyResult.completedRepairs)

  logDebug("Economy",
          "Queue advancement complete",
          " completed_projects=", $result.projects.len,
          " completed_repairs=", $result.repairs.len)

## Design Notes:
##
## **FIFO Priority Implementation:**
## Current implementation uses simplified FIFO: construction projects first, then repairs.
## True FIFO would require timestamped queue entries to interleave construction/repair.
## This is acceptable since both types advance simultaneously - only affects queue pulling order.
##
## **Multi-Dock Shipyard Behavior:**
## Shipyards can run multiple repairs simultaneously (up to available docks).
## Construction is limited to 1 active project but repairs can fill remaining docks.
##
## **Spaceport Cost Penalty:**
## The 2x cost penalty for spaceports is applied at BUILD ORDER time (in order submission),
## not during queue advancement. This ensures the cost is deducted upfront.
##
## **Integration with Legacy System:**
## The old colony.underConstruction field is DEPRECATED.
## This system replaces it with per-facility queues.
## Backwards compatibility can be maintained by syncing first facility's activeConstruction
## to colony.underConstruction if needed for UI/reports.
