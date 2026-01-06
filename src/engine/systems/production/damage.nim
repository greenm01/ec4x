## Facility Damage and Queue Management
##
## Handles clearing construction/repair queues when facilities are destroyed or crippled
## Per economy.md:5.0: "Ships under construction in docks can be destroyed during
## the Conflict Phase if the shipyard/spaceport is destroyed or crippled"
##
## **Architecture:**
## - Uses state layer APIs to read entities (state.repairProject, state.constructionProject)
## - Uses entity ops for mutations (project_ops.completeRepairProject, project_ops.completeConstructionProject)
## - Follows three-layer pattern: State → Business Logic → Entity Ops

import std/[options]
import ../../types/[core, game_state, production, facilities, colony, combat]
import ../../state/engine
import ../../entities/project_ops
import ../../../common/logger

proc clearFacilityQueues*(
    state: var GameState, colony: var Colony, facilityType: facilities.FacilityClass
) =
  ## Clear construction and repair queues for a specific facility type
  ## Called when a facility is destroyed or crippled
  ## Per economy.md:5.0, ships under construction/repair are lost with no salvage
  ##
  ## Uses entity ops to properly delete destroyed projects from entity manager

  var destroyedRepairs = 0'i32

  # Clear facility-specific repairs
  var survivingRepairs: seq[RepairProjectId] = @[]
  for repairId in colony.repairQueue:
    let repairOpt = state.repairProject(repairId)
    if repairOpt.isNone:
      # Project doesn't exist, skip it
      continue

    let repair = repairOpt.get()
    if repair.facilityType == facilityType:
      destroyedRepairs += 1
      let className =
        if repair.shipClass.isSome:
          $repair.shipClass.get()
        else:
          "Unknown"
      logWarn(
        "Facilities", "Facility destroyed: repair project lost",
        " type=", facilityType, " system=", colony.systemId,
        " class=", className, " cost=", repair.cost,
      )
      # Properly delete project from entity manager
      project_ops.completeRepairProject(state, repairId)
    else:
      survivingRepairs.add(repairId)
  colony.repairQueue = survivingRepairs

  # Construction projects can use any facility type, so only clear if ALL facilities gone
  # This is handled separately in clearAllConstructionQueues()

  if destroyedRepairs > 0:
    logInfo(
      "Facilities", "Facility destruction: repair projects lost",
      " type=", facilityType, " system=", colony.systemId,
      " count=", destroyedRepairs,
    )

proc clearAllConstructionQueues*(state: var GameState, colony: var Colony) =
  ## Clear ALL construction queues when colony has no remaining shipyards or spaceports
  ## Called when last facility is destroyed
  ##
  ## Uses entity ops to properly delete destroyed projects from entity manager

  var destroyedProjects = colony.constructionQueue.len.int32

  if colony.underConstruction.isSome:
    destroyedProjects += 1
    let projectId = colony.underConstruction.get()
    let projectOpt = state.constructionProject(projectId)
    if projectOpt.isSome:
      let project = projectOpt.get()
      logWarn(
        "Facilities", "All facilities destroyed: construction project lost",
        " system=", colony.systemId, " item=", project.itemId,
        " paid=", project.costPaid, " total=", project.costTotal,
      )
      # Properly delete project from entity manager
      project_ops.completeConstructionProject(state, projectId)

  for projectId in colony.constructionQueue:
    let projectOpt = state.constructionProject(projectId)
    if projectOpt.isSome:
      let project = projectOpt.get()
      logWarn(
        "Facilities", "All facilities destroyed: construction project lost",
        " system=", colony.systemId, " item=", project.itemId,
        " paid=", project.costPaid, " total=", project.costTotal,
      )
      # Properly delete project from entity manager
      project_ops.completeConstructionProject(state, projectId)

  colony.constructionQueue = @[]
  colony.underConstruction = none(ConstructionProjectId)

  if destroyedProjects > 0:
    logInfo(
      "Facilities", "All facilities destroyed: construction projects lost",
      " system=", colony.systemId, " count=", destroyedProjects,
    )

proc handleFacilityDestruction*(
    state: var GameState, colony: var Colony, facilityType: facilities.FacilityClass
) =
  ## Handle facility destruction: clear queues and check if any facilities remain
  ##
  ## **Design:**
  ## - Facility-specific repairs always cleared for that facility type
  ## - Construction queues only cleared if NO facilities remain (construction can use any dock)
  ##
  ## Uses state layer APIs to check remaining facilities

  # Clear facility-specific repairs
  state.clearFacilityQueues(colony, facilityType)

  # Check if colony has ANY remaining construction facilities
  # Iterate over neorias to find shipyards and spaceports
  var hasShipyards = false
  var hasSpaceports = false

  for neoriaId in colony.neoriaIds:
    let neoriaOpt = state.neoria(neoriaId)
    if neoriaOpt.isSome:
      let neoria = neoriaOpt.get()
      if neoria.neoriaClass == NeoriaClass.Shipyard and
          neoria.state != CombatState.Crippled:
        hasShipyards = true
      elif neoria.neoriaClass == NeoriaClass.Spaceport and
          neoria.state != CombatState.Crippled:
        hasSpaceports = true

      # Early exit if we found both types
      if hasShipyards and hasSpaceports:
        break

  if not hasShipyards and not hasSpaceports:
    # No construction facilities left - clear all construction queues
    state.clearAllConstructionQueues(colony)
