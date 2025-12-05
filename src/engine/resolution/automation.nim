## Automation System - Automatic colony and fleet management
##
## This module handles all automatic management actions that occur after commissioning
## in the Command Phase. These are quality-of-life features that reduce micromanagement
## while giving players control via per-colony toggles.
##
## **Design Rationale:**
## Automation happens immediately after commissioning to take advantage of freed resources:
## - Auto-repair: Uses newly-freed dock capacity from commissioned ships
## - Auto-squadron assignment: Organizes newly-commissioned ships into operational fleets
##
## **Phase Ordering (Updated 2025-12-04):**
## ```
## Command Phase:
##   1. Commission completed projects (frees dock capacity)
##   2. Auto-load fighters to carriers (if enabled) ← commissioning.nim
##   3. Auto-repair submission (if enabled) ← THIS MODULE
##   4. Auto-squadron balancing (always on) ← THIS MODULE
##   5. Process new build orders (uses freed capacity)
##   6. ... rest of Command Phase ...
## ```
##
## **Handles:**
## - Auto-repair submission: Submit crippled ships to repair queues
## - Auto-squadron balancing: Organize unassigned squadrons into fleets
##
## **Per-Colony Toggles:**
## - `colony.autoRepairEnabled` (default: false) - Submit repairs automatically
## - `colony.autoLoadingEnabled` (default: true) - Load fighters to carriers (in commissioning.nim)
## - Squadron balancing is always enabled (no toggle)
##
## **Data-Oriented Design:**
## - Pure capacity checks (no side effects)
## - Explicit mutations (clear state changes)
## - Batch processing (process all colonies together)

import std/[tables, options, strformat, sequtils]
import ../../common/types/[core, units]
import ../gamestate, ../fleet, ../squadron, ../logger, ../orders, ../order_types
import ../economy/repair_queue
import ../economy/capacity/carrier_hangar
import ./types as res_types

proc autoLoadFightersToCarriers*(state: var GameState, colony: var Colony,
                                   systemId: SystemId, orders: Table[HouseId, OrderPacket]) =
  ## Auto-load colony fighters onto available carriers at system
  ## Only runs if colony.autoLoadingEnabled == true
  ##
  ## **Behavior:**
  ## 1. Find Active carriers at colony with available hangar capacity
  ## 2. Only consider stationary carriers (Hold/Guard orders or no orders)
  ## 3. Load fighters until carrier capacity reached
  ## 4. Respect carrier hangar limits (based on ACO tech level)
  ##
  ## **Capacity Checking:**
  ## - Uses carrier_hangar.canLoadFighters() to validate space
  ## - CV: 3/4/5 fighters at ACO I/II/III
  ## - CX: 5/6/8 fighters at ACO I/II/III
  ##
  ## **Edge Cases:**
  ## - Carrier full: Skip to next carrier
  ## - All carriers full: Fighters remain at colony
  ## - No carriers: Fighters remain at colony
  ##
  ## **Called From:** processColonyAutomation() after commissioning

  if not colony.autoLoadingEnabled:
    logDebug(LogCategory.lcFleet, &"Auto-loading disabled at {systemId}")
    return

  if colony.fighterSquadrons.len == 0:
    return

  # Get house's ACO tech level for capacity
  let house = state.houses.getOrDefault(colony.owner)
  let acoLevel = house.techTree.levels.advancedCarrierOps

  # Find Active carriers at colony with available capacity
  var candidateCarriers: seq[tuple[fleetId: FleetId, squadronIdx: int]] = @[]

  for fleetId, fleet in state.fleets:
    if fleet.owner == colony.owner and fleet.location == systemId:
      if fleet.status != FleetStatus.Active:
        continue

      # Check if fleet is stationary (Hold/Guard or no orders)
      var isStationary = true
      if colony.owner in orders:
        for order in orders[colony.owner].fleetOrders:
          if order.fleetId == fleetId:
            # Moving orders: skip this fleet
            if order.orderType in [FleetOrderType.Move, FleetOrderType.Colonize,
                                   FleetOrderType.Patrol, FleetOrderType.SeekHome]:
              isStationary = false
            break

      if not isStationary:
        continue

      # Find carriers with available hangar space
      for idx, squadron in fleet.squadrons:
        if carrier_hangar.isCarrier(squadron.flagship.shipClass):
          let availableSpace = carrier_hangar.getAvailableHangarSpace(state, fleetId, idx)
          if availableSpace > 0:
            candidateCarriers.add((fleetId, idx))
            logDebug(LogCategory.lcFleet,
              &"Found carrier {squadron.id} at {systemId} with {availableSpace} hangar space")

  if candidateCarriers.len == 0:
    logDebug(LogCategory.lcFleet, &"No available carriers at {systemId} for auto-loading")
    return

  # Load fighters onto carriers
  var loadedCount = 0
  for (fleetId, squadronIdx) in candidateCarriers:
    if colony.fighterSquadrons.len == 0:
      break

    var fleet = state.fleets[fleetId]
    var squadron = fleet.squadrons[squadronIdx]

    # Load fighters until carrier full
    while carrier_hangar.canLoadFighters(state, fleetId, squadronIdx, 1) and
          colony.fighterSquadrons.len > 0:
      let fighter = colony.fighterSquadrons[0]
      colony.fighterSquadrons.delete(0)

      squadron.embarkedFighters.add(CarrierFighter(
        id: fighter.id,
        commissionedTurn: fighter.commissionedTurn
      ))

      loadedCount += 1
      # Update the squadron in the fleet
      fleet.squadrons[squadronIdx] = squadron

    # Write fleet back to state
    state.fleets[fleetId] = fleet

  if loadedCount > 0:
    logInfo(LogCategory.lcFleet, &"Auto-loaded {loadedCount} fighters at {systemId}")
  else:
    logDebug(LogCategory.lcFleet, &"No fighters loaded at {systemId} (carriers at capacity)")

proc autoSubmitRepairs*(state: var GameState, systemId: SystemId) =
  ## Automatically submit repair requests for crippled ships at colony
  ## Only runs if colony.autoRepairEnabled == true
  ##
  ## **Behavior:**
  ## - Scans all fleets at colony for crippled ships
  ## - Submits repair orders to shipyard repair queue
  ## - Respects shipyard dock capacity (10 docks per shipyard)
  ## - Repair queue is FIFO (first-in, first-out)
  ##
  ## **Requirements:**
  ## - Colony must have operational shipyards (spaceports cannot repair)
  ## - Ships must be crippled (isCrippled == true)
  ## - Shipyard must have available dock capacity
  ##
  ## **Called From:** resolveCommandPhase() after commissioning
  ## **Called After:** Commissioning (which frees dock capacity)
  ## **Called Before:** New build orders (repair queue established first)

  if systemId notin state.colonies:
    return

  let colony = state.colonies[systemId]

  if not colony.autoRepairEnabled:
    logDebug(LogCategory.lcEconomy, &"Auto-repair disabled at {systemId}")
    return

  # Delegate to repair_queue module for actual submission
  # This maintains separation of concerns - automation decides WHEN, repair_queue decides HOW
  repair_queue.submitAutomaticRepairs(state, systemId)

proc autoBalanceSquadronsToFleets*(state: var GameState, colony: var Colony,
                                     systemId: SystemId, orders: Table[HouseId, OrderPacket]) =
  ## Auto-assign unassigned squadrons to fleets at colony, balancing squadron count
  ##
  ## **Purpose:** Automatically organize newly-commissioned ships into operational fleets.
  ## This happens after commissioning creates unassigned squadrons.
  ##
  ## **Behavior:**
  ## 1. Looks for Active stationary fleets at colony (Hold/Guard orders or no orders)
  ## 2. If candidate fleets exist: distributes unassigned squadrons evenly across them
  ## 3. If NO candidate fleets exist: creates new single-squadron fleets for each
  ##
  ## **Fleet Selection:**
  ## - Must be Active status (excludes Reserve, Mothballed)
  ## - Must be stationary: Hold orders, GuardPlanet orders, GuardStarbase orders, or no orders
  ## - Excludes fleets with movement orders (Move/Colonize/Patrol/SeekHome)
  ## - Excludes fleets with movement-based standing orders (PatrolRoute/AutoColonize/AutoReinforce/AutoRepair/BlockadeTarget)
  ##
  ## **Distribution Algorithm:**
  ## - Calculates target squadron count per fleet: (total squadrons) / (fleet count)
  ## - Distributes unassigned squadrons to reach target count
  ## - Balanced distribution ensures no fleet is overloaded
  ##
  ## **Edge Cases:**
  ## - No candidate fleets: Creates new fleet for each squadron
  ## - Uneven distribution: Some fleets may have +1 squadron
  ##
  ## **Called From:** resolveCommandPhase() after commissioning and auto-repair
  ## **Always Enabled:** No per-colony toggle (essential for operational readiness)

  if colony.unassignedSquadrons.len == 0:
    return

  # Find Active stationary fleets at this colony
  var candidateFleets: seq[FleetId] = @[]

  for fleetId, fleet in state.fleets:
    if fleet.owner == colony.owner and fleet.location == systemId:
      if fleet.status != FleetStatus.Active:
        continue

      # Check if fleet is stationary (Hold/Guard or no orders)
      var isStationary = true

      # Check fleet orders (immediate movement orders)
      if colony.owner in orders:
        for order in orders[colony.owner].fleetOrders:
          if order.fleetId == fleetId:
            # Moving orders: skip this fleet
            if order.orderType in [FleetOrderType.Move, FleetOrderType.Colonize,
                                   FleetOrderType.Patrol, FleetOrderType.SeekHome]:
              isStationary = false
            break

      # Check standing orders (persistent movement behaviors)
      if fleetId in state.standingOrders:
        let standingOrder = state.standingOrders[fleetId]
        # Movement-based standing orders: skip this fleet
        if standingOrder.orderType in [StandingOrderType.PatrolRoute,
                                       StandingOrderType.AutoColonize,
                                       StandingOrderType.AutoReinforce,
                                       StandingOrderType.AutoRepair,
                                       StandingOrderType.BlockadeTarget]:
          isStationary = false

      if isStationary:
        candidateFleets.add(fleetId)

  # Case 1: No candidate fleets - create new fleet for each squadron
  if candidateFleets.len == 0:
    logDebug(LogCategory.lcFleet, &"No stationary fleets at {systemId}, creating new fleets")

    for squadron in colony.unassignedSquadrons:
      let newFleetId = $colony.owner & "_fleet_" & $systemId & "_" & $state.fleets.len
      state.fleets[newFleetId] = Fleet(
        id: newFleetId,
        owner: colony.owner,
        location: systemId,
        squadrons: @[squadron],
        spaceLiftShips: @[],
        status: FleetStatus.Active,
        autoBalanceSquadrons: true
      )
      logInfo(LogCategory.lcFleet, &"Created fleet {newFleetId} with squadron {squadron.id}")

    colony.unassignedSquadrons = @[]
    return

  # Case 2: Distribute squadrons evenly across candidate fleets
  let totalSquadrons = colony.unassignedSquadrons.len +
                        candidateFleets.mapIt(state.fleets[it].squadrons.len).foldl(a + b, 0)
  let targetPerFleet = totalSquadrons div candidateFleets.len

  logDebug(LogCategory.lcFleet,
    &"Balancing {colony.unassignedSquadrons.len} squadrons across {candidateFleets.len} fleets " &
    &"(target: {targetPerFleet} per fleet)")

  # Assign squadrons to fleets to reach target count
  for fleetId in candidateFleets:
    var fleet = state.fleets[fleetId]
    while fleet.squadrons.len < targetPerFleet and colony.unassignedSquadrons.len > 0:
      let squadron = colony.unassignedSquadrons[0]
      fleet.squadrons.add(squadron)
      colony.unassignedSquadrons.delete(0)
      logDebug(LogCategory.lcFleet, &"Assigned squadron {squadron.id} to fleet {fleetId}")
    state.fleets[fleetId] = fleet

  if colony.unassignedSquadrons.len > 0:
    logDebug(LogCategory.lcFleet,
      &"{colony.unassignedSquadrons.len} squadrons remain unassigned at {systemId}")

proc processColonyAutomation*(state: var GameState, orders: Table[HouseId, OrderPacket]) =
  ## Process all colony automation in batch
  ## Called once per turn in Command Phase after commissioning
  ##
  ## **Automation Steps:**
  ## 1. Auto-load fighters to carriers (per-colony toggle)
  ## 2. Auto-repair submission (per-colony toggle)
  ## 3. Auto-squadron balancing (always enabled)
  ##
  ## **Batch Processing:**
  ## - Processes all colonies in single pass
  ## - Efficient: single iteration over colonies
  ## - Clear ordering: fighters → repairs → squadrons
  ##
  ## **Called From:** resolveCommandPhase() in resolve.nim

  logDebug(LogCategory.lcEconomy, "=== Colony Automation Phase ===")

  # Step 1: Auto-load fighters to carriers (respects per-colony toggle)
  for systemId, colony in state.colonies.mpairs:
    if colony.autoLoadingEnabled and colony.fighterSquadrons.len > 0:
      autoLoadFightersToCarriers(state, colony, systemId, orders)

  # Step 2: Auto-repair submission (respects per-colony toggle)
  for systemId, colony in state.colonies:
    if colony.autoRepairEnabled:
      autoSubmitRepairs(state, systemId)

  # Step 3: Auto-squadron balancing (always enabled)
  for systemId, colony in state.colonies.mpairs:
    if colony.unassignedSquadrons.len > 0:
      autoBalanceSquadronsToFleets(state, colony, systemId, orders)

  logDebug(LogCategory.lcEconomy, "Colony automation complete")
