## Combat Resolution Engine
##
## Main combat resolution interface for EC4X.
## Works for Space, Orbital, or Planetary theaters.
##
## Per docs/specs/07-combat.md

import std/random
import ../../types/[game_state, combat]
import ../../state/engine
import ./[strength, cer, drm, hits, retreat]

proc determineOutcome*(state: GameState, battle: Battle): CombatResult =
  ## Determine battle outcome based on survivors
  ## Per docs/specs/07-combat.md Section 7.2

  let attackerShips = countOperationalShips(state, battle.attacker.fleets)
  let defenderShips = countOperationalShips(state, battle.defender.fleets)

  return CombatResult(
    theater: battle.theater,
    rounds: 0, # Will be set by caller
    attackerSurvived: attackerShips > 0,
    defenderSurvived: defenderShips > 0,
    attackerRetreatedFleets: battle.attackerRetreatedFleets,
    defenderRetreatedFleets: battle.defenderRetreatedFleets,
  )

proc resolveBattle*(
  state: GameState, battle: var Battle, rng: var Rand
): CombatResult =
  ## Main combat resolution - works for Space, Orbital, or Planetary
  ## Per docs/specs/07-combat.md Section 7.4
  ##
  ## **Combat Flow:**
  ## 1. Calculate total AS for each side (sum all ships from all fleets)
  ## 2. Calculate DRM for each side (theater-specific)
  ## 3. Roll CER (theater-specific table)
  ## 4. Calculate hits
  ## 5. Apply hits (changes ship.state across all fleets)
  ## 6. Check retreat PER FLEET
  ## 7. Check if combat ends
  ## 8. Repeat for up to 20 rounds

  var round = 1
  let maxRounds = 20

  while round <= maxRounds:
    # Calculate total AS for each side (sum all ships from all fleets)
    let attackerAS = calculateHouseAS(state, battle.attacker)
    let defenderAS = calculateHouseAS(state, battle.defender)

    # Calculate DRM for each side (theater-specific)
    let attackerDRM = calculateDRM(state, battle, isAttacker = true, round)
    let defenderDRM = calculateDRM(state, battle, isAttacker = false, round)

    # Roll CER (theater-specific table)
    let attackerCERResult = rollCER(rng, attackerDRM, battle.theater)
    let defenderCERResult = rollCER(rng, defenderDRM, battle.theater)

    # Calculate hits
    let attackerHits = int32(float32(attackerAS) * attackerCERResult.cer)
    let defenderHits = int32(float32(defenderAS) * defenderCERResult.cer)

    # Apply hits (changes ship.state across all fleets)
    let attackerShips = getAllShips(state, battle.attacker.fleets)
    let defenderShips = getAllShips(state, battle.defender.fleets)

    applyHits(state, defenderShips, attackerHits, attackerCERResult.isCriticalHit)
    applyHits(state, attackerShips, defenderHits, defenderCERResult.isCriticalHit)

    # Check retreat PER FLEET
    checkFleetRetreats(state, battle, attackerAS, defenderAS)

    # Check if combat ends
    if noCombatantsRemain(state, battle):
      break

    round += 1

  # Determine winner
  return determineOutcome(state, battle)

## Design Notes:
##
## **Spec Compliance:**
## - docs/specs/07-combat.md Section 7.4 - Combat Resolution System
## - docs/specs/07-combat.md Section 7.4.1 - CER Tables
## - docs/specs/07-combat.md Section 7.4.2 - Die Roll Modifiers (DRM)
## - docs/specs/07-combat.md Section 7.2.1 - Hit Application
## - docs/specs/07-combat.md Section 7.2.3 - Rules of Engagement (ROE)
##
## **Architecture:**
## - Combat aggregates at house level (sum all AS from all house fleets)
## - Retreat checks per fleet (each fleet checks own ROE)
## - Theater-specific CER tables and DRM calculations
## - No damage tracking between rounds (only ship.state changes)
##
## **Integration:**
## - Called from orchestrator.nim for Space/Orbital theaters
## - Called from planetary_combat.nim for Planetary theater
## - Depends on Phase 3 implementations: strength, cer, drm, hits, retreat
