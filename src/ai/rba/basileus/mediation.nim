## Basileus Mediation Module
##
## Byzantine Basileus - Multi-Advisor Priority Mediation
##
## Coordinates competing requirements from all advisors using personality weights
## and urgency scoring to create a unified priority queue for budget allocation

import std/[tables, algorithm, strformat, options, strutils]
import ../../../common/types/core
import ../controller_types
import ../../common/types as ai_types
import ../../../engine/logger
import ./personality

# Weighted requirement for unified priority queue
type
  AdvisorRequirement* = object
    ## Generic wrapper for any advisor requirement
    advisor*: AdvisorType
    priority*: RequirementPriority
    requirementType*: string  # "BuildRequirement", "ResearchRequirement", etc.
    estimatedCost*: int
    reason*: string
    # Original requirement data (for execution phase)
    buildReq*: Option[BuildRequirement]
    researchReq*: Option[ResearchRequirement]
    espionageReq*: Option[EspionageRequirement]
    economicReq*: Option[EconomicRequirement]
    diplomaticReq*: Option[DiplomaticRequirement]

  WeightedRequirement* = object
    ## Requirement with calculated weighted score for priority queue
    requirement*: AdvisorRequirement
    urgencyScore*: float
    advisorWeight*: float
    weightedScore*: float  # urgencyScore × advisorWeight × typeModifier

  MediatedAllocation* = object
    ## Result of mediation - budget per advisor + unfulfilled requirements
    domestikosBudget*: int
    logotheteBudget*: int
    drungariusBudget*: int
    eparchBudget*: int
    protostratorBudget*: int  # Always 0 (diplomacy costs 0 PP)
    fulfilledRequirements*: seq[WeightedRequirement]
    unfulfilledRequirements*: seq[WeightedRequirement]
    totalBudgetAllocated*: int

proc calculateUrgencyScore*(
  priority: RequirementPriority,
  reqType: string,
  isAtWar: bool = false  # NEW: War-time offensive boost
): float =
  ## Calculate base urgency score from requirement priority
  ## Type modifiers prevent personality from overriding strategic needs
  ## War-time offensive boost for invasion-related requirements

  let basePriority = case priority
    of RequirementPriority.Critical: 1000.0
    of RequirementPriority.High: 100.0
    of RequirementPriority.Medium: 10.0
    of RequirementPriority.Low: 1.0
    of RequirementPriority.Deferred: 0.1

  # Type modifiers (ThreatResponse and DefenseGap get extra urgency)
  var typeModifier = 1.0

  if reqType.contains("ThreatResponse"):
    typeModifier = 1.5  # +50% urgency for threat responses
  elif reqType.contains("DefenseGap"):
    typeModifier = 1.2  # +20% urgency for defense gaps

  # War-time offensive boost (user preference: aggressive war prosecution)
  if isAtWar:
    if reqType.contains("Offensive") or reqType.contains("Invasion") or
       reqType.contains("Transport") or reqType.contains("Carrier"):
      typeModifier *= 1.3  # +30% urgency for offensive capabilities during war
    elif reqType.contains("Military") or reqType.contains("Fleet"):
      typeModifier *= 1.15  # +15% urgency for general military during war

  return basePriority * typeModifier

proc convertToAdvisorRequirements*(
  domestikosReqs: BuildRequirements,
  logotheteReqs: ResearchRequirements,
  drungariusReqs: EspionageRequirements,
  eparchReqs: EconomicRequirements,
  protostratorReqs: DiplomaticRequirements
): seq[AdvisorRequirement] =
  ## Convert all advisor-specific requirements to generic AdvisorRequirement format

  result = @[]

  # Domestikos (military builds)
  for req in domestikosReqs.requirements:
    result.add(AdvisorRequirement(
      advisor: AdvisorType.Domestikos,
      priority: req.priority,
      requirementType: $req.requirementType,
      estimatedCost: req.estimatedCost,
      reason: req.reason,
      buildReq: some(req),
      researchReq: none(ResearchRequirement),
      espionageReq: none(EspionageRequirement),
      economicReq: none(EconomicRequirement),
      diplomaticReq: none(DiplomaticRequirement)
    ))

  # Logothete (research)
  for req in logotheteReqs.requirements:
    result.add(AdvisorRequirement(
      advisor: AdvisorType.Logothete,
      priority: req.priority,
      requirementType: "ResearchRequirement",
      estimatedCost: req.estimatedCost,
      reason: req.reason,
      buildReq: none(BuildRequirement),
      researchReq: some(req),
      espionageReq: none(EspionageRequirement),
      economicReq: none(EconomicRequirement),
      diplomaticReq: none(DiplomaticRequirement)
    ))

  # Drungarius (espionage)
  for req in drungariusReqs.requirements:
    result.add(AdvisorRequirement(
      advisor: AdvisorType.Drungarius,
      priority: req.priority,
      requirementType: $req.requirementType,
      estimatedCost: req.estimatedCost,
      reason: req.reason,
      buildReq: none(BuildRequirement),
      researchReq: none(ResearchRequirement),
      espionageReq: some(req),
      economicReq: none(EconomicRequirement),
      diplomaticReq: none(DiplomaticRequirement)
    ))

  # Eparch (economic/infrastructure)
  for req in eparchReqs.requirements:
    result.add(AdvisorRequirement(
      advisor: AdvisorType.Eparch,
      priority: req.priority,
      requirementType: $req.requirementType,
      estimatedCost: req.estimatedCost,
      reason: req.reason,
      buildReq: none(BuildRequirement),
      researchReq: none(ResearchRequirement),
      espionageReq: none(EspionageRequirement),
      economicReq: some(req),
      diplomaticReq: none(DiplomaticRequirement)
    ))

  # Protostrator (diplomacy - costs 0 PP, tracked for priority but not budget)
  for req in protostratorReqs.requirements:
    result.add(AdvisorRequirement(
      advisor: AdvisorType.Protostrator,
      priority: req.priority,
      requirementType: $req.requirementType,
      estimatedCost: 0,  # Diplomacy costs 0 PP
      reason: req.reason,
      buildReq: none(BuildRequirement),
      researchReq: none(ResearchRequirement),
      espionageReq: none(EspionageRequirement),
      economicReq: none(EconomicRequirement),
      diplomaticReq: some(req)
    ))

proc mediateRequirements*(
  domestikosReqs: BuildRequirements,
  logotheteReqs: ResearchRequirements,
  drungariusReqs: EspionageRequirements,
  eparchReqs: EconomicRequirements,
  protostratorReqs: DiplomaticRequirements,
  personality: AIPersonality,
  currentAct: ai_types.GameAct,
  availableBudget: int,
  houseId: HouseId,
  isAtWar: bool = false  # NEW: War status parameter
): MediatedAllocation =
  ## Mediate competing requirements from all advisors using personality weights
  ## Returns budget allocation per advisor + fulfilled/unfulfilled requirements

  logInfo(LogCategory.lcAI,
          &"{houseId} Basileus: Mediating requirements (budget={availableBudget}PP, act={currentAct}, atWar={isAtWar})")

  # 1. Calculate advisor weights (personality-driven + war-aware)
  let weights = calculateAdvisorWeights(personality, currentAct, isAtWar)

  logInfo(LogCategory.lcAI,
          &"{houseId} Basileus: Advisor weights - " &
          &"Domestikos={weights[AdvisorType.Domestikos]:.2f}, " &
          &"Logothete={weights[AdvisorType.Logothete]:.2f}, " &
          &"Drungarius={weights[AdvisorType.Drungarius]:.2f}, " &
          &"Eparch={weights[AdvisorType.Eparch]:.2f}, " &
          &"Protostrator={weights[AdvisorType.Protostrator]:.2f}")

  # 2. Convert all requirements to generic format
  let allRequirements = convertToAdvisorRequirements(
    domestikosReqs, logotheteReqs, drungariusReqs, eparchReqs, protostratorReqs
  )

  logInfo(LogCategory.lcAI,
          &"{houseId} Basileus: Processing {allRequirements.len} total requirements")

  # 3. Create weighted priority queue with war-aware urgency
  var weightedReqs: seq[WeightedRequirement] = @[]

  for req in allRequirements:
    let urgency = calculateUrgencyScore(req.priority, req.requirementType, isAtWar)
    let advisorWeight = weights[req.advisor]
    let weightedScore = urgency * advisorWeight

    weightedReqs.add(WeightedRequirement(
      requirement: req,
      urgencyScore: urgency,
      advisorWeight: advisorWeight,
      weightedScore: weightedScore
    ))

  # 4. Sort by weighted score (highest first)
  weightedReqs.sort(proc(a, b: WeightedRequirement): int =
    cmp(b.weightedScore, a.weightedScore)
  )

  # 5. Allocate budget in priority order
  result = MediatedAllocation(
    domestikosBudget: 0,
    logotheteBudget: 0,
    drungariusBudget: 0,
    eparchBudget: 0,
    protostratorBudget: 0,
    fulfilledRequirements: @[],
    unfulfilledRequirements: @[],
    totalBudgetAllocated: 0
  )

  var remainingBudget = availableBudget

  for weightedReq in weightedReqs:
    let req = weightedReq.requirement

    # Diplomacy is always "fulfilled" (costs 0 PP)
    if req.advisor == AdvisorType.Protostrator:
      result.fulfilledRequirements.add(weightedReq)
      continue

    # Check if we can afford this requirement
    if req.estimatedCost <= remainingBudget:
      # Fulfill requirement - allocate budget to advisor
      case req.advisor
      of AdvisorType.Domestikos:
        result.domestikosBudget += req.estimatedCost
      of AdvisorType.Logothete:
        result.logotheteBudget += req.estimatedCost
      of AdvisorType.Drungarius:
        result.drungariusBudget += req.estimatedCost
      of AdvisorType.Eparch:
        result.eparchBudget += req.estimatedCost
      of AdvisorType.Protostrator:
        discard  # Already handled above
      of AdvisorType.Treasurer:
        discard  # Treasurer doesn't have requirements

      remainingBudget -= req.estimatedCost
      result.totalBudgetAllocated += req.estimatedCost
      result.fulfilledRequirements.add(weightedReq)
    else:
      # Cannot afford - add to unfulfilled list
      result.unfulfilledRequirements.add(weightedReq)

  # 6. Enforce budget floors/ceilings (user preference: aggressive 45%/55%)
  # War-time: 45% minimum for military (Domestikos + Drungarius)
  # Peace-time: 55% maximum for military (prevent excessive militarization)
  let militaryBudget = result.domestikosBudget + result.drungariusBudget
  let militaryPercent = if availableBudget > 0:
    float(militaryBudget) / float(availableBudget)
  else:
    0.0

  if isAtWar:
    # War-time: Enforce 45% minimum for military
    let minMilitaryBudget = int(float(availableBudget) * 0.45)
    if militaryBudget < minMilitaryBudget:
      let shortfall = minMilitaryBudget - militaryBudget

      logInfo(LogCategory.lcAI,
              &"{houseId} Basileus: WAR - Military budget ({militaryBudget}PP = {militaryPercent*100:.1f}%) " &
              &"below 45% floor, reallocating {shortfall}PP from civilian advisors")

      # Reallocate from civilian advisors (Logothete, Eparch) proportionally
      let civilianBudget = result.logotheteBudget + result.eparchBudget
      if civilianBudget > 0:
        let logotheteShare = float(result.logotheteBudget) / float(civilianBudget)
        let eparchShare = float(result.eparchBudget) / float(civilianBudget)

        let logotheteReduction = min(result.logotheteBudget, int(float(shortfall) * logotheteShare))
        let eparchReduction = min(result.eparchBudget, int(float(shortfall) * eparchShare))

        result.logotheteBudget -= logotheteReduction
        result.eparchBudget -= eparchReduction
        result.domestikosBudget += (logotheteReduction + eparchReduction)
  else:
    # Peace-time: Enforce 55% maximum for military
    let maxMilitaryBudget = int(float(availableBudget) * 0.55)
    if militaryBudget > maxMilitaryBudget:
      let excess = militaryBudget - maxMilitaryBudget

      logInfo(LogCategory.lcAI,
              &"{houseId} Basileus: PEACE - Military budget ({militaryBudget}PP = {militaryPercent*100:.1f}%) " &
              &"exceeds 55% ceiling, reallocating {excess}PP to civilian advisors")

      # Reallocate excess to civilian advisors (prioritize tech in peace)
      let techShare = 0.6  # 60% to Logothete
      let economicShare = 0.4  # 40% to Eparch

      let domestikosReduction = min(result.domestikosBudget, int(float(excess) * 0.7))  # 70% from Domestikos
      let drungariusReduction = min(result.drungariusBudget, int(float(excess) * 0.3))  # 30% from Drungarius

      let totalReduction = domestikosReduction + drungariusReduction
      result.domestikosBudget -= domestikosReduction
      result.drungariusBudget -= drungariusReduction
      result.logotheteBudget += int(float(totalReduction) * techShare)
      result.eparchBudget += int(float(totalReduction) * economicShare)

  # ACT-AWARE MINIMUM BUDGET FLOORS (Classic 4X budget allocation)
  # Ensures baseline budget allocation regardless of personality weights
  # Layer 3 of the three-layer budget allocation system
  let (minConstructionPercent, minResearchPercent) = case currentAct
    of ai_types.GameAct.Act1_LandGrab:
      (0.45, 0.15)  # 45% construction, 15% research (expansion focus)
    of ai_types.GameAct.Act2_RisingTensions:
      (0.35, 0.20)  # 35% construction, 20% research (balanced growth)
    of ai_types.GameAct.Act3_TotalWar:
      (0.50, 0.15)  # 50% construction, 15% research (war economy)
    of ai_types.GameAct.Act4_Endgame:
      (0.60, 0.10)  # 60% construction, 10% research (total war)

  # Enforce construction minimum (reallocate from Logothete, Eparch)
  let minConstructionBudget = int(float(availableBudget) * minConstructionPercent)
  if result.domestikosBudget < minConstructionBudget:
    let deficit = minConstructionBudget - result.domestikosBudget
    # Reallocate 60% from Logothete, 40% from Eparch
    let fromLogothete = min(result.logotheteBudget, int(float(deficit) * 0.6))
    let fromEparch = min(result.eparchBudget, deficit - fromLogothete)
    let totalReallocated = fromLogothete + fromEparch

    result.domestikosBudget += totalReallocated
    result.logotheteBudget -= fromLogothete
    result.eparchBudget -= fromEparch

    logInfo(LogCategory.lcAI,
            &"{houseId} Basileus: Act {currentAct} construction floor ({int(minConstructionPercent*100)}%) " &
            &"enforced - reallocated {totalReallocated}PP to Domestikos (needed {deficit}PP)")

  # Enforce research minimum (reallocate from Eparch)
  let minResearchBudget = int(float(availableBudget) * minResearchPercent)
  if result.logotheteBudget < minResearchBudget:
    let deficit = minResearchBudget - result.logotheteBudget
    let fromEparch = min(result.eparchBudget, deficit)

    result.logotheteBudget += fromEparch
    result.eparchBudget -= fromEparch

    if fromEparch > 0:
      logInfo(LogCategory.lcAI,
              &"{houseId} Basileus: Act {currentAct} research floor ({int(minResearchPercent*100)}%) " &
              &"enforced - reallocated {fromEparch}PP to Logothete (needed {deficit}PP)")

  # Summary logging
  logInfo(LogCategory.lcAI,
          &"{houseId} Basileus: Mediation complete - " &
          &"allocated {result.totalBudgetAllocated}/{availableBudget}PP, " &
          &"fulfilled {result.fulfilledRequirements.len}/{weightedReqs.len} requirements")

  logInfo(LogCategory.lcAI,
          &"{houseId} Basileus: Per-advisor budgets - " &
          &"Domestikos={result.domestikosBudget}PP, " &
          &"Logothete={result.logotheteBudget}PP, " &
          &"Drungarius={result.drungariusBudget}PP, " &
          &"Eparch={result.eparchBudget}PP")

  if result.unfulfilledRequirements.len > 0:
    logInfo(LogCategory.lcAI,
            &"{houseId} Basileus: {result.unfulfilledRequirements.len} requirements unfulfilled - " &
            &"feedback loop will attempt reprioritization")

  return result
