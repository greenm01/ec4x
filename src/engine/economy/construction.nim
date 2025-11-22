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

export types.ConstructionProject, types.CompletedProject, types.ConstructionType

## Ship Construction Costs (reference.md:9.2)

proc getShipConstructionCost*(shipClass: ShipClass): int =
  ## Get construction cost for ship class
  ## Per reference.md:9.2
  ##
  ## TODO: Load from reference.md table
  ## Placeholder costs
  case shipClass
  of ShipClass.Fighter:
    return 5
  of ShipClass.Raider:
    return 15
  of ShipClass.Destroyer:
    return 25
  of ShipClass.Cruiser, ShipClass.LightCruiser, ShipClass.HeavyCruiser:
    return 40
  of ShipClass.Carrier, ShipClass.SuperCarrier:
    return 50
  of ShipClass.Battleship, ShipClass.Battlecruiser, ShipClass.Dreadnought, ShipClass.SuperDreadnought:
    return 60
  of ShipClass.TroopTransport, ShipClass.ETAC:
    return 30
  of ShipClass.Scout:
    return 10
  of ShipClass.Starbase:
    return 200
  of ShipClass.PlanetBreaker:
    return 1000

proc getShipBuildTime*(shipClass: ShipClass): int =
  ## Get construction time in turns
  ## Per reference.md:9.2
  ##
  ## TODO: Load from reference.md table
  ## Placeholder: 1 turn per 10 PP cost
  return max(1, getShipConstructionCost(shipClass) div 10)

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

proc advanceConstruction*(colony: var Colony, productionPoints: int): Option[CompletedProject] =
  ## Apply production points to construction
  ## Returns completed project if finished
  if colony.underConstruction.isNone:
    return none(CompletedProject)

  var project = colony.underConstruction.get()

  # Apply production
  project.costPaid += productionPoints

  # Check if complete
  if project.costPaid >= project.costTotal:
    let completed = CompletedProject(
      colonyId: colony.systemId,
      projectType: project.projectType,
      itemId: project.itemId
    )

    # Clear construction slot
    colony.underConstruction = none(ConstructionProject)

    return some(completed)

  # Update progress
  project.turnsRemaining = max(1, (project.costTotal - project.costPaid) div max(1, productionPoints))
  colony.underConstruction = some(project)

  return none(CompletedProject)

proc cancelConstruction*(colony: var Colony): int =
  ## Cancel construction and return refund (50% of invested PP)
  ## Returns refunded PP amount
  if colony.underConstruction.isNone:
    return 0

  let project = colony.underConstruction.get()
  let refund = project.costPaid div 2

  colony.underConstruction = none(ConstructionProject)

  return refund

## Construction Queue Helpers

proc createShipProject*(shipClass: ShipClass): ConstructionProject =
  ## Create ship construction project
  let cost = getShipConstructionCost(shipClass)
  let turns = getShipBuildTime(shipClass)

  result = ConstructionProject(
    projectType: ConstructionType.Ship,
    itemId: $shipClass,
    costTotal: cost,
    costPaid: 0,
    turnsRemaining: turns
  )

proc createBuildingProject*(buildingType: string): ConstructionProject =
  ## Create building construction project
  let cost = getBuildingCost(buildingType)

  result = ConstructionProject(
    projectType: ConstructionType.Building,
    itemId: buildingType,
    costTotal: cost,
    costPaid: 0,
    turnsRemaining: cost div 10  # Estimate
  )

proc createIndustrialProject*(colony: Colony, units: int): ConstructionProject =
  ## Create IU investment project
  let costPerUnit = getIndustrialUnitCost(colony)
  let totalCost = costPerUnit * units

  result = ConstructionProject(
    projectType: ConstructionType.Industrial,
    itemId: $units & " IU",
    costTotal: totalCost,
    costPaid: 0,
    turnsRemaining: 1  # IU investment completes in 1 turn
  )
