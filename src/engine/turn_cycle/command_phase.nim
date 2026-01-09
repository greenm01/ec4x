## Command Phase Resolution - Phase 3 of Canonical Turn Cycle
##
## Six-step phase executing server processing and player commands.
## Per docs/engine/ec4x_canonical_turn_cycle.md Phase 3.
##
## **Canonical Steps (CMD1-CMD6):**
## - CMD1: Order Cleanup - Reset completed/stale commands to Hold
## - CMD2: Unified Commissioning - Ships, repairs, colony assets
## - CMD3: Auto-Repair Submission - Queue repairs for autoRepair colonies
## - CMD4: Colony Automation - Auto-assign ships, load cargo
## - CMD5: Player Submission Window - Colony mgmt, transfers, terraforming
## - CMD6: Order Processing & Validation - Fleet commands, builds, research

import std/[tables, options, random, strformat, sets, hashes]

# Logging
import ../../common/logger

# Types
import ../types/[core, game_state, command, fleet, event, tech as tech_types, production]

# State Core (reading)
import ../state/[engine, iterators]

# Entity Ops (writing) - none needed; fleet state updates via updateFleet()

# Systems (business logic)
import ../systems/command/commands as cmd_helpers
import ../systems/production/[commissioning, construction, repairs]
import ../systems/fleet/mechanics
import ../systems/colony/[engine as colony_engine, terraforming]
import ../systems/population/transfers as pop_transfers
import ../systems/tech/costs as tech_costs
import ../event_factory/init as event_factory

# =============================================================================
# CMD1: ORDER CLEANUP
# =============================================================================

proc cleanupCompletedCommands(state: var GameState, events: seq[GameEvent]) =
  ## CMD1: Reset completed/failed/aborted commands to Hold + MissionState.None
  ##
  ## Scans events for CommandCompleted/Failed/Aborted and resets those fleets.
  ## Also resets any fleet with stale Executing state (consistency check).
  
  logInfo("Commands", "[CMD1] Order Cleanup - resetting completed commands")
  
  # Build set of fleets with completion events
  var completedFleets = initHashSet[FleetId]()
  for event in events:
    if event.eventType in {
      GameEventType.CommandCompleted,
      GameEventType.CommandFailed,
      GameEventType.CommandAborted
    }:
      if event.fleetId.isSome:
        completedFleets.incl(event.fleetId.get())
  
  # Reset those fleets to Hold + MissionState.None
  var resetCount = 0
  for fleetId in completedFleets:
    let fleetOpt = state.fleet(fleetId)
    if fleetOpt.isSome:
      var fleet = fleetOpt.get()
      fleet.command = cmd_helpers.createHoldCommand(fleetId)
      fleet.missionState = MissionState.None
      fleet.missionTarget = none(SystemId)
      state.updateFleet(fleetId, fleet)
      resetCount += 1
  
  logInfo("Commands", &"[CMD1] Reset {resetCount} fleet commands to Hold")

# =============================================================================
# CMD2: UNIFIED COMMISSIONING
# =============================================================================

proc commissionEntities(state: var GameState, events: var seq[GameEvent]) =
  ## CMD2: Commission ALL pending assets that survived Conflict Phase
  ##
  ## Per canonical spec:
  ## - 2a: Commission ships from Neorias (Spaceports/Shipyards)
  ## - 2b: Commission repaired ships from Drydocks (payment checked here)
  ## - 2c: Commission colony assets (fighters, ground units, facilities, starbases)
  ##
  ## No validation needed - if entity exists in state, it survived Conflict Phase.
  
  logInfo("Commands", "[CMD2] Unified Commissioning")
  
  # 2a: Clear damaged facility queues first (ships in destroyed docks are lost)
  commissioning.clearDamagedFacilityQueues(state, events)
  
  # 2b: Commission all pending projects from Production Phase
  # This includes both ships (military) and colony assets (planetary defense)
  # Split commissioning is handled here - ships go to fleets, planetary goes to colonies
  if state.pendingCommissions.len > 0:
    # Separate military (ships) from planetary (fighters, ground units, facilities)
    var militaryProjects: seq[CompletedProject] = @[]
    var planetaryProjects: seq[CompletedProject] = @[]
    
    for project in state.pendingCommissions:
      if project.projectType == BuildType.Ship:
        militaryProjects.add(project)
      else:
        planetaryProjects.add(project)
    
    # Commission ships to fleets
    if militaryProjects.len > 0:
      logInfo("Commands", &"[CMD2a] Commissioning {militaryProjects.len} ships from Neorias")
      commissioning.commissionShips(state, militaryProjects, events)
    else:
      logInfo("Commands", "[CMD2a] No ships to commission")
    
    # Commission planetary defense assets
    if planetaryProjects.len > 0:
      logInfo("Commands", &"[CMD2c] Commissioning {planetaryProjects.len} colony assets")
      commissioning.commissionPlanetaryDefense(state, planetaryProjects, events)
    else:
      logInfo("Commands", "[CMD2c] No colony assets to commission")
    
    # Clear pending commissions
    state.pendingCommissions = @[]
  else:
    logInfo("Commands", "[CMD2a] No pending commissions")
  
  # 2b: Commission repaired ships from drydocks
  # Repairs that completed in Production Phase are marked in repair projects
  # Query for completed repairs and commission them
  var completedRepairs: seq[RepairProject] = @[]
  for (repairId, repair) in state.repairProjects.entities.index.pairs:
    let repairOpt = state.repairProject(repairId)
    if repairOpt.isSome:
      let r = repairOpt.get()
      if r.turnsRemaining <= 0:
        completedRepairs.add(r)
  
  if completedRepairs.len > 0:
    logInfo("Commands", &"[CMD2b] Commissioning {completedRepairs.len} repaired ships")
    commissioning.commissionRepairedShips(state, completedRepairs, events)
  else:
    logInfo("Commands", "[CMD2b] No repairs to commission")
  
  logInfo("Commands", "[CMD2] Unified Commissioning complete")

# =============================================================================
# CMD3: AUTO-REPAIR SUBMISSION
# =============================================================================

proc submitAutoRepairs(state: var GameState, events: var seq[GameEvent]) =
  ## CMD3: Auto-submit repair orders for colonies with autoRepair=true
  ##
  ## Per canonical spec:
  ## - Priority 1: Crippled ships → Drydock queues
  ## - Priority 2: Crippled starbases → Colony repair queue
  ## - Priority 2: Crippled ground units → Colony repair queue
  ## - Priority 3: Crippled Neorias → Colony repair queue
  ##
  ## Players can cancel/modify these during CMD5 (player window).
  ## Payment happens at commissioning (CMD2 next turn).
  
  logInfo("Commands", "[CMD3] Auto-Repair Submission")
  
  var coloniesProcessed = 0
  for colony in state.allColonies():
    if colony.autoRepair:
      repairs.submitAllAutomaticRepairs(state, colony.systemId)
      coloniesProcessed += 1
  
  logInfo("Commands", &"[CMD3] Processed auto-repairs for {coloniesProcessed} colonies")

# =============================================================================
# CMD4: COLONY AUTOMATION
# =============================================================================

proc processColonyAutomation(
    state: var GameState,
    orders: Table[HouseId, CommandPacket],
    events: var seq[GameEvent]
) =
  ## CMD4: Automatically organize newly commissioned assets
  ##
  ## Per canonical spec:
  ## - 4a: Auto-assign ships to fleets (autoJoinFleets)
  ## - 4b: Auto-load marines onto transports (autoLoadMarines)
  ## - 4c: Auto-load fighters onto carriers (autoLoadFighters)
  ##
  ## Players see organized fleets/cargo in CMD5 (player window).
  
  logInfo("Commands", "[CMD4] Colony Automation")
  
  # Auto-load cargo at colonies (marines/colonists onto transports)
  # This handles autoLoadMarines logic
  mechanics.autoLoadCargo(state, orders, events)
  
  # Note: Auto-load fighters to carriers is handled by commissioning module
  # when it calls autoLoadFightersToCarriers after commissioning fighters
  
  logInfo("Commands", "[CMD4] Colony Automation complete")

# =============================================================================
# CMD5: PLAYER SUBMISSION WINDOW
# =============================================================================

proc processPlayerSubmissions(
    state: var GameState,
    orders: Table[HouseId, CommandPacket],
    events: var seq[GameEvent]
) =
  ## CMD5: Process player-submitted administrative commands
  ##
  ## Per canonical spec:
  ## - 5a: Zero-turn administrative commands (immediate)
  ## - 5b: Query commands (read-only)
  ## - 5c: Command submission (queued for CMD6)
  ##
  ## This step processes colony management, population transfers, terraforming.
  
  logInfo("Commands", "[CMD5] Player Submission Window")
  
  for (houseId, house) in state.activeHousesWithId():
    if houseId in orders:
      # Colony management commands (tax rates, auto-flags)
      colony_engine.resolveColonyCommands(state, orders[houseId])
      
      # Population transfers (Space Guild)
      pop_transfers.resolvePopulationTransfers(state, orders[houseId], events)
      
      # Terraforming commands
      terraforming.resolveTerraformCommands(state, orders[houseId], events)
  
  logInfo("Commands", "[CMD5] Player Submission Window complete")

# =============================================================================
# CMD6: ORDER PROCESSING & VALIDATION
# =============================================================================

proc processResearchAllocation(
    state: var GameState,
    orders: Table[HouseId, CommandPacket],
    events: var seq[GameEvent]
) =
  ## Process research allocation with treasury scaling
  ## Per canonical spec CMD6e
  
  for (houseId, _) in state.activeHousesWithId():
    if houseId notin orders:
      continue
    
    let packet = orders[houseId]
    let allocation = packet.researchAllocation
    
    # Calculate total PP cost for research
    var totalResearchCost: int32 = allocation.economic + allocation.science
    for field, pp in allocation.technology:
      totalResearchCost += pp
    
    # Skip if no research allocated
    if totalResearchCost == 0:
      continue
    
    # Get house for reading/writing (UFCS pattern)
    var house = state.house(houseId).get()
    var scaledAllocation = allocation
    let treasury = house.treasury
    
    # Treasury scaling - can't spend more than we have
    if treasury <= 0:
      # Bankrupt - no research
      scaledAllocation.economic = 0
      scaledAllocation.science = 0
      scaledAllocation.technology = initTable[TechField, int32]()
      totalResearchCost = 0
      logWarn("Research",
        &"{houseId} research cancelled - negative treasury ({treasury} PP)")
    elif totalResearchCost > treasury:
      # Scale down proportionally
      let affordablePercent = float(treasury) / float(totalResearchCost)
      scaledAllocation.economic =
        int32(float(allocation.economic) * affordablePercent)
      scaledAllocation.science =
        int32(float(allocation.science) * affordablePercent)
      
      var scaledTech = initTable[TechField, int32]()
      for field, pp in allocation.technology:
        scaledTech[field] = int32(float(pp) * affordablePercent)
      scaledAllocation.technology = scaledTech
      
      # Recalculate actual cost
      totalResearchCost = scaledAllocation.economic + scaledAllocation.science
      for field, pp in scaledAllocation.technology:
        totalResearchCost += pp
      
      logWarn("Research",
        &"{houseId} research scaled to {int(affordablePercent * 100)}%")
    
    # Deduct from treasury
    if totalResearchCost > 0:
      house.treasury -= totalResearchCost
      logInfo("Research", &"{houseId} spent {totalResearchCost} PP on research")
    
    # Calculate GHO (Gross House Output)
    var gho: int32 = 0
    for colony in state.coloniesOwned(houseId):
      gho += colony.production
    
    # Get current science level for RP conversion
    let currentSL = house.techTree.levels.sl
    
    # Convert PP to RP using tech costs
    let earnedRP = tech_costs.allocateResearch(scaledAllocation, gho, currentSL)
    
    # Accumulate RP
    house.techTree.accumulated.economic += earnedRP.economic
    house.techTree.accumulated.science += earnedRP.science
    
    for field, trp in earnedRP.technology:
      if field notin house.techTree.accumulated.technology:
        house.techTree.accumulated.technology[field] = 0
      house.techTree.accumulated.technology[field] += trp
    
    # Write back house changes
    state.updateHouse(houseId, house)

proc processOrderValidation(
    state: var GameState,
    orders: Table[HouseId, CommandPacket],
    events: var seq[GameEvent]
) =
  ## CMD6: Validate and store fleet commands, process builds and research
  ##
  ## Per canonical spec:
  ## - 6a: Validate fleet commands (store in Fleet.command)
  ## - 6b: Process build orders (pay PP upfront)
  ## - 6c: Process repair orders (manual)
  ## - 6d: Process tech research allocation
  
  logInfo("Commands", "[CMD6] Order Processing & Validation")
  
  # 6a: Process build commands
  logInfo("Commands", "[CMD6a] Processing build orders")
  for (houseId, house) in state.activeHousesWithId():
    if houseId in orders:
      construction.resolveBuildOrders(state, orders[houseId], events)
  
  # 6b: Validate and store fleet commands
  logInfo("Commands", "[CMD6b] Validating fleet commands")
  var ordersStored = 0
  var ordersRejected = 0
  
  for (houseId, house) in state.activeHousesWithId():
    if houseId notin orders:
      continue
    
    for cmd in orders[houseId].fleetCommands:
      let validation = cmd_helpers.validateFleetCommand(cmd, state, houseId)
      
      if validation.valid:
        let fleetOpt = state.fleet(cmd.fleetId)
        if fleetOpt.isSome:
          var fleet = fleetOpt.get()
          fleet.command = cmd
          fleet.missionState = MissionState.Traveling
          fleet.missionTarget = cmd.targetSystem
          state.updateFleet(cmd.fleetId, fleet)
          ordersStored += 1
          
          logDebug("Commands", &"  [STORED] Fleet {cmd.fleetId}: {cmd.commandType}")
      else:
        ordersRejected += 1
        logWarn("Commands", &"  [REJECTED] Fleet {cmd.fleetId}: {cmd.commandType} - {validation.error}")
        events.add(
          event_factory.orderRejected(
            houseId,
            $cmd.commandType,
            validation.error,
            fleetId = some(cmd.fleetId)
          )
        )
  
  logInfo("Commands", &"[CMD6b] Fleet commands: {ordersStored} stored, {ordersRejected} rejected")
  
  # 6c: Process manual repair orders
  logInfo("Commands", "[CMD6c] Processing manual repair orders")
  for (houseId, house) in state.activeHousesWithId():
    if houseId in orders:
      for repairCmd in orders[houseId].repairCommands:
        discard repairs.processManualRepairCommand(state, repairCmd)
  
  # 6d: Process research allocation
  logInfo("Commands", "[CMD6d] Processing research allocation")
  processResearchAllocation(state, orders, events)
  
  logInfo("Commands", "[CMD6] Order Processing & Validation complete")

# =============================================================================
# MAIN ENTRY POINT
# =============================================================================

proc resolveCommandPhase*(
    state: var GameState,
    orders: Table[HouseId, CommandPacket],
    events: var seq[GameEvent],
    rng: var Rand,
) =
  ## Command Phase Resolution - Phase 3 of Canonical Turn Cycle
  ##
  ## Executes six steps per docs/engine/ec4x_canonical_turn_cycle.md:
  ## - CMD1: Order Cleanup
  ## - CMD2: Unified Commissioning
  ## - CMD3: Auto-Repair Submission
  ## - CMD4: Colony Automation
  ## - CMD5: Player Submission Window
  ## - CMD6: Order Processing & Validation
  
  logInfo("Commands", &"=== Command Phase === (turn={state.turn})")
  
  # CMD1: Order Cleanup
  cleanupCompletedCommands(state, events)
  
  # CMD2: Unified Commissioning
  commissionEntities(state, events)
  
  # CMD3: Auto-Repair Submission
  submitAutoRepairs(state, events)
  
  # CMD4: Colony Automation
  processColonyAutomation(state, orders, events)
  
  # CMD5: Player Submission Window
  processPlayerSubmissions(state, orders, events)
  
  # CMD6: Order Processing & Validation
  processOrderValidation(state, orders, events)
  
  logInfo("Commands", "=== Command Phase Complete ===")
