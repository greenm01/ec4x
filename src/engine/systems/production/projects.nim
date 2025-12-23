## Construction Projects - Factory functions for creating construction projects
##
## This module provides factory functions that define construction projects:
## - Ships (capital ships and fighters)
## - Buildings (infrastructure facilities)
## - Industrial Units (IU investment)
##
## These are pure "definition" functions that return ConstructionProject objects.
## The actual order processing and queue assignment happens in resolution/construction.nim.
##
## **Separation of Concerns:**
## - This module: "What to build" (project definitions, cost calculations)
## - resolution/construction.nim: "How orders work" (validation, routing, treasury)
## - economy/facility_queue.nim: "Queue management" (advancement, completion)

import std/options
import math
import ../../types/core
import ../../types/production
import ../../types/ship
import ../../types/colony
import ../../types/facilities
import ../../config/economy_config  # For IU base cost
import ../../config/config_accessors

export production.ConstructionProject, production.CompletedProject, production.BuildType
export config_accessors.getShipConstructionCost, config_accessors.getShipBaseBuildTime
export config_accessors.getBuildingCost, config_accessors.getBuildingTime
export config_accessors.requiresSpaceport

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

  return int(
    float(globalEconomyConfig.industrial_investment.base_cost) * multiplier
  )

## Construction Project Factory Functions

proc createShipProject*(shipClass: ShipClass, cstLevel: int = 1): ConstructionProject =
  ## Create ship construction project with upfront payment model
  ## Requires CST level to calculate actual build time
  ## Per economy.md:5.0 - full cost must be paid upfront
  let cost = int32(getShipConstructionCost(shipClass))
  let turns = int32(getShipBuildTime(shipClass, cstLevel))

  result = ConstructionProject(
    id: ConstructionProjectId(0),  # ID assigned by entity manager
    colonyId: ColonyId(0),  # Assigned when added to queue
    projectType: BuildType.Ship,
    itemId: $shipClass,
    costTotal: cost,
    costPaid: cost,  # Full upfront payment
    turnsRemaining: turns,
    facilityId: none(uint32),
    facilityType: none(FacilityType)
  )

proc createBuildingProject*(buildingType: string): ConstructionProject =
  ## Create building construction project with upfront payment
  ## Per economy.md:5.0 - full cost must be paid upfront
  let cost = int32(getBuildingCost(buildingType))
  let turns = int32(getBuildingTime(buildingType))

  result = ConstructionProject(
    id: ConstructionProjectId(0),  # ID assigned by entity manager
    colonyId: ColonyId(0),  # Assigned when added to queue
    projectType: BuildType.Facility,
    itemId: buildingType,
    costTotal: cost,
    costPaid: cost,  # Full upfront payment
    turnsRemaining: turns,
    facilityId: none(uint32),
    facilityType: none(FacilityType)
  )

proc createIndustrialProject*(colony: Colony, units: int): ConstructionProject =
  ## Create IU investment project with upfront payment
  ## Per economy.md:5.0 - full cost must be paid upfront
  let costPerUnit = getIndustrialUnitCost(colony)
  let totalCost = int32(costPerUnit * units)

  result = ConstructionProject(
    id: ConstructionProjectId(0),  # ID assigned by entity manager
    colonyId: ColonyId(0),  # Assigned when added to queue
    projectType: BuildType.Industrial,
    itemId: $units & " IU",
    costTotal: totalCost,
    costPaid: totalCost,  # Full upfront payment
    turnsRemaining: 1,  # IU investment completes in 1 turn
    facilityId: none(uint32),
    facilityType: none(FacilityType)
  )
