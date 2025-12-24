## Squadron Damage and State Transition System
##
## Implements damage application, state transitions, and
## destruction protection rules for EC4X combat (Section 7.3.3)

import std/options
import ../../types/[core, combat as combat_types]

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

# NOTE: These functions need redesign for ID-based TaskForce structure
# TaskForce now stores squadronIds: seq[SquadronId], not embedded CombatSquadron objects
# Combat state is tracked separately during combat resolution
# These functions will be implemented in the combat engine that has access to
# both the combat state and the entity data

when false:  # Disabled until combat engine integration is complete
  proc findWeakestSquadron*(taskForce: TaskForce): Option[SquadronId] =
    ## Find squadron with lowest current DS in Task Force
    ## Used for Force Reduction when critical hit can't reduce selected target
    ##
    ## TODO: Redesign to work with ID-based structure
    ## Needs access to Squadron entities for DS values
    discard

when false:  # Disabled until combat engine integration is complete
  proc applyForceReduction*(
    taskForce: var TaskForce,
    targetId: SquadronId,
    damage: int32,
    defenseStrength: int32,
    roundNumber: int32
  ): StateChange =
    ## Apply Force Reduction rule for critical hits (Section 7.3.3)
    ## If insufficient damage to reduce target, reduce weakest unit instead
    ##
    ## TODO: Redesign to work with ID-based structure and CombatSquadron tracking
    discard

## Batch Damage Operations

when false:  # Disabled until combat engine integration is complete
  proc applySimultaneousDamage*(
    taskForce: var TaskForce,
    damageMap: seq[tuple[squadronId: SquadronId, damage: int32, isCritical: bool]],
    roundNumber: int32
  ): seq[StateChange] =
    ## Apply damage from multiple attackers simultaneously
    ## Handles overkill and destruction protection correctly
    ##
    ## Section 7.3.3: All damage applied simultaneously, then state transitions evaluated
    ##
    ## TODO: Redesign to work with ID-based structure and separate CombatSquadron tracking
    discard

## Query functions

proc isDestroyed*(squadron: CombatSquadron): bool =
  ## Check if squadron is destroyed
  squadron.state == CombatState.Destroyed

proc isCrippled*(squadron: CombatSquadron): bool =
  ## Check if squadron is crippled
  squadron.state == CombatState.Crippled

when false:  # Disabled until combat engine integration is complete
  proc getAliveSquadrons*(taskForce: TaskForce): seq[CombatSquadron] =
    ## Get all non-destroyed squadrons
    ## TODO: Redesign - TaskForce now has squadronIds, not embedded CombatSquadron objects
    discard

  proc countAlive*(taskForce: TaskForce): int32 =
    ## Count non-destroyed squadrons
    ## TODO: Redesign - needs access to combat state tracking
    discard

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
