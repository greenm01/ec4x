## Treasurer Multi-Advisor Budget Allocation Module
##
## Byzantine Imperial Treasurer - Multi-Advisor Coordination
##
## Hybrid budget allocation strategy:
## 1. Reserve minimums (10% recon, 5% expansion) - prevents starvation
## 2. Mediate remaining budget via Basileus priority queue
## 3. Generate per-advisor feedback (fulfilled/unfulfilled requirements)

import std/[tables, strformat, options, strutils]
import ../../../common/types/[core, units] # Added units
import ../../../engine/[logger, gamestate, fog_of_war]
import ../../../engine/diplomacy/types as dip_types
import ../controller_types
import ../../common/types as ai_types
import ../basileus/mediation
import ../goap/integration/conversion # For DomainType (fixed path)
import ../goap/core/types # For TechField (fixed path)

# MultiAdvisorAllocation now defined in controller_types.nim to avoid
# circular dependency (controller_types was importing from obsolete
# multi_advisor/mediation.nim)

proc extractBuildFeedback*(
  mediation: MediatedAllocation,
  domestikosReqs: BuildRequirements,
  availableBudget: int,
  currentCSTLevel: int # Added for tech-related suggestions
): TreasurerFeedback =
  ## Extract Treasurer feedback for Domestikos from mediation results

  result = TreasurerFeedback(
    fulfilledRequirements: @[],
    unfulfilledRequirements: @[],
    deferredRequirements: @[],
    totalBudgetAvailable: availableBudget,
    totalBudgetSpent: mediation.domestikosBudget,
    totalUnfulfilledCost: 0,
    detailedFeedback: @[] # Initialize detailed feedback
  )

  # Separate fulfilled/unfulfilled Domestikos requirements and generate detailed feedback
  var currentBudget = mediation.domestikosBudget # Budget actually allocated to Domestikos this turn

  for weightedReq in mediation.fulfilledRequirements:
    if weightedReq.requirement.advisor == AdvisorType.Domestikos:
      if weightedReq.requirement.buildReq.isSome:
        result.fulfilledRequirements.add(weightedReq.requirement.buildReq.get())
        # No detailed feedback for fulfilled requirements, as they succeeded
  
  for weightedReq in mediation.unfulfilledRequirements:
    if weightedReq.requirement.advisor == AdvisorType.Domestikos:
      if weightedReq.requirement.buildReq.isSome:
        let req = weightedReq.requirement.buildReq.get()
        if req.priority == RequirementPriority.Deferred:
          result.deferredRequirements.add(req)
        else:
          result.unfulfilledRequirements.add(req) # Keep for summary

          # Generate detailed feedback for unfulfilled build requirements
          let shortfall = req.estimatedCost - currentBudget # Approximate shortfall
          var unfulfillmentReason = UnfulfillmentReason.InsufficientBudget
          var suggestion = ""

          if req.shipClass.isSome:
            # TODO: Implement ship class tech requirements check
            # For now, assume all ships are available if we have sufficient budget
            discard
            # let shipData = getShipClassData(req.shipClass.get())
            # if currentCSTLevel < shipData.cstLevel:
            #   unfulfillmentReason = UnfulfillmentReason.TechNotAvailable
            #   suggestion = &"Research Construction Tech to level {shipData.cstLevel} to build {req.shipClass.get()}."
            # else:
            #   # Insufficient budget for this ship, suggest a cheaper alternative if possible
            #   # This is a heuristic and can be improved with more detailed ship data/AI config
            #   let cheaperShips = [ShipClass.Corvette, ShipClass.Frigate, ShipClass.Destroyer] # Example cheaper ships
            #   var affordableAlternative: Option[ShipClass] = none(ShipClass)
            #   for sClass in cheaperShips:
            #     let altShipData = getShipClassData(sClass)
            #     if currentCSTLevel >= altShipData.cstLevel and currentBudget >= altShipData.buildCost: # Check if affordable with remaining budget
            #       affordableAlternative = some(sClass)
            #       break
            #
            #   if affordableAlternative.isSome:
            #     suggestion = &"Increase budget for Domestikos. Or consider building a cheaper ship like {affordableAlternative.get()} (cost {getShipClassData(affordableAlternative.get()).buildCost}PP)."
            #   else:
            suggestion = &"Increase budget for Domestikos to build {req.shipClass.get()} (needed {req.estimatedCost}PP, had {currentBudget}PP)."
          elif req.itemId.isSome:
            case req.itemId.get()
            of "Shipyard", "Spaceport":
              # Facilities are handled by Eparch, so this indicates a cross-advisor mismatch or budget issue
              unfulfillmentReason = UnfulfillmentReason.BudgetReserved # Assuming Eparch's budget was insufficient or redirected
              suggestion = &"Increase budget for Eparch/Domestikos to build {req.itemId.get()} (needed {req.estimatedCost}PP, had {currentBudget}PP)."
            of "Marine", "Army", "GroundBattery", "PlanetaryShield":
              unfulfillmentReason = UnfulfillmentReason.InsufficientBudget
              suggestion = &"Increase budget for Domestikos to build {req.itemId.get()} (needed {req.estimatedCost}PP, had {currentBudget}PP)."
            else:
              unfulfillmentReason = UnfulfillmentReason.InsufficientBudget
              suggestion = &"Increase budget for Domestikos/Eparch for {req.itemId.get()} (needed {req.estimatedCost}PP, had {currentBudget}PP)."
          else:
            unfulfillmentReason = UnfulfillmentReason.InsufficientBudget
            suggestion = &"Increase budget for this build requirement (needed {req.estimatedCost}PP, had {currentBudget}PP)."

          result.detailedFeedback.add(RequirementFeedback(
            requirement: req, # Already a BuildRequirement
            originalAdvisorReason: req.reason,
            unfulfillmentReason: unfulfillmentReason,
            budgetShortfall: shortfall,
            quantityBuilt: 0, # Assuming no partial fulfillment for now
            suggestion: some(suggestion)
          ))
          result.totalUnfulfilledCost += req.estimatedCost

  return result

proc extractScienceFeedback*(
  mediation: MediatedAllocation,
  logotheteReqs: ResearchRequirements,
  availableBudget: int
): ScienceFeedback =
  ## Extract Treasurer feedback for Logothete from mediation results

  result = ScienceFeedback(
    fulfilledRequirements: @[],
    unfulfilledRequirements: @[],
    totalRPAvailable: availableBudget,
    totalRPSpent: mediation.logotheteBudget
  )

  var currentRPBudget = mediation.logotheteBudget

  for weightedReq in mediation.fulfilledRequirements:
    if weightedReq.requirement.advisor == AdvisorType.Logothete:
      if weightedReq.requirement.researchReq.isSome:
        result.fulfilledRequirements.add(weightedReq.requirement.researchReq.get())

  for weightedReq in mediation.unfulfilledRequirements:
    if weightedReq.requirement.advisor == AdvisorType.Logothete:
      if weightedReq.requirement.researchReq.isSome:
        let req = weightedReq.requirement.researchReq.get()
        result.unfulfilledRequirements.add(req) # Keep for summary

        # TODO: Implement detailed feedback mechanism
        # ScienceFeedback type currently doesn't support detailedFeedback field
  return result

proc extractDrungariusFeedback*(
  mediation: MediatedAllocation,
  drungariusReqs: EspionageRequirements,
  availableBudget: int
): DrungariusFeedback =
  ## Extract Treasurer feedback for Drungarius from mediation results

  result = DrungariusFeedback(
    fulfilledRequirements: @[],
    unfulfilledRequirements: @[],
    totalBudgetAvailable: availableBudget,
    totalBudgetSpent: mediation.drungariusBudget
  )

  var currentEspionageBudget = mediation.drungariusBudget

  for weightedReq in mediation.fulfilledRequirements:
    if weightedReq.requirement.advisor == AdvisorType.Drungarius:
      if weightedReq.requirement.espionageReq.isSome:
        result.fulfilledRequirements.add(weightedReq.requirement.espionageReq.get())

  for weightedReq in mediation.unfulfilledRequirements:
    if weightedReq.requirement.advisor == AdvisorType.Drungarius:
      if weightedReq.requirement.espionageReq.isSome:
        let req = weightedReq.requirement.espionageReq.get()
        result.unfulfilledRequirements.add(req) # Keep for summary

        # TODO: Implement detailed feedback mechanism
        # DrungariusFeedback type currently doesn't support detailedFeedback field
  return result

proc extractEparchFeedback*(
  mediation: MediatedAllocation,
  eparchReqs: EconomicRequirements,
  availableBudget: int
): EparchFeedback =
  ## Extract Treasurer feedback for Eparch from mediation results

  result = EparchFeedback(
    fulfilledRequirements: @[],
    unfulfilledRequirements: @[],
    totalBudgetAvailable: availableBudget,
    totalBudgetSpent: mediation.eparchBudget
  )

  var currentEconomicBudget = mediation.eparchBudget

  for weightedReq in mediation.fulfilledRequirements:
    if weightedReq.requirement.advisor == AdvisorType.Eparch:
      if weightedReq.requirement.economicReq.isSome:
        result.fulfilledRequirements.add(weightedReq.requirement.economicReq.get())

  for weightedReq in mediation.unfulfilledRequirements:
    if weightedReq.requirement.advisor == AdvisorType.Eparch:
      if weightedReq.requirement.economicReq.isSome:
        let req = weightedReq.requirement.economicReq.get()
        result.unfulfilledRequirements.add(req) # Keep for summary

        # TODO: Implement detailed feedback mechanism
        # EparchFeedback type currently doesn't support detailedFeedback field
  return result

proc isAtWar*(filtered: FilteredGameState, houseId: HouseId): bool =
  ## Check if a house is currently at war with any other house
  ## War status = DiplomaticState.Enemy
  result = false

  for pair, state in filtered.houseDiplomacy.pairs:
    let (house1, house2) = pair
    if (house1 == houseId or house2 == houseId) and state == dip_types.DiplomaticState.Enemy:
      return true

  return false

proc allocateBudgetMultiAdvisor*(
  domestikosReqs: BuildRequirements,
  logotheteReqs: ResearchRequirements,
  drungariusReqs: EspionageRequirements,
  eparchReqs: EconomicRequirements,
  protostratorReqs: DiplomaticRequirements,
  personality: AIPersonality,
  currentAct: ai_types.GameAct,
  availableBudget: int,
  houseId: HouseId,
  filtered: FilteredGameState,  # For war status detection
  goapBudgetEstimates: Option[Table[DomainType, int]] = none(Table[DomainType, int]),  # GOAP estimates by domain
  goapReservedAmount: Option[int] = none(int)  # NEW: Amount GOAP wants to reserve for future turns
): MultiAdvisorAllocation =
  ## Hybrid budget allocation strategy:
  ## 1. Reserve minimums (prevents starvation)
  ## 2. Mediate remaining budget via Basileus
  ## 3. Combine reserves + mediated budgets
  ## 4. Generate per-advisor feedback
  ##
  ## GOAP Phase 3 Enhancement:
  ## - If goapBudgetEstimates provided, uses strategic cost estimates for informed allocation
  ## - Prioritizes advisors with active GOAP plans

  # Detect war status for war-aware weights
  let atWar = isAtWar(filtered, houseId)

  logInfo(LogCategory.lcAI,
          &"{houseId} Treasurer: Multi-advisor allocation starting " &
          &"(budget={availableBudget}PP, act={currentAct}, atWar={atWar})")

  # GOAP Phase 3: Log strategic budget estimates if provided
  if goapBudgetEstimates.isSome:
    let estimates = goapBudgetEstimates.get()
    var totalEstimate = 0
    for domain, cost in estimates: # Iterate over DomainType
      totalEstimate += cost
    logInfo(LogCategory.lcAI,
            &"{houseId} Treasurer: GOAP strategic estimates: {totalEstimate}PP total")
    for domain, cost in estimates: # Iterate over DomainType
      if cost > 0:
        logInfo(LogCategory.lcAI, &"{houseId}   - {$domain}: {cost}PP") # Convert DomainType to string for logging

    # If GOAP estimates exceed available budget, log warning
    if totalEstimate > availableBudget:
      let shortfall = totalEstimate - availableBudget
      logInfo(LogCategory.lcAI,
              &"{houseId} Treasurer: WARNING - GOAP plans need {shortfall}PP more than available")

  # === STEP 1: Reserve minimums (prevents starvation) ===
  let minReconBudget = int(float(availableBudget) * 0.10)  # 10% for scouts
  let minExpansionBudget = int(float(availableBudget) * 0.05)  # 5% for expansion
  let reservedBudget = minReconBudget + minExpansionBudget
  let remainingBudget = availableBudget - reservedBudget

  let actualGoapReserved = goapReservedAmount.get(0)

  logInfo(LogCategory.lcAI,
          &"{houseId} Treasurer: Reserved {reservedBudget}PP " &
          &"(recon={minReconBudget}PP, expansion={minExpansionBudget}PP), " &
          &"mediating {remainingBudget}PP")
  if actualGoapReserved > 0:
    logInfo(LogCategory.lcAI,
            &"{houseId} Treasurer: GOAP requested {actualGoapReserved}PP for future turns.")

  # Subtract GOAP reserved amount from the available budget for current turn allocation
  let budgetForCurrentAllocation = remainingBudget - actualGoapReserved
  if budgetForCurrentAllocation < 0:
    logWarn(LogCategory.lcAI,
            &"{houseId} Treasurer: GOAP reservation of {actualGoapReserved}PP exceeds available " &
            &"budget for current allocation ({remainingBudget}PP). Allocating 0 to advisors.")
    # Set budgets to 0 and proceed, ensuring no negative allocations
    # This might need a more sophisticated conflict resolution if GOAP reservation is sacred
    # For now, current allocations take priority if budget is tight
  
  let effectiveBudgetForMediation = max(0, budgetForCurrentAllocation)
  logInfo(LogCategory.lcAI,
          &"{houseId} Treasurer: Effective budget for current turn mediation: {effectiveBudgetForMediation}PP")

  # === STEP 2: Mediate remaining budget with war-aware weights and GOAP estimates ===
  let mediation = mediateRequirements(
    domestikosReqs, logotheteReqs, drungariusReqs, eparchReqs, protostratorReqs,
    personality, currentAct, effectiveBudgetForMediation, houseId, atWar, goapBudgetEstimates
  )

  # === STEP 3: Combine reserves + mediated allocations ===
  result.budgets = initTable[AdvisorType, int]()
  result.budgets[AdvisorType.Domestikos] = reservedBudget + mediation.domestikosBudget
  result.budgets[AdvisorType.Logothete] = mediation.logotheteBudget
  result.budgets[AdvisorType.Drungarius] = mediation.drungariusBudget
  result.budgets[AdvisorType.Eparch] = mediation.eparchBudget
  result.budgets[AdvisorType.Protostrator] = 0  # Diplomacy costs 0 PP
  result.budgets[AdvisorType.Treasurer] = 0  # Treasurer doesn't get budget
  result.reservedBudget = actualGoapReserved # Store the amount actually reserved
  result.iteration = 0

  # === STEP 4: Generate per-advisor feedback ===
  let cstLevel = filtered.ownHouse.techTree.levels.constructionTech # Get CST level here
  
  result.treasurerFeedback = extractBuildFeedback(mediation, domestikosReqs, availableBudget, cstLevel)
  result.scienceFeedback = extractScienceFeedback(mediation, logotheteReqs, availableBudget)
  result.drungariusFeedback = extractDrungariusFeedback(mediation, drungariusReqs, availableBudget)
  result.eparchFeedback = extractEparchFeedback(mediation, eparchReqs, availableBudget)

  # Summary logging
  let totalAllocated = result.budgets[AdvisorType.Domestikos] +
                       result.budgets[AdvisorType.Logothete] +
                       result.budgets[AdvisorType.Drungarius] +
                       result.budgets[AdvisorType.Eparch]

  logInfo(LogCategory.lcAI,
          &"{houseId} Treasurer: Allocation complete - " &
          &"{totalAllocated}/{availableBudget}PP allocated")

  logInfo(LogCategory.lcAI,
          &"{houseId} Treasurer: Final budgets - " &
          &"Domestikos={result.budgets[AdvisorType.Domestikos]}PP " &
          &"(+{reservedBudget}PP local reserved), " &
          &"Logothete={result.budgets[AdvisorType.Logothete]}PP, " &
          &"Drungarius={result.budgets[AdvisorType.Drungarius]}PP, " &
          &"Eparch={result.budgets[AdvisorType.Eparch]}PP, " &
          &"GOAP Reserved={result.reservedBudget}PP")

  # Log unfulfilled counts for feedback loop
  logInfo(LogCategory.lcAI,
          &"{houseId} Treasurer: Unfulfilled requirements - " &
          &"Domestikos={result.treasurerFeedback.unfulfilledRequirements.len}, " &
          &"Logothete={result.scienceFeedback.unfulfilledRequirements.len}, " &
          &"Drungarius={result.drungariusFeedback.unfulfilledRequirements.len}, " &
          &"Eparch={result.eparchFeedback.unfulfilledRequirements.len}")

  return result
