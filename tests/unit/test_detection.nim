## Unit Tests: Combat Detection Modifiers
##
## Tests calculateDetectionModifiers from combat/detection.nim
## This is the ONLY pure function in detection.nim that doesn't need GameState.
##
## Per docs/specs/07-combat.md Section 7.3.1

import std/unittest
import ../../src/engine/types/[core, combat]
import ../../src/engine/systems/combat/detection

suite "Detection: Modifier Calculation":
  ## Test calculateDetectionModifiers - pure function

  test "base case - all zeros":
    let force = HouseCombatForce(
      houseId: HouseId(1),
      fleets: @[],
      clkLevel: 0,
      eliLevel: 0
    )
    let modifier = calculateDetectionModifiers(force, hasStarbase = false,
        isDefender = false)
    check modifier == 0

  test "CLK level adds to modifier":
    let force = HouseCombatForce(
      houseId: HouseId(1),
      fleets: @[],
      clkLevel: 3,
      eliLevel: 0
    )
    let modifier = calculateDetectionModifiers(force, hasStarbase = false,
        isDefender = false)
    check modifier == 3

  test "ELI level adds to modifier":
    let force = HouseCombatForce(
      houseId: HouseId(1),
      fleets: @[],
      clkLevel: 0,
      eliLevel: 5
    )
    let modifier = calculateDetectionModifiers(force, hasStarbase = false,
        isDefender = false)
    check modifier == 5

  test "CLK and ELI are additive":
    let force = HouseCombatForce(
      houseId: HouseId(1),
      fleets: @[],
      clkLevel: 2,
      eliLevel: 4
    )
    let modifier = calculateDetectionModifiers(force, hasStarbase = false,
        isDefender = false)
    check modifier == 6 # 2 + 4

  test "starbase bonus only for defender":
    let force = HouseCombatForce(
      houseId: HouseId(1),
      fleets: @[],
      clkLevel: 0,
      eliLevel: 0
    )

    # Attacker with starbase present (doesn't help them)
    let attackerMod = calculateDetectionModifiers(force, hasStarbase = true,
        isDefender = false)
    check attackerMod == 0 # No starbase bonus

    # Defender with starbase
    let defenderMod = calculateDetectionModifiers(force, hasStarbase = true,
        isDefender = true)
    check defenderMod == 2 # +2 from starbase sensors

  test "starbase without isDefender gives no bonus":
    let force = HouseCombatForce(
      houseId: HouseId(1),
      fleets: @[],
      clkLevel: 1,
      eliLevel: 1
    )
    # hasStarbase = true but isDefender = false
    let modifier = calculateDetectionModifiers(force, hasStarbase = true,
        isDefender = false)
    check modifier == 2 # Just CLK + ELI, no starbase

  test "full defender loadout":
    let force = HouseCombatForce(
      houseId: HouseId(1),
      fleets: @[],
      clkLevel: 5,
      eliLevel: 7
    )
    let modifier = calculateDetectionModifiers(force, hasStarbase = true,
        isDefender = true)
    check modifier == 14 # 5 + 7 + 2

  test "attacker has no starbase bonus even with high tech":
    let force = HouseCombatForce(
      houseId: HouseId(1),
      fleets: @[],
      clkLevel: 10,
      eliLevel: 10
    )
    let modifier = calculateDetectionModifiers(force, hasStarbase = true,
        isDefender = false)
    check modifier == 20 # Just CLK + ELI

suite "Detection: Result Interpretation":
  ## Test detection result values (not rollDetection itself - that needs state)
  ## Enum order: Ambush (0), Surprise (1), Intercept (2)
  ## Better detection = lower ord (Ambush is best)

  test "DetectionResult enum values":
    check DetectionResult.Ambush.ord == 0
    check DetectionResult.Surprise.ord == 1
    check DetectionResult.Intercept.ord == 2

  test "detection results ordering":
    # Ambush is best (lowest ord), Intercept is worst (highest ord)
    check DetectionResult.Ambush < DetectionResult.Surprise
    check DetectionResult.Surprise < DetectionResult.Intercept

suite "Detection: Edge Cases":

  test "defender without starbase":
    let force = HouseCombatForce(
      houseId: HouseId(1),
      fleets: @[],
      clkLevel: 3,
      eliLevel: 2
    )
    let modifier = calculateDetectionModifiers(force, hasStarbase = false,
        isDefender = true)
    check modifier == 5 # No starbase bonus even as defender

  test "maximum reasonable tech levels":
    let force = HouseCombatForce(
      houseId: HouseId(1),
      fleets: @[],
      clkLevel: 15, # Max CLK
      eliLevel: 15 # Max ELI
    )
    let modifier = calculateDetectionModifiers(force, hasStarbase = true,
        isDefender = true)
    check modifier == 32 # 15 + 15 + 2

  test "zero tech level scenario":
    let attacker = HouseCombatForce(
      houseId: HouseId(1),
      fleets: @[],
      clkLevel: 0,
      eliLevel: 0
    )
    let defender = HouseCombatForce(
      houseId: HouseId(2),
      fleets: @[],
      clkLevel: 0,
      eliLevel: 0
    )

    let aMod = calculateDetectionModifiers(attacker, hasStarbase = false,
        isDefender = false)
    let dMod = calculateDetectionModifiers(defender, hasStarbase = true,
        isDefender = true)

    check aMod == 0
    check dMod == 2 # Only starbase bonus

when isMainModule:
  echo "========================================"
  echo "  Detection Modifier Unit Tests"
  echo "========================================"
