## Simultaneous Espionage Resolution
##
## Handles simultaneous resolution of SpyPlanet, SpySystem, and HackStarbase orders
## to prevent first-mover advantages in intelligence operations.

import std/[tables, options, random, strformat, algorithm]
import ../../intelligence/spy_resolution
import ../../types/simultaneous as simultaneous_types
import ../combat/simultaneous_resolver
import ../../gamestate
import ../../index_maintenance
import ../../orders
import ../../order_types
import ../../logger
import ../../squadron
import ./engine as esp_engine
import ./executor as esp_executor
import ../../types/espionage as esp_types
import ../../config/espionage_config
import ../../types/core
import ../../prestige
import ../../event_factory/intelligence as intelligence_events
import ../../types/resolution as res_types
import ../../intelligence/generator as intel_generator
import ../../intelligence/types as intel_types

proc collectEspionageIntents*(
  state: GameState,
  orders: Table[HouseId, OrderPacket]
): seq[EspionageIntent] =
  ## Collect all espionage attempts
  result = @[]

  for houseId in state.houses.keys:
    if houseId notin orders:
      continue

    for order in orders[houseId].fleetOrders:
      if order.orderType notin [FleetOrderType.SpyPlanet, FleetOrderType.SpySystem, FleetOrderType.HackStarbase]:
        continue

      # Validate: fleet exists
      if order.fleetId notin state.fleets:
        continue

      # Calculate espionage strength using house prestige
      # Higher prestige = better intelligence operations
      let espionageStrength = state.houses[houseId].prestige

      # Get target from order
      if order.targetSystem.isNone:
        continue

      let targetSystem = order.targetSystem.get()

      # Log if fleet not at target (will attempt movement in Maintenance Phase)
      let fleet = state.fleets[order.fleetId]
      if fleet.location != targetSystem:
        logDebug(LogCategory.lcOrders, &"Espionage order queued: {order.fleetId} will move from {fleet.location} to {targetSystem}")

      result.add(EspionageIntent(
        houseId: houseId,
        fleetId: order.fleetId,
        targetSystem: targetSystem,
        orderType: $order.orderType,
        espionageStrength: espionageStrength
      ))

proc detectEspionageConflicts*(
  intents: seq[EspionageIntent]
): seq[EspionageConflict] =
  ## Group espionage intents by target system
  var targetSystems = initTable[SystemId, seq[EspionageIntent]]()

  for intent in intents:
    if intent.targetSystem notin targetSystems:
      targetSystems[intent.targetSystem] = @[]
    targetSystems[intent.targetSystem].add(intent)

  result = @[]
  for systemId, conflictingIntents in targetSystems:
    result.add(EspionageConflict(
      targetSystem: systemId,
      intents: conflictingIntents
    ))

proc resolveEspionageConflict*(
  state: var GameState,
  conflict: EspionageConflict,
  rng: var Rand,
  events: var seq[res_types.GameEvent]
): seq[simultaneous_types.EspionageResult] =
  ## Resolve espionage conflict by performing detection checks for each intent.
  result = @[]

  if conflict.intents.len == 0:
    return

  for intent in conflict.intents:
    let detected = spy_resolution.resolveSpyScoutDetection(
      state,
      intent.houseId,
      intent.fleetId,
      intent.targetSystem,
      rng
    )

    var outcome: ResolutionOutcome
    if detected:
      outcome = ResolutionOutcome.ConflictLost
      if intent.targetSystem in state.colonies:
        let defender = state.colonies[intent.targetSystem].owner
        events.add(intelligence_events.scoutDetected(
          intent.houseId,
          defender,
          intent.targetSystem,
          "Spy Scout"
        ))
    else:
      outcome = ResolutionOutcome.Success

    result.add(simultaneous_types.EspionageResult(
      houseId: intent.houseId,
      fleetId: intent.fleetId,
      originalTarget: intent.targetSystem,
      outcome: outcome,
      actualTarget: if outcome == ResolutionOutcome.Success: some(intent.targetSystem) else: none(SystemId),
      prestigeAwarded: 0  # Prestige handled elsewhere
    ))

proc resolveEspionage*(
  state: var GameState,
  orders: Table[HouseId, OrderPacket],
  rng: var Rand,
  events: var seq[res_types.GameEvent]
): seq[simultaneous_types.EspionageResult] =
  ## Main entry point: Resolve all espionage orders simultaneously
  result = @[]

  let intents = collectEspionageIntents(state, orders)
  if intents.len == 0:
    return

  let conflicts = detectEspionageConflicts(intents)

  for conflict in conflicts:
    let conflictResults = resolveEspionageConflict(state, conflict, rng, events)
    result.add(conflictResults)

proc wasEspionageHandled*(
  results: seq[simultaneous_types.EspionageResult],
  houseId: HouseId,
  fleetId: FleetId
): bool =
  ## Check if an espionage order was already handled
  for result in results:
    if result.houseId == houseId and result.fleetId == fleetId:
      return true
  return false

proc processEspionageActions*(
  state: var GameState,
  orders: Table[HouseId, OrderPacket],
  rng: var Rand,
  events: var seq[res_types.GameEvent]
) =
  ## Process OrderPacket.espionageAction for all houses
  ## This handles EBP-based espionage actions (TechTheft, Assassination, etc.)
  ## separate from fleet-based espionage orders

  for houseId in state.houses.keys:
    if houseId notin orders:
      continue

    let packet = orders[houseId]

    # Step 1: Process EBP/CIP investments (purchase points with PP)
    if packet.ebpInvestment > 0:
      let ebpPurchased = esp_engine.purchaseEBP(state.houses[houseId].espionageBudget, packet.ebpInvestment)
      # Deduct PP from treasury (already projected in AI, but need to deduct actual cost)
      state.houses[houseId].treasury -= packet.ebpInvestment
      logInfo(LogCategory.lcEconomy, &"{houseId} purchased {ebpPurchased} EBP for {packet.ebpInvestment} PP")

    if packet.cipInvestment > 0:
      let cipPurchased = esp_engine.purchaseCIP(state.houses[houseId].espionageBudget, packet.cipInvestment)
      state.houses[houseId].treasury -= packet.cipInvestment
      logInfo(LogCategory.lcEconomy, &"{houseId} purchased {cipPurchased} CIP for {packet.cipInvestment} PP")

    # Step 2: Execute espionage action if present
    if packet.espionageAction.isNone:
      continue

    let attempt = packet.espionageAction.get()

    # Validate target house is not eliminated (leaderboard is public info)
    if attempt.target in state.houses:
      if state.houses[attempt.target].eliminated:
        logDebug(LogCategory.lcAI, &"{houseId} cannot target eliminated house {attempt.target}")
        continue

    # Check if attacker has sufficient EBP
    let actionCost = esp_engine.getActionCost(attempt.action)
    if not esp_engine.canAffordAction(state.houses[houseId].espionageBudget, attempt.action):
      logDebug(LogCategory.lcAI, &"{houseId} cannot afford {attempt.action} (cost: {actionCost} EBP, has: {state.houses[houseId].espionageBudget.ebpPoints})")
      continue

    # Spend EBP
    if not esp_engine.spendEBP(state.houses[houseId].espionageBudget, attempt.action):
      logDebug(LogCategory.lcAI, &"{houseId} failed to spend EBP for {attempt.action}")
      continue

    logInfo(LogCategory.lcAI, &"{houseId} executing {attempt.action} against {attempt.target} (cost: {actionCost} EBP)")

    # Get target's CIC level from tech tree
    let targetCICLevel = case state.houses[attempt.target].techTree.levels.counterIntelligence
      of 1: esp_types.CICLevel.CIC1
      of 2: esp_types.CICLevel.CIC2
      of 3: esp_types.CICLevel.CIC3
      of 4: esp_types.CICLevel.CIC4
      of 5: esp_types.CICLevel.CIC5
      else: esp_types.CICLevel.CIC1

    let targetCIP = if attempt.target in state.houses:
                      state.houses[attempt.target].espionageBudget.cipPoints
                    else:
                      0

    # Execute espionage action with detection roll
    let result = esp_executor.executeEspionage(
      attempt,
      targetCICLevel,
      targetCIP,
      rng
    )

    # Apply results
    if result.success:
      logInfo(LogCategory.lcAI, &"  SUCCESS: {result.description}")

      # Apply prestige changes
      for prestigeEvent in result.attackerPrestigeEvents:
        applyPrestigeEvent(state, attempt.attacker, prestigeEvent)
      for prestigeEvent in result.targetPrestigeEvents:
        applyPrestigeEvent(state, attempt.target, prestigeEvent)

      # Create espionage event based on action type
      case attempt.action
      of esp_types.EspionageAction.SabotageLow:
        if attempt.targetSystem.isSome:
          events.add(intelligence_events.sabotageConducted(
            attempt.attacker,
            attempt.target,
            attempt.targetSystem.get(),
            result.iuDamage,
            "Low"
          ))
      of esp_types.EspionageAction.SabotageHigh:
        if attempt.targetSystem.isSome:
          events.add(intelligence_events.sabotageConducted(
            attempt.attacker,
            attempt.target,
            attempt.targetSystem.get(),
            result.iuDamage,
            "High"
          ))
      of esp_types.EspionageAction.TechTheft:
        events.add(intelligence_events.techTheftExecuted(
          attempt.attacker,
          attempt.target,
          result.srpStolen
        ))
      of esp_types.EspionageAction.Assassination:
        events.add(intelligence_events.assassinationAttempted(
          attempt.attacker,
          attempt.target,
          globalEspionageConfig.effects.assassination_srp_reduction
        ))
      of esp_types.EspionageAction.EconomicManipulation:
        events.add(intelligence_events.economicManipulationExecuted(
          attempt.attacker,
          attempt.target,
          globalEspionageConfig.effects.economic_ncv_reduction
        ))
      of esp_types.EspionageAction.CyberAttack:
        if attempt.targetSystem.isSome:
          events.add(intelligence_events.cyberAttackConducted(
            attempt.attacker,
            attempt.target,
            attempt.targetSystem.get()
          ))
      of esp_types.EspionageAction.PsyopsCampaign:
        events.add(intelligence_events.psyopsCampaignLaunched(
          attempt.attacker,
          attempt.target,
          globalEspionageConfig.effects.psyops_tax_reduction
        ))
      of esp_types.EspionageAction.IntelligenceTheft:
        events.add(intelligence_events.intelligenceTheftExecuted(
          attempt.attacker,
          attempt.target
        ))
      of esp_types.EspionageAction.PlantDisinformation:
        events.add(intelligence_events.disinformationPlanted(
          attempt.attacker,
          attempt.target
        ))
      of esp_types.EspionageAction.CounterIntelSweep:
        if attempt.targetSystem.isSome:
          events.add(intelligence_events.counterIntelSweepExecuted(
            attempt.attacker,
            attempt.targetSystem.get()
          ))

      # Apply ongoing effects
      if result.effect.isSome:
        state.ongoingEffects.add(result.effect.get())

      # Apply immediate effects (SRP theft, IU damage, etc.)
      if result.srpStolen > 0:
        if attempt.target in state.houses:
          state.houses[attempt.target].techTree.accumulated.science =
            max(0, state.houses[attempt.target].techTree.accumulated.science - result.srpStolen)
          state.houses[attempt.attacker].techTree.accumulated.science += result.srpStolen
          logInfo(LogCategory.lcAI, &"    Stole {result.srpStolen} SRP from {attempt.target}")
    else:
      logInfo(LogCategory.lcAI, &"  DETECTED by {attempt.target}")
      # Apply detection prestige penalties
      for prestigeEvent in result.attackerPrestigeEvents:
        applyPrestigeEvent(state, attempt.attacker, prestigeEvent)

      # Create detection event
      if attempt.targetSystem.isSome:
        events.add(intelligence_events.spyMissionDetected(
          attempt.attacker,
          attempt.target,
          attempt.targetSystem.get(),
          $attempt.action
        ))

proc processScoutIntelligence*(
  state: var GameState,
  results: seq[simultaneous_types.EspionageResult],
  orders: Table[HouseId, OrderPacket],
  rng: var Rand,
  events: var seq[res_types.GameEvent]
) =
  ## Process successful scout-based espionage results and generate intelligence reports
  ## This is the missing step that actually gathers colony/system/starbase intelligence
  ## from SpyPlanet/SpySystem/HackStarbase orders and populates house.intelligence databases
  ## Also creates detailed narrative events for espionage reports

  for result in results:
    # Consume scout fleet, regardless of outcome
    if result.fleetId in state.fleets:
      let fleet = state.fleets[result.fleetId]
      state.removeFleetFromIndices(result.fleetId, fleet.owner,
                                   fleet.location)
      state.fleets.del(result.fleetId)
      if result.fleetId in state.fleetOrders:
        state.fleetOrders.del(result.fleetId)
      logInfo(LogCategory.lcOrders, &"Spy Scout fleet {result.fleetId} consumed on mission.")

    # Only process successful espionage for intelligence gathering
    if result.outcome != ResolutionOutcome.Success:
      continue

    if result.actualTarget.isNone:
      continue

    let targetSystem = result.actualTarget.get()
    let houseId = result.houseId

    # Find the original fleet order to determine order type
    if houseId notin orders:
      continue

    let packet = orders[houseId]
    var orderType: FleetOrderType

    # Find matching fleet order
    var found = false
    for order in packet.fleetOrders:
      if order.fleetId == result.fleetId and
         order.targetSystem.isSome and
         order.targetSystem.get() == targetSystem:
        orderType = order.orderType
        found = true
        break

    if not found:
      continue

    # Generate appropriate intelligence based on order type
    case orderType
    of FleetOrderType.SpyPlanet:
      # Generate colony intelligence report
      let intelReport = intel_generator.generateColonyIntelReport(
        state, houseId, targetSystem, intel_types.IntelQuality.Spy)

      if intelReport.isSome:
        let report = intelReport.get()
        var house = state.houses[houseId]
        house.intelligence.addColonyReport(report)
        state.houses[houseId] = house

        # Calculate economic value for event
        let grossOutput = report.grossOutput.get(0)
        let industryValue = report.industry * 100
        let economicValue = grossOutput + industryValue
        let totalDefenses = report.defenses + report.starbaseLevel * 10

        # Create rich narrative event (visible only to spy house)
        # Scout-specific: SpyPlanet mission by scout fleet
        events.add(intelligence_events.scoutColonyIntelGathered(
          houseId,
          report.targetOwner,
          targetSystem,
          result.fleetId,
          totalDefenses,
          economicValue,
          report.starbaseLevel > 0,
          $report.quality
        ))

        # Log success (matches existing pattern from fleet_orders.nim:386)
        logInfo(LogCategory.lcFleet,
          &"Fleet {result.fleetId} ({houseId}) SpyPlanet success at {targetSystem} " &
          &"- intelligence DB now has {house.intelligence.colonyReports.len} colony reports")

    of FleetOrderType.SpySystem:
      # Generate system intelligence report (fleet composition)
      let intelReport = intel_generator.generateSystemIntelReport(
        state, houseId, targetSystem, intel_types.IntelQuality.Spy)

      if intelReport.isSome:
        let report = intelReport.get()
        var house = state.houses[houseId]
        house.intelligence.addSystemReport(report)
        state.houses[houseId] = house

        # Count detected fleets and ships
        let fleetsDetected = report.detectedFleets.len
        var shipsDetected = 0
        for fleetIntel in report.detectedFleets:
          shipsDetected += fleetIntel.shipCount

        # Determine target house (first fleet's owner, or none if empty)
        let targetHouse = if fleetsDetected > 0: report.detectedFleets[0].owner
                          else: houseId  # Fallback

        # Create rich narrative event (visible only to spy house)
        # Scout-specific: SpySystem mission by scout fleet
        events.add(intelligence_events.scoutSystemIntelGathered(
          houseId,
          targetHouse,
          targetSystem,
          result.fleetId,
          fleetsDetected,
          shipsDetected,
          $report.quality
        ))

        logInfo(LogCategory.lcFleet,
          &"Fleet {result.fleetId} ({houseId}) SpySystem success at {targetSystem} " &
          &"- gathered fleet intelligence")

    of FleetOrderType.HackStarbase:
      # Generate starbase intelligence report (economic/R&D data)
      let intelReport = intel_generator.generateStarbaseIntelReport(
        state, houseId, targetSystem, intel_types.IntelQuality.Spy)

      if intelReport.isSome:
        let report = intelReport.get()
        var house = state.houses[houseId]
        house.intelligence.addStarbaseReport(report)
        state.houses[houseId] = house

        # Check if economic data was acquired (based on quality)
        let hasEconomicData = report.quality == intel_types.IntelQuality.Spy or
                              report.quality == intel_types.IntelQuality.Perfect

        # Get facility data from colony (visible since hack succeeded)
        let colony = state.colonies[targetSystem]
        let starbaseCount = colony.starbases.len
        let spaceportCount = colony.spaceports.len
        let shipyardCount = colony.shipyards.len

        # Calculate total dock capacity
        var totalDocks = 0
        for spaceport in colony.spaceports:
          totalDocks += spaceport.effectiveDocks
        for shipyard in colony.shipyards:
          totalDocks += shipyard.effectiveDocks

        # Count ships under construction (active + queued)
        var shipsUnderConstruction = 0
        if colony.underConstruction.isSome:
          shipsUnderConstruction += 1
        shipsUnderConstruction += colony.constructionQueue.len

        # Count ships under repair
        let shipsUnderRepair = colony.repairQueue.len

        # Create rich narrative event (visible only to spy house)
        # Scout-specific: HackStarbase mission by scout fleet
        events.add(intelligence_events.scoutStarbaseIntelGathered(
          houseId,
          report.targetOwner,
          targetSystem,
          result.fleetId,
          starbaseCount,
          spaceportCount,
          shipyardCount,
          totalDocks,
          shipsUnderConstruction,
          shipsUnderRepair,
          hasEconomicData,
          $report.quality
        ))

        logInfo(LogCategory.lcFleet,
          &"Fleet {result.fleetId} ({houseId}) HackStarbase success at {targetSystem} " &
          &"- gathered economic/R&D intelligence")

    else:
      # Ignore non-espionage orders
      discard
