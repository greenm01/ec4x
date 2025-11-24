## Ground Combat Test Scenarios
##
## Tests for planetary bombardment, invasion, and blitz mechanics

import std/[sequtils, options, strformat]
import ../../src/engine/combat/[types, cer, ground, engine]
import ../../src/engine/squadron
import ../../src/common/types/[core, units, combat]

## Test Scenarios

proc testBasicBombardment*() =
  echo "\n=== Test: Basic Bombardment ==="

  # Create attacking fleet: 3 Battleships (AS=20 each)
  var attackingFleet: seq[CombatSquadron] = @[]
  for i in 1..3:
    let battleship = newEnhancedShip(ShipClass.Battleship, techLevel = 1)
    let squadron = newSquadron(battleship, id = fmt"sq-att-{i}", owner = "house-alpha", location = 1)
    attackingFleet.add(CombatSquadron(
      squadron: squadron,
      state: CombatState.Undamaged,
      damageThisTurn: 0,
      crippleRound: 0,
      bucket: TargetBucket.Capital,
      targetWeight: 1.0
    ))

  # Create planetary defense: 3 Ground Batteries (AS=0, DS=8 each)
  var defense = PlanetaryDefense(
    shields: none(ShieldLevel),
    groundBatteries: @[
      createGroundBattery("gb-1", "house-beta"),
      createGroundBattery("gb-2", "house-beta"),
      createGroundBattery("gb-3", "house-beta")
    ],
    groundForces: @[
      createArmy("army-1", "house-beta"),
      createArmy("army-2", "house-beta")
    ],
    spaceport: true
  )

  echo fmt"Attackers: 3 Battleships (AS={attackingFleet[0].squadron.flagship.stats.attackStrength} each)"
  echo fmt"Defenders: {defense.groundBatteries.len} Ground Batteries (DS=8 each)"
  echo fmt"Ground Forces: {defense.groundForces.len} Armies"

  # Conduct bombardment
  let result = conductBombardment(attackingFleet, defense, seed = 12345, maxRounds = 3)

  echo fmt"Result: {result.roundsCompleted} rounds"
  echo fmt"  Attacker hits: {result.attackerHits}"
  echo fmt"  Defender hits: {result.defenderHits}"
  echo fmt"  Batteries destroyed: {result.batteriesDestroyed}"
  echo fmt"  Batteries crippled: {result.batteriesCrippled}"
  echo fmt"  Infrastructure damage: {result.infrastructureDamage}"

  let batteriesRemaining = defense.groundBatteries.filterIt(it.state != CombatState.Destroyed).len
  echo fmt"  Batteries remaining: {batteriesRemaining}/{defense.groundBatteries.len}"

proc testBombardmentWithShields*() =
  echo "\n=== Test: Bombardment with Shields ==="

  # Create attacking fleet: 2 Cruisers (AS=8 each)
  var attackingFleet: seq[CombatSquadron] = @[]
  for i in 1..2:
    let cruiser = newEnhancedShip(ShipClass.Cruiser, techLevel = 1)
    let squadron = newSquadron(cruiser, id = fmt"sq-att-{i}", owner = "house-alpha", location = 1)
    attackingFleet.add(CombatSquadron(
      squadron: squadron,
      state: CombatState.Undamaged,
      damageThisTurn: 0,
      crippleRound: 0,
      bucket: TargetBucket.Capital,
      targetWeight: 1.0
    ))

  # Create defense with SLD3 shields
  var defense = PlanetaryDefense(
    shields: some(ShieldLevel(level: 3, blockChance: 0.45, blockPercentage: 0.35)),
    groundBatteries: @[
      createGroundBattery("gb-1", "house-beta"),
      createGroundBattery("gb-2", "house-beta")
    ],
    groundForces: @[],
    spaceport: true
  )

  echo fmt"Attackers: 2 Cruisers (AS=8 each)"
  echo "Defenders: SLD3 shields (35% block on 45% chance)"
  echo fmt"  {defense.groundBatteries.len} Ground Batteries"

  let result = conductBombardment(attackingFleet, defense, seed = 54321)

  echo fmt"Result: {result.roundsCompleted} rounds"
  echo fmt"  Attacker hits (before shields): {result.attackerHits + result.shieldBlocked}"
  echo fmt"  Hits blocked by shields: {result.shieldBlocked}"
  echo fmt"  Effective attacker hits: {result.attackerHits}"
  echo fmt"  Batteries destroyed: {result.batteriesDestroyed}"

proc testPlanetBreakerShieldBypass*() =
  echo "\n=== Test: Planet-Breaker Shield Bypass ==="

  # Create mixed fleet: 1 Planet-Breaker + 1 Battleship
  var attackingFleet: seq[CombatSquadron] = @[]

  let pb = newEnhancedShip(ShipClass.PlanetBreaker, techLevel = 10)
  let pbSquadron = newSquadron(pb, id = "sq-pb", owner = "house-alpha", location = 1)
  attackingFleet.add(CombatSquadron(
    squadron: pbSquadron,
    state: CombatState.Undamaged,
    damageThisTurn: 0,
    crippleRound: 0,
    bucket: TargetBucket.Capital,
    targetWeight: 1.0
  ))

  let bs = newEnhancedShip(ShipClass.Battleship, techLevel = 1)
  let bsSquadron = newSquadron(bs, id = "sq-bs", owner = "house-alpha", location = 1)
  attackingFleet.add(CombatSquadron(
    squadron: bsSquadron,
    state: CombatState.Undamaged,
    damageThisTurn: 0,
    crippleRound: 0,
    bucket: TargetBucket.Capital,
    targetWeight: 1.0
  ))

  # Create defense with maximum shields (SLD6)
  var defense = PlanetaryDefense(
    shields: some(ShieldLevel(level: 6, blockChance: 0.90, blockPercentage: 0.50)),
    groundBatteries: @[
      createGroundBattery("gb-1", "house-beta"),
      createGroundBattery("gb-2", "house-beta"),
      createGroundBattery("gb-3", "house-beta")
    ],
    groundForces: @[],
    spaceport: true
  )

  echo fmt"Attackers: 1 Planet-Breaker (AS=50) + 1 Battleship (AS=20)"
  echo "Defenders: SLD6 shields (50% block on 90% chance)"
  echo fmt"  {defense.groundBatteries.len} Ground Batteries"

  let result = conductBombardment(attackingFleet, defense, seed = 99999)

  echo fmt"Result: {result.roundsCompleted} rounds"
  echo fmt"  Total hits: {result.attackerHits}"
  echo fmt"  Hits blocked: {result.shieldBlocked} (only conventional)"
  echo "  Note: Planet-Breaker bypasses shields entirely"
  echo fmt"  Batteries destroyed: {result.batteriesDestroyed}"

proc testPlanetaryInvasion*() =
  echo "\n=== Test: Planetary Invasion ==="

  # Create Marines for invasion
  var attackingForces: seq[GroundUnit] = @[
    createMarine("marine-1", "house-alpha"),
    createMarine("marine-2", "house-alpha"),
    createMarine("marine-3", "house-alpha")
  ]

  var defendingForces: seq[GroundUnit] = @[
    createArmy("army-1", "house-beta"),
    createArmy("army-2", "house-beta")
  ]

  # Defense with all batteries destroyed (prerequisite for invasion)
  var defense = PlanetaryDefense(
    shields: some(ShieldLevel(level: 2, blockChance: 0.30, blockPercentage: 0.30)),
    groundBatteries: @[],  # All destroyed
    groundForces: defendingForces,
    spaceport: true
  )

  echo fmt"Attackers: {attackingForces.len} Marine Divisions (AS=7, DS=2 each)"
  echo fmt"Defenders: {defendingForces.len} Army Divisions (AS=5, DS=2 each)"
  echo "Shields: SLD2 (will be destroyed on landing)"

  let result = conductInvasion(attackingForces, defendingForces, defense, seed = 11111)

  echo fmt"Result: Success = {result.success}"
  echo fmt"  Attacker casualties: {result.attackerCasualties.len}"
  echo fmt"  Defender casualties: {result.defenderCasualties.len}"
  if result.success:
    echo fmt"  Infrastructure destroyed: {result.infrastructureDestroyed}%"
    echo "  Shields destroyed: Yes"
    echo "  Spaceport destroyed: Yes"

proc testPlanetaryBlitz*() =
  echo "\n=== Test: Planetary Blitz ==="

  # Create fleet with Marines
  var attackingFleet: seq[CombatSquadron] = @[]
  let destroyer = newEnhancedShip(ShipClass.Destroyer, techLevel = 1)
  let squadron = newSquadron(destroyer, id = "sq-att-1", owner = "house-alpha", location = 1)
  attackingFleet.add(CombatSquadron(
    squadron: squadron,
    state: CombatState.Undamaged,
    damageThisTurn: 0,
    crippleRound: 0,
    bucket: TargetBucket.Destroyer,
    targetWeight: 1.0
  ))

  var attackingForces: seq[GroundUnit] = @[
    createMarine("marine-1", "house-alpha"),
    createMarine("marine-2", "house-alpha")
  ]

  var defense = PlanetaryDefense(
    shields: some(ShieldLevel(level: 1, blockChance: 0.15, blockPercentage: 0.25)),
    groundBatteries: @[
      createGroundBattery("gb-1", "house-beta")
    ],
    groundForces: @[
      createArmy("army-1", "house-beta")
    ],
    spaceport: true
  )

  echo "Attackers: 1 Destroyer + 2 Marine Divisions"
  echo "Defenders: 1 Ground Battery + 1 Army"
  echo "Note: Marines get 0.5× AS penalty for quick insertion"

  let result = conductBlitz(attackingFleet, attackingForces, defense, seed = 22222)

  echo fmt"Result: Success = {result.success}"
  if result.success:
    echo fmt"  Assets seized: {result.assetsSeized}"
    echo fmt"  Infrastructure destroyed: {result.infrastructureDestroyed}% (intact)"
    echo "  Note: Shields, spaceports, batteries seized intact"

## Main test runner

when isMainModule:
  echo "╔════════════════════════════════════════════════╗"
  echo "║  EC4X Ground Combat Test Suite                ║"
  echo "╚════════════════════════════════════════════════╝"

  testBasicBombardment()
  testBombardmentWithShields()
  testPlanetBreakerShieldBypass()
  testPlanetaryInvasion()
  testPlanetaryBlitz()

  echo "\n╔════════════════════════════════════════════════╗"
  echo "║  All Ground Combat Tests Complete!            ║"
  echo "╚════════════════════════════════════════════════╝"
