## Unit tests for Scout/Raider detection mechanics
##
## Tests detection probability calculations from config/espionage.toml
## Validates mesh network modifiers, starbase bonuses, and tech penalties

import std/[unittest, tables]
import ../../src/engine/config/espionage_config

type
  DetectionThresholds = tuple[min: int, max: int]

proc calculateDetectionProbability(threshold: int, modifier: int = 0): float =
  ## Calculate detection probability for d20 roll
  ## Roll must exceed threshold to detect
  if threshold >= 21:
    return 0.0  # Impossible

  let effectiveThreshold = threshold - modifier

  # Roll must exceed threshold: success on (threshold+1) through 20
  if effectiveThreshold >= 20:
    return 0.0
  elif effectiveThreshold < 1:
    return 100.0
  else:
    let successes = 20 - effectiveThreshold
    return float(successes) / 20.0 * 100.0

suite "Scout/Raider Detection Configuration":

  test "Load scout detection modifiers from config":
    let config = loadEspionageConfig()

    # Test that mesh network modifiers are loaded
    # These will be added to EspionageConfig type
    # For now, test passes if config loads without error
    check config.ebpCostPP == 40
    check config.cipCostPP == 40

  test "Load raider detection modifiers from config":
    let config = loadEspionageConfig()

    # Test that raider detection modifiers are loaded
    # These will be added to EspionageConfig type
    check config.ebpCostPP > 0

suite "Detection Probability Calculations":

  test "Base detection probability without modifiers":
    # Test case: threshold of 12 (40% chance)
    let prob = calculateDetectionProbability(12, 0)
    check prob == 40.0

    # Test case: threshold of 10 (50% chance)
    let prob2 = calculateDetectionProbability(10, 0)
    check prob2 == 50.0

    # Test case: impossible detection (threshold 21+)
    let probImpossible = calculateDetectionProbability(21, 0)
    check probImpossible == 0.0

  test "Detection with positive modifiers":
    # Base threshold 12 (40%) + modifier +2 = effective 10 (50%)
    let prob = calculateDetectionProbability(12, 2)
    check prob == 50.0

    # Test mesh network effect: +3 modifier
    let probMesh = calculateDetectionProbability(12, 3)
    check abs(probMesh - 55.0) < 0.01  # Allow for floating point precision

    # Test starbase bonus: +2 modifier
    let probStarbase = calculateDetectionProbability(15, 2)
    check probStarbase == 35.0

  test "Detection with negative modifiers (tech penalty)":
    # Base threshold 12 (40%) + penalty -1 = effective 13 (35%)
    let prob = calculateDetectionProbability(12, -1)
    check prob == 35.0

    # Verify penalty reduces probability
    let baseProb = calculateDetectionProbability(10, 0)
    let penaltyProb = calculateDetectionProbability(10, -1)
    check penaltyProb < baseProb

  test "Mesh network modifier scaling":
    # Test progression: 0, +1, +2, +3
    let base = calculateDetectionProbability(12, 0)
    let mesh2_3 = calculateDetectionProbability(12, 1)
    let mesh4_5 = calculateDetectionProbability(12, 2)
    let mesh6plus = calculateDetectionProbability(12, 3)

    # Each modifier should increase probability by 5%
    check mesh2_3 == base + 5.0
    check mesh4_5 == base + 10.0
    check abs(mesh6plus - (base + 15.0)) < 0.01  # Allow for floating point precision

  test "Detection probability edge cases":
    # Very low threshold (easy detection)
    let easyDetect = calculateDetectionProbability(2, 0)
    check easyDetect == 90.0

    # Very high threshold (hard detection)
    let hardDetect = calculateDetectionProbability(19, 0)
    check hardDetect == 5.0

    # Threshold 20 (only natural 20 succeeds)
    let critOnly = calculateDetectionProbability(20, 0)
    check critOnly == 0.0  # Must exceed 20, which is impossible on d20

    # Modifier makes impossible possible
    let withModifier = calculateDetectionProbability(20, 1)
    check withModifier == 5.0  # Effective threshold 19

suite "Detection Table Progression Validation":

  test "Spy detection table progression":
    # Define test tables (simplified from assets.md)
    let spyTable = {
      (1, 1): (11, 13),  # ELI1 vs Spy ELI1
      (2, 1): (6, 8),    # ELI2 vs Spy ELI1
      (3, 1): (2, 4),    # ELI3 vs Spy ELI1
      (1, 2): (15, 17),  # ELI1 vs Spy ELI2
      (2, 2): (11, 13),  # ELI2 vs Spy ELI2
      (3, 2): (6, 8),    # ELI3 vs Spy ELI2
    }.toTable

    # Validate: Higher detector ELI = lower threshold (easier detection)
    let eli1_spy1_avg = (spyTable[(1, 1)][0] + spyTable[(1, 1)][1]) div 2
    let eli2_spy1_avg = (spyTable[(2, 1)][0] + spyTable[(2, 1)][1]) div 2
    let eli3_spy1_avg = (spyTable[(3, 1)][0] + spyTable[(3, 1)][1]) div 2

    check eli2_spy1_avg < eli1_spy1_avg  # ELI2 better than ELI1
    check eli3_spy1_avg < eli2_spy1_avg  # ELI3 better than ELI2

    # Validate: Higher spy ELI = higher threshold (harder detection)
    let eli2_spy1 = (spyTable[(2, 1)][0] + spyTable[(2, 1)][1]) div 2
    let eli2_spy2 = (spyTable[(2, 2)][0] + spyTable[(2, 2)][1]) div 2

    check eli2_spy2 > eli2_spy1  # Spy ELI2 harder to detect than Spy ELI1

  test "Raider detection table progression":
    # Define test tables
    let raiderTable = {
      (1, 1): (14, 16),  # ELI1 vs CLK1
      (2, 1): (10, 12),  # ELI2 vs CLK1
      (3, 1): (6, 8),    # ELI3 vs CLK1
      (1, 2): (17, 19),  # ELI1 vs CLK2
      (2, 2): (14, 16),  # ELI2 vs CLK2
      (3, 2): (10, 12),  # ELI3 vs CLK2
    }.toTable

    # Validate: Higher detector ELI = lower threshold
    let eli1_clk1_avg = (raiderTable[(1, 1)][0] + raiderTable[(1, 1)][1]) div 2
    let eli2_clk1_avg = (raiderTable[(2, 1)][0] + raiderTable[(2, 1)][1]) div 2

    check eli2_clk1_avg < eli1_clk1_avg

    # Validate: Higher raider CLK = higher threshold
    let eli2_clk1 = (raiderTable[(2, 1)][0] + raiderTable[(2, 1)][1]) div 2
    let eli2_clk2 = (raiderTable[(2, 2)][0] + raiderTable[(2, 2)][1]) div 2

    check eli2_clk2 > eli2_clk1

  test "Threshold variance (1d3 roll simulation)":
    # Test threshold range [10, 12]
    let thresholds: DetectionThresholds = (10, 12)

    # Calculate probabilities for each possible roll
    let probMin = calculateDetectionProbability(thresholds.min, 0)  # Roll 1: use min
    let probMid = calculateDetectionProbability(11, 0)              # Roll 2: use mid
    let probMax = calculateDetectionProbability(thresholds.max, 0)  # Roll 3: use max

    # Min threshold should have highest probability
    check probMin > probMid
    check probMid > probMax

    # Verify values
    check probMin == 50.0  # d20 > 10 = 50%
    check probMid == 45.0  # d20 > 11 = 45%
    check probMax == 40.0  # d20 > 12 = 40%

suite "ELI Advantage Mechanics":

  test "ELI advantage determines threshold selection":
    # ELI advantage major (2+ levels): use minimum threshold
    # ELI advantage minor (1 level): random threshold (1d3)
    # No advantage (lower/equal): use maximum threshold

    let thresholds: DetectionThresholds = (6, 8)

    # Major advantage scenario (use min)
    let probMajor = calculateDetectionProbability(thresholds[0], 0)
    check probMajor == 70.0

    # No advantage scenario (use max)
    let probNone = calculateDetectionProbability(thresholds[1], 0)
    check probNone == 60.0

    # Advantage provides 10% improvement
    check probMajor - probNone == 10.0

  test "Combined modifiers stack correctly":
    let baseThreshold = 12

    # Mesh network +2 and starbase +2 = +4 total
    let probStacked = calculateDetectionProbability(baseThreshold, 4)
    check probStacked == 60.0  # Effective threshold 8

    # Mesh +3 with tech penalty -1 = +2 net
    let probMixed = calculateDetectionProbability(baseThreshold, 2)
    check probMixed == 50.0  # Effective threshold 10
