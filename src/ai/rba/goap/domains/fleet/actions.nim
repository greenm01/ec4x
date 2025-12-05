## Fleet Domain Actions (Domestikos)
##
## Concrete actions for fleet operations:
## - MoveFleet: Move fleet to system
## - AssembleInvasionForce: Coordinate multiple fleets
## - AttackColony: Execute invasion
## - EstablishDefense: Assign guard duty
## - ConductScoutMission: Reconnaissance operation

import std/[tables, options]
import ../../core/[types, conditions]
import ../../state/effects
import ../../../../../common/types/[core, units, tech]

# =============================================================================
# Fleet Action Constructors
# =============================================================================

proc createMoveFleetAction*(
  fleetId: FleetId,
  fromSystem: SystemId,
  toSystem: SystemId,
  distance: int
): Action =
  ## Create action to move fleet between systems
  ##
  ## Cost: 0 PP (movement is free)
  ## Duration: Based on distance and fleet speed

  let turnDuration = (distance + 2) div 3  # Rough estimate: 3 hexes per turn

  result = Action(
    actionType: ActionType.MoveFleet,
    cost: 0,  # Movement is free
    duration: turnDuration,
    target: some(toSystem),
    targetHouse: none(HouseId),
    shipClass: none(ShipClass),
    quantity: 0,
    techField: none(TechField),
    preconditions: @[
      createPrecondition(ConditionKind.HasFleet, initTable[string, int]())
    ],
    effects: @[],  # Phase 1: Fleet position tracking not implemented
    description: "Move fleet " & fleetId & " from " & $fromSystem & " to " & $toSystem
  )

proc createAssembleInvasionForceAction*(
  targetSystem: SystemId,
  requiredStrength: int
): Action =
  ## Create action to coordinate multiple fleets for invasion
  ##
  ## Gathers fleets at staging point before invasion

  result = Action(
    actionType: ActionType.AssembleInvasionForce,
    cost: 0,  # Coordination is free
    duration: 2,  # Takes time to coordinate
    target: some(targetSystem),
    targetHouse: none(HouseId),
    shipClass: none(ShipClass),
    quantity: 0,
    techField: none(TechField),
    preconditions: @[
      createPrecondition(ConditionKind.HasFleetStrength,
                        {"minStrength": requiredStrength}.toTable)
    ],
    effects: @[],
    description: "Assemble invasion force for system " & $targetSystem
  )

proc createAttackColonyAction*(
  systemId: SystemId,
  targetHouse: HouseId,
  attackStrength: int
): Action =
  ## Create action to execute planetary invasion
  ##
  ## Requires assembled invasion force with transports and marines

  result = Action(
    actionType: ActionType.AttackColony,
    cost: 0,  # Combat is free (units already built)
    duration: 1,  # Combat resolution is instant
    target: some(systemId),
    targetHouse: some(targetHouse),
    shipClass: none(ShipClass),
    quantity: 0,
    techField: none(TechField),
    preconditions: @[
      createPrecondition(ConditionKind.HasFleetStrength,
                        {"minStrength": attackStrength}.toTable)
    ],
    effects: @[
      createEffect(EffectKind.GainControl, {"systemId": int(systemId)}.toTable)
    ],
    description: "Attack colony at system " & $systemId
  )

proc createEstablishDefenseAction*(
  systemId: SystemId,
  defenseStrength: int
): Action =
  ## Create action to assign fleet to defensive guard duty
  ##
  ## Fleet remains at system to defend against attacks

  result = Action(
    actionType: ActionType.EstablishDefense,
    cost: 0,  # Assignment is free
    duration: 1,
    target: some(systemId),
    targetHouse: none(HouseId),
    shipClass: none(ShipClass),
    quantity: 0,
    techField: none(TechField),
    preconditions: @[
      controlsSystem(systemId),
      createPrecondition(ConditionKind.HasFleet, initTable[string, int]())
    ],
    effects: @[
      defendColony(systemId)
    ],
    description: "Establish defense at system " & $systemId
  )

proc createConductScoutMissionAction*(
  systemId: SystemId
): Action =
  ## Create action to scout system for intelligence
  ##
  ## Updates intelligence database with current information

  result = Action(
    actionType: ActionType.ConductScoutMission,
    cost: 0,  # Scouting is free if scouts available
    duration: 1,
    target: some(systemId),
    targetHouse: none(HouseId),
    shipClass: none(ShipClass),
    quantity: 0,
    techField: none(TechField),
    preconditions: @[
      createPrecondition(ConditionKind.HasFleet, initTable[string, int]())
    ],
    effects: @[],  # Intelligence updates handled by game engine
    description: "Scout system " & $systemId
  )

# =============================================================================
# Fleet Action Planning
# =============================================================================

proc planDefenseActions*(
  state: WorldStateSnapshot,
  goal: Goal
): seq[Action] =
  ## Plan action sequence to achieve defense goal
  ##
  ## Returns ordered list of actions to defend colony

  result = @[]

  if goal.goalType != GoalType.DefendColony:
    return

  if goal.target.isNone:
    return

  let systemId = goal.target.get()

  # Simple plan: Move idle fleet to system and establish defense
  if state.idleFleets.len > 0:
    let fleetId = state.idleFleets[0]

    # Action 1: Move fleet to system (if not already there)
    # NOTE: Phase 1 doesn't track fleet positions, assume needs movement
    let moveAction = createMoveFleetAction(
      fleetId,
      SystemId(0),  # Unknown current position
      systemId,
      distance = 5  # Rough estimate
    )
    result.add(moveAction)

    # Action 2: Establish defensive posture
    let defenseAction = createEstablishDefenseAction(systemId, defenseStrength = 3)
    result.add(defenseAction)

proc planInvasionActions*(
  state: WorldStateSnapshot,
  goal: Goal
): seq[Action] =
  ## Plan action sequence to achieve invasion goal
  ##
  ## Returns ordered list of actions for invasion

  result = @[]

  if goal.goalType != GoalType.InvadeColony:
    return

  if goal.target.isNone or goal.targetHouse.isNone:
    return

  let systemId = goal.target.get()
  let targetHouse = goal.targetHouse.get()

  # Multi-step invasion plan:
  # 1. Assemble invasion force
  let assembleAction = createAssembleInvasionForceAction(
    systemId,
    requiredStrength = 20  # Minimum invasion strength
  )
  result.add(assembleAction)

  # 2. Execute attack
  let attackAction = createAttackColonyAction(
    systemId,
    targetHouse,
    attackStrength = 20
  )
  result.add(attackAction)

  # 3. Establish garrison (post-conquest defense)
  let garrisonAction = createEstablishDefenseAction(
    systemId,
    defenseStrength = 3
  )
  result.add(garrisonAction)

proc planReconnaissanceActions*(
  state: WorldStateSnapshot,
  goal: Goal
): seq[Action] =
  ## Plan action sequence to achieve reconnaissance goal
  ##
  ## Returns ordered list of actions for scouting

  result = @[]

  if goal.goalType != GoalType.ConductReconnaissance:
    return

  if goal.target.isNone:
    return

  let systemId = goal.target.get()

  # Simple plan: Scout mission
  let scoutAction = createConductScoutMissionAction(systemId)
  result.add(scoutAction)
