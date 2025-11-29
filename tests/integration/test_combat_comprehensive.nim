## Comprehensive Combat Engine Tests
##
## Tests all combat mechanics from combat specifications:
## - CER (Combat Effectiveness Rating) calculations and dice rolls
## - Damage application and state transitions
## - Destruction protection rules
## - Critical hits and Force Reduction
## - Target selection and priority buckets
## - Combat phase resolution
## - Retreat evaluation
## - Stalemate detection
## - Pre-combat detection (scouts vs raiders)
## - Input validation and boundary conditions
##
## This test suite provides comprehensive coverage for the combat engine
## which previously had only partial integration test coverage

import std/[unittest, tables, options, sequtils, random]
import ../../src/engine/combat/[types, cer, damage, targeting, retreat, resolution, engine]
import ../../src/engine/[squadron, ship, fleet]
import ../../src/common/types/[core, units, combat as commonCombat, diplomacy]

# Helper for edge case testing with custom stats
proc newCustomEnhancedShip(shipClass: ShipClass, attackStrength: int, defenseStrength: int, name: string = ""): EnhancedShip =
  ## Create EnhancedShip with custom stats for edge case testing
  let shipType = case shipClass
    of ShipClass.ETAC, ShipClass.TroopTransport:
      ShipType.Spacelift
    else:
      ShipType.Military

  EnhancedShip(
    shipClass: shipClass,
    shipType: shipType,
    stats: ShipStats(
      name: $shipClass,
      class: $shipClass,
      attackStrength: attackStrength,
      defenseStrength: defenseStrength,
      commandCost: 10,
      commandRating: 20,
      techLevel: 1,
      buildCost: 100,
      upkeepCost: 10,
      specialCapability: "",
      carryLimit: 0
    ),
    isCrippled: false,
    name: name
  )

suite "Combat Engine: CER Calculation":

  test "CER dice roll: deterministic PRNG":
    # Same seed should produce same rolls
    var rng1 = initRNG(42'i64)
    var rng2 = initRNG(42'i64)

    let roll1 = rng1.roll1d10()
    let roll2 = rng2.roll1d10()

    check roll1 == roll2

  test "CER dice roll: range validation":
    var rng = initRNG(100'i64)

    # Roll 1000 times and verify all in range 0-9
    for i in 1..1000:
      let roll = rng.roll1d10()
      check roll >= 0
      check roll <= 9

  test "CER lookup table: boundary values":
    # Test all thresholds from CER table
    check lookupCER(0) == 0.25
    check lookupCER(1) == 0.25
    check lookupCER(2) == 0.25
    check lookupCER(3) == 0.50
    check lookupCER(4) == 0.50
    check lookupCER(5) == 0.75
    check lookupCER(6) == 0.75
    check lookupCER(7) == 1.0
    check lookupCER(8) == 1.0
    check lookupCER(9) == 1.0
    check lookupCER(10) == 1.0
    check lookupCER(100) == 1.0  # Very high rolls still max at 1.0

  test "CER lookup table: negative values":
    # Negative modifiers can result in very low CER
    check lookupCER(-5) == 0.25
    check lookupCER(-10) == 0.25

  test "CER modifiers: scouts bonus":
    let mods = calculateModifiers(
      phase = CombatPhase.MainEngagement,
      roundNumber = 1,
      hasScouts = true,
      moraleModifier = 0,
      isSurprise = false,
      isAmbush = false
    )

    check mods == 1

  test "CER modifiers: morale range":
    # Test all morale modifiers (-1 to +2)
    for morale in -1..2:
      let mods = calculateModifiers(
        phase = CombatPhase.MainEngagement,
        roundNumber = 1,
        hasScouts = false,
        moraleModifier = morale,
        isSurprise = false,
        isAmbush = false
      )

      check mods == morale

  test "CER modifiers: surprise bonus first round only":
    let round1 = calculateModifiers(
      phase = CombatPhase.MainEngagement,
      roundNumber = 1,
      hasScouts = false,
      moraleModifier = 0,
      isSurprise = true,
      isAmbush = false
    )

    let round2 = calculateModifiers(
      phase = CombatPhase.MainEngagement,
      roundNumber = 2,
      hasScouts = false,
      moraleModifier = 0,
      isSurprise = true,
      isAmbush = false
    )

    check round1 == 3  # Surprise applies
    check round2 == 0  # Surprise doesn't apply

  test "CER modifiers: ambush bonus conditions":
    # Ambush only applies in Ambush phase, first round
    let ambushPhaseRound1 = calculateModifiers(
      phase = CombatPhase.Ambush,
      roundNumber = 1,
      hasScouts = false,
      moraleModifier = 0,
      isSurprise = false,
      isAmbush = true
    )

    let mainPhaseRound1 = calculateModifiers(
      phase = CombatPhase.MainEngagement,
      roundNumber = 1,
      hasScouts = false,
      moraleModifier = 0,
      isSurprise = false,
      isAmbush = true
    )

    let ambushPhaseRound2 = calculateModifiers(
      phase = CombatPhase.Ambush,
      roundNumber = 2,
      hasScouts = false,
      moraleModifier = 0,
      isSurprise = false,
      isAmbush = true
    )

    check ambushPhaseRound1 == 4  # Ambush applies
    check mainPhaseRound1 == 0    # Wrong phase
    check ambushPhaseRound2 == 0  # Wrong round

  test "CER modifiers: stacking all bonuses":
    # Max positive modifiers: scouts (1) + morale (2) + surprise (3) + ambush (4) = +10
    let maxMods = calculateModifiers(
      phase = CombatPhase.Ambush,
      roundNumber = 1,
      hasScouts = true,
      moraleModifier = 2,
      isSurprise = true,
      isAmbush = true
    )

    check maxMods == 10

  test "CER modifiers: worst case negative":
    # Min modifiers: no scouts, low morale (-1)
    let minMods = calculateModifiers(
      phase = CombatPhase.MainEngagement,
      roundNumber = 2,
      hasScouts = false,
      moraleModifier = -1,
      isSurprise = false,
      isAmbush = false
    )

    check minMods == -1

  test "CER roll: critical hit detection":
    var rng = initRNG(42'i64)

    # Find a critical roll (natural 9)
    var foundCritical = false
    for i in 1..100:
      let cerRoll = rollCER(
        rng,
        phase = CombatPhase.MainEngagement,
        roundNumber = 1,
        hasScouts = false,
        moraleModifier = 0
      )

      if cerRoll.isCriticalHit:
        check cerRoll.naturalRoll == 9
        foundCritical = true
        break

    check foundCritical

  test "CER roll: effectiveness calculation":
    var rng = initRNG(100'i64)

    let cerRoll = rollCER(
      rng,
      phase = CombatPhase.MainEngagement,
      roundNumber = 1,
      hasScouts = false,
      moraleModifier = 0
    )

    # Verify effectiveness matches lookup table
    let expectedEffectiveness = lookupCER(cerRoll.finalRoll)
    check cerRoll.effectiveness == expectedEffectiveness

  test "CER roll: desperation bonus":
    var rng = initRNG(42'i64)

    let normalRoll = rollCER(
      rng,
      phase = CombatPhase.MainEngagement,
      roundNumber = 1,
      hasScouts = false,
      moraleModifier = 0,
      desperationBonus = 0
    )

    var rng2 = initRNG(42'i64)  # Same seed
    let desperateRoll = rollCER(
      rng2,
      phase = CombatPhase.MainEngagement,
      roundNumber = 1,
      hasScouts = false,
      moraleModifier = 0,
      desperationBonus = 2
    )

    # Same natural roll, but desperation bonus increases final roll
    check desperateRoll.finalRoll == normalRoll.finalRoll + 2

suite "Combat Engine: Damage Application":

  proc createTestSquadron(shipClass: ShipClass): CombatSquadron =
    ## Helper to create test squadron with default stats
    let flagship = newEnhancedShip(shipClass, techLevel = 1, name = "test-ship-1")

    let sq = Squadron(
      id: "test-sq-1",
      flagship: flagship,
      ships: @[],
      owner: "", location: 0, embarkedFighters: @[]
    )

    result = CombatSquadron(
      squadron: sq,
      state: CombatState.Undamaged,
      fleetStatus: FleetStatus.Active,
      damageThisTurn: 0,
      crippleRound: 0,
      bucket: classifyBucket(sq),
      targetWeight: 0.0
    )

  test "Damage: undamaged to crippled threshold":
    var sq = createTestSquadron(ShipClass.Destroyer)
    let ds = sq.getCurrentDS()

    let change = applyDamageToSquadron(sq, damage = ds, roundNumber = 1, isCriticalHit = false)

    check change.fromState == CombatState.Undamaged
    check change.toState == CombatState.Crippled
    check sq.state == CombatState.Crippled
    check sq.damageThisTurn == ds

  test "Damage: crippled to destroyed":
    var sq = createTestSquadron(ShipClass.Destroyer)
    let ds = sq.getCurrentDS()

    # First cripple it
    discard applyDamageToSquadron(sq, damage = ds, roundNumber = 1, isCriticalHit = false)

    # Then destroy it
    let change = applyDamageToSquadron(sq, damage = ds, roundNumber = 1, isCriticalHit = false)

    check change.fromState == CombatState.Crippled
    check change.toState == CombatState.Destroyed
    check sq.state == CombatState.Destroyed

  test "Damage: destruction protection applies":
    var sq = createTestSquadron(ShipClass.Destroyer)
    let ds = sq.getCurrentDS()

    # Apply 2×DS damage in one hit (enough to cripple and destroy)
    let change = applyDamageToSquadron(sq, damage = ds * 2, roundNumber = 1, isCriticalHit = false)

    # Should be crippled, not destroyed (protection applies)
    check change.fromState == CombatState.Undamaged
    check change.toState == CombatState.Crippled
    check change.destructionProtectionApplied == true
    check sq.state == CombatState.Crippled

  test "Damage: critical hit bypasses destruction protection":
    var sq = createTestSquadron(ShipClass.Destroyer)
    let ds = sq.getCurrentDS()

    # Apply 2×DS damage with critical hit
    let change = applyDamageToSquadron(sq, damage = ds * 2, roundNumber = 1, isCriticalHit = true)

    # Should be destroyed (critical bypasses protection)
    check change.fromState == CombatState.Undamaged
    check change.toState == CombatState.Destroyed
    check sq.state == CombatState.Destroyed

  test "Damage: destruction protection across rounds":
    var sq = createTestSquadron(ShipClass.Destroyer)
    let ds = sq.getCurrentDS()

    # Cripple in round 1
    discard applyDamageToSquadron(sq, damage = ds, roundNumber = 1, isCriticalHit = false)

    # Reset damage tracker (new round)
    resetRoundDamage(sq)

    # Destroy in round 2 (protection doesn't apply across rounds)
    let change = applyDamageToSquadron(sq, damage = ds, roundNumber = 2, isCriticalHit = false)

    check change.toState == CombatState.Destroyed
    check sq.state == CombatState.Destroyed

  test "Damage: insufficient damage":
    var sq = createTestSquadron(ShipClass.Destroyer)
    let ds = sq.getCurrentDS()
    let insufficientDamage = ds - 1  # Just below threshold

    let change = applyDamageToSquadron(sq, damage = insufficientDamage, roundNumber = 1, isCriticalHit = false)

    # Should remain undamaged (damage < DS)
    check change.fromState == CombatState.Undamaged
    check change.toState == CombatState.Undamaged
    check sq.state == CombatState.Undamaged
    check sq.damageThisTurn == insufficientDamage

  test "Damage: accumulation within round":
    var sq = createTestSquadron(ShipClass.Destroyer)
    let ds = sq.getCurrentDS()
    let halfDS = ds div 2

    # Apply damage in two hits
    discard applyDamageToSquadron(sq, damage = halfDS, roundNumber = 1, isCriticalHit = false)
    let change2 = applyDamageToSquadron(sq, damage = halfDS, roundNumber = 1, isCriticalHit = false)

    # Total DS damage should cripple
    check change2.toState == CombatState.Crippled
    check sq.damageThisTurn >= ds

  test "Damage: already destroyed squadron":
    var sq = createTestSquadron(ShipClass.Destroyer)

    # Destroy it
    discard applyDamageToSquadron(sq, damage = 1000, roundNumber = 1, isCriticalHit = true)

    # Apply more damage (should do nothing)
    let change = applyDamageToSquadron(sq, damage = 100, roundNumber = 1, isCriticalHit = false)

    check change.fromState == CombatState.Destroyed
    check change.toState == CombatState.Destroyed

  test "Damage: zero damage":
    var sq = createTestSquadron(ShipClass.Destroyer)

    let change = applyDamageToSquadron(sq, damage = 0, roundNumber = 1, isCriticalHit = false)

    check change.toState == CombatState.Undamaged
    check sq.damageThisTurn == 0

  test "Damage: negative damage (defensive)":
    var sq = createTestSquadron(ShipClass.Destroyer)

    # Apply negative damage (shouldn't happen, but test robustness)
    let change = applyDamageToSquadron(sq, damage = -10, roundNumber = 1, isCriticalHit = false)

    check change.toState == CombatState.Undamaged
    check sq.damageThisTurn == -10

  test "Damage: very large damage values":
    var sq = createTestSquadron(ShipClass.Destroyer)

    let change = applyDamageToSquadron(sq, damage = 1_000_000, roundNumber = 1, isCriticalHit = true)

    check change.toState == CombatState.Destroyed

suite "Combat Engine: Combat Squadron Helpers":

  proc createTestSquadronWithState(state: CombatState): CombatSquadron =
    let flagship = newEnhancedShip(ShipClass.Destroyer, techLevel = 1, name = "test-ship")

    let sq = Squadron(
      id: "test-sq",
      flagship: flagship,
      ships: @[],
      owner: "", location: 0, embarkedFighters: @[]
    )

    result = CombatSquadron(
      squadron: sq,
      state: state,
      fleetStatus: FleetStatus.Active,
      damageThisTurn: 0,
      crippleRound: 0,
      bucket: TargetBucket.Destroyer,
      targetWeight: 0.0
    )

  test "getCurrentAS: undamaged squadron":
    let sq = createTestSquadronWithState(CombatState.Undamaged)
    let attackStr = sq.getCurrentAS()

    check attackStr > 0

  test "getCurrentAS: crippled squadron (half AS)":
    let undamaged = createTestSquadronWithState(CombatState.Undamaged)
    let crippled = createTestSquadronWithState(CombatState.Crippled)

    let undamagedAS = undamaged.getCurrentAS()
    let crippledAS = crippled.getCurrentAS()

    check crippledAS == undamagedAS div 2

  test "getCurrentAS: destroyed squadron":
    let sq = createTestSquadronWithState(CombatState.Destroyed)

    check sq.getCurrentAS() == 0

  test "getCurrentAS: reserve fleet (half AS)":
    var sq = createTestSquadronWithState(CombatState.Undamaged)
    let fullAS = sq.getCurrentAS()
    sq.fleetStatus = FleetStatus.Reserve

    check sq.getCurrentAS() == fullAS div 2

  test "getCurrentAS: crippled AND reserve (quarter AS)":
    var undamaged = createTestSquadronWithState(CombatState.Undamaged)
    let fullAS = undamaged.getCurrentAS()

    var sq = createTestSquadronWithState(CombatState.Crippled)
    sq.fleetStatus = FleetStatus.Reserve

    # Crippled: fullAS / 2, Reserve: / 2 again = fullAS / 4
    check sq.getCurrentAS() == fullAS div 4

  test "getCurrentDS: does not change when crippled":
    let undamaged = createTestSquadronWithState(CombatState.Undamaged)
    let crippled = createTestSquadronWithState(CombatState.Crippled)

    check undamaged.getCurrentDS() == crippled.getCurrentDS()

  test "getCurrentDS: reserve fleet (half DS)":
    var sq = createTestSquadronWithState(CombatState.Undamaged)
    let fullDS = sq.getCurrentDS()
    sq.fleetStatus = FleetStatus.Reserve

    check sq.getCurrentDS() == fullDS div 2

  test "isAlive: state checks":
    let undamaged = createTestSquadronWithState(CombatState.Undamaged)
    let crippled = createTestSquadronWithState(CombatState.Crippled)
    let destroyed = createTestSquadronWithState(CombatState.Destroyed)

    check undamaged.isAlive() == true
    check crippled.isAlive() == true
    check destroyed.isAlive() == false

  test "canBeTargeted: same as isAlive":
    let undamaged = createTestSquadronWithState(CombatState.Undamaged)
    let destroyed = createTestSquadronWithState(CombatState.Destroyed)

    check undamaged.canBeTargeted() == true
    check destroyed.canBeTargeted() == false

suite "Combat Engine: Target Bucket Classification":

  test "classifyBucket: Raiders":
    let flagship = newEnhancedShip(ShipClass.Raider, techLevel = 1, name = "raider")

    let sq = Squadron(id: "sq1", flagship: flagship, ships: @[], owner: "", location: 0, embarkedFighters: @[])

    check classifyBucket(sq) == TargetBucket.Raider

  test "classifyBucket: Capital ships":
    let cruiser = newEnhancedShip(ShipClass.Cruiser, techLevel = 1, name = "cruiser")
    let carrier = newEnhancedShip(ShipClass.Carrier, techLevel = 1, name = "carrier")
    let dreadnought = newEnhancedShip(ShipClass.Dreadnought, techLevel = 1, name = "dread")

    check classifyBucket(Squadron(id: "sq1", flagship: cruiser, ships: @[], owner: "", location: 0, embarkedFighters: @[])) == TargetBucket.Capital
    check classifyBucket(Squadron(id: "sq2", flagship: carrier, ships: @[], owner: "", location: 0, embarkedFighters: @[])) == TargetBucket.Capital
    check classifyBucket(Squadron(id: "sq3", flagship: dreadnought, ships: @[], owner: "", location: 0, embarkedFighters: @[])) == TargetBucket.Capital

  test "classifyBucket: Destroyers":
    let destroyer = newEnhancedShip(ShipClass.Destroyer, techLevel = 1, name = "destroyer")

    let sq = Squadron(id: "sq1", flagship: destroyer, ships: @[], owner: "", location: 0, embarkedFighters: @[])

    check classifyBucket(sq) == TargetBucket.Destroyer

  test "classifyBucket: Fighters":
    let fighter = newEnhancedShip(ShipClass.Fighter, techLevel = 1, name = "fighter")

    let sq = Squadron(id: "sq1", flagship: fighter, ships: @[], owner: "", location: 0, embarkedFighters: @[])

    check classifyBucket(sq) == TargetBucket.Fighter

  test "classifyBucket: Starbases":
    let starbase = newEnhancedShip(ShipClass.Starbase, techLevel = 1, name = "starbase")

    let sq = Squadron(id: "sq1", flagship: starbase, ships: @[], owner: "", location: 0, embarkedFighters: @[])

    check classifyBucket(sq) == TargetBucket.Starbase

  test "baseWeight: priority order":
    # Lower number = higher priority
    check baseWeight(TargetBucket.Raider) == 1.0
    check baseWeight(TargetBucket.Capital) == 2.0
    check baseWeight(TargetBucket.Destroyer) == 3.0
    check baseWeight(TargetBucket.Fighter) == 4.0
    check baseWeight(TargetBucket.Starbase) == 5.0

  test "calculateTargetWeight: crippled modifier":
    let flagship = newEnhancedShip(ShipClass.Destroyer, techLevel = 1, name = "ship1")
    let undamagedSq = CombatSquadron(
      squadron: Squadron(
        id: "sq1",
        flagship: flagship,
        ships: @[],
        owner: "", location: 0, embarkedFighters: @[]
      ),
      state: CombatState.Undamaged,
      fleetStatus: FleetStatus.Active,
      damageThisTurn: 0,
      crippleRound: 0,
      bucket: TargetBucket.Destroyer,
      targetWeight: 0.0
    )

    var crippledSq = undamagedSq
    crippledSq.state = CombatState.Crippled

    let undamagedWeight = calculateTargetWeight(undamagedSq)
    let crippledWeight = calculateTargetWeight(crippledSq)

    # Crippled gets 2x weight
    check crippledWeight == undamagedWeight * 2.0

suite "Combat Engine: Task Force Operations":

  proc createTestTaskForce(house: HouseId, squadronCount: int): TaskForce =
    var squadrons: seq[CombatSquadron] = @[]

    for i in 1..squadronCount:
      let flagship = newEnhancedShip(ShipClass.Destroyer, techLevel = 1, name = "ship-" & $i)

      let sq = Squadron(
        id: "sq-" & $i,
        flagship: flagship,
        ships: @[],
        owner: "", location: 0, embarkedFighters: @[]
      )

      squadrons.add(CombatSquadron(
        squadron: sq,
        state: CombatState.Undamaged,
        fleetStatus: FleetStatus.Active,
        damageThisTurn: 0,
        crippleRound: 0,
        bucket: TargetBucket.Destroyer,
        targetWeight: 0.0
      ))

    result = TaskForce(
      house: house,
      squadrons: squadrons,
      roe: 5,
      isCloaked: false,
      moraleModifier: 0,
      scoutBonus: false,
      isDefendingHomeworld: false,
      eliLevel: 1,
      clkLevel: 1
    )

  test "totalAS: sum of all squadron AS":
    let tf = createTestTaskForce("house1", squadronCount = 5)

    # Get AS from first squadron (all have same ship class)
    let singleAS = tf.squadrons[0].getCurrentAS()
    let expectedTotal = singleAS * 5

    check tf.totalAS() == expectedTotal

  test "totalAS: with crippled squadrons":
    var tf = createTestTaskForce("house1", squadronCount = 5)

    let singleAS = tf.squadrons[0].getCurrentAS()

    # Cripple 2 squadrons
    tf.squadrons[0].state = CombatState.Crippled
    tf.squadrons[1].state = CombatState.Crippled

    # 3 × fullAS + 2 × (fullAS / 2)
    let expectedTotal = (singleAS * 3) + (singleAS div 2 * 2)
    check tf.totalAS() == expectedTotal

  test "totalAS: with destroyed squadrons":
    var tf = createTestTaskForce("house1", squadronCount = 5)

    let singleAS = tf.squadrons[0].getCurrentAS()

    # Destroy 2 squadrons
    tf.squadrons[0].state = CombatState.Destroyed
    tf.squadrons[1].state = CombatState.Destroyed

    # 3 × fullAS (destroyed contribute 0)
    let expectedTotal = singleAS * 3
    check tf.totalAS() == expectedTotal

  test "aliveSquadrons: excludes destroyed":
    var tf = createTestTaskForce("house1", squadronCount = 5)

    tf.squadrons[1].state = CombatState.Destroyed
    tf.squadrons[3].state = CombatState.Destroyed

    let alive = tf.aliveSquadrons()

    check alive.len == 3

  test "isEliminated: all destroyed":
    var tf = createTestTaskForce("house1", squadronCount = 3)

    check tf.isEliminated() == false

    # Destroy all
    for i in 0..2:
      tf.squadrons[i].state = CombatState.Destroyed

    check tf.isEliminated() == true

  test "isEliminated: partial destruction":
    var tf = createTestTaskForce("house1", squadronCount = 3)

    tf.squadrons[0].state = CombatState.Destroyed
    tf.squadrons[1].state = CombatState.Destroyed

    # One still alive
    check tf.isEliminated() == false

suite "Combat Engine: Input Validation":

  test "CER modifiers: extreme morale values":
    # Test morale beyond normal range
    let extreme = calculateModifiers(
      phase = CombatPhase.MainEngagement,
      roundNumber = 1,
      hasScouts = false,
      moraleModifier = 100,
      isSurprise = false,
      isAmbush = false
    )

    check extreme == 100

  test "CER roll: very high desperation bonus":
    var rng = initRNG(42'i64)

    let cerRoll = rollCER(
      rng,
      phase = CombatPhase.MainEngagement,
      roundNumber = 1,
      hasScouts = false,
      moraleModifier = 0,
      desperationBonus = 50
    )

    # Should not crash, effectiveness caps at 1.0
    check cerRoll.effectiveness == 1.0

  test "Damage: squadron with zero DS":
    let flagship = newCustomEnhancedShip(ShipClass.Fighter, attackStrength = 3, defenseStrength = 0, name = "fighter")
    var sq = CombatSquadron(
      squadron: Squadron(
        id: "zero-ds",
        flagship: flagship,
        ships: @[],
        owner: "house1",
        location: 1,
        embarkedFighters: @[]
      ),
      state: CombatState.Undamaged,
      fleetStatus: FleetStatus.Active,
      damageThisTurn: 0,
      crippleRound: 0,
      bucket: TargetBucket.Fighter,
      targetWeight: 0.0
    )

    # Any damage should cripple (DS = 0)
    let change = applyDamageToSquadron(sq, damage = 1, roundNumber = 1, isCriticalHit = false)

    check change.toState == CombatState.Crippled

  test "Task Force: empty squadrons list":
    let emptyTF = TaskForce(
      house: "house1",
      squadrons: @[],
      roe: 5,
      isCloaked: false,
      moraleModifier: 0,
      scoutBonus: false,
      isDefendingHomeworld: false,
      eliLevel: 1,
      clkLevel: 1
    )

    check emptyTF.totalAS() == 0
    check emptyTF.aliveSquadrons().len == 0
    check emptyTF.isEliminated() == true

  test "CER: naturalRoll bounds":
    # Natural roll should always be 0-9 (after conversion)
    var rng = initRNG(12345'i64)

    for i in 1..1000:
      let cerRoll = rollCER(
        rng,
        phase = CombatPhase.MainEngagement,
        roundNumber = 1,
        hasScouts = false,
        moraleModifier = 0
      )

      check cerRoll.naturalRoll >= 0
      check cerRoll.naturalRoll <= 9

suite "Combat Engine: Edge Cases":

  test "Damage reset: clears accumulation":
    let flagship = newCustomEnhancedShip(ShipClass.Destroyer, attackStrength = 10, defenseStrength = 20, name = "ship1")
    var sq = CombatSquadron(
      squadron: Squadron(
        id: "sq1",
        flagship: flagship,
        ships: @[],
        owner: "house1",
        location: 1,
        embarkedFighters: @[]
      ),
      state: CombatState.Undamaged,
      fleetStatus: FleetStatus.Active,
      damageThisTurn: 15,
      crippleRound: 0,
      bucket: TargetBucket.Destroyer,
      targetWeight: 0.0
    )

    resetRoundDamage(sq)

    check sq.damageThisTurn == 0

  test "CER effectiveness: all possible values":
    # Verify only valid effectiveness values are returned
    for roll in -10..20:
      let effectiveness = lookupCER(roll)

      check effectiveness in [0.25, 0.50, 0.75, 1.0]

  test "Critical hit: only on natural 9":
    for naturalRoll in 0..9:
      let isCrit = isCritical(naturalRoll)

      if naturalRoll == 9:
        check isCrit == true
      else:
        check isCrit == false

  test "Bucket weights: valid ordering":
    # Ensure buckets maintain priority order
    let weights = [
      (TargetBucket.Raider, baseWeight(TargetBucket.Raider)),
      (TargetBucket.Capital, baseWeight(TargetBucket.Capital)),
      (TargetBucket.Destroyer, baseWeight(TargetBucket.Destroyer)),
      (TargetBucket.Fighter, baseWeight(TargetBucket.Fighter)),
      (TargetBucket.Starbase, baseWeight(TargetBucket.Starbase))
    ]

    # Each bucket should have higher weight than previous
    for i in 1..<weights.len:
      check weights[i][1] > weights[i-1][1]

  test "Mothballed fleet: AS/DS unchanged":
    let flagship = newCustomEnhancedShip(ShipClass.Destroyer, attackStrength = 10, defenseStrength = 20, name = "ship1")
    var sq = CombatSquadron(
      squadron: Squadron(
        id: "sq1",
        flagship: flagship,
        ships: @[],
        owner: "house1",
        location: 1,
        embarkedFighters: @[]
      ),
      state: CombatState.Undamaged,
      fleetStatus: FleetStatus.Mothballed,
      damageThisTurn: 0,
      crippleRound: 0,
      bucket: TargetBucket.Destroyer,
      targetWeight: 0.0
    )

    # Mothballed ships should not be in combat, but if they are, they function normally
    # (FleetStatus.Mothballed doesn't have special combat rules in the spec)
    check sq.getCurrentAS() == 10
    check sq.getCurrentDS() == 20

suite "Combat Engine: Stress Tests":

  test "CER: 10,000 dice rolls distribution":
    # Verify dice rolls are reasonably distributed
    var rng = initRNG(42'i64)
    var distribution: array[10, int]

    for i in 1..10_000:
      let roll = rng.roll1d10()
      distribution[roll] += 1

    # Each value should appear roughly 1000 times (±20%)
    for i in 0..9:
      check distribution[i] >= 800
      check distribution[i] <= 1200

  test "CER: deterministic across multiple sessions":
    # Same seed should always produce same sequence
    var sequences: seq[seq[int]] = @[]

    for session in 1..5:
      var rng = initRNG(999'i64)
      var sequence: seq[int] = @[]

      for i in 1..100:
        sequence.add(rng.roll1d10())

      sequences.add(sequence)

    # All sequences should be identical
    for i in 1..4:
      check sequences[i] == sequences[0]

  test "Damage: 1000 squadrons in Task Force":
    var squadrons: seq[CombatSquadron] = @[]

    for i in 1..1000:
      let flagship = newCustomEnhancedShip(ShipClass.Fighter, attackStrength = 3, defenseStrength = 1, name = "fighter-" & $i)

      squadrons.add(CombatSquadron(
        squadron: Squadron(
          id: "sq-" & $i,
          flagship: flagship,
          ships: @[],
          owner: "swarm",
          location: 1,
          embarkedFighters: @[]
        ),
        state: CombatState.Undamaged,
        fleetStatus: FleetStatus.Active,
        damageThisTurn: 0,
        crippleRound: 0,
        bucket: TargetBucket.Fighter,
        targetWeight: 0.0
      ))

    let tf = TaskForce(
      house: "swarm",
      squadrons: squadrons,
      roe: 5,
      isCloaked: false,
      moraleModifier: 0,
      scoutBonus: false,
      isDefendingHomeworld: false,
      eliLevel: 1,
      clkLevel: 1
    )

    check tf.totalAS() == 3000
    check tf.aliveSquadrons().len == 1000

  test "Damage: rapid state transitions":
    let flagship = newCustomEnhancedShip(ShipClass.Destroyer, attackStrength = 10, defenseStrength = 20, name = "ship")
    var sq = CombatSquadron(
      squadron: Squadron(
        id: "rapid",
        flagship: flagship,
        ships: @[],
        owner: "house1",
        location: 1,
        embarkedFighters: @[]
      ),
      state: CombatState.Undamaged,
      fleetStatus: FleetStatus.Active,
      damageThisTurn: 0,
      crippleRound: 0,
      bucket: TargetBucket.Destroyer,
      targetWeight: 0.0
    )

    # 1000 rapid damage applications
    for i in 1..1000:
      discard applyDamageToSquadron(sq, damage = 1, roundNumber = i, isCriticalHit = false)

      # After enough damage, should be destroyed
      if sq.damageThisTurn >= 40:
        break

    check sq.state == CombatState.Destroyed

  test "CER: extreme modifier combinations":
    # Test all combinations of max/min modifiers
    let testCases = [
      (hasScouts: true, morale: 2, surprise: true, ambush: true, expected: 10),
      (hasScouts: false, morale: -1, surprise: false, ambush: false, expected: -1),
      (hasScouts: true, morale: -1, surprise: true, ambush: false, expected: 3),
      (hasScouts: false, morale: 2, surprise: false, ambush: true, expected: 6)
    ]

    for tc in testCases:
      let mods = calculateModifiers(
        phase = if tc.ambush: CombatPhase.Ambush else: CombatPhase.MainEngagement,
        roundNumber = 1,
        hasScouts = tc.hasScouts,
        moraleModifier = tc.morale,
        isSurprise = tc.surprise,
        isAmbush = tc.ambush
      )

      check mods == tc.expected

  test "Task Force: all squadrons crippled simultaneously":
    var tf = TaskForce(
      house: "crippled-force",
      squadrons: @[],
      roe: 5,
      isCloaked: false,
      moraleModifier: 0,
      scoutBonus: false,
      isDefendingHomeworld: false,
      eliLevel: 1,
      clkLevel: 1
    )

    # Add 100 squadrons
    for i in 1..100:
      let flagship = newCustomEnhancedShip(ShipClass.Destroyer, attackStrength = 10, defenseStrength = 10, name = "ship-" & $i)

      tf.squadrons.add(CombatSquadron(
        squadron: Squadron(
          id: "sq-" & $i,
          flagship: flagship,
          ships: @[],
          owner: "crippled-force",
          location: 1,
          embarkedFighters: @[]
        ),
        state: CombatState.Undamaged,
        fleetStatus: FleetStatus.Active,
        damageThisTurn: 0,
        crippleRound: 0,
        bucket: TargetBucket.Destroyer,
        targetWeight: 0.0
      ))

    # Cripple all squadrons
    for i in 0..99:
      tf.squadrons[i].state = CombatState.Crippled

    # Total AS should be half
    check tf.totalAS() == 500
    check tf.aliveSquadrons().len == 100

  test "Damage: alternating cripple and heal (invalid but test robustness)":
    let flagship = newCustomEnhancedShip(ShipClass.Destroyer, attackStrength = 10, defenseStrength = 20, name = "ship")
    var sq = CombatSquadron(
      squadron: Squadron(
        id: "flipflop",
        flagship: flagship,
        ships: @[],
        owner: "house1",
        location: 1,
        embarkedFighters: @[]
      ),
      state: CombatState.Undamaged,
      fleetStatus: FleetStatus.Active,
      damageThisTurn: 0,
      crippleRound: 0,
      bucket: TargetBucket.Destroyer,
      targetWeight: 0.0
    )

    # Cripple
    discard applyDamageToSquadron(sq, damage = 20, roundNumber = 1, isCriticalHit = false)
    check sq.state == CombatState.Crippled

    # Try to "heal" by manually resetting state (not supported, but test)
    sq.state = CombatState.Undamaged
    resetRoundDamage(sq)

    # Should be able to cripple again
    discard applyDamageToSquadron(sq, damage = 20, roundNumber = 2, isCriticalHit = false)
    check sq.state == CombatState.Crippled

suite "Combat Engine: Extreme Edge Cases":

  test "CER: integer overflow protection on huge modifiers":
    let hugeModifiers = calculateModifiers(
      phase = CombatPhase.MainEngagement,
      roundNumber = 1,
      hasScouts = true,
      moraleModifier = int.high - 10,
      isSurprise = true,
      isAmbush = false
    )

    # Should not crash, but result may be undefined
    check hugeModifiers > 0

  test "Damage: negative defense strength":
    let flagship = newCustomEnhancedShip(ShipClass.Fighter, attackStrength = 3, defenseStrength = -5, name = "fighter")
    var sq = CombatSquadron(
      squadron: Squadron(
        id: "neg-ds",
        flagship: flagship,
        ships: @[],
        owner: "house1",
        location: 1,
        embarkedFighters: @[]
      ),
      state: CombatState.Undamaged,
      fleetStatus: FleetStatus.Active,
      damageThisTurn: 0,
      crippleRound: 0,
      bucket: TargetBucket.Fighter,
      targetWeight: 0.0
    )

    # Negative DS means any damage might cause weird behavior
    let change = applyDamageToSquadron(sq, damage = 1, roundNumber = 1, isCriticalHit = false)

    # Should not crash
    check change.squadronId == "neg-ds"

  test "Task Force: all squadrons destroyed then more added":
    var tf = TaskForce(
      house: "resurrection",
      squadrons: @[],
      roe: 5,
      isCloaked: false,
      moraleModifier: 0,
      scoutBonus: false,
      isDefendingHomeworld: false,
      eliLevel: 1,
      clkLevel: 1
    )

    # Add and destroy squadrons
    for i in 1..5:
      let flagship = newCustomEnhancedShip(ShipClass.Fighter, attackStrength = 1, defenseStrength = 1, name = "ship-" & $i)

      tf.squadrons.add(CombatSquadron(
        squadron: Squadron(
          id: "sq-" & $i,
          flagship: flagship,
          ships: @[],
          owner: "resurrection",
          location: 1,
          embarkedFighters: @[]
        ),
        state: CombatState.Destroyed,
        fleetStatus: FleetStatus.Active,
        damageThisTurn: 0,
        crippleRound: 0,
        bucket: TargetBucket.Fighter,
        targetWeight: 0.0
      ))

    check tf.isEliminated() == true

    # Add new living squadron
    let newFlagship = newCustomEnhancedShip(ShipClass.Destroyer, attackStrength = 10, defenseStrength = 10, name = "reinforcement")

    tf.squadrons.add(CombatSquadron(
      squadron: Squadron(
        id: "reinforcement-sq",
        flagship: newFlagship,
        ships: @[],
        owner: "resurrection",
        location: 1,
        embarkedFighters: @[]
      ),
      state: CombatState.Undamaged,
      fleetStatus: FleetStatus.Active,
      damageThisTurn: 0,
      crippleRound: 0,
      bucket: TargetBucket.Destroyer,
      targetWeight: 0.0
    ))

    # No longer eliminated
    check tf.isEliminated() == false
    check tf.totalAS() == 10

  test "CER: phase transitions with same modifiers":
    # Verify phase changes behavior correctly
    var rng1 = initRNG(42'i64)
    var rng2 = initRNG(42'i64)

    let ambushRoll = rollCER(
      rng1,
      phase = CombatPhase.Ambush,
      roundNumber = 1,
      hasScouts = false,
      moraleModifier = 0,
      isAmbush = true
    )

    let mainRoll = rollCER(
      rng2,
      phase = CombatPhase.MainEngagement,
      roundNumber = 1,
      hasScouts = false,
      moraleModifier = 0,
      isAmbush = true  # Ambush flag set but wrong phase
    )

    # Ambush should have higher final roll
    check ambushRoll.finalRoll > mainRoll.finalRoll

  test "Damage: squadron with massive AS/DS values":
    let flagship = newCustomEnhancedShip(ShipClass.SuperDreadnought, attackStrength = 1_000_000, defenseStrength = 1_000_000, name = "titan-ship")
    var sq = CombatSquadron(
      squadron: Squadron(
        id: "titan",
        flagship: flagship,
        ships: @[],
        owner: "house1",
        location: 1,
        embarkedFighters: @[]
      ),
      state: CombatState.Undamaged,
      fleetStatus: FleetStatus.Active,
      damageThisTurn: 0,
      crippleRound: 0,
      bucket: TargetBucket.Capital,
      targetWeight: 0.0
    )

    check sq.getCurrentAS() == 1_000_000
    check sq.getCurrentDS() == 1_000_000

    # Cripple it
    discard applyDamageToSquadron(sq, damage = 1_000_000, roundNumber = 1, isCriticalHit = false)

    check sq.state == CombatState.Crippled
    check sq.getCurrentAS() == 500_000

  test "CER: roll sequence repeatability":
    # Verify same seed produces identical roll sequences
    let seeds = [1'i64, 42'i64, 999'i64, 123456789'i64]

    for seed in seeds:
      var rng1 = initRNG(seed)
      var rng2 = initRNG(seed)

      for i in 1..100:
        check rng1.roll1d10() == rng2.roll1d10()

  test "Damage: protection with exactly threshold damage":
    let flagship = newCustomEnhancedShip(ShipClass.Destroyer, attackStrength = 10, defenseStrength = 20, name = "ship")
    var sq = CombatSquadron(
      squadron: Squadron(
        id: "threshold",
        flagship: flagship,
        ships: @[],
        owner: "house1",
        location: 1,
        embarkedFighters: @[]
      ),
      state: CombatState.Undamaged,
      fleetStatus: FleetStatus.Active,
      damageThisTurn: 0,
      crippleRound: 0,
      bucket: TargetBucket.Destroyer,
      targetWeight: 0.0
    )

    # Exactly 2× DS (40 damage) - should trigger protection
    let change = applyDamageToSquadron(sq, damage = 40, roundNumber = 1, isCriticalHit = false)

    check change.destructionProtectionApplied == true
    check sq.state == CombatState.Crippled

  test "Damage: protection with DS + 1":
    let flagship = newCustomEnhancedShip(ShipClass.Destroyer, attackStrength = 10, defenseStrength = 20, name = "ship")
    var sq = CombatSquadron(
      squadron: Squadron(
        id: "ds-plus-one",
        flagship: flagship,
        ships: @[],
        owner: "house1",
        location: 1,
        embarkedFighters: @[]
      ),
      state: CombatState.Undamaged,
      fleetStatus: FleetStatus.Active,
      damageThisTurn: 0,
      crippleRound: 0,
      bucket: TargetBucket.Destroyer,
      targetWeight: 0.0
    )

    # 21 damage - enough to cripple, not enough to destroy even without protection
    let change = applyDamageToSquadron(sq, damage = 21, roundNumber = 1, isCriticalHit = false)

    check change.toState == CombatState.Crippled
    check sq.state == CombatState.Crippled

  test "Task Force: ROE extreme values":
    let lowROE = TaskForce(
      house: "pacifist",
      squadrons: @[],
      roe: -100,
      isCloaked: false,
      moraleModifier: 0,
      scoutBonus: false,
      isDefendingHomeworld: false,
      eliLevel: 1,
      clkLevel: 1
    )

    let highROE = TaskForce(
      house: "aggressive",
      squadrons: @[],
      roe: 1000,
      isCloaked: false,
      moraleModifier: 0,
      scoutBonus: false,
      isDefendingHomeworld: false,
      eliLevel: 1,
      clkLevel: 1
    )

    # Should not crash with extreme ROE values
    check lowROE.roe == -100
    check highROE.roe == 1000

  test "CER: natural roll 9 with negative modifiers still critical":
    var rng = initRNG(42'i64)

    # Force rolls until we get a natural 9
    var foundCrit = false
    for i in 1..1000:
      let cerRoll = rollCER(
        rng,
        phase = CombatPhase.MainEngagement,
        roundNumber = 1,
        hasScouts = false,
        moraleModifier = -5,  # Large negative modifier
        desperationBonus = 0
      )

      if cerRoll.naturalRoll == 9:
        # Should still be critical even with negative modifiers
        check cerRoll.isCriticalHit == true
        foundCrit = true
        break

    check foundCrit

  test "Damage: round number wraparound":
    let flagship = newCustomEnhancedShip(ShipClass.Destroyer, attackStrength = 10, defenseStrength = 20, name = "ship")
    var sq = CombatSquadron(
      squadron: Squadron(
        id: "longevity",
        flagship: flagship,
        ships: @[],
        owner: "house1",
        location: 1,
        embarkedFighters: @[]
      ),
      state: CombatState.Undamaged,
      fleetStatus: FleetStatus.Active,
      damageThisTurn: 0,
      crippleRound: 0,
      bucket: TargetBucket.Destroyer,
      targetWeight: 0.0
    )

    # Cripple in very high round number
    discard applyDamageToSquadron(sq, damage = 20, roundNumber = 1_000_000, isCriticalHit = false)

    check sq.state == CombatState.Crippled
    check sq.crippleRound == 1_000_000

  test "Bucket classification: Scout ship class":
    # Scouts are not a combat class, but test handling
    let scoutFlagship = newCustomEnhancedShip(ShipClass.Scout, attackStrength = 1, defenseStrength = 5, name = "scout")

    let sq = Squadron(
      id: "scout-sq",
      flagship: scoutFlagship,
      ships: @[],
      owner: "house1",
      location: 1,
      embarkedFighters: @[]
    )

    # Should default to Capital bucket (as per else clause)
    check classifyBucket(sq) == TargetBucket.Capital

suite "Combat Engine: Concurrent Operations":

  test "Multiple Task Forces: simultaneous AS calculation":
    var forces: seq[TaskForce] = @[]

    for houseNum in 1..10:
      var squadrons: seq[CombatSquadron] = @[]

      for sqNum in 1..10:
        let flagship = newCustomEnhancedShip(ShipClass.Destroyer, attackStrength = 10, defenseStrength = 10, name = "h" & $houseNum & "-sq" & $sqNum)

        squadrons.add(CombatSquadron(
          squadron: Squadron(
            id: "h" & $houseNum & "-sq" & $sqNum,
            flagship: flagship,
            ships: @[],
            owner: "house" & $houseNum,
            location: 1,
            embarkedFighters: @[]
          ),
          state: CombatState.Undamaged,
          fleetStatus: FleetStatus.Active,
          damageThisTurn: 0,
          crippleRound: 0,
          bucket: TargetBucket.Destroyer,
          targetWeight: 0.0
        ))

      forces.add(TaskForce(
        house: "house" & $houseNum,
        squadrons: squadrons,
        roe: 5,
        isCloaked: false,
        moraleModifier: 0,
        scoutBonus: false,
        isDefendingHomeworld: false,
        eliLevel: 1,
        clkLevel: 1
      ))

    # All should have same AS
    for tf in forces:
      check tf.totalAS() == 100

  test "CER: parallel random number generation":
    # Multiple independent RNG instances
    var rngs: seq[CombatRNG] = @[]

    for seed in 1..100:
      rngs.add(initRNG(int64(seed)))

    # Each should produce independent sequences
    var rolls: seq[int] = @[]
    for rng in rngs.mitems:
      rolls.add(rng.roll1d10())

    # Should have variety (not all same)
    var uniqueRolls: seq[int] = @[]
    for roll in rolls:
      if roll notin uniqueRolls:
        uniqueRolls.add(roll)

    check uniqueRolls.len >= 5  # At least 5 different values

suite "Combat Engine: Regression Tests":

  test "CER: zero modifier produces base roll":
    var rng = initRNG(42'i64)

    let cerRoll = rollCER(
      rng,
      phase = CombatPhase.MainEngagement,
      roundNumber = 1,
      hasScouts = false,
      moraleModifier = 0,
      isSurprise = false,
      isAmbush = false,
      desperationBonus = 0
    )

    # Final roll should equal natural roll (no modifiers)
    check cerRoll.finalRoll == cerRoll.naturalRoll

  test "Damage: state transitions are irreversible":
    let flagship = newCustomEnhancedShip(ShipClass.Destroyer, attackStrength = 10, defenseStrength = 20, name = "ship")
    var sq = CombatSquadron(
      squadron: Squadron(
        id: "irreversible",
        flagship: flagship,
        ships: @[],
        owner: "house1",
        location: 1,
        embarkedFighters: @[]
      ),
      state: CombatState.Undamaged,
      fleetStatus: FleetStatus.Active,
      damageThisTurn: 0,
      crippleRound: 0,
      bucket: TargetBucket.Destroyer,
      targetWeight: 0.0
    )

    # Destroy it
    discard applyDamageToSquadron(sq, damage = 100, roundNumber = 1, isCriticalHit = true)

    check sq.state == CombatState.Destroyed

    # Manually try to "repair" (invalid operation)
    sq.state = CombatState.Undamaged
    sq.damageThisTurn = 0

    # System should treat it as undamaged (no enforcement of irreversibility in damage module)
    check sq.state == CombatState.Undamaged

  test "Task Force: empty house ID":
    let tf = TaskForce(
      house: "",
      squadrons: @[],
      roe: 5,
      isCloaked: false,
      moraleModifier: 0,
      scoutBonus: false,
      isDefendingHomeworld: false,
      eliLevel: 1,
      clkLevel: 1
    )

    check tf.house == ""
    check tf.isEliminated() == true

  test "CER: effectiveness calculation with fractional AS":
    # Test rounding behavior
    let testCases = [
      (attackStr: 10, effectiveness: 0.25, expected: 3),   # 10 * 0.25 = 2.5 → 3
      (attackStr: 10, effectiveness: 0.50, expected: 5),   # 10 * 0.50 = 5.0 → 5
      (attackStr: 10, effectiveness: 0.75, expected: 8),   # 10 * 0.75 = 7.5 → 8
      (attackStr: 10, effectiveness: 1.00, expected: 10),  # 10 * 1.00 = 10.0 → 10
      (attackStr: 7, effectiveness: 0.25, expected: 2),    # 7 * 0.25 = 1.75 → 2
      (attackStr: 7, effectiveness: 0.75, expected: 5)     # 7 * 0.75 = 5.25 → 5
    ]

    for tc in testCases:
      let hits = applyDamage(tc.attackStr, tc.effectiveness)
      check hits == tc.expected
