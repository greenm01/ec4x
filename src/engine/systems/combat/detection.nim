## Detection Rolling System
##
## Handles pre-combat detection phase to determine first-strike advantage.
## Per docs/specs/07-combat.md Section 7.3.1
##
## Detection determines combat surprise, NOT whether combat occurs.
## Raiders provide detection advantage but do not skip combat.

import std/[random, options]
import ../../types/[core, game_state, combat, ship, fleet]
import ../../state/engine

proc hasRaiders*(state: GameState, force: HouseCombatForce): bool =
  ## Check if combat force has any Raider ships
  for fleetId in force.fleets:
    let fleetOpt = state.fleet(fleetId)
    if fleetOpt.isNone():
      continue

    let fleet = fleetOpt.get()
    for shipId in fleet.ships:
      let shipOpt = state.ship(shipId)
      if shipOpt.isNone():
        continue

      let ship = shipOpt.get()
      if ship.shipClass == ShipClass.Raider and ship.state != CombatState.Destroyed:
        return true

  return false

proc calculateDetectionModifiers*(
  force: HouseCombatForce,
  hasStarbase: bool,
  isDefender: bool
): int32 =
  ## Calculate detection roll modifiers
  ## Per docs/specs/07-combat.md Section 7.3.1
  var modifier = 0'i32

  # CLK Level
  modifier += force.clkLevel

  # ELI Level
  modifier += force.eliLevel

  # Starbase Sensors (defender only)
  if isDefender and hasStarbase:
    modifier += 2

  return modifier

proc rollDetection*(
  state: GameState,
  attacker: HouseCombatForce,
  defender: HouseCombatForce,
  hasDefenderStarbase: bool,
  rng: var Rand
): DetectionResult =
  ## Roll opposed detection to determine first-strike advantage
  ## Per docs/specs/07-combat.md Section 7.3.1
  ##
  ## **Detection vs Combat Occurrence:**
  ## - Detection determines WHO gets first-strike advantage
  ## - Detection does NOT determine IF combat occurs
  ## - Raiders provide detection bonus, NOT combat skip
  ##
  ## **Detection Results:**
  ## - Ambush (5+ margin): +4 DRM first round
  ## - Surprise (1-4 margin): +3 DRM first round
  ## - Intercept (tie/no raiders): +0 DRM

  let attackerHasRaiders = hasRaiders(state, attacker)
  let defenderHasRaiders = hasRaiders(state, defender)

  # Case 1: Neither side has raiders → Intercept
  if not attackerHasRaiders and not defenderHasRaiders:
    return DetectionResult.Intercept

  # Calculate detection modifiers
  let attackerMod = calculateDetectionModifiers(attacker, false, false)
  let defenderMod = calculateDetectionModifiers(
    defender, hasDefenderStarbase, true
  )

  # Roll opposed detection (1d10 + modifiers)
  let attackerRoll = rand(rng, 1..10) + attackerMod
  let defenderRoll = rand(rng, 1..10) + defenderMod

  # Case 2: Only attacker has raiders
  if attackerHasRaiders and not defenderHasRaiders:
    let margin = attackerRoll - defenderRoll
    if margin >= 5:
      return DetectionResult.Ambush
    elif margin >= 1:
      return DetectionResult.Surprise
    else:
      return DetectionResult.Intercept

  # Case 3: Only defender has raiders
  if defenderHasRaiders and not attackerHasRaiders:
    let margin = defenderRoll - attackerRoll
    if margin >= 5:
      return DetectionResult.Ambush
    elif margin >= 1:
      return DetectionResult.Surprise
    else:
      return DetectionResult.Intercept

  # Case 4: Both have raiders → Roll-off
  if attackerHasRaiders and defenderHasRaiders:
    let margin = abs(attackerRoll - defenderRoll)

    if attackerRoll > defenderRoll:
      # Attacker wins detection
      if margin >= 5:
        return DetectionResult.Ambush
      elif margin >= 1:
        return DetectionResult.Surprise
    elif defenderRoll > attackerRoll:
      # Defender wins detection
      if margin >= 5:
        return DetectionResult.Ambush
      elif margin >= 1:
        return DetectionResult.Surprise

    # Tie detection roll → Intercept (no advantage)
    return DetectionResult.Intercept

  # Fallback (should never reach here)
  return DetectionResult.Intercept

## Design Notes:
##
## **Spec Compliance:**
## - docs/specs/07-combat.md Section 7.3.1 - Detection Phase
## - docs/specs/07-combat.md Section 7.4.2 - Detection DRM
##
## **Detection Flow:**
## 1. Check if either side has Raiders
## 2. If neither: Intercept (no detection advantage)
## 3. If one side: Roll detection, determine advantage
## 4. If both sides: Roll-off, winner gets advantage
## 5. Tie roll: Intercept (simultaneous engagement)
##
## **Key Principle:**
## Detection determines ADVANTAGE (DRM bonus), not WHETHER combat occurs.
## Raiders are combat enhancement, NOT combat avoidance.
##
## **Detection Modifiers:**
## - CLK Level: +X per level
## - ELI Level: +X per level
## - Defender Starbase: +2 (sensor arrays)
##
## **Detection Results:**
## - Ambush: 5+ margin → +4 DRM first round only
## - Surprise: 1-4 margin → +3 DRM first round only
## - Intercept: Tie/no raiders → +0 DRM
##
## **Integration:**
## Called by resolver.nim before combat round 1 to set battle.detectionResult
