import std/[tables, algorithm, options, sequtils]
import ../../../common/types/core # For HouseId, SystemId, FleetId (fixed path)
import ../../../engine/[gamestate, fog_of_war, logger]
import ../controller_types # For AdvisorType, RequirementType, BuildRequirement, ResearchRequirement, etc.
import ../config # For globalRBAConfig
# GOAP not yet integrated - commented out
# import ../goap/core/types # For DomainType, GOAPlan (needed for GOAP integration)
import ../../common/types # For AIPersonality

type
  AdvisorRequirement* = object
    ## A generic requirement from an advisor, with priority and estimated cost.
    reqType*: RequirementType      # e.g., BuildUnit, ResearchTech
    advisor*: AdvisorType          # e.g., Domestikos, Logothete
    priority*: RequirementPriority # Critical, High, Medium, Low, Deferred
    cost*: int                     # Estimated PP cost
    targetId*: Option[SystemId]    # System/Colony related to the requirement (optional)
    description*: string           # Human-readable description
    # Additional fields to store the original requirement for later execution
    case advisor*: AdvisorType
    of AdvisorType.Domestikos:
      buildReq*: Option[BuildRequirement]
    of AdvisorType.Logothete:
      researchReq*: Option[ResearchRequirement]
    of AdvisorType.Drungarius:
      espionageReq*: Option[EspionageRequirement]
    of AdvisorType.Eparch:
      economicReq*: Option[EconomicRequirement]
    of AdvisorType.Protostrator:
      diplomaticReq*: Option[DiplomaticRequirement]
    of AdvisorType.Basileus:
      discard # Basileus doesn't directly create requirements for mediation

  WeightedRequirement* = object
    ## An AdvisorRequirement with an added calculated weight for allocation.
    requirement*: AdvisorRequirement
    weight*: float

  MultiAdvisorAllocation* = object
    ## The final budget allocation result after mediation.
    budgets*: Table[AdvisorType, int] # Allocated budget for each advisor
    reservedBudget*: int              # Budget reserved for future turns by GOAP (for later phases)
    totalAllocated*: int              # Total PP allocated this turn
    remainingTreasury*: int           # Treasury left after allocation
    unfulfilledRequirements*: seq[AdvisorRequirement] # Requirements that could not be met

proc calculateUrgencyScore*(req: AdvisorRequirement, personality: AIPersonality): float =
  ## Calculates an urgency score for a requirement based on its priority and AI personality.
  ## This is a simplified placeholder and can be made more sophisticated.
  var score = 0.0
  case req.priority
  of RequirementPriority.Critical: score = 10.0
  of RequirementPriority.High:     score = 5.0
  of RequirementPriority.Medium:   score = 2.0
  of RequirementPriority.Low:      score = 1.0
  of RequirementPriority.Deferred: score = 0.5

  # Apply personality modifiers (simplified)
  case req.advisor
  of AdvisorType.Domestikos: score *= personality.aggression * (1.0 - personality.riskTolerance) * 1.5
  of AdvisorType.Logothete: score *= personality.techPriority * 1.2
  of AdvisorType.Eparch: score *= personality.economicFocus * personality.expansionDrive * 1.2
  of AdvisorType.Drungarius: score *= (1.0 - personality.riskTolerance) * 1.0
  of AdvisorType.Protostrator: score *= personality.diplomacyValue * 1.0
  of AdvisorType.Basileus: discard # Basileus itself doesn't have specific personality weights for requirements

  # Ensure minimum score
  result = max(0.1, score)

proc convertToAdvisorRequirements*(
  buildReqs: BuildRequirements,
  researchReqs: ResearchRequirements,
  espionageReqs: EspionageRequirements,
  economicReqs: EconomicRequirements,
  diplomaticReqs: DiplomaticRequirements
): Table[AdvisorType, seq[AdvisorRequirement]] =
  ## Consolidates all specific advisor requirements into a single table of generic AdvisorRequirements.
  result = initTable[AdvisorType, seq[AdvisorRequirement]]()

  # Domestikos
  for req in buildReqs.reqs:
    result.add(AdvisorType.Domestikos, AdvisorRequirement(
      reqType: req.reqType, advisor: AdvisorType.Domestikos, priority: req.priority,
      cost: req.cost, targetId: req.targetId, description: req.description,
      buildReq: some(req)
    ))

  # Logothete
  for req in researchReqs.reqs:
    result.add(AdvisorType.Logothete, AdvisorRequirement(
      reqType: req.reqType, advisor: AdvisorType.Logothete, priority: req.priority,
      cost: req.cost, description: req.description,
      researchReq: some(req)
    ))

  # Drungarius
  for req in espionageReqs.reqs:
    result.add(AdvisorType.Drungarius, AdvisorRequirement(
      reqType: req.reqType, advisor: AdvisorType.Drungarius, priority: req.priority,
      cost: req.cost, targetId: req.targetId, description: req.description,
      espionageReq: some(req)
    ))

  # Eparch
  for req in economicReqs.reqs:
    result.add(AdvisorType.Eparch, AdvisorRequirement(
      reqType: req.reqType, advisor: AdvisorType.Eparch, priority: req.priority,
      cost: req.cost, targetId: req.targetId, description: req.description,
      economicReq: some(req)
    ))

  # Protostrator
  for req in diplomaticReqs.reqs:
    result.add(AdvisorType.Protostrator, AdvisorRequirement(
      reqType: req.reqType, advisor: AdvisorType.Protostrator, priority: req.priority,
      cost: req.cost, targetId: req.targetId, description: req.description,
      diplomaticReq: some(req)
    ))

proc mediateRequirements*(
  controller: AIController,
  filtered: FilteredGameState,
  requirements: Table[AdvisorType, seq[AdvisorRequirement]]
): Table[AdvisorType, seq[AdvisorRequirement]] =
  ## Performs mediation and prioritization of requirements across advisors.
  ## This is a placeholder for a more complex RBA mediation system.
  ## For now, it simply returns the original requirements.
  ## In future, this could apply strategic adjustments, combine similar requests, etc.
  result = requirements

proc allocateBudgetMultiAdvisor*(
  controller: AIController,
  filtered: FilteredGameState,
  currentTreasury: int,
  requirements: Table[AdvisorType, seq[AdvisorRequirement]],
  goapBudgetEstimates: Table[string, int] # GOAP budget guidance from Phase 1.5
): MultiAdvisorAllocation =
  ## Allocates the available budget across multiple advisors, incorporating GOAP guidance.
  result.budgets = initTable[AdvisorType, int]()
  for advType in low(AdvisorType)..high(AdvisorType):
    result.budgets[advType] = 0
  result.reservedBudget = 0
  result.totalAllocated = 0
  result.remainingTreasury = currentTreasury
  result.unfulfilledRequirements = @[]

  var weightedReqs: seq[WeightedRequirement] = @[]
  for advisorType, reqList in requirements:
    for req in reqList:
      let baseWeight = calculateUrgencyScore(req, controller.personality)
      weightedReqs.add(WeightedRequirement(requirement: req, weight: baseWeight))

  # Apply GOAP budget guidance as a priority boost
  # This makes requirements aligned with active GOAP plans more likely to be funded.
  for i in 0 ..< weightedReqs.len:
    let req = weightedReqs[i].requirement
    let domainName = case req.advisor
      of AdvisorType.Domestikos: "Build" # Build is mainly for fleets/military and facilities
      of AdvisorType.Logothete: "Research"
      of AdvisorType.Drungarius: "Espionage"
      of AdvisorType.Eparch: "Economic"
      of AdvisorType.Protostrator: "Diplomatic"
      of AdvisorType.Basileus: "" # Basileus itself doesn't have a domain for budget allocation

    if domainName != "" and goapBudgetEstimates.hasKey(domainName):
      let goapAlloc = goapBudgetEstimates[domainName]
      # Boost requirements whose domain is targeted by GOAP with a percentage of the GOAP budget estimate
      # This is a heuristic. A more refined approach would link specific GOAP actions to specific RBA requirements.
      # For now, a flat boost based on the domain's GOAP estimate.
      let budgetGuidanceBoostFactor = controller.goapConfig.budgetGuidanceBoostFactor

      let boostAmount = float(goapAlloc) * budgetGuidanceBoostFactor
      weightedReqs[i].weight += boostAmount
      logDebug(LogCategory.lcAI, &"GOAP Budget Guidance: Boosting {req.description} (Advisor {req.advisor}) by {boostAmount:.2f} due to {domainName} GOAP estimate.")

  # Sort requirements by weight (highest first)
  weightedReqs.sort(proc(a, b: WeightedRequirement): int = cmp(b.weight, a.weight))

  var currentBudget = currentTreasury

  # Allocate funds
  for wr in weightedReqs:
    let reqCost = wr.requirement.cost
    if reqCost <= 0:
      logWarn(LogCategory.lcAI, &"Requirement with non-positive cost: {wr.requirement.description}. Skipping allocation.")
      result.unfulfilledRequirements.add(wr.requirement) # Still track, even if cost is zero
      continue

    if currentBudget >= reqCost:
      # Fully fund the requirement
      result.budgets[wr.requirement.advisor] += reqCost
      currentBudget -= reqCost
      result.totalAllocated += reqCost
    else:
      # Partially fund or leave unfulfilled
      # For now, we only fund fully. If partial funding is allowed, logic needs to be added.
      # Any critical/high priority requirements might get priority here with partial funding.
      result.unfulfilledRequirements.add(wr.requirement)
      logDebug(LogCategory.lcAI, &"Unfulfilled requirement: {wr.requirement.description} (cost: {reqCost}, remaining budget: {currentBudget})")

  result.remainingTreasury = currentBudget
  logInfo(LogCategory.lcAI, &"Budget Mediation: Total {result.totalAllocated} PP allocated, {result.remainingTreasury} PP remaining. {result.unfulfilledRequirements.len} requirements unfulfilled.")

  return result
import std/[tables, algorithm, options, sequtils]
import ../../../common/types/core # For HouseId, SystemId, FleetId (fixed path)
import ../../../engine/[gamestate, fog_of_war, logger]
import ../controller_types # For AdvisorType, RequirementType, BuildRequirement, ResearchRequirement, etc.
import ../config # For globalRBAConfig
# GOAP not yet integrated - commented out
# import ../goap/core/types # For DomainType, GOAPlan (needed for GOAP integration)
import ../../common/types # For AIPersonality

type
  AdvisorRequirement* = object
    ## A generic requirement from an advisor, with priority and estimated cost.
    reqType*: RequirementType      # e.g., BuildUnit, ResearchTech
    advisor*: AdvisorType          # e.g., Domestikos, Logothete
    priority*: RequirementPriority # Critical, High, Medium, Low, Deferred
    cost*: int                     # Estimated PP cost
    targetId*: Option[SystemId]    # System/Colony related to the requirement (optional)
    description*: string           # Human-readable description
    # Additional fields to store the original requirement for later execution
    case advisor*: AdvisorType
    of AdvisorType.Domestikos:
      buildReq*: Option[BuildRequirement]
    of AdvisorType.Logothete:
      researchReq*: Option[ResearchRequirement]
    of AdvisorType.Drungarius:
      espionageReq*: Option[EspionageRequirement]
    of AdvisorType.Eparch:
      economicReq*: Option[EconomicRequirement]
    of AdvisorType.Protostrator:
      diplomaticReq*: Option[DiplomaticRequirement]
    of AdvisorType.Basileus:
      discard # Basileus doesn't directly create requirements for mediation

  WeightedRequirement* = object
    ## An AdvisorRequirement with an added calculated weight for allocation.
    requirement*: AdvisorRequirement
    weight*: float

  MultiAdvisorAllocation* = object
    ## The final budget allocation result after mediation.
    budgets*: Table[AdvisorType, int] # Allocated budget for each advisor
    reservedBudget*: int              # Budget reserved for future turns by GOAP (for later phases)
    totalAllocated*: int              # Total PP allocated this turn
    remainingTreasury*: int           # Treasury left after allocation
    unfulfilledRequirements*: seq[AdvisorRequirement] # Requirements that could not be met

proc calculateUrgencyScore*(req: AdvisorRequirement, personality: AIPersonality): float =
  ## Calculates an urgency score for a requirement based on its priority and AI personality.
  ## This is a simplified placeholder and can be made more sophisticated.
  var score = 0.0
  case req.priority
  of RequirementPriority.Critical: score = 10.0
  of RequirementPriority.High:     score = 5.0
  of RequirementPriority.Medium:   score = 2.0
  of RequirementPriority.Low:      score = 1.0
  of RequirementPriority.Deferred: score = 0.5

  # Apply personality modifiers (simplified)
  case req.advisor
  of AdvisorType.Domestikos: score *= personality.aggression * (1.0 - personality.riskTolerance) * 1.5
  of AdvisorType.Logothete: score *= personality.techPriority * 1.2
  of AdvisorType.Eparch: score *= personality.economicFocus * personality.expansionDrive * 1.2
  of AdvisorType.Drungarius: score *= (1.0 - personality.riskTolerance) * 1.0
  of AdvisorType.Protostrator: score *= personality.diplomacyValue * 1.0
  of AdvisorType.Basileus: discard # Basileus itself doesn't have specific personality weights for requirements

  # Ensure minimum score
  result = max(0.1, score)

proc convertToAdvisorRequirements*(
  buildReqs: BuildRequirements,
  researchReqs: ResearchRequirements,
  espionageReqs: EspionageRequirements,
  economicReqs: EconomicRequirements,
  diplomaticReqs: DiplomaticRequirements
): Table[AdvisorType, seq[AdvisorRequirement]] =
  ## Consolidates all specific advisor requirements into a single table of generic AdvisorRequirements.
  result = initTable[AdvisorType, seq[AdvisorRequirement]]()

  # Domestikos
  for req in buildReqs.reqs:
    result.add(AdvisorType.Domestikos, AdvisorRequirement(
      reqType: req.reqType, advisor: AdvisorType.Domestikos, priority: req.priority,
      cost: req.cost, targetId: req.targetId, description: req.description,
      buildReq: some(req)
    ))

  # Logothete
  for req in researchReqs.reqs:
    result.add(AdvisorType.Logothete, AdvisorRequirement(
      reqType: req.reqType, advisor: AdvisorType.Logothete, priority: req.priority,
      cost: req.cost, description: req.description,
      researchReq: some(req)
    ))

  # Drungarius
  for req in espionageReqs.reqs:
    result.add(AdvisorType.Drungarius, AdvisorRequirement(
      reqType: req.reqType, advisor: AdvisorType.Drungarius, priority: req.priority,
      cost: req.cost, targetId: req.targetId, description: req.description,
      espionageReq: some(req)
    ))

  # Eparch
  for req in economicReqs.reqs:
    result.add(AdvisorType.Eparch, AdvisorRequirement(
      reqType: req.reqType, advisor: AdvisorType.Eparch, priority: req.priority,
      cost: req.cost, targetId: req.targetId, description: req.description,
      economicReq: some(req)
    ))

  # Protostrator
  for req in diplomaticReqs.reqs:
    result.add(AdvisorType.Protostrator, AdvisorRequirement(
      reqType: req.reqType, advisor: AdvisorType.Protostrator, priority: req.priority,
      cost: req.cost, targetId: req.targetId, description: req.description,
      diplomaticReq: some(req)
    ))

proc mediateRequirements*(
  controller: AIController,
  filtered: FilteredGameState,
  requirements: Table[AdvisorType, seq[AdvisorRequirement]]
): Table[AdvisorType, seq[AdvisorRequirement]] =
  ## Performs mediation and prioritization of requirements across advisors.
  ## This is a placeholder for a more complex RBA mediation system.
  ## For now, it simply returns the original requirements.
  ## In future, this could apply strategic adjustments, combine similar requests, etc.
  result = requirements

proc allocateBudgetMultiAdvisor*(
  controller: AIController,
  filtered: FilteredGameState,
  currentTreasury: int,
  requirements: Table[AdvisorType, seq[AdvisorRequirement]],
  goapBudgetEstimates: Table[string, int] # GOAP budget guidance from Phase 1.5
): MultiAdvisorAllocation =
  ## Allocates the available budget across multiple advisors, incorporating GOAP guidance.
  result.budgets = initTable[AdvisorType, int]()
  for advType in low(AdvisorType)..high(AdvisorType):
    result.budgets[advType] = 0
  result.reservedBudget = 0
  result.totalAllocated = 0
  result.remainingTreasury = currentTreasury
  result.unfulfilledRequirements = @[]

  var weightedReqs: seq[WeightedRequirement] = @[]
  for advisorType, reqList in requirements:
    for req in reqList:
      let baseWeight = calculateUrgencyScore(req, controller.personality)
      weightedReqs.add(WeightedRequirement(requirement: req, weight: baseWeight))

  # Apply GOAP budget guidance as a priority boost
  # This makes requirements aligned with active GOAP plans more likely to be funded.
  for i in 0 ..< weightedReqs.len:
    let req = weightedReqs[i].requirement
    let domainName = case req.advisor
      of AdvisorType.Domestikos: "Build" # Build is mainly for fleets/military and facilities
      of AdvisorType.Logothete: "Research"
      of AdvisorType.Drungarius: "Espionage"
      of AdvisorType.Eparch: "Economic"
      of AdvisorType.Protostrator: "Diplomatic"
      of AdvisorType.Basileus: "" # Basileus itself doesn't have a domain for budget allocation

    if domainName != "" and goapBudgetEstimates.hasKey(domainName):
      let goapAlloc = goapBudgetEstimates[domainName]
      # Boost requirements whose domain is targeted by GOAP with a percentage of the GOAP budget estimate
      # This is a heuristic. A more refined approach would link specific GOAP actions to specific RBA requirements.
      # For now, a flat boost based on the domain's GOAP estimate.
      let budgetGuidanceBoostFactor = controller.goapConfig.budgetGuidanceBoostFactor

      let boostAmount = float(goapAlloc) * budgetGuidanceBoostFactor
      weightedReqs[i].weight += boostAmount
      logDebug(LogCategory.lcAI, &"GOAP Budget Guidance: Boosting {req.description} (Advisor {req.advisor}) by {boostAmount:.2f} due to {domainName} GOAP estimate.")

  # Sort requirements by weight (highest first)
  weightedReqs.sort(proc(a, b: WeightedRequirement): int = cmp(b.weight, a.weight))

  var currentBudget = currentTreasury

  # Allocate funds
  for wr in weightedReqs:
    let reqCost = wr.requirement.cost
    if reqCost <= 0:
      logWarn(LogCategory.lcAI, &"Requirement with non-positive cost: {wr.requirement.description}. Skipping allocation.")
      result.unfulfilledRequirements.add(wr.requirement) # Still track, even if cost is zero
      continue

    if currentBudget >= reqCost:
      # Fully fund the requirement
      result.budgets[wr.requirement.advisor] += reqCost
      currentBudget -= reqCost
      result.totalAllocated += reqCost
    else:
      # Partially fund or leave unfulfilled
      # For now, we only fund fully. If partial funding is allowed, logic needs to be added.
      # Any critical/high priority requirements might get priority here with partial funding.
      result.unfulfilledRequirements.add(wr.requirement)
      logDebug(LogCategory.lcAI, &"Unfulfilled requirement: {wr.requirement.description} (cost: {reqCost}, remaining budget: {currentBudget})")

  result.remainingTreasury = currentBudget
  logInfo(LogCategory.lcAI, &"Budget Mediation: Total {result.totalAllocated} PP allocated, {result.remainingTreasury} PP remaining. {result.unfulfilledRequirements.len} requirements unfulfilled.")

  return result
