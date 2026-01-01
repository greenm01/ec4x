## Combat Phase Resolution Engine
##
## Implements the three-phase combat resolution system
## for EC4X (Section 7.3.1)
##
## Phase 1: Undetected Raiders (Ambush)
## Phase 2: Fighter Squadrons (Intercept)
## Phase 3: Capital Ships (Main Engagement)

import std/[tables, algorithm, options]
import ../../types/[core, combat as combat_types, diplomacy]
import ../../globals
import cer, targeting, damage

export combat_types

## CombatSquadron Helpers (avoid circular dependency with engine.nim)

proc isAlive(sq: CombatSquadron): bool {.inline.} =
  sq.state != CombatState.Destroyed

proc getCurrentAS(sq: CombatSquadron): int32 {.inline.} =
  if sq.state == CombatState.Crippled:
    max(1'i32, sq.attackStrength div 2)
  else:
    sq.attackStrength

proc resetRoundDamage(sq: var CombatSquadron) {.inline.} =
  sq.damageThisTurn = 0

## Phase Resolution

proc resolvePhase1_Ambush*(
    taskForces: var seq[TaskForce],
    squadronMap: Table[SquadronId, tuple[tfIdx: int, sqIdx: int]],
    roundNumber: int32,
    diplomaticRelations: Table[tuple[a, b: HouseId], DiplomaticState],
    systemOwner: Option[HouseId],
    rng: var CombatRNG,
    desperationBonus: int32 = 0,
    allowAmbush: bool = true,
    allowStarbaseTargeting: bool = true,
): RoundResult =
  ## Phase 1: Undetected Raiders attack with ambush bonus
  ## Section 7.3.1.1
  ##
  ## - Only undetected cloaked Raiders attack
  ## - +4 CER modifier (+ desperation bonus if applicable) - only if allowAmbush=true
  ## - Simultaneous attacks within phase
  ## - allowAmbush: If false, Raiders get initiative but NO +4 ambush bonus (orbital defense)
  ## - allowStarbaseTargeting: If false, starbases are screened and cannot be targeted

  result = RoundResult(
    phase: CombatPhase.Ambush, roundNumber: roundNumber, attacks: @[], stateChanges: @[]
  )

  # Find all undetected cloaked squadrons
  var ambushers: seq[tuple[tfIdx: int, sqIdx: int]] = @[]
  for tfIdx, tf in taskForces:
    if not tf.isCloaked:
      continue

    for sqIdx, sq in tf.squadrons:
      if sq.isAlive() and sq.bucket == TargetBucket.Raider:
        ambushers.add((tfIdx, sqIdx))

  if ambushers.len == 0:
    return result

  # All ambushers select targets simultaneously
  var attacks: seq[
    tuple[
      attackerTfIdx: int,
      attackerSqIdx: int,
      targetId: SquadronId,
      damage: int32,
      cerRoll: CERRoll,
    ]
  ] = @[]

  for amb in ambushers:
    let tfIdx = amb.tfIdx
    let sqIdx = amb.sqIdx
    let attacker = taskForces[tfIdx].squadrons[sqIdx]

    # Select target
    let targetId = selectTargetForAttack(
      attacker,
      taskForces[tfIdx],
      taskForces,
      diplomaticRelations,
      systemOwner,
      rng,
      allowStarbaseTargeting,
    )

    if targetId.isNone():
      continue

    # Roll for CER with ambush bonus (and desperation if applicable)
    # Ambush bonus only applies if allowAmbush=true (space combat, not orbital)
    let cerRoll = rollCER(
      rng,
      CombatPhase.Ambush,
      roundNumber,
      moraleModifier = taskForces[tfIdx].moraleModifier,
      isSurprise = (roundNumber == 1),
      isAmbush = allowAmbush, # +4 bonus only in space combat
      desperationBonus = desperationBonus,
    )

    # Calculate damage
    let damage = calculateHits(attacker.getCurrentAS(), cerRoll)

    attacks.add((tfIdx, sqIdx, targetId.get(), damage, cerRoll))

  # Apply all damage simultaneously using O(1) HashMap lookup
  for attack in attacks:
    # O(1) lookup instead of O(n²) nested loop (Phase 8 optimization)
    let (tfIdx, sqIdx) = squadronMap[attack.targetId]
    let targetStateBefore = taskForces[tfIdx].squadrons[sqIdx].state

    let change = applyDamageToSquadron(
      taskForces[tfIdx].squadrons[sqIdx],
      attack.damage,
      taskForces[tfIdx].squadrons[sqIdx].defenseStrength,
      roundNumber,
      attack.cerRoll.isCriticalHit,
    )

    result.attacks.add(
      AttackResult(
        attackerId: CombatTargetId(
          kind: CombatTargetKind.Squadron,
          squadronId: taskForces[attack.attackerTfIdx].squadrons[attack.attackerSqIdx]
            .squadronId,
        ),
        targetId: CombatTargetId(
          kind: CombatTargetKind.Squadron, squadronId: attack.targetId
        ),
        cerRoll: attack.cerRoll,
        damageDealt: attack.damage,
        targetStateBefore: targetStateBefore,
        targetStateAfter: change.toState,
      )
    )

    if change.fromState != change.toState:
      result.stateChanges.add(change)

proc resolvePhase2_Fighters*(
    taskForces: var seq[TaskForce],
    squadronMap: Table[SquadronId, tuple[tfIdx: int, sqIdx: int]],
    roundNumber: int32,
    diplomaticRelations: Table[tuple[a, b: HouseId], DiplomaticState],
    systemOwner: Option[HouseId],
    rng: var CombatRNG,
    desperationBonus: int32 = 0, # Not used by fighters (no CER), but kept for consistency
    allowStarbaseTargeting: bool = true,
): RoundResult =
  ## Phase 2: All fighter squadrons attack simultaneously
  ## Section 7.3.1.2
  ##
  ## - Fighters do NOT use CER (full AS as damage)
  ## - All fighters attack at once
  ## - Fighters have binary state (undamaged → destroyed, no crippled)
  ## - Note: desperationBonus does not apply to fighters (they always use full AS)
  ## - allowStarbaseTargeting: If false, starbases are screened and cannot be targeted

  result = RoundResult(
    phase: CombatPhase.Intercept,
    roundNumber: roundNumber,
    attacks: @[],
    stateChanges: @[],
  )

  # Find all fighter squadrons
  var fighters: seq[tuple[tfIdx: int, sqIdx: int]] = @[]
  for tfIdx, tf in taskForces:
    for sqIdx, sq in tf.squadrons:
      if sq.isAlive() and sq.bucket == TargetBucket.Fighter:
        fighters.add((tfIdx, sqIdx))

  if fighters.len == 0:
    return result

  # All fighters select targets and attack simultaneously
  var attacks: seq[
    tuple[attackerTfIdx: int, attackerSqIdx: int, targetId: SquadronId, damage: int32]
  ] = @[]

  for ftr in fighters:
    let tfIdx = ftr.tfIdx
    let sqIdx = ftr.sqIdx
    let attacker = taskForces[tfIdx].squadrons[sqIdx]

    # Select target (fighters prefer fighters per Section 7.3.2.3)
    let targetId = selectTargetForAttack(
      attacker,
      taskForces[tfIdx],
      taskForces,
      diplomaticRelations,
      systemOwner,
      rng,
      allowStarbaseTargeting,
    )

    if targetId.isNone():
      continue

    # Fighters deal full AS as damage (no CER roll)
    let damage = attacker.getCurrentAS()

    attacks.add((tfIdx, sqIdx, targetId.get(), damage))

  # Apply all damage simultaneously using O(1) HashMap lookup
  for attack in attacks:
    # O(1) lookup instead of O(n²) nested loop (Phase 8 optimization)
    let (tfIdx, sqIdx) = squadronMap[attack.targetId]
    let targetStateBefore = taskForces[tfIdx].squadrons[sqIdx].state

    let change = applyDamageToSquadron(
      taskForces[tfIdx].squadrons[sqIdx],
      attack.damage,
      taskForces[tfIdx].squadrons[sqIdx].defenseStrength,
      roundNumber,
      isCriticalHit = false, # Fighters don't crit
    )

    result.attacks.add(
      AttackResult(
        attackerId: CombatTargetId(
          kind: CombatTargetKind.Squadron,
          squadronId: taskForces[attack.attackerTfIdx].squadrons[attack.attackerSqIdx]
            .squadronId,
        ),
        targetId: CombatTargetId(
          kind: CombatTargetKind.Squadron, squadronId: attack.targetId
        ),
        cerRoll: CERRoll(effectiveness: 1.0, isCriticalHit: false), # Placeholder
        damageDealt: attack.damage,
        targetStateBefore: targetStateBefore,
        targetStateAfter: change.toState,
      )
    )

    if change.fromState != change.toState:
      result.stateChanges.add(change)

proc resolveCRTier(
    tier: seq[tuple[tfIdx: int, sqIdx: int, facIdx: int, cr: int32, isFacility: bool]],
    taskForces: var seq[TaskForce],
    squadronMap: Table[SquadronId, tuple[tfIdx: int, sqIdx: int]],
    roundNumber: int32,
    diplomaticRelations: Table[tuple[a, b: HouseId], DiplomaticState],
    systemOwner: Option[HouseId],
    rng: var CombatRNG,
    desperationBonus: int32 = 0,
    allowStarbaseTargeting: bool = true,
): RoundResult

proc resolvePhase3_CapitalShips*(
    taskForces: var seq[TaskForce],
    squadronMap: Table[SquadronId, tuple[tfIdx: int, sqIdx: int]],
    roundNumber: int32,
    diplomaticRelations: Table[tuple[a, b: HouseId], DiplomaticState],
    systemOwner: Option[HouseId],
    rng: var CombatRNG,
    desperationBonus: int32 = 0,
    allowStarbaseCombat: bool = true,
): RoundResult =
  ## Phase 3: Capital ships attack by CR order
  ## Section 7.3.1.3
  ##
  ## - Attack order by flagship CR (highest first)
  ## - Simultaneous attacks within same CR tier
  ## - CER rolls per squadron (with desperation bonus if applicable)
  ## - If allowStarbaseCombat=false, starbases are screened and cannot fight

  result = RoundResult(
    phase: CombatPhase.MainEngagement,
    roundNumber: roundNumber,
    attacks: @[],
    stateChanges: @[],
  )

  # Collect all non-fighter, alive squadrons and facilities with their CR
  type CapitalEntry = tuple[
    tfIdx: int, sqIdx: int, facIdx: int, cr: int32, isFacility: bool
  ]
  var capitals: seq[CapitalEntry] = @[]

  # Add squadrons
  for tfIdx, tf in taskForces:
    for sqIdx, sq in tf.squadrons:
      # Skip starbases if they're not allowed to fight (space combat screening)
      if not allowStarbaseCombat and sq.bucket == TargetBucket.Starbase:
        continue

      if sq.isAlive() and sq.bucket != TargetBucket.Fighter:
        let cr = sq.commandRating
        capitals.add((tfIdx, sqIdx, -1, cr, false))

  # Add facilities (starbases) if allowed to fight
  if allowStarbaseCombat:
    for tfIdx, tf in taskForces:
      for facIdx, fac in tf.facilities:
        if fac.state != CombatState.Destroyed:
          # Starbases use CR 0 (attack last, after all squadrons)
          capitals.add((tfIdx, -1, facIdx, 0'i32, true))

  if capitals.len == 0:
    return result

  # Sort by CR descending (highest CR attacks first)
  capitals.sort(
    proc(a, b: CapitalEntry): int =
      cmp(b.cr, a.cr)
  )

  # Group by CR tier and resolve each tier simultaneously
  var currentCR: int32 = -1
  var crTier: seq[CapitalEntry] = @[]

  for cap in capitals:
    if cap.cr != currentCR:
      # New CR tier - resolve previous tier first
      if crTier.len > 0:
        let tierResult = resolveCRTier(
          crTier, taskForces, squadronMap, roundNumber, diplomaticRelations,
          systemOwner, rng, desperationBonus, allowStarbaseCombat,
        )
        result.attacks.add(tierResult.attacks)
        result.stateChanges.add(tierResult.stateChanges)

      # Start new tier
      currentCR = cap.cr
      crTier = @[cap]
    else:
      crTier.add(cap)

  # Resolve final tier
  if crTier.len > 0:
    let tierResult = resolveCRTier(
      crTier, taskForces, squadronMap, roundNumber, diplomaticRelations, systemOwner,
      rng, desperationBonus, allowStarbaseCombat,
    )
    result.attacks.add(tierResult.attacks)
    result.stateChanges.add(tierResult.stateChanges)

proc resolveCRTier(
    tier: seq[tuple[tfIdx: int, sqIdx: int, facIdx: int, cr: int32, isFacility: bool]],
    taskForces: var seq[TaskForce],
    squadronMap: Table[SquadronId, tuple[tfIdx: int, sqIdx: int]],
    roundNumber: int32,
    diplomaticRelations: Table[tuple[a, b: HouseId], DiplomaticState],
    systemOwner: Option[HouseId],
    rng: var CombatRNG,
    desperationBonus: int32 = 0,
    allowStarbaseTargeting: bool = true,
): RoundResult =
  ## Resolve all attacks for squadrons and facilities with same CR
  ## All attacks in tier are simultaneous
  ## allowStarbaseTargeting: If false, starbases are screened and cannot be targeted

  result = RoundResult(
    phase: CombatPhase.MainEngagement,
    roundNumber: roundNumber,
    attacks: @[],
    stateChanges: @[],
  )

  # All squadrons and facilities in tier select targets and roll CER
  var attacks: seq[
    tuple[
      attackerTfIdx: int,
      attackerSqIdx: int,
      attackerFacIdx: int,
      isFacilityAttack: bool,
      targetId: CombatTargetId,
      damage: int32,
      cerRoll: CERRoll,
    ]
  ] = @[]

  for entry in tier:
    let tfIdx = entry.tfIdx

    if entry.isFacility:
      # Facility attack (starbase)
      let facIdx = entry.facIdx
      let facility = taskForces[tfIdx].facilities[facIdx]

      # Facilities target squadrons only (simplified targeting)
      # TODO: Use proper targeting system when needed
      var targetOpt: Option[CombatTargetId] = none(CombatTargetId)

      # Find first hostile squadron
      for otherTfIdx, otherTf in taskForces:
        if otherTf.houseId == taskForces[tfIdx].houseId:
          continue
        for sq in otherTf.squadrons:
          if sq.state != CombatState.Destroyed:
            targetOpt = some(
              CombatTargetId(kind: CombatTargetKind.Squadron, squadronId: sq.squadronId)
            )
            break
        if targetOpt.isSome:
          break

      if targetOpt.isNone:
        continue

      # Apply starbase die modifier (+2 from config) if this is a starbase
      let dieModifier: int32 =
        if facility.bucket == TargetBucket.Starbase:
          gameConfig.combat.starbase.starbaseDieModifier
        else:
          0'i32

      # Roll CER with starbase bonus
      var cerRoll = rollCER(
        rng,
        CombatPhase.MainEngagement,
        roundNumber,
        moraleModifier = taskForces[tfIdx].moraleModifier + dieModifier,
        isSurprise = (roundNumber == 1),
        desperationBonus = desperationBonus,
      )

      # Starbase critical reroll (once per round)
      if cerRoll.isCriticalHit and facility.bucket == TargetBucket.Starbase and
          gameConfig.combat.starbase.starbaseCriticalReroll:
        let reroll = rollCER(
          rng,
          CombatPhase.MainEngagement,
          roundNumber,
          moraleModifier = taskForces[tfIdx].moraleModifier + dieModifier,
          isSurprise = (roundNumber == 1),
          desperationBonus = desperationBonus,
        )
        if not reroll.isCriticalHit:
          cerRoll = reroll

      # Calculate damage using facility attack strength
      let attackStrength =
        if facility.state == CombatState.Crippled:
          max(1'i32, facility.attackStrength div 2)
        else:
          facility.attackStrength

      let damage = calculateHits(attackStrength, cerRoll)
      attacks.add((tfIdx, -1, facIdx, true, targetOpt.get(), damage, cerRoll))

    else:
      # Squadron attack (existing logic)
      let sqIdx = entry.sqIdx
      let attacker = taskForces[tfIdx].squadrons[sqIdx]

      # Select target
      let targetIdOpt = selectTargetForAttack(
        attacker,
        taskForces[tfIdx],
        taskForces,
        diplomaticRelations,
        systemOwner,
        rng,
        allowStarbaseTargeting,
      )

      if targetIdOpt.isNone():
        continue

      # Roll CER (with desperation bonus if applicable)
      let cerRoll = rollCER(
        rng,
        CombatPhase.MainEngagement,
        roundNumber,
        moraleModifier = taskForces[tfIdx].moraleModifier,
        isSurprise = (roundNumber == 1),
        desperationBonus = desperationBonus,
      )

      # Calculate damage
      let damage = calculateHits(attacker.getCurrentAS(), cerRoll)

      let targetId = CombatTargetId(
        kind: CombatTargetKind.Squadron, squadronId: targetIdOpt.get()
      )
      attacks.add((tfIdx, sqIdx, -1, false, targetId, damage, cerRoll))

  # Apply all damage simultaneously
  for attack in attacks:
    let targetStateBefore =
      case attack.targetId.kind
      of CombatTargetKind.Squadron:
        let (tfIdx, sqIdx) = squadronMap[attack.targetId.squadronId]
        taskForces[tfIdx].squadrons[sqIdx].state
      of CombatTargetKind.Facility:
        # Facilities can't be targeted yet, but keep for completeness
        CombatState.Undamaged

    # Apply damage based on target type
    let change =
      case attack.targetId.kind
      of CombatTargetKind.Squadron:
        let (tfIdx, sqIdx) = squadronMap[attack.targetId.squadronId]
        applyDamageToSquadron(
          taskForces[tfIdx].squadrons[sqIdx],
          attack.damage,
          taskForces[tfIdx].squadrons[sqIdx].defenseStrength,
          roundNumber,
          attack.cerRoll.isCriticalHit,
        )
      of CombatTargetKind.Facility:
        # Facility targeting not yet implemented
        StateChange(
          targetId: attack.targetId,
          fromState: CombatState.Undamaged,
          toState: CombatState.Undamaged,
          destructionProtectionApplied: false,
        )

    # Create attacker ID based on whether it's a squadron or facility
    let attackerId =
      if attack.isFacilityAttack:
        CombatTargetId(
          kind: CombatTargetKind.Facility,
          facilityId: taskForces[attack.attackerTfIdx].facilities[attack.attackerFacIdx]
            .facilityId,
        )
      else:
        CombatTargetId(
          kind: CombatTargetKind.Squadron,
          squadronId: taskForces[attack.attackerTfIdx].squadrons[attack.attackerSqIdx]
            .squadronId,
        )

    result.attacks.add(
      AttackResult(
        attackerId: attackerId,
        targetId: attack.targetId,
        cerRoll: attack.cerRoll,
        damageDealt: attack.damage,
        targetStateBefore: targetStateBefore,
        targetStateAfter: change.toState,
      )
    )

    if change.fromState != change.toState:
      result.stateChanges.add(change)

## Round Resolution

proc resolveRound*(
    taskForces: var seq[TaskForce],
    roundNumber: int32,
    diplomaticRelations: Table[tuple[a, b: HouseId], DiplomaticState],
    systemOwner: Option[HouseId],
    rng: var CombatRNG,
    desperationBonus: int32 = 0, # Bonus CER modifier for desperation rounds
    allowAmbush: bool = true, # If false, Raiders get initiative but NO +4 ambush bonus
    allowStarbaseCombat: bool = true, # If false, starbases detect but don't fight
): seq[RoundResult] =
  ## Resolve complete combat round (all 3 phases)
  ## Returns results from each phase
  ##
  ## desperationBonus: Additional CER modifier applied when combat stalls
  ## (both sides gain this bonus for one final attack attempt)
  ## allowAmbush: If false, undetected Raiders attack in Phase 1 but without +4 CER bonus (orbital combat)
  ## allowStarbaseCombat: If false, starbases participate in detection but are screened from combat (space combat)

  result = @[]

  # Build squadron lookup table once per round for O(1) target lookups
  # This eliminates O(n²) bottleneck in damage application (Phase 8 optimization)
  var squadronMap = initTable[SquadronId, tuple[tfIdx: int, sqIdx: int]]()
  for tfIdx in 0 ..< taskForces.len:
    for sqIdx in 0 ..< taskForces[tfIdx].squadrons.len:
      squadronMap[taskForces[tfIdx].squadrons[sqIdx].squadronId] = (tfIdx, sqIdx)

  # Phase 1: Undetected Raiders (Ambush)
  let phase1 = resolvePhase1_Ambush(
    taskForces, squadronMap, roundNumber, diplomaticRelations, systemOwner, rng,
    desperationBonus, allowAmbush, allowStarbaseCombat,
  )
  if phase1.attacks.len > 0:
    result.add(phase1)

  # Phase 2: Fighter Squadrons (Intercept)
  let phase2 = resolvePhase2_Fighters(
    taskForces, squadronMap, roundNumber, diplomaticRelations, systemOwner, rng,
    desperationBonus, allowStarbaseCombat,
  )
  if phase2.attacks.len > 0:
    result.add(phase2)

  # Phase 3: Capital Ships (Main Engagement)
  let phase3 = resolvePhase3_CapitalShips(
    taskForces, squadronMap, roundNumber, diplomaticRelations, systemOwner, rng,
    desperationBonus, allowStarbaseCombat,
  )
  if phase3.attacks.len > 0:
    result.add(phase3)

  # Reset round damage counters for next round
  for tf in taskForces.mitems:
    for sq in tf.squadrons.mitems:
      resetRoundDamage(sq)
