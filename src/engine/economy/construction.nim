## Construction System
##
## Ship and building construction per economy.md
##
## Construction mechanics:
## - Projects have total cost and progress
## - Production applied each maintenance phase
## - Projects complete when cost paid >= cost total

import std/[options, tables]
import types
import ../../common/types/[core, units]
import ../config/[construction_config, facilities_config]
import ../gamestate  # For unified Colony type

export types.ConstructionProject, types.CompletedProject, types.ConstructionType
# NOTE: Don't export gamestate.Colony to avoid ambiguity with gamestate's own export

## Ship Construction Costs and Times (reference.md:9.1 and 9.1.1)

import ../config/ships_config
import math

proc getShipConstructionCost*(shipClass: ShipClass): int =
  ## Get construction cost (PC) for ship class from ships.toml
  ## Per reference.md:9.1
  let shipsConfig = globalShipsConfig

  case shipClass
  of ShipClass.Fighter:
    return shipsConfig.fighter.build_cost
  of ShipClass.Corvette:
    return shipsConfig.corvette.build_cost
  of ShipClass.Frigate:
    return shipsConfig.frigate.build_cost
  of ShipClass.Raider:
    return shipsConfig.raider.build_cost
  of ShipClass.Destroyer:
    return shipsConfig.destroyer.build_cost
  of ShipClass.Cruiser:
    return shipsConfig.cruiser.build_cost
  of ShipClass.LightCruiser:
    return shipsConfig.light_cruiser.build_cost
  of ShipClass.HeavyCruiser:
    return shipsConfig.heavy_cruiser.build_cost
  of ShipClass.Carrier:
    return shipsConfig.carrier.build_cost
  of ShipClass.SuperCarrier:
    return shipsConfig.supercarrier.build_cost
  of ShipClass.Battleship:
    return shipsConfig.battleship.build_cost
  of ShipClass.Battlecruiser:
    return shipsConfig.battlecruiser.build_cost
  of ShipClass.Dreadnought:
    return shipsConfig.dreadnought.build_cost
  of ShipClass.SuperDreadnought:
    return shipsConfig.super_dreadnought.build_cost
  of ShipClass.TroopTransport:
    return shipsConfig.troop_transport.build_cost
  of ShipClass.ETAC:
    return shipsConfig.etac.build_cost
  of ShipClass.Scout:
    return shipsConfig.scout.build_cost
  of ShipClass.Starbase:
    return shipsConfig.starbase.build_cost
  of ShipClass.PlanetBreaker:
    return shipsConfig.planetbreaker.build_cost

proc getShipBaseBuildTime*(shipClass: ShipClass): int =
  ## Get base construction time (before CST modifier) from ships.toml
  ## Per reference.md:9.1.1
  let constructionConfig = globalShipsConfig.construction

  case shipClass
  of ShipClass.Fighter:
    return constructionConfig.fighter_base_time
  of ShipClass.Corvette:
    return constructionConfig.corvette_base_time
  of ShipClass.Frigate:
    return constructionConfig.frigate_base_time
  of ShipClass.Raider:
    return constructionConfig.raider_base_time
  of ShipClass.Destroyer:
    return constructionConfig.destroyer_base_time
  of ShipClass.Cruiser:
    return constructionConfig.cruiser_base_time
  of ShipClass.LightCruiser:
    return constructionConfig.light_cruiser_base_time
  of ShipClass.HeavyCruiser:
    return constructionConfig.heavy_cruiser_base_time
  of ShipClass.Carrier:
    return constructionConfig.carrier_base_time
  of ShipClass.SuperCarrier:
    return constructionConfig.supercarrier_base_time
  of ShipClass.Battleship:
    return constructionConfig.battleship_base_time
  of ShipClass.Battlecruiser:
    return constructionConfig.battlecruiser_base_time
  of ShipClass.Dreadnought:
    return constructionConfig.dreadnought_base_time
  of ShipClass.SuperDreadnought:
    return constructionConfig.super_dreadnought_base_time
  of ShipClass.TroopTransport:
    return constructionConfig.troop_transport_base_time
  of ShipClass.ETAC:
    return constructionConfig.etac_base_time
  of ShipClass.Scout:
    return constructionConfig.scout_base_time
  of ShipClass.Starbase:
    return constructionConfig.starbase_base_time
  of ShipClass.PlanetBreaker:
    return constructionConfig.planetbreaker_base_time

proc getShipBuildTime*(shipClass: ShipClass, cstLevel: int): int =
  ## Get actual construction time in turns with CST modifier
  ## Per reference.md:9.1.1
  ##
  ## Formula: ceiling(base_time × (1.0 - (CST_level - 1) × 0.10))
  ## Minimum: 1 turn
  let baseTime = getShipBaseBuildTime(shipClass)
  let modifier = 1.0 - (float(cstLevel - 1) * 0.10)
  let actualTime = ceil(float(baseTime) * modifier).int
  return max(1, actualTime)

## Building Construction Costs

proc getBuildingCost*(buildingType: string): int =
  ## Get construction cost for building type from config
  ## Uses both construction_config and facilities_config
  let constructionConfig = globalConstructionConfig.costs
  let facilitiesConfig = globalFacilitiesConfig

  case buildingType
  of "Shipyard":
    return facilitiesConfig.shipyard.build_cost
  of "Spaceport":
    return facilitiesConfig.spaceport.build_cost
  of "Starbase":
    return constructionConfig.starbase_cost
  of "GroundBattery":
    return constructionConfig.ground_battery_cost
  of "FighterSquadron":
    return constructionConfig.fighter_squadron_cost
  else:
    return 50  # Default for undefined buildings

proc getBuildingTime*(buildingType: string): int =
  ## Get construction time for building type from config
  let constructionConfig = globalConstructionConfig.construction
  let facilitiesConfig = globalFacilitiesConfig

  case buildingType
  of "Shipyard":
    return facilitiesConfig.shipyard.build_time
  of "Spaceport":
    return facilitiesConfig.spaceport.build_time
  of "Starbase":
    return constructionConfig.starbase_turns
  of "GroundBattery":
    return constructionConfig.ground_battery_turns
  of "FighterSquadron":
    return 1
  else:
    return 1  # Default 1 turn

proc requiresSpaceport*(buildingType: string): bool =
  ## Check if building requires a spaceport
  let facilitiesConfig = globalFacilitiesConfig

  case buildingType
  of "Shipyard":
    return facilitiesConfig.shipyard.requires_spaceport
  else:
    return false

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
  if colony.underConstruction.isSome:
    return false  # Already building something

  colony.underConstruction = some(project)
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
