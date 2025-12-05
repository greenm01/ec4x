## Fleet Domain Goals (Domestikos)
##
## Strategic goals for fleet operations:
## - DefendColony: Establish defensive fleet presence
## - SecureSystem: Capture and hold system
## - InvadeColony: Conquer enemy colony
## - EliminateFleet: Destroy enemy fleet
## - EstablishFleetPresence: Position fleet for strategic control
## - ConductReconnaissance: Scout system for intelligence

import std/[tables, options]
import ../../core/[types, conditions, heuristics]
import ../../state/effects
import ../../../../../common/types/[core, tech]

# =============================================================================
# Fleet Goal Constructors
# =============================================================================

proc createDefendColonyGoal*(
  systemId: SystemId,
  priority: float,
  minDefenseStrength: int = 3
): Goal =
  ## Create goal to defend a vulnerable colony
  ##
  ## Preconditions:
  ## - Must own the colony
  ## - Must have sufficient budget for defense fleet
  ##
  ## Success: Colony removed from vulnerableColonies list

  result = Goal(
    goalType: GoalType.DefendColony,
    priority: priority,
    target: some(systemId),
    targetHouse: none(HouseId),
    requiredResources: 100,  # Minimum 1 cruiser
    deadline: none(int),
    preconditions: @[
      controlsSystem(systemId),
      hasMinBudget(100)
    ],
    successCondition: nil,  # TODO: Create success condition in Phase 3
    description: "Defend colony at system " & $systemId
  )

proc createInvadeColonyGoal*(
  systemId: SystemId,
  targetHouse: HouseId,
  priority: float
): Goal =
  ## Create goal to invade enemy colony
  ##
  ## Preconditions:
  ## - Must have invasion force budget (transport + marines + escorts)
  ## - Target must be known enemy colony
  ##
  ## Success: System added to ownedColonies

  result = Goal(
    goalType: GoalType.InvadeColony,
    priority: priority,
    target: some(systemId),
    targetHouse: some(targetHouse),
    requiredResources: 210,  # Transport (60) + Marines (50) + Escorts (100)
    deadline: none(int),
    preconditions: @[
      hasMinBudget(210)
    ],
    successCondition: nil,
    description: "Invade colony at system " & $systemId & " owned by " & targetHouse
  )

proc createSecureSystemGoal*(
  systemId: SystemId,
  priority: float,
  sustainedPresence: bool = true
): Goal =
  ## Create goal to capture and hold a strategic system
  ##
  ## Similar to InvadeColony but focuses on military control
  ## May require larger force for sustained presence

  result = Goal(
    goalType: GoalType.SecureSystem,
    priority: priority,
    target: some(systemId),
    targetHouse: none(HouseId),
    requiredResources: if sustainedPresence: 400 else: 300,
    deadline: none(int),
    preconditions: @[
      hasMinBudget(300)
    ],
    successCondition: nil,
    description: "Secure system " & $systemId
  )

proc createEliminateFleetGoal*(
  targetHouse: HouseId,
  priority: float,
  estimatedEnemyStrength: int
): Goal =
  ## Create goal to destroy enemy fleet
  ##
  ## Requires superior force to enemy fleet
  ## estimatedEnemyStrength should be from intelligence

  let requiredStrength = (estimatedEnemyStrength * 150) div 100  # 1.5x enemy strength

  result = Goal(
    goalType: GoalType.EliminateFleet,
    priority: priority,
    target: none(SystemId),
    targetHouse: some(targetHouse),
    requiredResources: requiredStrength * 10,  # Rough PP estimate
    deadline: none(int),
    preconditions: @[
      createPrecondition(ConditionKind.HasFleetStrength,
                        {"minStrength": requiredStrength}.toTable)
    ],
    successCondition: nil,
    description: "Eliminate fleet of " & targetHouse
  )

proc createEstablishFleetPresenceGoal*(
  systemId: SystemId,
  priority: float
): Goal =
  ## Create goal to position fleet at strategic location
  ##
  ## Uses existing idle fleet (no build cost)
  ## For patrol, deterrence, or strategic positioning

  result = Goal(
    goalType: GoalType.EstablishFleetPresence,
    priority: priority,
    target: some(systemId),
    targetHouse: none(HouseId),
    requiredResources: 0,  # Movement only
    deadline: none(int),
    preconditions: @[
      createPrecondition(ConditionKind.HasFleet, initTable[string, int]())
    ],
    successCondition: nil,
    description: "Establish fleet presence at system " & $systemId
  )

proc createConductReconnaissanceGoal*(
  systemId: SystemId,
  priority: float
): Goal =
  ## Create goal to scout system for intelligence
  ##
  ## Updates intelligence on enemy colonies, fleets, defenses
  ## Low cost if scouts available, otherwise need to build scout

  result = Goal(
    goalType: GoalType.ConductReconnaissance,
    priority: priority,
    target: some(systemId),
    targetHouse: none(HouseId),
    requiredResources: 30,  # Scout cost if needed
    deadline: none(int),
    preconditions: @[],  # No hard preconditions
    successCondition: nil,
    description: "Conduct reconnaissance of system " & $systemId
  )

# =============================================================================
# Fleet Goal Analysis
# =============================================================================

proc analyzeDefenseNeeds*(state: WorldStateSnapshot): seq[Goal] =
  ## Analyze which colonies need defensive fleets
  ##
  ## Returns goals ordered by priority (most critical first)

  result = @[]

  # High priority: Undefended high-value colonies
  for systemId in state.vulnerableColonies:
    if systemId in state.ownedColonies:
      let goal = createDefendColonyGoal(systemId, priority = 0.9)
      result.add(goal)

  # Critical priority: Completely undefended colonies
  for systemId in state.undefendedColonies:
    if systemId in state.ownedColonies:
      let goal = createDefendColonyGoal(systemId, priority = 1.0)
      result.add(goal)

proc analyzeOffensiveOpportunities*(state: WorldStateSnapshot): seq[Goal] =
  ## Analyze invasion opportunities
  ##
  ## Returns goals for weak enemy colonies

  result = @[]

  for systemId in state.invasionOpportunities:
    # Find owner from knownEnemyColonies
    var owner: Option[HouseId] = none(HouseId)
    for (sys, house) in state.knownEnemyColonies:
      if sys == systemId:
        owner = some(house)
        break

    if owner.isSome:
      let goal = createInvadeColonyGoal(
        systemId,
        owner.get(),
        priority = 0.7  # Offensive operations are high but not critical
      )
      result.add(goal)

proc analyzeReconnaissanceNeeds*(state: WorldStateSnapshot): seq[Goal] =
  ## Analyze which systems need intelligence updates
  ##
  ## Returns goals for stale intel systems

  result = @[]

  for systemId in state.staleIntelSystems:
    let goal = createConductReconnaissanceGoal(
      systemId,
      priority = 0.5  # Intelligence gathering is medium priority
    )
    result.add(goal)
