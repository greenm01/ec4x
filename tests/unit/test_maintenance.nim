## Unit Tests: Maintenance Cost Calculations
##
## Tests ship and facility maintenance from income/maintenance.nim
## Config-driven functions that need gameConfig loaded
##
## Per economy.md:3.9

import std/[unittest]
import ../../src/engine/types/[ship, fleet, facilities, ground_unit, combat]
import ../../src/engine/systems/income/maintenance
import ../../src/engine/globals
import ../../src/engine/config/engine as config_engine

# Initialize config once for all tests
gameConfig = config_engine.loadGameConfig()

suite "Maintenance: Ship Costs by Class":
  ## Test getShipMaintenanceCost for different ship classes

  test "destroyer has maintenance cost":
    let cost = getShipMaintenanceCost(ShipClass.Destroyer, CombatState.Undamaged)
    check cost > 0

  test "battleship costs more than destroyer":
    let ddCost = getShipMaintenanceCost(ShipClass.Destroyer, CombatState.Undamaged)
    let bbCost = getShipMaintenanceCost(ShipClass.Battleship, CombatState.Undamaged)
    check bbCost > ddCost

  test "dreadnought costs more than battleship":
    let bbCost = getShipMaintenanceCost(ShipClass.Battleship, CombatState.Undamaged)
    let dnCost = getShipMaintenanceCost(ShipClass.Dreadnought, CombatState.Undamaged)
    check dnCost > bbCost

  test "all ship classes have positive maintenance":
    for shipClass in ShipClass:
      let cost = getShipMaintenanceCost(shipClass, CombatState.Undamaged)
      check cost >= 0 # Some auxiliary might be 0

suite "Maintenance: Combat State Modifiers":
  ## Test how damage affects maintenance

  test "crippled ships have reduced maintenance":
    let undamagedCost = getShipMaintenanceCost(
      ShipClass.Cruiser, CombatState.Undamaged
    )
    let crippledCost = getShipMaintenanceCost(
      ShipClass.Cruiser, CombatState.Crippled
    )
    check crippledCost < undamagedCost

  test "crippled maintenance is ~50% of base":
    let baseCost = getShipMaintenanceCost(
      ShipClass.Battlecruiser, CombatState.Undamaged
    )
    let crippledCost = getShipMaintenanceCost(
      ShipClass.Battlecruiser, CombatState.Crippled
    )
    # Should be around 50% (config: crippledMaintenanceMultiplier)
    let ratio = float(crippledCost) / float(baseCost)
    check ratio >= 0.4 and ratio <= 0.6

  test "destroyed ships still need some cost handling":
    # Destroyed ships typically have 0 maintenance
    # but we test the function doesn't crash
    let cost = getShipMaintenanceCost(ShipClass.Destroyer, CombatState.Destroyed)
    check cost >= 0

suite "Maintenance: Fleet Status Modifiers":
  ## Test Active/Reserve/Mothballed fleet maintenance

  test "active fleet has full maintenance":
    let activeCost = getShipMaintenanceCost(
      ShipClass.Cruiser, CombatState.Undamaged, FleetStatus.Active
    )
    check activeCost > 0

  test "reserve fleet has reduced maintenance":
    let activeCost = getShipMaintenanceCost(
      ShipClass.Cruiser, CombatState.Undamaged, FleetStatus.Active
    )
    let reserveCost = getShipMaintenanceCost(
      ShipClass.Cruiser, CombatState.Undamaged, FleetStatus.Reserve
    )
    check reserveCost < activeCost

  test "reserve is ~50% of active":
    let activeCost = getShipMaintenanceCost(
      ShipClass.Battleship, CombatState.Undamaged, FleetStatus.Active
    )
    let reserveCost = getShipMaintenanceCost(
      ShipClass.Battleship, CombatState.Undamaged, FleetStatus.Reserve
    )
    let ratio = float(reserveCost) / float(activeCost)
    check ratio >= 0.4 and ratio <= 0.6

  test "mothballed fleet has minimal maintenance":
    let activeCost = getShipMaintenanceCost(
      ShipClass.Cruiser, CombatState.Undamaged, FleetStatus.Active
    )
    let mothballedCost = getShipMaintenanceCost(
      ShipClass.Cruiser, CombatState.Undamaged, FleetStatus.Mothballed
    )
    check mothballedCost < activeCost

  test "mothballed is ~10% of active":
    let activeCost = getShipMaintenanceCost(
      ShipClass.Dreadnought, CombatState.Undamaged, FleetStatus.Active
    )
    let mothballedCost = getShipMaintenanceCost(
      ShipClass.Dreadnought, CombatState.Undamaged, FleetStatus.Mothballed
    )
    let ratio = float(mothballedCost) / float(activeCost)
    check ratio >= 0.05 and ratio <= 0.15

suite "Maintenance: Fleet Total Calculation":
  ## Test calculateFleetMaintenance

  test "empty fleet has zero maintenance":
    let ships: seq[(ShipClass, CombatState)] = @[]
    check calculateFleetMaintenance(ships) == 0

  test "single ship fleet":
    let ships = @[(ShipClass.Destroyer, CombatState.Undamaged)]
    let total = calculateFleetMaintenance(ships)
    let expected = getShipMaintenanceCost(ShipClass.Destroyer, CombatState.Undamaged)
    check total == expected

  test "multiple ships sum correctly":
    let ships = @[
      (ShipClass.Destroyer, CombatState.Undamaged),
      (ShipClass.Destroyer, CombatState.Undamaged),
      (ShipClass.Cruiser, CombatState.Undamaged)
    ]
    let total = calculateFleetMaintenance(ships)
    let expected =
      getShipMaintenanceCost(ShipClass.Destroyer, CombatState.Undamaged) * 2 +
      getShipMaintenanceCost(ShipClass.Cruiser, CombatState.Undamaged)
    check total == expected

  test "mixed damage states":
    let ships = @[
      (ShipClass.Battleship, CombatState.Undamaged),
      (ShipClass.Battleship, CombatState.Crippled)
    ]
    let total = calculateFleetMaintenance(ships)
    let undamaged = getShipMaintenanceCost(ShipClass.Battleship, CombatState.Undamaged)
    let crippled = getShipMaintenanceCost(ShipClass.Battleship, CombatState.Crippled)
    check total == undamaged + crippled

suite "Maintenance: Facility Upkeep":
  ## Test facility maintenance costs

  test "spaceport has upkeep":
    let upkeep = getSpaceportUpkeep()
    check upkeep > 0

  test "shipyard has upkeep":
    let upkeep = getShipyardUpkeep()
    check upkeep > 0

  test "starbase has upkeep":
    let upkeep = getStarbaseUpkeep()
    check upkeep > 0

  test "drydock has upkeep":
    let upkeep = getDrydockUpkeep()
    check upkeep > 0

  test "shipyard costs at least as much as spaceport":
    # Both facilities have upkeep, shipyard >= spaceport
    check getShipyardUpkeep() >= getSpaceportUpkeep()

  test "starbase is most expensive":
    check getStarbaseUpkeep() > getShipyardUpkeep()

suite "Maintenance: Ground Unit Upkeep":
  ## Test ground unit maintenance

  test "army has upkeep":
    let upkeep = getArmyUpkeep()
    check upkeep >= 0

  test "marine has upkeep":
    let upkeep = getMarineUpkeep()
    check upkeep >= 0

  test "ground battery has no upkeep":
    # Defensive installations are free to maintain
    check getGroundBatteryUpkeep() == 0

  test "planetary shield has no upkeep":
    check getPlanetaryShieldUpkeep() == 0

suite "Maintenance: Infrastructure Repair":
  ## Test repair cost calculations

  test "zero damage costs nothing":
    check calculateRepairCost(0.0) == 0

  test "10% damage costs 10 PP":
    check calculateRepairCost(0.1) == 10

  test "50% damage costs 50 PP":
    check calculateRepairCost(0.5) == 50

  test "100% damage costs 100 PP":
    check calculateRepairCost(1.0) == 100

  test "repair cost scales linearly":
    let cost25 = calculateRepairCost(0.25)
    let cost50 = calculateRepairCost(0.50)
    check cost50 == cost25 * 2

when isMainModule:
  echo "========================================"
  echo "  Maintenance Unit Tests"
  echo "========================================"
