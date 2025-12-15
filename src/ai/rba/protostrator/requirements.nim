## Protostrator Diplomatic Requirements Module
##
## Byzantine Imperial Protostrator - Diplomatic Requirements Generation
##
## Generates diplomatic requirements with priorities for Basileus mediation
## Intelligence-driven diplomacy (NAPs with strong enemies, wars against weak)

import std/[tables, options, strformat, strutils]
import ../../../common/types/[core, diplomacy]
import ../../../engine/[gamestate, fog_of_war, logger]
import ../../../engine/diplomacy/types as dip_types
import ../../../engine/diplomacy/proposals as dip_proposals
import ../controller_types
import ../shared/intelligence_types  # For IntelligenceSnapshot
import ../../common/types as ai_types
import ../intelligence # For countSharedBorders

# =============================================================================
# Dynamic Prestige Threshold Calculation
# =============================================================================

proc calculateDynamicThresholds(filtered: FilteredGameState): tuple[overwhelming: int, moderate: int, strong: int] =
  ## Calculate dynamic prestige thresholds based on average prestige across all houses
  ## Replaces hardcoded values (500, 200, 300) with game-state-responsive thresholds
  ##
  ## Scales with:
  ## - Map size (more colonies = higher prestige)
  ## - Game progression (prestige grows over time)
  ## - Number of active houses (elimination affects averages)
  ##
  ## Returns: (overwhelming, moderate, strong) prestige gap thresholds

  var totalPrestige = 0
  var houseCount = 0

  # Calculate average prestige across all active houses
  for houseId, prestige in filtered.housePrestige:
    if not filtered.houseEliminated.getOrDefault(houseId, false):
      totalPrestige += prestige
      houseCount += 1

  # Prevent division by zero
  if houseCount == 0:
    # Fallback to legacy hardcoded values if no houses exist
    return (overwhelming: 500, moderate: 200, strong: 300)

  let avgPrestige = totalPrestige div houseCount

  # Dynamic thresholds as % of average prestige
  # - Overwhelming: 35% of average (seek NAP to avoid conflict)
  # - Moderate: 15% of average (NAP if diplomatic-focused)
  # - Strong: 25% of average (strong diplomatic relations threshold)
  #
  # These percentages scale naturally with game progression:
  # Early game (avg ~300): overwhelming=105, moderate=45, strong=75
  # Mid game (avg ~800): overwhelming=280, moderate=120, strong=200
  # Late game (avg ~1500): overwhelming=525, moderate=225, strong=375
  result.overwhelming = (avgPrestige * 35) div 100
  result.moderate = (avgPrestige * 15) div 100
  result.strong = (avgPrestige * 25) div 100

  # Apply minimum thresholds to prevent division-by-zero issues in early game
  result.overwhelming = max(result.overwhelming, 50)
  result.moderate = max(result.moderate, 20)
  result.strong = max(result.strong, 30)

proc evaluateWarReadiness(
  ownPrestige: int,
  targetPrestige: int,
  ownColonies: int,
  targetColonies: int,
  hasVulnerableColonies: bool,
  sharedBorders: int,
  targetAllies: int,
  currentAct: ai_types.GameAct,
  personality: AIPersonality
): tuple[shouldDeclare: bool, score: float, reason: string] =
  ## Multi-factor war evaluation system (user-selected threshold: 3.0)
  ##
  ## Factors:
  ## 1. Prestige gap (act-adjusted thresholds)
  ## 2. Vulnerable colonies detected
  ## 3. Land hunger (own colonies < 6)
  ## 4. Border friction (shared borders >= 2)
  ## 5. Diplomatic isolation (target has no allies)
  ## 6. Personality scaling (aggression multiplier)

  var score = 0.0
  var reasons: seq[string] = @[]

  let prestigeGap = ownPrestige - targetPrestige

  # Factor 1: Prestige gap (act-adjusted thresholds)
  # prestigeGap = ownPrestige - targetPrestige, so POSITIVE = we're ahead
  # We want to declare war when we have a prestige LEAD, so prestigeGap should be POSITIVE
  # Thresholds based on observed prestige progression:
  #   Turn 2-7 (Act1): ~600-1600 prestige, gaps ~200-400
  #   Turn 8-15 (Act2): ~1600-3500 prestige, gaps ~400-800
  #   Turn 16-25 (Act3): ~3500-5500 prestige, gaps ~800-1200
  #   Turn 26+ (Act4): ~5500+ prestige, gaps ~1000+
  let actThreshold = case currentAct
    of ai_types.GameAct.Act1_LandGrab: 150   # Need moderate lead in Act 1 (early expansion, avoid early wars)
    of ai_types.GameAct.Act2_RisingTensions: 100  # Smaller lead in Act 2 (rising tensions)
    of ai_types.GameAct.Act3_TotalWar: 0   # Any lead in Act 3 (total war)
    of ai_types.GameAct.Act4_Endgame: -100      # Can even declare when slightly behind in Act 4 (desperate endgame)

  if prestigeGap > actThreshold:
    score += 2.0
    reasons.add(&"prestige lead ({prestigeGap})")

  # Factor 2: Vulnerable colonies detected
  if hasVulnerableColonies:
    score += 1.5
    reasons.add("vulnerable colonies")

  # Factor 3: Land hunger
  if ownColonies < 6 and currentAct >= ai_types.GameAct.Act2_RisingTensions:
    score += 1.5
    reasons.add(&"land hunger ({ownColonies} colonies)")

  # Factor 4: Border friction
  if sharedBorders >= 2:
    score += 0.5 * sharedBorders.float
    reasons.add(&"{sharedBorders} shared borders")

  # Factor 5: Diplomatic isolation
  if targetAllies == 0:
    score += 1.0
    reasons.add("target isolated")

  # Factor 6: Personality-adjusted war threshold
  # REMOVED: score *= personality.aggression (this made peaceful AIs never declare war)
  # NEW: Aggression affects threshold, not score
  #
  # Base thresholds (act-dependent):
  # - Act 1-2: 3.0 (moderate threshold for early expansion wars)
  # - Act 3-4: 2.5 (lower threshold for total war era)
  #
  # Personality scaling:
  # - Aggressive (0.7+): -1.0 threshold (easier to declare war)
  # - Moderate (0.3-0.7): +0.0 threshold (baseline)
  # - Defensive (0.0-0.3): +1.0 threshold (harder to declare war)
  let baseThreshold = case currentAct
    of ai_types.GameAct.Act1_LandGrab: 3.0
    of ai_types.GameAct.Act2_RisingTensions: 3.0
    of ai_types.GameAct.Act3_TotalWar: 2.5
    of ai_types.GameAct.Act4_Endgame: 2.5

  let personalityAdjustment = if personality.aggression >= 0.7:
      -1.0  # Aggressive personalities declare war easier
    elif personality.aggression >= 0.3:
      0.0   # Moderate personalities use base threshold
    else:
      1.0   # Defensive personalities avoid war

  let warThreshold = baseThreshold + personalityAdjustment

  let shouldDeclare = score >= warThreshold
  let reason = if shouldDeclare: reasons.join(", ") else: ""

  # DEBUG: Log war evaluation for diagnosis
  if score > 0.0 or shouldDeclare:
    logDebug(LogCategory.lcAI,
             &"War eval: own={ownPrestige} target={targetPrestige} gap={prestigeGap} " &
             &"score={score:.2f} threshold={warThreshold:.1f} (base={baseThreshold:.1f} adj={personalityAdjustment:+.1f}) " &
             &"declare={shouldDeclare} reasons=[{reasons.join(\", \")}]")

  return (shouldDeclare, score, reason)

proc generateDiplomaticRequirements*(
  controller: AIController,
  filtered: FilteredGameState,
  intelSnapshot: IntelligenceSnapshot
): DiplomaticRequirements =
  ## Generate diplomatic requirements with intelligence-driven priorities
  ##
  ## Priority tiers:
  ## - Critical: Emergency peace with overwhelming enemies
  ## - High: NAPs with stronger powers, war declarations against vulnerable enemies
  ## - Medium: Alliance proposals, pact renewals
  ## - Low: Opportunistic diplomacy, relationship maintenance
  ## - Deferred: Luxury diplomacy (non-strategic pacts)
  ##
  ## NOTE: Diplomacy costs 0 PP, so no budget feedback needed
  ## Basileus provides feedback on priority conflicts only

  result.requirements = @[]
  result.generatedTurn = filtered.turn
  result.iteration = 0

  # Calculate dynamic prestige thresholds based on game state
  # Replaces hardcoded values (500, 200, 300) with adaptive thresholds
  let thresholds = calculateDynamicThresholds(filtered)

  let p = controller.personality
  let house = filtered.ownHouse
  let myPrestige = house.prestige

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Protostrator: Generating diplomatic requirements " &
          &"(prestige={myPrestige}, diplomacyValue={p.diplomacyValue:.2f})")

  # === Analyze other houses for diplomatic opportunities ===
  type DiplomaticTarget = object
    houseId: HouseId
    prestige: int
    prestigeGap: int  # positive = they're stronger
    currentRelation: dip_types.DiplomaticState
    recommendedAction: DiplomaticRequirementType
    priority: RequirementPriority
    reason: string

  var diplomaticTargets: seq[DiplomaticTarget] = @[]

  for houseId, prestige in filtered.housePrestige:
    if houseId == controller.houseId:
      continue

    let prestigeGap = prestige - myPrestige
    let relation = dip_types.getDiplomaticState(house.diplomaticRelations, houseId)

    var target = DiplomaticTarget(
      houseId: houseId,
      prestige: prestige,
      prestigeGap: prestigeGap,
      currentRelation: relation,
      recommendedAction: DiplomaticRequirementType.MaintainRelations,
      priority: RequirementPriority.Low,
      reason: ""
    )

    # === DECISION LOGIC: Determine recommended action ===

    case relation
    of dip_types.DiplomaticState.Neutral:
      # No current pact - evaluate strategic position
      # Phase E: Check diplomatic intelligence for potential allies/threats
      var isPotentialAlly = false
      var isPotentialThreat = false
      var observedHostilityLevel = HostilityLevel.Unknown

      if intelSnapshot.diplomatic.potentialAllies.contains(houseId):
        isPotentialAlly = true
      if intelSnapshot.diplomatic.potentialThreats.contains(houseId):
        isPotentialThreat = true
      if intelSnapshot.diplomatic.observedHostility.hasKey(houseId):
        observedHostilityLevel = intelSnapshot.diplomatic.observedHostility[houseId]

      # Intelligence-driven threat prioritization
      if isPotentialThreat or observedHostilityLevel == HostilityLevel.Aggressive:
        # Hostile activity detected - prioritize NAP if they're stronger
        if prestigeGap > 0:
          target.recommendedAction = DiplomaticRequirementType.ProposePact
          target.priority = RequirementPriority.Critical
          target.reason = &"NAP with aggressive power {houseId} (hostile activity detected, prestige gap: {prestigeGap})"
        # Otherwise consider for war below
      elif prestigeGap > thresholds.overwhelming:
        # Much stronger enemy - seek NAP to avoid conflict
        target.recommendedAction = DiplomaticRequirementType.ProposePact
        target.priority = RequirementPriority.Critical
        target.reason = &"NAP with overwhelming power {houseId} (prestige gap: {prestigeGap})"
      elif prestigeGap > thresholds.moderate:
        # Moderately stronger - NAP if diplomatic-focused OR intelligence suggests alliance potential
        if p.diplomacyValue > 0.6 or isPotentialAlly:
          target.recommendedAction = DiplomaticRequirementType.ProposePact
          target.priority = RequirementPriority.High
          let allyNote = if isPotentialAlly: " (potential ally)" else: ""
          target.reason = &"NAP with stronger power {houseId} (prestige gap: {prestigeGap}){allyNote}"
      else:
        # Multi-factor war evaluation
        # Check if they have vulnerable colonies
        var hasVulnerableColonies = false
        for targetSystem in intelSnapshot.highValueTargets:
          for (systemId, owner) in intelSnapshot.knownEnemyColonies:
            if owner == houseId and systemId == targetSystem:
              hasVulnerableColonies = true
              break

        # Count our colonies and target colonies
        let ownColonies = filtered.ownColonies.len
        var targetColonies = 0
        for (systemId, owner) in intelSnapshot.knownEnemyColonies:
          if owner == houseId:
            targetColonies += 1

        # Calculate shared borders and allies
        let sharedBorders = intelligence.countSharedBorders(filtered, intelSnapshot, controller.houseId, houseId)
        # In the 3-state system, there are no formal allies to count for target house.
        # Assume 0 allies, as this contributes to "target isolated" for war evaluation.
        let targetAllies = 0

        # Get current game act

        # Calculate total colonized systems from public leaderboard
        let totalSystems = filtered.starMap.systems.len
        var totalColonized = 0
        for houseId, colonyCount in filtered.houseColonies:
          totalColonized += colonyCount

        # Use colonization-based Act determination (90% threshold for Act 2 transition)
        let currentAct = ai_types.getCurrentGameAct(totalSystems, totalColonized,
                                                    filtered.turn)

        # Evaluate war readiness with multi-factor system
        let warEval = evaluateWarReadiness(
          myPrestige, prestige,
          ownColonies, targetColonies,
          hasVulnerableColonies,
          sharedBorders, targetAllies,
          currentAct, p
        )

        if warEval.shouldDeclare:
          target.recommendedAction = DiplomaticRequirementType.DeclareWar
          target.priority = RequirementPriority.High
          target.reason = &"War against {houseId}: {warEval.reason} (score: {warEval.score:.1f})"


    of dip_types.DiplomaticState.Hostile:
      # Tensions escalated from deep space combat
      # Decide: escalate to war or de-escalate to neutral
      if prestigeGap > 400:
        # Much stronger enemy - seek de-escalation urgently
        target.recommendedAction = DiplomaticRequirementType.SeekPeace
        target.priority = RequirementPriority.High
        target.reason = &"De-escalate tensions with stronger {houseId} (gap: {prestigeGap})"
      elif prestigeGap > 200 and p.aggression < 0.5:
        # Moderately stronger, non-aggressive - seek de-escalation
        target.recommendedAction = DiplomaticRequirementType.SeekPeace
        target.priority = RequirementPriority.Medium
        target.reason = &"De-escalate with {houseId} to avoid full war"
      elif prestigeGap < -200 and p.aggression > 0.6:
        # Much weaker enemy, aggressive personality - escalate to war
        target.recommendedAction = DiplomaticRequirementType.DeclareWar
        target.priority = RequirementPriority.High
        target.reason = &"Escalate hostilities to war with weaker {houseId}"
      else:
        # Maintain hostile state (continue deep space skirmishes)
        target.recommendedAction = DiplomaticRequirementType.MaintainRelations
        target.priority = RequirementPriority.Low
        target.reason = &"Continue hostile tensions with {houseId}"

    of dip_types.DiplomaticState.Enemy:
      # At war - evaluate if peace is needed
      if prestigeGap > 600:
        # Overwhelming enemy - seek peace urgently
        target.recommendedAction = DiplomaticRequirementType.SeekPeace
        target.priority = RequirementPriority.Critical
        target.reason = &"Emergency peace with overwhelming {houseId} (gap: {prestigeGap})"
      elif prestigeGap > 300 and p.aggression < 0.4:
        # Stronger enemy - seek peace if not aggressive
        target.recommendedAction = DiplomaticRequirementType.SeekPeace
        target.priority = RequirementPriority.High
        target.reason = &"Peace with stronger {houseId} (gap: {prestigeGap})"
      else:
        # Continue war (either winning or aggressive personality)
        target.recommendedAction = DiplomaticRequirementType.MaintainRelations
        target.priority = RequirementPriority.Low
        target.reason = &"Continue war with {houseId}"

    # Add target if action is needed
    if target.recommendedAction != DiplomaticRequirementType.MaintainRelations or
       target.priority >= RequirementPriority.High:
      diplomaticTargets.add(target)

  # === GENERATE REQUIREMENTS ===
  for target in diplomaticTargets:
    # Determine proposal type for pact proposals
    var proposalType: Option[dip_proposals.ProposalType] = none(dip_proposals.ProposalType)
    if target.recommendedAction == DiplomaticRequirementType.ProposePact:
      # AllyPact is no longer implemented. A ProposePact requirement
      # might map to a SetNeutral diplomatic action directly, or
      # to a different specific proposal type not yet defined.
      proposalType = none(dip_proposals.ProposalType) # Set to none for now to resolve compilation.

    result.requirements.add(DiplomaticRequirement(
      requirementType: target.recommendedAction,
      priority: target.priority,
      targetHouse: target.houseId,
      proposalType: proposalType,
      estimatedCost: 0,  # Diplomacy costs 0 PP
      reason: target.reason,
      expectedBenefit: case target.recommendedAction
        of DiplomaticRequirementType.ProposePact:
          "Secure borders and avoid costly conflicts"
        of DiplomaticRequirementType.DeclareWar:
          "Expand territory and prestige through conquest"
        of DiplomaticRequirementType.SeekPeace:
          "End costly war and rebuild strength"
        else:
          "Maintain diplomatic stability"
    ))

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Protostrator: Generated {result.requirements.len} diplomatic requirements")

  return result

proc reprioritizeDiplomaticRequirements*(
  originalRequirements: DiplomaticRequirements,
  basileusFeedback: string  # Future: Basileus priority conflict feedback
): DiplomaticRequirements =
  ## Reprioritize diplomatic requirements based on Basileus feedback
  ##
  ## NOTE: Diplomacy costs 0 PP, so no Treasurer feedback needed
  ## This function handles priority conflicts from Basileus (future implementation)

  result = DiplomaticRequirements(
    requirements: originalRequirements.requirements,
    generatedTurn: originalRequirements.generatedTurn,
    iteration: originalRequirements.iteration + 1
  )

  # For now, no reprioritization needed (diplomacy costs 0 PP)
  # Future: Handle Basileus feedback on priority conflicts
  # e.g., "War declaration conflicts with NAP proposal to ally"

  logInfo(LogCategory.lcAI,
          &"Protostrator: Diplomatic requirements unchanged (iteration {result.iteration})")

  return result
