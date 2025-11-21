## Maintenance and Upkeep System
##
## Fleet maintenance, infrastructure upkeep, repairs per economy.md:3.9
##
## Maintenance costs (economy.md:3.9):
## - Ships have maintenance costs based on class/tech
## - Buildings have upkeep
## - Damaged infrastructure requires repair

import std/tables
import types
import ../../common/types/[core, units]

export types.MaintenanceReport

## Ship Maintenance Costs (economy.md:3.9)

proc getShipMaintenanceCost*(shipClass: ShipClass, isCrippled: bool): int =
  ## Get maintenance cost for ship per turn
  ## Per economy.md:3.9
  ##
  ## TODO: Load from reference.md table
  ## Placeholder costs
  let baseCost = case shipClass
    of ShipClass.Fighter:
      1
    of ShipClass.Scout:
      1
    of ShipClass.Raider:
      2
    of ShipClass.Destroyer:
      3
    of ShipClass.Cruiser, ShipClass.LightCruiser, ShipClass.HeavyCruiser:
      4
    of ShipClass.Carrier, ShipClass.SuperCarrier:
      5
    of ShipClass.Battleship, ShipClass.Battlecruiser, ShipClass.Dreadnought, ShipClass.SuperDreadnought:
      6
    of ShipClass.TroopTransport, ShipClass.ETAC:
      3
    of ShipClass.Starbase:
      10
    of ShipClass.PlanetBreaker:
      50

  # Crippled ships cost 50% more to maintain
  if isCrippled:
    return baseCost + (baseCost div 2)
  else:
    return baseCost

proc calculateFleetMaintenance*(ships: seq[(ShipClass, bool)]): int =
  ## Calculate total fleet maintenance
  ## Args: seq of (ship class, is crippled)
  result = 0
  for (shipClass, isCrippled) in ships:
    result += getShipMaintenanceCost(shipClass, isCrippled)

## Building Maintenance

proc getBuildingMaintenance*(buildingType: string): int =
  ## Get maintenance cost for building
  ##
  ## TODO: Define building maintenance costs
  ## Placeholder
  case buildingType
  of "Shipyard":
    return 5
  of "Spaceport":
    return 3
  of "ResearchLab":
    return 4
  of "Starbase":
    return 10
  else:
    return 2

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
