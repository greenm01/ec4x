## Income Phase Resolution - Phase 0A
##
## This module handles the Income Phase (Phase 2) of turn resolution:
## - Blockade status application
## - Ongoing espionage effects (SRP/NCV/Tax reductions, starbase crippling)
## - EBP/CIP point purchases with over-investment penalties
## - Spy scout detection and intelligence gathering
## - Starbase surveillance (continuous monitoring)
## - Income collection via economy engine
## - Construction completion and ship commissioning
## - Repair queue processing
## - Research allocation (PP to RP conversion)
## - Research breakthroughs (every 5 turns)
##
## Per operations.md: Production is calculated AFTER conflict, so damaged
## infrastructure produces less. Blockades established during Conflict Phase
## reduce GCO for the same turn's Income Phase with no delay.

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
import ../../config/[espionage_config, construction_config]
import ../../resolution/[fleet_orders, automation, types as res_game_types]
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

  # Apply blockade status to all colonies
  # Per operations.md:6.2.6: "Blockades established during the Conflict Phase
  # reduce GCO for that same turn's Income Phase calculation - there is no delay"
  blockade_engine.applyBlockades(state)

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

  # Process spy scout detection and intelligence gathering
  # Per assets.md:2.4.2: "For every turn that a spy Scout operates in unfriendly
  # system occupied by rival ELI, the rival will roll on the Spy Detection Table"
  var survivingScouts = initTable[string, SpyScout]()

  for scoutId, scout in state.spyScouts:
    if scout.detected:
      # Scout was detected in a previous turn
      continue

    var wasDetected = false
    let scoutLocation = scout.location

    # Check if system has rival ELI units (fleets with scouts or starbases)
    # Get all houses in the system (from fleets and colonies)
    var housesInSystem: seq[HouseId] = @[]

    # Check for colonies (starbases provide detection)
    if scoutLocation in state.colonies:
      let colony = state.colonies[scoutLocation]
      if colony.owner != scout.owner:
        housesInSystem.add(colony.owner)

    # Check for fleets with scouts
    for fleetId, fleet in state.fleets:
      if fleet.location == scoutLocation and fleet.owner != scout.owner:
        # Check if fleet has scouts
        for squadron in fleet.squadrons:
          if squadron.flagship.shipClass == ShipClass.Scout:
            if not housesInSystem.contains(fleet.owner):
              housesInSystem.add(fleet.owner)
            break

    # For each rival house in system, roll detection
    for rivalHouse in housesInSystem:
      # Build ELI unit from fleets
      var detectorELI: seq[int] = @[]
      var hasStarbase = false

      # Check for colony with starbase
      if scoutLocation in state.colonies:
        let colony = state.colonies[scoutLocation]
        if colony.owner == rivalHouse:
          # Check for operational starbase presence (not crippled)
          for starbase in colony.starbases:
            if not starbase.isCrippled:
              hasStarbase = true
              break

      # Collect ELI from fleets
      for fleetId, fleet in state.fleets:
        if fleet.location == scoutLocation and fleet.owner == rivalHouse:
          for squadron in fleet.squadrons:
            if squadron.flagship.shipClass == ShipClass.Scout:
              detectorELI.add(squadron.flagship.stats.techLevel)

      # Attempt detection if there are ELI units
      if detectorELI.len > 0:
        let detectorUnit = ELIUnit(
          eliLevels: detectorELI,
          isStarbase: hasStarbase
        )

        # Roll detection with turn RNG
        var rng = initRand(state.turn xor scoutId.hash())
        let detectionResult = detectSpyScout(detectorUnit, scout.eliLevel, rng)

        if detectionResult.detected:
          logInfo(LogCategory.lcGeneral,
            &"Spy scout {scoutId} detected by {rivalHouse} " &
            &"(ELI {detectionResult.effectiveELI} vs {scout.eliLevel}, " &
            &"rolled {detectionResult.roll} > {detectionResult.threshold})")
          wasDetected = true
          break

    if wasDetected:
      # Scout is destroyed, don't add to surviving scouts
      logInfo(LogCategory.lcGeneral, &"Spy scout {scoutId} destroyed")
    else:
      # Scout survives and gathers intelligence
      survivingScouts[scoutId] = scout

      # Generate intelligence reports based on mission type
      # Enhanced scout intelligence system automatically:
      # - Generates detailed scout encounter reports
      # - Tracks fleet movement history over time
      # - Tracks construction activity over multiple visits
      case scout.mission
      of SpyMissionType.SpyOnPlanet:
        logDebug(LogCategory.lcGeneral, &"Spy scout {scoutId} gathering planetary intelligence at system-{scoutLocation}")
        scout_intel.processScoutIntelligence(state, scoutId, scout.owner, scoutLocation)
        logDebug(LogCategory.lcGeneral, &"Enhanced colony intel: population, industry, defenses, construction tracking")

      of SpyMissionType.HackStarbase:
        logDebug(LogCategory.lcGeneral, &"Spy scout {scoutId} hacking starbase at system-{scoutLocation}")
        let report = intel_gen.generateStarbaseIntelReport(state, scout.owner, scoutLocation, intel_types.IntelQuality.Spy)
        if report.isSome:
          var house = state.houses[scout.owner]
          house.intelligence.addStarbaseReport(report.get())
          state.houses[scout.owner] = house
          logDebug(LogCategory.lcGeneral,
            &"Intel: Treasury {report.get().treasuryBalance.get(0)} PP, Tax rate {report.get().taxRate.get(0.0)}%")

      of SpyMissionType.SpyOnSystem:
        logDebug(LogCategory.lcGeneral, &"Spy scout {scoutId} conducting system surveillance at {scoutLocation}")
        scout_intel.processScoutIntelligence(state, scoutId, scout.owner, scoutLocation)
        logDebug(LogCategory.lcGeneral, &"Enhanced system intel: fleet composition, movement patterns, cargo details")

  # Update spy scouts in game state (remove detected ones)
  state.spyScouts = survivingScouts

  # Process starbase surveillance (continuous monitoring every turn)
  logDebug(LogCategory.lcGeneral, &"Processing starbase surveillance...")
  var survRng = initRand(state.turn + 12345)  # Unique seed for surveillance
  starbase_surveillance.processAllStarbaseSurveillance(state, state.turn, survRng)

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
              # Execute salvage order (returns PP added to treasury)
              let result = cmd_executor.executeFleetOrder(state, houseId, order)
              if result.success:
                logInfo(LogCategory.lcEconomy,
                  &"[SALVAGE] {houseId} Fleet-{order.fleetId} salvaged ships")
                # PP already added to treasury by executeSalvageOrder
              else:
                logDebug(LogCategory.lcEconomy,
                  &"[SALVAGE] {houseId} Fleet-{order.fleetId} failed: {result.message}")

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
        events.add(res_game_types.GameEvent(
          eventType: res_game_types.GameEventType.UnitDisbanded,
          houseId: houseId,
          description: action.description,
          systemId: some(colonyId)
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
      events.add(res_game_types.GameEvent(
        eventType: res_game_types.GameEventType.UnitDisbanded,
        houseId: houseId,
        description: action.description,
        systemId: none(SystemId)
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
      events.add(res_game_types.GameEvent(
        eventType: res_game_types.GameEventType.UnitDisbanded,
        houseId: houseId,
        description: action.description,
        systemId: none(SystemId)
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
      events.add(res_game_types.GameEvent(
        eventType: res_game_types.GameEventType.UnitDisbanded,
        houseId: houseId,
        description: action.description,
        systemId: none(SystemId)
      ))

  logDebug(LogCategory.lcEconomy,
          "[CAPACITY ENFORCEMENT] Completed capacity enforcement")

  # Call economy engine
  let incomeReport = econ_engine.resolveIncomePhase(
    coloniesSeqIncome,
    houseTaxPolicies,
    houseTechLevels,
    houseCSTTechLevels,
    houseTreasuries
  )

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


  # Check victory conditions (after all economic and prestige updates)
  # Per FINAL_TURN_SEQUENCE.md: Victory check happens in Income Phase Step 8
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
