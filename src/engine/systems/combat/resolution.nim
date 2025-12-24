## Combat Phase Resolution Engine
##
## Implements the three-phase combat resolution system
## for EC4X (Section 7.3.1)
##
## Phase 1: Undetected Raiders (Ambush)
## Phase 2: Fighter Squadrons (Intercept)
## Phase 3: Capital Ships (Main Engagement)

import std/[tables, algorithm, options]
import ../../types/combat as combat_types
import cer, targeting, damage

export combat_types

## Phase Resolution

proc resolvePhase1_Ambush*(
    taskForces: var seq[TaskForce],
    squadronMap: Table[SquadronId, tuple[tfIdx: int, sqIdx: int]],
    roundNumber: int,
    diplomaticRelations: Table[tuple[a, b: HouseId], DiplomaticState],
    systemOwner: Option[HouseId],
    rng: var CombatRNG,
    desperationBonus: int = 0,
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
      damage: int,
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
      roundNumber,
      attack.cerRoll.isCriticalHit,
    )

    result.attacks.add(
      AttackResult(
        attackerId:
          taskForces[attack.attackerTfIdx].squadrons[attack.attackerSqIdx].squadron.id,
        targetId: attack.targetId,
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
    roundNumber: int,
    diplomaticRelations: Table[tuple[a, b: HouseId], DiplomaticState],
    systemOwner: Option[HouseId],
    rng: var CombatRNG,
    desperationBonus: int = 0, # Not used by fighters (no CER), but kept for consistency
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
    tuple[attackerTfIdx: int, attackerSqIdx: int, targetId: SquadronId, damage: int]
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
      roundNumber,
      isCriticalHit = false, # Fighters don't crit
    )

    result.attacks.add(
      AttackResult(
        attackerId:
          taskForces[attack.attackerTfIdx].squadrons[attack.attackerSqIdx].squadron.id,
        targetId: attack.targetId,
        cerRoll: CERRoll(effectiveness: 1.0, isCriticalHit: false), # Placeholder
        damageDealt: attack.damage,
        targetStateBefore: targetStateBefore,
        targetStateAfter: change.toState,
      )
    )

    if change.fromState != change.toState:
      result.stateChanges.add(change)

proc resolveCRTier(
  tier: seq[tuple[tfIdx: int, sqIdx: int, cr: int]],
  taskForces: var seq[TaskForce],
  squadronMap: Table[SquadronId, tuple[tfIdx: int, sqIdx: int]],
  roundNumber: int,
  diplomaticRelations: Table[tuple[a, b: HouseId], DiplomaticState],
  systemOwner: Option[HouseId],
  rng: var CombatRNG,
  desperationBonus: int = 0,
  allowStarbaseTargeting: bool = true,
): RoundResult

proc resolvePhase3_CapitalShips*(
    taskForces: var seq[TaskForce],
    squadronMap: Table[SquadronId, tuple[tfIdx: int, sqIdx: int]],
    roundNumber: int,
    diplomaticRelations: Table[tuple[a, b: HouseId], DiplomaticState],
    systemOwner: Option[HouseId],
    rng: var CombatRNG,
    desperationBonus: int = 0,
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

  # Collect all non-fighter, alive squadrons with their CR
  type CapitalEntry = tuple[tfIdx: int, sqIdx: int, cr: int]
  var capitals: seq[CapitalEntry] = @[]

  for tfIdx, tf in taskForces:
    for sqIdx, sq in tf.squadrons:
      # Skip starbases if they're not allowed to fight (space combat screening)
      if not allowStarbaseCombat and sq.bucket == TargetBucket.Starbase:
        continue

      if sq.isAlive() and sq.bucket != TargetBucket.Fighter:
        let cr = sq.squadron.flagship.stats.commandRating
        capitals.add((tfIdx, sqIdx, cr))

  if capitals.len == 0:
    return result

  # Sort by CR descending (highest CR attacks first)
  capitals.sort(
    proc(a, b: CapitalEntry): int =
      cmp(b.cr, a.cr)
  )

  # Group by CR tier and resolve each tier simultaneously
  var currentCR = -1
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
    tier: seq[tuple[tfIdx: int, sqIdx: int, cr: int]],
    taskForces: var seq[TaskForce],
    squadronMap: Table[SquadronId, tuple[tfIdx: int, sqIdx: int]],
    roundNumber: int,
    diplomaticRelations: Table[tuple[a, b: HouseId], DiplomaticState],
    systemOwner: Option[HouseId],
    rng: var CombatRNG,
    desperationBonus: int = 0,
    allowStarbaseTargeting: bool = true,
): RoundResult =
  ## Resolve all attacks for squadrons with same CR
  ## All attacks in tier are simultaneous
  ## allowStarbaseTargeting: If false, starbases are screened and cannot be targeted

  result = RoundResult(
    phase: CombatPhase.MainEngagement,
    roundNumber: roundNumber,
    attacks: @[],
    stateChanges: @[],
  )

  # All squadrons in tier select targets and roll CER
  var attacks: seq[
    tuple[
      attackerTfIdx: int,
      attackerSqIdx: int,
      targetId: SquadronId,
      damage: int,
      cerRoll: CERRoll,
    ]
  ] = @[]

  for entry in tier:
    let tfIdx = entry.tfIdx
    let sqIdx = entry.sqIdx
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

    attacks.add((tfIdx, sqIdx, targetId.get(), damage, cerRoll))

  # Apply all damage simultaneously using O(1) HashMap lookup
  for attack in attacks:
    # O(1) lookup instead of O(n²) nested loop (Phase 8 optimization)
    let (tfIdx, sqIdx) = squadronMap[attack.targetId]
    let targetStateBefore = taskForces[tfIdx].squadrons[sqIdx].state

    let change = applyDamageToSquadron(
      taskForces[tfIdx].squadrons[sqIdx],
      attack.damage,
      roundNumber,
      attack.cerRoll.isCriticalHit,
    )

    result.attacks.add(
      AttackResult(
        attackerId:
          taskForces[attack.attackerTfIdx].squadrons[attack.attackerSqIdx].squadron.id,
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
    roundNumber: int,
    diplomaticRelations: Table[tuple[a, b: HouseId], DiplomaticState],
    systemOwner: Option[HouseId],
    rng: var CombatRNG,
    desperationBonus: int = 0, # Bonus CER modifier for desperation rounds
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
      squadronMap[taskForces[tfIdx].squadrons[sqIdx].squadron.id] = (tfIdx, sqIdx)

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
