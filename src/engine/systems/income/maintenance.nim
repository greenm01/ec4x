## Maintenance and Upkeep System
##
## Fleet maintenance, infrastructure upkeep, repairs per economy.md:3.9
##
## Maintenance costs (economy.md:3.9):
## - Ships have maintenance costs based on class/tech (ships.toml)
## - Buildings have upkeep (construction.toml, facilities.toml)
## - Damaged infrastructure requires repair (construction.toml)

import ../../types/[game_state, units, fleet, production]
import
  ../../config/
    [construction_config, facilities_config, ground_units_config, combat_config]
import ../../state/iterators

export production.MaintenanceReport
# NOTE: Don't export Colony to avoid ambiguity - importers should use game_state directly
export fleet.FleetStatus

## Ship Maintenance Costs (economy.md:3.9)

proc getShipMaintenanceCost*(
    shipClass: ShipClass,
    isCrippled: bool,
    fleetStatus: FleetStatus = FleetStatus.Active,
): int =
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
    # Per combat.toml: crippled_maintenance_multiplier = 0.5
    return int(
      float(baseCost) * globalCombatConfig.damage_rules.crippled_maintenance_multiplier
    )
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
  return globalFacilitiesConfig.facilities[FacilityClass.Spaceport].upkeep_cost

proc getShipyardUpkeep*(): int =
  ## Get upkeep cost for shipyard per turn
  ## Per facilities.toml and construction.toml
  return globalFacilitiesConfig.facilities[FacilityClass.Shipyard].upkeep_cost

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
  return globalGroundUnitsConfig.units[GroundClass.Army].upkeep_cost

proc getMarineUpkeep*(): int =
  ## Get upkeep cost for marine division per turn
  ## Per ground_units.toml
  return globalGroundUnitsConfig.units[GroundClass.Marine].upkeep_cost

proc getBuildingMaintenance*(buildingType: string): int =
  ## Get maintenance cost for building (legacy compatibility)
  ## Use specific functions above for new code
  case buildingType
  of "Shipyard":
    return getShipyardUpkeep()
  of "Spaceport":
    return getSpaceportUpkeep()
  of "ResearchLab":
    # NOTE: Research labs are not implemented as physical buildings
    # The game uses TRP (Technology Research Points) for research instead
    # This is a legacy case preserved for backward compatibility
    return 4
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

proc calculateHouseMaintenanceCost*(state: GameState, houseId: HouseId): int =
  ## Calculate total maintenance cost for a house (fleets + colonies)
  ## This is a PURE calculation function for AI budget planning
  ## Does NOT deduct from treasury - just calculates the cost
  ##
  ## Used by AI to reserve maintenance budget before allocating to construction
  result = 0

  # Fleet maintenance using entity managers
  for fleet in state.fleetsOwned(houseId):
    var fleetData: seq[(ShipClass, bool)] = @[]

    # Iterate over squadron IDs
    for squadronId in fleet.squadrons:
      if squadronId notin state.squadrons.entities.index:
        continue

      let squadronIdx = state.squadrons.entities.index[squadronId]
      let squadron = state.squadrons.entities.data[squadronIdx]

      # Add flagship
      if squadron.flagshipId in state.ships.entities.index:
        let flagshipIdx = state.ships.entities.index[squadron.flagshipId]
        let flagship = state.ships.entities.data[flagshipIdx]
        fleetData.add((flagship.shipClass, flagship.isCrippled))

      # Add escort ships
      for shipId in squadron.ships:
        if shipId notin state.ships.entities.index:
          continue
        let shipIdx = state.ships.entities.index[shipId]
        let ship = state.ships.entities.data[shipIdx]
        fleetData.add((ship.shipClass, ship.isCrippled))

    result += calculateFleetMaintenance(fleetData)

  # Colony maintenance (facilities, ground forces)
  for colony in state.coloniesOwned(houseId):
    result += calculateColonyUpkeep(colony)

## Infrastructure Repair

proc calculateRepairCost*(damage: float): int =
  ## Calculate cost to repair infrastructure damage
  ## Per operations.md:6.2.6 - bombardment damages infrastructure
  ##
  ## Formula: damage * 100 PP
  ## Example: 0.1 damage (10%) = 10 PP to repair
  ## This represents the PP cost to restore damaged infrastructure
  return int(damage * 100.0)

proc applyRepair*(colony: var Colony, repairPoints: int): float =
  ## Apply repair points to damaged infrastructure
  ## Returns amount of damage repaired
  if colony.infrastructureDamage <= 0.0:
    return 0.0

  # Convert repair PP to damage reduction
  # Rate: 100 PP repairs 1.0 (100%) damage
  # This is the inverse of calculateRepairCost
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
  ## - Infrastructure damage (implemented below)
  ## - Production loss (applied via infrastructureDamage modifier)
  ## - Prestige penalty (handled by maintenance_shortfall.nim)
  ##
  ## Full shortfall cascade system in maintenance_shortfall.nim

  if shortfall > 0:
    let damageAmount = float(shortfall) / 1000.0 # 1% damage per 10 PP shortfall
    colony.infrastructureDamage = min(1.0, colony.infrastructureDamage + damageAmount)
