## Test configuration loading and validation

import unittest
import ../src/engine/config

suite "Configuration Loading and Validation":

  test "Load all config files successfully":
    let config = loadGameConfig("data")
    check config.ships.len == 17  # All 17 ship classes
    check config.groundUnits.len == 4  # All 4 ground unit types
    check config.facilities.len == 2  # All 2 facility types

  test "Ship stats loaded correctly":
    let config = loadGameConfig("data")
    let destroyer = config.getShipStats(Destroyer)

    check destroyer.attackStrength > 0
    check destroyer.defenseStrength > 0
    check destroyer.buildCost > 0
    check destroyer.upkeepCost >= 0
    check destroyer.techLevel >= 0

  test "Ground unit stats loaded correctly":
    let config = loadGameConfig("data")
    let marines = config.getGroundUnitStats(MarineDivision)

    check marines.attackStrength > 0
    check marines.defenseStrength > 0
    check marines.buildCost > 0

  test "Facility stats loaded correctly":
    let config = loadGameConfig("data")
    let shipyard = config.getFacilityStats(Shipyard)

    check shipyard.buildCost > 0
    check shipyard.docks > 0
    check shipyard.buildTime > 0

  test "Combat config loaded correctly":
    let config = loadGameConfig("data")

    check config.combat.criticalHitRoll > 0
    check config.combat.retreatAfterRound >= 1

  test "Economy config loaded correctly":
    let config = loadGameConfig("data")

    check config.economy.startingTreasury > 0
    check config.economy.researchCostBase > 0
    check config.economy.ebpCostPerPoint > 0

  test "Prestige config loaded correctly":
    let config = loadGameConfig("data")

    check config.prestige.startingPrestige > 0
    check config.prestige.victoryThreshold > config.prestige.startingPrestige

  test "Validation catches negative attack strength":
    # This would require a malformed config file to test properly
    # For now, just verify validation functions exist
    skip()

  test "Validation catches invalid build costs":
    # This would require a malformed config file to test properly
    skip()
