## Maintenance and Upkeep System
##
## Fleet maintenance, infrastructure upkeep, repairs per economy.md:3.9
##
## Maintenance costs (economy.md:3.9):
## - Ships have maintenance costs based on class/tech (ships.toml)
## - Buildings have upkeep (construction.toml, facilities.toml)
## - Damaged infrastructure requires repair (construction.toml)

import std/options
import ../../types/[game_state, core, ship, fleet, colony, facilities, ground_unit]
import ../../globals
import ../../state/[iterators, engine as state_helpers]

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

  let stats = gameConfig.ships.ships[shipClass]
  let baseCost = int(stats.maintenanceCost)

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
      float(baseCost) * gameConfig.combat.damageRules.crippledMaintenanceMultiplier
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
  ## Per facilities.toml: maintenance = buildCost * maintenancePercent
  let facility = gameConfig.facilities.facilities[FacilityClass.Spaceport]
  return int(float(facility.buildCost) * facility.maintenancePercent)

proc getShipyardUpkeep*(): int =
  ## Get upkeep cost for shipyard per turn
  ## Per facilities.toml: maintenance = buildCost * maintenancePercent
  let facility = gameConfig.facilities.facilities[FacilityClass.Shipyard]
  return int(float(facility.buildCost) * facility.maintenancePercent)

proc getStarbaseUpkeep*(): int =
  ## Get upkeep cost for starbase per turn
  ## Per facilities.toml: maintenance = buildCost * maintenancePercent
  let facility = gameConfig.facilities.facilities[FacilityClass.Starbase]
  return int(float(facility.buildCost) * facility.maintenancePercent)

proc getGroundBatteryUpkeep*(): int =
  ## Get upkeep cost for ground battery per turn
  ## Ground batteries have no maintenance cost (defensive installations)
  return 0

proc getPlanetaryShieldUpkeep*(): int =
  ## Get upkeep cost for planetary shield per turn
  ## Planetary shields have no maintenance cost (passive defense)
  return 0

proc getArmyUpkeep*(): int =
  ## Get upkeep cost for army division per turn
  ## Per ground_units.toml
  return int(gameConfig.groundUnits.units[GroundClass.Army].maintenanceCost)

proc getMarineUpkeep*(): int =
  ## Get upkeep cost for marine division per turn
  ## Per ground_units.toml
  return int(gameConfig.groundUnits.units[GroundClass.Marine].maintenanceCost)

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

proc calculateColonyUpkeep*(colony: Colony): int =
  ## Calculate total upkeep for all facilities and defenses at colony
  ## TODO: This function needs to be rewritten to use entity managers
  ## For now, returning 0 until facility entity managers are accessible here
  result = 0

  # NOTE: Facilities are now in entity managers (state.spaceports, state.shipyards, etc.)
  # This function needs GameState parameter to query them properly
  # Legacy Colony type no longer has facility fields

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
      let squadronOpt = state_helpers.squadrons(state, squadronId)
      if squadronOpt.isNone:
        continue

      let squadron = squadronOpt.get()

      # Add flagship
      let flagshipOpt = state_helpers.ship(state, squadron.flagshipId)
      if flagshipOpt.isSome:
        let flagship = flagshipOpt.get()
        fleetData.add((flagship.shipClass, flagship.isCrippled))

      # Add escort ships
      for shipId in squadron.ships:
        let shipOpt = state_helpers.ship(state, shipId)
        if shipOpt.isSome:
          let ship = shipOpt.get()
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
