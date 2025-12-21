## Target Priority and Selection System
##
## Implements diplomatic filtering, bucket classification,
## and weighted random target selection for EC4X combat
## (Section 7.3.2)

import std/[options, tables]
import ../../../types/combat as types
import ./cer

export TargetBucket, DiplomaticState

## Diplomatic Filtering (Section 7.3.2.1)

type
  FleetOrder* {.pure.} = enum
    Hold = 0,
    Move = 1,
    SeekHome = 2,
    Patrol = 3,
    GuardStarbase = 4,
    GuardBlockade = 5,
    Bombard = 6,
    Invade = 7,
    Blitz = 8,
    # ... others not relevant to targeting

proc isHostile*(
  attacker: HouseId,
  target: HouseId,
  diplomaticRelations: Table[tuple[a, b: HouseId], DiplomaticState],
  targetOrders: FleetOrder,
  attackerControlsSystem: bool
): bool =
  ## Determine if target Task Force is hostile per Section 7.3.2.1
  ##
  ## A house is hostile if:
  ## 1. Enemy diplomatic status
  ## 2. Target has threatening orders (05-08, 12) in attacker's controlled system
  ## 3. Target is patrolling in attacker's territory without NAP
  ## 4. Target engaged attacker in previous rounds

  # Check Enemy status
  let relation = diplomaticRelations.getOrDefault((attacker, target), DiplomaticState.Neutral)
  if relation == DiplomaticState.Enemy:
    return true

  # Check threatening orders in controlled territory
  if attackerControlsSystem:
    if targetOrders in [
      FleetOrder.GuardBlockade,
      FleetOrder.Bombard,
      FleetOrder.Invade,
      FleetOrder.Blitz
    ]:
      return true

  # Patrol in controlled territory by hostile/enemy forces
  if attackerControlsSystem and targetOrders == FleetOrder.Patrol:
    if relation in {DiplomaticState.Hostile, DiplomaticState.Enemy}:
      return true

  # Default: not hostile
  return false

## Target Candidate Pool Building

proc filterHostileSquadrons*(
  attacker: TaskForce,
  allTaskForces: seq[TaskForce],
  diplomaticRelations: Table[tuple[a, b: HouseId], DiplomaticState],
  systemOwner: Option[HouseId],
  allowStarbaseTargeting: bool = true
): seq[CombatSquadron] =
  ## Get all squadrons from hostile Task Forces
  ## Filters out destroyed squadrons and friendly forces
  ## If allowStarbaseTargeting=false, starbases are screened and cannot be targeted
  result = @[]

  for tf in allTaskForces:
    # Skip own Task Force
    if tf.house == attacker.house:
      continue

    # Check if hostile (simplified - would need fleet orders in real impl)
    let attackerControlsSystem = systemOwner.isSome and systemOwner.get() == attacker.house
    let isHostileHouse = isHostile(
      attacker.house,
      tf.house,
      diplomaticRelations,
      FleetOrder.Patrol,  # Placeholder - real impl would track per fleet
      attackerControlsSystem
    )

    if isHostileHouse:
      for sq in tf.squadrons:
        # Note: Starbases moved to facility system (not in squadrons anymore)
        # Starbase screening handled separately via colony facilities and TargetBucket.Starbase

        if sq.canBeTargeted():
          result.add(sq)

## Bucket-Based Target Selection (Section 7.3.2.4)

proc getCandidatesByBucket*(
  hostileSquadrons: seq[CombatSquadron],
  bucket: TargetBucket
): seq[CombatSquadron] =
  ## Get all squadrons in a specific bucket
  result = @[]
  for sq in hostileSquadrons:
    if sq.bucket == bucket:
      result.add(sq)

proc buildCandidatePool*(
  hostileSquadrons: seq[CombatSquadron],
  attackerBucket: TargetBucket
): seq[CombatSquadron] =
  ## Build target candidate pool using bucket priority
  ## Section 7.3.2.4: Walk buckets in order, return first non-empty

  # Special rule: Fighters target fighters first (Section 7.3.2.3)
  if attackerBucket == TargetBucket.Fighter:
    let enemyFighters = getCandidatesByBucket(hostileSquadrons, TargetBucket.Fighter)
    if enemyFighters.len > 0:
      return enemyFighters
    # If no enemy fighters, fall through to standard targeting

  # Standard bucket order: Raider → Capital → Destroyer → Fighter → Starbase
  const bucketOrder = [
    TargetBucket.Raider,
    TargetBucket.Capital,
    TargetBucket.Destroyer,
    TargetBucket.Fighter,
    TargetBucket.Starbase
  ]

  for bucket in bucketOrder:
    let candidates = getCandidatesByBucket(hostileSquadrons, bucket)
    if candidates.len > 0:
      return candidates

  # No valid targets
  return @[]

## Weighted Random Selection (Section 7.3.2.5)

proc selectTarget*(
  candidates: seq[CombatSquadron],
  rng: var CombatRNG
): Option[SquadronId] =
  ## Select target using weighted random selection
  ## Weights = Base_Weight × Crippled_Modifier
  ## Returns selected squadron ID, or none if no candidates

  if candidates.len == 0:
    return none(SquadronId)

  if candidates.len == 1:
    return some(candidates[0].squadron.id)

  # Calculate total weight
  var totalWeight = 0.0
  for sq in candidates:
    totalWeight += sq.targetWeight

  # Generate random value in [0, totalWeight)
  let randomValue = float(rng.next() mod 1000000) / 1000000.0 * totalWeight

  # Select target based on weighted probability
  var cumulative = 0.0
  for sq in candidates:
    cumulative += sq.targetWeight
    if randomValue <= cumulative:
      return some(sq.squadron.id)

  # Fallback (shouldn't reach here)
  return some(candidates[^1].squadron.id)

## High-level targeting interface

proc selectTargetForAttack*(
  attacker: CombatSquadron,
  attackerTF: TaskForce,
  allTaskForces: seq[TaskForce],
  diplomaticRelations: Table[tuple[a, b: HouseId], DiplomaticState],
  systemOwner: Option[HouseId],
  rng: var CombatRNG,
  allowStarbaseTargeting: bool = true
): Option[SquadronId] =
  ## Complete target selection process for one attacking squadron
  ##
  ## Returns: Selected target squadron ID, or none if no valid targets
  ## If allowStarbaseTargeting=false, starbases are screened and cannot be targeted

  # Step 1: Diplomatic filtering
  let hostileSquadrons = filterHostileSquadrons(
    attackerTF,
    allTaskForces,
    diplomaticRelations,
    systemOwner,
    allowStarbaseTargeting
  )

  if hostileSquadrons.len == 0:
    return none(SquadronId)

  # Step 2: Build candidate pool by bucket priority
  let candidates = buildCandidatePool(hostileSquadrons, attacker.bucket)

  if candidates.len == 0:
    return none(SquadronId)

  # Step 3: Weighted random selection
  return selectTarget(candidates, rng)

## Debug/testing helpers

proc getCandidateInfo*(candidates: seq[CombatSquadron]): string =
  ## Format candidate pool for logging
  result = "Candidates: " & $candidates.len & " ["
  for i, sq in candidates:
    if i > 0: result.add(", ")
    result.add($sq.bucket & ":" & $sq.squadron.id)
    if sq.state == CombatState.Crippled:
      result.add("(CRIP)")
  result.add("]")
