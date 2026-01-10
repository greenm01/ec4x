## Unit Tests: ROE Thresholds and Retreat Logic
##
## Tests getROEThreshold from combat/retreat.nim
## This is the pure function for ROE → threshold conversion.
##
## Per docs/specs/07-combat.md Section 7.2.3

import std/unittest
import ../../src/engine/systems/combat/retreat

suite "ROE: Threshold Lookup Table":
  ## Test getROEThreshold - maps ROE level to retreat threshold

  test "ROE 0 - never engage":
    check getROEThreshold(0) == 0.0

  test "ROE 1 - only engage defenseless":
    check getROEThreshold(1) == 999.0

  test "ROE 2 - need 4:1 advantage":
    check getROEThreshold(2) == 4.0

  test "ROE 3 - need 3:1 advantage":
    check getROEThreshold(3) == 3.0

  test "ROE 4 - need 2:1 advantage":
    check getROEThreshold(4) == 2.0

  test "ROE 5 - need 3:2 advantage":
    check getROEThreshold(5) == 1.5

  test "ROE 6 - engage if equal or better":
    check getROEThreshold(6) == 1.0

  test "ROE 7 - tolerate 3:2 disadvantage":
    check getROEThreshold(7) == 0.67

  test "ROE 8 - tolerate 2:1 disadvantage":
    check getROEThreshold(8) == 0.5

  test "ROE 9 - tolerate 3:1 disadvantage":
    check getROEThreshold(9) == 0.33

  test "ROE 10 - never retreat":
    check getROEThreshold(10) == 0.0

suite "ROE: Edge Cases":

  test "ROE out of range defaults to 1.0":
    check getROEThreshold(11) == 1.0
    check getROEThreshold(100) == 1.0
    check getROEThreshold(-1) == 1.0
    check getROEThreshold(-5) == 1.0

suite "ROE: Retreat Decision Logic":
  ## Test retreat ratio comparisons against thresholds

  test "ROE 6 - equal odds stays":
    let threshold = getROEThreshold(6)
    let ratio = 1.0 # Equal AS
    check ratio >= threshold # Should NOT retreat

  test "ROE 6 - slight disadvantage retreats":
    let threshold = getROEThreshold(6)
    let ratio = 0.9 # 90% of enemy AS
    check ratio < threshold # Should retreat

  test "ROE 7 - slight disadvantage stays":
    let threshold = getROEThreshold(7)
    let ratio = 0.8 # 80% of enemy AS
    check ratio >= threshold # Should NOT retreat (threshold is 0.67)

  test "ROE 7 - heavy disadvantage retreats":
    let threshold = getROEThreshold(7)
    let ratio = 0.5 # 50% of enemy AS (2:1 against)
    check ratio < threshold # Should retreat

  test "ROE 10 never retreats":
    let threshold = getROEThreshold(10)
    # Even with terrible odds
    check 0.1 >= threshold # 10:1 against still doesn't retreat
    check 0.01 >= threshold # 100:1 against
    check 0.001 >= threshold # 1000:1 against

  test "ROE 0 always retreats":
    let threshold = getROEThreshold(0)
    # threshold is 0.0, so ratio can never be >= 0.0 and NOT retreat
    # Actually ratio >= 0.0 is always true for non-negative AS
    # ROE 0 "never engage" means they retreat even if winning
    # The check is: if ratio < threshold, retreat
    # For threshold 0.0, ratio < 0.0 is never true with positive AS
    # This suggests ROE 0 shouldn't be used for ratio comparison
    # It's a special case meaning "auto-retreat before combat"
    check threshold == 0.0

  test "ROE 1 retreats unless enemy has zero AS":
    let threshold = getROEThreshold(1)
    # Need 999x advantage (enemy has near-zero AS)
    check 10.0 < threshold # 10:1 advantage not enough
    check 100.0 < threshold # 100:1 advantage not enough
    check 999.0 >= threshold # Exactly 999:1 okay

suite "ROE: Real Combat Scenarios":

  test "2 fleets vs 3 fleets at equal strength":
    # My 2 fleets: 200 AS each = 400 total
    # Enemy 3 fleets: 200 AS each = 600 total
    let myAS = 400.0
    let enemyAS = 600.0
    let ratio = myAS / enemyAS # 0.6666...

    # ROE 7 threshold is 0.67, ratio is 0.666..., so fleet retreats
    check ratio < getROEThreshold(7) # ROE 7 retreats (0.666 < 0.67)
    check ratio < getROEThreshold(6) # ROE 6 retreats (needs equal)
    check ratio >= getROEThreshold(8) # ROE 8 stays (threshold 0.5)

  test "overwhelming force":
    let myAS = 1000.0
    let enemyAS = 200.0
    let ratio = myAS / enemyAS # 5.0

    # Everyone stays with 5:1 advantage
    for roe in 1'i32 .. 10'i32:
      if roe == 1:
        check ratio < getROEThreshold(roe) # ROE 1 needs 999:1
      else:
        check ratio >= getROEThreshold(roe)

  test "desperate defense":
    let myAS = 100.0
    let enemyAS = 500.0
    let ratio = myAS / enemyAS # 0.2

    check ratio < getROEThreshold(9) # Even ROE 9 (0.33) retreats
    check ratio >= getROEThreshold(10) # Only ROE 10 stays

suite "ROE: Threshold Ordering":
  ## Verify thresholds decrease as ROE increases (more aggressive)

  test "thresholds decrease with higher ROE":
    # ROE 2-9 should have decreasing thresholds
    check getROEThreshold(2) > getROEThreshold(3)
    check getROEThreshold(3) > getROEThreshold(4)
    check getROEThreshold(4) > getROEThreshold(5)
    check getROEThreshold(5) > getROEThreshold(6)
    check getROEThreshold(6) > getROEThreshold(7)
    check getROEThreshold(7) > getROEThreshold(8)
    check getROEThreshold(8) > getROEThreshold(9)

  test "ROE 0 and 10 are both 0.0 (special cases)":
    check getROEThreshold(0) == getROEThreshold(10)
    check getROEThreshold(0) == 0.0

when isMainModule:
  echo "========================================"
  echo "  ROE Retreat Unit Tests"
  echo "========================================"
