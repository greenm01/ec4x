## Espionage Resolution System
##
## Resolves scout-based intelligence operations and EBP-based espionage actions.
## Operations are independent (not competitive conflicts).
##
## **Two Espionage Systems** (per docs/specs/09-intel-espionage.md):
##
## 1. **Scout Intelligence Operations** (Section 9.1.1)
##    - Fleet commands: SpyColony, SpySystem, HackStarbase
##    - Scouts travel to target, establish persistent operations
##    - Detection checks each turn (may be destroyed if detected)
##    - Provides Perfect Quality intelligence if successful
##
## 2. **EBP-Based Espionage Actions** (Section 9.2)
##    - CommandPacket.espionageAction field
##    - Actions: TechTheft, Assassination, Sabotage, etc.
##    - Cost EBP points (40 PP each)
##    - Subject to CIC detection rolls
##    - Maximum one action per turn per house
##
## **Architecture Compliance** (src/engine/architecture.md):
## - Uses state layer APIs (UFCS pattern)
## - Uses iterators for batch access
## - Uses entity ops for mutations
## - Uses common/logger for logging

import std/[tables, options, random, sequtils]
import ../../types/[core, game_state, command, fleet, espionage, intel, event, facilities]
import ../../state/[engine, iterators]
import ../../entities/fleet_ops
import ../../intel/[spy_resolution, generator as intel_generator]
import ../../event_factory/intel
import ../../prestige/engine as prestige
import ../../globals
import ../../../common/logger
import ./[engine as esp_engine, executor as esp_executor]

proc collectScoutOperations*(
    state: GameState, orders: Table[HouseId, CommandPacket]
): seq[espionage.ScoutIntelOperation] =
  ## Collect all scout-based intelligence operations from orders
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
      let fleetCheckOpt = state.fleet(command.fleetId)
      if fleetCheckOpt.isNone:
        continue

      # Calculate espionage strength using house prestige
      # Higher prestige = better intel operations
      let espionageStrength = house.prestige

      # Get target from order
      if command.targetSystem.isNone:
        continue

      let targetSystem = command.targetSystem.get()

      # Log if fleet not at target (will attempt movement in Maintenance Phase)
      let fleetOpt = state.fleet(command.fleetId)
      if fleetOpt.isSome:
        let fleet = fleetOpt.get()
        if fleet.location != targetSystem:
          logDebug(
            "Espionage",
            "Order queued: fleet will move",
            " fleetId=",
            command.fleetId,
            " from=",
            fleet.location,
            " to=",
            targetSystem,
          )

      result.add(
        espionage.ScoutIntelOperation(
          houseId: houseId,
          fleetId: command.fleetId,
          targetSystem: targetSystem,
          orderType: $command.commandType,
          espionageStrength: espionageStrength,
        )
      )

proc resolveScoutOperation*(
    state: var GameState,
    operation: espionage.ScoutIntelOperation,
    rng: var Rand,
    events: var seq[event.GameEvent],
): espionage.ScoutIntelResult =
  ## Resolve a single scout intelligence operation
  ## Each operation is independent (no conflict resolution)
  ## Per docs/specs/09-intel-espionage.md Section 9.1.1

  # Detection check
  let detected = spy_resolution.resolveSpyScoutDetection(
    state, operation.houseId, operation.fleetId, operation.targetSystem, rng
  )

  if detected:
    # Scout detected - operation fails
    let colonyOpt = state.colonyBySystem(operation.targetSystem)
    if colonyOpt.isSome:
      let defender = colonyOpt.get().owner
      events.add(
        intel.scoutDetected(
          operation.houseId, defender, operation.targetSystem, "Spy Scout"
        )
      )

    return espionage.ScoutIntelResult(
      houseId: operation.houseId,
      fleetId: operation.fleetId,
      targetSystem: operation.targetSystem,
      detected: true,
      intelligenceGathered: false,
    )
  else:
    # Scout undetected - operation succeeds
    return espionage.ScoutIntelResult(
      houseId: operation.houseId,
      fleetId: operation.fleetId,
      targetSystem: operation.targetSystem,
      detected: false,
      intelligenceGathered: true,
    )

proc resolveEspionage*(
    state: var GameState,
    orders: Table[HouseId, CommandPacket],
    rng: var Rand,
    events: var seq[event.GameEvent],
): seq[espionage.ScoutIntelResult] =
  ## Main entry point: Resolve all scout-based intelligence operations
  ## Operations are processed independently (no conflict resolution needed)
  ## Per docs/specs/09-intel-espionage.md Section 9.1.1
  result = @[]

  let operations = collectScoutOperations(state, orders)
  if operations.len == 0:
    return

  logInfo("Espionage", "Resolving scout operations", " count=", operations.len)

  # Process each operation independently
  for operation in operations:
    let operationResult = resolveScoutOperation(state, operation, rng, events)
    result.add(operationResult)

  let successful = result.filterIt(it.intelligenceGathered).len
  let detected = result.filterIt(it.detected).len
  logInfo(
    "Espionage",
    "Scout operations resolved",
    " total=",
    result.len,
    " successful=",
    successful,
    " detected=",
    detected,
  )

proc wasEspionageHandled*(
    results: seq[espionage.ScoutIntelResult], houseId: HouseId, fleetId: FleetId
): bool =
  ## Check if a scout operation was already handled
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
    let houseOpt = state.house(houseId)
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
      logInfo(
        "Espionage",
        "EBP purchased",
        " house=",
        houseId,
        " ebp=",
        ebpPurchased,
        " cost=",
        packet.ebpInvestment,
        " PP",
      )

    if packet.cipInvestment > 0:
      let cipPurchased =
        esp_engine.purchaseCIP(house.espionageBudget, packet.cipInvestment)
      house.treasury -= packet.cipInvestment
      logInfo(
        "Espionage",
        "CIP purchased",
        " house=",
        houseId,
        " cip=",
        cipPurchased,
        " cost=",
        packet.cipInvestment,
        " PP",
      )

    # Step 2: Execute espionage action if present
    if packet.espionageAction.isNone:
      # Update house if investments were made
      if packet.ebpInvestment > 0 or packet.cipInvestment > 0:
        state.updateHouse(houseId, house)
      continue

    let attempt = packet.espionageAction.get()

    # Validate target house is not eliminated (leaderboard is public info)
    let targetOpt = state.house(attempt.target)
    if targetOpt.isSome and targetOpt.get().isEliminated:
      logDebug(
        "Espionage",
        "Cannot target eliminated house",
        " attacker=",
        houseId,
        " target=",
        attempt.target,
      )
      # Update house before continuing
      state.updateHouse(houseId, house)
      continue

    # Check if attacker has sufficient EBP
    let actionCost = esp_engine.getActionCost(attempt.action)
    if not esp_engine.canAffordAction(house.espionageBudget, attempt.action):
      logDebug(
        "Espionage",
        "Insufficient EBP",
        " house=",
        houseId,
        " action=",
        attempt.action,
        " cost=",
        actionCost,
        " has=",
        house.espionageBudget.ebpPoints,
      )
      # Update house before continuing
      state.updateHouse(houseId, house)
      continue

    # Spend EBP
    if not esp_engine.spendEBP(house.espionageBudget, attempt.action):
      logDebug(
        "Espionage",
        "Failed to spend EBP",
        " house=",
        houseId,
        " action=",
        attempt.action,
      )
      # Update house before continuing
      state.updateHouse(houseId, house)
      continue

    logInfo(
      "Espionage",
      "Executing action",
      " attacker=",
      houseId,
      " target=",
      attempt.target,
      " action=",
      attempt.action,
      " cost=",
      actionCost,
      " EBP",
    )

    # Get target's CIC level from tech tree
    let targetHouseOpt = state.house(attempt.target)
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
      logInfo("Espionage", "Action SUCCESS", " desc=", result.description)

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
            gameConfig.espionage.effects.assassination_srp_reduction,
          )
        )
      of espionage.EspionageAction.EconomicManipulation:
        events.add(
          economicManipulationExecuted(
            attempt.attacker, attempt.target,
            gameConfig.espionage.effects.economic_ncv_reduction,
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
            gameConfig.espionage.effects.psyops_tax_reduction,
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
        let targetHouseOpt = state.house(attempt.target)
        let attackerHouseOpt = state.house(attempt.attacker)

        if targetHouseOpt.isSome and attackerHouseOpt.isSome:
          var targetHouse = targetHouseOpt.get()
          var attackerHouse = attackerHouseOpt.get()

          targetHouse.techTree.accumulated.science = max(
            0, targetHouse.techTree.accumulated.science - result.srpStolen
          )
          attackerHouse.techTree.accumulated.science += result.srpStolen

          state.updateHouse(attempt.target, targetHouse)
          state.updateHouse(attempt.attacker, attackerHouse)

          logInfo(
            "Espionage",
            "SRP stolen",
            " from=",
            attempt.target,
            " amount=",
            result.srpStolen,
          )
    else:
      logInfo(
        "Espionage", "Action DETECTED", " attacker=", houseId, " defender=", attempt.target
      )
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

proc processScoutIntel*(
    state: var GameState,
    results: seq[espionage.ScoutIntelResult],
    orders: Table[HouseId, CommandPacket],
    rng: var Rand,
    events: var seq[event.GameEvent],
) =
  ## Process successful scout intelligence results and generate intelligence reports
  ## Gathers colony/system/starbase intelligence from SpyPlanet/SpySystem/HackStarbase
  ## operations and stores in house.intel databases
  ## Per docs/specs/09-intel-espionage.md Section 9.1.1

  for result in results:
    # Consume scout fleet, regardless of outcome
    if result.fleetId in state.fleets.entities.index:
      fleet_ops.destroyFleet(state, result.fleetId)
      logInfo(
        "Espionage",
        "Scout fleet consumed",
        " fleetId=",
        result.fleetId,
      )

    # Only process successful operations for intel gathering
    if not result.intelligenceGathered:
      continue

    let targetSystem = result.targetSystem
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
        state, houseId, targetSystem, IntelQuality.Spy
      )

      if intelReport.isSome:
        let report = intelReport.get()
        let houseOpt = state.house(houseId)
        if houseOpt.isSome:
          var house = houseOpt.get()
          house.intel.colonyReports[report.colonyId] = report
          state.updateHouse(houseId, house)

          # Calculate economic value for event
          let grossOutput = report.grossOutput.get(0)
          let infrastructureValue = report.infrastructure * 100
          let economicValue = grossOutput + infrastructureValue
          # Calculate total ground defenses (batteries, armies, marines)
          let totalDefenses =
            report.groundBatteryCount + report.armyCount + report.marineCount

          # Create rich narrative event (visible only to spy house)
          # Scout-specific: SpyPlanet mission by scout fleet
          # Note: hasStarbase=false for colony intel (orbital intel needed for starbase)
          events.add(
            scoutColonyIntelGathered(
              houseId,
              report.targetOwner,
              targetSystem,
              result.fleetId,
              totalDefenses,
              economicValue,
              false, # Colony intel doesn't include orbital starbase data
              $report.quality,
            )
          )

          # Log success
          let reportCount = house.intel.colonyReports.len
          logInfo(
            "Espionage",
            "SpyPlanet success",
            " fleet=",
            result.fleetId,
            " house=",
            houseId,
            " target=",
            targetSystem,
            " reports=",
            reportCount,
          )
    of FleetCommandType.SpySystem:
      # Generate system intel report (fleet composition)
      let intelReport = intel_generator.generateSystemIntelReport(
        state, houseId, targetSystem, IntelQuality.Spy
      )

      if intelReport.isSome:
        let package = intelReport.get()

        # Store system intel report in house intel database
        let houseOpt = state.house(houseId)
        if houseOpt.isSome:
          var house = houseOpt.get()
          house.intel.systemReports[targetSystem] = package.report
          state.updateHouse(houseId, house)

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
            $package.report.quality,
          )
        )

        logInfo(
          "Espionage",
          "SpySystem success",
          " fleet=",
          result.fleetId,
          " house=",
          houseId,
          " target=",
          targetSystem,
        )
    of FleetCommandType.HackStarbase:
      # Generate starbase intel report (economic/R&D data)
      let intelReport = intel_generator.generateStarbaseIntelReport(
        state, houseId, targetSystem, IntelQuality.Spy
      )

      if intelReport.isSome:
        let report = intelReport.get()
        let houseOpt = state.house(houseId)
        if houseOpt.isSome:
          var house = houseOpt.get()
          house.intel.starbaseReports[report.kastraId] = report
          state.updateHouse(houseId, house)

        # Check if economic data was acquired (based on quality)
        let hasEconomicData =
          report.quality == IntelQuality.Spy or report.quality == IntelQuality.Perfect

        # Get facility data from colony (visible since hack succeeded)
        let colonyOpt = state.colonyBySystem(targetSystem)
        if colonyOpt.isSome:
          let colony = colonyOpt.get()

          # Query facility counts using entity manager
          # Neorias (production facilities): Spaceport, Shipyard, Drydock
          # Kastras (defensive facilities): Starbase
          let kastraCount = colony.kastraIds.len
          var spaceportCount = 0
          var shipyardCount = 0
          var drydockCount = 0
          var totalDocks = 0

          for neoriaId in colony.neoriaIds:
            let neoriaOpt = state.neoria(neoriaId)
            if neoriaOpt.isSome:
              let neoria = neoriaOpt.get()
              case neoria.neoriaClass
              of NeoriaClass.Spaceport:
                spaceportCount += 1
                totalDocks += neoria.effectiveDocks
              of NeoriaClass.Shipyard:
                shipyardCount += 1
                totalDocks += neoria.effectiveDocks
              of NeoriaClass.Drydock:
                drydockCount += 1
                totalDocks += neoria.effectiveDocks

          # TODO: Query construction/repair queues from production system
          let shipsUnderConstruction = 0 # Would need production system access
          let shipsUnderRepair = 0 # Would need repair system access

          # Create rich narrative event (visible only to spy house)
          # Scout-specific: HackStarbase mission by scout fleet
          events.add(
            scoutStarbaseIntelGathered(
              houseId,
              report.targetOwner,
              targetSystem,
              result.fleetId,
              kastraCount,
              spaceportCount,
              shipyardCount,
              totalDocks,
              shipsUnderConstruction,
              shipsUnderRepair,
              hasEconomicData,
              $report.quality,
            )
          )

          logInfo(
            "Espionage",
            "HackStarbase success",
            " fleet=",
            result.fleetId,
            " house=",
            houseId,
            " target=",
            targetSystem,
          )
    else:
      # Ignore non-espionage orders
      discard
