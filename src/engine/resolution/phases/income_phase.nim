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

import std/[tables, options, random, sequtils, hashes, math, strutils, strformat]
import ../../../common/[hex, types/core, types/units, types/tech]
import ../../gamestate, ../../orders, ../../fleet, ../../squadron
import ../../starmap, ../../logger
import ../../order_types
import ../../economy/[types as econ_types, engine as econ_engine, projects, facility_queue]
import ../../economy/capacity/fighter as fighter_capacity
import ../../economy/capacity/planet_breakers as planet_breaker_capacity
import ../../economy/capacity/capital_squadrons as capital_squadron_capacity
import ../../economy/capacity/total_squadrons as total_squadron_capacity
import ../../research/[types as res_types, costs as res_costs, advancement]
import ../../espionage/[types as esp_types]
import ../../diplomacy/[proposals as dip_proposals]
import ../../blockade/engine as blockade_engine
import ../../intelligence/[
  detection, types as intel_types, generator as intel_gen,
  starbase_surveillance, scout_intel
]
import ../../config/[espionage_config, construction_config, gameplay_config, economy_config]
import ../../resolution/[fleet_orders, automation, types as res_game_types]
import ../../resolution/event_factory/init as event_factory
import ../../commands/executor as cmd_executor  # For salvage order execution
import ../../prestige/[types as prestige_types, events as prestige_events, application as prestige_app]

proc resolveIncomePhase*(
  state: var GameState,
  orders: Table[HouseId, OrderPacket],
  events: var seq[GameEvent]
) =
  ## Phase 2: Collect income and allocate resources
  ## Production is calculated AFTER conflict, so damaged infrastructure produces less
  ## Also applies ongoing espionage effects (SRP/NCV/Tax reductions)
  logDebug(LogCategory.lcGeneral, &"[Income Phase]")

  # ===================================================================
  # STEP 0: APPLY ONGOING ESPIONAGE EFFECTS
  # ===================================================================
  # Per diplomacy.md:8.2 - Active espionage effects modify production/intel
  logInfo(LogCategory.lcGeneral, "[INCOME STEP 0] Applying ongoing espionage effects...")

  # Apply ongoing espionage effects to houses
  var activeEffects: seq[esp_types.OngoingEffect] = @[]
  for effect in state.ongoingEffects:
    if effect.turnsRemaining > 0:
      activeEffects.add(effect)

      case effect.effectType
      of esp_types.EffectType.SRPReduction:
        logDebug(LogCategory.lcGeneral,
          &"{effect.targetHouse} affected by SRP reduction (-{int(effect.magnitude * 100)}%)")
      of esp_types.EffectType.NCVReduction:
        logDebug(LogCategory.lcGeneral,
          &"{effect.targetHouse} affected by NCV reduction (-{int(effect.magnitude * 100)}%)")
      of esp_types.EffectType.TaxReduction:
        logDebug(LogCategory.lcGeneral,
          &"{effect.targetHouse} affected by tax reduction (-{int(effect.magnitude * 100)}%)")
      of esp_types.EffectType.StarbaseCrippled:
        if effect.targetSystem.isSome:
          let systemId = effect.targetSystem.get()
          logDebug(LogCategory.lcGeneral, &"Starbase at system-{systemId} is crippled")

          # Apply crippled state to starbase in colony
          if systemId in state.colonies:
            var colony = state.colonies[systemId]
            if colony.owner == effect.targetHouse:
              for starbase in colony.starbases.mitems:
                if not starbase.isCrippled:
                  starbase.isCrippled = true
                  logDebug(LogCategory.lcGeneral, &"Applied crippled state to starbase {starbase.id}")
              state.colonies[systemId] = colony
      of esp_types.EffectType.IntelBlocked:
        logDebug(LogCategory.lcGeneral, &"{effect.targetHouse} protected by counter-intelligence sweep")
      of esp_types.EffectType.IntelCorrupted:
        logDebug(LogCategory.lcGeneral,
          &"{effect.targetHouse}'s intelligence corrupted by disinformation (+/-{int(effect.magnitude * 100)}% variance)")

  state.ongoingEffects = activeEffects

  # ===================================================================
  # STEP 0b: PROCESS EBP/CIP INVESTMENT
  # ===================================================================
  # Per diplomacy.md:8.2 - Purchase EBP/CIP at 40 PP each
  # Over-investment penalty: lose 1 prestige per 1% over 5% threshold
  logInfo(LogCategory.lcEconomy, "[INCOME STEP 0b] Processing EBP/CIP purchases...")

  # Process EBP/CIP purchases (diplomacy.md:8.2)
  # EBP and CIP cost 40 PP each
  # Over-investment penalty: lose 1 prestige per 1% over 5% of turn budget
  for houseId in state.houses.keys:
    if houseId in orders:
      let packet = orders[houseId]

      if packet.ebpInvestment > 0 or packet.cipInvestment > 0:
        let ebpCost = packet.ebpInvestment * globalEspionageConfig.costs.ebp_cost_pp
        let cipCost = packet.cipInvestment * globalEspionageConfig.costs.cip_cost_pp
        let totalCost = ebpCost + cipCost

        # Deduct from treasury
        if state.houses[houseId].treasury >= totalCost:
          state.houses[houseId].treasury -= totalCost
          state.houses[houseId].espionageBudget.ebpPoints += packet.ebpInvestment
          state.houses[houseId].espionageBudget.cipPoints += packet.cipInvestment
          state.houses[houseId].espionageBudget.ebpInvested = ebpCost
          state.houses[houseId].espionageBudget.cipInvested = cipCost

          logInfo(LogCategory.lcEconomy,
            &"{houseId} purchased {packet.ebpInvestment} EBP, {packet.cipInvestment} CIP ({totalCost} PP)")

          # Check for over-investment penalty (configurable threshold from espionage.toml)
          let turnBudget = state.houses[houseId].espionageBudget.turnBudget
          if turnBudget > 0:
            let totalInvestment = ebpCost + cipCost
            let investmentPercent = (totalInvestment * 100) div turnBudget
            let threshold = globalEspionageConfig.investment.threshold_percentage

            if investmentPercent > threshold:
              let prestigePenalty = -(investmentPercent - threshold) * globalEspionageConfig.investment.penalty_per_percent
              let prestigeEvent = prestige_events.createPrestigeEvent(
                prestige_types.PrestigeSource.HighTaxPenalty,
                prestigePenalty,
                &"Over-investment penalty: -{int(prestigePenalty * -1)} (investment {investmentPercent}% exceeds {threshold}% threshold)"
              )
              prestige_app.applyPrestigeEvent(state, houseId, prestigeEvent)
              logWarn(LogCategory.lcEconomy, &"Over-investment penalty: {prestigePenalty} prestige")
        else:
          logError(LogCategory.lcEconomy, &"{houseId} insufficient funds for EBP/CIP purchase")


  # ===================================================================
  # STEP 1: CALCULATE BASE PRODUCTION
  # ===================================================================
  logInfo(LogCategory.lcEconomy, &"[INCOME STEP 1] Calculating base production...")

  # Convert colonies table to sequence for income phase
  # NOTE: No type conversion needed - gamestate.Colony has all economic fields
  var coloniesSeqIncome: seq[Colony] = @[]
  for systemId, colony in state.colonies:
    coloniesSeqIncome.add(colony)

  # Build house data tables in single pass (optimization: 4 loops → 1 loop)
  var houseTaxPolicies = initTable[HouseId, econ_types.TaxPolicy]()
  var houseTechLevels = initTable[HouseId, int]()
  var houseCSTTechLevels = initTable[HouseId, int]()
  var houseTreasuries = initTable[HouseId, int]()

  for houseId, house in state.houses:
    houseTaxPolicies[houseId] = house.taxPolicy
    houseTechLevels[houseId] = house.techTree.levels.economicLevel  # EL = economicLevel (confusing naming)
    houseCSTTechLevels[houseId] = house.techTree.levels.constructionTech
    houseTreasuries[houseId] = house.treasury

  # Call economy engine with natural growth rate from config
  let incomeReport = econ_engine.resolveIncomePhase(
    coloniesSeqIncome,
    houseTaxPolicies,
    houseTechLevels,
    houseCSTTechLevels,
    houseTreasuries,
    baseGrowthRate = globalEconomyConfig.population.natural_growth_rate
  )

  logInfo(LogCategory.lcEconomy, &"[INCOME STEP 1] Production calculation completed")

  # ===================================================================
  # STEP 2: APPLY BLOCKADES (from Conflict Phase)
  # ===================================================================
  # Per operations.md:6.2.6: "Blockades established during the Conflict Phase
  # reduce GCO for that same turn's Income Phase calculation - there is no delay"
  logInfo(LogCategory.lcEconomy, &"[INCOME STEP 2] Applying blockade penalties...")
  blockade_engine.applyBlockades(state)

  var blockadeCount = 0
  for systemId, colony in state.colonies:
    if colony.blockaded:
      blockadeCount += 1
  logInfo(LogCategory.lcEconomy, &"[INCOME STEP 2] Completed ({blockadeCount} colonies blockaded)")

  # ===================================================================
  # STEP 3: CALCULATE AND DEDUCT MAINTENANCE UPKEEP
  # ===================================================================
  # Per canonical turn cycle: Calculate maintenance for surviving ships/facilities
  # after Conflict Phase, deduct from treasuries before collecting resources
  logInfo(LogCategory.lcEconomy, &"[INCOME STEP 3] Calculating maintenance upkeep...")

  let maintenanceUpkeepByHouse = econ_engine.calculateAndDeductMaintenanceUpkeep(state, events)

  # Log maintenance costs for diagnostics
  for houseId, upkeepCost in maintenanceUpkeepByHouse:
    logInfo(LogCategory.lcEconomy, &"  {houseId}: {upkeepCost} PP maintenance")

  logInfo(LogCategory.lcEconomy, &"[INCOME STEP 3] Maintenance upkeep completed")

  # ===================================================================
  # STEP 4: EXECUTE SALVAGE ORDERS
  # ===================================================================
  # Salvage orders execute in Income Phase (not Command Phase) because:
  # 1. Fleet must survive Conflict Phase to salvage wreckage
  # 2. Salvage is an economic operation (ships → PP)
  # 3. Salvage PP should be included in turn's treasury before income calculation
  # 4. Fleet must have arrived at target (checked via arrivedFleets)
  logInfo(LogCategory.lcEconomy, "[INCOME STEP 4] Executing salvage orders...")

  for houseId in state.houses.keys:
    if houseId in orders:
      for order in orders[houseId].fleetOrders:
        if order.orderType == FleetOrderType.Salvage:
          # Check if fleet still exists (survived Conflict Phase)
          if order.fleetId in state.fleets:
            let fleet = state.fleets[order.fleetId]
            if fleet.owner == houseId:
              # Check if fleet has arrived at target
              if order.fleetId notin state.arrivedFleets:
                logDebug(LogCategory.lcEconomy,
                  &"[SALVAGE] Fleet {order.fleetId} has not arrived at target, skipping")
                continue

              # Execute salvage order (returns PP added to treasury, events added directly)
              let outcome = cmd_executor.executeFleetOrder(state, houseId, order, events)
              if outcome == OrderOutcome.Success:
                logInfo(LogCategory.lcEconomy,
                  &"[SALVAGE] {houseId} Fleet-{order.fleetId} salvaged ships")
                # PP already added to treasury by executeSalvageOrder
                # Clear arrival status
                if order.fleetId in state.arrivedFleets:
                  state.arrivedFleets.del(order.fleetId)
                  logDebug(LogCategory.lcEconomy, &"  Cleared arrival status for fleet {order.fleetId}")
              else:
                logDebug(LogCategory.lcEconomy,
                  &"[SALVAGE] {houseId} Fleet-{order.fleetId} failed")

  logInfo(LogCategory.lcEconomy, "[INCOME STEP 4] Completed salvage orders")

  # ===================================================================
  # STEP 5: CAPACITY ENFORCEMENT AFTER IU LOSS
  # ===================================================================
  # Per FINAL_TURN_SEQUENCE.md Income Phase Step 5
  # Enforce capacity limits AFTER IU loss from blockades/combat
  # Order: Capital squadrons (immediate) → Total squadrons (2-turn grace) →
  #        Fighters (2-turn grace) → Planet-breakers (immediate)
  logInfo(LogCategory.lcEconomy,
          "[INCOME STEP 5] Checking capacity violations after IU loss...")

  # Check fighter squadron capacity violations (assets.md:2.4.1)
  # Uses unified capacity management system (economy/capacity/fighter.nim)
  # 2-turn grace period per colony
  logDebug(LogCategory.lcEconomy,
          "[CAPACITY] Checking fighter squadron capacity...")
  let fighterEnforcement = fighter_capacity.processCapacityEnforcement(state, events)
  for action in fighterEnforcement:
    if action.affectedUnits.len > 0:
      let colonyId = SystemId(parseInt(action.entityId))
      if colonyId in state.colonies:
        let houseId = state.colonies[colonyId].owner
        events.add(event_factory.unitDisbanded(
          houseId,
          "Fighter Squadron",
          action.description,
          some(colonyId)
        ))

  # Check planet-breaker capacity violations (assets.md:2.4.8)
  # Immediate enforcement (no grace period)
  logDebug(LogCategory.lcEconomy,
          "[CAPACITY] Checking planet-breaker capacity...")
  let pbEnforcement =
    planet_breaker_capacity.processCapacityEnforcement(state)
  for action in pbEnforcement:
    if action.affectedUnits.len > 0:
      let houseId = HouseId(action.entityId)
      events.add(event_factory.unitDisbanded(
        houseId,
        "Planet-Breaker",
        action.description,
        none(SystemId)
      ))

  # Check capital squadron capacity violations (reference.md Table 10.5)
  # Immediate Space Guild seizure (no grace period)
  logDebug(LogCategory.lcEconomy,
          "[CAPACITY] Checking capital squadron capacity...")
  let capitalEnforcement =
    capital_squadron_capacity.processCapacityEnforcement(state, events)
  for action in capitalEnforcement:
    if action.affectedUnits.len > 0:
      let houseId = HouseId(action.entityId)
      events.add(event_factory.unitDisbanded(
        houseId,
        "Capital Squadron",
        action.description,
        none(SystemId)
      ))

  # Check total squadron capacity (prevents escort spam)
  # 2-turn grace period (house-wide)
  # Runs AFTER capital squadron enforcement
  logDebug(LogCategory.lcEconomy,
          "[CAPACITY] Checking total squadron capacity...")
  let totalEnforcement =
    total_squadron_capacity.processCapacityEnforcement(state, events)
  for action in totalEnforcement:
    if action.affectedUnits.len > 0:
      let houseId = HouseId(action.entityId)
      events.add(event_factory.unitDisbanded(
        houseId,
        "Squadron",
        action.description,
        none(SystemId)
      ))

  logInfo(LogCategory.lcEconomy,
          "[INCOME STEP 5] Completed capacity enforcement")

  # ===================================================================
  # STEP 6: COLLECT RESOURCES
  # ===================================================================
  logInfo(LogCategory.lcEconomy, &"[INCOME STEP 6] Collecting resources and applying to treasuries...")

  # Write back modified colonies (population growth was applied in-place)
  # CRITICAL: Colonies were copied to seq, modified via mpairs, must write back to persist
  for colony in coloniesSeqIncome:
    state.colonies[colony.systemId] = colony

  # Apply results back to game state
  for houseId, houseReport in incomeReport.houseReports:
    # CRITICAL: Get house once, modify all fields, write back to persist
    var house = state.houses[houseId]
    house.treasury = houseTreasuries[houseId]
    # Store income report for intelligence gathering (HackStarbase missions)
    house.latestIncomeReport = some(houseReport)
    logInfo(LogCategory.lcEconomy,
      &"{house.name}: +{houseReport.totalNet} PP (Gross: {houseReport.totalGross})")

    # Update colony production fields from income reports
    for colonyReport in houseReport.colonies:
      if colonyReport.colonyId in state.colonies:
        # CRITICAL: Get colony, modify, write back to persist
        var colony = state.colonies[colonyReport.colonyId]
        colony.production = colonyReport.grossOutput
        state.colonies[colonyReport.colonyId] = colony

    # ===================================================================
    # STEP 7: CALCULATE PRESTIGE
    # ===================================================================
    # Apply prestige events from economic activities
    for event in houseReport.prestigeEvents:
      prestige_app.applyPrestigeEvent(state, houseId, event)
      let sign = if event.amount > 0: "+" else: ""
      logDebug(LogCategory.lcEconomy,
        &"Prestige: {sign}{event.amount} ({event.description}) → {state.houses[houseId].prestige}")

    # Write back modified house
    state.houses[houseId] = house

    # Apply blockade prestige penalties
    # Per operations.md:6.2.6: "-2 prestige per colony under blockade"
    let blockadePenalty = blockade_engine.calculateBlockadePrestigePenalty(state, houseId)
    if blockadePenalty < 0:
      let blockadedCount = blockade_engine.getBlockadedColonies(state, houseId).len
      let blockadePenaltyEvent = prestige_events.createPrestigeEvent(
        prestige_types.PrestigeSource.BlockadePenalty,
        blockadePenalty,
        &"{blockadedCount} colonies under blockade ({blockadePenalty} prestige per colony)"
      )
      prestige_app.applyPrestigeEvent(state, houseId, blockadePenaltyEvent)
      logWarn(LogCategory.lcEconomy,
        &"Prestige: {blockadePenalty} ({blockadedCount} colonies under blockade) → {state.houses[houseId].prestige}")

  logInfo(LogCategory.lcEconomy, &"[INCOME STEP 6 & 7] Resources collected, prestige calculated")

  # ===================================================================
  # STEP 8: CHECK ELIMINATION & VICTORY CONDITIONS
  # ===================================================================
  # Per canonical turn cycle: Elimination and victory checks happen in Income Phase Step 8
  # Step 8a: House elimination checks (standard elimination + defensive collapse)
  # Step 8b: Victory condition checks (after eliminations processed)
  logInfo(LogCategory.lcGeneral, &"[INCOME STEP 8a] Checking elimination conditions...")

  let gameplayConfig = globalGameplayConfig
  let defensiveCollapseThreshold = gameplayConfig.elimination.defensive_collapse_threshold
  let defensiveCollapseTurns = gameplayConfig.elimination.defensive_collapse_turns
  var eliminatedCount = 0

  for houseId, house in state.houses:
    # Standard elimination: no colonies and no invasion capability
    # Use indices for O(1) lookup instead of O(c) and O(f) scans
    let colonies = if houseId in state.coloniesByOwner: state.coloniesByOwner[houseId] else: @[]

    var fleets: seq[Fleet] = @[]
    if houseId in state.fleetsByOwner:
      for fleetId in state.fleetsByOwner[houseId]:
        if fleetId in state.fleets:
          fleets.add(state.fleets[fleetId])

    if colonies.len == 0:
      # No colonies - check if house has invasion capability
      # (marines on Auxiliary squadrons)
      var hasInvasionCapability = false

      for fleet in fleets:
        for squadron in fleet.squadrons:
          if squadron.squadronType == SquadronType.Auxiliary:
            if squadron.flagship.cargo.isSome:
              let cargo = squadron.flagship.cargo.get()
              if cargo.cargoType == CargoType.Marines and cargo.quantity > 0:
                hasInvasionCapability = true
                break
        if hasInvasionCapability:
          break

      # Eliminate if no fleets OR no loaded transports with marines
      if fleets.len == 0 or not hasInvasionCapability:
        # CRITICAL: Get, modify, write back to persist
        var houseToUpdate = state.houses[houseId]
        houseToUpdate.eliminated = true
        state.houses[houseId] = houseToUpdate
        eliminatedCount += 1

        let reason = if fleets.len == 0:
          "no remaining forces"
        else:
          "no marines for reconquest"

        events.add(event_factory.houseEliminated(
          houseId,
          HouseId("unknown")  # No specific eliminator for standard elimination
        ))
        logInfo(LogCategory.lcGeneral,
          &"{house.name} eliminated! ({reason})")
        continue

    # Defensive collapse: prestige < threshold for consecutive turns
    # CRITICAL: Get house once, modify elimination/counter, write back
    var houseToUpdate = state.houses[houseId]

    if house.prestige < defensiveCollapseThreshold:
      houseToUpdate.negativePrestigeTurns += 1
      logWarn(LogCategory.lcGeneral,
        &"{house.name} at risk: prestige {house.prestige} " &
        &"({houseToUpdate.negativePrestigeTurns}/" &
        &"{defensiveCollapseTurns} turns " &
        &"until elimination)")

      if houseToUpdate.negativePrestigeTurns >= defensiveCollapseTurns:
        houseToUpdate.eliminated = true
        houseToUpdate.status = HouseStatus.DefensiveCollapse
        eliminatedCount += 1
        events.add(event_factory.houseEliminated(
          houseId,
          HouseId("defensive_collapse")  # Self-elimination from negative prestige
        ))
        logInfo(LogCategory.lcGeneral,
          &"{house.name} eliminated by defensive collapse!")
    else:
      # Reset counter when prestige recovers
      houseToUpdate.negativePrestigeTurns = 0

    # Write back modified house
    state.houses[houseId] = houseToUpdate

  logInfo(LogCategory.lcGeneral, &"[INCOME STEP 8a] Elimination checks completed ({eliminatedCount} houses eliminated)")

  # Step 8b: Check victory conditions (after eliminations are processed)
  logInfo(LogCategory.lcGeneral, &"[INCOME STEP 8b] Checking victory conditions...")
  let victorOpt = state.checkVictoryCondition()
  if victorOpt.isSome:
    let victorId = victorOpt.get()
    state.phase = GamePhase.Completed

    var victorName = "Unknown"
    for houseId, house in state.houses:
      if house.id == victorId:
        victorName = house.name
        break

    logInfo(LogCategory.lcGeneral,
      &"*** {victorName} has won the game! ***")

  # ===================================================================
  # STEP 9: ADVANCE TIMERS
  # ===================================================================
  logInfo(LogCategory.lcOrders, "[INCOME STEP 9] Advancing timers...")

  # Decrement ongoing espionage effect counters
  var remainingEffects: seq[esp_types.OngoingEffect] = @[]
  for effect in state.ongoingEffects:
    var updatedEffect = effect
    updatedEffect.turnsRemaining -= 1

    if updatedEffect.turnsRemaining > 0:
      remainingEffects.add(updatedEffect)
      logDebug(LogCategory.lcGeneral,
        &"Effect on {updatedEffect.targetHouse} expires in " &
        &"{updatedEffect.turnsRemaining} turn(s)")
    else:
      logDebug(LogCategory.lcGeneral,
        &"Effect on {updatedEffect.targetHouse} has expired")

  state.ongoingEffects = remainingEffects

  # Expire pending diplomatic proposals
  for proposal in state.pendingProposals.mitems:
    if proposal.status == dip_proposals.ProposalStatus.Pending:
      proposal.expiresIn -= 1

      if proposal.expiresIn <= 0:
        proposal.status = dip_proposals.ProposalStatus.Expired
        logDebug(LogCategory.lcGeneral,
          &"Proposal {proposal.id} expired ({proposal.proposer} → " &
          &"{proposal.target})")

  # Clean up old proposals (keep 10 turn history)
  let currentTurn = state.turn
  state.pendingProposals.keepIf(proc(p: dip_proposals.PendingProposal): bool =
    p.status == dip_proposals.ProposalStatus.Pending or
    (currentTurn - p.submittedTurn) < 10
  )

  logInfo(LogCategory.lcOrders, "[INCOME STEP 9] Completed advancing timers")
