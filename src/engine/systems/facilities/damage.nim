## Facility Damage and Queue Management
##
## Handles clearing construction/repair queues when facilities are destroyed or crippled
## Per economy.md:5.0: "Ships under construction in docks can be destroyed during
## the Conflict Phase if the shipyard/spaceport is destroyed or crippled"

import std/[options, strformat]
import ../../types/[core, game_state, production, facilities, colony]
import ../../../common/logger

proc clearFacilityQueues*(
    colony: var Colony, facilityType: facilities.FacilityClass, state: GameState
) =
  ## Clear construction and repair queues for a specific facility type
  ## Called when a facility is destroyed or crippled
  ## Per economy.md:5.0, ships under construction/repair are lost with no salvage
  ##
  ## **DoD Pattern:**
  ## - Takes GameState for repair project lookups
  ## - Repairs are stored by ID, need entity access for logging

  var destroyedRepairs = 0

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
        "Facilities",
        "Facility destroyed: repair project lost",
        &"type={facilityType} system={colony.systemId} class={className} cost={repair.cost}",
      )
    else:
      survivingRepairs.add(repairId)
  colony.repairQueue = survivingRepairs

  # Construction projects can use any facility type, so only clear if ALL facilities gone
  # This is handled separately in clearAllConstructionQueues()

  if destroyedRepairs > 0:
    logInfo(
      "Facilities",
      "Facility destruction: repair projects lost",
      &"type={facilityType} system={colony.systemId} count={destroyedRepairs}",
    )

proc clearAllConstructionQueues*(colony: var Colony, state: GameState) =
  ## Clear ALL construction queues when colony has no remaining shipyards or spaceports
  ## Called when last facility is destroyed
  ##
  ## **DoD Pattern:**
  ## - Takes GameState for construction project lookups
  ## - Projects are stored by ID, need entity access for logging

  var destroyedProjects = colony.constructionQueue.len

  if colony.underConstruction.isSome:
    destroyedProjects += 1
    let projectId = colony.underConstruction.get()
    let projectOpt = state.constructionProject(projectId)
    if projectOpt.isSome:
      let project = projectOpt.get()
      logWarn(
        "Facilities",
        "All facilities destroyed: construction project lost",
        &"system={colony.systemId} item={project.itemId} paid={project.costPaid} total={project.costTotal}",
      )

  for projectId in colony.constructionQueue:
    let projectOpt = state.constructionProject(projectId)
    if projectOpt.isSome:
      let project = projectOpt.get()
      logWarn(
        "Facilities",
        "All facilities destroyed: construction project lost",
        &"system={colony.systemId} item={project.itemId} paid={project.costPaid} total={project.costTotal}",
      )

  colony.constructionQueue = @[]
  colony.underConstruction = none(ConstructionProjectId)

  if destroyedProjects > 0:
    logInfo(
      "Facilities",
      "All facilities destroyed: construction projects lost",
      &"system={colony.systemId} count={destroyedProjects}",
    )

proc handleFacilityDestruction*(
    colony: var Colony, facilityType: facilities.FacilityClass, state: GameState
) =
  ## Handle facility destruction: clear queues and check if any facilities remain
  ##
  ## **Design:**
  ## - Facility-specific repairs always cleared for that facility type
  ## - Construction queues only cleared if NO facilities remain (construction can use any dock)
  ##
  ## **DoD Pattern:**
  ## - Takes GameState for facility entity access
  ## - Looks up shipyards by ID to check crippled status

  # Clear facility-specific repairs
  clearFacilityQueues(colony, facilityType, state)

  # Check if colony has ANY remaining construction facilities
  # Iterate over neorias to find shipyards and spaceports
  var hasShipyards = false
  var hasSpaceports = false

  for neoriaId in colony.neoriaIds:
    let neoriaOpt = state.neoria(neoriaId)
    if neoriaOpt.isSome:
      let neoria = neoriaOpt.get()
      if neoria.neoriaClass == NeoriaClass.Shipyard and not neoria.isCrippled:
        hasShipyards = true
      elif neoria.neoriaClass == NeoriaClass.Spaceport and not neoria.isCrippled:
        hasSpaceports = true

      # Early exit if we found both types
      if hasShipyards and hasSpaceports:
        break

  if not hasShipyards and not hasSpaceports:
    # No construction facilities left - clear all construction queues
    clearAllConstructionQueues(colony, state)
