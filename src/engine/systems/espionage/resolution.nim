## Espionage Resolution System
##
## Resolves scout-based intelligence operations and EBP-based espionage actions.
## Operations are independent (not competitive conflicts).
##
## **Two Espionage Systems** (per docs/specs/09-intel-espionage.md):
##
## 1. **Scout Intelligence Operations** (Section 9.1.1)
##    - Fleet commands: ScoutColony, ScoutSystem, HackStarbase
##    - Scouts travel to target, establish persistent operations
##    - Detection checks each turn (may be destroyed if detected)
##    - Provides Perfect Quality intelligence if successful
##
## 2. **EBP-Based Espionage Actions** (Section 9.2)
##    - CommandPacket.espionageActions field (seq, max 3 per target per turn)
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
import ../command/commands
import ../../intel/[spy_resolution, generator]
import ../../event_factory/intel
import ../../prestige/engine
import ../../globals
import ../../../common/logger
import ./[engine, executor]

# Forward declaration helper
proc generateMissionIntel(
    state: GameState,
    missionType: FleetCommandType,
    targetSystem: SystemId,
    ownerHouse: HouseId,
    events: var seq[event.GameEvent]
)

proc resolveScoutMissions*(
    state: GameState,
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
  ##   - If undetected: Set fleet.missionState = ScoutLocked, generate Perfect intel
  ##
  ## Phase 2: EXISTING missions (Step 6a.5 - query fleets with missionState == ScoutLocked)
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
    # Filter for scout mission types only
    if command.commandType notin [
      FleetCommandType.ScoutColony,
      FleetCommandType.ScoutSystem,
      FleetCommandType.HackStarbase
    ]:
      continue

    # Validate scout-only fleet
    if not state.isScoutOnly(fleet):
      logWarn("Espionage", "Non-scout ships in scout mission fleet",
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

      state.destroyFleet(fleetId)

      # Generate detection event + diplomatic escalation
      events.add(intel.scoutDetected(
        fleet.houseId, defender, targetSystem, "Scout"
      ))

    else:
      # UNDETECTED: Mission succeeds - fleet already has all mission data
      logInfo("Espionage", "New mission started successfully",
        " fleetId=", fleetId, " scouts=", scoutCount)

      # Mission data already set on fleet entity:
      # - fleet.command.commandType = mission type (ScoutColony/ScoutSystem/HackStarbase)
      # - fleet.missionState = ScoutLocked (set by caller)
      # - fleet.missionTarget = targetSystem
      # - fleet.missionStartTurn = state.turn
      # - fleet.ships.len = scout count (scout-only fleets)

      # Generate Perfect quality intel (first turn)
      generateMissionIntel(state, command.commandType, targetSystem, fleet.houseId, events)

    newMissionsProcessed += 1

  logInfo("Espionage", "[Step 6a] Complete",
    " new_missions=", newMissionsProcessed)

  # ==================================================================
  # PHASE 2: EXISTING MISSIONS (Step 6a.5 - Persistent Detection)
  # ==================================================================
  logInfo("Espionage", "[Step 6a.5] Processing existing missions...")

  var existingMissionsProcessed = 0

  # Query all fleets with active scout missions (entity-manager pattern)
  for fleet in state.allFleets():
    # Filter: Only fleets with active scout missions from PREVIOUS turns
    if fleet.missionState != MissionState.ScoutLocked:
      continue

    # CRITICAL FILTER: Skip missions that started THIS turn
    # They already had first detection in Phase 1 above
    if fleet.missionStartTurn >= state.turn:
      logDebug("Espionage", "Skipping newly-started mission",
        " fleetId=", fleet.id, " startTurn=", fleet.missionStartTurn)
      continue

    # Extract mission data from fleet entity
    let fleetId = fleet.id
    let targetSystem = fleet.missionTarget.get(SystemId(0))
    let scoutCount = int32(fleet.ships.len) # Scout-only fleets
    let missionType = fleet.command.commandType

    # Validate target still exists
    let colonyOpt = state.colonyBySystem(targetSystem)
    if colonyOpt.isNone:
      logInfo("Espionage", "Target colony lost, ending mission",
        " fleetId=", fleetId)
      # Reset fleet to Hold
      var updatedFleet = fleet
      updatedFleet.missionState = MissionState.None
      updatedFleet.command = createHoldCommand(fleetId)
      state.updateFleet(fleetId, updatedFleet)
      continue

    let defender = colonyOpt.get().owner

    # RUN PERSISTENT DETECTION CHECK
    let detectionResult = spy_resolution.resolveScoutDetection(
      state, scoutCount, defender, targetSystem, rng
    )

    if detectionResult.detected:
      # DETECTED: Mission fails - destroy fleet
      logInfo("Espionage", "Existing mission detected",
        " fleetId=", fleetId, " turnsActive=", state.turn - fleet.missionStartTurn,
        " roll=", detectionResult.roll, " target=", detectionResult.threshold)

      state.destroyFleet(fleetId)

      # Generate detection event + diplomatic escalation
      events.add(intel.scoutDetected(
        fleet.houseId, defender, targetSystem, "Scout"
      ))

    else:
      # UNDETECTED: Generate Perfect intel, continue mission
      logDebug("Espionage", "Mission continues",
        " fleetId=", fleetId, " turnsActive=", state.turn - fleet.missionStartTurn)

      # Generate Perfect quality intel (ongoing)
      generateMissionIntel(
        state, missionType, targetSystem,
        fleet.houseId, events
      )

    existingMissionsProcessed += 1

  logInfo("Espionage", "[Step 6a.5] Complete",
    " existing_missions=", existingMissionsProcessed)

proc generateMissionIntel(
    state: GameState,
    missionType: FleetCommandType,
    targetSystem: SystemId,
    ownerHouse: HouseId,
    events: var seq[event.GameEvent]
) =
  ## Generate Perfect quality intelligence based on mission type
  ## Called for both new missions (first turn) and ongoing missions

  case missionType
  of FleetCommandType.ScoutColony:
    # Generate colony intel (Perfect quality)
    let intelReport = generateColonyIntelReport(
      state, ownerHouse, targetSystem, IntelQuality.Perfect
    )
    if intelReport.isSome:
      let report = intelReport.get()
      let houseOpt = state.house(ownerHouse)
      if houseOpt.isSome:
        var house = houseOpt.get()
        house.intel.colonyReports[report.colonyId] = report
        state.updateHouse(ownerHouse, house)

  of FleetCommandType.ScoutSystem:
    # Generate system intel (Perfect quality)
    let systemIntel = generateSystemIntelReport(
      state, ownerHouse, targetSystem, IntelQuality.Perfect
    )
    if systemIntel.isSome:
      let package = systemIntel.get()
      let houseOpt = state.house(ownerHouse)
      if houseOpt.isSome:
        var house = houseOpt.get()
        house.intel.systemReports[targetSystem] = package.report
        state.updateHouse(ownerHouse, house)

  of FleetCommandType.HackStarbase:
    # Generate starbase intel (Perfect quality)
    let intelReport = generateStarbaseIntelReport(
      state, ownerHouse, targetSystem, IntelQuality.Perfect
    )
    if intelReport.isSome:
      let report = intelReport.get()
      let houseOpt = state.house(ownerHouse)
      if houseOpt.isSome:
        var house = houseOpt.get()
        house.intel.starbaseReports[report.kastraId] = report
        state.updateHouse(ownerHouse, house)

  else:
    discard # Other FleetCommandTypes not applicable to scout missions

proc wasEspionageHandled*(
    results: seq[ScoutIntelResult], houseId: HouseId, fleetId: FleetId
): bool =
  ## Check if a scout operation was already handled
  for r in results:
    if r.houseId == houseId and r.fleetId == fleetId:
      return true
  return false

proc processEspionageActions*(
    state: GameState,
    orders: Table[HouseId, CommandPacket],
    rng: var Rand,
    events: var seq[event.GameEvent],
) =
  ## Process CommandPacket.espionageActions for all houses
  ## This handles EBP-based espionage actions (TechTheft, Assassination, etc.)
  ## separate from fleet-based espionage orders
  ## Note: Max 3 operations per target house per turn (validated in commands.nim)

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
        purchaseEBP(house.espionageBudget, packet.ebpInvestment)
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
        purchaseCIP(house.espionageBudget, packet.cipInvestment)
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

    # Step 2: Execute espionage actions (0 to many per turn)
    if packet.espionageActions.len == 0:
      # Update house if investments were made
      if packet.ebpInvestment > 0 or packet.cipInvestment > 0:
        state.updateHouse(houseId, house)
      continue

    # Process each espionage action in the packet
    for attempt in packet.espionageActions:
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
        continue

      # Check if attacker has sufficient EBP
      let actionCost = getActionCost(attempt.action)
      if not canAffordAction(house.espionageBudget, attempt.action):
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
        continue

      # Spend EBP
      if not spendEBP(house.espionageBudget, attempt.action):
        logDebug(
          "Espionage",
          "Failed to spend EBP",
          " house=",
          houseId,
          " action=",
          attempt.action,
        )
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
      let result = executeEspionage(attempt, targetCICLevel, targetCIP, rng)

      # Apply results
      if result.success:
        logInfo("Espionage", "Action SUCCESS", " desc=", result.description)

        # Apply prestige changes
        for prestigeEvent in result.attackerPrestigeEvents:
          applyPrestigeEvent(state, attempt.attacker, prestigeEvent)
        for prestigeEvent in result.targetPrestigeEvents:
          applyPrestigeEvent(state, attempt.target, prestigeEvent)

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
          "Espionage",
          "Action DETECTED",
          " attacker=",
          houseId,
          " defender=",
          attempt.target,
        )
        # Apply detection prestige penalties
        for prestigeEvent in result.attackerPrestigeEvents:
          applyPrestigeEvent(state, attempt.attacker, prestigeEvent)

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

    # Update house entity after all espionage actions resolved
    state.updateHouse(houseId, house)

# Legacy functions removed - replaced by resolveScoutMissions()
# Old processScoutIntel() and processPersistentSpyDetection() consolidated
# into single unified resolveScoutMissions() function above
