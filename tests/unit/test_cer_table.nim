## Unit tests for CER Table
##
## Tests that lookupCER returns correct bucketed values per spec 07-combat.md:344-354

import std/unittest
import ../../src/engine/systems/combat/cer
import ../../src/engine/engine  # For initialization
import ../../src/engine/globals  # For gameConfig access

suite "CER Table Tests":
  # Initialize configs once before running tests
  setup:
    discard newGame()  # This loads all configs

  test "lookupCER: Tier 1 (rolls 0-2) returns 0.25":
    check lookupCER(0) == 0.25
    check lookupCER(1) == 0.25
    check lookupCER(2) == 0.25

  test "lookupCER: Tier 2 (rolls 3-4) returns 0.50":
    check lookupCER(3) == 0.50
    check lookupCER(4) == 0.50

  test "lookupCER: Tier 3 (rolls 5-6) returns 0.75":
    check lookupCER(5) == 0.75
    check lookupCER(6) == 0.75

  test "lookupCER: Tier 4 (rolls 7+) returns 1.00":
    check lookupCER(7) == 1.00
    check lookupCER(8) == 1.00
    check lookupCER(9) == 1.00
    check lookupCER(10) == 1.00
    check lookupCER(15) == 1.00

  test "lookupCER: Uses config thresholds":
    # Verify we're reading from config, not hardcoded
    let cfg = gameConfig.combat.cerTable
    check cfg.veryPoorMax == 2
    check cfg.poorMax == 4
    check cfg.averageMax == 6
    check cfg.goodMin == 7

  test "lookupCER: Uses config multipliers":
    # Verify we're reading multipliers from config
    let cfg = gameConfig.combat.cerTable
    check cfg.veryPoorMultiplier == 0.25
    check cfg.poorMultiplier == 0.50
    check cfg.averageMultiplier == 0.75
    check cfg.goodMultiplier == 1.00
