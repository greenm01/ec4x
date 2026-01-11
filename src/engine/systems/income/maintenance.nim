## Maintenance and Upkeep System
##
## Fleet maintenance, infrastructure upkeep, repairs per economy.md:3.9
##
## Maintenance costs (economy.md:3.9):
## - Ships have maintenance costs based on class/tech (ships.toml)
## - Buildings have upkeep (construction.toml, facilities.toml)
## - Damaged infrastructure requires repair (construction.toml)

import std/options
import ../../types/[game_state, core, ship, fleet, colony, facilities, ground_unit, combat]
import ../../globals
import ../../state/[iterators, engine]

export fleet.FleetStatus
export combat.CombatState

## Ship Maintenance Costs (economy.md:3.9)

proc shipMaintenanceCost*(
    shipClass: ShipClass,
    state: CombatState,
    fleetStatus: FleetStatus = FleetStatus.Active,
): int32 =
  ## Get maintenance cost for ship per turn
  ## Per economy.md:3.9 and ships.toml upkeep_cost field
  ##
  ## Uses actual upkeep values from ships.toml config
  ## Crippled maintenance multiplier: combat.toml [damage_rules] crippled_maintenance_multiplier = 0.5
  ## Fleet status modifiers:
  ##   - Active: 100% maintenance (or 50% if crippled)
  ##   - Reserve: 50% maintenance
  ##   - Mothballed: 10% maintenance (skeleton crews, system integrity)

  let stats = gameConfig.ships.ships[shipClass]
  let baseCost = stats.maintenanceCost

  # Apply fleet status modifiers
  # Per 02-assets.md section 2.3.3.5 and config/ships.kdl
  case fleetStatus
  of FleetStatus.Mothballed:
    return int32(
      float32(baseCost) * gameConfig.ships.mothballed.maintenanceMultiplier
    )
  of FleetStatus.Reserve:
    return int32(float32(baseCost) * gameConfig.ships.reserve.maintenanceMultiplier)
  of FleetStatus.Active:
    # Active ships: full cost unless crippled
    if state == CombatState.Crippled:
      # Per combat.toml: crippled_maintenance_multiplier
      return int32(
        float32(baseCost) * gameConfig.combat.damageRules.crippledMaintenanceMultiplier
      )
    else:
      return baseCost

proc calculateFleetMaintenance*(ships: seq[(ShipClass, CombatState)]): int32 =
  ## Calculate total fleet maintenance
  ## Args: seq of (ship class, combat state)
  result = 0
  for (shipClass, shipState) in ships:
    result += shipMaintenanceCost(shipClass, shipState)

## Building and Facility Maintenance

proc spaceportUpkeep*(): int32 =
  ## Get upkeep cost for spaceport per turn
  ## Per facilities.kdl: maintenance = buildCost * maintenancePercent
  let facility = gameConfig.facilities.facilities[FacilityClass.Spaceport]
  return int32(float32(facility.buildCost) * facility.maintenancePercent)

proc shipyardUpkeep*(): int32 =
  ## Get upkeep cost for shipyard per turn
  ## Per facilities.kdl: maintenance = buildCost * maintenancePercent
  let facility = gameConfig.facilities.facilities[FacilityClass.Shipyard]
  return int32(float32(facility.buildCost) * facility.maintenancePercent)

proc starbaseUpkeep*(): int32 =
  ## Get upkeep cost for starbase per turn
  ## Per facilities.kdl: maintenance = buildCost * maintenancePercent
  let facility = gameConfig.facilities.facilities[FacilityClass.Starbase]
  return int32(float32(facility.buildCost) * facility.maintenancePercent)

proc drydockUpkeep*(): int32 =
  ## Get upkeep cost for drydock per turn
  ## Per facilities.kdl: maintenance = buildCost * maintenancePercent
  ## Drydock: 150 PP * 5% = 7.5 PP/turn
  let facility = gameConfig.facilities.facilities[FacilityClass.Drydock]
  return int32(float32(facility.buildCost) * facility.maintenancePercent)

proc groundBatteryUpkeep*(): int32 =
  ## Get upkeep cost for ground battery per turn
  ## Ground batteries have no maintenance cost (defensive installations)
  return 0

proc planetaryShieldUpkeep*(): int32 =
  ## Get upkeep cost for planetary shield per turn
  ## Planetary shields have no maintenance cost (passive defense)
  return 0

proc armyUpkeep*(): int32 =
  ## Get upkeep cost for army division per turn
  ## Per ground_units.kdl
  return gameConfig.groundUnits.units[GroundClass.Army].maintenanceCost

proc marineUpkeep*(): int32 =
  ## Get upkeep cost for marine division per turn
  ## Per ground_units.kdl
  return gameConfig.groundUnits.units[GroundClass.Marine].maintenanceCost

proc calculateColonyUpkeep*(state: GameState, colony: Colony): int32 =
  ## Calculate total upkeep for all facilities and defenses at colony
  ## Uses entity managers to access Neorias and Kastras
  result = 0

  # Neoria upkeep (Spaceports, Shipyards, Drydocks)
  for neoriaId in colony.neoriaIds:
    let neoriaOpt = state.neoria(neoriaId)
    if neoriaOpt.isSome:
      let neoria = neoriaOpt.get()
      case neoria.neoriaClass
      of NeoriaClass.Spaceport:
        result += spaceportUpkeep()
      of NeoriaClass.Shipyard:
        result += shipyardUpkeep()
      of NeoriaClass.Drydock:
        result += drydockUpkeep()

  # Kastra upkeep (Starbases)
  for kastraId in colony.kastraIds:
    let kastraOpt = state.kastra(kastraId)
    if kastraOpt.isSome:
      result += starbaseUpkeep()

  # Ground unit upkeep
  for groundUnitId in colony.groundUnitIds:
    let unitOpt = state.groundUnit(groundUnitId)
    if unitOpt.isSome:
      let unit = unitOpt.get()
      case unit.stats.unitType
      of GroundClass.Army:
        result += armyUpkeep()
      of GroundClass.Marine:
        result += marineUpkeep()
      of GroundClass.GroundBattery:
        result += groundBatteryUpkeep()
      of GroundClass.PlanetaryShield:
        result += planetaryShieldUpkeep()

proc calculateHouseMaintenanceCost*(state: GameState, houseId: HouseId): int32 =
  ## Calculate total maintenance cost for a house (fleets + colonies)
  ## This is a PURE calculation function for AI budget planning
  ## Does NOT deduct from treasury - just calculates the cost
  ##
  ## Used by AI to reserve maintenance budget before allocating to construction
  result = 0

  # Fleet maintenance using entity managers
  for fleet in state.fleetsOwned(houseId):
    var fleetData: seq[(ShipClass, CombatState)] = @[]

    # Iterate over ships in fleet
    for shipId in fleet.ships:
      let shipOpt = state.ship(shipId)
      if shipOpt.isSome:
        let ship = shipOpt.get()
        fleetData.add((ship.shipClass, ship.state))

    result += calculateFleetMaintenance(fleetData)

  # Colony maintenance (facilities, ground forces)
  for colony in state.coloniesOwned(houseId):
    result += calculateColonyUpkeep(state, colony)

## Infrastructure Repair

proc calculateRepairCost*(damage: float32): int32 =
  ## Calculate cost to repair infrastructure damage
  ## Per operations.md:6.2.6 - bombardment damages infrastructure
  ##
  ## Formula: damage * 100 PP
  ## Example: 0.1 damage (10%) = 10 PP to repair
  ## This represents the PP cost to restore damaged infrastructure
  return int32(damage * 100.0'f32)

proc applyRepair*(colony: var Colony, repairPoints: int32): float32 =
  ## Apply repair points to damaged infrastructure
  ## Returns amount of damage repaired
  if colony.infrastructureDamage <= 0.0'f32:
    return 0.0'f32

  # Convert repair PP to damage reduction
  # Rate: 100 PP repairs 1.0 (100%) damage
  # This is the inverse of calculateRepairCost
  let repairAmount = float32(repairPoints) / 100.0'f32

  let actualRepair = min(repairAmount, colony.infrastructureDamage)
  colony.infrastructureDamage -= actualRepair

  return actualRepair

## Maintenance Shortfall (economy.md:3.11)

proc applyMaintenanceShortfall*(colony: var Colony, shortfall: int32) =
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
    let damageAmount = float32(shortfall) / 1000.0'f32 # 1% damage per 10 PP shortfall
    colony.infrastructureDamage = min(1.0'f32, colony.infrastructureDamage + damageAmount)
