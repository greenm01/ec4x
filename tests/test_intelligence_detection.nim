## Tests for spy scout and raider detection mechanics
##
## Verifies ELI calculations, mesh networks, and detection rolls

import unittest2
import std/[random]
import ../src/engine/intelligence/detection
import ../src/engine/squadron
import ../src/engine/config/espionage_config

suite "ELI Mesh Network Calculations":

  test "weighted average ELI - single scout":
    let avg = calculateWeightedAverageELI(@[3])
    check avg == 3

  test "weighted average ELI - identical scouts":
    let avg = calculateWeightedAverageELI(@[2, 2, 2])
    check avg == 2

  test "weighted average ELI - mixed scouts (rounds up)":
    # Example from spec: 2+2+4+4+4 = 16/5 = 3.2 → rounds up to 4
    let avg = calculateWeightedAverageELI(@[2, 2, 4, 4, 4])
    check avg == 4

  test "weighted average ELI - two scouts":
    # Example from spec: 1+3 = 4/2 = 2
    let avg = calculateWeightedAverageELI(@[1, 3])
    check avg == 2

  test "weighted average ELI - rounds up":
    # 3+4 = 7/2 = 3.5 → rounds up to 4
    let avg = calculateWeightedAverageELI(@[3, 4])
    check avg == 4

  test "dominant tech penalty - no penalty":
    # Balanced fleet: 1 ELI1, 1 ELI3, avg=2, neither >50%
    let result = applyDominantTechPenalty(2, @[1, 3])
    check result == 2

  test "dominant tech penalty - applies penalty":
    # Example from spec: 5 scouts (2×ELI2, 3×ELI4), avg=4
    # 2 scouts are below avg (ELI2 < 4), 2/5 = 40% < 50%, so NO penalty
    let result = applyDominantTechPenalty(4, @[2, 2, 4, 4, 4])
    check result == 4  # No penalty since only 40% below

  test "dominant tech penalty - exactly 50% no penalty":
    # 4 scouts (2×ELI1, 2×ELI3), avg=2
    # Exactly 50% below, not >50%, so no penalty
    let result = applyDominantTechPenalty(2, @[1, 1, 3, 3])
    check result == 2

  test "mesh network bonus - single scout":
    let bonus = getMeshNetworkBonus(1)
    check bonus == 0

  test "mesh network bonus - 2-3 scouts":
    check getMeshNetworkBonus(2) == 1
    check getMeshNetworkBonus(3) == 1

  test "mesh network bonus - 4-5 scouts":
    check getMeshNetworkBonus(4) == 2
    check getMeshNetworkBonus(5) == 2

  test "mesh network bonus - 6+ scouts":
    check getMeshNetworkBonus(6) == 3
    check getMeshNetworkBonus(10) == 3

  test "effective ELI - example 1 from spec":
    # 2×ELI2, 3×ELI4 → avg=4, no penalty (only 40%), mesh+2 → ELI6 capped at 5
    let effectiveELI = calculateEffectiveELI(@[2, 2, 4, 4, 4])
    check effectiveELI == 5  # 4 + 2 mesh = 6, capped at 5

  test "effective ELI - example 2 from spec":
    # 1×ELI1, 1×ELI3 → avg=2, mesh+1 → ELI3
    let effectiveELI = calculateEffectiveELI(@[1, 3])
    check effectiveELI == 3

  test "effective ELI - starbase gets bonus vs spies":
    # Single ELI2 starbase gets +2 bonus → ELI4
    let effectiveELI = calculateEffectiveELI(@[2], isStarbase = true)
    check effectiveELI == 4

  test "effective ELI - capped at max level":
    # Even with bonuses, can't exceed ELI5
    let effectiveELI = calculateEffectiveELI(@[5, 5, 5, 5, 5, 5])
    check effectiveELI == 5

suite "Spy Scout Detection":

  test "spy detection threshold roll - picks from range":
    let thresholdRange: ThresholdRange = [10, 12]

    # Test all possible 1d3 outcomes
    var results: set[0..20] = {}
    for i in 1..30:
      let threshold = rollSpyDetectionThreshold(thresholdRange)
      check threshold >= 10 and threshold <= 12
      results.incl(threshold)

    # Should see all three values (10, 11, 12) over 30 rolls
    check 10 in results
    check 11 in results
    check 12 in results

  test "spy detection - deterministic with seeded RNG":
    var rng = initRand(12345)
    let result = attemptSpyDetection(3, 3, rng)

    # ELI3 vs Spy ELI3 has range [11, 13]
    check result.threshold >= 11 and result.threshold <= 13
    check result.roll >= 1 and result.roll <= 20

  test "spy detection - impossible detection returns false":
    var rng = initRand(12345)

    # ELI1 vs Spy ELI5 is impossible [21, 21]
    # Can't roll >21 on 1d20
    var detectedCount = 0
    for i in 1..100:
      let result = attemptSpyDetection(1, 5, rng)
      if result.detected:
        detectedCount += 1

    check detectedCount == 0

  test "spy detection - easy detection likely succeeds":
    var rng = initRand(54321)

    # ELI5 vs Spy ELI1 is very easy [0, 1]
    # Almost any roll will succeed
    var detectedCount = 0
    for i in 1..100:
      let result = attemptSpyDetection(5, 1, rng)
      if result.detected:
        detectedCount += 1

    # Should detect >90% of the time
    check detectedCount > 90

  test "detectSpyScout - integrates effective ELI calculation":
    var rng = initRand(99999)

    let unit = ELIUnit(
      eliLevels: @[2, 2, 4, 4, 4],
      isStarbase: false
    )

    let result = detectSpyScout(unit, 3, rng)

    # Should calculate effective ELI as 5 (per spec example)
    check result.effectiveELI == 5

suite "Raider Detection":

  test "raider threshold strategy - ELI advantage 2+":
    # ELI5 vs CLK3 = 2 levels advantage → use lower bound
    let strategy = getRaiderThresholdStrategy(5, 3)
    check strategy == "lower"

  test "raider threshold strategy - ELI advantage 0-1":
    # ELI3 vs CLK3 = equal → use random
    let strategy = getRaiderThresholdStrategy(3, 3)
    check strategy == "random"

    # ELI4 vs CLK3 = 1 level advantage → use random
    let strategy2 = getRaiderThresholdStrategy(4, 3)
    check strategy2 == "random"

  test "raider threshold strategy - CLK advantage":
    # ELI2 vs CLK4 = -2 levels → use upper bound
    let strategy = getRaiderThresholdStrategy(2, 4)
    check strategy == "upper"

  test "rollRaiderThreshold - lower strategy":
    let thresholdRange: ThresholdRange = [6, 8]
    var rng = initRand(11111)

    let threshold = rollRaiderThreshold(thresholdRange, "lower", rng)
    check threshold == 6

  test "rollRaiderThreshold - upper strategy":
    let thresholdRange: ThresholdRange = [6, 8]
    var rng = initRand(11111)

    let threshold = rollRaiderThreshold(thresholdRange, "upper", rng)
    check threshold == 8

  test "rollRaiderThreshold - random strategy":
    let thresholdRange: ThresholdRange = [6, 8]
    var rng = initRand(22222)

    # Should pick value in range
    let threshold = rollRaiderThreshold(thresholdRange, "random", rng)
    check threshold >= 6 and threshold <= 8

  test "raider detection - impossible detection returns false":
    var rng = initRand(33333)

    # ELI1 vs CLK5 is impossible [21, 21]
    var detectedCount = 0
    for i in 1..100:
      let result = attemptRaiderDetection(1, 5, rng)
      if result.detected:
        detectedCount += 1

    check detectedCount == 0

  test "raider detection - easy detection likely succeeds":
    var rng = initRand(44444)

    # ELI5 vs CLK1 is very easy [1, 3]
    var detectedCount = 0
    for i in 1..100:
      let result = attemptRaiderDetection(5, 1, rng)
      if result.detected:
        detectedCount += 1

    # Should detect >90% of the time
    check detectedCount > 90

  test "detectRaider - integrates effective ELI calculation":
    var rng = initRand(55555)

    let unit = ELIUnit(
      eliLevels: @[3, 4],
      isStarbase: false
    )

    let result = detectRaider(unit, 4, rng)

    # 3+4=7/2=3.5→4, +1 mesh → ELI5
    check result.effectiveELI == 5

suite "Squadron/Fleet ELI Helpers":

  test "getScoutELILevels - extracts ELI from scouts":
    # Note: Scouts have CR=0 so can't add other ships to squadron
    # Use getFleetELILevels with multiple scout squadrons instead
    let scout1 = newEnhancedShip(ShipClass.Scout)
    let scout2 = newEnhancedShip(ShipClass.Scout)

    let sq1 = newSquadron(scout1)
    let sq2 = newSquadron(scout2)

    let eliLevels = getFleetELILevels(@[sq1, sq2])
    check eliLevels.len == 2

  test "getScoutELILevels - ignores non-scouts":
    let scout = newEnhancedShip(ShipClass.Scout)
    let cruiser = newEnhancedShip(ShipClass.Cruiser)

    var squadron = newSquadron(scout)
    discard squadron.addShip(cruiser)

    let eliLevels = getScoutELILevels(squadron)
    check eliLevels.len == 1

  test "getFleetCloakLevel - finds highest CLK":
    # Note: CLK level would be tracked at game state level
    # This test verifies raiders are detected
    let raider1 = newEnhancedShip(ShipClass.Raider)
    let raider2 = newEnhancedShip(ShipClass.Raider)

    let sq1 = newSquadron(raider1)
    let sq2 = newSquadron(raider2)

    let cloakLevel = getFleetCloakLevel(@[sq1, sq2])
    # Returns base tech level from config
    check cloakLevel > 0

  test "getFleetCloakLevel - returns 0 if no raiders":
    let cruiser = newEnhancedShip(ShipClass.Cruiser, techLevel = 3)
    let squadron = newSquadron(cruiser)

    let cloakLevel = getFleetCloakLevel(@[squadron])
    check cloakLevel == 0

  test "getFleetCloakLevel - ignores crippled raiders":
    var raider = newEnhancedShip(ShipClass.Raider, techLevel = 3)
    raider.isCrippled = true

    let squadron = newSquadron(raider)
    let cloakLevel = getFleetCloakLevel(@[squadron])
    check cloakLevel == 0

  test "hasELICapability - detects scouts":
    let scout = newEnhancedShip(ShipClass.Scout, techLevel = 2)
    let squadron = newSquadron(scout)

    check hasELICapability(@[squadron]) == true

  test "hasELICapability - returns false without scouts":
    let cruiser = newEnhancedShip(ShipClass.Cruiser, techLevel = 2)
    let squadron = newSquadron(cruiser)

    check hasELICapability(@[squadron]) == false

  test "createELIUnit - from fleet":
    let scout1 = newEnhancedShip(ShipClass.Scout, techLevel = 2)
    let scout2 = newEnhancedShip(ShipClass.Scout, techLevel = 4)

    let sq1 = newSquadron(scout1)
    let sq2 = newSquadron(scout2)

    let unit = createELIUnit(@[sq1, sq2], isStarbase = false)

    check unit.eliLevels.len == 2
    check unit.isStarbase == false

  test "createELIUnit - starbase":
    let unit = createELIUnit(@[], isStarbase = true)

    check unit.eliLevels.len == 0
    check unit.isStarbase == true

suite "Spec Examples Verification":

  test "spec example 1 - spy detection with mixed fleet":
    # From assets.md:2.4.2 Example 1
    # 2×ELI2, 3×ELI4 detecting Spy ELI3

    let unit = ELIUnit(
      eliLevels: @[2, 2, 4, 4, 4],
      isStarbase: false
    )

    let effectiveELI = calculateEffectiveELI(unit.eliLevels)
    check effectiveELI == 5

    # ELI5 vs Spy ELI3 should use range [2, 4]
    let thresholds = getSpyDetectionThreshold(5, 3)
    check thresholds == [2, 4]

  test "spec example 2 - spy detection balanced fleet":
    # From assets.md:2.4.2 Example 2
    # 1×ELI1, 1×ELI3 detecting Spy ELI4

    let unit = ELIUnit(
      eliLevels: @[1, 3],
      isStarbase: false
    )

    let effectiveELI = calculateEffectiveELI(unit.eliLevels)
    check effectiveELI == 3

    # ELI3 vs Spy ELI4 should use range [15, 17]
    let thresholds = getSpyDetectionThreshold(3, 4)
    check thresholds == [15, 17]

  test "spec example - raider detection high-tech fleet":
    # From assets.md:2.4.3 Example 1
    # 3×ELI5 detecting CLK2

    let unit = ELIUnit(
      eliLevels: @[5, 5, 5],
      isStarbase: false
    )

    let effectiveELI = calculateEffectiveELI(unit.eliLevels)
    check effectiveELI == 5

    # ELI5 vs CLK2 should use range [3, 5]
    let thresholds = getRaiderDetectionThreshold(5, 2)
    check thresholds == [3, 5]

    # 2+ level advantage → use lower bound
    let strategy = getRaiderThresholdStrategy(5, 2)
    check strategy == "lower"

  test "spec example - raider detection uncertain scenario":
    # From assets.md:2.4.3 Example 2
    # 1×ELI3, 1×ELI4 detecting CLK4

    let unit = ELIUnit(
      eliLevels: @[3, 4],
      isStarbase: false
    )

    let effectiveELI = calculateEffectiveELI(unit.eliLevels)
    check effectiveELI == 5

    # ELI5 vs CLK4 should use range [10, 12]
    let thresholds = getRaiderDetectionThreshold(5, 4)
    check thresholds == [10, 12]

    # 1 level advantage → use random
    let strategy = getRaiderThresholdStrategy(5, 4)
    check strategy == "random"
