import std/[options, tables, strformat, algorithm, sequtils]
import ../../../common/types/core
import ../../../engine/[gamestate, logger, economy/maintenance] # Added economy/maintenance for checkMaintenanceShortfall
import ../controller_types
import ../shared/intelligence_types # For IntelligenceSnapshot
import ../../common/types as ai_types
import ../goap/core/types # For GoalType
import ../goap/integration/plan_tracking # For PlanTracker, PlanStatus
import ../config # For globalRBAConfig

export EconomicRequirementType, EconomicRequirement, EconomicRequirements

# =============================================================================
# Phase 7.2: Competitive Economic Assessment
# =============================================================================

type
  EconomicCompetitiveAssessment = object
    ## Phase 7.2: Assessment of our economic position vs enemies
    underEconomicPressure*: bool  # Enemies significantly out-producing us
    enemyShipyardAdvantage*: int  # How many more shipyards enemies have total
    strongestEnemy*: Option[HouseId]  # Most economically powerful enemy
    productionRatio*: float  # Our production / average enemy production
    infrastructurePriorityBoost*: float  # 1.0-2.0 multiplier for infrastructure

proc assessCompetitiveEconomicPosition(
  ourHouse: House,
  intelSnapshot: IntelligenceSnapshot
): EconomicCompetitiveAssessment =
  ## Phase 7.2: Compare our economic capabilities with enemy intelligence
  result.underEconomicPressure = false
  result.enemyShipyardAdvantage = 0
  result.strongestEnemy = none(HouseId)
  result.productionRatio = 1.0
  result.infrastructurePriorityBoost = 1.0

  # Calculate our total production and shipyards
  var ourTotalProduction = 0
  var ourShipyardCount = 0
  for colonyId, colony in ourHouse.colonies:
    ourTotalProduction += colony.production
    ourShipyardCount += colony.shipyards.len

  # Analyze enemy economic strength
  var enemyCount = 0
  var totalEnemyProduction = 0.0
  var strongestEnemyProduction = 0.0
  var strongestEnemyHouse: Option[HouseId] = none(HouseId)

  for houseId, strength in intelSnapshot.economic.enemyEconomicStrength:
    enemyCount += 1
    let estimatedProduction = strength.estimatedProduction.float
    totalEnemyProduction += estimatedProduction

    if estimatedProduction > strongestEnemyProduction:
      strongestEnemyProduction = estimatedProduction
      strongestEnemyHouse = some(houseId)

  # Count enemy shipyards from construction activity intelligence
  var totalEnemyShipyards = 0
  for systemId, activity in intelSnapshot.economic.constructionActivity:
    totalEnemyShipyards += activity.shipyardCount

  result.enemyShipyardAdvantage = totalEnemyShipyards - ourShipyardCount
  result.strongestEnemy = strongestEnemyHouse

  # Calculate production ratio
  if enemyCount > 0:
    let avgEnemyProduction = totalEnemyProduction / float(enemyCount)
    if avgEnemyProduction > 0:
      result.productionRatio = float(ourTotalProduction) / avgEnemyProduction

  # Flag economic pressure if significantly behind
  # Configuration from config/rba.toml [eparch.economic_pressure]
  if result.productionRatio < globalRBAConfig.eparch.economic_pressure.production_ratio_moderate:
    result.underEconomicPressure = true
    result.infrastructurePriorityBoost = globalRBAConfig.eparch.economic_pressure.boost_moderate_pressure

  if result.productionRatio < globalRBAConfig.eparch.economic_pressure.production_ratio_severe:
    result.infrastructurePriorityBoost = globalRBAConfig.eparch.economic_pressure.boost_severe_pressure

  # Also flag pressure if enemy shipyard advantage is significant
  if result.enemyShipyardAdvantage >= globalRBAConfig.eparch.economic_pressure.shipyard_advantage_threshold:
    result.underEconomicPressure = true
    result.infrastructurePriorityBoost = max(result.infrastructurePriorityBoost,
                                              globalRBAConfig.eparch.economic_pressure.boost_shipyard_disadvantage)

proc generateEconomicRequirements*(
  controller: AIController,
  filtered: FilteredGameState,
  intelSnapshot: IntelligenceSnapshot,
  currentAct: ai_types.GameAct
): EconomicRequirements =
  ## Generates economic requirements for the Eparch advisor.
  ##
  ## Includes requirements for:
  ## - Facility construction (Shipyards, Spaceports)
  ## - Terraforming
  ## - Population transfers
  ## - Industrial Unit (IU) investment
  ## - Balancing economy (tax rates to avoid maintenance shortfall)
  ## - Also factors in "MaintainPrestige" GOAP goal for penalty avoidance (Gap 6)

  result.requirements = @[]
  result.totalEstimatedCost = 0
  result.generatedTurn = filtered.turn
  result.iteration = 0

  let p = controller.personality
  let house = filtered.ownHouse
  let currentTreasury = house.treasury
  let currentIncome = house.latestIncomeReport.getOrDefault(defaultHouseIncomeReport()).netIncome # Net income from last turn
  let maintenanceCost = calculateTotalMaintenanceCost(house, filtered) # Current turn maintenance

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Eparch: Generating economic requirements " &
          &"(Treasury={currentTreasury}PP, NetIncome={currentIncome}PP, Maintenance={maintenanceCost}PP)")

  # Check if "MaintainPrestige" GOAP goal is active.
  # TODO: Re-enable once goapPlanTracker is integrated into AIController
  let isMaintainPrestigeActive = false
  # let isMaintainPrestigeActive = controller.goapPlanTracker.activePlans.anyIt(
  #   it.status == PlanStatus.Active and it.plan.goal.goalType == GoalType.MaintainPrestige
  # )

  # === CRITICAL: Avoid Maintenance Shortfall Prestige Penalty (Gap 6) ===
  # See docs/specs/diplomacy.md "Prestige Penalty Mechanics"
  # If facing maintenance shortfall OR current income is negative and treasury is low,
  # prioritize a "BalanceEconomy" action (which will imply tax rate adjustments).
  let potentialShortfall = checkMaintenanceShortfall(
    house,
    filtered,
    house.taxPolicy.currentTaxRate, # Use current tax rate
    currentIncome # Use last turn's income as a baseline
  )
  
  let isAlreadyInShortfall = house.consecutiveShortfallTurns > 0
  let isAboutToEnterShortfall = (currentIncome < maintenanceCost) and (currentTreasury < maintenanceCost)

  if (isMaintainPrestigeActive and (isAlreadyInShortfall or isAboutToEnterShortfall)) or
     (isAlreadyInShortfall and house.consecutiveShortfallTurns < globalRBAConfig.eparch.maintenance.penalty_turns_critical):
    logWarn(LogCategory.lcAI, &"{controller.houseId} Eparch: CRITICAL - Detecting maintenance shortfall risk. " &
                             &"Current Income: {currentIncome}PP, Maintenance: {maintenanceCost}PP, Treasury: {currentTreasury}PP. " &
                             &"MaintainPrestige active: {isMaintainPrestigeActive}. Consecutive shortfalls: {house.consecutiveShortfallTurns}")
    
    # Generate a high-priority requirement to balance the economy (implies adjusting tax rate)
    let balanceReq = EconomicRequirement(
      requirementType: EconomicRequirementType.TaxPolicy,
      priority: RequirementPriority.Critical, # Critical to avoid escalating prestige penalties
      targetColony: controller.homeworld, # Tax policy is house-wide, target homeworld as symbolic
      estimatedCost: 0, # No direct PP cost for changing tax policy
      reason: &"CRITICAL: Avoid Maintenance Shortfall Prestige Penalty ({house.consecutiveShortfallTurns} turns in shortfall)."
    )
    result.requirements.add(balanceReq)
    # The actual tax adjustment will happen in phase 7.5: Colony Management

  # === Phase 7.2: Competitive Economic Assessment ===
  # Compare our economic position with enemy intelligence
  let competitivePosition = assessCompetitiveEconomicPosition(house, intelSnapshot)

  if competitivePosition.underEconomicPressure:
    logWarn(LogCategory.lcAI,
            &"{controller.houseId} Eparch: ECONOMIC PRESSURE DETECTED - " &
            &"Production ratio: {competitivePosition.productionRatio:.2f}x average enemy, " &
            &"Enemy shipyard advantage: +{competitivePosition.enemyShipyardAdvantage}, " &
            &"Infrastructure priority boost: {competitivePosition.infrastructurePriorityBoost:.1f}x")

    if competitivePosition.strongestEnemy.isSome:
      logInfo(LogCategory.lcAI,
              &"{controller.houseId} Eparch: Strongest economic rival: {competitivePosition.strongestEnemy.get()}")
  else:
    logDebug(LogCategory.lcAI,
             &"{controller.houseId} Eparch: Competitive position stable - " &
             &"Production ratio: {competitivePosition.productionRatio:.2f}x average enemy")

  # === HIGH: Facility Construction (Shipyards, Spaceports) ===
  # Prioritize based on current production needs, defense gaps, GOAP goals
  # Phase 7.2: Infrastructure priority boost applied if under economic pressure
  # ... (existing facility logic will go here)

  # === MEDIUM: IU Investment ===
  # ... (existing IU investment logic will go here)

  # === LOW: Terraforming ===
  # ... (existing terraforming logic will go here)

  # === LOW: Population Transfers ===
  # ... (existing population transfer logic will go here)

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Eparch: Generated {result.requirements.len} economic requirements " &
          &"(total cost estimate: {result.totalEstimatedCost}PP)")

  return result

proc reprioritizeEconomicRequirements*(
  originalRequirements: EconomicRequirements,
  feedback: EparchFeedback
): EconomicRequirements =
  ## Reprioritize unfulfilled economic requirements based on Treasurer feedback
  ## Pattern: Critical stays, High→Medium, Medium→Low, drop Low/Deferred

  result = EconomicRequirements(
    requirements: @[],
    totalEstimatedCost: 0,
    generatedTurn: originalRequirements.generatedTurn,
    iteration: originalRequirements.iteration + 1
  )

  if feedback.unfulfilledRequirements.len == 0:
    # All requirements fulfilled
    result.requirements = originalRequirements.requirements
    result.totalEstimatedCost = originalRequirements.totalEstimatedCost
    return result

  logInfo(LogCategory.lcAI,
          &"Eparch: Reprioritizing {feedback.unfulfilledRequirements.len} unfulfilled economic requirements")

  # Keep fulfilled requirements unchanged
  for req in feedback.fulfilledRequirements:
    result.requirements.add(req)
    result.totalEstimatedCost += req.estimatedCost

  # Reprioritize unfulfilled requirements
  for req in feedback.unfulfilledRequirements:
    var adjustedReq = req
    case req.priority
    of RequirementPriority.Critical:
      # Critical (like Maintenance Shortfall) stays Critical
      adjustedReq.priority = RequirementPriority.Critical
      adjustedReq.reason &= " [CRITICAL: Budget insufficient]"
    of RequirementPriority.High:
      adjustedReq.priority = RequirementPriority.Medium
      adjustedReq.reason &= " [Downgraded from High]"
    of RequirementPriority.Medium:
      adjustedReq.priority = RequirementPriority.Low
      adjustedReq.reason &= " [Downgraded from Medium]"
    of RequirementPriority.Low:
      # Drop Low operations
      logDebug(LogCategory.lcAI, &"Eparch: Dropping Low priority requirement: {req.reason}")
      continue
    of RequirementPriority.Deferred:
      # Already deferred, keep as deferred
      continue

    result.requirements.add(adjustedReq)
    result.totalEstimatedCost += adjustedReq.estimatedCost

  logInfo(LogCategory.lcAI,
          &"Eparch: Reprioritized to {result.requirements.len} requirements " &
          &"(iteration {result.iteration})")

  return result
