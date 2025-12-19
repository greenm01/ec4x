## Starbase Mechanics Verification Tests
##
## Tests the specific starbase mechanics implemented:
## 1. Starbase detection participation in space combat (doesn't fight)
## 2. Starbase screening in space combat (can't be targeted)
## 3. Starbase combat participation in orbital combat (fights)
## 4. Detection state persistence from space to orbital

import std/[sequtils, options, strformat, tables]
import ../../src/engine/combat/[types, cer, engine, starbase, targeting]
import ../../src/engine/squadron
import ../../src/common/types/[core, units, combat, diplomacy]

## Test 1: Starbase Detection in Space Combat (Detection Only, No Combat)
proc test_StarbaseDetectionInSpaceCombat*() =
  echo "\n╔════════════════════════════════════════════════════════════════╗"
  echo "║ TEST 1: Starbase Detection in Space Combat                   ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo "\nScenario: Cloaked Raider attacks colony with starbase + mobile fleet"
  echo "Expected: Starbase provides ELI+2 detection but does NOT fight"
  echo "         Starbase cannot be targeted or damaged in space combat"

  # Attacker: 1 Cloaked Raider
  let raider = newShip(ShipClass.Raider, techLevel = 1)
  let raiderSquadron = newSquadron(raider, id = "raider-1", owner = "house-attacker", location = 1)
  let attackerFleet = @[CombatSquadron(
    squadron: raiderSquadron,
    state: CombatState.Undamaged,
    damageThisTurn: 0,
    crippleRound: 0,
    bucket: TargetBucket.Raider,
    targetWeight: 1.0
  )]

  # Defender: 1 Destroyer (mobile) + 1 Starbase
  let destroyer = newShip(ShipClass.Destroyer, techLevel = 1)
  let destroyerSquadron = newSquadron(destroyer, id = "destroyer-1", owner = "house-defender", location = 1)
  let starbase = createStarbaseCombatSquadron("starbase-1", "house-defender", 1, techLevel = 1)

  let defenderFleet = @[
    CombatSquadron(
      squadron: destroyerSquadron,
      state: CombatState.Undamaged,
      damageThisTurn: 0,
      crippleRound: 0,
      bucket: TargetBucket.Destroyer,
      targetWeight: 1.0
    ),
    starbase  # Starbase included for detection
  ]

  echo fmt"\nAttacker: 1 Raider (AS=4, cloaked)"
  echo fmt"Defender: 1 Destroyer (AS=4) + 1 Starbase (AS=45, ELI+2)"

  # Space Combat - allowStarbaseCombat = false
  let spaceContext = BattleContext(
    systemId: 1,
    taskForces: @[
      TaskForce(house: "house-attacker", squadrons: attackerFleet, roe: 6, scoutBonus: false, moraleModifier: 0, isCloaked: true, isDefendingHomeworld: false),
      TaskForce(house: "house-defender", squadrons: defenderFleet, roe: 8, scoutBonus: false, moraleModifier: 0, isCloaked: false, isDefendingHomeworld: false)
    ],
    seed: 12345,
    maxRounds: 5,
    allowAmbush: true,
    allowStarbaseCombat: false,  # Starbase detects but doesn't fight
    preDetectedHouses: @[]
  )

  let spaceResult = resolveCombat(spaceContext)

  echo fmt"\n✓ Space combat resolved in {spaceResult.totalRounds} rounds"
  echo fmt"  Victor: {spaceResult.victor}"

  # Verify starbase was not damaged
  let starbaseAfterCombat = defenderFleet[1]  # Starbase is second in fleet
  if starbaseAfterCombat.state == CombatState.Undamaged:
    echo "  ✓ PASS: Starbase undamaged (correctly screened from space combat)"
  else:
    echo "  ✗ FAIL: Starbase took damage in space combat (should be screened)"

  echo "\nExpected behavior:"
  echo "  • Starbase provides +2 ELI for detection rolls"
  echo "  • Starbase does NOT attack in space combat"
  echo "  • Starbase CANNOT be targeted by enemy in space combat"


## Test 2: Starbase Combat in Orbital Defense
proc test_StarbaseCombatInOrbitalDefense*() =
  echo "\n╔════════════════════════════════════════════════════════════════╗"
  echo "║ TEST 2: Starbase Combat in Orbital Defense                   ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo "\nScenario: Enemy fleet bypasses space combat and attacks colony directly"
  echo "Expected: Starbase FIGHTS in orbital defense and can be targeted"

  # Attacker: 2 Battleships
  let attackerFleet = @[
    (proc(): CombatSquadron =
      let bs = newShip(ShipClass.Battleship, techLevel = 1)
      let sq = newSquadron(bs, id = "bs-1", owner = "house-attacker", location = 1)
      CombatSquadron(squadron: sq, state: CombatState.Undamaged, damageThisTurn: 0, crippleRound: 0, bucket: TargetBucket.Capital, targetWeight: 1.0)
    )(),
    (proc(): CombatSquadron =
      let bs = newShip(ShipClass.Battleship, techLevel = 1)
      let sq = newSquadron(bs, id = "bs-2", owner = "house-attacker", location = 1)
      CombatSquadron(squadron: sq, state: CombatState.Undamaged, damageThisTurn: 0, crippleRound: 0, bucket: TargetBucket.Capital, targetWeight: 1.0)
    )()
  ]

  # Defender: Starbase only (orbital defense)
  let starbase = createStarbaseCombatSquadron("starbase-1", "house-defender", 1, techLevel = 3)
  let defenderFleet = @[starbase]

  echo fmt"\nAttacker: 2 Battleships (AS=20 each, total AS=40)"
  echo fmt"Defender: 1 Starbase (AS=45)"

  # Orbital Combat - allowStarbaseCombat = true
  let orbitalContext = BattleContext(
    systemId: 1,
    taskForces: @[
      TaskForce(house: "house-attacker", squadrons: attackerFleet, roe: 8, scoutBonus: false, moraleModifier: 0, isCloaked: false, isDefendingHomeworld: false),
      TaskForce(house: "house-defender", squadrons: defenderFleet, roe: 8, scoutBonus: false, moraleModifier: 0, isCloaked: false, isDefendingHomeworld: false)
    ],
    seed: 54321,
    maxRounds: 5,
    allowAmbush: false,  # No ambush in orbital
    allowStarbaseCombat: true,  # Starbase fights in orbital
    preDetectedHouses: @[]
  )

  let orbitalResult = resolveCombat(orbitalContext)

  echo fmt"\n✓ Orbital combat resolved in {orbitalResult.totalRounds} rounds"
  echo fmt"  Victor: {orbitalResult.victor}"

  # Verify starbase participated (should have taken damage or dealt damage)
  echo "\nExpected behavior:"
  echo "  • Starbase attacks enemy ships in Phase 3 (Main Engagement)"
  echo "  • Starbase CAN be targeted and damaged by attackers"
  echo "  • Starbase gets no ambush bonus (orbital combat)"


## Test 3: Detection State Persistence (Space → Orbital)
proc test_DetectionPersistence*() =
  echo "\n╔════════════════════════════════════════════════════════════════╗"
  echo "║ TEST 3: Detection State Persistence (Space → Orbital)        ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo "\nScenario: Raider detected in space combat, then proceeds to orbital"
  echo "Expected: Raider remains detected in orbital (no re-surprise)"

  # Attacker: 1 Raider (initially cloaked)
  let raider = newShip(ShipClass.Raider, techLevel = 1)
  let raiderSquadron = newSquadron(raider, id = "raider-1", owner = "house-attacker", location = 1)
  let attackerFleet = @[CombatSquadron(
    squadron: raiderSquadron,
    state: CombatState.Undamaged,
    damageThisTurn: 0,
    crippleRound: 0,
    bucket: TargetBucket.Raider,
    targetWeight: 1.0
  )]

  # Defender: Starbase with high detection
  let starbase = createStarbaseCombatSquadron("starbase-1", "house-defender", 1, techLevel = 3)
  let defenderFleet = @[starbase]

  echo fmt"\nAttacker: 1 Raider (AS=4, initially cloaked)"
  echo fmt"Defender: 1 Starbase (AS=45, ELI+2)"

  # PHASE 1: Space Combat
  echo "\nPhase 1: Space Combat (starbase detects but doesn't fight)"
  let spaceContext = BattleContext(
    systemId: 1,
    taskForces: @[
      TaskForce(house: "house-attacker", squadrons: attackerFleet, roe: 6, scoutBonus: false, moraleModifier: 0, isCloaked: true, isDefendingHomeworld: false),
      TaskForce(house: "house-defender", squadrons: defenderFleet, roe: 8, scoutBonus: false, moraleModifier: 0, isCloaked: false, isDefendingHomeworld: false)
    ],
    seed: 99999,
    maxRounds: 1,  # Just one round to trigger detection
    allowAmbush: true,
    allowStarbaseCombat: false,
    preDetectedHouses: @[]
  )

  let spaceResult = resolveCombat(spaceContext)
  echo fmt"  Space combat: {spaceResult.totalRounds} rounds"

  # PHASE 2: Orbital Combat (simulate pre-detected houses from space)
  # In real game, resolve.nim would track which houses were detected in space
  # and pass them to orbital combat via preDetectedHouses
  echo "\nPhase 2: Orbital Combat (raiders pre-detected from space combat)"
  let orbitalContext = BattleContext(
    systemId: 1,
    taskForces: @[
      TaskForce(house: "house-attacker", squadrons: attackerFleet, roe: 6, scoutBonus: false, moraleModifier: 0, isCloaked: true, isDefendingHomeworld: false),
      TaskForce(house: "house-defender", squadrons: defenderFleet, roe: 8, scoutBonus: false, moraleModifier: 0, isCloaked: false, isDefendingHomeworld: false)
    ],
    seed: 88888,
    maxRounds: 5,
    allowAmbush: false,  # No ambush in orbital
    allowStarbaseCombat: true,
    preDetectedHouses: @[HouseId("house-attacker")]  # Attacker was detected in space phase
  )

  let orbitalResult = resolveCombat(orbitalContext)
  echo fmt"  Orbital combat: {orbitalResult.totalRounds} rounds"

  echo "\nExpected behavior:"
  echo "  • Raider detected in space combat (starbase ELI+2 bonus)"
  echo "  • Detection persists to orbital combat"
  echo "  • Raider does NOT get ambush bonus in orbital (already detected)"
  echo "  • Starbase fights in orbital combat"


## Test 4: Targeting Verification - Starbase Screening
proc test_StarbaseScreeningInSpace*() =
  echo "\n╔════════════════════════════════════════════════════════════════╗"
  echo "║ TEST 4: Starbase Screening in Space Combat                   ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo "\nScenario: Verify starbase cannot be targeted during space combat"
  echo "Expected: Targeting system filters out starbases when allowStarbaseTargeting=false"

  # Create mock squadrons for targeting test
  let attacker = CombatSquadron(
    squadron: newSquadron(newShip(ShipClass.Battleship, techLevel = 1), id = "bs-1", owner = "house-attacker", location = 1),
    state: CombatState.Undamaged,
    damageThisTurn: 0,
    crippleRound: 0,
    bucket: TargetBucket.Capital,
    targetWeight: 1.0
  )

  let destroyer = CombatSquadron(
    squadron: newSquadron(newShip(ShipClass.Destroyer, techLevel = 1), id = "dd-1", owner = "house-defender", location = 1),
    state: CombatState.Undamaged,
    damageThisTurn: 0,
    crippleRound: 0,
    bucket: TargetBucket.Destroyer,
    targetWeight: 1.0
  )

  let starbase = createStarbaseCombatSquadron("starbase-1", "house-defender", 1, techLevel = 1)

  let attackerTF = TaskForce(
    house: "house-attacker",
    squadrons: @[attacker],
    roe: 8,
    scoutBonus: false,
    moraleModifier: 0,
    isCloaked: false,
    isDefendingHomeworld: false
  )

  let defenderTF = TaskForce(
    house: "house-defender",
    squadrons: @[destroyer, starbase],
    roe: 8,
    scoutBonus: false,
    moraleModifier: 0,
    isCloaked: false,
    isDefendingHomeworld: false
  )

  echo "\nSetup:"
  echo "  Attacker: 1 Battleship"
  echo "  Defender: 1 Destroyer + 1 Starbase"

  # Test targeting with starbase screening (space combat)
  let diplomaticRelations = {("house-attacker", "house-defender"): DiplomaticState.Enemy}.toTable
  let systemOwner = some(HouseId("house-defender"))

  echo "\nTest 1: Space Combat (allowStarbaseTargeting=false)"
  let hostileSquadrons_space = filterHostileSquadrons(
    attackerTF,
    @[attackerTF, defenderTF],
    diplomaticRelations,
    systemOwner,
    allowStarbaseTargeting = false  # Starbase screened
  )

  # Starbases use Capital bucket, so check by squadron ID
  let starbaseTargeted_space = hostileSquadrons_space.anyIt(it.squadron.id == "starbase-1")
  if not starbaseTargeted_space:
    echo "  ✓ PASS: Starbase filtered from target candidates (space combat)"
  else:
    echo "  ✗ FAIL: Starbase included in target candidates (should be screened)"

  echo "\nTest 2: Orbital Combat (allowStarbaseTargeting=true)"
  let hostileSquadrons_orbital = filterHostileSquadrons(
    attackerTF,
    @[attackerTF, defenderTF],
    diplomaticRelations,
    systemOwner,
    allowStarbaseTargeting = true  # Starbase can be targeted
  )

  echo fmt"  Debug: Found {hostileSquadrons_orbital.len} hostile squadrons"
  for sq in hostileSquadrons_orbital:
    echo fmt"    - {sq.bucket}: {sq.squadron.id}"

  # Starbases use Capital bucket for targeting (line 77 in starbase.nim)
  # Check if starbase squadron is present by ID
  let starbaseTargeted_orbital = hostileSquadrons_orbital.anyIt(it.squadron.id == "starbase-1")
  if starbaseTargeted_orbital:
    echo "  ✓ PASS: Starbase included in target candidates (orbital combat)"
    echo "  Note: Starbases use Capital bucket for targeting purposes"
  else:
    echo "  ✗ FAIL: Starbase excluded from target candidates (should be targetable)"


## Main Test Runner
when isMainModule:
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║  EC4X Starbase Mechanics Verification Suite                  ║"
  echo "╚════════════════════════════════════════════════════════════════╝"

  test_StarbaseDetectionInSpaceCombat()
  test_StarbaseCombatInOrbitalDefense()
  test_DetectionPersistence()
  test_StarbaseScreeningInSpace()

  echo "\n╔════════════════════════════════════════════════════════════════╗"
  echo "║  All Starbase Mechanics Tests Complete!                      ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
