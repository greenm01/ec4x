## Squadron Damage and State Transition System
##
## Implements damage application, state transitions, and
## destruction protection rules for EC4X combat (Section 7.3.3)

import std/options
import types

export CombatState, StateChange

## Damage Application

proc applyDamageToSquadron*(
  squadron: var CombatSquadron,
  damage: int,
  roundNumber: int,
  isCriticalHit: bool
): StateChange =
  ## Apply damage to a squadron and handle state transitions
  ## Returns StateChange describing what happened
  ##
  ## Destruction Protection (Section 7.3.3):
  ## - Squadron cannot go Undamaged → Crippled → Destroyed in same round
  ## - Critical hits bypass this protection

  let initialState = squadron.state
  var newState = initialState

  # Already destroyed - no further damage
  if squadron.state == CombatState.Destroyed:
    return StateChange(
      squadronId: squadron.squadron.id,
      fromState: initialState,
      toState: initialState,
      destructionProtectionApplied: false
    )

  # Track damage this turn for destruction protection
  squadron.damageThisTurn += damage
  let totalDamage = squadron.damageThisTurn
  let ds = squadron.getCurrentDS()

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
            squadronId: squadron.squadron.id,
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
    squadronId: squadron.squadron.id,
    fromState: initialState,
    toState: newState,
    destructionProtectionApplied: false
  )

## Damage Reset (between rounds)

proc resetRoundDamage*(squadron: var CombatSquadron) =
  ## Reset damage tracking at start of new round
  ## Destruction protection only applies within a single round
  squadron.damageThisTurn = 0

## Critical Hit Special Rules (Section 7.3.3)

proc findWeakestSquadron*(taskForce: TaskForce): Option[SquadronId] =
  ## Find squadron with lowest current DS in Task Force
  ## Used for Force Reduction when critical hit can't reduce selected target

  var weakest: Option[CombatSquadron] = none(CombatSquadron)
  var lowestDS = int.high

  for sq in taskForce.squadrons:
    if not sq.isAlive():
      continue

    let ds = sq.getCurrentDS()
    if ds < lowestDS:
      lowestDS = ds
      weakest = some(sq)

  if weakest.isSome():
    return some(weakest.get().squadron.id)
  else:
    return none(SquadronId)

proc applyForceReduction*(
  taskForce: var TaskForce,
  targetId: SquadronId,
  damage: int,
  roundNumber: int
): StateChange =
  ## Apply Force Reduction rule for critical hits (Section 7.3.3)
  ## If insufficient damage to reduce target, reduce weakest unit instead

  # Find target squadron
  var targetSquadron: Option[int] = none(int)
  for i, sq in taskForce.squadrons:
    if sq.squadron.id == targetId:
      targetSquadron = some(i)
      break

  if targetSquadron.isNone():
    # Target not found - shouldn't happen
    return StateChange(
      squadronId: targetId,
      fromState: CombatState.Destroyed,
      toState: CombatState.Destroyed,
      destructionProtectionApplied: false
    )

  let targetIdx = targetSquadron.get()
  var target = taskForce.squadrons[targetIdx]
  let targetDS = target.getCurrentDS()

  # Check if damage is sufficient to reduce target
  if damage >= targetDS:
    # Sufficient - apply to target with critical hit flag
    let change = applyDamageToSquadron(target, damage, roundNumber, isCriticalHit = true)
    taskForce.squadrons[targetIdx] = target
    return change

  # Insufficient - find and reduce weakest squadron
  let weakestId = findWeakestSquadron(taskForce)
  if weakestId.isNone():
    # No valid target - shouldn't happen
    return StateChange(
      squadronId: targetId,
      fromState: target.state,
      toState: target.state,
      destructionProtectionApplied: false
    )

  # Find weakest and reduce it
  for i, sq in taskForce.squadrons.mpairs:
    if sq.squadron.id == weakestId.get():
      # Apply damage equal to its DS to guarantee reduction
      let change = applyDamageToSquadron(sq, sq.getCurrentDS(), roundNumber, isCriticalHit = true)
      return change

  # Fallback - shouldn't reach here
  return StateChange(
    squadronId: targetId,
    fromState: target.state,
    toState: target.state,
    destructionProtectionApplied: false
  )

## Batch Damage Operations

proc applySimultaneousDamage*(
  taskForce: var TaskForce,
  damageMap: seq[tuple[squadronId: SquadronId, damage: int, isCritical: bool]],
  roundNumber: int
): seq[StateChange] =
  ## Apply damage from multiple attackers simultaneously
  ## Handles overkill and destruction protection correctly
  ##
  ## Section 7.3.3: All damage applied simultaneously, then state transitions evaluated

  result = @[]

  # Group damage by squadron
  var squadronDamage: seq[tuple[squadronId: SquadronId, totalDamage: int, hasCritical: bool]] = @[]

  for entry in damageMap:
    var found = false
    for i in 0..<squadronDamage.len:
      if squadronDamage[i].squadronId == entry.squadronId:
        squadronDamage[i].totalDamage += entry.damage
        if entry.isCritical:
          squadronDamage[i].hasCritical = true
        found = true
        break

    if not found:
      squadronDamage.add((entry.squadronId, entry.damage, entry.isCritical))

  # Apply accumulated damage to each squadron
  for entry in squadronDamage:
    for i in 0..<taskForce.squadrons.len:
      if taskForce.squadrons[i].squadron.id == entry.squadronId:
        let change = applyDamageToSquadron(
          taskForce.squadrons[i],
          entry.totalDamage,
          roundNumber,
          entry.hasCritical
        )
        result.add(change)
        break

## Query functions

proc isDestroyed*(squadron: CombatSquadron): bool =
  ## Check if squadron is destroyed
  squadron.state == CombatState.Destroyed

proc isCrippled*(squadron: CombatSquadron): bool =
  ## Check if squadron is crippled
  squadron.state == CombatState.Crippled

proc getAliveSquadrons*(taskForce: TaskForce): seq[CombatSquadron] =
  ## Get all non-destroyed squadrons
  result = @[]
  for sq in taskForce.squadrons:
    if not sq.isDestroyed():
      result.add(sq)

proc countAlive*(taskForce: TaskForce): int =
  ## Count non-destroyed squadrons
  result = 0
  for sq in taskForce.squadrons:
    if not sq.isDestroyed():
      result += 1

## String formatting for logs

proc `$`*(change: StateChange): string =
  ## Pretty print state change for logs
  result = "Squadron " & change.squadronId & ": "
  result &= $change.fromState & " → " & $change.toState
  if change.destructionProtectionApplied:
    result &= " (destruction protection applied)"
