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

import std/[tables, options, strformat, random, sets, hashes]
import ../../common/logger
import ../types/[core, game_state, fleet, event, command, production, starmap, tech, intel, house, prestige]
import ../state/[engine, iterators, fleet_queries]
import ../entities/fleet_ops
import ../systems/fleet/[execution, movement]
import ../systems/production/[commissioning, queue_advancement, projects]
import ../systems/diplomacy/resolution
import ../systems/population/transfers
import ../systems/colony/terraforming
import ../systems/tech/advancement
import ../prestige/engine
import ../event_factory/[commands, intel, init as event_factory, victory]
import ../intel/generator
import ../starmap as starmap_module

proc resolveProductionPhase*(
    state: var GameState,
    events: var seq[GameEvent],
    orders: Table[HouseId, CommandPacket],
    rng: var Rand,
): seq[CompletedProject] =
  ## Phase 4: Upkeep, effect decrements, and diplomatic status updates
  ## Returns completed projects for commissioning in next turn's Command Phase
  logInfo("Production", &"=== Production Phase === (turn={state.turn})")

  result = @[] # Will collect completed projects from construction queues

  # Build set of fleets with completed commands for O(1) lookup in Step 1a
  var completedFleetCommands = initHashSet[FleetId]()
  for event in events:
    if event.eventType == GameEventType.CommandCompleted and
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
    "Production",
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
      logDebug("Production", &"  {fleetId} command completed, no movement needed")
      continue

    # Check 2: Skip if fleet already at target
    if fleet.location == targetSystem:
      logDebug("Production", &"  {fleetId} already at target {targetSystem}")
      continue

    logDebug(
      "Production",
      &"  Moving {fleetId} toward {targetSystem} for {persistentCommand.commandType} command",
    )

    # Pathfinding: Find route from current location to target
    # CRITICAL: findPath() respects lane restrictions based on fleet composition:
    # - Fleet with crippled ships: Major lanes only (via canFleetTraverseLane)
    # - Fleet with ETACs/TroopTransports: Major + Minor lanes only
    # - Fleet with no restrictions: All lanes available
    let pathResult = state.findPath(fleet.location, targetSystem, fleet)

    if not pathResult.found or pathResult.path.len == 0:
      logWarn(
        "Production",
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
        let colonyOpt = state.colonyBySystem(systemId)
        if colonyOpt.isNone or colonyOpt.get().owner != fleet.houseId:
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

    # Update fleet location (uses entity_ops to maintain indexes)
    fleet_ops.moveFleet(state, fleetId, newLocation)
    fleetsMovedCount += 1

    logDebug(
      "Production", &"  Moved {fleetId} {jumpsToMove} jump(s) to {newLocation}"
    )

  logInfo(
    "Production",
    &"[PRODUCTION STEP 1a] Completed ({fleetsMovedCount} fleets moved toward targets)",
  )

  # ===================================================================
  # PRODUCTION STEP 1b: Fleet Arrival Detection
  # ===================================================================
  # Detect commands ready for execution
  # Check which fleets have arrived at their command targets
  # Set missionState = Executing for arrived fleets
  # Generate FleetArrived events for execution in Conflict/Income phases

  logInfo("Production", "[PRODUCTION STEP 1b] Detecting fleet arrivals...")

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
        fleetArrived(
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
        "Production",
        &"  Fleet {fleetId} arrived at {targetSystem} (command: {command.commandType})",
      )

  logInfo(
    "Production",
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
    "Production",
    "[PRODUCTION STEP 1c] Administrative completion for Production commands...",
  )
  state.performCommandMaintenance(
    orders,
    events,
    rng,
    isProductionCommand,
    "Production Phase Step 1c",
  )
  logInfo(
    "Production", "[PRODUCTION STEP 1c] Administrative completion complete"
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
    "Production",
    "[PRODUCTION STEP 1d] Checking for scout-on-scout encounters...",
  )

  var scoutDetectionCount = 0

  # Check each location for scout encounters (using persistent index)
  for systemId, fleetIds in state.fleets.bySystem.pairs:
    # Need at least 2 fleets for detection
    if fleetIds.len < 2:
      continue

    # Filter for scout-only fleets
    var scoutFleets: seq[tuple[id: FleetId, owner: HouseId]] = @[]
    for fleetId in fleetIds:
      let fleetOpt = state.fleet(fleetId)
      if fleetOpt.isNone:
        continue # Skip stale index entry
      let fleet = fleetOpt.get()
      if state.isScoutOnly(fleet):
        scoutFleets.add((id: fleetId, owner: fleet.houseId))

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
        let observerFleetOpt = state.fleet(observer.id)
        let targetFleetOpt = state.fleet(target.id)
        if observerFleetOpt.isNone or targetFleetOpt.isNone:
          continue

        let observerFleet = observerFleetOpt.get()

        # Count scout ships for detection formula (scout-only fleets)
        let observerScoutCount = state.countScoutShips(observerFleet)
        let targetHouse = state.house(target.owner).get()
        let targetELI = targetHouse.techTree.levels.eli

        # Detection roll: 1d20 vs (15 - observerScoutCount + targetELI)
        let detectionRoll = rng.rand(1 .. 20)
        let detectionThreshold = 15 - observerScoutCount + targetELI

        logDebug(
          "Production",
          &"  {observer.owner} scouts ({observerScoutCount} sq) roll {detectionRoll} " &
            &"vs {detectionThreshold} to detect {target.owner} scouts at {systemId}",
        )

        # Check if detection succeeds
        if detectionRoll >= detectionThreshold:
          # Generate ScoutDetected event
          events.add(
            scoutDetected(
              owner = target.owner, # The scout's owner
              detector = observer.owner, # The house that detected
              systemId = systemId,
              scoutType = "Fleet",
            )
          )

          # Generate Visual quality intel report
          let intelReport = state.generateSystemIntelReport(
            observer.owner, # Scout owner (observer)
            systemId,
            IntelQuality.Visual, # Only observable data
          )

          # Add intel report to observer's database
          if intelReport.isSome:
            var observerHouse = state.house(observer.owner).get()
            let package = intelReport.get()
            observerHouse.intel.systemReports[systemId] = package.report
            # Also store fleet and ship intel
            for (fleetId, fleetIntel) in package.fleetIntel:
              observerHouse.intel.fleetIntel[fleetId] = fleetIntel
            for (shipId, shipIntel) in package.shipIntel:
              observerHouse.intel.shipIntel[shipId] = shipIntel
            state.updateHouse(observer.owner, observerHouse)

          scoutDetectionCount += 1

          logDebug(
            "Production",
            &"  {observer.owner} detected {target.owner} scouts at {systemId} " &
              &"(roll: {detectionRoll} >= {detectionThreshold})",
          )

  logInfo(
    "Production",
    &"[PRODUCTION STEP 1d] Completed ({scoutDetectionCount} scout detections)",
  )

  # ===================================================================
  # PRODUCTION STEP 2: Construction & Repair Advancement
  # ===================================================================
  logInfo(
    "Economy",
    "[PRODUCTION STEP 2] Advancing construction & repair queues...",
  )

  # -------------------------------------------------------------------
  # STEP 2a: Construction Queue Advancement
  # -------------------------------------------------------------------
  # Advance build queues (ships, ground units, facilities)
  # Mark projects as completed
  # Consume PP/RP from treasuries
  let queueResults = state.advanceAllQueues()

  # -------------------------------------------------------------------
  # STEP 2b: Split Commissioning
  # -------------------------------------------------------------------
  # Planetary Defense: Commission immediately (same turn)
  # Military Units: Store for next turn's Command Phase Part A
  var planetaryProjects: seq[CompletedProject] = @[]
  var militaryProjects: seq[CompletedProject] = @[]

  for project in queueResults.projects:
    if project.isPlanetaryDefense():
      planetaryProjects.add(project)
    else:
      militaryProjects.add(project)

  # Commission planetary defense immediately
  if planetaryProjects.len > 0:
    logInfo(
      "Economy",
      &"[PRODUCTION STEP 2b] Commissioning {planetaryProjects.len} planetary defense assets",
    )
    state.commissionPlanetaryDefense(planetaryProjects, events)

  # Collect ship projects for next turn's Command Phase commissioning
  result.add(militaryProjects)

  # -------------------------------------------------------------------
  # STEP 2c: Repair Queue
  # -------------------------------------------------------------------
  # Note: Repair advancement is handled by tickConstructionAndRepair() above
  # Repairs complete in 1 turn and are immediately operational (no commissioning delay)

  logInfo(
    "Economy",
    &"[PRODUCTION STEP 2] Completed ({planetaryProjects.len} planetary commissioned, " &
      &"{militaryProjects.len} ships pending)",
  )

  # ===================================================================
  # STEP 3: DIPLOMATIC ACTIONS
  # ===================================================================
  # Process diplomatic actions (moved from Command Phase)
  # Diplomatic state changes happen AFTER all commands execute
  logInfo("Production", "[PRODUCTION STEP 3] Processing diplomatic actions...")
  state.resolveDiplomaticActions(orders, events)
  logInfo("Production", "[PRODUCTION STEP 3] Completed diplomatic actions")

  # ===================================================================
  # STEP 4: POPULATION TRANSFERS
  # ===================================================================
  logInfo(
    "Production", "[PRODUCTION STEP 4] Processing population transfers..."
  )
  let transferCompletions = state.processTransfers()
  let transferEvents = generateTransferEvents(state, transferCompletions)
  events.add(transferEvents)
  logInfo("Production", "[PRODUCTION STEP 4] Completed population transfers")

  # ===================================================================
  # STEP 5: TERRAFORMING
  # ===================================================================
  logInfo(
    "Production", "[PRODUCTION STEP 5] Processing terraforming projects..."
  )
  state.processTerraformingProjects(events)
  logInfo("Production", "[PRODUCTION STEP 5] Completed terraforming projects")

  # ===================================================================
  # STEP 6: CLEANUP AND PREPARATION
  # ===================================================================
  logInfo("Production", "[PRODUCTION STEP 6] Performing cleanup...")
  # Timer logic moved to Income Phase Step 9.
  # Other cleanup (destroyed entities, fog of war) is handled implicitly
  # by other systems or is not yet implemented.
  logInfo("Production", "[PRODUCTION STEP 6] Cleanup complete")

  # ===================================================================
  # STEP 7: RESEARCH ADVANCEMENT
  # ===================================================================
  # Process tech advancements using accumulated RP from Command Phase
  # Per economy.md:4.1: Tech upgrades can be purchased EVERY TURN if RP available
  # Per canonical turn cycle: Step 7 processes EL/SL/TechField upgrades
  logInfo(
    "Production", "[PRODUCTION STEP 7] Processing research advancements..."
  )

  # -------------------------------------------------------------------
  # STEP 7a: BREAKTHROUGH ROLLS (Every 5 Turns)
  # -------------------------------------------------------------------
  # Per economy.md:4.1.1: Breakthrough rolls provide bonus RP, cost reductions, or free levels
  if state.turn.isBreakthroughTurn():
    logDebug(
      "Research",
      &"[RESEARCH BREAKTHROUGHS] Turn {state.turn} - rolling for breakthroughs",
    )
    for (houseId, _) in state.allHousesWithId():
      # Roll for breakthrough
      var rng = initRand(hash(state.turn) xor hash(houseId))
      let breakthroughOpt = rng.rollBreakthrough() # Approximate 5-turn total

      if breakthroughOpt.isSome:
        let breakthrough = breakthroughOpt.get
        logInfo("Research", &"{houseId} BREAKTHROUGH: {breakthrough}")

        # Apply breakthrough effects. 50-50 for economic or science breakthrough
        let allocation = ResearchAllocation(
          economic: int32(rng.rand(1 .. 10)),
          science: int32(rng.rand(1 .. 10)),
          technology: initTable[TechField, int32](),
        )
        var house = state.house(houseId).get()
        let event = house.techTree.applyBreakthrough(breakthrough, allocation)
        state.updateHouse(houseId, house)

        logDebug(
          "Research",
          &"{houseId} breakthrough effect applied (category: {event.category})",
        )

  # -------------------------------------------------------------------
  # STEP 7b-7d: TECH LEVEL ADVANCEMENT (EL, SL, Tech Fields)
  # -------------------------------------------------------------------
  # Process tech upgrades using accumulated RP from Command Phase Part C
  var totalAdvancements = 0
  for (houseId, _) in state.allHousesWithId():
    var house = state.house(houseId).get()
    
    # STEP 7b: Economic Level (EL) Advancement
    # Try to advance Economic Level (EL) with accumulated ERP
    let currentEL = house.techTree.levels.el
    let elAdv = house.techTree.attemptELAdvancement(currentEL)
    if elAdv.isSome:
      totalAdvancements += 1
      let adv = elAdv.get()
      logInfo(
        "Research",
        &"{house.name}: EL {adv.elFromLevel} → {adv.elToLevel} " &
          &"(spent {adv.elCost} ERP)",
      )
      if adv.prestigeEvent.isSome:
        state.applyPrestigeEvent(houseId, adv.prestigeEvent.get())
        logDebug("Research", &"+{adv.prestigeEvent.get().amount} prestige")
      events.add(victory.techAdvance(houseId, "Economic Level", adv.elToLevel))

    # STEP 7c: Science Level (SL) Advancement
    # Try to advance Science Level (SL) with accumulated SRP
    let currentSL = house.techTree.levels.sl
    let slAdv = house.techTree.attemptSLAdvancement(currentSL)
    if slAdv.isSome:
      totalAdvancements += 1
      let adv = slAdv.get()
      logInfo(
        "Research",
        &"{house.name}: SL {adv.slFromLevel} → {adv.slToLevel} " &
          &"(spent {adv.slCost} SRP)",
      )
      if adv.prestigeEvent.isSome:
        state.applyPrestigeEvent(houseId, adv.prestigeEvent.get())
        logDebug("Research", &"+{adv.prestigeEvent.get().amount} prestige")
      events.add(victory.techAdvance(houseId, "Science Level", adv.slToLevel))

    # STEP 7d: Technology Field Advancement (CST, WEP, TFM, ELI, CI)
    # Try to advance technology fields with accumulated TRP
    for field in [
      TechField.ConstructionTech, TechField.WeaponsTech, TechField.TerraformingTech,
      TechField.ElectronicIntelligence, TechField.CounterIntelligence,
    ]:
      let techAdv = attemptTechAdvancement(state, houseId, house.techTree, field)
      if techAdv.isSome:
        totalAdvancements += 1
        let adv = techAdv.get()
        logInfo(
          "Research",
          &"{house.name}: {field} {adv.techFromLevel} → " &
            &"{adv.techToLevel} (spent {adv.techCost} TRP)",
        )

        # Apply prestige if available
        if adv.prestigeEvent.isSome:
          state.applyPrestigeEvent(houseId, adv.prestigeEvent.get())
          logDebug(
            "Research", &"+{adv.prestigeEvent.get().amount} prestige"
          )

        # Generate event
        events.add(victory.techAdvance(houseId, $field, adv.techToLevel))
    
    # Update house with all tech changes
    state.updateHouse(houseId, house)

  logInfo(
    "Production",
    &"[PRODUCTION STEP 7] Research advancements completed ({totalAdvancements} total advancements)",
  )
