## Production Phase Resolution - Phase 4 of Canonical Turn Cycle
##
## Server batch processing phase: fleet movement, construction advancement,
## diplomatic state changes, and timer updates.
##
## **Canonical Execution Order:**
##
## Step 1: Fleet Movement
##   1a. Fleet Travel (move fleets toward targets)
##   1b. Fleet Arrival Detection (detect commands ready for execution)
##   1c. Administrative Completion (Production commands: Move, JoinFleet, Reserve, etc.)
##   1d. Scout-on-Scout Detection (reconnaissance encounters)
##
## Step 2: Construction and Repair Advancement
##   2a. Construction Queue Advancement
##   2b. Split Commissioning (Planetary Defense immediate, Military Units next turn)
##   2c. Repair Queue
##
## Step 3: Diplomatic Actions
##
## Step 4: Population Transfers
##
## Step 5: Terraforming
##
## Step 6: Cleanup and Preparation
##
## Step 7: Research Advancement (EL, SL, Tech Fields)
##
## **Key Properties:**
## - Split Commissioning: Planetary defenses commission immediately (Step 2b)
## - Military units (ships) are stored and commissioned next turn (Command Phase Part A)
## - Fleet movement positions units for next turn's Conflict Phase

import
  std/[tables, options, strformat, strutils, algorithm, sequtils, random, sets, hashes]
import ../../../common/[types/core, types/units, types/tech, types/combat]
import ../../gamestate, ../../orders, ../../logger, ../../starmap
import ../../index_maintenance
import ../../order_types
import ../fleet_order_execution # For movement command execution
import ../../economy/[types as econ_types, engine as econ_engine, facility_queue]
import ../../research/[types as res_types, advancement]
import ../commissioning # For planetary defense commissioning
import ../../espionage/[types as esp_types]
import ../../diplomacy/[proposals as dip_proposals]
import ../../population/[types as pop_types]
import ../../config/[gameplay_config, population_config]
import ../[types as res_types_common]
import ../fleet_orders # For findClosestOwnedColony
import ../diplomatic_resolution
import ../event_factory/init as event_factory
import ../../prestige
import ../../fleet # For scout detection helpers
import ../../intelligence/[types as intel_types, generator] # For intel generation
import ../../colony/terraforming # For processTerraformingProjects
import ../../population/transfers as pop_transfers # For resolvePopulationArrivals

proc resolveProductionPhase*(
    state: var GameState,
    events: var seq[GameEvent],
    orders: Table[HouseId, CommandPacket],
    rng: var Rand,
): seq[econ_types.CompletedProject] =
  ## Phase 4: Upkeep, effect decrements, and diplomatic status updates
  ## Returns completed projects for commissioning in next turn's Command Phase
  logInfo(LogCategory.lcCommands, &"=== Production Phase === (turn={state.turn})")

  result = @[] # Will collect completed projects from construction queues

  # Build set of fleets with completed commands for O(1) lookup in Step 1a
  var completedFleetCommands = initHashSet[FleetId]()
  for event in events:
    if event.eventType == res_types_common.GameEventType.CommandCompleted and
        event.fleetId.isSome:
      completedFleetCommands.incl(event.fleetId.get())

  # ===================================================================
  # PRODUCTION STEP 1a: Fleet Travel (Move Toward Targets)
  # ===================================================================
  # ALL fleets with persistent commands move autonomously toward target systems
  # via pathfinding. This allows multi-turn missions: fleet travels incrementally each turn.

  # Count persistent commands
  var persistentCommandCount = 0
  for fleet in state.allFleets():
    if fleet.command.isSome:
      persistentCommandCount += 1

  logInfo(
    LogCategory.lcCommands,
    &"[PRODUCTION STEP 1a] Moving fleets toward command targets... ({persistentCommandCount} persistent commands)",
  )

  var fleetsMovedCount = 0

  for fleet in state.allFleets():
    # Skip if no command assigned
    if fleet.command.isNone:
      continue

    let fleetId = fleet.id
    let persistentCommand = fleet.command.get()

    # Filter 1: Skip commands without target systems
    if persistentCommand.targetSystem.isNone:
      continue

    # Filter 2: Skip Hold commands (explicit "stay here")
    if persistentCommand.commandType == FleetCommandType.Hold:
      continue

    let targetSystem = persistentCommand.targetSystem.get()

    # Check 1: Skip if command already completed this turn (event-based)
    if fleetId in completedFleetCommands:
      logDebug(LogCategory.lcCommands, &"  {fleetId} command completed, no movement needed")
      continue

    # Check 2: Skip if fleet already at target
    if fleet.location == targetSystem:
      logDebug(LogCategory.lcCommands, &"  {fleetId} already at target {targetSystem}")
      continue

    logDebug(
      LogCategory.lcCommands,
      &"  Moving {fleetId} toward {targetSystem} for {persistentCommand.commandType} command",
    )

    # Pathfinding: Find route from current location to target
    # CRITICAL: findPath() respects lane restrictions based on fleet composition:
    # - Fleet with crippled ships: Major lanes only (via canFleetTraverseLane)
    # - Fleet with ETACs/TroopTransports: Major + Minor lanes only
    # - Fleet with no restrictions: All lanes available
    let pathResult = state.starMap.findPath(fleet.location, targetSystem, fleet)

    if not pathResult.found or pathResult.path.len == 0:
      logWarn(
        LogCategory.lcCommands,
        &"  No path found for {fleetId} from {fleet.location} to {targetSystem} (lane restrictions may apply)",
      )
      continue

    # Determine max jumps per turn (1-2 based on territory control and lane types)
    var maxJumps = 1 # Default: 1 jump per turn

    # 2-jump rule: All systems owned by house AND both jumps are Major lanes
    if pathResult.path.len >= 3: # Need at least 2 intermediate jumps available
      var allSystemsOwned = true
      var nextTwoAreMajor = true

      # Check ownership of all systems in path
      for systemId in pathResult.path:
        if systemId notin state.colonies or state.colonies[systemId].owner != fleet.owner:
          allSystemsOwned = false
          break

      # Check if next 2 jumps are Major lanes
      if allSystemsOwned:
        for i in 0 ..< min(2, pathResult.path.len - 1):
          let fromSys = pathResult.path[i]
          let toSys = pathResult.path[i + 1]

          let laneType = state.starMap.getLaneType(fromSys, toSys)
          if laneType.isNone or laneType.get() != LaneClass.Major:
            nextTwoAreMajor = false
            break

        if nextTwoAreMajor:
          maxJumps = 2

    # Move fleet along path (1 or 2 jumps)
    let jumpsToMove = min(maxJumps, pathResult.path.len - 1)
    let newLocation = pathResult.path[jumpsToMove]

    # Update fleet location
    let oldLocation = fleet.location
    state.updateFleetLocation(fleetId, oldLocation, newLocation)
    state.fleets[fleetId].location = newLocation
    fleetsMovedCount += 1

    logDebug(
      LogCategory.lcCommands, &"  Moved {fleetId} {jumpsToMove} jump(s) to {newLocation}"
    )

  logInfo(
    LogCategory.lcCommands,
    &"[PRODUCTION STEP 1a] Completed ({fleetsMovedCount} fleets moved toward targets)",
  )

  # ===================================================================
  # PRODUCTION STEP 1b: Fleet Arrival Detection
  # ===================================================================
  # Detect commands ready for execution
  # Check which fleets have arrived at their command targets
  # Set missionState = Executing for arrived fleets
  # Generate FleetArrived events for execution in Conflict/Income phases

  logInfo(LogCategory.lcCommands, "[PRODUCTION STEP 1b] Detecting fleet arrivals...")

  var arrivedFleetCount = 0

  for fleet in state.allFleets():
    # Skip if no command assigned
    if fleet.command.isNone:
      continue

    let fleetId = fleet.id
    let command = fleet.command.get()

    # Skip if command has no target system
    if command.targetSystem.isNone:
      continue

    let targetSystem = command.targetSystem.get()

    # Check if fleet is at target system
    if fleet.location == targetSystem:
      # Generate FleetArrived event
      events.add(
        event_factory.fleetArrived(
          fleet.houseId,
          fleetId,
          $command.commandType, # Convert enum to string
          targetSystem,
        )
      )

      # Update fleet mission state to Executing (arrived at target)
      var updatedFleet = fleet
      updatedFleet.missionState = MissionState.Executing
      state.updateFleet(fleetId, updatedFleet)
      arrivedFleetCount += 1

      logDebug(
        LogCategory.lcCommands,
        &"  Fleet {fleetId} arrived at {targetSystem} (command: {command.commandType})",
      )

  logInfo(
    LogCategory.lcCommands,
    &"[PRODUCTION STEP 1b] Completed ({arrivedFleetCount} fleets arrived at targets)",
  )

  # ===================================================================
  # PRODUCTION STEP 1c: Administrative Completion (Production Commands)
  # ===================================================================
  # Handle administrative completion for commands that finish during/after travel:
  # - Mark commands complete (Move, Hold, SeekHome, Rendezvous, View)
  # - Merge fleets (JoinFleet)
  # - Apply status changes (Reserve, Mothball, Reactivate)
  # Note: This is NOT command execution - it's lifecycle management
  # Commands are behavior parameters that already determined fleet actions
  logInfo(
    LogCategory.lcCommands,
    "[PRODUCTION STEP 1c] Administrative completion for Production commands...",
  )
  fleet_order_execution.performCommandMaintenance(
    state,
    orders,
    events,
    rng,
    fleet_order_execution.isProductionCommand,
    "Production Phase Step 1c",
  )
  logInfo(
    LogCategory.lcCommands, "[PRODUCTION STEP 1c] Administrative completion complete"
  )

  # ===================================================================
  # PRODUCTION STEP 1d: Scout-on-Scout Detection (Reconnaissance Encounters)
  # ===================================================================
  # When scout fleets from different houses are at same location,
  # each side makes independent ELI-based detection roll
  # Detection formula: 1d20 vs (15 - observerScoutCount + targetELI)
  # Asymmetric detection possible (A detects B, but B doesn't detect A)
  # No combat triggered - scouts never fight each other
  # Intelligence Quality: Visual (only observable data)

  logInfo(
    LogCategory.lcCommands,
    "[PRODUCTION STEP 1d] Checking for scout-on-scout encounters...",
  )

  var scoutDetectionCount = 0

  # Check each location for scout encounters (using persistent index)
  for systemId, fleetIds in state.fleetsByLocation:
    # Need at least 2 fleets for detection
    if fleetIds.len < 2:
      continue

    # Filter for scout-only fleets
    var scoutFleets: seq[tuple[id: FleetId, owner: HouseId]] = @[]
    for fleetId in fleetIds:
      if fleetId notin state.fleets:
        continue # Skip stale index entry
      let fleet = state.fleets[fleetId]
      if fleet.isScoutOnly():
        scoutFleets.add((id: fleetId, owner: fleet.owner))

    # Need at least 2 scout fleets for detection
    if scoutFleets.len < 2:
      continue

    # Check each pair of scout fleets from different houses
    for i in 0 ..< scoutFleets.len:
      for j in (i + 1) ..< scoutFleets.len:
        let observer = scoutFleets[i]
        let target = scoutFleets[j]

        # Skip if same house (can't detect own scouts)
        if observer.owner == target.owner:
          continue

        # Double-check fleets still exist (defensive programming)
        if observer.id notin state.fleets or target.id notin state.fleets:
          continue

        let observerFleet = state.fleets[observer.id]
        let targetFleet = state.fleets[target.id]

        # Count scout squadrons for detection formula
        let observerScoutCount = observerFleet.countScoutSquadrons()
        let targetELI =
          state.houses[target.owner].techTree.levels.eli

        # Detection roll: 1d20 vs (15 - observerScoutCount + targetELI)
        let detectionRoll = rng.rand(1 .. 20)
        let detectionThreshold = 15 - observerScoutCount + targetELI

        logDebug(
          LogCategory.lcCommands,
          &"  {observer.owner} scouts ({observerScoutCount} sq) roll {detectionRoll} " &
            &"vs {detectionThreshold} to detect {target.owner} scouts at {systemId}",
        )

        # Check if detection succeeds
        if detectionRoll >= detectionThreshold:
          # Generate ScoutDetected event
          events.add(
            event_factory.scoutDetected(
              owner = target.owner, # The scout's owner
              detector = observer.owner, # The house that detected
              systemId = systemId,
              scoutType = "Fleet",
            )
          )

          # Generate Visual quality intel report
          let intelReport = generator.generateSystemIntelReport(
            state,
            observer.owner, # Scout owner (observer)
            systemId,
            intel_types.IntelQuality.Visual, # Only observable data
          )

          # Add intel report to observer's database
          if intelReport.isSome:
            state.houses[observer.owner].intelligence.addSystemReport(intelReport.get())

          scoutDetectionCount += 1

          logDebug(
            LogCategory.lcCommands,
            &"  {observer.owner} detected {target.owner} scouts at {systemId} " &
              &"(roll: {detectionRoll} >= {detectionThreshold})",
          )

  logInfo(
    LogCategory.lcCommands,
    &"[PRODUCTION STEP 1d] Completed ({scoutDetectionCount} scout detections)",
  )

  # ===================================================================
  # PRODUCTION STEP 2: Construction & Repair Advancement
  # ===================================================================
  logInfo(
    LogCategory.lcEconomy,
    "[PRODUCTION STEP 2] Advancing construction & repair queues...",
  )

  # -------------------------------------------------------------------
  # STEP 2a: Construction Queue Advancement
  # -------------------------------------------------------------------
  # Advance build queues (ships, ground units, facilities)
  # Mark projects as completed
  # Consume PP/RP from treasuries
  let maintenanceReport = econ_engine.tickConstructionAndRepair(state, events)

  # -------------------------------------------------------------------
  # STEP 2b: Split Commissioning
  # -------------------------------------------------------------------
  # Planetary Defense: Commission immediately (same turn)
  # Military Units: Store for next turn's Command Phase Part A
  var planetaryProjects: seq[econ_types.CompletedProject] = @[]
  var militaryProjects: seq[econ_types.CompletedProject] = @[]

  for project in maintenanceReport.completedProjects:
    if facility_queue.isPlanetaryDefense(project):
      planetaryProjects.add(project)
    else:
      militaryProjects.add(project)

  # Commission planetary defense immediately
  if planetaryProjects.len > 0:
    logInfo(
      LogCategory.lcEconomy,
      &"[PRODUCTION STEP 2b] Commissioning {planetaryProjects.len} planetary defense assets",
    )
    commissioning.commissionPlanetaryDefense(state, planetaryProjects, events)

  # Collect ship projects for next turn's Command Phase commissioning
  result.add(militaryProjects)

  # -------------------------------------------------------------------
  # STEP 2c: Repair Queue
  # -------------------------------------------------------------------
  # Note: Repair advancement is handled by tickConstructionAndRepair() above
  # Repairs complete in 1 turn and are immediately operational (no commissioning delay)

  logInfo(
    LogCategory.lcEconomy,
    &"[PRODUCTION STEP 2] Completed ({planetaryProjects.len} planetary commissioned, " &
      &"{militaryProjects.len} ships pending)",
  )

  # ===================================================================
  # STEP 3: DIPLOMATIC ACTIONS
  # ===================================================================
  # Process diplomatic actions (moved from Command Phase)
  # Diplomatic state changes happen AFTER all commands execute
  logInfo(LogCategory.lcCommands, "[PRODUCTION STEP 3] Processing diplomatic actions...")
  diplomatic_resolution.resolveDiplomaticActions(state, orders, events)
  logInfo(LogCategory.lcCommands, "[PRODUCTION STEP 3] Completed diplomatic actions")

  # ===================================================================
  # STEP 4: POPULATION TRANSFERS
  # ===================================================================
  logInfo(
    LogCategory.lcCommands, "[PRODUCTION STEP 4] Processing population transfers..."
  )
  pop_transfers.resolvePopulationArrivals(state, events)
  logInfo(LogCategory.lcCommands, "[PRODUCTION STEP 4] Completed population transfers")

  # ===================================================================
  # STEP 5: TERRAFORMING
  # ===================================================================
  logInfo(
    LogCategory.lcCommands, "[PRODUCTION STEP 5] Processing terraforming projects..."
  )
  terraforming.processTerraformingProjects(state, events)
  logInfo(LogCategory.lcCommands, "[PRODUCTION STEP 5] Completed terraforming projects")

  # ===================================================================
  # STEP 6: CLEANUP AND PREPARATION
  # ===================================================================
  logInfo(LogCategory.lcCommands, "[PRODUCTION STEP 6] Performing cleanup...")
  # Timer logic moved to Income Phase Step 9.
  # Other cleanup (destroyed entities, fog of war) is handled implicitly
  # by other systems or is not yet implemented.
  logInfo(LogCategory.lcCommands, "[PRODUCTION STEP 6] Cleanup complete")

  # ===================================================================
  # STEP 7: RESEARCH ADVANCEMENT
  # ===================================================================
  # Process tech advancements using accumulated RP from Command Phase
  # Per economy.md:4.1: Tech upgrades can be purchased EVERY TURN if RP available
  # Per canonical turn cycle: Step 7 processes EL/SL/TechField upgrades
  logInfo(
    LogCategory.lcCommands, "[PRODUCTION STEP 7] Processing research advancements..."
  )

  # -------------------------------------------------------------------
  # STEP 7a: BREAKTHROUGH ROLLS (Every 5 Turns)
  # -------------------------------------------------------------------
  # Per economy.md:4.1.1: Breakthrough rolls provide bonus RP, cost reductions, or free levels
  if advancement.isBreakthroughTurn(state.turn):
    logDebug(
      LogCategory.lcResearch,
      &"[RESEARCH BREAKTHROUGHS] Turn {state.turn} - rolling for breakthroughs",
    )
    for houseId in state.houses.keys:
      # Roll for breakthrough
      var rng = initRand(hash(state.turn) xor hash(houseId))
      let breakthroughOpt = advancement.rollBreakthrough(rng) # Approximate 5-turn total

      if breakthroughOpt.isSome:
        let breakthrough = breakthroughOpt.get
        logInfo(LogCategory.lcResearch, &"{houseId} BREAKTHROUGH: {breakthrough}")

        # Apply breakthrough effects. 50-50 for economic or science breakthrough
        let allocation = res_types.ResearchAllocation(
          economic: rng.rand(1 .. 10),
          science: rng.rand(1 .. 10),
          technology: initTable[TechField, int](),
        )
        let event = advancement.applyBreakthrough(
          state.houses[houseId].techTree, breakthrough, allocation
        )

        logDebug(
          LogCategory.lcResearch,
          &"{houseId} breakthrough effect applied (category: {event.category})",
        )

  # -------------------------------------------------------------------
  # STEP 7b-7d: TECH LEVEL ADVANCEMENT (EL, SL, Tech Fields)
  # -------------------------------------------------------------------
  # Process tech upgrades using accumulated RP from Command Phase Part C
  var totalAdvancements = 0
  for houseId, house in state.houses.mpairs:
    # STEP 7b: Economic Level (EL) Advancement
    # Try to advance Economic Level (EL) with accumulated ERP
    let currentEL = house.techTree.levels.el
    let elAdv = attemptELAdvancement(house.techTree, currentEL)
    if elAdv.isSome:
      totalAdvancements += 1
      let adv = elAdv.get()
      logInfo(
        LogCategory.lcResearch,
        &"{house.name}: EL {adv.elFromLevel} → {adv.elToLevel} " &
          &"(spent {adv.elCost} ERP)",
      )
      if adv.prestigeEvent.isSome:
        applyPrestigeEvent(state, houseId, adv.prestigeEvent.get())
        logDebug(LogCategory.lcResearch, &"+{adv.prestigeEvent.get().amount} prestige")
      events.add(event_factory.techAdvance(houseId, "Economic Level", adv.elToLevel))

    # STEP 7c: Science Level (SL) Advancement
    # Try to advance Science Level (SL) with accumulated SRP
    let currentSL = house.techTree.levels.sl
    let slAdv = attemptSLAdvancement(house.techTree, currentSL)
    if slAdv.isSome:
      totalAdvancements += 1
      let adv = slAdv.get()
      logInfo(
        LogCategory.lcResearch,
        &"{house.name}: SL {adv.slFromLevel} → {adv.slToLevel} " &
          &"(spent {adv.slCost} SRP)",
      )
      if adv.prestigeEvent.isSome:
        applyPrestigeEvent(state, houseId, adv.prestigeEvent.get())
        logDebug(LogCategory.lcResearch, &"+{adv.prestigeEvent.get().amount} prestige")
      events.add(event_factory.techAdvance(houseId, "Science Level", adv.slToLevel))

    # STEP 7d: Technology Field Advancement (CST, WEP, TFM, ELI, CI)
    # Try to advance technology fields with accumulated TRP
    for field in [
      TechField.ConstructionTech, TechField.WeaponsTech, TechField.TerraformingTech,
      TechField.ElectronicIntelligence, TechField.CounterIntelligence,
    ]:
      let advancement = attemptTechAdvancement(state, houseId, house.techTree, field)
      if advancement.isSome:
        totalAdvancements += 1
        let adv = advancement.get()
        logInfo(
          LogCategory.lcResearch,
          &"{house.name}: {field} {adv.techFromLevel} → " &
            &"{adv.techToLevel} (spent {adv.techCost} TRP)",
        )

        # Apply prestige if available
        if adv.prestigeEvent.isSome:
          applyPrestigeEvent(state, houseId, adv.prestigeEvent.get())
          logDebug(
            LogCategory.lcResearch, &"+{adv.prestigeEvent.get().amount} prestige"
          )

        # Generate event
        events.add(event_factory.techAdvance(houseId, $field, adv.techToLevel))

  logInfo(
    LogCategory.lcCommands,
    &"[PRODUCTION STEP 7] Research advancements completed ({totalAdvancements} total advancements)",
  )
