## Simultaneous Espionage Resolution
##
## Handles simultaneous resolution of SpyPlanet, SpySystem, and HackStarbase orders
## to prevent first-mover advantages in intelligence operations.

import std/[tables, options, random, strformat, algorithm, logging]
import ../../types/[core, game_state, simultaneous, orders, espionage, intelligence, event]
import ../../entities/fleet_ops
import ../intelligence/[spy_resolution, generator as intel_generator]
import ../combat/simultaneous_resolver
import ../event/factory/intelligence as intelligence_events
import ../prestige/engine as prestige
import ../../config/espionage_config
import ./[engine as esp_engine, executor as esp_executor]

proc collectEspionageIntents*(
  state: GameState,
  orders: Table[HouseId, OrderPacket]
): seq[simultaneous.EspionageIntent] =
  ## Collect all espionage attempts
  result = @[]

  for houseId, house in state.houses.entities.data:
    if houseId notin orders:
      continue

    for command in orders[houseId].fleetCommands:
      if command.commandType notin [FleetCommandType.SpyPlanet, FleetCommandType.SpySystem, FleetCommandType.HackStarbase]:
        continue

      # Validate: fleet exists
      if command.fleetId notin state.fleets.entities.index:
        continue

      # Calculate espionage strength using house prestige
      # Higher prestige = better intelligence operations
      let espionageStrength = house.prestige

      # Get target from order
      if command.targetSystem.isNone:
        continue

      let targetSystem = command.targetSystem.get()

      # Log if fleet not at target (will attempt movement in Maintenance Phase)
      let fleetIdx = state.fleets.entities.index[command.fleetId]
      let fleet = state.fleets.entities.data[fleetIdx]
      if fleet.location != targetSystem:
        debug "Espionage order queued: ", command.fleetId, " will move from ", fleet.location, " to ", targetSystem

      result.add(simultaneous.EspionageIntent(
        houseId: houseId,
        fleetId: command.fleetId,
        targetSystem: targetSystem,
        orderType: $command.commandType,
        espionageStrength: espionageStrength
      ))

proc detectEspionageConflicts*(
  intents: seq[simultaneous.EspionageIntent]
): seq[simultaneous.EspionageConflict] =
  ## Group espionage intents by target system
  var targetSystems = initTable[SystemId, seq[simultaneous.EspionageIntent]]()

  for intent in intents:
    if intent.targetSystem notin targetSystems:
      targetSystems[intent.targetSystem] = @[]
    targetSystems[intent.targetSystem].add(intent)

  result = @[]
  for systemId, conflictingIntents in targetSystems:
    result.add(simultaneous.EspionageConflict(
      targetSystem: systemId,
      intents: conflictingIntents
    ))

proc resolveEspionageConflict*(
  state: var GameState,
  conflict: simultaneous.EspionageConflict,
  rng: var Rand,
  events: var seq[event.GameEvent]
): seq[simultaneous.EspionageResult] =
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

    var outcome: simultaneous.ResolutionOutcome
    if detected:
      outcome = simultaneous.ResolutionOutcome.ConflictLost
      if intent.targetSystem in state.colonies.entities.index:
        let colonyIdx = state.colonies.entities.index[intent.targetSystem]
        let defender = state.colonies.entities.data[colonyIdx].owner
        events.add(intelligence_events.scoutDetected(
          intent.houseId,
          defender,
          intent.targetSystem,
          "Spy Scout"
        ))
    else:
      outcome = simultaneous.ResolutionOutcome.Success

    result.add(simultaneous.EspionageResult(
      houseId: intent.houseId,
      fleetId: intent.fleetId,
      originalTarget: intent.targetSystem,
      outcome: outcome,
      actualTarget: if outcome == simultaneous.ResolutionOutcome.Success: some(intent.targetSystem) else: none(SystemId),
      prestigeAwarded: 0  # Prestige handled elsewhere
    ))

proc resolveEspionage*(
  state: var GameState,
  orders: Table[HouseId, OrderPacket],
  rng: var Rand,
  events: var seq[event.GameEvent]
): seq[simultaneous.EspionageResult] =
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
  results: seq[simultaneous.EspionageResult],
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
  events: var seq[event.GameEvent]
) =
  ## Process OrderPacket.espionageAction for all houses
  ## This handles EBP-based espionage actions (TechTheft, Assassination, etc.)
  ## separate from fleet-based espionage orders

  for houseId, house in state.houses.entities.data.mpairs:
    if houseId notin orders:
      continue

    let packet = orders[houseId]

    # Step 1: Process EBP/CIP investments (purchase points with PP)
    if packet.ebpInvestment > 0:
      let ebpPurchased = esp_engine.purchaseEBP(house.espionageBudget, packet.ebpInvestment)
      # Deduct PP from treasury (already projected in AI, but need to deduct actual cost)
      house.treasury -= packet.ebpInvestment
      info houseId, " purchased ", ebpPurchased, " EBP for ", packet.ebpInvestment, " PP"

    if packet.cipInvestment > 0:
      let cipPurchased = esp_engine.purchaseCIP(house.espionageBudget, packet.cipInvestment)
      house.treasury -= packet.cipInvestment
      info houseId, " purchased ", cipPurchased, " CIP for ", packet.cipInvestment, " PP"

    # Step 2: Execute espionage action if present
    if packet.espionageAction.isNone:
      continue

    let attempt = packet.espionageAction.get()

    # Validate target house is not eliminated (leaderboard is public info)
    if attempt.target in state.houses.entities.index:
      let targetIdx = state.houses.entities.index[attempt.target]
      if state.houses.entities.data[targetIdx].isEliminated:
        debug houseId, " cannot target eliminated house ", attempt.target
        continue

    # Check if attacker has sufficient EBP
    let actionCost = esp_engine.getActionCost(attempt.action)
    if not esp_engine.canAffordAction(house.espionageBudget, attempt.action):
      debug houseId, " cannot afford ", attempt.action, " (cost: ", actionCost, " EBP, has: ", house.espionageBudget.ebpPoints, ")"
      continue

    # Spend EBP
    if not esp_engine.spendEBP(house.espionageBudget, attempt.action):
      debug houseId, " failed to spend EBP for ", attempt.action
      continue

    info houseId, " executing ", attempt.action, " against ", attempt.target, " (cost: ", actionCost, " EBP)"

    # Get target's CIC level from tech tree
    let targetIdx = state.houses.entities.index[attempt.target]
    let targetHouse = state.houses.entities.data[targetIdx]
    let targetCICLevel = case targetHouse.techTree.levels.counterIntelligence
      of 1: espionage.CICLevel.CIC1
      of 2: espionage.CICLevel.CIC2
      of 3: espionage.CICLevel.CIC3
      of 4: espionage.CICLevel.CIC4
      of 5: espionage.CICLevel.CIC5
      else: espionage.CICLevel.CIC1

    let targetCIP = targetHouse.espionageBudget.cipPoints

    # Execute espionage action with detection roll
    let result = esp_executor.executeEspionage(
      attempt,
      targetCICLevel,
      targetCIP,
      rng
    )

    # Apply results
    if result.success:
      info "  SUCCESS: ", result.description

      # Apply prestige changes
      for prestigeEvent in result.attackerPrestigeEvents:
        prestige.applyPrestigeEvent(state, attempt.attacker, prestigeEvent)
      for prestigeEvent in result.targetPrestigeEvents:
        prestige.applyPrestigeEvent(state, attempt.target, prestigeEvent)

      # Create espionage event based on action type
      case attempt.action
      of espionage.EspionageAction.SabotageLow:
        if attempt.targetSystem.isSome:
          events.add(intelligence_events.sabotageConducted(
            attempt.attacker,
            attempt.target,
            attempt.targetSystem.get(),
            result.iuDamage,
            "Low"
          ))
      of espionage.EspionageAction.SabotageHigh:
        if attempt.targetSystem.isSome:
          events.add(intelligence_events.sabotageConducted(
            attempt.attacker,
            attempt.target,
            attempt.targetSystem.get(),
            result.iuDamage,
            "High"
          ))
      of espionage.EspionageAction.TechTheft:
        events.add(intelligence_events.techTheftExecuted(
          attempt.attacker,
          attempt.target,
          result.srpStolen
        ))
      of espionage.EspionageAction.Assassination:
        events.add(intelligence_events.assassinationAttempted(
          attempt.attacker,
          attempt.target,
          globalEspionageConfig.effects.assassination_srp_reduction
        ))
      of espionage.EspionageAction.EconomicManipulation:
        events.add(intelligence_events.economicManipulationExecuted(
          attempt.attacker,
          attempt.target,
          globalEspionageConfig.effects.economic_ncv_reduction
        ))
      of espionage.EspionageAction.CyberAttack:
        if attempt.targetSystem.isSome:
          events.add(intelligence_events.cyberAttackConducted(
            attempt.attacker,
            attempt.target,
            attempt.targetSystem.get()
          ))
      of espionage.EspionageAction.PsyopsCampaign:
        events.add(intelligence_events.psyopsCampaignLaunched(
          attempt.attacker,
          attempt.target,
          globalEspionageConfig.effects.psyops_tax_reduction
        ))
      of espionage.EspionageAction.IntelligenceTheft:
        events.add(intelligence_events.intelligenceTheftExecuted(
          attempt.attacker,
          attempt.target
        ))
      of espionage.EspionageAction.PlantDisinformation:
        events.add(intelligence_events.disinformationPlanted(
          attempt.attacker,
          attempt.target
        ))
      of espionage.EspionageAction.CounterIntelSweep:
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
        if attempt.target in state.houses.entities.index:
          let targetIdx2 = state.houses.entities.index[attempt.target]
          let attackerIdx = state.houses.entities.index[attempt.attacker]
          state.houses.entities.data[targetIdx2].techTree.accumulated.science =
            max(0, state.houses.entities.data[targetIdx2].techTree.accumulated.science - result.srpStolen)
          state.houses.entities.data[attackerIdx].techTree.accumulated.science += result.srpStolen
          info "    Stole ", result.srpStolen, " SRP from ", attempt.target
    else:
      info "  DETECTED by ", attempt.target
      # Apply detection prestige penalties
      for prestigeEvent in result.attackerPrestigeEvents:
        prestige.applyPrestigeEvent(state, attempt.attacker, prestigeEvent)

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
  results: seq[simultaneous.EspionageResult],
  orders: Table[HouseId, OrderPacket],
  rng: var Rand,
  events: var seq[event.GameEvent]
) =
  ## Process successful scout-based espionage results and generate intelligence reports
  ## This is the missing step that actually gathers colony/system/starbase intelligence
  ## from SpyPlanet/SpySystem/HackStarbase orders and populates house.intelligence databases
  ## Also creates detailed narrative events for espionage reports

  for result in results:
    # Consume scout fleet, regardless of outcome
    if result.fleetId in state.fleets.entities.index:
      fleet_ops.destroyFleet(state, result.fleetId)
      info "Spy Scout fleet ", result.fleetId, " consumed on mission."

    # Only process successful espionage for intelligence gathering
    if result.outcome != simultaneous.ResolutionOutcome.Success:
      continue

    if result.actualTarget.isNone:
      continue

    let targetSystem = result.actualTarget.get()
    let houseId = result.houseId

    # Find the original fleet order to determine order type
    if houseId notin orders:
      continue

    let packet = orders[houseId]
    var orderType: FleetCommandType

    # Find matching fleet order
    var found = false
    for command in packet.fleetCommands:
      if command.fleetId == result.fleetId and
         command.targetSystem.isSome and
         command.targetSystem.get() == targetSystem:
        orderType = command.commandType
        found = true
        break

    if not found:
      continue

    # Generate appropriate intelligence based on order type
    case orderType
    of FleetCommandType.SpyPlanet:
      # Generate colony intelligence report
      let intelReport = intel_generator.generateColonyIntelReport(
        state, houseId, targetSystem, intelligence.IntelQuality.Spy)

      if intelReport.isSome:
        let report = intelReport.get()
        let houseIdx = state.houses.entities.index[houseId]
        state.houses.entities.data[houseIdx].intelligence.addColonyReport(report)

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

        # Log success
        let reportCount = state.houses.entities.data[houseIdx].intelligence.colonyReports.len
        info "Fleet ", result.fleetId, " (", houseId, ") SpyPlanet success at ", targetSystem,
             " - intelligence DB now has ", reportCount, " colony reports"

    of FleetCommandType.SpySystem:
      # Generate system intelligence report (fleet composition)
      let intelReport = intel_generator.generateSystemIntelReport(
        state, houseId, targetSystem, intelligence.IntelQuality.Spy)

      if intelReport.isSome:
        let report = intelReport.get()
        let houseIdx = state.houses.entities.index[houseId]
        state.houses.entities.data[houseIdx].intelligence.addSystemReport(report)

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

        info "Fleet ", result.fleetId, " (", houseId, ") SpySystem success at ", targetSystem,
             " - gathered fleet intelligence"

    of FleetCommandType.HackStarbase:
      # Generate starbase intelligence report (economic/R&D data)
      let intelReport = intel_generator.generateStarbaseIntelReport(
        state, houseId, targetSystem, intelligence.IntelQuality.Spy)

      if intelReport.isSome:
        let report = intelReport.get()
        let houseIdx = state.houses.entities.index[houseId]
        state.houses.entities.data[houseIdx].intelligence.addStarbaseReport(report)

        # Check if economic data was acquired (based on quality)
        let hasEconomicData = report.quality == intelligence.IntelQuality.Spy or
                              report.quality == intelligence.IntelQuality.Perfect

        # Get facility data from colony (visible since hack succeeded)
        let colonyIdx = state.colonies.entities.index[targetSystem]
        let colony = state.colonies.entities.data[colonyIdx]
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

        info "Fleet ", result.fleetId, " (", houseId, ") HackStarbase success at ", targetSystem,
             " - gathered economic/R&D intelligence"

    else:
      # Ignore non-espionage orders
      discard
