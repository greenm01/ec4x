## Debug ROE=4 retreat issue
import std/[strformat, options]
import ../src/engine/combat/[types, engine, retreat]
import ../src/engine/squadron
import ../src/common/types/[core, units, combat]

# Recreate exact scenario from roe_retreat.nim scenario 1
var smallFleet: seq[CombatSquadron] = @[]
for i in 1..2:
  let cruiser = newEnhancedShip(ShipClass.Cruiser, techLevel = 1)
  let squadron = newSquadron(cruiser, id = fmt"sq-small-{i}", owner = "house-defender", location = 1)
  smallFleet.add(CombatSquadron(
    squadron: squadron,
    state: CombatState.Undamaged,
    damageThisTurn: 0,
    crippleRound: 0,
    bucket: TargetBucket.Capital,
    targetWeight: 1.0
  ))

var largeFleet: seq[CombatSquadron] = @[]
for i in 1..6:
  let cruiser = newEnhancedShip(ShipClass.Cruiser, techLevel = 1)
  let squadron = newSquadron(cruiser, id = fmt"sq-large-{i}", owner = "house-attacker", location = 1)
  largeFleet.add(CombatSquadron(
    squadron: squadron,
    state: CombatState.Undamaged,
    damageThisTurn: 0,
    crippleRound: 0,
    bucket: TargetBucket.Capital,
    targetWeight: 1.0
  ))

let smallTF = TaskForce(
  house: "house-defender",
  squadrons: smallFleet,
  roe: 4,
  isCloaked: false,
  moraleModifier: 0,
  scoutBonus: false,
  isDefendingHomeworld: false
)

let largeTF = TaskForce(
  house: "house-attacker",
  squadrons: largeFleet,
  roe: 8,
  isCloaked: false,
  moraleModifier: 0,
  scoutBonus: false,
  isDefendingHomeworld: false
)

echo "=== Initial State ==="
echo fmt"Defender: {smallTF.totalAS()} AS, ROE={smallTF.roe}"
echo fmt"Attacker: {largeTF.totalAS()} AS, ROE={largeTF.roe}"
echo fmt"Ratio: {float(smallTF.totalAS()) / float(largeTF.totalAS())}"

# Manually evaluate retreat with prestige=40
let prestige = smallTF.roe * 10
echo fmt"\nPrestige calculation: {smallTF.roe} * 10 = {prestige}"

let eval = evaluateRetreat(smallTF, @[smallTF, largeTF], prestige)

echo "\n=== Retreat Evaluation ==="
echo fmt"Task Force: {eval.taskForce}"
echo fmt"Our Strength: {eval.ourStrength}"
echo fmt"Enemy Strength: {eval.enemyStrength}"
echo fmt"Strength Ratio: {eval.strengthRatio}"
echo fmt"Base ROE: {smallTF.roe}"
echo fmt"Effective ROE: {eval.effectiveROE}"
echo fmt"Wants to Retreat: {eval.wantsToRetreat}"
echo fmt"Reason: {eval.reason}"

# Check threshold
echo "\n=== Threshold Check ==="
let threshold = ROEThresholds[eval.effectiveROE].threshold
echo fmt"ROE {eval.effectiveROE} threshold: {threshold}"
echo fmt"Ratio {eval.strengthRatio} < {threshold}? {eval.strengthRatio < threshold}"

# Now run actual combat
echo "\n=== Running Combat ==="
let battle = BattleContext(
  systemId: 1,
  taskForces: @[smallTF, largeTF],
  seed: 44444,
  maxRounds: 20
)

let result = resolveCombat(battle)

echo fmt"Rounds: {result.totalRounds}"
echo fmt"Retreated: {result.retreated}"
echo fmt"Eliminated: {result.eliminated}"
echo fmt"Victor: {result.victor}"
