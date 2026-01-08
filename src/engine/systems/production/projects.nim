## Construction Projects - Factory functions for creating construction projects
##
## This module provides factory functions that define construction projects:
## - Ships (capital ships and fighters)
## - Buildings (infrastructure facilities)
## - Industrial Units (IU investment)
##
## These are pure "definition" functions that return ConstructionProject objects.
## The actual command processing and queue assignment happens in construction.nim.
##
## **Separation of Concerns:**
## - This module: "What to build" (project definitions, cost calculations)
## - construction.nim: "How commands work" (validation, routing, treasury)
## - queue_advancement.nim: "Queue management" (advancement, completion)
##
## **Architecture Notes:**
## - Uses accessors.nim for config access (DRY principle)
## - Pure factory functions - no state mutations
## - All projects use upfront payment model (economy.md:5.0)

import std/[options, tables]
import ../../types/[core, production, ship, colony, facilities]
import ../../entities/project_ops
import ../../globals
import ./accessors

export production.ConstructionProject, production.CompletedProject, production.BuildType

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
  # Tiers are ordered 1-5, check in command until threshold exceeded
  var multiplier = 1.0'f32  # Default fallback

  let cfg = gameConfig.economy.industrialInvestment
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
  ## Per economy.md:5.0 - full cost must be paid upfront
  ## Per construction.kdl: all ships build in 1 turn
  let cost = accessors.getShipConstructionCost(shipClass)
  let turns = accessors.getShipBaseBuildTime(shipClass)

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

proc createBuildingProject*(buildingType: FacilityClass): ConstructionProject =
  ## Create building construction project with upfront payment
  ## Per economy.md:5.0 - full cost must be paid upfront
  ## Per construction.kdl: all facilities build in 1 turn
  let cost = accessors.getBuildingCost(buildingType)
  let turns = accessors.getBuildingTime(buildingType)

  result = project_ops.newConstructionProject(
    id = ConstructionProjectId(0), # ID assigned by entity manager
    colonyId = ColonyId(0), # Assigned when added to queue
    projectType = BuildType.Facility,
    itemId = $buildingType, # Convert enum to string
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
