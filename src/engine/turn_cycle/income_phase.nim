## Income Phase Resolution - Phase 2 of Canonical Turn Cycle
##
## Handles all economic calculations, resource collection, and game state evaluation
## after Conflict Phase damage has been applied.
##
## **Canonical Execution Order:**
##
## Step 1: Calculate Base Production
## Step 2: Apply Blockades (from Conflict Phase)
## Step 3: Calculate Maintenance Costs
## Step 4: Execute Salvage Orders
## Step 5: Capacity Enforcement After IU Loss
##   5a. Capital Squadron Capacity (No Grace Period)
##   5b. Total Squadron Limit (2-Turn Grace Period)
##   5c. Fighter Squadron Capacity (2-Turn Grace Period)
##   5d. Planet-Breaker Enforcement (Immediate)
## Step 5a: Apply C2 Pool Logistical Strain
## Step 6: Collect Resources
## Step 7: Calculate Prestige
## Step 8: House Elimination & Victory Checks
##   8a. House Elimination
##   8b. Victory Conditions
## Step 9: Advance Timers
##
## **Key Properties:**
## - Production calculated AFTER Conflict Phase damage (damaged facilities produce less)
## - Blockades established in Conflict Phase affect same turn's production (no delay)
## - Capacity enforcement uses post-blockade/post-combat IU values
## - Elimination checks happen AFTER prestige calculation (Step 7)
## - Victory checks happen AFTER elimination processing (Step 8a)

import std/[tables, options, strutils, random]
import ../../common/logger
import ../types/[game_state, command, event, core, espionage, fleet, house, diplomacy, victory]
import ../state/[engine, iterators, fleet_queries]
import ../globals
import ../systems/income/engine as income_engine
import ../systems/capacity/[fighter, c2_pool, planet_breakers]
import ../systems/espionage/engine as esp_engine
import ../systems/fleet/dispatcher
import ../systems/diplomacy/proposals
import ../victory/engine as victory_engine
import ../event_factory/init as event_factory
import ../systems/fleet/execution as fleet_order_execution

proc resolveIncomePhase*(
    state: var GameState,
    orders: Table[HouseId, CommandPacket],
    events: var seq[GameEvent],
    rng: var Rand,
) =
  ## Phase 2: Collect income and allocate resources
  ## Production is calculated AFTER conflict, so damaged infrastructure produces less
  ## Also applies ongoing espionage effects (SRP/NCV/Tax reductions)
  logInfo("Income", "=== Income Phase ===", "turn=", $state.turn)

  # ===================================================================
  # STEP 0: APPLY ONGOING ESPIONAGE EFFECTS
  # ===================================================================
  # Effects modify production/intel during GCO calculation (Step 1)
  logInfo("Income", "[STEP 0] Filtering active espionage effects...")

  var activeEffects: seq[OngoingEffect] = @[]
  for effect in state.ongoingEffects:
    if effect.turnsRemaining > 0:
      activeEffects.add(effect)
      logDebug(
        "Espionage",
        "Active effect",
        "target=", $effect.targetHouse,
        " type=", $effect.effectType,
        " remaining=", $effect.turnsRemaining
      )

  state.ongoingEffects = activeEffects
  logInfo("Income", "[STEP 0] Complete", "active=", $activeEffects.len)

  # ===================================================================
  # STEP 0b: PROCESS EBP/CIP INVESTMENT
  # ===================================================================
  # Purchase EBP/CIP with PP, check over-investment penalty
  logInfo("Income", "[STEP 0b] Processing EBP/CIP purchases...")

  var purchaseCount = 0
  for (houseId, house) in state.allHousesWithId():
    if houseId notin orders:
      continue

    let packet = orders[houseId]
    if packet.ebpInvestment == 0 and packet.cipInvestment == 0:
      continue

    let ebpCost = packet.ebpInvestment * gameConfig.espionage.costs.ebpCostPp
    let cipCost = packet.cipInvestment * gameConfig.espionage.costs.cipCostPp
    let totalCost = ebpCost + cipCost

    var updatedHouse = house
    if updatedHouse.treasury < totalCost:
      logError("Espionage", "Insufficient funds for EBP/CIP",
        "house=", $houseId, " cost=", $totalCost)
      continue

    # Deduct from treasury and add points
    updatedHouse.treasury -= totalCost
    discard esp_engine.purchaseEBP(updatedHouse.espionageBudget,
      packet.ebpInvestment)
    discard esp_engine.purchaseCIP(updatedHouse.espionageBudget,
      packet.cipInvestment)

    # Check over-investment penalty (if configured)
    # TODO: Add investment config to espionage.toml if over-investment penalty needed

    state.updateHouse(houseId, updatedHouse)
    purchaseCount += 1

  logInfo("Income", "[STEP 0b] Complete", "purchases=", $purchaseCount)

  # ===================================================================
  # STEP 1: CALCULATE BASE PRODUCTION
  # ===================================================================
  logInfo("Economy", "[STEP 1] Calculating base production...")

  # Call income engine (calculates GCO, applies blockades, updates treasuries)
  let incomeReport = income_engine.resolveIncomePhase(
    state, baseGrowthRate = gameConfig.economy.population.naturalGrowthRate
  )

  logInfo("Economy", "[STEP 1] Complete",
    "houses=", $incomeReport.houseReports.len)

  # ===================================================================
  # STEP 2: APPLY BLOCKADES (from Conflict Phase)
  # ===================================================================
  # Blockades already applied during Step 1 GCO calculation
  var blockadeCount = 0
  for colony in state.allColonies():
    if colony.blockaded:
      blockadeCount += 1

  logInfo("Economy", "[STEP 2] Blockades applied", "count=", $blockadeCount)

  # ===================================================================
  # STEP 3: CALCULATE AND DEDUCT MAINTENANCE UPKEEP
  # ===================================================================
  logInfo("Economy", "[STEP 3] Calculating maintenance upkeep...")

  let maintenanceUpkeepByHouse =
    income_engine.calculateAndDeductMaintenanceUpkeep(state, events)

  for houseId, upkeepCost in maintenanceUpkeepByHouse:
    logInfo("Economy", "Maintenance paid",
      "house=", $houseId, " cost=", $upkeepCost, " PP")

  logInfo("Economy", "[STEP 3] Complete")

  # ===================================================================
  # STEP 4: EXECUTE SALVAGE ORDERS
  # ===================================================================
  # Salvage commands execute if fleet survived Conflict Phase and arrived
  logInfo("Fleet", "[STEP 4] Executing salvage orders...")

  var salvageCount = 0
  for (houseId, _) in state.allHousesWithId():
    if houseId notin orders:
      continue

    for command in orders[houseId].fleetCommands:
      if command.commandType != FleetCommandType.Salvage:
        continue

      # Check fleet survived Conflict Phase
      let fleetOpt = state.fleet(command.fleetId)
      if fleetOpt.isNone:
        continue

      let fleet = fleetOpt.get()

      # Check arrival (required for execution)
      if fleet.missionState != MissionState.Executing:
        continue

      # Execute salvage via dispatcher
      let outcome = dispatcher.executeFleetCommand(state, houseId, command, events)
      if outcome == OrderOutcome.Success:
        salvageCount += 1
        # Salvage destroys the fleet, so no need to update missionState

  logInfo("Fleet", "[STEP 4] Complete", "salvaged=", $salvageCount)

  # ===================================================================
  # ADMINISTRATIVE COMPLETION (Income Commands)
  # ===================================================================
  # Mark Income Phase commands complete after salvage operations finish
  # Note: This is administrative completion only - salvage behavior already happened above
  logInfo("Income", "[INCOME PHASE] Administrative completion for Income commands...")
  fleet_order_execution.performCommandMaintenance(
    state, orders, events, rng,
    fleet_order_execution.isIncomeCommand,
    "Income Phase - Administrative Completion"
  )
  logInfo("Income", "[INCOME PHASE] Administrative completion complete")

  # ===================================================================
  # STEP 5: CAPACITY ENFORCEMENT AFTER IU LOSS
  # ===================================================================
  logInfo("Economy", "[STEP 5] Checking capacity violations...")

  # Fighter squadron capacity (2-turn grace period per colony)
  let fighterEnforcement = fighter.processCapacityEnforcement(state, events)

  # Planet-breaker capacity (immediate enforcement, 1 per colony)
  let pbEnforcement = planet_breakers.processCapacityEnforcement(state, events)

  logInfo("Economy", "[STEP 5] Complete",
    "fighters=", $fighterEnforcement.len,
    " pbs=", $pbEnforcement.len)

  # ===================================================================
  # STEP 5a: APPLY C2 POOL LOGISTICAL STRAIN
  # ===================================================================
  # Logistical strain penalty for exceeding C2 Pool capacity
  logInfo("Economy", "[STEP 5a] Processing C2 Pool logistical strain...")

  for (houseId, _) in state.allHousesWithId():
    let analysis = c2_pool.processLogisticalStrain(state, houseId, events)

    if analysis.logisticalStrain > 0:
      logWarn("Economy", "Logistical strain penalty",
        "house=", $houseId,
        " cost=", $analysis.logisticalStrain, " PP",
        " excess=", $analysis.excess, " CC")
    else:
      logDebug("Economy", "C2 Pool status",
        "house=", $houseId,
        " cc=", $analysis.totalFleetCC, "/", $analysis.c2Pool)

  logInfo("Economy", "[STEP 5a] Complete")

  # ===================================================================
  # STEP 6: COLLECT RESOURCES
  # ===================================================================
  # Treasury and growth already applied by income_engine.resolveIncomePhase()
  logInfo("Economy", "[STEP 6] Collecting resources...")

  for houseId, houseReport in incomeReport.houseReports:
    # Store income report for intelligence (HackStarbase missions)
    let houseOpt = state.house(houseId)
    if houseOpt.isSome:
      var house = houseOpt.get()
      house.latestIncomeReport = some(houseReport)
      state.updateHouse(houseId, house)

    logInfo("Economy", "House income",
      "house=", $houseId,
      " net=", $houseReport.totalNet, " PP",
      " gross=", $houseReport.totalGross, " PP")

    # Update colony production fields from income reports
    for colonyReport in houseReport.colonies:
      let colonyOpt = state.colony(colonyReport.colonyId)
      if colonyOpt.isSome:
        var colony = colonyOpt.get()
        colony.production = colonyReport.grossOutput
        state.updateColony(colonyReport.colonyId, colony)

  logInfo("Economy", "[STEP 6] Complete")

  # ===================================================================
  # STEP 7: CALCULATE PRESTIGE
  # ===================================================================
  logInfo("Prestige", "[STEP 7] Calculating prestige...")

  for houseId, houseReport in incomeReport.houseReports:
    # Apply prestige events from economic activities
    for prestigeEvent in houseReport.prestigeEvents:
      let houseOpt = state.house(houseId)
      if houseOpt.isSome:
        var house = houseOpt.get()
        house.prestige += prestigeEvent.amount
        state.updateHouse(houseId, house)
        logDebug("Prestige", "Event applied",
          "house=", $houseId,
          " amount=", $prestigeEvent.amount,
          " desc=", prestigeEvent.description)

    # Apply blockade prestige penalties
    var blockadedCount = 0
    for colony in state.coloniesOwned(houseId):
      if colony.blockaded:
        blockadedCount += 1

    if blockadedCount > 0:
      let penaltyPerColony = gameConfig.prestige.penalties.blockadePenalty
      let blockadePenalty = int32(penaltyPerColony * blockadedCount)
      let houseOpt = state.house(houseId)
      if houseOpt.isSome:
        var house = houseOpt.get()
        house.prestige += blockadePenalty
        state.updateHouse(houseId, house)
        logWarn("Prestige", "Blockade penalty",
          "house=", $houseId,
          " penalty=", $blockadePenalty,
          " colonies=", $blockadedCount)

  logInfo("Prestige", "[STEP 7] Complete")

  # ===================================================================
  # STEP 8: CHECK ELIMINATION & VICTORY CONDITIONS
  # ===================================================================
  logInfo("Victory", "[STEP 8a] Checking elimination conditions...")

  let defenseCollapseThreshold =
    gameConfig.gameplay.elimination.defensiveCollapseThreshold
  let defenseCollapseTurns =
    gameConfig.gameplay.elimination.defensiveCollapseTurns
  var eliminatedCount = 0

  for (houseId, house) in state.allHousesWithId():
    if house.isEliminated:
      continue

    # Standard elimination: no colonies AND no invasion capability
    var colonyCount = 0
    for _ in state.coloniesOwned(houseId):
      colonyCount += 1

    if colonyCount == 0:
      # Check if house has invasion capability (marines on transports)
      var hasInvasionCapability = false
      for fleet in state.fleetsOwned(houseId):
        if state.hasLoadedMarines(fleet):
          hasInvasionCapability = true
          break

      # Eliminate if no fleets OR no marines for reconquest
      var fleetCount = 0
      for _ in state.fleetsOwned(houseId):
        fleetCount += 1

      if fleetCount == 0 or not hasInvasionCapability:
        var houseToUpdate = house
        houseToUpdate.isEliminated = true
        houseToUpdate.eliminatedTurn = state.turn
        state.updateHouse(houseId, houseToUpdate)
        eliminatedCount += 1

        let reason = if fleetCount == 0:
          "no remaining forces" else: "no marines for reconquest"
        # HouseId(0) represents "unknown" eliminator
        events.add(event_factory.houseEliminated(houseId, HouseId(0)))
        logInfo("Victory", "House eliminated",
          "house=", $houseId, " reason=", reason)
        continue

    # Defensive collapse: prestige < threshold for consecutive turns
    var houseToUpdate = house
    if house.prestige < defenseCollapseThreshold:
      houseToUpdate.negativePrestigeTurns += 1
      logWarn("Victory", "Defensive collapse warning",
        "house=", $houseId,
        " prestige=", $house.prestige,
        " turns=", $houseToUpdate.negativePrestigeTurns, "/", $defenseCollapseTurns)

      if houseToUpdate.negativePrestigeTurns >= defenseCollapseTurns:
        houseToUpdate.isEliminated = true
        houseToUpdate.eliminatedTurn = state.turn
        houseToUpdate.status = HouseStatus.DefensiveCollapse
        state.updateHouse(houseId, houseToUpdate)
        eliminatedCount += 1
        # HouseId(1) represents "defensive collapse" self-elimination
        events.add(event_factory.houseEliminated(houseId, HouseId(1)))
        logInfo("Victory", "House eliminated by defensive collapse",
          "house=", $houseId)
        continue
    else:
      # Reset counter when prestige recovers
      houseToUpdate.negativePrestigeTurns = 0

    state.updateHouse(houseId, houseToUpdate)

  logInfo("Victory", "[STEP 8a] Complete", "eliminated=", $eliminatedCount)

  # Step 8b: Check victory conditions (after eliminations processed)
  logInfo("Victory", "[STEP 8b] Checking victory conditions...")
  
  let victoryCondition = VictoryCondition(
    turnLimit: gameSetup.victoryConditions.turnLimit,
    enableDefensiveCollapse: true
  )
  let victoryCheck = victory_engine.checkVictoryConditions(state, victoryCondition)
  
  if victoryCheck.victoryOccurred:
    logInfo("Victory", "*** GAME OVER ***",
      "victor=", $victoryCheck.status.houseId,
      " type=", $victoryCheck.status.victoryType,
      " turn=", $victoryCheck.status.achievedOnTurn)
    # Victory event handled by victory engine
  
  logInfo("Victory", "[STEP 8b] Complete")

  # ===================================================================
  # STEP 9: ADVANCE TIMERS
  # ===================================================================
  logInfo("Income", "[STEP 9] Advancing timers...")

  # Decrement ongoing espionage effect counters
  var remainingEffects: seq[OngoingEffect] = @[]
  for effect in state.ongoingEffects:
    var updatedEffect = effect
    updatedEffect.turnsRemaining -= 1

    if updatedEffect.turnsRemaining > 0:
      remainingEffects.add(updatedEffect)
    else:
      logDebug("Espionage", "Effect expired",
        "target=", $updatedEffect.targetHouse,
        " type=", $updatedEffect.effectType)

  state.ongoingEffects = remainingEffects

  # Expire pending diplomatic proposals
  var expiredCount = 0
  var updatedProposals: seq[PendingProposal] = @[]
  
  for proposal in state.pendingProposals:
    var p = proposal
    if p.status == ProposalStatus.Pending:
      # Check if proposal expired (expiresOnTurn reached)
      if state.turn >= p.expiresOnTurn:
        p.status = ProposalStatus.Expired
        expiredCount += 1
        logDebug("Diplomacy", "Proposal expired",
          "id=", p.id,
          " from=", $p.proposer,
          " to=", $p.target)
    
    # Keep recent proposals (10 turn history)
    if p.status == ProposalStatus.Pending or (state.turn - p.submittedTurn) < 10:
      updatedProposals.add(p)

  state.pendingProposals = updatedProposals

  logInfo("Income", "[STEP 9] Complete",
    "expired=", $expiredCount,
    " remaining=", $state.pendingProposals.len)
