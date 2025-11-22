## Test detection table lookup functions
##
## Verifies that spy scout and raider detection tables can be queried correctly

import unittest2
import ../src/engine/config/espionage_config

suite "Detection Table Lookups":

  test "spy detection table - basic lookups":
    # Test all diagonal (same ELI level) entries
    let eli1_vs_spy1 = getSpyDetectionThreshold(1, 1)
    check eli1_vs_spy1 == [11, 13]

    let eli2_vs_spy2 = getSpyDetectionThreshold(2, 2)
    check eli2_vs_spy2 == [11, 13]

    let eli3_vs_spy3 = getSpyDetectionThreshold(3, 3)
    check eli3_vs_spy3 == [11, 13]

    let eli4_vs_spy4 = getSpyDetectionThreshold(4, 4)
    check eli4_vs_spy4 == [11, 13]

    let eli5_vs_spy5 = getSpyDetectionThreshold(5, 5)
    check eli5_vs_spy5 == [11, 13]

  test "spy detection table - detector advantage":
    # ELI2 vs ELI1 spy should be easier than ELI2 vs ELI2
    let eli2_vs_spy1 = getSpyDetectionThreshold(2, 1)
    check eli2_vs_spy1 == [6, 8]

    let eli2_vs_spy2 = getSpyDetectionThreshold(2, 2)
    check eli2_vs_spy2 == [11, 13]

    # Lower threshold = easier detection
    check eli2_vs_spy1[0] < eli2_vs_spy2[0]

  test "spy detection table - spy advantage":
    # ELI1 vs ELI2 spy should be harder than ELI1 vs ELI1
    let eli1_vs_spy1 = getSpyDetectionThreshold(1, 1)
    check eli1_vs_spy1 == [11, 13]

    let eli1_vs_spy2 = getSpyDetectionThreshold(1, 2)
    check eli1_vs_spy2 == [15, 17]

    # Higher threshold = harder detection
    check eli1_vs_spy2[0] > eli1_vs_spy1[0]

  test "spy detection table - impossible detection":
    # ELI1 vs ELI5 spy should be impossible (21+ on 1d20)
    let eli1_vs_spy5 = getSpyDetectionThreshold(1, 5)
    check eli1_vs_spy5 == [21, 21]

  test "spy detection table - best case scenario":
    # ELI5 vs ELI1 spy should be easiest detection
    let eli5_vs_spy1 = getSpyDetectionThreshold(5, 1)
    check eli5_vs_spy1 == [0, 1]

    # Should be easier than any other combination
    let eli4_vs_spy1 = getSpyDetectionThreshold(4, 1)
    check eli5_vs_spy1[0] <= eli4_vs_spy1[0]

  test "raider detection table - basic lookups":
    # Test all diagonal (same ELI/CLK level) entries
    let eli1_vs_clk1 = getRaiderDetectionThreshold(1, 1)
    check eli1_vs_clk1 == [14, 16]

    let eli2_vs_clk2 = getRaiderDetectionThreshold(2, 2)
    check eli2_vs_clk2 == [14, 16]

    let eli3_vs_clk3 = getRaiderDetectionThreshold(3, 3)
    check eli3_vs_clk3 == [14, 16]

    let eli4_vs_clk4 = getRaiderDetectionThreshold(4, 4)
    check eli4_vs_clk4 == [14, 16]

    let eli5_vs_clk5 = getRaiderDetectionThreshold(5, 5)
    check eli5_vs_clk5 == [14, 16]

  test "raider detection table - detector advantage":
    # ELI2 vs CLK1 should be easier than ELI2 vs CLK2
    let eli2_vs_clk1 = getRaiderDetectionThreshold(2, 1)
    check eli2_vs_clk1 == [10, 12]

    let eli2_vs_clk2 = getRaiderDetectionThreshold(2, 2)
    check eli2_vs_clk2 == [14, 16]

    # Lower threshold = easier detection
    check eli2_vs_clk1[0] < eli2_vs_clk2[0]

  test "raider detection table - cloak advantage":
    # ELI1 vs CLK2 should be harder than ELI1 vs CLK1
    let eli1_vs_clk1 = getRaiderDetectionThreshold(1, 1)
    check eli1_vs_clk1 == [14, 16]

    let eli1_vs_clk2 = getRaiderDetectionThreshold(1, 2)
    check eli1_vs_clk2 == [17, 19]

    # Higher threshold = harder detection
    check eli1_vs_clk2[0] > eli1_vs_clk1[0]

  test "raider detection table - impossible detection":
    # ELI1 vs CLK3+ should be impossible
    let eli1_vs_clk3 = getRaiderDetectionThreshold(1, 3)
    check eli1_vs_clk3 == [21, 21]

    let eli1_vs_clk4 = getRaiderDetectionThreshold(1, 4)
    check eli1_vs_clk4 == [21, 21]

    let eli1_vs_clk5 = getRaiderDetectionThreshold(1, 5)
    check eli1_vs_clk5 == [21, 21]

  test "raider detection table - best case scenario":
    # ELI5 vs CLK1 should be easiest detection
    let eli5_vs_clk1 = getRaiderDetectionThreshold(5, 1)
    check eli5_vs_clk1 == [1, 3]

    # Should be easier than any other combination
    let eli4_vs_clk1 = getRaiderDetectionThreshold(4, 1)
    check eli5_vs_clk1[0] <= eli4_vs_clk1[0]

  test "invalid ELI levels return impossible":
    # Invalid detector ELI
    let invalid_detector = getSpyDetectionThreshold(6, 1)
    check invalid_detector == [21, 21]

    # Invalid spy ELI
    let invalid_spy = getSpyDetectionThreshold(1, 6)
    check invalid_spy == [21, 21]

    # Both invalid
    let both_invalid = getSpyDetectionThreshold(0, 0)
    check both_invalid == [21, 21]

  test "threshold ranges are valid":
    # Check that min <= max for all valid combinations
    for detectorELI in 1..5:
      for spyELI in 1..5:
        let thresholds = getSpyDetectionThreshold(detectorELI, spyELI)
        check thresholds[0] <= thresholds[1]

    for detectorELI in 1..5:
      for cloakLevel in 1..5:
        let thresholds = getRaiderDetectionThreshold(detectorELI, cloakLevel)
        check thresholds[0] <= thresholds[1]
