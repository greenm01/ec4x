## Unit tests for C2 Pool Capacity System
##
## Tests the C2 Pool calculation, logistical strain penalties, and fleet status modifiers
## per assets.md:2.3.3.3-2.3.3.4
##
## **Note:** These tests focus on pure calculation functions. Some tests require
## gameConfig to be initialized, so we use the engine's initialization.

import std/unittest
import ../../src/engine/systems/capacity/c2_pool
import ../../src/engine/engine  # For initialization
import ../../src/engine/globals  # For gameConfig access

suite "C2 Pool Capacity Tests":
  # Initialize configs once before running tests
  setup:
    discard newGame()  # This loads all configs
  test "calculateC2Pool: basic formula (IU × 0.5) + SC bonus":
    # Test with no SC tech (0 bonus)
    check calculateC2Pool(totalHouseIU = 1000, scLevel = 0) == 500

    # Test with SC I (+50)
    check calculateC2Pool(totalHouseIU = 1000, scLevel = 1) == 550

    # Test with SC II (+60)
    check calculateC2Pool(totalHouseIU = 1000, scLevel = 2) == 560

    # Test with SC V (+125)
    check calculateC2Pool(totalHouseIU = 1000, scLevel = 5) == 625

  test "calculateC2Pool: edge cases":
    # Zero IU
    check calculateC2Pool(totalHouseIU = 0, scLevel = 1) == 50

    # Large IU
    check calculateC2Pool(totalHouseIU = 10000, scLevel = 5) == 5125

    # Odd IU (tests floor operation)
    check calculateC2Pool(totalHouseIU = 1001, scLevel = 0) == 500

  test "calculateLogisticalStrain: basic formula (excess × 0.5)":
    # Within capacity (no strain)
    check calculateLogisticalStrain(totalCC = 100, c2Pool = 150) == 0

    # Exactly at capacity (no strain)
    check calculateLogisticalStrain(totalCC = 150, c2Pool = 150) == 0

    # 50 CC over capacity
    check calculateLogisticalStrain(totalCC = 200, c2Pool = 150) == 25

    # 100 CC over capacity
    check calculateLogisticalStrain(totalCC = 250, c2Pool = 150) == 50

  test "calculateLogisticalStrain: edge cases":
    # Far below capacity
    check calculateLogisticalStrain(totalCC = 0, c2Pool = 1000) == 0

    # Massive overage
    check calculateLogisticalStrain(totalCC = 2000, c2Pool = 100) == 950

    # Odd excess (tests floor operation)
    check calculateLogisticalStrain(totalCC = 151, c2Pool = 150) == 0

  # Note: Fleet status CC modifiers and analyzeC2Capacity are tested
  # in integration tests since they require full GameState setup

  test "SC tech bonus values from config":
    # These test that the config values are correctly read
    # Assumes gameConfig is properly initialized

    # SC I: +50
    check calculateC2Pool(0, 1) == 50

    # SC II: +60
    check calculateC2Pool(0, 2) == 60

    # SC III: +75
    check calculateC2Pool(0, 3) == 75

    # SC IV: +90
    check calculateC2Pool(0, 4) == 90

    # SC V: +125
    check calculateC2Pool(0, 5) == 125

  test "IU contribution formula (× 0.5)":
    # Verify the 0.5 multiplier is correctly applied
    check calculateC2Pool(100, 0) == 50
    check calculateC2Pool(200, 0) == 100
    check calculateC2Pool(500, 0) == 250
    check calculateC2Pool(1000, 0) == 500
    check calculateC2Pool(2000, 0) == 1000

  test "logistical strain scales linearly with excess":
    # Verify the 0.5 multiplier on excess is linear
    let c2Pool = 100

    check calculateLogisticalStrain(110, c2Pool) == 5    # 10 excess
    check calculateLogisticalStrain(120, c2Pool) == 10   # 20 excess
    check calculateLogisticalStrain(150, c2Pool) == 25   # 50 excess
    check calculateLogisticalStrain(200, c2Pool) == 50   # 100 excess

  test "no negative logistical strain":
    # Verify max(0, excess) prevents negative costs
    check calculateLogisticalStrain(0, 1000) == 0
    check calculateLogisticalStrain(50, 1000) == 0
    check calculateLogisticalStrain(999, 1000) == 0
    check calculateLogisticalStrain(1000, 1000) == 0
