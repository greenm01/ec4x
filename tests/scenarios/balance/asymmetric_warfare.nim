## Asymmetric Warfare Balance Tests
##
## Test special units in their INTENDED roles, not head-to-head capital battles
## Per assets.md design philosophy

import std/[strformat, options]
import ../../../src/engine/combat/[types, engine, ground]
import ../../../src/engine/squadron
import ../../../src/common/types/[core, units, combat]

## Scenario 1: Fighter Colony Defense
## Fighters should excel at defending colonies, not attacking capital ships
proc scenario_FighterColonyDefense*() =
  echo "\n=== Scenario: Fighter Colony Defense ==="
  echo "Design: Fighters defend home colony against attacking capitals"
  echo "Expected: Fighters leverage local advantage to hold off attackers\n"

  # Attacking capital fleet: 2 Cruisers (AS=8 each)
  var attackers: seq[CombatSquadron] = @[]
  for i in 1..2:
    let cruiser = newEnhancedShip(ShipClass.Cruiser, techLevel = 1)
    let squadron = newSquadron(cruiser, id = fmt"sq-ca-{i}", owner = "house-invader", location = 1)
    attackers.add(CombatSquadron(
      squadron: squadron,
      state: CombatState.Undamaged,
      damageThisTurn: 0,
      crippleRound: 0,
      bucket: TargetBucket.Capital,
      targetWeight: 1.0
    ))

  # Defending fighter swarm: 6 Fighter squadrons (AS=2 each, but HOME DEFENSE)
  var defenders: seq[CombatSquadron] = @[]
  for i in 1..6:
    let fighter = newEnhancedShip(ShipClass.Fighter, techLevel = 1)
    let squadron = newSquadron(fighter, id = fmt"sq-ff-{i}", owner = "house-defender", location = 1)
    defenders.add(CombatSquadron(
      squadron: squadron,
      state: CombatState.Undamaged,
      damageThisTurn: 0,
      crippleRound: 0,
      bucket: TargetBucket.Fighter,
      targetWeight: 1.0
    ))

  let attackerTF = TaskForce(
    house: "house-invader",
    squadrons: attackers,
    roe: 6,
    isCloaked: false,
    moraleModifier: 0,
    scoutBonus: false,
    isDefendingHomeworld: false
  )

  let defenderTF = TaskForce(
    house: "house-defender",
    squadrons: defenders,
    roe: 10,  # Fight to the death
    isCloaked: false,
    moraleModifier: 2,  # High morale defending home
    scoutBonus: false,
    isDefendingHomeworld: true  # Never retreat
  )

  let battle = BattleContext(
    systemId: 1,
    taskForces: @[attackerTF, defenderTF],
    seed: 11111,
    maxRounds: 20
  )

  let result = resolveCombat(battle)

  let victor = if result.victor.isSome: result.victor.get else: "Draw"
  echo fmt"Attacker AS: {2 * 8} (2 Cruisers)"
  echo fmt"Defender AS: {6 * 2} (6 Fighters, homeworld defense)"
  echo fmt"Result: {victor}"
  echo fmt"Rounds: {result.totalRounds}"
  echo "\nAnalysis: Fighters get homeworld morale bonus (+2 CER)"
  echo "          Numbers (6v2) and morale offset capital ship advantage"

## Scenario 2: Raider Ambush
## Raiders should excel with first-strike advantage, not frontal assault
proc scenario_RaiderAmbush*() =
  echo "\n=== Scenario: Raider Ambush (Cloaked First Strike) ==="
  echo "Design: Cloaked raiders ambush patrol fleet"
  echo "Expected: Ambush bonus compensates for raiders' lower stats\n"

  # Patrolling fleet: 2 Destroyers (AS=4, DS=10)
  var patrol: seq[CombatSquadron] = @[]
  for i in 1..2:
    let destroyer = newEnhancedShip(ShipClass.Destroyer, techLevel = 1)
    let squadron = newSquadron(destroyer, id = fmt"sq-dd-{i}", owner = "house-patrol", location = 1)
    patrol.add(CombatSquadron(
      squadron: squadron,
      state: CombatState.Undamaged,
      damageThisTurn: 0,
      crippleRound: 0,
      bucket: TargetBucket.Destroyer,
      targetWeight: 1.0
    ))

  # Raider fleet: 3 Raiders (AS=3, DS=5, but CLOAKED)
  var raiders: seq[CombatSquadron] = @[]
  for i in 1..3:
    let raider = newEnhancedShip(ShipClass.Raider, techLevel = 1)
    let squadron = newSquadron(raider, id = fmt"sq-rr-{i}", owner = "house-raiders", location = 1)
    raiders.add(CombatSquadron(
      squadron: squadron,
      state: CombatState.Undamaged,
      damageThisTurn: 0,
      crippleRound: 0,
      bucket: TargetBucket.Raider,
      targetWeight: 1.0
    ))

  let patrolTF = TaskForce(
    house: "house-patrol",
    squadrons: patrol,
    roe: 6,
    isCloaked: false,
    moraleModifier: 0,
    scoutBonus: false,
    isDefendingHomeworld: false
  )

  let raiderTF = TaskForce(
    house: "house-raiders",
    squadrons: raiders,
    roe: 6,
    isCloaked: true,  # AMBUSH ADVANTAGE
    moraleModifier: 1,  # Confident ambushers
    scoutBonus: false,
    isDefendingHomeworld: false
  )

  let battle = BattleContext(
    systemId: 1,
    taskForces: @[raiderTF, patrolTF],
    seed: 22222,
    maxRounds: 20
  )

  let result = resolveCombat(battle)

  let victor = if result.victor.isSome: result.victor.get else: "Draw"
  echo fmt"Patrol AS: {2 * 4} (2 Destroyers)"
  echo fmt"Raiders AS: {3 * 3} (3 Raiders, CLOAKED)"
  echo fmt"Result: {victor}"
  echo fmt"Rounds: {result.totalRounds}"
  echo "\nAnalysis: Raiders get Ambush Phase (first strike)"
  echo "          Cloaking provides tactical advantage despite lower stats"

## Scenario 3: Scout Detection Advantage
## Scouts enable detection and tactical bonuses
proc scenario_ScoutDetection*() =
  echo "\n=== Scenario: Scout Detection Advantage ==="
  echo "Design: Fleet with scout detects and counters cloaked raiders"
  echo "Expected: Scout bonus negates raider ambush advantage\n"

  # Raider attackers: 3 Raiders (cloaked)
  var raiders: seq[CombatSquadron] = @[]
  for i in 1..3:
    let raider = newEnhancedShip(ShipClass.Raider, techLevel = 1)
    let squadron = newSquadron(raider, id = fmt"sq-rr-{i}", owner = "house-raiders", location = 1)
    raiders.add(CombatSquadron(
      squadron: squadron,
      state: CombatState.Undamaged,
      damageThisTurn: 0,
      crippleRound: 0,
      bucket: TargetBucket.Raider,
      targetWeight: 1.0
    ))

  # Defender with scout: 1 Scout + 2 Destroyers
  var defenders: seq[CombatSquadron] = @[]

  let scoutShip = newEnhancedShip(ShipClass.Scout, techLevel = 1)
  let scoutSquadron = newSquadron(scoutShip, id = "sq-scout-1", owner = "house-defender", location = 1)
  defenders.add(CombatSquadron(
    squadron: scoutSquadron,
    state: CombatState.Undamaged,
    damageThisTurn: 0,
    crippleRound: 0,
    bucket: TargetBucket.Raider,  # Scouts use Raider bucket
    targetWeight: 1.0
  ))

  for i in 1..2:
    let destroyer = newEnhancedShip(ShipClass.Destroyer, techLevel = 1)
    let squadron = newSquadron(destroyer, id = fmt"sq-dd-{i}", owner = "house-defender", location = 1)
    defenders.add(CombatSquadron(
      squadron: squadron,
      state: CombatState.Undamaged,
      damageThisTurn: 0,
      crippleRound: 0,
      bucket: TargetBucket.Destroyer,
      targetWeight: 1.0
    ))

  let raiderTF = TaskForce(
    house: "house-raiders",
    squadrons: raiders,
    roe: 6,
    isCloaked: true,
    moraleModifier: 0,
    scoutBonus: false,
    isDefendingHomeworld: false
  )

  let defenderTF = TaskForce(
    house: "house-defender",
    squadrons: defenders,
    roe: 6,
    isCloaked: false,
    moraleModifier: 0,
    scoutBonus: true,  # SCOUT DETECTION BONUS
    isDefendingHomeworld: false
  )

  let battle = BattleContext(
    systemId: 1,
    taskForces: @[raiderTF, defenderTF],
    seed: 33333,
    maxRounds: 20
  )

  let result = resolveCombat(battle)

  let victor = if result.victor.isSome: result.victor.get else: "Draw"
  echo fmt"Raiders AS: {3 * 3} (3 Raiders, cloaked)"
  echo fmt"Defenders AS: {1 * 1 + 2 * 4} (1 Scout + 2 Destroyers, detection bonus)"
  echo fmt"Result: {victor}"
  echo fmt"Rounds: {result.totalRounds}"
  echo "\nAnalysis: Scout provides +1 CER bonus for entire fleet"
  echo "          Detection counters raider cloaking advantage"

## Scenario 4: Carrier Fighter Deployment
## Carriers transport fighters for strategic colony defense
proc scenario_CarrierDeployment*() =
  echo "\n=== Scenario: Carrier Strategic Deployment ==="
  echo "Design: Carrier deploys fighters to defend allied colony"
  echo "Expected: Transported fighters provide effective colony defense\n"

  # Note: This scenario demonstrates the CONCEPT
  # Actual implementation would require fleet movement + combat integration

  echo "Concept: Carrier transports 4 fighter squadrons to allied colony"
  echo "         Fighters disembark and establish defensive position"
  echo "         When attackers arrive, fighters defend with full strength"
  echo "\nStrategic value:"
  echo "  - Carriers enable rapid fighter deployment"
  echo "  - Fighters cost-effective for colony defense"
  echo "  - Mobile defense strategy vs. fixed defenses"
  echo "\nImplementation: Requires starmap movement integration"

## Scenario 5: Starbase Hacking
## Scout infiltrates enemy starbase to gather intelligence
proc scenario_StarbaseHacking*() =
  echo "\n=== Scenario: Starbase Hacking ==="
  echo "Design: Solo Scout infiltrates enemy starbase network"
  echo "Expected: Scout gathers economic and R&D intelligence without combat\n"

  echo "Per operations.md:6.2.11 - Hack a Starbase:"
  echo "  - Mission reserved for solo Scouts"
  echo "  - Scout disguises as civilian satellite"
  echo "  - Hacks starbase network for intelligence"
  echo "  - Gathers economic and R&D data"
  echo ""
  echo "Strategic value:"
  echo "  - Reveals enemy tech levels and research direction"
  echo "  - Exposes production capacity and economy"
  echo "  - Non-combat intelligence gathering"
  echo "  - Requires starbase detection rolls to succeed"
  echo "\nImplementation: Stub exists in starbase.nim, needs full implementation"

## Scenario 6: Multi-System Fleet Transit
## Fleet navigates through multiple systems using lane traversal rules
proc scenario_MultiSystemTransit*() =
  echo "\n=== Scenario: Multi-System Fleet Transit ==="
  echo "Design: Fleet moves through friendly territory using 2-jump rule"
  echo "Expected: Fleet reaches distant system in fewer turns\n"

  echo "Per operations.md:6.1 - Jump Lane Traversal:"
  echo "  - Major lanes: 2 jumps/turn if all systems owned by player"
  echo "  - Major lanes: 1 jump/turn into unexplored/rival systems"
  echo "  - Minor/Restricted lanes: Always 1 jump/turn"
  echo ""
  echo "Tactical application:"
  echo "  - Rapid reinforcement along friendly supply lines"
  echo "  - Strategic mobility advantage in controlled space"
  echo "  - Border defense can respond faster"
  echo "  - Invasion slows at enemy borders (1 jump/turn)"
  echo "\nImplementation: ✅ COMPLETE in resolve.nim:resolveMovementOrder"

## Main Runner
when isMainModule:
  echo "╔════════════════════════════════════════════════╗"
  echo "║  Asymmetric Warfare Balance Tests            ║"
  echo "╚════════════════════════════════════════════════╝"

  scenario_FighterColonyDefense()
  scenario_RaiderAmbush()
  scenario_ScoutDetection()
  scenario_CarrierDeployment()
  scenario_StarbaseHacking()
  scenario_MultiSystemTransit()

  echo "\n╔════════════════════════════════════════════════╗"
  echo "║  Asymmetric Tests Complete                    ║"
  echo "╚════════════════════════════════════════════════╝"
