## Unit Tests: Tech Effect Calculations
##
## Tests pure functions from tech/effects.nim
## These functions calculate bonuses and multipliers based on tech levels.
##
## Per economy.md:4.0

import std/[unittest, math]
import ../../src/engine/systems/tech/effects

# Load config for config-dependent functions
import ../../src/engine/globals
import ../../src/engine/config/engine as config_engine

# Initialize config once for all tests
gameConfig = config_engine.loadGameConfig()

suite "Tech Effects: Economic Level (EL)":
  ## Test EL bonus calculations per economy.md:4.2

  test "EL 0 gives 0% bonus":
    check economicBonus(0) == 0.0

  test "EL 1 gives 5% bonus":
    check abs(economicBonus(1) - 0.05) < 0.001

  test "EL 5 gives 25% bonus":
    check abs(economicBonus(5) - 0.25) < 0.001

  test "EL 10 gives 50% bonus (cap)":
    check abs(economicBonus(10) - 0.50) < 0.001

  test "EL 11 is capped at 50%":
    check abs(economicBonus(11) - 0.50) < 0.001

  test "EL 20 is still capped at 50%":
    check abs(economicBonus(20) - 0.50) < 0.001

  test "applyEconomicBonus multiplies correctly":
    check applyEconomicBonus(100, 0) == 100 # 100 * 1.0
    check applyEconomicBonus(100, 1) == 105 # 100 * 1.05
    check applyEconomicBonus(100, 10) == 150 # 100 * 1.50
    check applyEconomicBonus(1000, 5) == 1250 # 1000 * 1.25

suite "Tech Effects: Weapons Tech (WEP)":
  ## Test WEP bonus calculations per economy.md:4.6

  test "WEP 0 gives 0% bonus":
    check weaponsBonus(0) == 0.0

  test "WEP 1 gives 10% bonus":
    check abs(weaponsBonus(1) - 0.10) < 0.001

  test "WEP 5 gives 50% bonus":
    check abs(weaponsBonus(5) - 0.50) < 0.001

  test "WEP 10 gives 100% bonus":
    check abs(weaponsBonus(10) - 1.00) < 0.001

  test "WEP 15 gives 150% bonus":
    check abs(weaponsBonus(15) - 1.50) < 0.001

  test "applyWeaponsBonus to Attack Strength":
    check applyWeaponsBonus(100, 0) == 100 # 100 * 1.0
    check applyWeaponsBonus(100, 1) == 110 # 100 * 1.1
    check applyWeaponsBonus(100, 5) == 150 # 100 * 1.5
    check applyWeaponsBonus(100, 10) == 200 # 100 * 2.0

  test "applyDefenseBonus to Defense Strength":
    check applyDefenseBonus(50, 0) == 50
    check applyDefenseBonus(50, 2) == 60 # 50 * 1.2
    check applyDefenseBonus(50, 5) == 75 # 50 * 1.5

suite "Tech Effects: Construction Tech (CST)":
  ## Test CST capacity multipliers per economy.md:4.5

  test "CST 1 gives 1.0x multiplier (base)":
    check abs(getConstructionCapacityMultiplier(1) - 1.0) < 0.001

  test "CST 2 gives 1.1x multiplier":
    check abs(getConstructionCapacityMultiplier(2) - 1.10) < 0.001

  test "CST 5 gives 1.4x multiplier":
    check abs(getConstructionCapacityMultiplier(5) - 1.40) < 0.001

  test "CST 10 gives 1.9x multiplier":
    check abs(getConstructionCapacityMultiplier(10) - 1.90) < 0.001

  test "dock capacity multiplier uses config":
    # Per spec: CST I = 1.0x, CST II = 1.1x, ... CST X = 1.9x
    # Formula: baseModifier + (CST - 1) * incrementPerLevel
    # Config: baseModifier=1.0, incrementPerLevel=0.10
    let mult1 = getDockCapacityMultiplier(1)
    let mult2 = getDockCapacityMultiplier(2)
    let mult5 = getDockCapacityMultiplier(5)
    check abs(mult1 - 1.0) < 0.001 # CST 1 = 1.0x
    check abs(mult2 - 1.1) < 0.001 # CST 2 = 1.1x
    check mult5 > mult2 # Higher CST = higher multiplier

  test "calculateEffectiveDocks":
    # CST 1 should give base docks (1.0x)
    check calculateEffectiveDocks(10, 1) == 10

    # CST 5 should give 1.4x docks (per spec table)
    let docks5 = calculateEffectiveDocks(10, 5)
    check docks5 == 14 # 10 * 1.4 = 14

suite "Tech Effects: Terraforming (TER)":
  ## Test terraforming costs and requirements per economy.md:4.7

  test "terraforming base costs by planet class":
    check getTerraformingBaseCost(1) == 60 # Extreme -> Desolate
    check getTerraformingBaseCost(2) == 180 # Desolate -> Hostile
    check getTerraformingBaseCost(3) == 500 # Hostile -> Harsh
    check getTerraformingBaseCost(4) == 1000 # Harsh -> Benign
    check getTerraformingBaseCost(5) == 1500 # Benign -> Lush
    check getTerraformingBaseCost(6) == 2000 # Lush -> Eden

  test "Eden (class 7) cannot be improved":
    check getTerraformingBaseCost(7) == 0

  test "terraforming speed is always 1 turn":
    check getTerraformingSpeed(1) == 1
    check getTerraformingSpeed(5) == 1
    check getTerraformingSpeed(7) == 1

  test "canTerraform requires TER level >= target class":
    # Need TER 2 to terraform class 1 -> 2
    check canTerraform(1, 2) == true
    check canTerraform(1, 1) == false

    # Need TER 5 to terraform class 4 -> 5
    check canTerraform(4, 5) == true
    check canTerraform(4, 4) == false

    # Need TER 7 to terraform class 6 -> 7
    check canTerraform(6, 7) == true
    check canTerraform(6, 6) == false

  test "Eden cannot be terraformed further":
    check canTerraform(7, 7) == false
    check canTerraform(7, 10) == false

suite "Tech Effects: Electronic Intelligence (ELI)":
  ## Test ELI counter-cloak bonus

  test "ELI counter-cloak bonus":
    check getELICounterCloakBonus(0) == 0
    check getELICounterCloakBonus(1) == 0 # 1 div 2 = 0
    check getELICounterCloakBonus(2) == 1 # 2 div 2 = 1
    check getELICounterCloakBonus(4) == 2
    check getELICounterCloakBonus(10) == 5
    check getELICounterCloakBonus(15) == 7

suite "Tech Effects: Carrier Operations (ACO)":
  ## Test carrier capacity by ACO level per economy.md:4.13

  test "CV capacity by ACO level":
    check getCarrierCapacityCV(1) == 3 # ACO I
    check getCarrierCapacityCV(2) == 4 # ACO II
    check getCarrierCapacityCV(3) == 5 # ACO III

  test "CX capacity by ACO level":
    check getCarrierCapacityCX(1) == 5 # ACO I
    check getCarrierCapacityCX(2) == 6 # ACO II
    check getCarrierCapacityCX(3) == 8 # ACO III

  test "ACO beyond level 3 uses level 3 values":
    check getCarrierCapacityCV(4) == 5
    check getCarrierCapacityCV(10) == 5
    check getCarrierCapacityCX(4) == 8
    check getCarrierCapacityCX(10) == 8

suite "Tech Effects: Strategic Command (SC)":
  ## Test SC fleet limit calculations per docs/specs/04-research_development.md

  test "SC scales with map size":
    # Small map
    let smallFleets = getMaxCombatFleets(scLevel = 5, totalSystems = 36,
        playerCount = 4)
    # Medium map
    let mediumFleets = getMaxCombatFleets(scLevel = 5, totalSystems = 92,
        playerCount = 4)
    # Large map
    let largeFleets = getMaxCombatFleets(scLevel = 5, totalSystems = 156,
        playerCount = 4)

    check mediumFleets > smallFleets
    check largeFleets > mediumFleets

  test "SC level affects base fleet count":
    let sc1 = getMaxCombatFleets(scLevel = 1, totalSystems = 92, playerCount = 4)
    let sc3 = getMaxCombatFleets(scLevel = 3, totalSystems = 92, playerCount = 4)
    let sc5 = getMaxCombatFleets(scLevel = 5, totalSystems = 92, playerCount = 4)

    check sc3 > sc1
    check sc5 > sc3

  test "more players reduces systems per player":
    let twoPlayers = getMaxCombatFleets(scLevel = 3, totalSystems = 92,
        playerCount = 2)
    let fourPlayers = getMaxCombatFleets(scLevel = 3, totalSystems = 92,
        playerCount = 4)
    let eightPlayers = getMaxCombatFleets(scLevel = 3, totalSystems = 92,
        playerCount = 8)

    # More players = fewer systems each = lower fleet limit
    check fourPlayers < twoPlayers
    check eightPlayers < fourPlayers

  test "invalid SC level returns fallback":
    let result = getMaxCombatFleets(scLevel = 99, totalSystems = 92,
        playerCount = 4)
    check result == 10 # Fallback to SC I base

when isMainModule:
  echo "========================================"
  echo "  Tech Effects Unit Tests"
  echo "========================================"
