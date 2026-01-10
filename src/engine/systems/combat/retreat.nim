## Retreat and ROE Evaluation System
##
## Implements Rules of Engagement (ROE) evaluation and
## per-fleet retreat decisions.
##
## Per docs/specs/07-combat.md Section 7.2.3

import std/[options, sequtils]
import ../../types/[core, game_state, combat, fleet, ship]
import ../../state/engine
import ./strength
import ./screened
import ./morale

proc applyRetreatLossesToScreenedUnits*(state: var GameState, fleetId: FleetId) =
  ## Apply proportional losses to screened units during retreat
  ## Screened units take same casualty rate as combat ships
  ## Per screened.nim design notes

  let fleetOpt = state.fleet(fleetId)
  if fleetOpt.isNone:
    return

  # Get combat ships (exclude screened)
  let combatShips = getCombatShipsInFleet(state, fleetId)
  if combatShips.len == 0:
    return

  # Count casualties among combat ships
  var casualties = 0
  for shipId in combatShips:
    let shipOpt = state.ship(shipId)
    if shipOpt.isSome:
      let ship = shipOpt.get()
      if ship.state == CombatState.Crippled or ship.state == CombatState.Destroyed:
        casualties += 1

  # Calculate casualty rate
  let casualtyRate = float(casualties) / float(combatShips.len)

  # Apply same rate to screened units
  let screenedShips = getScreenedShipsInFleet(state, fleetId)
  let screenedCasualties = int(float(screenedShips.len) * casualtyRate)

  # Destroy proportional number of screened units
  for i in 0 ..< min(screenedCasualties, screenedShips.len):
    let shipId = screenedShips[i]
    let shipOpt = state.ship(shipId)
    if shipOpt.isSome:
      var ship = shipOpt.get()
      ship.state = CombatState.Destroyed
      state.updateShip(shipId, ship)

proc getROEThreshold*(roe: int32): float =
  ## Get retreat threshold from ROE level
  ## Per docs/specs/07-combat.md Section 7.2.3
  ##
  ## **ROE Levels:**
  ## - 0: 0.0 (never engage)
  ## - 1: 999.0 (only engage defenseless)
  ## - 2: 4.0 (need 4:1 advantage)
  ## - 3: 3.0 (need 3:1 advantage)
  ## - 4: 2.0 (need 2:1 advantage)
  ## - 5: 1.5 (need 3:2 advantage)
  ## - 6: 1.0 (engage if equal or better)
  ## - 7: 0.67 (tolerate 3:2 disadvantage)
  ## - 8: 0.5 (tolerate 2:1 disadvantage)
  ## - 9: 0.33 (tolerate 3:1 disadvantage)
  ## - 10: 0.0 (never retreat)

  case roe
  of 0:
    0.0
  of 1:
    999.0
  of 2:
    4.0
  of 3:
    3.0
  of 4:
    2.0
  of 5:
    1.5
  of 6:
    1.0
  of 7:
    0.67
  of 8:
    0.5
  of 9:
    0.33
  of 10:
    0.0
  else:
    1.0 # Default to even odds

proc checkFleetRetreats*(
  state: var GameState, battle: var Battle, attackerAS: int32, defenderAS: int32
) =
  ## Check retreat for each fleet individually
  ## Per docs/specs/07-combat.md Section 7.2.3
  ##
  ## **Retreat Rules:**
  ## - Each fleet compares its own AS to total enemy AS
  ## - Ratio compared against fleet's ROE threshold
  ## - If ratio < threshold, fleet retreats
  ## - Homeworld defense: NEVER retreat (override)

  # Check attacker fleets
  for fleetId in battle.attacker.fleets:
    let fleetOpt = state.fleet(fleetId)
    if fleetOpt.isNone:
      continue

    let fleet = fleetOpt.get()
    let fleetAS = calculateFleetAS(state, fleetId)

    # Skip if fleet has no combat power
    if fleetAS == 0:
      continue

    let ratio = float(fleetAS) / float(defenderAS)
    
    # Apply morale modifier to effective ROE (per spec 7.2.3)
    # Morale based on relative standing to leading house
    let moraleModifier = getMoraleROEModifier(state, fleet.houseId)
    let effectiveROE = fleet.roe + moraleModifier
    let threshold = getROEThreshold(effectiveROE)

    if ratio < threshold:
      # Fleet retreats
      battle.attackerRetreatedFleets.add(fleetId)

      # Apply proportional losses to screened units
      applyRetreatLossesToScreenedUnits(state, fleetId)

      # Remove fleet from battle
      battle.attacker.fleets = battle.attacker.fleets.filterIt(it != fleetId)

  # Check defender fleets
  for fleetId in battle.defender.fleets:
    let fleetOpt = state.fleet(fleetId)
    if fleetOpt.isNone:
      continue

    let fleet = fleetOpt.get()
    let fleetAS = calculateFleetAS(state, fleetId)

    # Skip if fleet has no combat power
    if fleetAS == 0:
      continue

    let ratio = float(fleetAS) / float(attackerAS)
    
    # Apply morale modifier to effective ROE (per spec 7.2.3)
    # Morale based on relative standing to leading house
    let moraleModifier = getMoraleROEModifier(state, fleet.houseId)
    let effectiveROE = fleet.roe + moraleModifier
    let threshold = getROEThreshold(effectiveROE)

    # Homeworld defense override: NEVER retreat
    if battle.defender.isDefendingHomeworld:
      continue

    if ratio < threshold:
      # Fleet retreats
      battle.defenderRetreatedFleets.add(fleetId)

      # Apply proportional losses to screened units
      applyRetreatLossesToScreenedUnits(state, fleetId)

      # Remove fleet from battle
      battle.defender.fleets = battle.defender.fleets.filterIt(it != fleetId)

proc noCombatantsRemain*(state: GameState, battle: Battle): bool =
  ## Check if combat should end (one or both sides have no operational ships)
  ## Per docs/specs/07-combat.md Section 7.2.3

  let attackerShips = countOperationalShips(state, battle.attacker.fleets)
  let defenderShips = countOperationalShips(state, battle.defender.fleets)

  return attackerShips == 0 or defenderShips == 0

## Design Notes:
##
## **Spec Compliance:**
## - docs/specs/07-combat.md Section 7.2.3 - Rules of Engagement
## - docs/specs/07-combat.md Section 7.2.3 - Retreat Mechanics
##
## **Per-Fleet Retreat:**
## - Each fleet checks independently
## - Compares fleet AS to total enemy AS (not individual enemy fleets)
## - ROE threshold determines retreat behavior
## - Retreated fleets removed from battle immediately
##
## **Homeworld Defense Override:**
## - Defender at homeworld NEVER retreats
## - Overrides ROE settings
## - Only applies to defender (not attacker)
##
## **Retreat Timing:**
## - Checked after each round of combat
## - Retreat evaluation uses post-round strength
## - Multiple fleets can retreat simultaneously
##
## **Fleet AS Calculation:**
## - Sum of all ship AS in fleet
## - Includes crippled ships (at 50% AS)
## - Excludes destroyed ships (0 AS)
##
## **Combat Termination:**
## - Combat ends when one side has no operational ships
## - Operational = Undamaged or Crippled (not Destroyed)
## - Empty fleets (all ships destroyed) don't prevent retreat checks
##
## **Special Cases:**
## - ROE 0 (never engage): Immediate retreat if any enemy present
## - ROE 1 (only engage defenseless): Retreat unless enemy has 0 AS
## - ROE 10 (never retreat): Fight to the death
## - Negative enemy AS: Impossible, but would trigger retreat for ROE < 10
