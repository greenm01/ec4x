## Fleet Domain Goals (Domestikos)
##
## Strategic goals for fleet operations:
## - DefendColony: Establish defensive fleet presence
## - SecureSystem: Capture and hold system
## - InvadeColony: Conquer enemy colony
## - EliminateFleet: Destroy enemy fleet
## - EstablishFleetPresence: Position fleet for strategic control
## - ConductReconnaissance: Scout system for intelligence

import std/[tables, options, math, strformat, sets, strutils]
import ../../core/[types, conditions, heuristics]
import ../../state/effects
import ../../../config  # For GOAPConfig
import ../../../../../engine/intelligence/types as intel_types
import ../../../../../engine/[logger, starmap]
import ../../../../../common/types/[core, tech]
import ../../../shared/intelligence_types  # For InvasionOpportunity
import campaign_classifier  # Phase 6: Campaign classification

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

proc analyzeOffensiveOpportunities*(
  state: WorldStateSnapshot,
  starMap: StarMap,
  config: GOAPConfig
): seq[Goal] =
  ## Analyze invasion opportunities with campaign classification
  ##
  ## Phase 6: GOAP Intelligence Integration
  ## - Classifies targets (Speculative/Raid/Assault/Deliberate)
  ## - Checks intelligence requirements
  ## - Generates goals even without sufficient intel (A* plans prerequisites)
  ## - Analyzes unexplored adjacent systems for speculative opportunities

  result = @[]

  # Convert ownedColonies seq to HashSet for efficient lookup
  var ownedColoniesSet = initHashSet[SystemId]()
  for colony in state.ownedColonies:
    ownedColoniesSet.incl(colony)

  # DEBUG: Log vulnerable targets count
  logDebug(LogCategory.lcAI,
    &"GOAP analyzeOffensive: {state.intelSnapshot.military.vulnerableTargets.len} vulnerable targets found")

  # Step 1: Analyze known targets from intelligence snapshot
  for target in state.intelSnapshot.military.vulnerableTargets:
    logDebug(LogCategory.lcAI,
      &"GOAP: Analyzing target system {target.systemId} (owner={target.owner}, vuln={target.vulnerability:.2f})")

    # Classify campaign type
    let campaignType = classifyCampaign(
      target,
      ownedColoniesSet,
      starMap,
      state.turn,
      config.intelligence_thresholds
    )

    # Check intelligence requirements
    let intelCheck = checkIntelligenceRequirements(
      target,
      state.turn,
      campaignType,
      config.intelligence_thresholds
    )

    # Calculate priority based on campaign type and intel status
    var priority = case campaignType
      of CampaignType.Speculative:
        # Speculative: Base on proximity confidence (40-60% range)
        assessSpeculativeConfidence(
          target.systemId,
          ownedColoniesSet,
          starMap,
          state.turn,
          config.intelligence_thresholds
        )
      of CampaignType.Raid:
        # Raid: High vulnerability + good intel = high priority
        0.5 + (target.vulnerability * 0.4)
      of CampaignType.Assault:
        # Assault: Moderate priority (planned operation)
        0.4 + (target.vulnerability * 0.3)
      of CampaignType.Deliberate:
        # Deliberate: Lower priority (fortified target, long campaign)
        0.3 + (target.vulnerability * 0.2)

    # Clamp priority to valid range [0.0, 1.0]
    priority = clamp(priority, 0.0, 1.0)

    # Create goal with campaign-specific preconditions
    var goal = createInvadeColonyGoal(
      target.systemId,
      target.owner,
      priority = priority
    )

    # Add campaign-specific intelligence preconditions
    case campaignType
    of CampaignType.Speculative:
      goal.preconditions.add(
        createPrecondition(
          ConditionKind.MeetsSpeculativeRequirements,
          {"systemId": int(target.systemId)}.toTable
        )
      )
    of CampaignType.Raid:
      goal.preconditions.add(
        createPrecondition(
          ConditionKind.MeetsRaidRequirements,
          {"systemId": int(target.systemId)}.toTable
        )
      )
    of CampaignType.Assault:
      goal.preconditions.add(
        createPrecondition(
          ConditionKind.MeetsAssaultRequirements,
          {"systemId": int(target.systemId)}.toTable
        )
      )
    of CampaignType.Deliberate:
      goal.preconditions.add(
        createPrecondition(
          ConditionKind.MeetsDeliberateRequirements,
          {"systemId": int(target.systemId)}.toTable
        )
      )

    # Add goal regardless of intel sufficiency - A* will plan prerequisites
    result.add(goal)

    if intelCheck.met:
      logDebug(LogCategory.lcAI,
        &"GOAP: Created {campaignType} InvadeColony goal for system {target.systemId} (priority={priority:.2f}, intel=sufficient)")
    else:
      logDebug(LogCategory.lcAI,
        &"GOAP: Created {campaignType} InvadeColony goal for system {target.systemId} (priority={priority:.2f}, intel=insufficient: {intelCheck.gaps.join(\", \")})")

  # Step 2: Analyze unexplored adjacent systems for speculative opportunities
  # (Systems not in vulnerableTargets but adjacent to owned colonies)
  for ownedColony in state.ownedColonies:
    # Get adjacent system IDs
    let adjacentIds = getAdjacentSystems(starMap, ownedColony.uint)

    for adjacentId in adjacentIds:
      let adjacentSystemId = SystemId(adjacentId)

      # Skip if already analyzed above
      var alreadyAnalyzed = false
      for target in state.intelSnapshot.military.vulnerableTargets:
        if target.systemId == adjacentSystemId:
          alreadyAnalyzed = true
          break

      if alreadyAnalyzed:
        continue

      # Check if truly unexplored (no intel at all)
      if adjacentSystemId notin state.systemIntelQuality:
        # Generate speculative invasion goal
        let speculativeConfidence = assessSpeculativeConfidence(
          adjacentSystemId,
          ownedColoniesSet,
          starMap,
          state.turn,
          config.intelligence_thresholds
        )

        # Only create goal if confidence meets minimum threshold
        if speculativeConfidence >= 0.4:
          var goal = createInvadeColonyGoal(
            adjacentSystemId,
            HouseId("unknown"),  # Don't know owner yet
            priority = speculativeConfidence
          )
          goal.preconditions.add(
            createPrecondition(
              ConditionKind.MeetsSpeculativeRequirements,
              {"systemId": int(adjacentSystemId)}.toTable
            )
          )
          result.add(goal)
          logDebug(LogCategory.lcAI,
            &"GOAP: Created Speculative InvadeColony goal for unexplored system {adjacentSystemId} (priority={speculativeConfidence:.2f})")

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
