## Economy resolution - Income, construction, and maintenance operations
##
## This module handles all economy-related resolution including:
## - Income phase with resource collection and espionage effects
## - Build orders and construction management
## - Squadron management and fleet organization
## - Cargo management for spacelift ships
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
import ../gamestate, ../orders, ../fleet, ../squadron, ../spacelift, ../starmap, ../logger
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
proc autoBalanceSquadronsToFleets*(state: var gamestate.GameState, colony: var gamestate.Colony, systemId: SystemId, orders: Table[HouseId, OrderPacket])
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

  # Check if house has spy scouts in this system
  for scoutId, scout in state.spyScouts:
    if scout.owner == houseId and scout.location == systemId and not scout.detected:
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
    squadrons: @[],
    spaceliftShips: @[]
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

  # Apply ongoing espionage effects to houses
  var activeEffects: seq[esp_types.OngoingEffect] = @[]
  for effect in state.ongoingEffects:
    if effect.turnsRemaining > 0:
      activeEffects.add(effect)

      case effect.effectType
      of esp_types.EffectType.SRPReduction:
        logDebug(LogCategory.lcGeneral,
          &"{effect.targetHouse} affected by SRP reduction (-{int(effect.magnitude * 100)}%)")
      of esp_types.EffectType.NCVReduction:
        logDebug(LogCategory.lcGeneral,
          &"{effect.targetHouse} affected by NCV reduction (-{int(effect.magnitude * 100)}%)")
      of esp_types.EffectType.TaxReduction:
        logDebug(LogCategory.lcGeneral,
          &"{effect.targetHouse} affected by tax reduction (-{int(effect.magnitude * 100)}%)")
      of esp_types.EffectType.StarbaseCrippled:
        if effect.targetSystem.isSome:
          let systemId = effect.targetSystem.get()
          logDebug(LogCategory.lcGeneral, &"Starbase at system-{systemId} is crippled")

          # Apply crippled state to starbase in colony
          if systemId in state.colonies:
            var colony = state.colonies[systemId]
            if colony.owner == effect.targetHouse:
              for starbase in colony.starbases.mitems:
                if not starbase.isCrippled:
                  starbase.isCrippled = true
                  logDebug(LogCategory.lcGeneral, &"Applied crippled state to starbase {starbase.id}")
              state.colonies[systemId] = colony
      of esp_types.EffectType.IntelBlocked:
        logDebug(LogCategory.lcGeneral, &"{effect.targetHouse} protected by counter-intelligence sweep")
      of esp_types.EffectType.IntelCorrupted:
        logDebug(LogCategory.lcGeneral,
          &"{effect.targetHouse}'s intelligence corrupted by disinformation (+/-{int(effect.magnitude * 100)}% variance)")

  state.ongoingEffects = activeEffects

  # Process EBP/CIP purchases (diplomacy.md:8.2)
  # EBP and CIP cost 40 PP each
  # Over-investment penalty: lose 1 prestige per 1% over 5% of turn budget
  for houseId in state.houses.keys:
    if houseId in orders:
      let packet = orders[houseId]

      if packet.ebpInvestment > 0 or packet.cipInvestment > 0:
        let ebpCost = packet.ebpInvestment * globalEspionageConfig.costs.ebp_cost_pp
        let cipCost = packet.cipInvestment * globalEspionageConfig.costs.cip_cost_pp
        let totalCost = ebpCost + cipCost

        # Deduct from treasury
        if state.houses[houseId].treasury >= totalCost:
          state.houses[houseId].treasury -= totalCost
          state.houses[houseId].espionageBudget.ebpPoints += packet.ebpInvestment
          state.houses[houseId].espionageBudget.cipPoints += packet.cipInvestment
          state.houses[houseId].espionageBudget.ebpInvested = ebpCost
          state.houses[houseId].espionageBudget.cipInvested = cipCost

          logInfo(LogCategory.lcEconomy,
            &"{houseId} purchased {packet.ebpInvestment} EBP, {packet.cipInvestment} CIP ({totalCost} PP)")

          # Check for over-investment penalty (configurable threshold from espionage.toml)
          let turnBudget = state.houses[houseId].espionageBudget.turnBudget
          if turnBudget > 0:
            let totalInvestment = ebpCost + cipCost
            let investmentPercent = (totalInvestment * 100) div turnBudget
            let threshold = globalEspionageConfig.investment.threshold_percentage

            if investmentPercent > threshold:
              let prestigePenalty = -(investmentPercent - threshold) * globalEspionageConfig.investment.penalty_per_percent
              let prestigeEvent = prestige_types.createPrestigeEvent(
                prestige_types.PrestigeSource.MaintenanceShortfall,
                prestigePenalty,
                &"Over-investment penalty: -{int(prestigePenalty * -1)} (investment {investmentPercent}% exceeds {threshold}% threshold)"
              )
              prestige_app.applyPrestigeEvent(state, houseId, prestigeEvent)
              logWarn(LogCategory.lcEconomy, &"Over-investment penalty: {prestigePenalty} prestige")
        else:
          logError(LogCategory.lcEconomy, &"{houseId} insufficient funds for EBP/CIP purchase")

  # Process spy scout detection and intelligence gathering
  # Per assets.md:2.4.2: "For every turn that a spy Scout operates in unfriendly
  # system occupied by rival ELI, the rival will roll on the Spy Detection Table"
  var survivingScouts = initTable[string, SpyScout]()

  for scoutId, scout in state.spyScouts:
    if scout.detected:
      # Scout was detected in a previous turn
      continue

    var wasDetected = false
    let scoutLocation = scout.location

    # Check if system has rival ELI units (fleets with scouts or starbases)
    # Get all houses in the system (from fleets and colonies)
    var housesInSystem: seq[HouseId] = @[]

    # Check for colonies (starbases provide detection)
    if scoutLocation in state.colonies:
      let colony = state.colonies[scoutLocation]
      if colony.owner != scout.owner:
        housesInSystem.add(colony.owner)

    # Check for fleets with scouts
    for fleetId, fleet in state.fleets:
      if fleet.location == scoutLocation and fleet.owner != scout.owner:
        # Check if fleet has scouts
        for squadron in fleet.squadrons:
          if squadron.flagship.shipClass == ShipClass.Scout:
            if not housesInSystem.contains(fleet.owner):
              housesInSystem.add(fleet.owner)
            break

    # For each rival house in system, roll detection
    for rivalHouse in housesInSystem:
      # Build ELI unit from fleets
      var detectorELI: seq[int] = @[]
      var hasStarbase = false

      # Check for colony with starbase
      if scoutLocation in state.colonies:
        let colony = state.colonies[scoutLocation]
        if colony.owner == rivalHouse:
          # Check for operational starbase presence (not crippled)
          for starbase in colony.starbases:
            if not starbase.isCrippled:
              hasStarbase = true
              break

      # Collect ELI from fleets
      for fleetId, fleet in state.fleets:
        if fleet.location == scoutLocation and fleet.owner == rivalHouse:
          for squadron in fleet.squadrons:
            if squadron.flagship.shipClass == ShipClass.Scout:
              detectorELI.add(squadron.flagship.stats.techLevel)

      # Attempt detection if there are ELI units
      if detectorELI.len > 0:
        let detectorUnit = ELIUnit(
          eliLevels: detectorELI,
          isStarbase: hasStarbase
        )

        # Roll detection with turn RNG
        var rng = initRand(state.turn xor scoutId.hash())
        let detectionResult = detectSpyScout(detectorUnit, scout.eliLevel, rng)

        if detectionResult.detected:
          logInfo(LogCategory.lcGeneral,
            &"Spy scout {scoutId} detected by {rivalHouse} " &
            &"(ELI {detectionResult.effectiveELI} vs {scout.eliLevel}, " &
            &"rolled {detectionResult.roll} > {detectionResult.threshold})")
          wasDetected = true
          break

    if wasDetected:
      # Scout is destroyed, don't add to surviving scouts
      logInfo(LogCategory.lcGeneral, &"Spy scout {scoutId} destroyed")
    else:
      # Scout survives and gathers intelligence
      survivingScouts[scoutId] = scout

      # Generate intelligence reports based on mission type
      # Enhanced scout intelligence system automatically:
      # - Generates detailed scout encounter reports
      # - Tracks fleet movement history over time
      # - Tracks construction activity over multiple visits
      case scout.mission
      of SpyMissionType.SpyOnPlanet:
        logDebug(LogCategory.lcGeneral, &"Spy scout {scoutId} gathering planetary intelligence at system-{scoutLocation}")
        scout_intel.processScoutIntelligence(state, scoutId, scout.owner, scoutLocation)
        logDebug(LogCategory.lcGeneral, &"Enhanced colony intel: population, industry, defenses, construction tracking")

      of SpyMissionType.HackStarbase:
        logDebug(LogCategory.lcGeneral, &"Spy scout {scoutId} hacking starbase at system-{scoutLocation}")
        let report = intel_gen.generateStarbaseIntelReport(state, scout.owner, scoutLocation, intel_types.IntelQuality.Spy)
        if report.isSome:
          var house = state.houses[scout.owner]
          house.intelligence.addStarbaseReport(report.get())
          state.houses[scout.owner] = house
          logDebug(LogCategory.lcGeneral,
            &"Intel: Treasury {report.get().treasuryBalance.get(0)} PP, Tax rate {report.get().taxRate.get(0.0)}%")

      of SpyMissionType.SpyOnSystem:
        logDebug(LogCategory.lcGeneral, &"Spy scout {scoutId} conducting system surveillance at {scoutLocation}")
        scout_intel.processScoutIntelligence(state, scoutId, scout.owner, scoutLocation)
        logDebug(LogCategory.lcGeneral, &"Enhanced system intel: fleet composition, movement patterns, cargo details")

  # Update spy scouts in game state (remove detected ones)
  state.spyScouts = survivingScouts

  # Process starbase surveillance (continuous monitoring every turn)
  logDebug(LogCategory.lcGeneral, &"Processing starbase surveillance...")
  var survRng = initRand(state.turn + 12345)  # Unique seed for surveillance
  starbase_surveillance.processAllStarbaseSurveillance(state, state.turn, survRng)

  # Convert colonies table to sequence for income phase
  # NOTE: No type conversion needed - gamestate.Colony has all economic fields
  var coloniesSeqIncome: seq[Colony] = @[]
  for systemId, colony in state.colonies:
    coloniesSeqIncome.add(colony)

  # Build house tax policies from House state
  var houseTaxPolicies = initTable[HouseId, econ_types.TaxPolicy]()
  for houseId, house in state.houses:
    houseTaxPolicies[houseId] = house.taxPolicy

  # Build house tech levels (Economic Level = economicLevel field)
  var houseTechLevels = initTable[HouseId, int]()
  for houseId, house in state.houses:
    houseTechLevels[houseId] = house.techTree.levels.economicLevel  # EL = economicLevel (confusing naming)

  # Build house CST tech levels (Construction = constructionTech field)
  var houseCSTTechLevels = initTable[HouseId, int]()
  for houseId, house in state.houses:
    houseCSTTechLevels[houseId] = house.techTree.levels.constructionTech

  # Build house treasuries
  var houseTreasuries = initTable[HouseId, int]()
  for houseId, house in state.houses:
    houseTreasuries[houseId] = house.treasury

  # Call economy engine
  let incomeReport = econ_engine.resolveIncomePhase(
    coloniesSeqIncome,
    houseTaxPolicies,
    houseTechLevels,
    houseCSTTechLevels,
    houseTreasuries
  )

  # Write back modified colonies (population growth was applied in-place)
  # CRITICAL: Colonies were copied to seq, modified via mpairs, must write back to persist
  for colony in coloniesSeqIncome:
    state.colonies[colony.systemId] = colony

  # Apply results back to game state
  for houseId, houseReport in incomeReport.houseReports:
    # CRITICAL: Get house once, modify all fields, write back to persist
    var house = state.houses[houseId]
    house.treasury = houseTreasuries[houseId]
    # Store income report for intelligence gathering (HackStarbase missions)
    house.latestIncomeReport = some(houseReport)
    logInfo(LogCategory.lcEconomy,
      &"{house.name}: +{houseReport.totalNet} PP (Gross: {houseReport.totalGross})")

    # Update colony production fields from income reports
    for colonyReport in houseReport.colonies:
      if colonyReport.colonyId in state.colonies:
        # CRITICAL: Get colony, modify, write back to persist
        var colony = state.colonies[colonyReport.colonyId]
        colony.production = colonyReport.grossOutput
        state.colonies[colonyReport.colonyId] = colony

    # Apply prestige events from economic activities
    for event in houseReport.prestigeEvents:
      prestige_app.applyPrestigeEvent(state, houseId, event)
      let sign = if event.amount > 0: "+" else: ""
      logDebug(LogCategory.lcEconomy,
        &"Prestige: {sign}{event.amount} ({event.description}) → {state.houses[houseId].prestige}")

    # Write back modified house
    state.houses[houseId] = house

    # Apply blockade prestige penalties
    # Per operations.md:6.2.6: "-2 prestige per colony under blockade"
    let blockadePenalty = blockade_engine.calculateBlockadePrestigePenalty(state, houseId)
    if blockadePenalty < 0:
      let blockadedCount = blockade_engine.getBlockadedColonies(state, houseId).len
      let blockadePenaltyEvent = prestige_types.createPrestigeEvent(
        prestige_types.PrestigeSource.BlockadePenalty,
        blockadePenalty,
        &"{blockadedCount} colonies under blockade ({blockadePenalty} prestige per colony)"
      )
      prestige_app.applyPrestigeEvent(state, houseId, blockadePenaltyEvent)
      logWarn(LogCategory.lcEconomy,
        &"Prestige: {blockadePenalty} ({blockadedCount} colonies under blockade) → {state.houses[houseId].prestige}")

  # Process construction completion - decrement turns and complete projects
  # NEW: Process ALL projects in construction queue (not just legacy single project)
  for systemId, colony in state.colonies.mpairs:
    # Process build queue (all projects in parallel)
    var completedProjects: seq[econ_types.ConstructionProject] = @[]
    var remainingProjects: seq[econ_types.ConstructionProject] = @[]

    # DEBUG: Log queue contents
    if colony.constructionQueue.len > 0:
      logDebug(LogCategory.lcEconomy, &"System-{systemId} has {colony.constructionQueue.len} projects in construction queue")
      for project in colony.constructionQueue:
        logDebug(LogCategory.lcEconomy, &"  - {project.itemId}: {project.turnsRemaining} turns remaining")

    for project in colony.constructionQueue.mitems:
      project.turnsRemaining -= 1

      if project.turnsRemaining <= 0:
        completedProjects.add(project)
      else:
        remainingProjects.add(project)

    # =========================================================================
    # SHIP COMMISSIONING PIPELINE
    # =========================================================================
    # Process completed construction projects and commission new units
    #
    # **Commissioning Pipeline for Combat Ships:**
    # 1. Ship construction completes (1 turn per economy.md:5.0)
    # 2. Ship commissioned with current tech levels
    # 3. **Squadron Assignment** (auto-balance strength):
    #    - Escorts try to join existing unassigned capital ship squadrons (balance)
    #    - If no capital squadrons, escorts try to join same-class escort squadrons
    #    - Capital ships always create new squadrons (they're flagships)
    #    - Unjoined escorts create new squadrons
    # 4. **Fleet Assignment** (always enabled):
    #    - Calls autoBalanceSquadronsToFleets() to organize squadrons into fleets
    #    - Balances squadron count across existing stationary Active fleets
    #    - Creates new fleets if no candidate fleets exist
    #
    # **Commissioning Pipeline for Spacelift Ships (ETAC/TT):**
    # 1. Ship commissioned to colony.unassignedSpaceLiftShips
    # 2. Immediately joins first available fleet via auto-assignment
    #
    # **Result:**
    # - Ships end up in fleets, ready for orders (auto-assignment always enabled)
    # - See docs/architecture/fleet-management.md for rationale
    # =========================================================================

    for project in completedProjects:
      if project.turnsRemaining <= 0:
        # Construction complete!
        logDebug(LogCategory.lcEconomy, &"Construction completed at system-{systemId}: {project.itemId}")

        case project.projectType
        of econ_types.ConstructionType.Ship:
          # Commission ship from Spaceport/Shipyard
          let shipClass = parseEnum[ShipClass](project.itemId)
          let techLevel = state.houses[colony.owner].techTree.levels.constructionTech

          # ARCHITECTURE FIX: Check if this is a spacelift ship (NOT a combat squadron)
          let isSpaceLift = shipClass in [ShipClass.ETAC, ShipClass.TroopTransport]

          # ARCHITECTURE FIX: Fighters go to colony.fighterSquadrons, not fleets
          let isFighter = shipClass == ShipClass.Fighter

          logInfo(LogCategory.lcEconomy, &"Commissioning {shipClass}: isFighter={isFighter}, isSpaceLift={isSpaceLift}")

          if isFighter:
            # Path 1: Commission fighter at colony (assets.md:2.4.1)
            # Use turn + timestamp to ensure unique IDs (avoid collisions when fighters loaded onto carriers)
            let fighterSeqNum = state.turn * 100 + colony.fighterSquadrons.len
            let fighterSq = FighterSquadron(
              id: $systemId & "-FS-" & $fighterSeqNum,
              commissionedTurn: state.turn
            )

            colony.fighterSquadrons.add(fighterSq)
            logDebug(LogCategory.lcEconomy, &"Commissioned fighter squadron {fighterSq.id} at {systemId} (Path 1)")

            # Path 2: Auto-load onto carriers at same colony (assets.md:2.4.1)
            # Find carriers at this colony with available hangar space
            for fleetId, fleet in state.fleets.mpairs:
              if fleet.location == systemId and fleet.owner == colony.owner:
                for squadron in fleet.squadrons.mitems:
                  if squadron.flagship.shipClass in [ShipClass.Carrier, ShipClass.SuperCarrier]:
                    # Check hangar capacity (simplified: CV=3, CX=5, ignoring ACO tech for now)
                    let maxCapacity = if squadron.flagship.shipClass == ShipClass.Carrier: 3 else: 5
                    let currentLoad = squadron.embarkedFighters.len

                    if currentLoad < maxCapacity:
                      # Auto-load fighter onto carrier
                      let carrierFighter = CarrierFighter(
                        id: fighterSq.id,
                        commissionedTurn: fighterSq.commissionedTurn
                      )
                      squadron.embarkedFighters.add(carrierFighter)

                      # Remove from colony (transfer ownership)
                      # SAFETY CHECK: Ensure we have fighters to remove
                      let lenBefore = colony.fighterSquadrons.len
                      if lenBefore > 0:
                        let indexToDelete = lenBefore - 1
                        logDebug(LogCategory.lcFleet,
                          &"About to delete fighter at index {indexToDelete} (len={lenBefore})")
                        colony.fighterSquadrons.delete(indexToDelete)
                        logDebug(LogCategory.lcFleet,
                          &"Auto-loaded {fighterSq.id} onto carrier {fleetId} (Path 2, {currentLoad + 1}/{maxCapacity} capacity)")
                        logDebug(LogCategory.lcFleet,
                          &"Deleted fighter from colony (len before: {lenBefore}, after: {colony.fighterSquadrons.len})")
                      else:
                        logError(LogCategory.lcFleet,
                          &"ERROR: Tried to auto-load {fighterSq.id} but colony.fighterSquadrons is empty!")
                      # Exit both loops after successful auto-load
                      break
                  if squadron.embarkedFighters.len > 0:  # Fighter was loaded
                    break
          elif isSpaceLift:
            # Create SpaceLiftShip (individual unit, not squadron)
            let shipId = colony.owner & "_" & $shipClass & "_" & $systemId & "_" & $state.turn
            var spaceLiftShip = newSpaceLiftShip(shipId, shipClass, colony.owner, systemId)

            # Auto-load PTU onto ETAC at commissioning with extraction cost
            # Larger colonies spare PTUs more cheaply due to exponential PU→PTU relationship
            # Formula: extraction_cost = 1.0 / (1.0 + 0.00657 * pu)
            # Examples: 100 PU colony loses 0.60 PU, 1000 PU colony loses only 0.13 PU
            # Note: Space Guild transfers will have ADDITIONAL costs beyond just extraction
            # See docs/specs/economy.md:15-27 for PTU mechanics
            if shipClass == ShipClass.ETAC and colony.population > 1:
              # Calculate extraction cost (PU lost from colony to create 1 PTU)
              let extractionCost = 1.0 / (1.0 + 0.00657 * colony.population.float)

              # Apply cost by reducing colony population (affects future GCO/production)
              let newPopulation = colony.population.float - extractionCost
              colony.population = max(1, newPopulation.int)

              # Load PTU onto ETAC
              spaceLiftShip.cargo.cargoType = CargoType.Colonists
              spaceLiftShip.cargo.quantity = 1
              logInfo(LogCategory.lcEconomy, &"Loaded 1 PTU onto {shipId} (extraction: {extractionCost:.2f} PU from {systemId})")

            colony.unassignedSpaceLiftShips.add(spaceLiftShip)
            logInfo(LogCategory.lcEconomy, &"Commissioned {shipClass} spacelift ship at {systemId}")

            # Auto-assign to fleets (create new fleet if needed)
            if colony.unassignedSpaceLiftShips.len > 0:
              # Get the ship from unassigned pool (use this reference, not the local variable)
              let shipToAssign = colony.unassignedSpaceLiftShips[colony.unassignedSpaceLiftShips.len - 1]

              # Find or create fleet at this location
              var targetFleetId = ""
              for fleetId, fleet in state.fleets:
                if fleet.location == systemId and fleet.owner == colony.owner:
                  targetFleetId = fleetId
                  break

              if targetFleetId == "":
                # Create new fleet for spacelift ship
                targetFleetId = $colony.owner & "_fleet" & $(state.fleets.len + 1)
                state.fleets[targetFleetId] = Fleet(
                  id: targetFleetId,
                  owner: colony.owner,
                  location: systemId,
                  squadrons: @[],
                  spaceLiftShips: @[shipToAssign],
                  status: FleetStatus.Active,
                  autoBalanceSquadrons: true
                )
                let createdFleet = state.fleets[targetFleetId]
                logInfo(LogCategory.lcFleet, &"Commissioned {shipClass} in new fleet {targetFleetId} with {createdFleet.spaceLiftShips.len} spacelift ships")
              else:
                # Add to existing fleet
                state.fleets[targetFleetId].spaceLiftShips.add(shipToAssign)
                logInfo(LogCategory.lcFleet, &"Commissioned {shipClass} in fleet {targetFleetId}")

              # Remove from unassigned pool (it's now in fleet)
              # SAFETY CHECK: Ensure we have ships to remove
              if colony.unassignedSpaceLiftShips.len > 0:
                colony.unassignedSpaceLiftShips.delete(colony.unassignedSpaceLiftShips.len - 1)
              else:
                logError(LogCategory.lcFleet,
                  &"ERROR: Tried to remove spacelift ship but colony.unassignedSpaceLiftShips is empty!")

              # WARN if ETAC assigned without PTU (potential colonization failure)
              if shipClass == ShipClass.ETAC and
                 (spaceLiftShip.cargo.cargoType != CargoType.Colonists or spaceLiftShip.cargo.quantity == 0):
                logWarn(LogCategory.lcFleet, &"Empty ETAC {shipId} assigned to fleet {targetFleetId} - colonization will fail!")

              logInfo(LogCategory.lcFleet, &"Auto-assigned {shipClass} to fleet {targetFleetId}")

          else:
            # Combat ship - create squadron as normal
            let newShip = newEnhancedShip(shipClass, techLevel)

            # SQUADRON FORMATION LOGIC (Step 3 of commissioning pipeline)
            # Goal: Create balanced, combat-ready squadrons before fleet assignment
            #
            # Tactical Doctrine:
            # - **Escorts** (small/fast ships): Join existing squadrons as supporting units
            # - **Capital ships** (large/slow): Always become squadron flagships
            #
            # This creates combined-arms squadrons (e.g., Battleship + 3 Destroyers)
            # which have better tactical capabilities than single-ship squadrons
            var addedToSquadron = false

            # Classify ship as escort or capital based on hull class and role
            # Escorts: Small/fast ships (SC, FG, DD, CT, CL) - support role, expendable
            # Capitals: Large/powerful ships (CA+, BB+, CV+) - flagship role, valuable
            let isEscort = shipClass in [
              ShipClass.Scout, ShipClass.Frigate, ShipClass.Destroyer,
              ShipClass.Corvette, ShipClass.LightCruiser
            ]

            # ESCORT ASSIGNMENT: Join existing squadrons to create balanced battle groups
            if isEscort:
              # Try to join unassigned capital ship squadrons first
              for squadron in colony.unassignedSquadrons.mitems:
                let flagshipIsCapital = squadron.flagship.shipClass in [
                  ShipClass.Battleship, ShipClass.Dreadnought, ShipClass.SuperDreadnought,
                  ShipClass.Carrier, ShipClass.SuperCarrier, ShipClass.Battlecruiser,
                  ShipClass.HeavyCruiser, ShipClass.Cruiser
                ]
                if flagshipIsCapital and squadron.canAddShip(newShip):
                  squadron.ships.add(newShip)
                  logDebug(LogCategory.lcEconomy, &"Commissioned {shipClass} and added to unassigned capital squadron {squadron.id}")
                  addedToSquadron = true
                  break

              # If no capital squadrons, try joining escort squadrons
              if not addedToSquadron:
                for squadron in colony.unassignedSquadrons.mitems:
                  if squadron.flagship.shipClass == shipClass and squadron.canAddShip(newShip):
                    squadron.ships.add(newShip)
                    logDebug(LogCategory.lcEconomy, &"Commissioned {shipClass} and added to unassigned escort squadron {squadron.id}")
                    addedToSquadron = true
                    break

            # Capital ships and unassigned escorts create new squadrons at colony
            if not addedToSquadron:
              let squadronId = colony.owner & "_sq_" & $systemId & "_" & $state.turn & "_" & project.itemId
              let newSquadron = newSquadron(newShip, squadronId, colony.owner, systemId)
              colony.unassignedSquadrons.add(newSquadron)
              logDebug(LogCategory.lcEconomy, &"Commissioned {shipClass} into new unassigned squadron at {systemId}")

            # Fleet Organization: Automatically organize newly-commissioned squadrons into fleets
            # This completes the economic production pipeline: Treasury → Construction → Commissioning → Fleet
            # Without this step, units remain in unassignedSquadrons and cannot execute operational orders
            # (e.g., scouts cannot perform espionage, carriers cannot deploy to defensive positions)
            if colony.unassignedSquadrons.len > 0:
              autoBalanceSquadronsToFleets(state, colony, systemId, orders)

        of econ_types.ConstructionType.Building:
          # Add building to colony
          if project.itemId == "Spaceport":
            # Calculate CST-scaled dock capacity
            let cstLevel = state.houses[colony.owner].techTree.levels.constructionTech
            let baseDocks = globalConstructionConfig.construction.spaceport_docks
            let cstMultiplier = 1.0 + float(cstLevel - 1) * globalConstructionConfig.modifiers.construction_capacity_increase_per_level
            let scaledDocks = int(float(baseDocks) * cstMultiplier)

            let spaceportId = colony.owner & "_spaceport_" & $systemId & "_" & $state.turn
            let spaceport = Spaceport(
              id: spaceportId,
              commissionedTurn: state.turn,
              baseDocks: globalFacilitiesConfig.spaceport.docks,
              effectiveDocks: res_effects.calculateEffectiveDocks(globalFacilitiesConfig.spaceport.docks, cstLevel),
              constructionQueue: @[],
              activeConstructions: @[]
            )
            colony.spaceports.add(spaceport)
            logDebug(LogCategory.lcEconomy, &"Added Spaceport to system-{systemId} ({scaledDocks} docks, CST {cstLevel})")

          elif project.itemId == "Shipyard":
            # Calculate CST-scaled dock capacity
            let cstLevel = state.houses[colony.owner].techTree.levels.constructionTech
            let baseDocks = globalConstructionConfig.construction.shipyard_docks
            let cstMultiplier = 1.0 + float(cstLevel - 1) * globalConstructionConfig.modifiers.construction_capacity_increase_per_level
            let scaledDocks = int(float(baseDocks) * cstMultiplier)

            let shipyardId = colony.owner & "_shipyard_" & $systemId & "_" & $state.turn
            let shipyard = Shipyard(
              id: shipyardId,
              commissionedTurn: state.turn,
              baseDocks: globalFacilitiesConfig.shipyard.docks,
              effectiveDocks: res_effects.calculateEffectiveDocks(globalFacilitiesConfig.shipyard.docks, cstLevel),
              isCrippled: false,
              constructionQueue: @[],
              activeConstructions: @[]
            )
            colony.shipyards.add(shipyard)
            logDebug(LogCategory.lcEconomy, &"Added Shipyard to system-{systemId} ({scaledDocks} docks, CST {cstLevel})")

          elif project.itemId == "GroundBattery":
            colony.groundBatteries += 1
            logDebug(LogCategory.lcEconomy, &"Added Ground Battery to system-{systemId}")

          elif project.itemId == "PlanetaryShield":
            # Set planetary shield level based on house's SLD tech
            colony.planetaryShieldLevel = state.houses[colony.owner].techTree.levels.shieldTech
            logDebug(LogCategory.lcEconomy, &"Added Planetary Shield (SLD{colony.planetaryShieldLevel}) to system-{systemId}")

        of econ_types.ConstructionType.Industrial:
          # IU investment - industrial capacity was added when project started
          # Just log completion
          logDebug(LogCategory.lcEconomy, &"Industrial expansion completed at system-{systemId}")

        of econ_types.ConstructionType.Infrastructure:
          # Infrastructure was already added during creation
          # Just log completion
          logDebug(LogCategory.lcEconomy, &"Infrastructure expansion completed at system-{systemId}")

    # Update construction queue with remaining (in-progress) projects
    colony.constructionQueue = remainingProjects

    # =========================================================================
    # REPAIR QUEUE PROCESSING
    # =========================================================================
    # Process repair queue (all repairs in parallel, similar to construction)
    # Ships repair for 1 turn at 25% of build cost
    # Repaired ships recommission through standard squadron pipeline
    #
    # **Repair Priority:**
    # - Construction projects (priority=0) take precedence over repairs
    # - Ship repairs (priority=1) before starbase repairs (priority=2)
    # - Dock capacity shared between construction and repairs
    # =========================================================================

    var completedRepairs: seq[econ_types.RepairProject] = @[]
    var remainingRepairs: seq[econ_types.RepairProject] = @[]

    if colony.repairQueue.len > 0:
      logDebug(LogCategory.lcEconomy, &"System-{systemId} has {colony.repairQueue.len} repairs in queue")

    for repair in colony.repairQueue.mitems:
      repair.turnsRemaining -= 1

      if repair.turnsRemaining <= 0:
        completedRepairs.add(repair)
      else:
        remainingRepairs.add(repair)

    # Commission repaired ships through standard pipeline
    for repair in completedRepairs:
      case repair.targetType
      of econ_types.RepairTargetType.Ship:
        if repair.shipClass.isSome:
          let shipClass = repair.shipClass.get()
          logInfo(LogCategory.lcEconomy, &"Repair completed at system-{systemId}: {shipClass}")

          # Commission repaired ship as new ship (same as construction)
          let isSpaceLift = shipClass in [ShipClass.ETAC, ShipClass.TroopTransport]

          if isSpaceLift:
            # Spacelift ships commission to unassigned list (use newSpaceLiftShip for config-based capacity)
            let spaceLiftShip = newSpaceLiftShip(
              id = "", # Will be assigned during fleet integration
              shipClass = shipClass,
              owner = colony.owner,
              location = colony.systemId
            )
            colony.unassignedSpaceLiftShips.add(spaceLiftShip)
            logDebug(LogCategory.lcEconomy, &"Recommissioned {shipClass} as spacelift ship (repaired)")
          else:
            # Combat ships commission through squadron pipeline
            let stats = getShipStats(shipClass)
            let ship = EnhancedShip(
              shipClass: shipClass,
              shipType: ShipType.Military,
              stats: stats,
              isCrippled: false,  # Repaired!
              name: $shipClass
            )

            # Squadron assignment logic (same as construction)
            if shipClass in {ShipClass.Battleship, ShipClass.SuperDreadnought,
                            ShipClass.Dreadnought, ShipClass.Carrier,
                            ShipClass.SuperCarrier, ShipClass.HeavyCruiser,
                            ShipClass.Cruiser}:
              # Capital ships become flagships
              let newSquadron = newSquadron(
                flagship = ship,
                id = "SQ-" & $systemId & "-" & $(colony.unassignedSquadrons.len + 1),
                owner = colony.owner,
                location = systemId
              )
              colony.unassignedSquadrons.add(newSquadron)
              logDebug(LogCategory.lcEconomy, &"Recommissioned {shipClass} as new squadron flagship (repaired)")
            else:
              # Escorts try to join existing squadrons
              var joined = false

              # Try to join existing capital ship squadrons first
              for sq in colony.unassignedSquadrons.mitems:
                let flagshipClass = sq.flagship.shipClass
                if flagshipClass in {ShipClass.Battleship, ShipClass.SuperDreadnought,
                                    ShipClass.Dreadnought, ShipClass.Carrier,
                                    ShipClass.SuperCarrier, ShipClass.HeavyCruiser,
                                    ShipClass.Cruiser}:
                  if sq.canAddShip(ship):
                    discard sq.addShip(ship)
                    joined = true
                    logDebug(LogCategory.lcEconomy, &"Recommissioned {shipClass} joined capital squadron (repaired)")
                    break

              # If not joined, try same-class escort squadrons
              if not joined:
                for sq in colony.unassignedSquadrons.mitems:
                  if sq.flagship.shipClass == shipClass:
                    if sq.canAddShip(ship):
                      discard sq.addShip(ship)
                      joined = true
                      logDebug(LogCategory.lcEconomy, &"Recommissioned {shipClass} joined escort squadron (repaired)")
                      break

              # If still not joined, create new escort squadron
              if not joined:
                let newSquadron = newSquadron(
                  flagship = ship,
                  id = "SQ-" & $systemId & "-" & $(colony.unassignedSquadrons.len + 1),
                  owner = colony.owner,
                  location = systemId
                )
                colony.unassignedSquadrons.add(newSquadron)
                logDebug(LogCategory.lcEconomy, &"Recommissioned {shipClass} as new escort squadron (repaired)")

      of econ_types.RepairTargetType.Starbase:
        # Repair starbase at colony
        if repair.starbaseIdx.isSome:
          let idx = repair.starbaseIdx.get()
          if idx >= 0 and idx < colony.starbases.len:
            colony.starbases[idx].isCrippled = false
            logInfo(LogCategory.lcEconomy, &"Repair completed at system-{systemId}: Starbase-{idx}")

    # Update repair queue
    colony.repairQueue = remainingRepairs

    # LEGACY SUPPORT: Update underConstruction field for backwards compatibility
    # Keep the first in-progress project as the "active" one
    if remainingProjects.len > 0:
      colony.underConstruction = some(remainingProjects[0])
    else:
      colony.underConstruction = none(econ_types.ConstructionProject)

    # CRITICAL: Write back colony to persist ALL modifications in this loop iteration
    # Even with mpairs, nested seq/field modifications require explicit write-back:
    # - fighterSquadrons (commissioned fighters)
    # - unassignedSpaceLiftShips (commissioned transports/ETACs)
    # - unassignedSquadrons (repaired ships forming squadrons)
    # - population (ETAC PTU extraction cost)
    # - constructionQueue (completed/remaining projects)
    # - repairQueue (completed/remaining repairs)
    # - starbases (repaired starbases)
    # - underConstruction (legacy field)
    state.colonies[systemId] = colony

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

## Phase 3: Command


proc autoBalanceSquadronsToFleets*(state: var GameState, colony: var gamestate.Colony, systemId: SystemId, orders: Table[HouseId, OrderPacket]) =
  ## Auto-assign unassigned squadrons to fleets at colony, balancing squadron count
  ##
  ## **Purpose:** Automatically organize newly-commissioned ships into operational fleets
  ## during the Construction & Commissioning phase of economy resolution.
  ##
  ## **Behavior:**
  ## 1. Looks for Active stationary fleets at colony (Hold orders or no orders)
  ## 2. If candidate fleets exist: distributes unassigned squadrons evenly across them
  ## 3. If NO candidate fleets exist: creates new single-squadron fleets for each unassigned squadron
  ##
  ## **Fleet Status Filtering:**
  ## - Only considers `FleetStatus.Active` fleets for auto-assignment
  ## - Excludes `FleetStatus.Reserve` (50% maintenance, reduced combat effectiveness)
  ## - Excludes `FleetStatus.Mothballed` (0% maintenance, offline storage)
  ##
  ## **Why This Matters:**
  ## This function is critical for AI operational effectiveness. Without it, newly-built
  ## units (especially scouts) remain in `colony.unassignedSquadrons` indefinitely and
  ## never execute their intended missions. For example, scouts cannot perform espionage
  ## missions unless they are organized into fleets.
  ##
  ## **Architecture Note:**
  ## This function lives in economy_resolution.nim because fleet organization from
  ## newly-commissioned ships is part of the industrial → military transition, not
  ## tactical fleet operations. It represents the final step in the economic production
  ## pipeline: Treasury → Construction → Commissioning → Fleet Organization.
  if colony.unassignedSquadrons.len == 0:
    return

  # Get all fleets at this colony owned by same house
  var candidateFleets: seq[FleetId] = @[]
  for fleetId, fleet in state.fleets:
    if fleet.owner == colony.owner and fleet.location == systemId:
      # Only consider Active fleets (exclude Reserve and Mothballed)
      if fleet.status != FleetStatus.Active:
        continue

      # Check if fleet has stationary orders (Hold, Guard, Patrol, or no orders)
      # These orders keep fleets at/near the colony and can accept reinforcements
      var isStationary = true

      # Check if fleet has active orders
      if colony.owner in orders:
        for order in orders[colony.owner].fleetOrders:
          if order.fleetId == fleetId:
            # Fleet is stationary if: Hold, GuardStarbase, GuardPlanet, or Patrol (at same system)
            case order.orderType
            of FleetOrderType.Hold, FleetOrderType.GuardStarbase, FleetOrderType.GuardPlanet:
              isStationary = true
            of FleetOrderType.Patrol:
              # Patrol at same system is stationary, patrol to other system is movement
              isStationary = (order.targetSystem.isNone or order.targetSystem.get() == systemId)
            else:
              isStationary = false
            break

      # Also check standing orders - fleets with movement-based standing orders should not receive squadrons
      # Movement-based: PatrolRoute, AutoColonize, AutoReinforce, AutoRepair (when seeking shipyard)
      # Stationary: DefendSystem, GuardColony, AutoEvade, BlockadeTarget (at target)
      if isStationary and fleetId in state.standingOrders:
        let standingOrder = state.standingOrders[fleetId]
        case standingOrder.orderType
        of StandingOrderType.PatrolRoute, StandingOrderType.AutoColonize, StandingOrderType.AutoReinforce:
          # These always involve movement between systems
          isStationary = false
        of StandingOrderType.AutoRepair:
          # AutoRepair only moves when damaged, otherwise stationary
          # For simplicity, treat as non-stationary (don't want to add squadrons if fleet might leave for repairs)
          isStationary = false
        else:
          # DefendSystem, GuardColony, AutoEvade, BlockadeTarget are stationary (at/defending a system)
          # None, or any future order types default to stationary
          discard

      if isStationary:
        candidateFleets.add(fleetId)

  if candidateFleets.len == 0:
    # No existing stationary fleets - create ONE consolidated fleet for ALL orphan squadrons
    if colony.unassignedSquadrons.len > 0:
      let newFleetId = colony.owner & "_fleet_" & $systemId & "_" & $state.turn
      let allSquadrons = colony.unassignedSquadrons  # Collect all orphan squadrons
      state.fleets[newFleetId] = Fleet(
        id: newFleetId,
        owner: colony.owner,
        location: systemId,
        squadrons: allSquadrons,  # All squadrons in one fleet
        spaceLiftShips: @[],
        status: FleetStatus.Active,
        autoBalanceSquadrons: true
      )
      colony.unassignedSquadrons = @[]  # Clear the list
      logDebug(LogCategory.lcFleet, &"Auto-created consolidated fleet {newFleetId} with {allSquadrons.len} squadrons")
    return

  # Calculate target squadron count per fleet (balanced distribution)
  let totalSquadrons = colony.unassignedSquadrons.len +
                        candidateFleets.mapIt(state.fleets[it].squadrons.len).foldl(a + b, 0)
  let targetPerFleet = totalSquadrons div candidateFleets.len

  # Assign squadrons to fleets to reach target count
  for fleetId in candidateFleets:
    var fleet = state.fleets[fleetId]
    while fleet.squadrons.len < targetPerFleet and colony.unassignedSquadrons.len > 0:
      let squadron = colony.unassignedSquadrons[0]
      fleet.squadrons.add(squadron)
      colony.unassignedSquadrons.delete(0)
    state.fleets[fleetId] = fleet

