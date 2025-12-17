## Fleet Domain Goals (Domestikos)
##
## Strategic goals for fleet operations:
## - DefendColony: Establish defensive fleet presence
## - SecureSystem: Capture and hold system
## - InvadeColony: Conquer enemy colony
## - EliminateFleet: Destroy enemy fleet
## - EstablishFleetPresence: Position fleet for strategic control
## - ConductReconnaissance: Scout system for intelligence

import std/[tables, options, math, strformat]
import ../../core/[types, conditions, heuristics]
import ../../state/effects
import ../../../../../engine/intelligence/types as intel_types
import ../../../../../engine/logger
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
    requiredResources: 200,  # Lowered from 500 for early-game invasions
    deadline: none(int),
    preconditions: @[
      hasMinBudget(200)  # Lowered from 500 to enable early invasions
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
    requiredResources: 300, # Lowered from 800 for early-game operations
    deadline: none(int),
    preconditions: @[
      hasMinBudget(300)  # Lowered from 800 to enable early operations
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
  ## Phase 3.4: Applies intel quality and staleness weighting

  result = @[]

  # DEBUG: Log vulnerable targets count
  logDebug(LogCategory.lcAI,
    &"GOAP analyzeOffensive: {state.intelSnapshot.military.vulnerableTargets.len} vulnerable targets found")

  # Use detailed vulnerable targets from intelligence snapshot
  for target in state.intelSnapshot.military.vulnerableTargets:
    logDebug(LogCategory.lcAI,
      &"GOAP: Analyzing target system {target.systemId} (owner={target.owner}, vuln={target.vulnerability:.2f})")
    # Base priority from vulnerability score (0.0-1.0 → 0.5-0.9 priority range)
    var priority = 0.5 + (target.vulnerability * 0.4)

    # Phase 3.4: Apply intel quality multiplier
    let qualityMultiplier = case target.intelQuality
      of intel_types.IntelQuality.Perfect:
        1.2  # High confidence in assessment
      of intel_types.IntelQuality.Spy:
        1.0  # Good intelligence
      of intel_types.IntelQuality.Scan:
        0.7  # Basic scan data
      of intel_types.IntelQuality.Visual:
        0.5  # Visual sighting only, low confidence
      else:
        0.8  # Unknown quality, moderate confidence

    priority *= qualityMultiplier

    # Phase 3.4: Apply staleness penalty (intel >5 turns old)
    let intelAge = state.turn - target.lastIntelTurn
    if intelAge > 5:
      # Decay priority by 10% per turn over 5 turns, minimum 50%
      let stalenessPenalty = max(0.5, 1.0 - (float(intelAge - 5) * 0.1))
      priority *= stalenessPenalty

    # Clamp priority to valid range [0.0, 1.0]
    priority = clamp(priority, 0.0, 1.0)

    let goal = createInvadeColonyGoal(
      target.systemId,
      target.owner,
      priority = priority
    )
    result.add(goal)
    logDebug(LogCategory.lcAI,
      &"GOAP: Created InvadeColony goal for system {target.systemId} (priority={priority:.2f})")

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
