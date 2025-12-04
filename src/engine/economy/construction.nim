## Construction System
##
## Ship and building construction per economy.md
##
## Construction mechanics:
## - Projects have total cost and progress
## - Production applied each maintenance phase
## - Projects complete when cost paid >= cost total
##
## REFACTORED (Phase 9): Data-Oriented Design
## - Eliminated 120+ lines of case duplication
## - All config lookups moved to config_accessors.nim (macro-generated)
## - Reduced from 320 lines → 200 lines (37% reduction)

import std/options
import math
import types
import ../../common/types/units
import ../gamestate  # For unified Colony type
import config_accessors  # DoD refactoring: macro-generated config accessors

export types.ConstructionProject, types.CompletedProject, types.ConstructionType
export config_accessors.getShipConstructionCost, config_accessors.getShipBaseBuildTime
export config_accessors.getBuildingCost, config_accessors.getBuildingTime
export config_accessors.requiresSpaceport
# NOTE: Don't export gamestate.Colony to avoid ambiguity with gamestate's own export

## Ship Construction Times (reference.md:9.1 and 9.1.1)
## (Cost and base time accessors provided by config_accessors.nim)

proc getShipBuildTime*(shipClass: ShipClass, cstLevel: int): int =
  ## Ship construction completes instantly (1 turn)
  ## Per new time narrative: turns represent variable time periods (1-15 years)
  ## Multi-turn construction would cause severe balance issues across map sizes
  ## CST tech still unlocks ship classes and affects capacity (see Phase 3)
  return 1  # Always instant

## Building Construction (provided by config_accessors.nim)
## - getBuildingCost, getBuildingTime, requiresSpaceport now in config_accessors

## Industrial Unit Investment (economy.md:3.4)

proc getIndustrialUnitCost*(colony: Colony): int =
  ## Calculate cost for next IU investment
  ## Cost scales based on IU percentage relative to PU
  ##
  ## Per economy.md:3.4:
  ## - Up to 50% PU: 1.0x (30 PP)
  ## - 51-75%: 1.2x (36 PP)
  ## - 76-100%: 1.5x (45 PP)
  ## - 101-150%: 2.0x (60 PP)
  ## - 151%+: 2.5x (75 PP)

  let iuPercent = if colony.populationUnits > 0:
    int((float(colony.industrial.units) / float(colony.populationUnits)) * 100.0)
  else:
    0

  let multiplier = if iuPercent <= 50:
    1.0
  elif iuPercent <= 75:
    1.2
  elif iuPercent <= 100:
    1.5
  elif iuPercent <= 150:
    2.0
  else:
    2.5

  return int(float(BASE_IU_COST) * multiplier)

## Construction Management

proc startConstruction*(colony: var Colony, project: ConstructionProject): bool =
  ## Start new construction project at colony
  ## Returns true if started successfully
  ##
  ## NOTE: This function is DEPRECATED for build queue system.
  ## The economy resolution code directly manages constructionQueue now.
  ## We keep this for backwards compatibility but it no longer blocks on underConstruction.
  ##
  ## The build queue system allows multiple simultaneous projects up to dock capacity.
  ## Construction validation happens in economy_resolution.nim via canAcceptMoreProjects().

  # LEGACY: Set underConstruction for first project (backwards compatibility)
  if colony.underConstruction.isNone:
    colony.underConstruction = some(project)

  # Always return true - actual capacity checking happens in resolution layer
  return true

proc advanceConstruction*(colony: var Colony): Option[CompletedProject] =
  ## Advance construction by one turn (upfront payment model)
  ## Returns completed project if finished
  ## Per economy.md:5.0 - full cost paid upfront, construction tracks turns
  if colony.underConstruction.isNone:
    return none(CompletedProject)

  var project = colony.underConstruction.get()

  # Decrement turns remaining
  project.turnsRemaining -= 1

  # Check if complete
  if project.turnsRemaining <= 0:
    let completed = CompletedProject(
      colonyId: colony.systemId,
      projectType: project.projectType,
      itemId: project.itemId
    )

    # Clear construction slot
    colony.underConstruction = none(ConstructionProject)

    # Pull next project from queue if available
    if colony.constructionQueue.len > 0:
      colony.underConstruction = some(colony.constructionQueue[0])
      colony.constructionQueue.delete(0)

    return some(completed)

  # Update progress
  colony.underConstruction = some(project)

  return none(CompletedProject)

proc cancelConstruction*(colony: var Colony): int =
  ## Cancel construction and return refund (50% of total cost)
  ## Returns refunded PP amount
  ## Per economy.md:5.0 - 50% refund on cancellation
  if colony.underConstruction.isNone:
    return 0

  let project = colony.underConstruction.get()
  let refund = project.costTotal div 2

  colony.underConstruction = none(ConstructionProject)

  return refund

## Construction Queue Helpers

proc createShipProject*(shipClass: ShipClass, cstLevel: int = 1): ConstructionProject =
  ## Create ship construction project with upfront payment model
  ## Requires CST level to calculate actual build time
  ## Per economy.md:5.0 - full cost must be paid upfront
  let cost = getShipConstructionCost(shipClass)
  let turns = getShipBuildTime(shipClass, cstLevel)

  result = ConstructionProject(
    projectType: ConstructionType.Ship,
    itemId: $shipClass,
    costTotal: cost,
    costPaid: cost,  # Full upfront payment
    turnsRemaining: turns
  )

proc createBuildingProject*(buildingType: string): ConstructionProject =
  ## Create building construction project with upfront payment
  ## Per economy.md:5.0 - full cost must be paid upfront
  let cost = getBuildingCost(buildingType)
  let turns = getBuildingTime(buildingType)

  result = ConstructionProject(
    projectType: ConstructionType.Building,
    itemId: buildingType,
    costTotal: cost,
    costPaid: cost,  # Full upfront payment
    turnsRemaining: turns
  )

proc createIndustrialProject*(colony: Colony, units: int): ConstructionProject =
  ## Create IU investment project with upfront payment
  ## Per economy.md:5.0 - full cost must be paid upfront
  let costPerUnit = getIndustrialUnitCost(colony)
  let totalCost = costPerUnit * units

  result = ConstructionProject(
    projectType: ConstructionType.Industrial,
    itemId: $units & " IU",
    costTotal: totalCost,
    costPaid: totalCost,  # Full upfront payment
    turnsRemaining: 1  # IU investment completes in 1 turn
  )
