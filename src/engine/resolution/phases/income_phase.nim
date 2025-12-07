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

  # Process construction completion - decrement turns and complete projects
  # NEW: Process ALL projects in construction queue (not just legacy single project)
  for systemId, colony in state.colonies.mpairs:
    # Process build queue (all projects in parallel)
    var completedProjects: seq[econ_types.ConstructionProject] = @[]
    var remainingProjects: seq[econ_types.ConstructionProject] = @[]

    # DEBUG: Log queue contents
    if colony.constructionQueue.len > 0:
      logDebug(LogCategory.lcEconomy, &"System-{systemId} has {colony.constructionQueue.len} projects in construction queue")
      for project in colony.constructionQueue:
        logDebug(LogCategory.lcEconomy, &"  - {project.itemId}: {project.turnsRemaining} turns remaining")

    for project in colony.constructionQueue.mitems:
      project.turnsRemaining -= 1

      if project.turnsRemaining <= 0:
        completedProjects.add(project)
      else:
        remainingProjects.add(project)

    # =========================================================================
    # SHIP COMMISSIONING PIPELINE
    # =========================================================================
    # Process completed construction projects and commission new units
    #
    # **Commissioning Pipeline for Combat Ships:**
    # 1. Ship construction completes (1 turn per economy.md:5.0)
    # 2. Ship commissioned with current tech levels
    # 3. **Squadron Assignment** (auto-balance strength):
    #    - Escorts try to join existing unassigned capital ship squadrons (balance)
    #    - If no capital squadrons, escorts try to join same-class escort squadrons
    #    - Capital ships always create new squadrons (they're flagships)
    #    - Unjoined escorts create new squadrons
    # 4. **Fleet Assignment** (always enabled):
    #    - Calls autoBalanceSquadronsToFleets() to organize squadrons into fleets
    #    - Balances squadron count across existing stationary Active fleets
    #    - Creates new fleets if no candidate fleets exist
    #
    # **Commissioning Pipeline for Spacelift Ships (ETAC/TT):**
    # 1. Ship commissioned to colony.unassignedSpaceLiftShips
    # 2. Immediately joins first available fleet via auto-assignment
    #
    # **Result:**
    # - Ships end up in fleets, ready for orders (auto-assignment always enabled)
    # - See docs/architecture/fleet-management.md for rationale
    # =========================================================================

    for project in completedProjects:
      if project.turnsRemaining <= 0:
        # Construction complete!
        logDebug(LogCategory.lcEconomy, &"Construction completed at system-{systemId}: {project.itemId}")

        case project.projectType
        of econ_types.ConstructionType.Ship:
          # Commission ship from Spaceport/Shipyard
          let shipClass = parseEnum[ShipClass](project.itemId)
          let techLevel = state.houses[colony.owner].techTree.levels.constructionTech

          # ARCHITECTURE FIX: Check if this is a spacelift ship (NOT a combat squadron)
          let isSpaceLift = shipClass in [ShipClass.ETAC, ShipClass.TroopTransport]

          # ARCHITECTURE FIX: Fighters go to colony.fighterSquadrons, not fleets
          let isFighter = shipClass == ShipClass.Fighter

          logInfo(LogCategory.lcEconomy, &"Commissioning {shipClass}: isFighter={isFighter}, isSpaceLift={isSpaceLift}")

          if isFighter:
            # Path 1: Commission fighter at colony (assets.md:2.4.1)
            # Use turn + timestamp to ensure unique IDs (avoid collisions when fighters loaded onto carriers)
            let fighterSeqNum = state.turn * 100 + colony.fighterSquadrons.len
            let fighterSq = FighterSquadron(
              id: $systemId & "-FS-" & $fighterSeqNum,
              commissionedTurn: state.turn
            )

            colony.fighterSquadrons.add(fighterSq)
            logDebug(LogCategory.lcEconomy, &"Commissioned fighter squadron {fighterSq.id} at {systemId} (Path 1)")

            # Path 2: Auto-load onto carriers at same colony (assets.md:2.4.1)
            # Find carriers at this colony with available hangar space
            for fleetId, fleet in state.fleets.mpairs:
              if fleet.location == systemId and fleet.owner == colony.owner:
                for squadron in fleet.squadrons.mitems:
                  if squadron.flagship.shipClass in [ShipClass.Carrier, ShipClass.SuperCarrier]:
                    # Check hangar capacity (simplified: CV=3, CX=5, ignoring ACO tech for now)
                    let maxCapacity = if squadron.flagship.shipClass == ShipClass.Carrier: 3 else: 5
                    let currentLoad = squadron.embarkedFighters.len

                    if currentLoad < maxCapacity:
                      # Auto-load fighter onto carrier
                      let carrierFighter = CarrierFighter(
                        id: fighterSq.id,
                        commissionedTurn: fighterSq.commissionedTurn
                      )
                      squadron.embarkedFighters.add(carrierFighter)

                      # Remove from colony (transfer ownership)
                      # SAFETY CHECK: Ensure we have fighters to remove
                      let lenBefore = colony.fighterSquadrons.len
                      if lenBefore > 0:
                        let indexToDelete = lenBefore - 1
                        logDebug(LogCategory.lcFleet,
                          &"About to delete fighter at index {indexToDelete} (len={lenBefore})")
                        colony.fighterSquadrons.delete(indexToDelete)
                        logDebug(LogCategory.lcFleet,
                          &"Auto-loaded {fighterSq.id} onto carrier {fleetId} (Path 2, {currentLoad + 1}/{maxCapacity} capacity)")
                        logDebug(LogCategory.lcFleet,
                          &"Deleted fighter from colony (len before: {lenBefore}, after: {colony.fighterSquadrons.len})")
                      else:
                        logError(LogCategory.lcFleet,
                          &"ERROR: Tried to auto-load {fighterSq.id} but colony.fighterSquadrons is empty!")
                      # Exit both loops after successful auto-load
                      break
                  if squadron.embarkedFighters.len > 0:  # Fighter was loaded
                    break
          elif isSpaceLift:
            # Create SpaceLiftShip (individual unit, not squadron)
            let shipId = colony.owner & "_" & $shipClass & "_" & $systemId & "_" & $state.turn
            var spaceLiftShip = newSpaceLiftShip(shipId, shipClass, colony.owner, systemId)

            # Auto-load PTU onto ETAC at commissioning with extraction cost
            # Larger colonies spare PTUs more cheaply due to exponential PU→PTU relationship
            # Formula: extraction_cost = 1.0 / (1.0 + 0.00657 * pu)
            # Examples: 100 PU colony loses 0.60 PU, 1000 PU colony loses only 0.13 PU
            # Note: Space Guild transfers will have ADDITIONAL costs beyond just extraction
            # See docs/specs/economy.md:15-27 for PTU mechanics
            if shipClass == ShipClass.ETAC and colony.population > 1:
              # Calculate extraction cost (PU lost from colony to create 1 PTU)
              let extractionCost = 1.0 / (1.0 + 0.00657 * colony.population.float)

              # Apply cost by reducing colony population (affects future GCO/production)
              let newPopulation = colony.population.float - extractionCost
              colony.population = max(1, newPopulation.int)

              # Load PTU onto ETAC
              spaceLiftShip.cargo.cargoType = CargoType.Colonists
              spaceLiftShip.cargo.quantity = 1
              logInfo(LogCategory.lcEconomy, &"Loaded 1 PTU onto {shipId} (extraction: {extractionCost:.2f} PU from {systemId})")

            colony.unassignedSpaceLiftShips.add(spaceLiftShip)
            logInfo(LogCategory.lcEconomy, &"Commissioned {shipClass} spacelift ship at {systemId}")

            # Auto-assign to fleets (create new fleet if needed)
            if colony.unassignedSpaceLiftShips.len > 0:
              # Get the ship from unassigned pool (use this reference, not the local variable)
              let shipToAssign = colony.unassignedSpaceLiftShips[colony.unassignedSpaceLiftShips.len - 1]

              # Find or create fleet at this location
              var targetFleetId = ""
              for fleetId, fleet in state.fleets:
                if fleet.location == systemId and fleet.owner == colony.owner:
                  targetFleetId = fleetId
                  break

              if targetFleetId == "":
                # Create new fleet for spacelift ship
                targetFleetId = $colony.owner & "_fleet" & $(state.fleets.len + 1)
                state.fleets[targetFleetId] = Fleet(
                  id: targetFleetId,
                  owner: colony.owner,
                  location: systemId,
                  squadrons: @[],
                  spaceLiftShips: @[shipToAssign],
                  status: FleetStatus.Active,
                  autoBalanceSquadrons: true
                )
                let createdFleet = state.fleets[targetFleetId]
                logInfo(LogCategory.lcFleet, &"Commissioned {shipClass} in new fleet {targetFleetId} with {createdFleet.spaceLiftShips.len} spacelift ships")
              else:
                # Add to existing fleet
                state.fleets[targetFleetId].spaceLiftShips.add(shipToAssign)
                logInfo(LogCategory.lcFleet, &"Commissioned {shipClass} in fleet {targetFleetId}")

              # Remove from unassigned pool (it's now in fleet)
              # SAFETY CHECK: Ensure we have ships to remove
              if colony.unassignedSpaceLiftShips.len > 0:
                colony.unassignedSpaceLiftShips.delete(colony.unassignedSpaceLiftShips.len - 1)
              else:
                logError(LogCategory.lcFleet,
                  &"ERROR: Tried to remove spacelift ship but colony.unassignedSpaceLiftShips is empty!")

              # WARN if ETAC assigned without PTU (potential colonization failure)
              if shipClass == ShipClass.ETAC and
                 (spaceLiftShip.cargo.cargoType != CargoType.Colonists or spaceLiftShip.cargo.quantity == 0):
                logWarn(LogCategory.lcFleet, &"Empty ETAC {shipId} assigned to fleet {targetFleetId} - colonization will fail!")

              logInfo(LogCategory.lcFleet, &"Auto-assigned {shipClass} to fleet {targetFleetId}")

          else:
            # Combat ship - create squadron as normal
            let newShip = newEnhancedShip(shipClass, techLevel)

            # SQUADRON FORMATION LOGIC (Step 3 of commissioning pipeline)
            # Goal: Create balanced, combat-ready squadrons before fleet assignment
            #
            # Tactical Doctrine:
            # - **Escorts** (small/fast ships): Join existing squadrons as supporting units
            # - **Capital ships** (large/slow): Always become squadron flagships
            #
            # This creates combined-arms squadrons (e.g., Battleship + 3 Destroyers)
            # which have better tactical capabilities than single-ship squadrons
            var addedToSquadron = false

            # Classify ship as escort or capital based on hull class and role
            # Escorts: Small/fast ships (SC, FG, DD, CT, CL) - support role, expendable
            # Capitals: Large/powerful ships (CA+, BB+, CV+) - flagship role, valuable
            let isEscort = shipClass in [
              ShipClass.Scout, ShipClass.Frigate, ShipClass.Destroyer,
              ShipClass.Corvette, ShipClass.LightCruiser
            ]

            # ESCORT ASSIGNMENT: Join existing squadrons to create balanced battle groups
            if isEscort:
              # Try to join unassigned capital ship squadrons first
              for squadron in colony.unassignedSquadrons.mitems:
                let flagshipIsCapital = squadron.flagship.shipClass in [
                  ShipClass.Battleship, ShipClass.Dreadnought, ShipClass.SuperDreadnought,
                  ShipClass.Carrier, ShipClass.SuperCarrier, ShipClass.Battlecruiser,
                  ShipClass.HeavyCruiser, ShipClass.Cruiser
                ]
                if flagshipIsCapital and squadron.canAddShip(newShip):
                  squadron.ships.add(newShip)
                  logDebug(LogCategory.lcEconomy, &"Commissioned {shipClass} and added to unassigned capital squadron {squadron.id}")
                  addedToSquadron = true
                  break

              # If no capital squadrons, try joining escort squadrons
              if not addedToSquadron:
                for squadron in colony.unassignedSquadrons.mitems:
                  if squadron.flagship.shipClass == shipClass and squadron.canAddShip(newShip):
                    squadron.ships.add(newShip)
                    logDebug(LogCategory.lcEconomy, &"Commissioned {shipClass} and added to unassigned escort squadron {squadron.id}")
                    addedToSquadron = true
                    break

            # Capital ships and unassigned escorts create new squadrons at colony
            if not addedToSquadron:
              let squadronId = colony.owner & "_sq_" & $systemId & "_" & $state.turn & "_" & project.itemId
              let newSquadron = newSquadron(newShip, squadronId, colony.owner, systemId)
              colony.unassignedSquadrons.add(newSquadron)
              logDebug(LogCategory.lcEconomy, &"Commissioned {shipClass} into new unassigned squadron at {systemId}")

            # Fleet Organization: Automatically organize newly-commissioned squadrons into fleets
            # This completes the economic production pipeline: Treasury → Construction → Commissioning → Fleet
            # Without this step, units remain in unassignedSquadrons and cannot execute operational orders
            # (e.g., scouts cannot perform espionage, carriers cannot deploy to defensive positions)
            if colony.unassignedSquadrons.len > 0:
              autoBalanceSquadronsToFleets(state, colony, systemId, orders)

        of econ_types.ConstructionType.Building:
          # Add building to colony
          if project.itemId == "Spaceport":
            # Calculate CST-scaled dock capacity
            let cstLevel = state.houses[colony.owner].techTree.levels.constructionTech
            let baseDocks = globalConstructionConfig.construction.spaceport_docks
            let cstMultiplier = 1.0 + float(cstLevel - 1) * globalConstructionConfig.modifiers.construction_capacity_increase_per_level
            let scaledDocks = int(float(baseDocks) * cstMultiplier)

            let spaceportId = colony.owner & "_spaceport_" & $systemId & "_" & $state.turn
            let spaceport = Spaceport(
              id: spaceportId,
              commissionedTurn: state.turn,
              docks: scaledDocks
            )
            colony.spaceports.add(spaceport)
            logDebug(LogCategory.lcEconomy, &"Added Spaceport to system-{systemId} ({scaledDocks} docks, CST {cstLevel})")

          elif project.itemId == "Shipyard":
            # Calculate CST-scaled dock capacity
            let cstLevel = state.houses[colony.owner].techTree.levels.constructionTech
            let baseDocks = globalConstructionConfig.construction.shipyard_docks
            let cstMultiplier = 1.0 + float(cstLevel - 1) * globalConstructionConfig.modifiers.construction_capacity_increase_per_level
            let scaledDocks = int(float(baseDocks) * cstMultiplier)

            let shipyardId = colony.owner & "_shipyard_" & $systemId & "_" & $state.turn
            let shipyard = Shipyard(
              id: shipyardId,
              commissionedTurn: state.turn,
              docks: scaledDocks
            )
            colony.shipyards.add(shipyard)
            logDebug(LogCategory.lcEconomy, &"Added Shipyard to system-{systemId} ({scaledDocks} docks, CST {cstLevel})")

          elif project.itemId == "GroundBattery":
            colony.groundBatteries += 1
            logDebug(LogCategory.lcEconomy, &"Added Ground Battery to system-{systemId}")

          elif project.itemId == "PlanetaryShield":
            # Set planetary shield level based on house's SLD tech
            colony.planetaryShieldLevel = state.houses[colony.owner].techTree.levels.shieldTech
            logDebug(LogCategory.lcEconomy, &"Added Planetary Shield (SLD{colony.planetaryShieldLevel}) to system-{systemId}")

        of econ_types.ConstructionType.Industrial:
          # IU investment - industrial capacity was added when project started
          # Just log completion
          logDebug(LogCategory.lcEconomy, &"Industrial expansion completed at system-{systemId}")

        of econ_types.ConstructionType.Infrastructure:
          # Infrastructure was already added during creation
          # Just log completion
          logDebug(LogCategory.lcEconomy, &"Infrastructure expansion completed at system-{systemId}")

    # Update construction queue with remaining (in-progress) projects
    colony.constructionQueue = remainingProjects

    # =========================================================================
    # REPAIR QUEUE PROCESSING
    # =========================================================================
    # Process repair queue (all repairs in parallel, similar to construction)
    # Ships repair for 1 turn at 25% of build cost
    # Repaired ships recommission through standard squadron pipeline
    #
    # **Repair Priority:**
    # - Construction projects (priority=0) take precedence over repairs
    # - Ship repairs (priority=1) before starbase repairs (priority=2)
    # - Dock capacity shared between construction and repairs
    # =========================================================================

    var completedRepairs: seq[econ_types.RepairProject] = @[]
    var remainingRepairs: seq[econ_types.RepairProject] = @[]

    if colony.repairQueue.len > 0:
      logDebug(LogCategory.lcEconomy, &"System-{systemId} has {colony.repairQueue.len} repairs in queue")

    for repair in colony.repairQueue.mitems:
      repair.turnsRemaining -= 1

      if repair.turnsRemaining <= 0:
        completedRepairs.add(repair)
      else:
        remainingRepairs.add(repair)

    # Commission repaired ships through standard pipeline
    for repair in completedRepairs:
      case repair.targetType
      of econ_types.RepairTargetType.Ship:
        if repair.shipClass.isSome:
          let shipClass = repair.shipClass.get()
          logInfo(LogCategory.lcEconomy, &"Repair completed at system-{systemId}: {shipClass}")

          # Commission repaired ship as new ship (same as construction)
          let isSpaceLift = shipClass in [ShipClass.ETAC, ShipClass.TroopTransport]

          if isSpaceLift:
            # Spacelift ships commission to unassigned list
            let capacity = case shipClass
              of ShipClass.TroopTransport: 1  # 1 MD (Marine Division)
              of ShipClass.ETAC: 1            # 1 PTU (Population Transfer Unit)
              else: 0

            let spaceLiftShip = SpaceLiftShip(
              id: "", # Will be assigned
              shipClass: shipClass,
              owner: colony.owner,
              location: colony.systemId,
              isCrippled: false,  # Repaired!
              cargo: SpaceLiftCargo(
                cargoType: CargoType.None,
                quantity: 0,
                capacity: capacity
              )
            )
            colony.unassignedSpaceLiftShips.add(spaceLiftShip)
            logDebug(LogCategory.lcEconomy, &"Recommissioned {shipClass} as spacelift ship (repaired)")
          else:
            # Combat ships commission through squadron pipeline
            let stats = getShipStats(shipClass)
            let ship = EnhancedShip(
              shipClass: shipClass,
              shipType: ShipType.Military,
              stats: stats,
              isCrippled: false,  # Repaired!
              name: $shipClass
            )

            # Squadron assignment logic (same as construction)
            if shipClass in {ShipClass.Battleship, ShipClass.SuperDreadnought,
                            ShipClass.Dreadnought, ShipClass.Carrier,
                            ShipClass.SuperCarrier, ShipClass.HeavyCruiser,
                            ShipClass.Cruiser}:
              # Capital ships become flagships
              let newSquadron = newSquadron(
                flagship = ship,
                id = "SQ-" & $systemId & "-" & $(colony.unassignedSquadrons.len + 1),
                owner = colony.owner,
                location = systemId
              )
              colony.unassignedSquadrons.add(newSquadron)
              logDebug(LogCategory.lcEconomy, &"Recommissioned {shipClass} as new squadron flagship (repaired)")
            else:
              # Escorts try to join existing squadrons
              var joined = false

              # Try to join existing capital ship squadrons first
              for sq in colony.unassignedSquadrons.mitems:
                let flagshipClass = sq.flagship.shipClass
                if flagshipClass in {ShipClass.Battleship, ShipClass.SuperDreadnought,
                                    ShipClass.Dreadnought, ShipClass.Carrier,
                                    ShipClass.SuperCarrier, ShipClass.HeavyCruiser,
                                    ShipClass.Cruiser}:
                  if sq.canAddShip(ship):
                    discard sq.addShip(ship)
                    joined = true
                    logDebug(LogCategory.lcEconomy, &"Recommissioned {shipClass} joined capital squadron (repaired)")
                    break

              # If not joined, try same-class escort squadrons
              if not joined:
                for sq in colony.unassignedSquadrons.mitems:
                  if sq.flagship.shipClass == shipClass:
                    if sq.canAddShip(ship):
                      discard sq.addShip(ship)
                      joined = true
                      logDebug(LogCategory.lcEconomy, &"Recommissioned {shipClass} joined escort squadron (repaired)")
                      break

              # If still not joined, create new escort squadron
              if not joined:
                let newSquadron = newSquadron(
                  flagship = ship,
                  id = "SQ-" & $systemId & "-" & $(colony.unassignedSquadrons.len + 1),
                  owner = colony.owner,
                  location = systemId
                )
                colony.unassignedSquadrons.add(newSquadron)
                logDebug(LogCategory.lcEconomy, &"Recommissioned {shipClass} as new escort squadron (repaired)")

      of econ_types.RepairTargetType.Starbase:
        # Repair starbase at colony
        if repair.starbaseIdx.isSome:
          let idx = repair.starbaseIdx.get()
          if idx >= 0 and idx < colony.starbases.len:
            colony.starbases[idx].isCrippled = false
            logInfo(LogCategory.lcEconomy, &"Repair completed at system-{systemId}: Starbase-{idx}")

    # Update repair queue
    colony.repairQueue = remainingRepairs

    # LEGACY SUPPORT: Update underConstruction field for backwards compatibility
    # Keep the first in-progress project as the "active" one
    if remainingProjects.len > 0:
      colony.underConstruction = some(remainingProjects[0])
    else:
      colony.underConstruction = none(econ_types.ConstructionProject)

    # CRITICAL: Write back colony to persist ALL modifications in this loop iteration
    # Even with mpairs, nested seq/field modifications require explicit write-back:
    # - fighterSquadrons (commissioned fighters)
    # - unassignedSpaceLiftShips (commissioned transports/ETACs)
    # - unassignedSquadrons (repaired ships forming squadrons)
    # - population (ETAC PTU extraction cost)
    # - constructionQueue (completed/remaining projects)
    # - repairQueue (completed/remaining repairs)
    # - starbases (repaired starbases)
    # - underConstruction (legacy field)
    state.colonies[systemId] = colony

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
