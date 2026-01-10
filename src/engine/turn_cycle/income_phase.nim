## Income Phase Resolution - Phase 2 of Canonical Turn Cycle
##
## Handles all economic calculations, resource collection, and game state
## evaluation after Conflict Phase damage has been applied.
##
## **Canonical Execution Order (INC1-11):**
##
## INC1: Apply Ongoing Espionage Effects
## INC2: Process EBP/CIP Investment
## INC3: Calculate Base Production
## INC4: Apply Blockades (from Conflict Phase)
## INC5: Execute Salvage Commands (BEFORE maintenance!)
## INC6: Maintenance Processing (6a-6d)
## INC7: Capacity Enforcement (7a C2 Pool, 7b Fighter, 7c Planet-Breaker)
## INC8: Collect Resources
## INC9: Calculate Prestige
## INC10: House Elimination & Victory Checks (10a, 10b)
## INC11: Advance Timers
##
## **Key Properties:**
## - Production calculated AFTER Conflict Phase damage
## - Blockades established in Conflict Phase affect same turn's production
## - Salvage executes BEFORE maintenance (don't pay on salvaged fleets)
## - Capacity enforcement uses post-blockade/post-combat IU values
## - Elimination checks happen AFTER prestige calculation
## - Victory checks happen AFTER elimination processing

import std/[tables, options, random]
import ../../common/logger
import ../types/[game_state, command, event, core, espionage, fleet, house,
                 diplomacy, victory]
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

# =============================================================================
# INC1: Apply Ongoing Espionage Effects
# =============================================================================

proc applyOngoingEspionageEffects(state: var GameState): int =
  ## [INC1] Filter active espionage effects, apply modifiers
  ## Returns count of active effects
  logInfo("Income", "[INC1] Applying ongoing espionage effects...")

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
  logInfo("Income", "[INC1] Complete", "active=", $activeEffects.len)
  return activeEffects.len

# =============================================================================
# INC2: Process EBP/CIP Investment
# =============================================================================

proc processEBPCIPInvestment(
    state: var GameState,
    orders: Table[HouseId, CommandPacket],
    events: var seq[GameEvent],
): int =
  ## [INC2] Purchase EBP/CIP with PP, check over-investment penalty
  ## Returns count of houses that made purchases
  logInfo("Income", "[INC2] Processing EBP/CIP purchases...")

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
    # Pass PP spent (ebpCost/cipCost), NOT points to purchase
    # purchaseEBP/CIP divide by cost to calculate points purchased
    updatedHouse.treasury -= totalCost
    discard esp_engine.purchaseEBP(updatedHouse.espionageBudget, ebpCost)
    discard esp_engine.purchaseCIP(updatedHouse.espionageBudget, cipCost)

    # TODO: Add over-investment penalty check if configured
    # Threshold: >5% of turn budget → -1 prestige per 1% over threshold

    state.updateHouse(houseId, updatedHouse)
    purchaseCount += 1

    logDebug("Espionage", "EBP/CIP purchased",
      "house=", $houseId,
      " ebp=", $packet.ebpInvestment,
      " cip=", $packet.cipInvestment,
      " cost=", $totalCost)

  logInfo("Income", "[INC2] Complete", "purchases=", $purchaseCount)
  return purchaseCount

# =============================================================================
# INC3: Calculate Base Production
# =============================================================================

proc calculateBaseProduction(
    state: var GameState,
): income_engine.IncomePhaseReport =
  ## [INC3] Calculate GCO, apply blockades (via income_engine)
  ## Returns income report with per-house and per-colony details
  logInfo("Economy", "[INC3] Calculating base production...")

  let incomeReport = income_engine.resolveIncomePhase(
    state, baseGrowthRate = gameConfig.economy.population.naturalGrowthRate
  )

  logInfo("Economy", "[INC3] Complete",
    "houses=", $incomeReport.houseReports.len)
  return incomeReport

# =============================================================================
# INC4: Apply Blockades (informational - already applied in INC3)
# =============================================================================

proc countBlockadedColonies(state: GameState): int =
  ## [INC4] Count blockaded colonies (blockades already applied during INC3)
  ## Returns count of blockaded colonies
  logInfo("Economy", "[INC4] Counting blockaded colonies...")

  var blockadeCount = 0
  for colony in state.allColonies():
    if colony.blockaded:
      blockadeCount += 1

  logInfo("Economy", "[INC4] Complete", "blockaded=", $blockadeCount)
  return blockadeCount

# =============================================================================
# INC5: Execute Salvage Commands (BEFORE maintenance!)
# =============================================================================

proc executeSalvageCommands(
    state: var GameState,
    orders: Table[HouseId, CommandPacket],
    events: var seq[GameEvent],
): int =
  ## [INC5] Execute salvage orders for fleets that survived Conflict Phase
  ## CRITICAL: Runs BEFORE maintenance so salvaged ships don't incur costs
  ## Returns count of salvaged fleets
  logInfo("Fleet", "[INC5] Executing salvage orders...")

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
      let outcome = dispatcher.executeFleetCommand(state, houseId, command,
                                                   events)
      if outcome == OrderOutcome.Success:
        salvageCount += 1
        # Salvage destroys the fleet, so no need to update missionState

  logInfo("Fleet", "[INC5] Complete", "salvaged=", $salvageCount)
  return salvageCount

# =============================================================================
# INC6: Maintenance Processing (6a-6d)
# =============================================================================

proc processMaintenancePhase(
    state: var GameState,
    events: var seq[GameEvent],
) =
  ## [INC6] Calculate and deduct maintenance upkeep
  ## Substeps: 6a Calculate, 6b Payment, 6c Shortfall, 6d Auto-Salvage
  logInfo("Economy", "[INC6] Processing maintenance...")

  let maintenanceUpkeepByHouse =
    income_engine.calculateAndDeductMaintenanceUpkeep(state, events)

  for houseId, upkeepCost in maintenanceUpkeepByHouse:
    logInfo("Economy", "Maintenance paid",
      "house=", $houseId, " cost=", $upkeepCost, " PP")

  logInfo("Economy", "[INC6] Complete")

# =============================================================================
# INC7: Capacity Enforcement (7a C2 Pool, 7b Fighter, 7c Planet-Breaker)
# =============================================================================

proc enforceCapacityLimits(
    state: var GameState,
    events: var seq[GameEvent],
) =
  ## [INC7] Enforce capacity limits post-combat
  ## 7a: C2 Pool logistical strain (soft cap, financial penalty)
  ## 7b: Fighter capacity (2-turn grace period)
  ## 7c: Planet-Breaker enforcement (immediate)
  logInfo("Economy", "[INC7] Enforcing capacity limits...")

  # [INC7a] C2 Pool Logistical Strain
  logInfo("Economy", "[INC7a] Processing C2 Pool logistical strain...")
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

  # [INC7b] Fighter squadron capacity (2-turn grace period per colony)
  logInfo("Economy", "[INC7b] Processing fighter capacity...")
  let fighterEnforcement = fighter.processCapacityEnforcement(state, events)

  # [INC7c] Planet-breaker capacity (immediate enforcement, 1 per colony)
  logInfo("Economy", "[INC7c] Processing planet-breaker capacity...")
  let pbEnforcement = planet_breakers.processCapacityEnforcement(state, events)

  logInfo("Economy", "[INC7] Complete",
    "fighters=", $fighterEnforcement.len,
    " pbs=", $pbEnforcement.len)

# =============================================================================
# INC8: Collect Resources
# =============================================================================

proc collectResources(
    state: var GameState,
    incomeReport: income_engine.IncomePhaseReport,
) =
  ## [INC8] Store income reports and update colony production fields
  ## Treasury already updated by income_engine.resolveIncomePhase()
  logInfo("Economy", "[INC8] Collecting resources...")

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

  logInfo("Economy", "[INC8] Complete")

# =============================================================================
# INC9: Calculate Prestige
# =============================================================================

proc calculatePrestige(
    state: var GameState,
    incomeReport: income_engine.IncomePhaseReport,
    events: var seq[GameEvent],
) =
  ## [INC9] Apply prestige from economic activities and blockade penalties
  logInfo("Prestige", "[INC9] Calculating prestige...")

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

  logInfo("Prestige", "[INC9] Complete")

# =============================================================================
# INC10a: House Elimination
# =============================================================================

proc processEliminationChecks(
    state: var GameState,
    events: var seq[GameEvent],
): int =
  ## [INC10a] Check and process house eliminations
  ## Standard elimination: no colonies AND no invasion capability
  ## Defensive collapse: prestige below threshold for consecutive turns
  ## Returns count of eliminated houses
  logInfo("Victory", "[INC10a] Checking elimination conditions...")

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
        " turns=", $houseToUpdate.negativePrestigeTurns,
        "/", $defenseCollapseTurns)

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

  logInfo("Victory", "[INC10a] Complete", "eliminated=", $eliminatedCount)
  return eliminatedCount

# =============================================================================
# INC10b: Victory Conditions
# =============================================================================

proc checkVictoryConditions(
    state: var GameState,
    events: var seq[GameEvent],
): victory_engine.VictoryCheck =
  ## [INC10b] Check victory conditions after eliminations processed
  ## Returns victory check result
  logInfo("Victory", "[INC10b] Checking victory conditions...")

  let victoryCondition = VictoryCondition(
    turnLimit: gameSetup.victoryConditions.turnLimit,
    enableDefensiveCollapse: true
  )
  let victoryCheck = victory_engine.checkVictoryConditions(state,
                                                           victoryCondition)

  if victoryCheck.victoryOccurred:
    logInfo("Victory", "*** GAME OVER ***",
      "victor=", $victoryCheck.status.houseId,
      " type=", $victoryCheck.status.victoryType,
      " turn=", $victoryCheck.status.achievedOnTurn)
    # Victory event handled by victory engine

  logInfo("Victory", "[INC10b] Complete")
  return victoryCheck

# =============================================================================
# INC11: Advance Timers
# =============================================================================

proc advanceTimers(state: var GameState, events: var seq[GameEvent]): int =
  ## [INC11] Decrement effect timers, expire diplomatic proposals
  ## Returns count of expired proposals
  logInfo("Income", "[INC11] Advancing timers...")

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
          "id=", $p.id,
          " from=", $p.proposer,
          " to=", $p.target)
        
        # Generate event for proposal expiration
        # Use TreatyBroken event type (proposal expired = treaty opportunity lost)
        let proposalTypeName = case p.proposalType
          of ProposalType.DeescalateToNeutral:
            "De-escalation to Neutral"
          of ProposalType.DeescalateToHostile:
            "De-escalation to Hostile"
        
        events.add(
          event_factory.treatyBroken(
            p.proposer, p.target, proposalTypeName, "Proposal expired without response"
          )
        )

    # Keep recent proposals (10 turn history)
    if p.status == ProposalStatus.Pending or (state.turn - p.submittedTurn) < 10:
      updatedProposals.add(p)

  state.pendingProposals = updatedProposals

  logInfo("Income", "[INC11] Complete",
    "expired=", $expiredCount,
    " remaining=", $state.pendingProposals.len)
  return expiredCount

# =============================================================================
# Main Orchestrator
# =============================================================================

proc resolveIncomePhase*(
    state: var GameState,
    orders: Table[HouseId, CommandPacket],
    events: var seq[GameEvent],
    rng: var Rand,
) =
  ## Phase 2: Income Phase orchestrator
  ##
  ## Executes all income phase steps in canonical order (INC1-11).
  ## Production calculated AFTER Conflict Phase damage.
  ## Salvage executes BEFORE maintenance (don't pay on salvaged fleets).
  logInfo("Income", "=== Income Phase ===", "turn=", $state.turn)

  # INC1: Apply Ongoing Espionage Effects
  discard state.applyOngoingEspionageEffects()

  # INC2: Process EBP/CIP Investment
  discard state.processEBPCIPInvestment(orders, events)

  # INC3: Calculate Base Production (includes blockade application)
  let incomeReport = state.calculateBaseProduction()

  # INC4: Apply Blockades (informational - already in INC3)
  discard state.countBlockadedColonies()

  # INC5: Execute Salvage Commands (BEFORE maintenance!)
  discard state.executeSalvageCommands(orders, events)

  # Administrative completion for Income commands
  logInfo("Income", "[INCOME] Administrative completion for Income commands...")
  fleet_order_execution.performCommandMaintenance(
    state, orders, events, rng,
    fleet_order_execution.isIncomeCommand,
    "Income Phase - Administrative Completion"
  )

  # INC6: Maintenance Processing (AFTER salvage!)
  state.processMaintenancePhase(events)

  # INC7: Capacity Enforcement (7a C2 Pool, 7b Fighter, 7c Planet-Breaker)
  state.enforceCapacityLimits(events)

  # INC8: Collect Resources
  state.collectResources(incomeReport)

  # INC9: Calculate Prestige
  state.calculatePrestige(incomeReport, events)

  # INC10a: House Elimination
  discard state.processEliminationChecks(events)

  # INC10b: Victory Conditions
  discard state.checkVictoryConditions(events)

  # INC11: Advance Timers
  discard state.advanceTimers(events)

  logInfo("Income", "=== Income Phase Complete ===")
