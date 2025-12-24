## Facility Damage and Queue Management
##
## Handles clearing construction/repair queues when facilities are destroyed or crippled
## Per economy.md:5.0: "Ships under construction in docks can be destroyed during
## the Conflict Phase if the shipyard/spaceport is destroyed or crippled"

import std/[strformat, options, sequtils]
import ../../types/[game_state, production, facilities]
import ../../../common/logger

proc clearFacilityQueues*(colony: var Colony, facilityType: facilities.FacilityType) =
  ## Clear construction and repair queues for a specific facility type
  ## Called when a facility is destroyed or crippled
  ## Per economy.md:5.0, ships under construction/repair are lost with no salvage

  var destroyedRepairs = 0

  # Clear facility-specific repairs
  var survivingRepairs: seq[production.RepairProject] = @[]
  for repair in colony.repairQueue:
    if repair.facilityType == facilityType:
      destroyedRepairs += 1
      let className = if repair.shipClass.isSome: $repair.shipClass.get() else: "Unknown"
      logWarn("Facilities", "Facility destroyed: repair project lost",
              facilityType = facilityType, systemId = colony.systemId,
              className = className, cost = repair.cost)
    else:
      survivingRepairs.add(repair)
  colony.repairQueue = survivingRepairs

  # Construction projects can use any facility type, so only clear if ALL facilities gone
  # This is handled separately in clearAllConstructionQueues()

  if destroyedRepairs > 0:
    logInfo("Facilities", "Facility destruction: repair projects lost",
            facilityType = facilityType, systemId = colony.systemId,
            count = destroyedRepairs)

proc clearAllConstructionQueues*(colony: var Colony) =
  ## Clear ALL construction queues when colony has no remaining shipyards or spaceports
  ## Called when last facility is destroyed
  var destroyedProjects = colony.constructionQueue.len

  if colony.underConstruction.isSome:
    destroyedProjects += 1
    let project = colony.underConstruction.get()
    logWarn("Facilities", "All facilities destroyed: construction project lost",
            systemId = colony.systemId, itemId = project.itemId,
            investment = project.costPaid, total = project.costTotal)

  for project in colony.constructionQueue:
    logWarn("Facilities", "All facilities destroyed: construction project lost",
            systemId = colony.systemId, itemId = project.itemId,
            investment = project.costPaid, total = project.costTotal)

  colony.constructionQueue = @[]
  colony.underConstruction = none(production.ConstructionProject)

  if destroyedProjects > 0:
    logInfo("Facilities", "All facilities destroyed: construction projects lost",
            systemId = colony.systemId, count = destroyedProjects)

proc handleFacilityDestruction*(colony: var Colony, facilityType: facilities.FacilityType) =
  ## Handle facility destruction: clear queues and check if any facilities remain
  ##
  ## **Design:**
  ## - Facility-specific repairs always cleared for that facility type
  ## - Construction queues only cleared if NO facilities remain (construction can use any dock)

  # Clear facility-specific repairs
  clearFacilityQueues(colony, facilityType)

  # Check if colony has ANY remaining construction facilities
  let hasShipyards = colony.shipyards.anyIt(not it.isCrippled)
  let hasSpaceports = colony.spaceports.len > 0

  if not hasShipyards and not hasSpaceports:
    # No construction facilities left - clear all construction queues
    clearAllConstructionQueues(colony)
