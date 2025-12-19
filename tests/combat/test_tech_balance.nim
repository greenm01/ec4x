## Tech Level Balance Test
##
## Verify that higher tech levels provide appropriate combat advantage
## Per gameplay.md:1.2, tech starts at level 1

import std/[strformat, sequtils, options]
import ../../src/engine/combat/[types, engine]
import ../../src/engine/squadron
import ../../src/common/types/[core, units, combat]

proc testTechBalance*() =
  echo "\n=== Tech Level Balance Test ==="
  echo "Testing: Tech 3 (2 squadrons) vs Tech 1 (2 squadrons)"
  echo "Equal numbers - tech should be the deciding factor\n"

  # Tech 3 fleet: 2 Battleships
  var tech3Fleet: seq[CombatSquadron] = @[]
  for i in 1..2:
    let ship = newShip(ShipClass.Battleship, techLevel = 3, name = "BB-Tech3")
    let squadron = newSquadron(ship, id = fmt"sq-t3-{i}", owner = "house-advanced", location = 1)
    tech3Fleet.add(CombatSquadron(
      squadron: squadron,
      state: CombatState.Undamaged,
      damageThisTurn: 0,
      crippleRound: 0,
      bucket: TargetBucket.Capital,
      targetWeight: 1.0
    ))

  # Tech 1 fleet: 2 Battleships (same ship type, lower tech)
  var tech1Fleet: seq[CombatSquadron] = @[]
  for i in 1..2:
    let ship = newShip(ShipClass.Battleship, techLevel = 1, name = "BB-Tech1")
    let squadron = newSquadron(ship, id = fmt"sq-t1-{i}", owner = "house-starting", location = 1)
    tech1Fleet.add(CombatSquadron(
      squadron: squadron,
      state: CombatState.Undamaged,
      damageThisTurn: 0,
      crippleRound: 0,
      bucket: TargetBucket.Capital,
      targetWeight: 1.0
    ))

  # Print ship stats for comparison
  echo "Tech 3 Battleship stats:"
  let t3Ship = tech3Fleet[0].squadron.flagship
  echo fmt"  AS: {t3Ship.stats.attackStrength}, DS: {t3Ship.stats.defenseStrength}"

  echo "Tech 1 Battleship stats:"
  let t1Ship = tech1Fleet[0].squadron.flagship
  echo fmt"  AS: {t1Ship.stats.attackStrength}, DS: {t1Ship.stats.defenseStrength}"

  echo fmt"\nTech 3 total AS: {tech3Fleet.mapIt(it.squadron.flagship.stats.attackStrength).foldl(a + b)}"
  echo fmt"Tech 1 total AS: {tech1Fleet.mapIt(it.squadron.flagship.stats.attackStrength).foldl(a + b)}"

  # (Note: TaskForce fields checked below when creating copies for each battle)

  # Run multiple battles with different seeds
  var tech3Wins = 0
  var tech1Wins = 0
  var draws = 0
  let numTests = 100

  echo fmt"\nRunning {numTests} battles with different seeds..."

  for testNum in 1..numTests:
    # Create fresh fleets for each test
    var tech3FleetCopy: seq[CombatSquadron] = @[]
    for i in 1..2:
      let ship = newShip(ShipClass.Battleship, techLevel = 3)
      let squadron = newSquadron(ship, id = fmt"sq-t3-{i}", owner = "house-advanced", location = 1)
      tech3FleetCopy.add(CombatSquadron(
        squadron: squadron,
        state: CombatState.Undamaged,
        damageThisTurn: 0,
        crippleRound: 0,
        bucket: TargetBucket.Capital,
        targetWeight: 1.0
      ))

    var tech1FleetCopy: seq[CombatSquadron] = @[]
    for i in 1..2:
      let ship = newShip(ShipClass.Battleship, techLevel = 1)
      let squadron = newSquadron(ship, id = fmt"sq-t1-{i}", owner = "house-starting", location = 1)
      tech1FleetCopy.add(CombatSquadron(
        squadron: squadron,
        state: CombatState.Undamaged,
        damageThisTurn: 0,
        crippleRound: 0,
        bucket: TargetBucket.Capital,
        targetWeight: 1.0
      ))

    let tech3TFCopy = TaskForce(
      house: "house-advanced",
      squadrons: tech3FleetCopy,
      roe: 6,
      isCloaked: false,
      moraleModifier: 0,
      scoutBonus: false,
      isDefendingHomeworld: false
    )

    let tech1TFCopy = TaskForce(
      house: "house-starting",
      squadrons: tech1FleetCopy,
      roe: 6,
      isCloaked: false,
      moraleModifier: 0,
      scoutBonus: false,
      isDefendingHomeworld: false
    )

    let battle = BattleContext(
      systemId: 1,
      taskForces: @[tech3TFCopy, tech1TFCopy],
      seed: testNum * 12345,
      maxRounds: 20
    )

    let result = resolveCombat(battle)

    if result.victor.isSome:
      if result.victor.get == "house-advanced":
        tech3Wins += 1
      elif result.victor.get == "house-starting":
        tech1Wins += 1
      else:
        draws += 1
    else:
      draws += 1

  echo "\n=== Results ==="
  echo fmt"Tech 3 wins: {tech3Wins}/{numTests} ({100.0 * tech3Wins.float / numTests.float:.1f}%)"
  echo fmt"Tech 1 wins: {tech1Wins}/{numTests} ({100.0 * tech1Wins.float / numTests.float:.1f}%)"
  echo fmt"Draws: {draws}/{numTests} ({100.0 * draws.float / numTests.float:.1f}%)"

  echo "\n=== Expected Result ==="
  echo "Tech 3 should win 60-80% of the time (20% advantage per 2 tech levels)"
  echo "Currently working as expected if Tech 3 wins > 60%"

  if tech3Wins < 60:
    echo "\n⚠️  BALANCE ISSUE: Tech 3 not winning enough!"
    echo "    Higher tech should have clear advantage"
  else:
    echo "\n✅ Tech balance working correctly"

when isMainModule:
  testTechBalance()
