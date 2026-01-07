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

import std/[tables, options, random]
import ../../types/[core, game_state, command, fleet, espionage, intel, event]
import ../../state/[engine, iterators, fleet_queries]
import ../../entities/fleet_ops
import ../../intel/[spy_resolution, generator as intel_generator]
import ../../event_factory/intel
import ../../prestige/engine as prestige
import ../../globals
import ../../../common/logger
import ./[engine as esp_engine, executor as esp_executor]

# Forward declaration helper
proc generateMissionIntel(
    state: var GameState,
    missionType: SpyMissionType,
    targetSystem: SystemId,
    ownerHouse: HouseId,
    events: var seq[event.GameEvent]
)

proc resolveScoutMissions*(
    state: var GameState,
    rng: var Rand,
    events: var seq[event.GameEvent]
) =
  ## Unified scout mission processing for both new and existing missions
  ## Handles both Conflict Phase Step 6a (new) and Step 6a.5 (existing)
  ##
  ## Phase 1: NEW missions (Step 6a - from arrivedFleets)
  ##   - Process spy commands where fleet arrived this turn
  ##   - Transition Traveling → OnSpyMission
  ##   - Run first detection check (gates mission registration)
  ##   - If detected: Destroy fleet, diplomatic escalation
  ##   - If undetected: Register in activeSpyMissions, generate Perfect intel
  ##
  ## Phase 2: EXISTING missions (Step 6a.5 - from activeSpyMissions)
  ##   - Process missions from previous turns (startTurn < state.turn)
  ##   - Run ongoing detection checks
  ##   - If detected: Destroy fleet, end mission
  ##   - If undetected: Generate Perfect intel, continue mission
  ##
  ## Per:
  ##   - docs/engine/mechanics/scout-espionage-system.md
  ##   - docs/engine/architecture/ec4x_canonical_turn_cycle.md

  logInfo("Espionage", "=== Resolving Scout Missions ===")

  # ==================================================================
  # PHASE 1: NEW MISSIONS (Step 6a - Mission Start & First Detection)
  # ==================================================================
  logInfo("Espionage", "[Step 6a] Processing new scout missions...")

  var newMissionsProcessed = 0

  # Use iterator: fleetsWithArrivedConflictCommands filters spy commands
  for (fleetId, fleet, command) in state.fleetsWithArrivedConflictCommands():
    # Filter for spy mission types only
    if command.commandType notin [
      FleetCommandType.SpyColony,
      FleetCommandType.SpySystem,
      FleetCommandType.HackStarbase
    ]:
      continue

    # Validate scout-only fleet
    if not state.isScoutOnly(fleet):
      logWarn("Espionage", "Non-scout ships in spy mission fleet",
        " fleetId=", fleetId)
      continue

    # Validate Traveling state (should be arriving from Production Phase)
    if fleet.missionState != MissionState.Traveling:
      logWarn("Espionage", "Fleet not in Traveling state",
        " fleetId=", fleetId, " state=", fleet.missionState)
      continue

    # Get scout count using fleet query
    let scoutCount = state.countScoutShips(fleet)
    if scoutCount == 0:
      logWarn("Espionage", "No scouts in fleet", " fleetId=", fleetId)
      continue

    # Get target and defender
    let targetSystem = command.targetSystem.get()  # Validated by iterator
    let colonyOpt = state.colonyBySystem(targetSystem)
    if colonyOpt.isNone:
      logWarn("Espionage", "No colony at target",
        " system=", targetSystem)
      continue

    let defender = colonyOpt.get().owner

    # TRANSITION: Traveling → OnSpyMission (before detection)
    var updatedFleet = fleet
    updatedFleet.missionState = MissionState.ScoutLocked
    updatedFleet.missionStartTurn = state.turn
    state.updateFleet(fleetId, updatedFleet)

    # RUN FIRST DETECTION CHECK (gates mission registration)
    let detectionResult = spy_resolution.resolveScoutDetection(
      state, scoutCount, defender, targetSystem, rng
    )

    if detectionResult.detected:
      # DETECTED: Mission fails - destroy fleet
      logInfo("Espionage", "New mission detected on start",
        " fleetId=", fleetId, " scouts=", scoutCount,
        " roll=", detectionResult.roll, " target=", detectionResult.threshold)

      fleet_ops.destroyFleet(state, fleetId)

      # Generate detection event + diplomatic escalation
      events.add(intel.scoutDetected(
        fleet.houseId, defender, targetSystem, "Scout"
      ))

    else:
      # UNDETECTED: Mission succeeds - register for persistence
      logInfo("Espionage", "New mission started successfully",
        " fleetId=", fleetId, " scouts=", scoutCount)

      # Convert command type to mission type
      let missionType = case command.commandType
        of FleetCommandType.SpyColony: SpyMissionType.SpyOnPlanet
        of FleetCommandType.SpySystem: SpyMissionType.SpyOnSystem
        of FleetCommandType.HackStarbase: SpyMissionType.HackStarbase
        else: SpyMissionType.SpyOnPlanet  # Unreachable

      # REGISTER IN ACTIVE SPY MISSIONS
      state.activeSpyMissions[fleetId] = ActiveSpyMission(
        fleetId: fleetId,
        missionType: missionType,
        targetSystem: targetSystem,
        scoutCount: scoutCount,
        startTurn: state.turn,  # CRITICAL: For filtering in Phase 2
        ownerHouse: fleet.houseId
      )

      # Generate Perfect quality intel (first turn)
      generateMissionIntel(state, missionType, targetSystem, fleet.houseId, events)

    newMissionsProcessed += 1

  logInfo("Espionage", "[Step 6a] Complete",
    " new_missions=", newMissionsProcessed)

  # ==================================================================
  # PHASE 2: EXISTING MISSIONS (Step 6a.5 - Persistent Detection)
  # ==================================================================
  logInfo("Espionage", "[Step 6a.5] Processing existing missions...")

  var existingMissionsProcessed = 0
  var missionsToRemove: seq[FleetId] = @[]

  for fleetId, mission in state.activeSpyMissions.pairs:
    # CRITICAL FILTER: Skip missions that started THIS turn
    # They already had first detection in Phase 1 above
    if mission.startTurn >= state.turn:
      logDebug("Espionage", "Skipping newly-started mission",
        " fleetId=", fleetId, " startTurn=", mission.startTurn)
      continue

    # Validate fleet still exists
    let fleetOpt = state.fleet(fleetId)
    if fleetOpt.isNone:
      logWarn("Espionage", "Mission fleet no longer exists",
        " fleetId=", fleetId)
      missionsToRemove.add(fleetId)
      continue

    # Validate target still exists
    let colonyOpt = state.colonyBySystem(mission.targetSystem)
    if colonyOpt.isNone:
      logInfo("Espionage", "Target colony lost, ending mission",
        " fleetId=", fleetId)
      missionsToRemove.add(fleetId)
      continue

    let defender = colonyOpt.get().owner

    # RUN PERSISTENT DETECTION CHECK
    let detectionResult = spy_resolution.resolveScoutDetection(
      state, mission.scoutCount, defender, mission.targetSystem, rng
    )

    if detectionResult.detected:
      # DETECTED: Mission fails - destroy fleet
      logInfo("Espionage", "Existing mission detected",
        " fleetId=", fleetId, " turnsActive=", state.turn - mission.startTurn,
        " roll=", detectionResult.roll, " target=", detectionResult.threshold)

      fleet_ops.destroyFleet(state, fleetId)
      missionsToRemove.add(fleetId)

      # Generate detection event + diplomatic escalation
      events.add(intel.scoutDetected(
        mission.ownerHouse, defender, mission.targetSystem, "Scout"
      ))

    else:
      # UNDETECTED: Generate Perfect intel, continue mission
      logDebug("Espionage", "Mission continues",
        " fleetId=", fleetId, " turnsActive=", state.turn - mission.startTurn)

      # Generate Perfect quality intel (ongoing)
      generateMissionIntel(
        state, mission.missionType, mission.targetSystem,
        mission.ownerHouse, events
      )

    existingMissionsProcessed += 1

  # Remove ended missions
  for fleetId in missionsToRemove:
    state.activeSpyMissions.del(fleetId)

  logInfo("Espionage", "[Step 6a.5] Complete",
    " existing_missions=", existingMissionsProcessed,
    " ended=", missionsToRemove.len)

proc generateMissionIntel(
    state: var GameState,
    missionType: SpyMissionType,
    targetSystem: SystemId,
    ownerHouse: HouseId,
    events: var seq[event.GameEvent]
) =
  ## Generate Perfect quality intelligence based on mission type
  ## Called for both new missions (first turn) and ongoing missions

  case missionType
  of SpyMissionType.SpyOnPlanet:
    # Generate colony intel (Perfect quality)
    let intelReport = intel_generator.generateColonyIntelReport(
      state, ownerHouse, targetSystem, IntelQuality.Perfect
    )
    if intelReport.isSome:
      let report = intelReport.get()
      let houseOpt = state.house(ownerHouse)
      if houseOpt.isSome:
        var house = houseOpt.get()
        house.intel.colonyReports[report.colonyId] = report
        state.updateHouse(ownerHouse, house)

  of SpyMissionType.SpyOnSystem:
    # Generate system intel (Perfect quality)
    let systemIntel = intel_generator.generateSystemIntelReport(
      state, ownerHouse, targetSystem, IntelQuality.Perfect
    )
    if systemIntel.isSome:
      let package = systemIntel.get()
      let houseOpt = state.house(ownerHouse)
      if houseOpt.isSome:
        var house = houseOpt.get()
        house.intel.systemReports[targetSystem] = package.report
        state.updateHouse(ownerHouse, house)

  of SpyMissionType.HackStarbase:
    # Generate starbase intel (Perfect quality)
    let intelReport = intel_generator.generateStarbaseIntelReport(
      state, ownerHouse, targetSystem, IntelQuality.Perfect
    )
    if intelReport.isSome:
      let report = intelReport.get()
      let houseOpt = state.house(ownerHouse)
      if houseOpt.isSome:
        var house = houseOpt.get()
        house.intel.starbaseReports[report.kastraId] = report
        state.updateHouse(ownerHouse, house)

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

# Legacy functions removed - replaced by resolveScoutMissions()
# Old processScoutIntel() and processPersistentSpyDetection() consolidated
# into single unified resolveScoutMissions() function above
