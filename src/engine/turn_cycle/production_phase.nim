## Production Phase Resolution - Phase 4 of Canonical Turn Cycle
##
## Server batch processing: movement, construction advancement, diplomacy.
## Per docs/engine/ec4x_canonical_turn_cycle.md
##
## **Canonical Steps:**
## - PRD1: Fleet Movement (1a-1d)
## - PRD2: Construction & Repair Advancement
## - PRD3: Diplomatic Actions
## - PRD4: Population Transfers
## - PRD5: Terraforming
## - PRD6: Cleanup
## - PRD7: Research Advancement
##
## **Key Principle:** NO commissioning here. All completed projects
## are returned for CMD2 (Unified Commissioning) next turn.
##
## **Architecture:**
## - Uses UFCS pattern for all state access
## - Uses iterators for batch entity access
## - Uses entity_ops for index-affecting mutations
## - Uses common/logger for all logging

import std/[tables, options, strformat, random, sets, hashes]
import ../../common/logger
import ../types/[
  core, game_state, fleet, event, command, production, starmap, tech,
  player_state, house,
]
import ../state/[engine, iterators, fleet_queries]
import ../entities/fleet_ops
import ../systems/fleet/[execution, movement]
import ../systems/production/queue_advancement
import ../systems/diplomacy/resolution
import ../systems/population/transfers
import ../systems/colony/terraforming
import ../systems/tech/advancement
import ../prestige/engine
import ../event_factory/[commands, intel, victory]
import ../intel/generator
import ../starmap

# =============================================================================
# PRD1a: FLEET TRAVEL
# =============================================================================

proc processFleetTravel(
    state: GameState,
    events: var seq[GameEvent],
    completedFleetCommands: HashSet[FleetId],
) =
  ## PRD1a: Move fleets toward command targets
  ##
  ## All fleets with persistent commands move autonomously toward target
  ## systems via pathfinding. Multi-turn missions travel incrementally.
  ##
  ## Movement rules:
  ## - 1 jump per turn (default)
  ## - 2 jumps if: all systems owned AND both jumps are Major lanes
  ## - Crippled ships: Major lanes only
  ## - ETACs/Transports: Major + Minor lanes only
  
  var persistentCommandCount = 0
  for fleet in state.allFleets():
    if fleet.missionState != MissionState.None:
      persistentCommandCount += 1
  
  logInfo("Production",
    &"[PRD1a] Moving fleets toward targets ({persistentCommandCount} active)")
  
  var fleetsMovedCount = 0
  
  for fleet in state.allFleets():
    # Skip idle fleets (no active command)
    if fleet.missionState == MissionState.None:
      continue
    
    let fleetId = fleet.id
    let command = fleet.command
    
    # Skip commands without target systems
    if command.targetSystem.isNone:
      continue
    
    # Skip Hold commands (explicit "stay here")
    if command.commandType == FleetCommandType.Hold:
      continue
    
    let targetSystem = command.targetSystem.get()
    
    # Skip if command already completed this turn
    if fleetId in completedFleetCommands:
      logDebug("Production", &"  {fleetId} command completed, skipping")
      continue
    
    # Skip if already at target
    if fleet.location == targetSystem:
      logDebug("Production", &"  {fleetId} already at target {targetSystem}")
      continue
    
    # Pathfinding respects lane restrictions based on fleet composition
    let pathResult = state.findPath(fleet.location, targetSystem, fleet)
    
    if not pathResult.found or pathResult.path.len == 0:
      logWarn("Production",
        &"  No path for {fleetId}: {fleet.location} -> {targetSystem}")
      continue
    
    # Determine max jumps (1-2 based on territory and lane types)
    var maxJumps = 1
    
    if pathResult.path.len >= 3:
      var allSystemsOwned = true
      var nextTwoAreMajor = true
      
      # Check ownership of systems in path
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
    
    # Move fleet along path
    let jumpsToMove = min(maxJumps, pathResult.path.len - 1)
    let newLocation = pathResult.path[jumpsToMove]
    
    state.moveFleet(fleetId, newLocation)
    fleetsMovedCount += 1
    
    logDebug("Production",
      &"  Moved {fleetId} {jumpsToMove} jump(s) to {newLocation}")
  
  logInfo("Production", &"[PRD1a] Complete ({fleetsMovedCount} fleets moved)")

# =============================================================================
# PRD1b: FLEET ARRIVAL DETECTION
# =============================================================================

proc detectFleetArrivals(
    state: GameState,
    events: var seq[GameEvent],
) =
  ## PRD1b: Detect fleets that arrived at command targets
  ##
  ## Sets missionState = Executing for arrived fleets.
  ## Conflict/Income phases filter for missionState == Executing to determine
  ## which commands execute.
  
  logInfo("Production", "[PRD1b] Detecting fleet arrivals...")
  
  var arrivedCount = 0
  
  for fleet in state.allFleets():
    # Skip idle fleets
    if fleet.missionState == MissionState.None:
      continue
    
    let fleetId = fleet.id
    let command = fleet.command
    
    # Skip if no target system
    if command.targetSystem.isNone:
      continue
    
    let targetSystem = command.targetSystem.get()
    
    # Check if fleet is at target
    if fleet.location == targetSystem:
      # Generate FleetArrived event
      events.add(fleetArrived(
        fleet.houseId,
        fleetId,
        $command.commandType,
        targetSystem,
      ))
      
      # Update mission state to Executing
      var updatedFleet = fleet
      updatedFleet.missionState = MissionState.Executing
      state.updateFleet(fleetId, updatedFleet)
      arrivedCount += 1
      
      logDebug("Production",
        &"  {fleetId} arrived at {targetSystem} ({command.commandType})")
  
  logInfo("Production", &"[PRD1b] Complete ({arrivedCount} fleets arrived)")

# =============================================================================
# PRD1c: ADMINISTRATIVE COMPLETION (PRODUCTION COMMANDS)
# =============================================================================

proc processAdministrativeCompletion(
    state: GameState,
    orders: Table[HouseId, CommandPacket],
    events: var seq[GameEvent],
    rng: var Rand,
) =
  ## PRD1c: Mark Production commands complete
  ##
  ## Handles administrative completion for commands that finish during travel:
  ## - Travel completion: Move, Hold, SeekHome, Rendezvous
  ## - Fleet merging: JoinFleet
  ## - Status changes: Reserve, Mothball, Reactivate
  ## - Reconnaissance: View
  ##
  ## Uses isProductionCommand() filter from execution module.
  
  logInfo("Production", "[PRD1c] Administrative completion...")
  
  state.performCommandMaintenance(
    orders,
    events,
    rng,
    isProductionCommand,
    "Production Phase PRD1c",
  )
  
  logInfo("Production", "[PRD1c] Complete")

# =============================================================================
# PRD1d: SCOUT-ON-SCOUT DETECTION
# =============================================================================

proc processScoutDetection(
    state: GameState,
    events: var seq[GameEvent],
    rng: var Rand,
) =
  ## PRD1d: Scout-on-scout detection at same location
  ##
  ## When scout fleets from different houses occupy the same system,
  ## each side makes independent ELI-based detection roll.
  ##
  ## Detection formula: 1d20 vs (15 - observerScoutCount + targetELI)
  ## Asymmetric: A may detect B while B doesn't detect A
  ## No combat: scouts never fight each other
  ## Intel quality: Visual (observable data only)
  
  logInfo("Production", "[PRD1d] Scout-on-scout detection...")
  
  var detectionCount = 0
  
  # Check each location for scout encounters (using bySystem index)
  for systemId, fleetIds in state.fleets.bySystem.pairs:
    if fleetIds.len < 2:
      continue
    
    # Filter for scout-only fleets
    var scoutFleets: seq[tuple[id: FleetId, owner: HouseId]] = @[]
    for fleetId in fleetIds:
      let fleetOpt = state.fleet(fleetId)
      if fleetOpt.isNone:
        continue
      let fleet = fleetOpt.get()
      if state.isScoutOnly(fleet):
        scoutFleets.add((id: fleetId, owner: fleet.houseId))
    
    if scoutFleets.len < 2:
      continue
    
    # Check each pair from different houses
    for i in 0 ..< scoutFleets.len:
      for j in (i + 1) ..< scoutFleets.len:
        let observer = scoutFleets[i]
        let target = scoutFleets[j]
        
        # Skip same house
        if observer.owner == target.owner:
          continue
        
        let observerFleetOpt = state.fleet(observer.id)
        let targetFleetOpt = state.fleet(target.id)
        if observerFleetOpt.isNone or targetFleetOpt.isNone:
          continue
        
        let observerFleet = observerFleetOpt.get()
        let observerScoutCount = state.countScoutShips(observerFleet)
        
        let targetHouseOpt = state.house(target.owner)
        if targetHouseOpt.isNone:
          continue
        let targetELI = targetHouseOpt.get().techTree.levels.eli
        
        # Detection roll
        let roll = rng.rand(1 .. 20)
        let threshold = 15 - observerScoutCount + targetELI
        
        logDebug("Production",
          &"  {observer.owner} scouts ({observerScoutCount}) " &
          &"roll {roll} vs {threshold} to detect {target.owner}")
        
        if roll >= threshold:
          # Generate ScoutDetected event
          events.add(scoutDetected(
            owner = target.owner,
            detector = observer.owner,
            systemId = systemId,
            scoutType = "Fleet",
          ))
          
          # Generate Visual quality intel
          let intelReport = generateSystemObservation(
            state, observer.owner, systemId, IntelQuality.Visual
          )
          
          if intelReport.isSome:
            var observerHouse = state.house(observer.owner).get()
            let package = intelReport.get()
            observerHouse.intel.systemObservations[systemId] = package.report
            for (fleetId, fleetIntel) in package.fleetObservations:
              observerHouse.intel.fleetObservations[fleetId] = fleetIntel
            for (shipId, shipIntel) in package.shipObservations:
              observerHouse.intel.shipObservations[shipId] = shipIntel
            state.updateHouse(observer.owner, observerHouse)
          
          detectionCount += 1
          logDebug("Production",
            &"  {observer.owner} detected {target.owner} at {systemId}")
  
  logInfo("Production", &"[PRD1d] Complete ({detectionCount} detections)")

# =============================================================================
# PRD2: CONSTRUCTION & REPAIR ADVANCEMENT
# =============================================================================

proc advanceQueues(
    state: GameState,
): tuple[projects: seq[CompletedProject], repairs: seq[RepairProject]] =
  ## PRD2a+2b: Advance all construction and repair queues
  ##
  ## For each project: decrement turnsRemaining
  ## If turnsRemaining = 0: Mark AwaitingCommission
  ##
  ## **NO commissioning here** - all completed projects returned for
  ## CMD2 (Unified Commissioning) next turn.
  
  logInfo("Production", "[PRD2] Advancing construction & repair queues...")
  
  result = state.advanceAllQueues()
  
  logInfo("Production",
    &"[PRD2] Complete ({result.projects.len} construction, " &
    &"{result.repairs.len} repairs ready for commissioning)")

# =============================================================================
# PRD3: DIPLOMATIC ACTIONS
# =============================================================================

proc processDiplomacy(
    state: GameState,
    orders: Table[HouseId, CommandPacket],
    events: var seq[GameEvent],
) =
  ## PRD3: Process diplomatic actions
  ##
  ## - Alliance proposals (accept/reject)
  ## - Trade agreements
  ## - Diplomatic status changes (Peace, War, Alliance)
  
  logInfo("Production", "[PRD3] Processing diplomatic actions...")
  
  state.resolveDiplomaticActions(orders, events)
  
  logInfo("Production", "[PRD3] Complete")

# =============================================================================
# PRD4: POPULATION TRANSFERS
# =============================================================================

proc processPopulationTransfers(
    state: GameState,
    events: var seq[GameEvent],
) =
  ## PRD4: Process Space Guild population transfers
  ##
  ## Execute PopulationTransfer orders, update colony populations.
  
  logInfo("Production", "[PRD4] Processing population transfers...")
  
  let completions = state.processTransfers()
  let transferEvents = generateTransferEvents(state, completions)
  events.add(transferEvents)
  
  logInfo("Production", &"[PRD4] Complete ({completions.len} transfers)")

# =============================================================================
# PRD5: TERRAFORMING
# =============================================================================

proc processTerraforming(
    state: GameState,
    events: var seq[GameEvent],
) =
  ## PRD5: Advance terraforming projects
  ##
  ## Decrement turn counters, complete terraforming (upgrade planet class).
  
  logInfo("Production", "[PRD5] Processing terraforming...")
  
  state.processTerraformingProjects(events)
  
  logInfo("Production", "[PRD5] Complete")

# =============================================================================
# PRD6: CLEANUP AND PREPARATION
# =============================================================================

proc performCleanup(state: GameState) =
  ## PRD6: Cleanup and preparation for next turn
  ##
  ## - Remove destroyed entities (handled implicitly by combat)
  ## - Update fog-of-war visibility (handled by intel system)
  ## - Prepare for next turn's Conflict Phase
  ##
  ## NOTE: Most cleanup is handled by other systems. This step is
  ## primarily a placeholder for future expansion.
  
  logInfo("Production", "[PRD6] Performing cleanup...")
  
  # Timer logic moved to Income Phase Step 11
  # Other cleanup handled implicitly by combat/intel systems
  
  logInfo("Production", "[PRD6] Complete")

# =============================================================================
# PRD7: RESEARCH ADVANCEMENT
# =============================================================================

proc processResearchAdvancement(
    state: GameState,
    events: var seq[GameEvent],
    rng: var Rand,
) =
  ## PRD7: Process tech advancements using accumulated RP from Command Phase
  ##
  ## Per economy.md:4.1: Tech upgrades can occur EVERY TURN if RP available
  ##
  ## Steps:
  ## - PRD7a: Breakthrough Rolls (every 5 turns)
  ## - PRD7b: Economic Level (EL) Advancement
  ## - PRD7c: Science Level (SL) Advancement
  ## - PRD7d: Technology Field Advancement (CST, WEP, TFM, ELI, CI)
  
  logInfo("Production", "[PRD7] Processing research advancement...")
  
  # -------------------------------------------------------------------------
  # PRD7a: BREAKTHROUGH ROLLS (Every 5 Turns)
  # -------------------------------------------------------------------------
  if state.turn.isBreakthroughTurn():
    logDebug("Production",
      &"[PRD7a] Turn {state.turn} - rolling for breakthroughs")
    
    for (houseId, _) in state.activeHousesWithId():
      var houseRng = initRand(hash(state.turn) xor hash(houseId))
      let breakthroughOpt = houseRng.rollBreakthrough()
      
      if breakthroughOpt.isSome:
        let breakthrough = breakthroughOpt.get()
        logInfo("Production", &"  {houseId} BREAKTHROUGH: {breakthrough}")
        
        # Apply breakthrough effects
        let allocation = ResearchAllocation(
          economic: int32(houseRng.rand(1 .. 10)),
          science: int32(houseRng.rand(1 .. 10)),
          technology: initTable[TechField, int32](),
        )
        var house = state.house(houseId).get()
        let event = house.techTree.applyBreakthrough(breakthrough, allocation)
        state.updateHouse(houseId, house)
        
        logDebug("Production",
          &"  Breakthrough effect applied (category: {event.category})")
  
  # -------------------------------------------------------------------------
  # PRD7b-7d: TECH LEVEL ADVANCEMENT
  # -------------------------------------------------------------------------
  var totalAdvancements = 0
  
  for (houseId, _) in state.activeHousesWithId():
    var house = state.house(houseId).get()
    
    # PRD7b: Economic Level (EL) Advancement
    let currentEL = house.techTree.levels.el
    let elAdv = house.techTree.attemptELAdvancement(currentEL)
    if elAdv.isSome:
      totalAdvancements += 1
      let adv = elAdv.get()
      logInfo("Production",
        &"  {house.name}: EL {adv.elFromLevel} -> {adv.elToLevel} " &
        &"(spent {adv.elCost} ERP)")
      if adv.prestigeEvent.isSome:
        state.applyPrestigeEvent(houseId, adv.prestigeEvent.get())
      events.add(victory.techAdvance(houseId, "Economic Level", adv.elToLevel))
    
    # PRD7c: Science Level (SL) Advancement
    let currentSL = house.techTree.levels.sl
    let slAdv = house.techTree.attemptSLAdvancement(currentSL)
    if slAdv.isSome:
      totalAdvancements += 1
      let adv = slAdv.get()
      logInfo("Production",
        &"  {house.name}: SL {adv.slFromLevel} -> {adv.slToLevel} " &
        &"(spent {adv.slCost} SRP)")
      if adv.prestigeEvent.isSome:
        state.applyPrestigeEvent(houseId, adv.prestigeEvent.get())
      events.add(victory.techAdvance(houseId, "Science Level", adv.slToLevel))
    
    # PRD7d: Technology Field Advancement
    for field in [
      TechField.ConstructionTech, TechField.WeaponsTech,
      TechField.TerraformingTech, TechField.ElectronicIntelligence,
      TechField.CounterIntelligence,
    ]:
      let techAdv = attemptTechAdvancement(state, houseId, house.techTree, field)
      if techAdv.isSome:
        totalAdvancements += 1
        let adv = techAdv.get()
        logInfo("Production",
          &"  {house.name}: {field} {adv.techFromLevel} -> {adv.techToLevel} " &
          &"(spent {adv.techCost} TRP)")
        if adv.prestigeEvent.isSome:
          applyPrestigeEvent(
            state, houseId, adv.prestigeEvent.get()
          )
        events.add(victory.techAdvance(houseId, $field, adv.techToLevel))
    
    # Write back all tech changes
    state.updateHouse(houseId, house)
  
  logInfo("Production",
    &"[PRD7] Complete ({totalAdvancements} total advancements)")

# =============================================================================
# MAIN ENTRY POINT
# =============================================================================

proc resolveProductionPhase*(
    state: GameState,
    events: var seq[GameEvent],
    orders: Table[HouseId, CommandPacket],
    rng: var Rand,
): seq[CompletedProject] =
  ## Execute Production Phase (PRD1-7)
  ##
  ## Per docs/engine/ec4x_canonical_turn_cycle.md:
  ## - PRD1: Fleet Movement (1a-1d)
  ## - PRD2: Construction & Repair Advancement
  ## - PRD3: Diplomatic Actions
  ## - PRD4: Population Transfers
  ## - PRD5: Terraforming
  ## - PRD6: Cleanup
  ## - PRD7: Research Advancement
  ##
  ## Returns completed projects for CMD2 (Unified Commissioning) next turn.
  ## NO commissioning happens in this phase.
  
  logInfo("Production", &"=== Production Phase === (turn={state.turn})")
  
  # Build set of completed commands for O(1) lookup in PRD1a
  var completedFleetCommands = initHashSet[FleetId]()
  for event in events:
    if event.eventType == GameEventType.CommandCompleted and
        event.fleetId.isSome:
      completedFleetCommands.incl(event.fleetId.get())
  
  # =========================================================================
  # PRD1: FLEET MOVEMENT
  # =========================================================================
  processFleetTravel(state, events, completedFleetCommands)
  detectFleetArrivals(state, events)
  processAdministrativeCompletion(state, orders, events, rng)
  processScoutDetection(state, events, rng)
  
  # =========================================================================
  # PRD2: CONSTRUCTION & REPAIR ADVANCEMENT
  # =========================================================================
  let queueResults = advanceQueues(state)
  
  # Return ALL completed projects for CMD2 commissioning
  # NO split commissioning - everything deferred to Command Phase
  result = queueResults.projects
  
  # =========================================================================
  # PRD3-6: OTHER PROCESSING
  # =========================================================================
  processDiplomacy(state, orders, events)
  processPopulationTransfers(state, events)
  processTerraforming(state, events)
  performCleanup(state)
  
  # =========================================================================
  # PRD7: RESEARCH ADVANCEMENT
  # =========================================================================
  processResearchAdvancement(state, events, rng)
  
  logInfo("Production",
    &"=== Production Phase Complete === " &
    &"({result.len} projects pending commissioning)")
