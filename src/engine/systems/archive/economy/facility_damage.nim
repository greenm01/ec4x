## Facility Damage and Queue Management
##
## Handles clearing construction/repair queues when facilities are destroyed or crippled
## Per economy.md:5.0: "Ships under construction in docks can be destroyed during
## the Conflict Phase if the shipyard/spaceport is destroyed or crippled"

import std/[options, sequtils, strformat]
import ../../gamestate
import ../../types/economy as econ_types
import ../../../common/logger

proc clearFacilityQueues*(colony: var Colony, facilityType: econ_types.FacilityType) =
  ## Clear construction and repair queues for a specific facility type
  ## Called when a facility is destroyed or crippled
  ## Per economy.md:5.0, ships under construction/repair are lost with no salvage

  var destroyedRepairs = 0

  # Clear facility-specific repairs
  var survivingRepairs: seq[econ_types.RepairProject] = @[]
  for repair in colony.repairQueue:
    if repair.facilityType == facilityType:
      destroyedRepairs += 1
      let className = if repair.shipClass.isSome: $repair.shipClass.get() else: "Unknown"
      logWarn("Economy",
              &"{facilityType} destroyed at system-{colony.systemId}: Repair project for {className} lost",
              &"Cost: {repair.cost} PP")
    else:
      survivingRepairs.add(repair)
  colony.repairQueue = survivingRepairs

  # Construction projects can use any facility type, so only clear if ALL facilities gone
  # This is handled separately in clearAllConstructionQueues()

  if destroyedRepairs > 0:
    logInfo("Economy",
            &"{facilityType} destruction at system-{colony.systemId}",
            &"{destroyedRepairs} repair projects lost")

proc clearAllConstructionQueues*(colony: var Colony) =
  ## Clear ALL construction queues when colony has no remaining shipyards or spaceports
  ## Called when last facility is destroyed
  var destroyedProjects = colony.constructionQueue.len

  if colony.underConstruction.isSome:
    destroyedProjects += 1
    let project = colony.underConstruction.get()
    logWarn("Economy",
            &"All facilities destroyed at system-{colony.systemId}: Construction project {project.itemId} lost",
            &"Investment: {project.costPaid}/{project.costTotal} PP")

  for project in colony.constructionQueue:
    logWarn("Economy",
            &"All facilities destroyed at system-{colony.systemId}: Construction project {project.itemId} lost",
            &"Investment: {project.costPaid}/{project.costTotal} PP")

  colony.constructionQueue = @[]
  colony.underConstruction = none(econ_types.ConstructionProject)

  if destroyedProjects > 0:
    logInfo("Economy",
            &"All facilities destroyed at system-{colony.systemId}",
            &"{destroyedProjects} construction projects lost")

proc handleFacilityDestruction*(colony: var Colony, facilityType: econ_types.FacilityType) =
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
