## Simultaneous Espionage Resolution
##
## Handles simultaneous resolution of SpyPlanet, SpySystem, and HackStarbase orders
## to prevent first-mover advantages in intelligence operations.

import std/[tables, options, random, logging]
import
  ../../types/[core, game_state, simultaneous, command, fleet, espionage, intel, event]
import ../../state/[engine as state_helpers, iterators]
import ../../entities/fleet_ops
import ../../intel/[spy_resolution, generator as intel_generator]
import ../../event_factory/intel
import ../../prestige/engine as prestige
import ./[engine as esp_engine, executor as esp_executor]

proc collectEspionageIntents*(
    state: GameState, orders: Table[HouseId, CommandPacket]
): seq[simultaneous.EspionageIntent] =
  ## Collect all espionage attempts
  result = @[]

  for houseId, house in state.allHousesWithId():
    if houseId notin orders:
      continue

    for command in orders[houseId].fleetCommands:
      if command.commandType notin [
        FleetCommandType.SpyColony, FleetCommandType.SpySystem,
        FleetCommandType.HackStarbase,
      ]:
        continue

      # Validate: fleet exists
      let fleetCheckOpt = state_helpers.fleet(state, command.fleetId)
      if fleetCheckOpt.isNone:
        continue

      # Calculate espionage strength using house prestige
      # Higher prestige = better intelligence operations
      let espionageStrength = house.prestige

      # Get target from order
      if command.targetSystem.isNone:
        continue

      let targetSystem = command.targetSystem.get()

      # Log if fleet not at target (will attempt movement in Maintenance Phase)
      let fleetOpt = state_helpers.fleet(state, command.fleetId)
      if fleetOpt.isSome:
        let fleet = fleetOpt.get()
        if fleet.location != targetSystem:
          debug "Espionage order queued: ",
            command.fleetId, " will move from ", fleet.location, " to ", targetSystem

      result.add(
        simultaneous.EspionageIntent(
          houseId: houseId,
          fleetId: command.fleetId,
          targetSystem: targetSystem,
          orderType: $command.commandType,
          espionageStrength: espionageStrength,
        )
      )

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
    result.add(
      simultaneous.EspionageConflict(
        targetSystem: systemId, intents: conflictingIntents
      )
    )

proc resolveEspionageConflict*(
    state: var GameState,
    conflict: simultaneous.EspionageConflict,
    rng: var Rand,
    events: var seq[event.GameEvent],
): seq[simultaneous.EspionageResult] =
  ## Resolve espionage conflict by performing detection checks for each intent.
  result = @[]

  if conflict.intents.len == 0:
    return

  for intent in conflict.intents:
    let detected = spy_resolution.resolveSpyScoutDetection(
      state, intent.houseId, intent.fleetId, intent.targetSystem, rng
    )

    var outcome: simultaneous.ResolutionOutcome
    if detected:
      outcome = simultaneous.ResolutionOutcome.ConflictLost
      # Try to find colony at target system (ColonyId typically matches SystemId)
      let colonyOpt = state_helpers.colonyBySystem(state, intent.targetSystem)
      if colonyOpt.isSome:
        let defender = colonyOpt.get().owner
        events.add(
          intel.scoutDetected(
            intent.houseId, defender, intent.targetSystem, "Spy Scout"
          )
        )
    else:
      outcome = simultaneous.ResolutionOutcome.Success

    result.add(
      simultaneous.EspionageResult(
        houseId: intent.houseId,
        fleetId: intent.fleetId,
        originalTarget: intent.targetSystem,
        outcome: outcome,
        actualTarget:
          if outcome == simultaneous.ResolutionOutcome.Success:
            some(intent.targetSystem)
          else:
            none(SystemId),
        prestigeAwarded: 0, # Prestige handled elsewhere
      )
    )

proc resolveEspionage*(
    state: var GameState,
    orders: Table[HouseId, CommandPacket],
    rng: var Rand,
    events: var seq[event.GameEvent],
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
    results: seq[simultaneous.EspionageResult], houseId: HouseId, fleetId: FleetId
): bool =
  ## Check if an espionage order was already handled
  for result in results:
    if result.houseId == houseId and result.fleetId == fleetId:
      return true
  return false

proc processEspionageActions*(
    state: var GameState,
    orders: Table[HouseId, CommandPacket],
    rng: var Rand,
    events: var seq[event.GameEvent],
) =
  ## Process CommandPacket.espionageAction for all houses
  ## This handles EBP-based espionage actions (TechTheft, Assassination, etc.)
  ## separate from fleet-based espionage orders

  for houseId, _ in state.allHousesWithId():
    if houseId notin orders:
      continue

    # Get mutable copy of house for modifications
    let houseOpt = state_helpers.house(state, houseId)
    if houseOpt.isNone:
      continue
    var house = houseOpt.get()

    let packet = orders[houseId]

    # Step 1: Process EBP/CIP investments (purchase points with PP)
    if packet.ebpInvestment > 0:
      let ebpPurchased =
        esp_engine.purchaseEBP(house.espionageBudget, packet.ebpInvestment)
      # Deduct PP from treasury (already projected in AI, but need to deduct actual cost)
      house.treasury -= packet.ebpInvestment
      info houseId,
        " purchased ", ebpPurchased, " EBP for ", packet.ebpInvestment, " PP"

    if packet.cipInvestment > 0:
      let cipPurchased =
        esp_engine.purchaseCIP(house.espionageBudget, packet.cipInvestment)
      house.treasury -= packet.cipInvestment
      info houseId,
        " purchased ", cipPurchased, " CIP for ", packet.cipInvestment, " PP"

    # Step 2: Execute espionage action if present
    if packet.espionageAction.isNone:
      # Update house if investments were made
      if packet.ebpInvestment > 0 or packet.cipInvestment > 0:
        state.updateHouse(houseId, house)
      continue

    let attempt = packet.espionageAction.get()

    # Validate target house is not eliminated (leaderboard is public info)
    let targetOpt = state_helpers.house(state, attempt.target)
    if targetOpt.isSome and targetOpt.get().isEliminated:
      debug houseId, " cannot target eliminated house ", attempt.target
      # Update house before continuing
      state.updateHouse(houseId, house)
      continue

    # Check if attacker has sufficient EBP
    let actionCost = esp_engine.getActionCost(attempt.action)
    if not esp_engine.canAffordAction(house.espionageBudget, attempt.action):
      debug houseId,
        " cannot afford ", attempt.action, " (cost: ", actionCost, " EBP, has: ",
        house.espionageBudget.ebpPoints, ")"
      # Update house before continuing
      state.updateHouse(houseId, house)
      continue

    # Spend EBP
    if not esp_engine.spendEBP(house.espionageBudget, attempt.action):
      debug houseId, " failed to spend EBP for ", attempt.action
      # Update house before continuing
      state.updateHouse(houseId, house)
      continue

    info houseId,
      " executing ", attempt.action, " against ", attempt.target, " (cost: ",
      actionCost, " EBP)"

    # Get target's CIC level from tech tree
    let targetHouseOpt = state_helpers.house(state, attempt.target)
    if targetHouseOpt.isNone:
      # Update house before continuing
      state.updateHouse(houseId, house)
      continue
    let targetHouse = targetHouseOpt.get()
    let targetCICLevel =
      case targetHouse.techTree.levels.cic
      of 1: espionage.CICLevel.CIC1
      of 2: espionage.CICLevel.CIC2
      of 3: espionage.CICLevel.CIC3
      of 4: espionage.CICLevel.CIC4
      of 5: espionage.CICLevel.CIC5
      else: espionage.CICLevel.CIC1

    let targetCIP = targetHouse.espionageBudget.cipPoints

    # Execute espionage action with detection roll
    let result = esp_executor.executeEspionage(attempt, targetCICLevel, targetCIP, rng)

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
          events.add(
            sabotageConducted(
              attempt.attacker,
              attempt.target,
              attempt.targetSystem.get(),
              result.iuDamage,
              "Low",
            )
          )
      of espionage.EspionageAction.SabotageHigh:
        if attempt.targetSystem.isSome:
          events.add(
            sabotageConducted(
              attempt.attacker,
              attempt.target,
              attempt.targetSystem.get(),
              result.iuDamage,
              "High",
            )
          )
      of espionage.EspionageAction.TechTheft:
        events.add(
          techTheftExecuted(
            attempt.attacker, attempt.target, result.srpStolen
          )
        )
      of espionage.EspionageAction.Assassination:
        events.add(
          assassinationAttempted(
            attempt.attacker, attempt.target,
            globalEspionageConfig.effects.assassination_srp_reduction,
          )
        )
      of espionage.EspionageAction.EconomicManipulation:
        events.add(
          economicManipulationExecuted(
            attempt.attacker, attempt.target,
            globalEspionageConfig.effects.economic_ncv_reduction,
          )
        )
      of espionage.EspionageAction.CyberAttack:
        if attempt.targetSystem.isSome:
          events.add(
            cyberAttackConducted(
              attempt.attacker, attempt.target, attempt.targetSystem.get()
            )
          )
      of espionage.EspionageAction.PsyopsCampaign:
        events.add(
          psyopsCampaignLaunched(
            attempt.attacker, attempt.target,
            globalEspionageConfig.effects.psyops_tax_reduction,
          )
        )
      of espionage.EspionageAction.IntelTheft:
        events.add(
          intelTheftExecuted(
            attempt.attacker, attempt.target
          )
        )
      of espionage.EspionageAction.PlantDisinformation:
        events.add(
          disinformationPlanted(attempt.attacker, attempt.target)
        )
      of espionage.EspionageAction.CounterIntelSweep:
        if attempt.targetSystem.isSome:
          events.add(
            counterIntelSweepExecuted(
              attempt.attacker, attempt.targetSystem.get()
            )
          )

      # Apply ongoing effects
      if result.effect.isSome:
        state.ongoingEffects.add(result.effect.get())

      # Apply immediate effects (SRP theft, IU damage, etc.)
      if result.srpStolen > 0:
        let targetHouseOpt = state_helpers.house(state, attempt.target)
        let attackerHouseOpt = state_helpers.house(state, attempt.attacker)

        if targetHouseOpt.isSome and attackerHouseOpt.isSome:
          var targetHouse = targetHouseOpt.get()
          var attackerHouse = attackerHouseOpt.get()

          targetHouse.techTree.accumulated.science = max(
            0,
            targetHouse.techTree.accumulated.science - result.srpStolen
          )
          attackerHouse.techTree.accumulated.science += result.srpStolen

          state.updateHouse(attempt.target, targetHouse)
          state.updateHouse(attempt.attacker, attackerHouse)

          info "    Stole ", result.srpStolen, " SRP from ", attempt.target
    else:
      info "  DETECTED by ", attempt.target
      # Apply detection prestige penalties
      for prestigeEvent in result.attackerPrestigeEvents:
        prestige.applyPrestigeEvent(state, attempt.attacker, prestigeEvent)

      # Create detection event
      if attempt.targetSystem.isSome:
        events.add(
          spyMissionDetected(
            attempt.attacker,
            attempt.target,
            attempt.targetSystem.get(),
            $attempt.action,
          )
        )

    # Update house entity after espionage action resolution
    state.updateHouse(houseId, house)

proc processScoutIntelligence*(
    state: var GameState,
    results: seq[simultaneous.EspionageResult],
    orders: Table[HouseId, CommandPacket],
    rng: var Rand,
    events: var seq[event.GameEvent],
) =
  ## Process successful scout-based espionage results and generate intelligence reports
  ## This is the missing step that actually gathers colony/system/starbase intelligence
  ## from SpyPlanet/SpySystem/HackStarbase orders and populates house.intelligence databases
  ## Also creates detailed narrative events for espionage reports

  for result in results:
    # Consume scout fleet, regardless of outcome
    if result.fleetId in state.hasFleet:
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
      if command.fleetId == result.fleetId and command.targetSystem.isSome and
          command.targetSystem.get() == targetSystem:
        orderType = command.commandType
        found = true
        break

    if not found:
      continue

    # Generate appropriate intelligence based on order type
    case orderType
    of FleetCommandType.SpyColony:
      # Generate colony intelligence report
      let intelReport = intel_generator.generateColonyIntelReport(
        state, houseId, targetSystem, intelligence.IntelQuality.Spy
      )

      if intelReport.isSome:
        let report = intelReport.get()
        let houseOpt = state_helpers.house(state, houseId)
        if houseOpt.isSome:
          var house = houseOpt.get()
          house.intelligence.addColonyReport(report)
          state.updateHouse(houseId, house)

          # Calculate economic value for event
          let grossOutput = report.grossOutput.get(0)
          let industryValue = report.industry * 100
          let economicValue = grossOutput + industryValue
          let totalDefenses = report.defenses + report.starbaseLevel * 10

          # Create rich narrative event (visible only to spy house)
          # Scout-specific: SpyPlanet mission by scout fleet
          events.add(
            scoutColonyIntelGathered(
              houseId,
              report.targetOwner,
              targetSystem,
              result.fleetId,
              totalDefenses,
              economicValue,
              report.starbaseLevel > 0,
              $report.quality,
            )
          )

          # Log success
          let reportCount = house.intelligence.colonyReports.len
          info "Fleet ",
            result.fleetId, " (", houseId, ") SpyPlanet success at ", targetSystem,
            " - intelligence DB now has ", reportCount, " colony reports"
    of FleetCommandType.SpySystem:
      # Generate system intelligence report (fleet composition)
      let intelReport = intel_generator.generateSystemIntelReport(
        state, houseId, targetSystem, intelligence.IntelQuality.Spy
      )

      if intelReport.isSome:
        let package = intelReport.get()

        # Store system intel report in intelligence database
        if houseId in state.intelligence:
          state.intelligence[houseId].systemReports[targetSystem] = package.report

        # Count detected fleets and ships
        let fleetsDetected = package.fleetIntel.len
        var shipsDetected = 0
        for (fleetId, intel) in package.fleetIntel:
          shipsDetected += intel.shipCount

        # Determine target house (first fleet's owner, or none if empty)
        let targetHouse =
          if fleetsDetected > 0:
            package.fleetIntel[0].intel.owner
          else:
            houseId # Fallback

        # Create rich narrative event (visible only to spy house)
        # Scout-specific: SpySystem mission by scout fleet
        events.add(
          scoutSystemIntelGathered(
            houseId,
            targetHouse,
            targetSystem,
            result.fleetId,
            fleetsDetected,
            shipsDetected,
            $report.quality,
          )
        )

        info "Fleet ",
          result.fleetId, " (", houseId, ") SpySystem success at ", targetSystem,
          " - gathered fleet intelligence"
    of FleetCommandType.HackStarbase:
      # Generate starbase intelligence report (economic/R&D data)
      let intelReport = intel_generator.generateStarbaseIntelReport(
        state, houseId, targetSystem, intelligence.IntelQuality.Spy
      )

      if intelReport.isSome:
        let report = intelReport.get()
        let houseOpt = state_helpers.house(state, houseId)
        if houseOpt.isSome:
          var house = houseOpt.get()
          house.intelligence.addStarbaseReport(report)
          state.updateHouse(houseId, house)

        # Check if economic data was acquired (based on quality)
        let hasEconomicData =
          report.quality == IntelQuality.Spy or
          report.quality == IntelQuality.Perfect

        # Get facility data from colony (visible since hack succeeded)
        let colonyOpt = state_helpers.colonyBySystem(state, targetSystem)
        if colonyOpt.isSome:
          let colony = colonyOpt.get()

          # TODO: Refactor to use GameState entity managers for facilities
          # Facilities are now in state.starbases, state.spaceports, state.shipyards
          # Construction/repair queues are in separate systems
          let starbaseCount = 0  # TODO: Query state.starbases for this colony
          let spaceportCount = 0 # TODO: Query state.spaceports for this colony
          let shipyardCount = 0  # TODO: Query state.shipyards for this colony
          let totalDocks = 0     # TODO: Calculate from facility entities
          let shipsUnderConstruction = 0  # TODO: Query construction system
          let shipsUnderRepair = 0         # TODO: Query repair system

          # Create rich narrative event (visible only to spy house)
          # Scout-specific: HackStarbase mission by scout fleet
          events.add(
            scoutStarbaseIntelGathered(
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
              $report.quality,
            )
          )

          info "Fleet ",
            result.fleetId, " (", houseId, ") HackStarbase success at ", targetSystem,
            " - gathered economic/R&D intelligence"
    else:
      # Ignore non-espionage orders
      discard
