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
import ../../types/[core, production, ship, colony, facilities]
import ../../config/[economy_config, config_accessors]
import ../../entities/project_ops
import ../../../common/logger

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
  return 1 # Always instant

## Building Construction (provided by config_accessors.nim)
## - getBuildingCost, getBuildingTime, requiresSpaceport now in config_accessors

## Industrial Unit Investment (economy.md:3.4)

proc getIndustrialUnitCost*(colony: Colony): int32 =
  ## Calculate cost for next IU investment
  ## Cost scales based on IU percentage relative to PU (economy.md:3.4)
  ## Reads scaling tiers from config/economy.kdl

  let iuPercent =
    if colony.populationUnits > 0:
      int32((float32(colony.industrial.units) / float32(colony.populationUnits)) * 100.0)
    else:
      0'i32

  # Find applicable tier based on IU percentage
  # Tiers are ordered 1-5, check in order until threshold exceeded
  var multiplier = 1.0'f32  # Default fallback

  let cfg = globalEconomyConfig.industrialInvestment
  for tierNum in 1'i32 .. 5'i32:
    if cfg.costScaling.hasKey(tierNum):
      let tier = cfg.costScaling[tierNum]
      if iuPercent <= tier.threshold:
        multiplier = tier.multiplier
        break
      # If we've passed all thresholds, use the highest tier's multiplier
      multiplier = tier.multiplier

  return int32(float32(cfg.baseCost) * multiplier)

## Construction Project Factory Functions

proc createShipProject*(shipClass: ShipClass, cstLevel: int = 1): ConstructionProject =
  ## Create ship construction project with upfront payment model
  ## Requires CST level to calculate actual build time
  ## Per economy.md:5.0 - full cost must be paid upfront
  let cost = int32(getShipConstructionCost(shipClass))
  let turns = int32(getShipBuildTime(shipClass, cstLevel))

  result = project_ops.newConstructionProject(
    id = ConstructionProjectId(0), # ID assigned by entity manager
    colonyId = ColonyId(0), # Assigned when added to queue
    projectType = BuildType.Ship,
    itemId = $shipClass,
    costTotal = cost,
    costPaid = cost, # Full upfront payment
    turnsRemaining = turns,
    neoriaId = none(NeoriaId),
  )

proc createBuildingProject*(buildingType: string): ConstructionProject =
  ## Create building construction project with upfront payment
  ## Per economy.md:5.0 - full cost must be paid upfront
  let cost = int32(getBuildingCost(buildingType))
  let turns = int32(getBuildingTime(buildingType))

  result = project_ops.newConstructionProject(
    id = ConstructionProjectId(0), # ID assigned by entity manager
    colonyId = ColonyId(0), # Assigned when added to queue
    projectType = BuildType.Facility,
    itemId = buildingType,
    costTotal = cost,
    costPaid = cost, # Full upfront payment
    turnsRemaining = turns,
    neoriaId = none(NeoriaId),
  )

proc createIndustrialProject*(colony: Colony, units: int): ConstructionProject =
  ## Create IU investment project with upfront payment
  ## Per economy.md:5.0 - full cost must be paid upfront
  let costPerUnit = getIndustrialUnitCost(colony)
  let totalCost = int32(costPerUnit * units)

  result = project_ops.newConstructionProject(
    id = ConstructionProjectId(0), # ID assigned by entity manager
    colonyId = ColonyId(0), # Assigned when added to queue
    projectType = BuildType.Industrial,
    itemId = $units & " IU",
    costTotal = totalCost,
    costPaid = totalCost, # Full upfront payment
    turnsRemaining = 1, # IU investment completes in 1 turn
    neoriaId = none(NeoriaId),
  )
