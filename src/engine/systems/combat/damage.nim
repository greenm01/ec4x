## Squadron Damage and State Transition System
##
## Implements damage application, state transitions, and
## destruction protection rules for EC4X combat (Section 7.3.3)

import std/[options, tables]
import ../../types/[core, combat as combat_types, squadron, ship]
import ../../state/entity_manager
import ../squadron/entity as squadron_entity

export combat_types

## Damage Application

proc applyDamageToSquadron*(
  squadron: var CombatSquadron,
  damage: int32,
  defenseStrength: int32,
  roundNumber: int32,
  isCriticalHit: bool
): StateChange =
  ## Apply damage to a squadron and handle state transitions
  ## Returns StateChange describing what happened
  ##
  ## Destruction Protection (Section 7.3.3):
  ## - Squadron cannot go Undamaged → Crippled → Destroyed in same round
  ## - Critical hits bypass this protection
  ##
  ## Parameters:
  ## - defenseStrength: Current DS of the squadron (from Squadron entity)

  let initialState = squadron.state
  var newState = initialState

  # Already destroyed - no further damage
  if squadron.state == CombatState.Destroyed:
    return StateChange(
      targetId: CombatTargetId(kind: CombatTargetKind.Squadron, squadronId: squadron.squadronId),
      fromState: initialState,
      toState: initialState,
      destructionProtectionApplied: false
    )

  # Track damage this turn for destruction protection
  squadron.damageThisTurn += damage
  let totalDamage = squadron.damageThisTurn
  let ds = defenseStrength

  case squadron.state
  of CombatState.Undamaged:
    # Check if damage meets crippling threshold
    if totalDamage >= ds:
      newState = CombatState.Crippled
      squadron.state = CombatState.Crippled
      squadron.crippleRound = roundNumber

      # Check for immediate destruction
      let excessDamage = totalDamage - ds
      if excessDamage >= ds:
        # Has enough damage to destroy, but check protection
        if isCriticalHit or squadron.crippleRound < roundNumber:
          # Critical hit bypasses protection, or was crippled in previous round
          newState = CombatState.Destroyed
          squadron.state = CombatState.Destroyed
        else:
          # Destruction protection applies - stays crippled
          return StateChange(
            targetId: CombatTargetId(kind: CombatTargetKind.Squadron, squadronId: squadron.squadronId),
            fromState: initialState,
            toState: CombatState.Crippled,
            destructionProtectionApplied: true
          )

  of CombatState.Crippled:
    # Already crippled, check for destruction
    if totalDamage >= ds:
      newState = CombatState.Destroyed
      squadron.state = CombatState.Destroyed

  of CombatState.Destroyed:
    # Already handled above
    discard

  return StateChange(
    targetId: CombatTargetId(kind: CombatTargetKind.Squadron, squadronId: squadron.squadronId),
    fromState: initialState,
    toState: newState,
    destructionProtectionApplied: false
  )

## Damage Application - Facilities

proc applyDamageToFacility*(
  facility: var CombatFacility,
  damage: int32,
  roundNumber: int32,
  isCriticalHit: bool
): StateChange =
  ## Apply damage to a facility and handle state transitions
  ## Returns StateChange describing what happened
  ##
  ## Facilities use same destruction protection rules as squadrons
  ## Defense strength comes from facility.defenseStrength field

  let initialState = facility.state
  var newState = initialState

  # Already destroyed - no further damage
  if facility.state == CombatState.Destroyed:
    return StateChange(
      targetId: CombatTargetId(kind: CombatTargetKind.Facility, facilityId: facility.facilityId),
      fromState: initialState,
      toState: initialState,
      destructionProtectionApplied: false
    )

  # Track damage this turn for destruction protection
  facility.damageThisTurn += damage
  let totalDamage = facility.damageThisTurn
  let ds = facility.defenseStrength  # Use stored DS

  case facility.state
  of CombatState.Undamaged:
    # Check if damage meets crippling threshold
    if totalDamage >= ds:
      newState = CombatState.Crippled
      facility.state = CombatState.Crippled
      facility.crippleRound = roundNumber

      # Check for immediate destruction
      let excessDamage = totalDamage - ds
      if excessDamage >= ds:
        # Has enough damage to destroy, but check protection
        if isCriticalHit or facility.crippleRound < roundNumber:
          # Critical hit bypasses protection, or was crippled in previous round
          newState = CombatState.Destroyed
          facility.state = CombatState.Destroyed
        else:
          # Destruction protection applies - stays crippled
          return StateChange(
            targetId: CombatTargetId(kind: CombatTargetKind.Facility, facilityId: facility.facilityId),
            fromState: initialState,
            toState: CombatState.Crippled,
            destructionProtectionApplied: true
          )

  of CombatState.Crippled:
    # Already crippled, check for destruction
    if totalDamage >= ds:
      newState = CombatState.Destroyed
      facility.state = CombatState.Destroyed

  of CombatState.Destroyed:
    # Already handled above
    discard

  return StateChange(
    targetId: CombatTargetId(kind: CombatTargetKind.Facility, facilityId: facility.facilityId),
    fromState: initialState,
    toState: newState,
    destructionProtectionApplied: false
  )

## Damage Reset (between rounds)

proc resetRoundDamage*(squadron: var CombatSquadron) =
  ## Reset damage tracking at start of new round
  ## Destruction protection only applies within a single round
  squadron.damageThisTurn = 0

proc resetRoundDamage*(facility: var CombatFacility) =
  ## Reset damage tracking at start of new round
  ## Destruction protection only applies within a single round
  facility.damageThisTurn = 0

## Critical Hit Special Rules (Section 7.3.3)

proc findWeakestSquadron*(
  combatSquadrons: seq[CombatSquadron],
  squadrons: Squadrons,
  ships: Ships
): Option[SquadronId] =
  ## Find squadron with lowest current DS in combat squadrons list
  ## Used for Force Reduction when critical hit can't reduce selected target
  ##
  ## Following DoD pattern:
  ## - Takes combat state (seq[CombatSquadron]) as parameter
  ## - Takes entity access (Squadrons, Ships) for DS calculation
  ## - Returns ID, not embedded object

  if combatSquadrons.len == 0:
    return none(SquadronId)

  var weakestId: Option[SquadronId] = none(SquadronId)
  var lowestDS = int.high

  for combatSq in combatSquadrons:
    # Skip destroyed squadrons
    if combatSq.state == CombatState.Destroyed:
      continue

    # Get Squadron entity to calculate DS
    let squadronOpt = squadrons.entities.getEntity(combatSq.squadronId)
    if squadronOpt.isNone:
      continue

    let squadron = squadronOpt.get()
    let ds = squadron_entity.defenseStrength(squadron, ships)

    if ds < lowestDS:
      lowestDS = ds
      weakestId = some(combatSq.squadronId)

  return weakestId

proc applyForceReduction*(
  combatSquadrons: var seq[CombatSquadron],
  targetId: SquadronId,
  damage: int32,
  defenseStrength: int32,
  roundNumber: int32,
  squadrons: Squadrons,
  ships: Ships
): StateChange =
  ## Apply Force Reduction rule for critical hits (Section 7.3.3)
  ## If insufficient damage to reduce target, reduce weakest unit instead
  ##
  ## Following DoD pattern:
  ## - Takes combat state (var seq[CombatSquadron]) for mutation
  ## - Takes entity access (Squadrons, Ships) for DS calculations
  ## - Modifies combat state in place

  # Find target squadron in combat state
  var targetIdx = -1
  for i, combatSq in combatSquadrons:
    if combatSq.squadronId == targetId:
      targetIdx = i
      break

  if targetIdx < 0:
    # Target not found - this shouldn't happen in normal combat
    return StateChange(
      targetId: CombatTargetId(kind: CombatTargetKind.Squadron, squadronId: targetId),
      fromState: CombatState.Undamaged,
      toState: CombatState.Undamaged,
      destructionProtectionApplied: false
    )

  # Try to apply damage to target
  var targetCombatSq = combatSquadrons[targetIdx]
  let targetChange = applyDamageToSquadron(
    targetCombatSq,
    damage,
    defenseStrength,
    roundNumber,
    isCriticalHit = true  # Force Reduction is from critical hit
  )

  # If target was reduced (state changed), apply damage and return
  if targetChange.toState != targetChange.fromState:
    combatSquadrons[targetIdx] = targetCombatSq
    return targetChange

  # Target not reduced - find weakest squadron for Force Reduction
  let weakestIdOpt = findWeakestSquadron(combatSquadrons, squadrons, ships)
  if weakestIdOpt.isNone:
    # No valid target found, damage wasted
    return targetChange

  let weakestId = weakestIdOpt.get()

  # Find weakest squadron in combat state
  var weakestIdx = -1
  for i, combatSq in combatSquadrons:
    if combatSq.squadronId == weakestId:
      weakestIdx = i
      break

  if weakestIdx < 0:
    return targetChange

  # Get weakest squadron's DS for damage application
  let weakestSquadronOpt = squadrons.entities.getEntity(weakestId)
  if weakestSquadronOpt.isNone:
    return targetChange

  let weakestSquadron = weakestSquadronOpt.get()
  let weakestDS = squadron_entity.defenseStrength(weakestSquadron, ships).int32

  # Apply damage to weakest squadron
  var weakestCombatSq = combatSquadrons[weakestIdx]
  let weakestChange = applyDamageToSquadron(
    weakestCombatSq,
    damage,
    weakestDS,
    roundNumber,
    isCriticalHit = true
  )

  combatSquadrons[weakestIdx] = weakestCombatSq
  return weakestChange

## Batch Damage Operations

proc applySimultaneousDamage*(
  combatSquadrons: var seq[CombatSquadron],
  damageMap: seq[tuple[squadronId: SquadronId, damage: int32, defenseStrength: int32, isCritical: bool]],
  roundNumber: int32
): seq[StateChange] =
  ## Apply damage from multiple attackers simultaneously
  ## Handles overkill and destruction protection correctly
  ##
  ## Section 7.3.3: All damage applied simultaneously, then state transitions evaluated
  ##
  ## Following DoD pattern:
  ## - Takes combat state (var seq[CombatSquadron]) for mutation
  ## - Takes damage map with pre-calculated DS values
  ## - Accumulates damage, then evaluates all state transitions at once

  result = @[]

  # Build lookup table for squadron indices
  var squadronIndices: Table[SquadronId, int] = initTable[SquadronId, int]()
  for i, combatSq in combatSquadrons:
    squadronIndices[combatSq.squadronId] = i

  # Accumulate all damage first (simultaneous damage rule)
  for entry in damageMap:
    let idx = squadronIndices.getOrDefault(entry.squadronId, -1)
    if idx < 0:
      continue  # Squadron not found

    var combatSq = combatSquadrons[idx]

    # Skip already destroyed squadrons
    if combatSq.state == CombatState.Destroyed:
      continue

    # Accumulate damage
    combatSq.damageThisTurn += entry.damage
    combatSquadrons[idx] = combatSq

  # Now evaluate all state transitions based on accumulated damage
  for entry in damageMap:
    let idx = squadronIndices.getOrDefault(entry.squadronId, -1)
    if idx < 0:
      continue

    var combatSq = combatSquadrons[idx]

    # Apply state transitions based on accumulated damage
    let change = applyDamageToSquadron(
      combatSq,
      damage = 0,  # Damage already accumulated above
      defenseStrength = entry.defenseStrength,
      roundNumber = roundNumber,
      isCriticalHit = entry.isCritical
    )

    combatSquadrons[idx] = combatSq

    # Only record actual state changes
    if change.toState != change.fromState:
      result.add(change)

## Query functions

proc isDestroyed*(squadron: CombatSquadron): bool =
  ## Check if squadron is destroyed
  squadron.state == CombatState.Destroyed

proc isCrippled*(squadron: CombatSquadron): bool =
  ## Check if squadron is crippled
  squadron.state == CombatState.Crippled

proc getAliveSquadrons*(combatSquadrons: seq[CombatSquadron]): seq[CombatSquadron] =
  ## Get all non-destroyed squadrons
  ## Following DoD pattern: operates on combat state sequence
  result = @[]
  for combatSq in combatSquadrons:
    if combatSq.state != CombatState.Destroyed:
      result.add(combatSq)

proc countAlive*(combatSquadrons: seq[CombatSquadron]): int32 =
  ## Count non-destroyed squadrons
  ## Following DoD pattern: operates on combat state sequence
  result = 0
  for combatSq in combatSquadrons:
    if combatSq.state != CombatState.Destroyed:
      result += 1

## String formatting for logs

proc `$`*(change: StateChange): string =
  ## Pretty print state change for logs
  case change.targetId.kind
  of CombatTargetKind.Squadron:
    result = "Squadron " & $change.targetId.squadronId & ": "
  of CombatTargetKind.Facility:
    result = "Facility " & $change.targetId.facilityId & ": "
  result &= $change.fromState & " → " & $change.toState
  if change.destructionProtectionApplied:
    result &= " (destruction protection applied)"
