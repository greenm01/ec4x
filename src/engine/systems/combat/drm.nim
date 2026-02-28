## Die Roll Modifiers (DRM) Calculation System
##
## Calculates all combat modifiers that affect CER rolls.
## Theater-specific bonuses and penalties.
##
## Per docs/specs/07-combat.md Section 7.4.2


import ../../types/[game_state, combat, ship]
import ../../state/[engine, iterators]
import ./strength

proc calculateFighterSuperiority*(
  state: GameState, ourForce: HouseCombatForce, enemyForce: HouseCombatForce
): int32 =
  ## Calculate Fighter Superiority DRM
  ## Per docs/specs/07-combat.md Section 7.4.2
  ##
  ## **Rules:**
  ## - +2 if 3:1+ fighter AS advantage
  ## - +1 if 2:1+ fighter AS advantage
  ## - +0 otherwise

  var ourFighterAS = 0'i32
  var enemyFighterAS = 0'i32

  # Count our fighters
  for fleetId in ourForce.fleets:
    for ship in state.shipsInFleet(fleetId):
      if ship.shipClass == ShipClass.Fighter and
          ship.state != CombatState.Destroyed:
        ourFighterAS += calculateShipAS(state, ship)

  # Count enemy fighters
  for fleetId in enemyForce.fleets:
    for ship in state.shipsInFleet(fleetId):
      if ship.shipClass == ShipClass.Fighter and
          ship.state != CombatState.Destroyed:
        enemyFighterAS += calculateShipAS(state, ship)

  # Calculate ratio
  if enemyFighterAS == 0 and ourFighterAS > 0:
    return 2 # We have fighters, they don't
  elif enemyFighterAS > 0:
    let ratio = float(ourFighterAS) / float(enemyFighterAS)
    if ratio >= 3.0:
      return 2
    elif ratio >= 2.0:
      return 1

  return 0

proc calculateDRM*(
  state: GameState, battle: Battle, isAttacker: bool, round: int
): int32 =
  ## Calculate all DRM modifiers for one side
  ## Per docs/specs/07-combat.md Section 7.4.2
  ##
  ## **DRM Components:**
  ## - Morale: ±1 or ±2 from prestige
  ## - Detection: +4 (Ambush) or +3 (Surprise), first round only, attacker only
  ## - Fighter Superiority: +2 at 3:1, +1 at 2:1 (recalculated each round)
  ## - ELI Advantage: +1 if higher tech
  ## - Starbase Sensors: +1 (defender only, if starbase present)
  ## - Homeworld Defense: +1 (defender only, if defending homeworld)

  result = 0
  let force = if isAttacker: battle.attacker else: battle.defender
  let enemyForce = if isAttacker: battle.defender else: battle.attacker

  # Morale (all theaters, first round only)
  if round == 1:
    result += force.morale

  case battle.theater
  of CombatTheater.Space, CombatTheater.Orbital:
    # Detection bonus (first round only, applies to winner of detection roll)
    # Per spec 7.3.2: Detection winner (either side) gets bonus
    if round == 1:
      let wonDetection = (isAttacker and battle.attackerWonDetection) or 
                         (not isAttacker and not battle.attackerWonDetection)
      if wonDetection:
        let detectionBonus =
          case battle.detectionResult
          of DetectionResult.Ambush:
            4'i32
          of DetectionResult.Surprise:
            3'i32
          of DetectionResult.Intercept:
            0'i32
        result += detectionBonus

    # Fighter Superiority (recalculated each round)
    result += calculateFighterSuperiority(state, force, enemyForce)

    # ELI Advantage
    if force.eliLevel > enemyForce.eliLevel:
      result += 1

    # Starbase Sensors (defender only)
    if not isAttacker and battle.hasDefenderStarbase:
      result += 1

    # Homeworld Defense (defender only)
    if not isAttacker and force.isDefendingHomeworld:
      result += 1

  of CombatTheater.Planetary:
    # Planetary combat DRM handled separately in planetary_combat.nim
    # This is for space/orbital DRM calculation
    discard

## Design Notes:
##
## **Spec Compliance:**
## - docs/specs/07-combat.md Section 7.4.2 - Die Roll Modifiers
## - docs/specs/07-combat.md Section 7.3 - Detection & Intelligence
##
## **DRM Stacking:**
## - All DRM stack additively
## - No maximum or minimum DRM cap
## - Round-by-round recalculation for dynamic modifiers (Fighter Superiority)
##
## **Morale Integration:**
## - Morale DRM comes from prestige system
## - Calculated before combat starts
## - Stored in HouseCombatForce.morale field
## - Applied first round only
##
## **Fighter Superiority:**
## - Recalculated each round (fighters can be destroyed)
## - Only counts operational fighters (not crippled/destroyed)
## - Ratio-based bonus (3:1 or 2:1)
##
## **Asymmetric Bonuses:**
## - Detection: Attacker only, first round only
## - Starbase Sensors: Defender only
## - Homeworld Defense: Defender only
## - ELI/Fighter Superiority: Either side can benefit
##
## **Special Cases:**
## - Cloaked attackers: Detection bonus applied via detectionResult
## - Multiple starbases: Still only +1 (presence-based, not count-based)
## - Neutral systems: No homeworld bonus for either side
