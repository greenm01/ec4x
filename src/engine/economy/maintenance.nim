## Maintenance and Upkeep System
##
## Fleet maintenance, infrastructure upkeep, repairs per economy.md:3.9
##
## Maintenance costs (economy.md:3.9):
## - Ships have maintenance costs based on class/tech (ships.toml)
## - Buildings have upkeep (construction.toml, facilities.toml)
## - Damaged infrastructure requires repair (construction.toml)

import std/tables
import types
import ../../common/types/[core, units]
import ../config/[ships_config, construction_config, facilities_config, ground_units_config]
import ../squadron, ../gamestate, ../fleet

export types.MaintenanceReport
# NOTE: Don't export Colony to avoid ambiguity - importers should use gamestate directly
export fleet.FleetStatus

## Ship Maintenance Costs (economy.md:3.9)

proc getShipMaintenanceCost*(shipClass: ShipClass, isCrippled: bool, fleetStatus: FleetStatus = FleetStatus.Active): int =
  ## Get maintenance cost for ship per turn
  ## Per economy.md:3.9 and ships.toml upkeep_cost field
  ##
  ## Uses actual upkeep values from ships.toml config
  ## Crippled maintenance multiplier: combat.toml [damage_rules] crippled_maintenance_multiplier = 0.5
  ## Fleet status modifiers:
  ##   - Active: 100% maintenance (or 50% if crippled)
  ##   - Reserve: 50% maintenance
  ##   - Mothballed: 0% maintenance

  let stats = getShipStats(shipClass)
  let baseCost = stats.upkeepCost

  # Mothballed ships have zero maintenance
  if fleetStatus == FleetStatus.Mothballed:
    return 0

  # Reserve ships cost half to maintain
  if fleetStatus == FleetStatus.Reserve:
    return baseCost div 2

  # Active ships: full cost unless crippled
  if isCrippled:
    return baseCost div 2  # TODO: Load from combat.toml instead of hardcoding
  else:
    return baseCost

proc calculateFleetMaintenance*(ships: seq[(ShipClass, bool)]): int =
  ## Calculate total fleet maintenance
  ## Args: seq of (ship class, is crippled)
  result = 0
  for (shipClass, isCrippled) in ships:
    result += getShipMaintenanceCost(shipClass, isCrippled)

## Building and Facility Maintenance

proc getSpaceportUpkeep*(): int =
  ## Get upkeep cost for spaceport per turn
  ## Per facilities.toml and construction.toml
  return globalFacilitiesConfig.spaceport.upkeep_cost

proc getShipyardUpkeep*(): int =
  ## Get upkeep cost for shipyard per turn
  ## Per facilities.toml and construction.toml
  return globalFacilitiesConfig.shipyard.upkeep_cost

proc getStarbaseUpkeep*(): int =
  ## Get upkeep cost for starbase per turn
  ## Per construction.toml
  return globalConstructionConfig.upkeep.starbase_upkeep

proc getGroundBatteryUpkeep*(): int =
  ## Get upkeep cost for ground battery per turn
  ## Per construction.toml
  return globalConstructionConfig.upkeep.ground_battery_upkeep

proc getPlanetaryShieldUpkeep*(): int =
  ## Get upkeep cost for planetary shield per turn
  ## Per construction.toml (regardless of SLD level)
  return globalConstructionConfig.upkeep.planetary_shield_upkeep

proc getArmyUpkeep*(): int =
  ## Get upkeep cost for army division per turn
  ## Per ground_units.toml
  return globalGroundUnitsConfig.army.upkeep_cost

proc getMarineUpkeep*(): int =
  ## Get upkeep cost for marine division per turn
  ## Per ground_units.toml
  return globalGroundUnitsConfig.marine_division.upkeep_cost

proc getBuildingMaintenance*(buildingType: string): int =
  ## Get maintenance cost for building (legacy compatibility)
  ## Use specific functions above for new code
  case buildingType
  of "Shipyard":
    return getShipyardUpkeep()
  of "Spaceport":
    return getSpaceportUpkeep()
  of "ResearchLab":
    return 4  # TODO: Add research labs to config
  of "Starbase":
    return getStarbaseUpkeep()
  else:
    return 2

proc calculateColonyUpkeep*(colony: gamestate.Colony): int =
  ## Calculate total upkeep for all facilities and defenses at colony
  ## Includes: spaceports, shipyards, starbases, ground batteries,
  ##           planetary shields, armies, marines
  result = 0

  # Spaceports
  result += colony.spaceports.len * getSpaceportUpkeep()

  # Shipyards
  result += colony.shipyards.len * getShipyardUpkeep()

  # Starbases
  result += colony.starbases.len * getStarbaseUpkeep()

  # Ground batteries
  result += colony.groundBatteries * getGroundBatteryUpkeep()

  # Planetary shields (one per colony max)
  if colony.planetaryShieldLevel > 0:
    result += getPlanetaryShieldUpkeep()

  # Armies
  result += colony.armies * getArmyUpkeep()

  # Marines
  result += colony.marines * getMarineUpkeep()

## Infrastructure Repair

proc calculateRepairCost*(damage: float): int =
  ## Calculate cost to repair infrastructure damage
  ## Per operations.md:6.2.6 - bombardment damages infrastructure
  ##
  ## Repair cost scales with damage severity
  ## TODO: Define proper repair cost formula
  return int(damage * 100.0)

proc applyRepair*(colony: var Colony, repairPoints: int): float =
  ## Apply repair points to damaged infrastructure
  ## Returns amount of damage repaired
  if colony.infrastructureDamage <= 0.0:
    return 0.0

  # Convert repair PP to damage reduction
  # TODO: Define proper repair rate
  let repairAmount = float(repairPoints) / 100.0

  let actualRepair = min(repairAmount, colony.infrastructureDamage)
  colony.infrastructureDamage -= actualRepair

  return actualRepair

## Maintenance Shortfall (economy.md:3.11)

proc applyMaintenanceShortfall*(colony: var Colony, shortfall: int) =
  ## Apply consequences of maintenance shortfall
  ## Per economy.md:3.11
  ##
  ## Shortfall consequences:
  ## - Infrastructure damage
  ## - Production loss
  ## - Prestige penalty
  ##
  ## TODO: Implement proper shortfall mechanics
  ## For now, add infrastructure damage

  if shortfall > 0:
    let damageAmount = float(shortfall) / 1000.0  # 1% damage per 10 PP shortfall
    colony.infrastructureDamage = min(1.0, colony.infrastructureDamage + damageAmount)
