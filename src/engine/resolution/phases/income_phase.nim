## Income Phase Resolution - Phase 2 of Canonical Turn Cycle
##
## Handles all economic calculations, resource collection, and game state evaluation
## after Conflict Phase damage has been applied.
##
## **Canonical Execution Order:**
##
## Step 1: Calculate Base Production (colony GCO → gross PP)
## Step 2: Apply Blockades (reduce GCO for blockaded colonies)
## Step 3: Calculate Maintenance Costs (deduct from gross production → net PP)
## Step 4: Execute Salvage Orders (recover PP from combat wreckage)
## Step 5: Capacity Enforcement (after IU loss from combat/blockades)
##   5a: Capital Squadron Capacity (immediate enforcement, no grace period)
##   5b: Total Squadron Limit (2-turn grace period before auto-disband)
##   5c: Fighter Squadron Capacity (2-turn grace period before auto-disband)
##   5d: Planet-Breaker Enforcement (immediate, colony count limit)
## Step 6: Collect Resources (apply net PP/RP to house treasuries)
## Step 7: Calculate Prestige (award/deduct for turn events)
## Step 8: House Elimination & Victory Checks
##   8a: House Elimination (standard elimination + defensive collapse)
##   8b: Victory Conditions (prestige/elimination/turn limit)
## Step 9: Advance Timers (espionage effects, diplomatic timers, grace periods)
##
## **Key Properties:**
## - Production calculated AFTER Conflict Phase damage (damaged facilities produce less)
## - Blockades established in Conflict Phase affect same turn's production (no delay)
## - Capacity enforcement uses post-blockade/post-combat IU values
## - Elimination checks happen AFTER prestige calculation (Step 7)
## - Victory checks happen AFTER elimination processing (Step 8a)

import std/[tables, options, random, sequtils, hashes, math, strutils, strformat]
import ../../../common/[hex, types/core, types/units, types/tech]
import ../../gamestate, ../../orders, ../../fleet, ../../squadron, ../../spacelift
import ../../starmap, ../../logger
import ../../order_types
import ../../economy/[types as econ_types, engine as econ_engine, projects, facility_queue]
import ../../economy/capacity/fighter as fighter_capacity
import ../../economy/capacity/planet_breakers as planet_breaker_capacity
import ../../economy/capacity/capital_squadrons as capital_squadron_capacity
import ../../economy/capacity/total_squadrons as total_squadron_capacity
import ../../research/[types as res_types, costs as res_costs, advancement]
import ../../espionage/[types as esp_types]
import ../../blockade/engine as blockade_engine
import ../../intelligence/[
  detection, types as intel_types, generator as intel_gen,
  starbase_surveillance, scout_intel
]
import ../../config/[espionage_config, construction_config, gameplay_config]
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

  # Build house tax policies from House state
  var houseTaxPolicies = initTable[HouseId, econ_types.TaxPolicy]()
  for houseId, house in state.houses:
    houseTaxPolicies[houseId] = house.taxPolicy

  # Build house tech levels (Economic Level = economicLevel field)
  var houseTechLevels = initTable[HouseId, int]()
  for houseId, house in state.houses:
    houseTechLevels[houseId] = house.techTree.levels.economicLevel  # EL = economicLevel (confusing naming)

  # Build house CST tech levels (Construction = constructionTech field)
  var houseCSTTechLevels = initTable[HouseId, int]()
  for houseId, house in state.houses:
    houseCSTTechLevels[houseId] = house.techTree.levels.constructionTech

  # Build house treasuries
  var houseTreasuries = initTable[HouseId, int]()
  for houseId, house in state.houses:
    houseTreasuries[houseId] = house.treasury

  # ===================================================================
  # STEP 4: EXECUTE SALVAGE ORDERS
  # ===================================================================
  # Salvage orders execute in Income Phase (not Command Phase) because:
  # 1. Fleet must survive Conflict Phase to salvage wreckage
  # 2. Salvage is an economic operation (ships → PP)
  # 3. Salvage PP should be included in turn's treasury before income calculation
  logDebug(LogCategory.lcEconomy, "[SALVAGE] Executing salvage orders...")

  for houseId in state.houses.keys:
    if houseId in orders:
      for order in orders[houseId].fleetOrders:
        if order.orderType == FleetOrderType.Salvage:
          # Check if fleet still exists (survived Conflict Phase)
          if order.fleetId in state.fleets:
            let fleet = state.fleets[order.fleetId]
            if fleet.owner == houseId:
              # Execute salvage order (returns PP added to treasury, events added directly)
              let outcome = cmd_executor.executeFleetOrder(state, houseId, order, events)
              if outcome == OrderOutcome.Success:
                logInfo(LogCategory.lcEconomy,
                  &"[SALVAGE] {houseId} Fleet-{order.fleetId} salvaged ships")
                # PP already added to treasury by executeSalvageOrder
              else:
                logDebug(LogCategory.lcEconomy,
                  &"[SALVAGE] {houseId} Fleet-{order.fleetId} failed")

  logDebug(LogCategory.lcEconomy, "[SALVAGE] Completed salvage orders")

  # ===================================================================
  # STEP 5: CAPACITY ENFORCEMENT AFTER IU LOSS
  # ===================================================================
  # Per FINAL_TURN_SEQUENCE.md Income Phase Step 5
  # Enforce capacity limits AFTER IU loss from blockades/combat
  # Order: Capital squadrons (immediate) → Total squadrons (2-turn grace) →
  #        Fighters (2-turn grace) → Planet-breakers (immediate)
  logDebug(LogCategory.lcEconomy,
          "[CAPACITY ENFORCEMENT] Checking capacity violations after IU loss...")

  # Check fighter squadron capacity violations (assets.md:2.4.1)
  # Uses unified capacity management system (economy/capacity/fighter.nim)
  # 2-turn grace period per colony
  logDebug(LogCategory.lcEconomy,
          "[CAPACITY] Checking fighter squadron capacity...")
  let fighterEnforcement = fighter_capacity.processCapacityEnforcement(state)
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
    capital_squadron_capacity.processCapacityEnforcement(state)
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
    total_squadron_capacity.processCapacityEnforcement(state)
  for action in totalEnforcement:
    if action.affectedUnits.len > 0:
      let houseId = HouseId(action.entityId)
      events.add(event_factory.unitDisbanded(
        houseId,
        "Squadron",
        action.description,
        none(SystemId)
      ))

  logDebug(LogCategory.lcEconomy,
          "[CAPACITY ENFORCEMENT] Completed capacity enforcement")

  # ===================================================================
  # STEP 1 & 3: ECONOMY ENGINE (Production + Maintenance)
  # ===================================================================
  # Economy engine calculates:
  # - Step 1: Base production (PP/RP from colonies, improvements, modifiers)
  # - Step 3: Maintenance costs (deducted from treasuries)
  logInfo(LogCategory.lcEconomy, &"[INCOME STEP 1 & 3] Running economy engine (production + maintenance)...")

  # Call economy engine
  let incomeReport = econ_engine.resolveIncomePhase(
    coloniesSeqIncome,
    houseTaxPolicies,
    houseTechLevels,
    houseCSTTechLevels,
    houseTreasuries
  )

  logInfo(LogCategory.lcEconomy, &"[INCOME STEP 1 & 3] Economy engine completed")

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
  var eliminatedCount = 0

  for houseId, house in state.houses:
    # Standard elimination: no colonies and no invasion capability
    let colonies = state.getHouseColonies(houseId)
    let fleets = state.getHouseFleets(houseId)

    if colonies.len == 0:
      # No colonies - check if house has invasion capability
      # (marines on transports)
      var hasInvasionCapability = false

      for fleet in fleets:
        for transport in fleet.spaceLiftShips:
          if transport.cargo.cargoType == CargoType.Marines and
             transport.cargo.quantity > 0:
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

    if house.prestige <
       gameplayConfig.elimination.defensive_collapse_threshold:
      houseToUpdate.negativePrestigeTurns += 1
      logWarn(LogCategory.lcGeneral,
        &"{house.name} at risk: prestige {house.prestige} " &
        &"({houseToUpdate.negativePrestigeTurns}/" &
        &"{gameplayConfig.elimination.defensive_collapse_turns} turns " &
        &"until elimination)")

      if houseToUpdate.negativePrestigeTurns >=
         gameplayConfig.elimination.defensive_collapse_turns:
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

  # Construction/repair advancement REMOVED from Income Phase
  # Per FINAL_TURN_SEQUENCE.md:
  # - Maintenance Phase: Construction queues advance, projects marked complete
  # - Command Phase Part A: Completed projects commissioned
  # This separation ensures proper 1-turn delay between completion and commissioning

  # Process research allocation
  # Per economy.md:4.0: Players allocate PP to research each turn
  # PP is converted to ERP/SRP/TRP based on current tech levels and GHO
  for houseId in state.houses.keys:
    if houseId in orders:
      let packet = orders[houseId]
      let allocation = packet.researchAllocation

      # Calculate total PP cost for this research allocation
      var totalResearchCost = allocation.economic + allocation.science
      for field, pp in allocation.technology:
        totalResearchCost += pp

      # Scale down research allocation if treasury cannot afford it
      # Research is planned at AI time but processed after Income Phase
      # This prevents negative treasury from over-aggressive research budgets
      var scaledAllocation = allocation

      # CRITICAL: If treasury is negative or zero, no research happens
      if state.houses[houseId].treasury <= 0:
        # Zero out all research - house is bankrupt
        scaledAllocation.economic = 0
        scaledAllocation.science = 0
        scaledAllocation.technology = initTable[TechField, int]()
        totalResearchCost = 0

        logWarn(LogCategory.lcResearch,
          &"{houseId} research cancelled - negative treasury ({state.houses[houseId].treasury} PP)")

      elif totalResearchCost > state.houses[houseId].treasury:
        # Calculate scaling factor (how much we can actually afford)
        let affordablePercent = float(state.houses[houseId].treasury) / float(totalResearchCost)

        # Scale all allocations proportionally
        scaledAllocation.economic = int(float(allocation.economic) * affordablePercent)
        scaledAllocation.science = int(float(allocation.science) * affordablePercent)

        var scaledTech = initTable[TechField, int]()
        for field, pp in allocation.technology:
          scaledTech[field] = int(float(pp) * affordablePercent)
        scaledAllocation.technology = scaledTech

        # Recalculate actual cost
        totalResearchCost = scaledAllocation.economic + scaledAllocation.science
        for field, pp in scaledAllocation.technology:
          totalResearchCost += pp

        logWarn(LogCategory.lcResearch,
          &"{houseId} research budget scaled down by {int(affordablePercent * 100)}% due to treasury constraints")

      # Deduct research cost from treasury (CRITICAL FIX)
      # Research competes with builds for treasury resources
      if totalResearchCost > 0:
        state.houses[houseId].treasury -= totalResearchCost
        logInfo(LogCategory.lcResearch,
          &"{houseId} spent {totalResearchCost} PP on research " &
          &"(treasury: {state.houses[houseId].treasury + totalResearchCost} → {state.houses[houseId].treasury})")

      # Calculate GHO for this house
      var gho = 0
      for colony in state.colonies.values:
        if colony.owner == houseId:
          gho += colony.production

      # Get current tech levels
      let currentSL = state.houses[houseId].techTree.levels.scienceLevel  # Science Level

      # Convert PP allocations to RP (use SCALED allocation, not original)
      let earnedRP = res_costs.allocateResearch(scaledAllocation, gho, currentSL)

      # Accumulate RP
      state.houses[houseId].techTree.accumulated.economic += earnedRP.economic
      state.houses[houseId].techTree.accumulated.science += earnedRP.science

      for field, trp in earnedRP.technology:
        if field notin state.houses[houseId].techTree.accumulated.technology:
          state.houses[houseId].techTree.accumulated.technology[field] = 0
        state.houses[houseId].techTree.accumulated.technology[field] += trp

      # Save earned RP to House state for diagnostics tracking
      state.houses[houseId].lastTurnResearchERP = earnedRP.economic
      state.houses[houseId].lastTurnResearchSRP = earnedRP.science
      var totalTRP = 0
      for field, trp in earnedRP.technology:
        totalTRP += trp
      state.houses[houseId].lastTurnResearchTRP = totalTRP

      # Log allocations (use SCALED allocation for accurate reporting)
      if scaledAllocation.economic > 0:
        logDebug(LogCategory.lcResearch,
          &"{houseId} allocated {scaledAllocation.economic} PP → {earnedRP.economic} ERP " &
          &"(total: {state.houses[houseId].techTree.accumulated.economic} ERP)")
      if scaledAllocation.science > 0:
        logDebug(LogCategory.lcResearch,
          &"{houseId} allocated {scaledAllocation.science} PP → {earnedRP.science} SRP " &
          &"(total: {state.houses[houseId].techTree.accumulated.science} SRP)")
      for field, pp in scaledAllocation.technology:
        if pp > 0 and field in earnedRP.technology:
          let totalTRP = state.houses[houseId].techTree.accumulated.technology.getOrDefault(field, 0)
          logDebug(LogCategory.lcResearch,
            &"{houseId} allocated {pp} PP → {earnedRP.technology[field]} TRP ({field}) (total: {totalTRP} TRP)")

  # Tech advancement happens in resolveCommandPhase (not here)
  # Per economy.md:4.1: Tech upgrades can be purchased every turn if RP is available

  # Research breakthroughs (every 5 turns)
  # Per economy.md:4.1.1: Breakthrough rolls provide bonus RP, cost reductions, or free levels
  if advancement.isBreakthroughTurn(state.turn):
    logDebug(LogCategory.lcResearch, &"[RESEARCH BREAKTHROUGHS] Turn {state.turn} - rolling for breakthroughs")
    for houseId in state.houses.keys:
      # Calculate total RP invested in last 5 turns
      # NOTE: This is a simplified approximation - proper implementation would track historical RP
      let investedRP = state.houses[houseId].lastTurnResearchERP +
                       state.houses[houseId].lastTurnResearchSRP +
                       state.houses[houseId].lastTurnResearchTRP

      # Roll for breakthrough
      var rng = initRand(hash(state.turn) xor hash(houseId))
      let breakthroughOpt = advancement.rollBreakthrough(investedRP * 5, rng)  # Approximate 5-turn total

      if breakthroughOpt.isSome:
        let breakthrough = breakthroughOpt.get
        logInfo(LogCategory.lcResearch, &"{houseId} BREAKTHROUGH: {breakthrough}")

        # Apply breakthrough effects
        let allocation = res_types.ResearchAllocation(
          economic: state.houses[houseId].lastTurnResearchERP,
          science: state.houses[houseId].lastTurnResearchSRP,
          technology: initTable[TechField, int]()
        )
        let event = advancement.applyBreakthrough(
          state.houses[houseId].techTree,
          breakthrough,
          allocation
        )

        logDebug(LogCategory.lcResearch, &"{houseId} breakthrough effect applied (category: {event.category})")
