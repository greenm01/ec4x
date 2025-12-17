## Economy resolution - Income, construction, and maintenance operations
##
## This module handles all economy-related resolution including:
## - Income phase with resource collection and espionage effects
## - Build orders and construction management
## - Squadron management and fleet organization
## - Cargo management for transport squadrons (Expansion/Auxiliary)
## - Population transfers via Space Guild
## - Terraforming operations
## - Maintenance phase with upkeep and effect tracking
##
## **Construction & Commissioning Phase Architecture**
##
## This module handles construction and commissioning because these operations
## represent the economic/industrial workflow of turning treasury resources
## into operational military units. The flow is:
##
## 1. **Build Phase** (`resolveBuildOrders`):
##    - Houses spend treasury on construction projects
##    - Progress tracks toward completion over multiple turns
##    - Represents shipyard/factory industrial capacity
##
## 2. **Commissioning Phase** (within construction completion):
##    - Completed ships are added to `colony.unassignedSquadrons`
##    - Represents the "delivery" of industrial output
##
## 3. **Fleet Organization Phase** (`autoBalanceSquadronsToFleets`):
##    - Unassigned squadrons are organized into operational fleets
##    - New fleets are created if no stationary fleets exist
##    - Only Active fleets are considered (excludes Reserve/Mothballed)
##    - Represents the transition from industrial output to military readiness
##
## This architecture keeps the economic turn resolution (treasury → ships → fleets)
## separate from tactical fleet operations (movement, combat, espionage) which are
## handled in fleet_orders.nim and combat_resolution.nim.
##
## The auto-fleet creation here enables newly-built units (especially scouts)
## to immediately begin operational duties without requiring explicit player orders.

import std/[tables, options, random, sequtils, hashes, math, strutils, strformat]
import ../../common/[hex, types/core, types/units, types/tech]
import ../gamestate, ../orders, ../fleet, ../squadron, ../starmap, ../logger
import ../order_types  # For StandingOrder and StandingOrderType
import ../economy/[types as econ_types, engine as econ_engine, projects, maintenance, facility_queue]
import ../economy/capacity/fighter as fighter_capacity
import ../economy/capacity/planet_breakers as planet_breaker_capacity
import ../economy/capacity/capital_squadrons as capital_squadron_capacity
import ../economy/capacity/total_squadrons as total_squadron_capacity
import ../research/[types as res_types, costs as res_costs, effects as res_effects, advancement]
import ../espionage/[types as esp_types, engine as esp_engine]
import ../diplomacy/[types as dip_types, proposals as dip_proposals]
import ../blockade/engine as blockade_engine
import ../intelligence/[detection, types as intel_types, generator as intel_gen, starbase_surveillance, scout_intel]
import ../population/[types as pop_types]
import ../config/[espionage_config, population_config, ground_units_config, gameplay_config, construction_config, facilities_config]
import ../colonization/engine as col_engine
import ./types  # Common resolution types
import ./fleet_orders  # For findClosestOwnedColony
import ./event_factory/init as event_factory
import ../prestige as prestige_types
import ../prestige/application as prestige_app
import ./phases/income_phase  # NEW implementation with capacity enforcement
import ./phases/maintenance_phase as maint_phase  # NEW implementation with fleet movement

# Forward declarations
# NOTE: autoLoadFightersToCarriers is unused - see when false: block below
# proc autoLoadFightersToCarriers(state: var gamestate.GameState, colony: var gamestate.Colony, systemId: SystemId, orders: Table[HouseId, OrderPacket])

proc resolveColonyManagementOrders*(state: var GameState, packet: OrderPacket) =
  ## Process colony management orders - tax rates, auto-repair toggles, etc.
  for order in packet.colonyManagement:
    # Validate colony exists and is owned (should have been validated already)
    if order.colonyId notin state.colonies:
      logError(LogCategory.lcEconomy, &"Colony management failed: System-{order.colonyId} has no colony")
      continue

    var colony = state.colonies[order.colonyId]
    if colony.owner != packet.houseId:
      logError(LogCategory.lcEconomy, &"Colony management failed: {packet.houseId} does not own system-{order.colonyId}")
      continue

    # Execute action
    case order.action
    of ColonyManagementAction.SetTaxRate:
      colony.taxRate = order.taxRate
      logInfo(LogCategory.lcEconomy, &"Colony-{order.colonyId} tax rate set to {order.taxRate}%")

    of ColonyManagementAction.SetAutoRepair:
      colony.autoRepairEnabled = order.enableAutoRepair
      let status = if order.enableAutoRepair: "enabled" else: "disabled"
      logInfo(LogCategory.lcEconomy, &"Colony-{order.colonyId} auto-repair {status}")

    # Write back
    state.colonies[order.colonyId] = colony

proc resolveTerraformOrders*(state: var GameState, packet: OrderPacket, events: var seq[GameEvent]) =
  ## Process terraforming orders - initiate new terraforming projects
  ## Per economy.md Section 4.7
  for order in packet.terraformOrders:
    # Validate colony exists and is owned by house
    if order.colonySystem notin state.colonies:
      logError(LogCategory.lcEconomy, &"Terraforming failed: System-{order.colonySystem} has no colony")
      continue

    var colony = state.colonies[order.colonySystem]
    if colony.owner != packet.houseId:
      logError(LogCategory.lcEconomy, &"Terraforming failed: {packet.houseId} does not own system-{order.colonySystem}")
      continue

    # Check if already terraforming
    if colony.activeTerraforming.isSome:
      logError(LogCategory.lcEconomy, &"Terraforming failed: System-{order.colonySystem} already has active terraforming project")
      continue

    # Get house tech level
    if packet.houseId notin state.houses:
      logError(LogCategory.lcEconomy, &"Terraforming failed: House {packet.houseId} not found")
      continue

    let house = state.houses[packet.houseId]
    let terLevel = house.techTree.levels.terraformingTech

    # Validate TER level requirement
    let currentClass = ord(colony.planetClass) + 1  # Convert enum to class number (1-7)
    if not res_effects.canTerraform(currentClass, terLevel):
      let targetClass = currentClass + 1
      logError(LogCategory.lcEconomy, &"Terraforming failed: TER level {terLevel} insufficient for class {currentClass} → {targetClass} (requires TER {targetClass})")
      continue

    # Calculate costs and duration
    let targetClass = currentClass + 1
    let ppCost = res_effects.getTerraformingBaseCost(currentClass)
    let turnsRequired = res_effects.getTerraformingSpeed(terLevel)

    # Check house treasury has sufficient PP
    if house.treasury < ppCost:
      logError(LogCategory.lcEconomy, &"Terraforming failed: Insufficient PP (need {ppCost}, have {house.treasury})")
      continue

    # Deduct PP cost from house treasury
    state.houses[packet.houseId].treasury -= ppCost

    # Create terraforming project
    let project = TerraformProject(
      startTurn: state.turn,
      turnsRemaining: turnsRequired,
      targetClass: targetClass,
      ppCost: ppCost,
      ppPaid: ppCost
    )

    colony.activeTerraforming = some(project)
    state.colonies[order.colonySystem] = colony

    let className = case targetClass
      of 1: "Extreme"
      of 2: "Desolate"
      of 3: "Hostile"
      of 4: "Harsh"
      of 5: "Benign"
      of 6: "Lush"
      of 7: "Eden"
      else: "Unknown"

    logInfo(LogCategory.lcEconomy,
      &"{house.name} initiated terraforming of system-{order.colonySystem} " &
      &"to {className} (class {targetClass}) - Cost: {ppCost} PP, Duration: {turnsRequired} turns")

    # Note: This was using TerraformComplete incorrectly for "initiated" - should be constructionStarted
    events.add(event_factory.constructionStarted(
      packet.houseId,
      &"Terraforming to {className}",
      order.colonySystem,
      ppCost
    ))

proc hasVisibilityOn(state: GameState, systemId: SystemId, houseId: HouseId): bool =
  ## Check if a house has visibility on a system (fog of war)
  ## A house can see a system if:
  ## - They own a colony there
  ## - They have a fleet present
  ## - They have a spy scout present

  # Check if house owns colony in this system
  if systemId in state.colonies:
    if state.colonies[systemId].owner == houseId:
      return true

  # Check if house has any fleets in this system
  for fleetId, fleet in state.fleets:
    if fleet.owner == houseId and fleet.location == systemId:
      return true

  return false

proc canGuildTraversePath(state: GameState, path: seq[SystemId], transferringHouse: HouseId): bool =
  ## Check if Space Guild can traverse a path for a given house
  ## Guild validates path using the house's known intel (fog of war)
  ## Returns false if:
  ## - Path crosses system the house has no visibility on (intel leak prevention)
  ## - Path crosses enemy-controlled system (blockade)
  for systemId in path:
    # Player must have visibility on this system (prevents intel leak exploit)
    if not hasVisibilityOn(state, systemId, transferringHouse):
      return false

    # If system has a colony, it must be friendly (not enemy-controlled)
    if systemId in state.colonies:
      let colony = state.colonies[systemId]
      if colony.owner != transferringHouse:
        # Enemy-controlled system - Guild cannot pass through
        return false

  return true

proc calculateTransitTime(state: GameState, sourceSystem: SystemId, destSystem: SystemId, houseId: HouseId): tuple[turns: int, jumps: int] =
  ## Calculate Space Guild transit time and jump distance
  ## Per config/population.toml: turns_per_jump = 1, minimum_turns = 1
  ## Uses pathfinding to calculate actual jump lane distance
  ## Returns (turns: -1, jumps: 0) if path crosses enemy territory (Guild cannot complete transfer)
  if sourceSystem == destSystem:
    return (turns: 1, jumps: 0)  # Minimum 1 turn even for same system, 0 jumps

  # Space Guild civilian transports can use all lanes (not restricted by fleet composition)
  # Create a dummy fleet that can traverse all lanes
  let dummyFleet = Fleet(
    id: "transit_calc",
    owner: "GUILD".HouseId,
    location: sourceSystem,
    squadrons: @[]
  )

  # Use starmap pathfinding to get actual jump distance
  let pathResult = state.starMap.findPath(sourceSystem, destSystem, dummyFleet)

  if pathResult.found:
    # Check if path crosses enemy territory
    if not canGuildTraversePath(state, pathResult.path, houseId):
      return (turns: -1, jumps: 0)  # Cannot traverse enemy territory

    # Path length - 1 = number of jumps (e.g., [A, B, C] = 2 jumps)
    # 1 turn per jump per config/population.toml
    let jumps = pathResult.path.len - 1
    return (turns: max(1, jumps), jumps: jumps)
  else:
    # No valid path found (shouldn't happen on a connected map, but handle gracefully)
    # Fall back to hex distance as approximation
    if sourceSystem in state.starMap.systems and destSystem in state.starMap.systems:
      let source = state.starMap.systems[sourceSystem]
      let dest = state.starMap.systems[destSystem]
      let hexDist = distance(source.coords, dest.coords)
      let jumps = hexDist.int
      return (turns: max(1, jumps), jumps: jumps)
    else:
      return (turns: 1, jumps: 0)  # Ultimate fallback

proc calculateTransferCost(planetClass: PlanetClass, ptuAmount: int, jumps: int): int =
  ## Calculate Space Guild transfer cost per config/population.toml
  ## Formula: base_cost_per_ptu × ptu_amount × (1 + jumps × 0.20)
  ## Source: docs/specs/economy.md Section 3.7, config/population.toml [transfer_costs]

  # Base cost per PTU by planet class (config/population.toml)
  let baseCostPerPTU = case planetClass
    of PlanetClass.Eden: 4
    of PlanetClass.Lush: 5
    of PlanetClass.Benign: 6
    of PlanetClass.Harsh: 8
    of PlanetClass.Hostile: 10
    of PlanetClass.Desolate: 12
    of PlanetClass.Extreme: 15

  # Distance modifier: +20% per jump (config/population.toml [transfer_modifiers])
  # Per spec: "Base × (1 + 0.2 × jumps)" where jumps includes the first jump
  let distanceMultiplier = if jumps > 0:
    1.0 + (float(jumps) * 0.20)
  else:
    1.0  # Same system, no distance penalty

  # Total cost = base × ptu × distance_modifier (rounded up)
  let totalCost = ceil(float(baseCostPerPTU * ptuAmount) * distanceMultiplier).int

  return totalCost

proc resolvePopulationTransfers*(state: var GameState, packet: OrderPacket, events: var seq[GameEvent]) =
  ## Process Space Guild population transfers between colonies
  ## Source: docs/specs/economy.md Section 3.7, config/population.toml
  logDebug(LogCategory.lcEconomy, &"Processing population transfers for {state.houses[packet.houseId].name}")

  for transfer in packet.populationTransfers:
    # Validate source colony exists and is owned by house
    if transfer.sourceColony notin state.colonies:
      logError(LogCategory.lcEconomy, &"Transfer failed: source colony {transfer.sourceColony} not found")
      continue

    var sourceColony = state.colonies[transfer.sourceColony]
    if sourceColony.owner != packet.houseId:
      logError(LogCategory.lcEconomy, &"Transfer failed: source colony {transfer.sourceColony} not owned by {packet.houseId}")
      continue

    # Validate destination colony exists and is owned by house
    if transfer.destColony notin state.colonies:
      logError(LogCategory.lcEconomy, &"Transfer failed: destination colony {transfer.destColony} not found")
      continue

    var destColony = state.colonies[transfer.destColony]
    if destColony.owner != packet.houseId:
      logError(LogCategory.lcEconomy, &"Transfer failed: destination colony {transfer.destColony} not owned by {packet.houseId}")
      continue

    # Critical validation: Destination must have ≥1 PTU (50k souls) to be a functional colony
    if destColony.souls < soulsPerPtu():
      logError(LogCategory.lcEconomy,
        &"Transfer failed: destination colony {transfer.destColony} has only {destColony.souls} " &
        &"souls (needs ≥{soulsPerPtu()} to accept transfers)")
      continue

    # Convert PTU amount to souls for exact transfer
    let soulsToTransfer = transfer.ptuAmount * soulsPerPtu()

    # Validate source has enough souls (can transfer any amount, even fractional PTU)
    if sourceColony.souls < soulsToTransfer:
      logError(LogCategory.lcEconomy,
        &"Transfer failed: source colony {transfer.sourceColony} has only {sourceColony.souls} " &
        &"souls (needs {soulsToTransfer} for {transfer.ptuAmount} PTU)")
      continue

    # Check concurrent transfer limit (max 5 per house per config/population.toml)
    let activeTransfers = state.populationInTransit.filterIt(it.houseId == packet.houseId)
    if activeTransfers.len >= globalPopulationConfig.max_concurrent_transfers:
      logWarn(LogCategory.lcEconomy,
        &"Transfer rejected: Maximum {globalPopulationConfig.max_concurrent_transfers} " &
        &"concurrent transfers reached (house has {activeTransfers.len} active)")
      continue

    # Calculate transit time and jump distance
    let (transitTime, jumps) = calculateTransitTime(state, transfer.sourceColony, transfer.destColony, packet.houseId)

    # Check if Guild can complete the transfer (path must be known and not blocked)
    if transitTime < 0:
      logError(LogCategory.lcEconomy,
        &"Transfer failed: No safe Guild route between {transfer.sourceColony} and {transfer.destColony} " &
        &"(requires scouted path through friendly/neutral territory)")
      continue

    let arrivalTurn = state.turn + transitTime

    # Calculate transfer cost based on destination planet class and jump distance
    # Per config/population.toml and docs/specs/economy.md Section 3.7
    let cost = calculateTransferCost(destColony.planetClass, transfer.ptuAmount, jumps)

    # Check house treasury and deduct cost
    var house = state.houses[packet.houseId]
    if house.treasury < cost:
      logError(LogCategory.lcEconomy, &"Transfer failed: Insufficient funds (need {cost} PP, have {house.treasury} PP)")
      continue

    # Deduct cost from treasury
    house.treasury -= cost
    state.houses[packet.houseId] = house

    # Deduct souls from source colony immediately (they've departed)
    sourceColony.souls -= soulsToTransfer
    sourceColony.population = sourceColony.souls div 1_000_000
    state.colonies[transfer.sourceColony] = sourceColony

    # Create in-transit entry
    let transferId = $packet.houseId & "_" & $transfer.sourceColony & "_" & $transfer.destColony & "_" & $state.turn
    let inTransit = pop_types.PopulationInTransit(
      id: transferId,
      houseId: packet.houseId,
      sourceSystem: transfer.sourceColony,
      destSystem: transfer.destColony,
      ptuAmount: transfer.ptuAmount,
      costPaid: cost,
      arrivalTurn: arrivalTurn
    )
    state.populationInTransit.add(inTransit)

    logInfo(LogCategory.lcEconomy,
      &"Space Guild transporting {transfer.ptuAmount} PTU ({soulsToTransfer} souls) from " &
      &"{transfer.sourceColony} to {transfer.destColony} (arrives turn {arrivalTurn}, cost: {cost} PP)")

    events.add(event_factory.populationTransfer(
      packet.houseId,
      transfer.ptuAmount,
      transfer.sourceColony,
      transfer.destColony,
      true,
      &"Space Guild transport initiated (ETA: turn {arrivalTurn}, cost: {cost} PP)"
    ))

proc resolvePopulationArrivals*(state: var GameState, events: var seq[GameEvent]) =
  ## Process Space Guild population transfers that arrive this turn
  ## Implements risk handling per config/population.toml [transfer_risks]
  ## Per config: dest_blockaded_behavior = "closest_owned"
  ## Per config: dest_collapsed_behavior = "closest_owned"
  logDebug(LogCategory.lcGeneral, &"[Processing Space Guild Arrivals]")

  var arrivedTransfers: seq[int] = @[]  # Indices to remove after processing

  for idx, transfer in state.populationInTransit:
    if transfer.arrivalTurn != state.turn:
      continue  # Not arriving this turn

    let soulsToDeliver = transfer.ptuAmount * soulsPerPtu()

    # Check destination status
    if transfer.destSystem notin state.colonies:
      # Destination colony no longer exists
      logWarn(LogCategory.lcEconomy, &"Transfer {transfer.id}: {transfer.ptuAmount} PTU LOST - destination colony destroyed")
      arrivedTransfers.add(idx)
      events.add(event_factory.populationTransfer(
        transfer.houseId,
        transfer.ptuAmount,
        transfer.sourceSystem,
        transfer.destSystem,
        false,
        "destination destroyed"
      ))
      continue

    var destColony = state.colonies[transfer.destSystem]

    # Check if destination requires alternative delivery
    # Space Guild makes best-faith effort to deliver somewhere safe
    # Per config/population.toml: dest_blockaded_behavior = "closest_owned"
    # Per config/population.toml: dest_collapsed_behavior = "closest_owned"
    # Per config/population.toml: dest_conquered_behavior = "closest_owned" (NEW)
    var needsAlternativeDestination = false
    var alternativeReason = ""

    if destColony.owner != transfer.houseId:
      # Destination conquered - Guild tries to find alternative colony
      needsAlternativeDestination = true
      alternativeReason = "conquered by " & $destColony.owner
    elif destColony.blockaded:
      needsAlternativeDestination = true
      alternativeReason = "blockaded"
    elif destColony.souls < soulsPerPtu():
      needsAlternativeDestination = true
      alternativeReason = "collapsed below minimum viable population"

    if needsAlternativeDestination:
      # Space Guild attempts to deliver to closest owned colony
      let alternativeDest = findClosestOwnedColony(state, transfer.destSystem, transfer.houseId)

      if alternativeDest.isSome:
        # Deliver to alternative colony
        let altSystemId = alternativeDest.get()
        var altColony = state.colonies[altSystemId]
        altColony.souls += soulsToDeliver
        altColony.population = altColony.souls div 1_000_000
        state.colonies[altSystemId] = altColony

        logWarn(LogCategory.lcEconomy,
          &"Transfer {transfer.id}: {transfer.ptuAmount} PTU redirected to {altSystemId} " &
          &"- original destination {transfer.destSystem} {alternativeReason}")
        events.add(event_factory.populationTransfer(
          transfer.houseId,
          transfer.ptuAmount,
          transfer.sourceSystem,
          altSystemId,
          true,
          &"redirected from {transfer.destSystem} ({alternativeReason})"
        ))
      else:
        # No owned colonies - colonists are lost
        logWarn(LogCategory.lcEconomy,
          &"Transfer {transfer.id}: {transfer.ptuAmount} PTU LOST - destination {alternativeReason}, no owned colonies available")
        events.add(event_factory.populationTransfer(
          transfer.houseId,
          transfer.ptuAmount,
          transfer.sourceSystem,
          transfer.destSystem,
          false,
          &"{alternativeReason}, no owned colonies for delivery"
        ))

      arrivedTransfers.add(idx)
      continue

    # Successful delivery!
    destColony.souls += soulsToDeliver
    destColony.population = destColony.souls div 1_000_000
    state.colonies[transfer.destSystem] = destColony

    logInfo(LogCategory.lcEconomy,
      &"Transfer {transfer.id}: {transfer.ptuAmount} PTU arrived at {transfer.destSystem} ({soulsToDeliver} souls)")
    events.add(event_factory.populationTransfer(
      transfer.houseId,
      transfer.ptuAmount,
      transfer.sourceSystem,
      transfer.destSystem,
      true,
      ""
    ))

    arrivedTransfers.add(idx)

  # Remove processed transfers (in reverse order to preserve indices)
  for idx in countdown(arrivedTransfers.len - 1, 0):
    state.populationInTransit.del(arrivedTransfers[idx])

proc processTerraformingProjects(state: var GameState, events: var seq[GameEvent]) =
  ## Process active terraforming projects for all houses
  ## Per economy.md Section 4.7

  for colonyId, colony in state.colonies.mpairs:
    if colony.activeTerraforming.isNone:
      continue

    let houseId = colony.owner
    if houseId notin state.houses:
      continue

    let house = state.houses[houseId]
    var project = colony.activeTerraforming.get()
    project.turnsRemaining -= 1

    if project.turnsRemaining <= 0:
      # Terraforming complete!
      # Convert int class number (1-7) back to PlanetClass enum (0-6)
      colony.planetClass = PlanetClass(project.targetClass - 1)
      colony.activeTerraforming = none(TerraformProject)

      let className = case project.targetClass
        of 1: "Extreme"
        of 2: "Desolate"
        of 3: "Hostile"
        of 4: "Harsh"
        of 5: "Benign"
        of 6: "Lush"
        of 7: "Eden"
        else: "Unknown"

      logInfo(LogCategory.lcEconomy,
        &"{house.name} completed terraforming of {colonyId} to {className} (class {project.targetClass})")

      events.add(event_factory.terraformComplete(
        houseId,
        colonyId,
        className
      ))
    else:
      logDebug(LogCategory.lcEconomy,
        &"{house.name} terraforming {colonyId}: {project.turnsRemaining} turn(s) remaining")
      # Update project
      colony.activeTerraforming = some(project)

proc resolveMaintenancePhase*(state: var GameState, events: var seq[GameEvent], orders: Table[HouseId, OrderPacket], rng: var Rand): seq[econ_types.CompletedProject] =
  ## Phase 4: Upkeep, effect decrements, and diplomatic status updates
  ## Forward to new implementation in phases/maintenance_phase.nim
  return maint_phase.resolveMaintenancePhase(state, events, orders, rng)

proc resolveIncomePhase*(state: var GameState, orders: Table[HouseId, OrderPacket], events: var seq[GameEvent]) =
  ## Phase 2: Collect income and allocate resources
  ## Forward to new implementation in phases/income_phase.nim which includes capacity enforcement
  income_phase.resolveIncomePhase(state, orders, events)

  # Process research allocation
  # Per economy.md:4.0: Players allocate PP to research each turn
  # PP is converted to ERP/SRP/TRP based on current tech levels and GHO
  for houseId in state.houses.keys:
    if houseId in orders:
      let packet = orders[houseId]
      let allocation = packet.researchAllocation

      # Calculate total PP cost for this research allocation
      var totalResearchCost = allocation.economic + allocation.science
      for field, pp in allocation.technology:
        totalResearchCost += pp

      # Scale down research allocation if treasury cannot afford it
      # Research is planned at AI time but processed after Income Phase
      # This prevents negative treasury from over-aggressive research budgets
      var scaledAllocation = allocation

      # CRITICAL: If treasury is negative or zero, no research happens
      if state.houses[houseId].treasury <= 0:
        # Zero out all research - house is bankrupt
        scaledAllocation.economic = 0
        scaledAllocation.science = 0
        scaledAllocation.technology = initTable[TechField, int]()
        totalResearchCost = 0

        logWarn(LogCategory.lcResearch,
          &"{houseId} research cancelled - negative treasury ({state.houses[houseId].treasury} PP)")

      elif totalResearchCost > state.houses[houseId].treasury:
        # Calculate scaling factor (how much we can actually afford)
        let affordablePercent = float(state.houses[houseId].treasury) / float(totalResearchCost)

        # Scale all allocations proportionally
        scaledAllocation.economic = int(float(allocation.economic) * affordablePercent)
        scaledAllocation.science = int(float(allocation.science) * affordablePercent)

        var scaledTech = initTable[TechField, int]()
        for field, pp in allocation.technology:
          scaledTech[field] = int(float(pp) * affordablePercent)
        scaledAllocation.technology = scaledTech

        # Recalculate actual cost
        totalResearchCost = scaledAllocation.economic + scaledAllocation.science
        for field, pp in scaledAllocation.technology:
          totalResearchCost += pp

        logWarn(LogCategory.lcResearch,
          &"{houseId} research budget scaled down by {int(affordablePercent * 100)}% due to treasury constraints")

      # Deduct research cost from treasury (CRITICAL FIX)
      # Research competes with builds for treasury resources
      if totalResearchCost > 0:
        state.houses[houseId].treasury -= totalResearchCost
        logInfo(LogCategory.lcResearch,
          &"{houseId} spent {totalResearchCost} PP on research " &
          &"(treasury: {state.houses[houseId].treasury + totalResearchCost} → {state.houses[houseId].treasury})")

      # Calculate GHO for this house
      var gho = 0
      for colony in state.colonies.values:
        if colony.owner == houseId:
          gho += colony.production

      # Get current tech levels
      let currentSL = state.houses[houseId].techTree.levels.scienceLevel  # Science Level

      # Convert PP allocations to RP (use SCALED allocation, not original)
      let earnedRP = res_costs.allocateResearch(scaledAllocation, gho, currentSL)

      # Accumulate RP
      state.houses[houseId].techTree.accumulated.economic += earnedRP.economic
      state.houses[houseId].techTree.accumulated.science += earnedRP.science

      for field, trp in earnedRP.technology:
        if field notin state.houses[houseId].techTree.accumulated.technology:
          state.houses[houseId].techTree.accumulated.technology[field] = 0
        state.houses[houseId].techTree.accumulated.technology[field] += trp

      # Save earned RP to House state for diagnostics tracking
      state.houses[houseId].lastTurnResearchERP = earnedRP.economic
      state.houses[houseId].lastTurnResearchSRP = earnedRP.science
      var totalTRP = 0
      for field, trp in earnedRP.technology:
        totalTRP += trp
      state.houses[houseId].lastTurnResearchTRP = totalTRP

      # Log allocations (use SCALED allocation for accurate reporting)
      if scaledAllocation.economic > 0:
        logDebug(LogCategory.lcResearch,
          &"{houseId} allocated {scaledAllocation.economic} PP → {earnedRP.economic} ERP " &
          &"(total: {state.houses[houseId].techTree.accumulated.economic} ERP)")
      if scaledAllocation.science > 0:
        logDebug(LogCategory.lcResearch,
          &"{houseId} allocated {scaledAllocation.science} PP → {earnedRP.science} SRP " &
          &"(total: {state.houses[houseId].techTree.accumulated.science} SRP)")
      for field, pp in scaledAllocation.technology:
        if pp > 0 and field in earnedRP.technology:
          let totalTRP = state.houses[houseId].techTree.accumulated.technology.getOrDefault(field, 0)
          logDebug(LogCategory.lcResearch,
            &"{houseId} allocated {pp} PP → {earnedRP.technology[field]} TRP ({field}) (total: {totalTRP} TRP)")

  # Tech advancement happens in resolveCommandPhase (not here)
  # Per economy.md:4.1: Tech upgrades can be purchased every turn if RP is available

  # Research breakthroughs (every 5 turns)
  # Per economy.md:4.1.1: Breakthrough rolls provide bonus RP, cost reductions, or free levels
  if advancement.isBreakthroughTurn(state.turn):
    logDebug(LogCategory.lcResearch, &"[RESEARCH BREAKTHROUGHS] Turn {state.turn} - rolling for breakthroughs")
    for houseId in state.houses.keys:
      # Calculate total RP invested in last 5 turns
      # NOTE: This is a simplified approximation - proper implementation would track historical RP
      let investedRP = state.houses[houseId].lastTurnResearchERP +
                       state.houses[houseId].lastTurnResearchSRP +
                       state.houses[houseId].lastTurnResearchTRP

      # Roll for breakthrough
      var rng = initRand(hash(state.turn) xor hash(houseId))
      let breakthroughOpt = advancement.rollBreakthrough(investedRP * 5, rng)  # Approximate 5-turn total

      if breakthroughOpt.isSome:
        let breakthrough = breakthroughOpt.get
        logInfo(LogCategory.lcResearch, &"{houseId} BREAKTHROUGH: {breakthrough}")

        # Apply breakthrough effects
        let allocation = res_types.ResearchAllocation(
          economic: state.houses[houseId].lastTurnResearchERP,
          science: state.houses[houseId].lastTurnResearchSRP,
          technology: initTable[TechField, int]()
        )
        let event = advancement.applyBreakthrough(
          state.houses[houseId].techTree,
          breakthrough,
          allocation
        )

        logDebug(LogCategory.lcResearch, &"{houseId} breakthrough effect applied (category: {event.category})")

