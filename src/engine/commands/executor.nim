## Fleet Order Execution Engine
## Implements all 16 fleet order types from operations.md Section 6.2

import std/[options, tables, strformat]
import ../../common/types/[core, units]
import ../gamestate, ../orders, ../fleet, ../squadron, ../state_helpers, ../logger, ../starmap
import ../index_maintenance
import ../intelligence/detection
import ../combat/[types as combat_types]
import ../diplomacy/[types as dip_types]
import ../resolution/[types as resolution_types, fleet_orders]
import ../resolution/event_factory/init as event_factory
import ../standing_orders

type
  OrderOutcome* {.pure.} = enum
    Success,  # Order executed successfully, continue if persistent
    Failed,   # Order failed validation/execution, remove from queue
    Aborted   # Order cancelled (conditions changed), remove from queue

# =============================================================================
# Forward Declarations
# =============================================================================

proc executeHoldOrder(state: var GameState, fleet: Fleet, order: FleetOrder, events: var seq[resolution_types.GameEvent]): OrderOutcome
proc executeMoveOrder(state: var GameState, fleet: Fleet, order: FleetOrder, events: var seq[resolution_types.GameEvent]): OrderOutcome
proc executeSeekHomeOrder(state: var GameState, fleet: Fleet, order: FleetOrder, events: var seq[resolution_types.GameEvent]): OrderOutcome
proc executePatrolOrder(state: var GameState, fleet: Fleet, order: FleetOrder, events: var seq[resolution_types.GameEvent]): OrderOutcome
proc executeGuardStarbaseOrder(state: var GameState, fleet: Fleet, order: FleetOrder, events: var seq[resolution_types.GameEvent]): OrderOutcome
proc executeGuardPlanetOrder(state: var GameState, fleet: Fleet, order: FleetOrder, events: var seq[resolution_types.GameEvent]): OrderOutcome
proc executeBlockadeOrder(state: var GameState, fleet: Fleet, order: FleetOrder, events: var seq[resolution_types.GameEvent]): OrderOutcome
proc executeBombardOrder(state: var GameState, fleet: Fleet, order: FleetOrder, events: var seq[resolution_types.GameEvent]): OrderOutcome
proc executeInvadeOrder(state: var GameState, fleet: Fleet, order: FleetOrder, events: var seq[resolution_types.GameEvent]): OrderOutcome
proc executeBlitzOrder(state: var GameState, fleet: Fleet, order: FleetOrder, events: var seq[resolution_types.GameEvent]): OrderOutcome
proc executeSpyPlanetOrder(state: var GameState, fleet: Fleet, order: FleetOrder, events: var seq[resolution_types.GameEvent]): OrderOutcome
proc executeHackStarbaseOrder(state: var GameState, fleet: Fleet, order: FleetOrder, events: var seq[resolution_types.GameEvent]): OrderOutcome
proc executeSpySystemOrder(state: var GameState, fleet: Fleet, order: FleetOrder, events: var seq[resolution_types.GameEvent]): OrderOutcome
proc executeColonizeOrder(state: var GameState, fleet: Fleet, order: FleetOrder, events: var seq[resolution_types.GameEvent]): OrderOutcome
proc executeJoinFleetOrder(state: var GameState, fleet: Fleet, order: FleetOrder, events: var seq[resolution_types.GameEvent]): OrderOutcome
proc executeRendezvousOrder(state: var GameState, fleet: Fleet, order: FleetOrder, events: var seq[resolution_types.GameEvent]): OrderOutcome
proc executeSalvageOrder(state: var GameState, fleet: Fleet, order: FleetOrder, events: var seq[resolution_types.GameEvent]): OrderOutcome
proc executeReserveOrder(state: var GameState, fleet: Fleet, order: FleetOrder, events: var seq[resolution_types.GameEvent]): OrderOutcome
proc executeMothballOrder(state: var GameState, fleet: Fleet, order: FleetOrder, events: var seq[resolution_types.GameEvent]): OrderOutcome
proc executeReactivateOrder(state: var GameState, fleet: Fleet, order: FleetOrder, events: var seq[resolution_types.GameEvent]): OrderOutcome
proc executeViewWorldOrder(state: var GameState, fleet: Fleet, order: FleetOrder, events: var seq[resolution_types.GameEvent]): OrderOutcome

# =============================================================================
# Order Execution Dispatcher
# =============================================================================

proc executeFleetOrder*(
  state: var GameState,
  houseId: HouseId,
  order: FleetOrder,
  events: var seq[resolution_types.GameEvent]
): OrderOutcome =
  ## Main dispatcher for fleet order execution
  ## Routes to appropriate handler based on order type

  # Validate fleet exists
  let fleetOpt = state.getFleet(order.fleetId)
  if fleetOpt.isNone:
    events.add(event_factory.orderFailed(
      houseId = houseId,
      fleetId = order.fleetId,
      orderType = $order.orderType,
      reason = "fleet not found",
      systemId = none(SystemId)
    ))
    return OrderOutcome.Failed

  let fleet = fleetOpt.get()

  # Validate fleet ownership
  if fleet.owner != houseId:
    events.add(event_factory.orderFailed(
      houseId = houseId,
      fleetId = order.fleetId,
      orderType = $order.orderType,
      reason = "fleet not owned by house",
      systemId = some(fleet.location)
    ))
    return OrderOutcome.Failed

  # Route to order type handler
  case order.orderType
  of FleetOrderType.Hold:
    return executeHoldOrder(state, fleet, order, events)
  of FleetOrderType.Move:
    return executeMoveOrder(state, fleet, order, events)
  of FleetOrderType.SeekHome:
    return executeSeekHomeOrder(state, fleet, order, events)
  of FleetOrderType.Patrol:
    return executePatrolOrder(state, fleet, order, events)
  of FleetOrderType.GuardStarbase:
    return executeGuardStarbaseOrder(state, fleet, order, events)
  of FleetOrderType.GuardPlanet:
    return executeGuardPlanetOrder(state, fleet, order, events)
  of FleetOrderType.BlockadePlanet:
    return executeBlockadeOrder(state, fleet, order, events)
  of FleetOrderType.Bombard:
    return executeBombardOrder(state, fleet, order, events)
  of FleetOrderType.Invade:
    return executeInvadeOrder(state, fleet, order, events)
  of FleetOrderType.Blitz:
    return executeBlitzOrder(state, fleet, order, events)
  of FleetOrderType.SpyPlanet:
    return executeSpyPlanetOrder(state, fleet, order, events)
  of FleetOrderType.HackStarbase:
    return executeHackStarbaseOrder(state, fleet, order, events)
  of FleetOrderType.SpySystem:
    return executeSpySystemOrder(state, fleet, order, events)
  of FleetOrderType.Colonize:
    return executeColonizeOrder(state, fleet, order, events)
  of FleetOrderType.JoinFleet:
    return executeJoinFleetOrder(state, fleet, order, events)
  of FleetOrderType.Rendezvous:
    return executeRendezvousOrder(state, fleet, order, events)
  of FleetOrderType.Salvage:
    return executeSalvageOrder(state, fleet, order, events)
  of FleetOrderType.Reserve:
    return executeReserveOrder(state, fleet, order, events)
  of FleetOrderType.Mothball:
    return executeMothballOrder(state, fleet, order, events)
  of FleetOrderType.Reactivate:
    return executeReactivateOrder(state, fleet, order, events)
  of FleetOrderType.ViewWorld:
    return executeViewWorldOrder(state, fleet, order, events)

# =============================================================================
# Order 00: Hold Position
# =============================================================================

proc executeHoldOrder(
  state: var GameState,
  fleet: Fleet,
  order: FleetOrder,
  events: var seq[resolution_types.GameEvent]
): OrderOutcome =
  ## Order 00: Hold position and standby
  ## Always succeeds - fleet does nothing this turn

  # Silent - OrderIssued generated upstream
  return OrderOutcome.Success

# =============================================================================
# Order 01: Move Fleet
# =============================================================================

proc executeMoveOrder(
  state: var GameState,
  fleet: Fleet,
  order: FleetOrder,
  events: var seq[resolution_types.GameEvent]
): OrderOutcome =
  ## Order 01: Move to new system and hold position
  ## Calls resolveMovementOrder to execute actual movement with pathfinding

  # Per economy.md:3.9 - Reserve and Mothballed fleets cannot move
  if fleet.status == FleetStatus.Reserve:
    return OrderOutcome.Failed

  if fleet.status == FleetStatus.Mothballed:
    return OrderOutcome.Failed

  if order.targetSystem.isNone:
    return OrderOutcome.Failed

  # Execute actual movement using centralized movement arbiter
  # Events are handled by the calling context (fleet_order_execution.nim)
  var events: seq[resolution_types.GameEvent] = @[]
  fleet_orders.resolveMovementOrder(state, fleet.owner, order, events)

  return OrderOutcome.Success

# =============================================================================
# Order 02: Seek Home
# =============================================================================

proc executeSeekHomeOrder(
  state: var GameState,
  fleet: Fleet,
  order: FleetOrder,
  events: var seq[resolution_types.GameEvent]
): OrderOutcome =
  ## Order 02: Find closest friendly colony and move there
  ## If that colony is conquered, find next closest

  # Find all friendly colonies
  # Use coloniesByOwner index for O(1) lookup instead of O(c) scan
  var friendlyColonies: seq[SystemId] = @[]
  if fleet.owner in state.coloniesByOwner:
    friendlyColonies = state.coloniesByOwner[fleet.owner]

  if friendlyColonies.len == 0:
    # No friendly colonies - abort mission
    events.add(event_factory.orderAborted(
      fleet.owner,
      fleet.id,
      "SeekHome",
      reason = "no friendly colonies available",
      systemId = some(fleet.location)
    ))
    return OrderOutcome.Aborted

  # Find closest colony using pathfinding
  var closestColony = friendlyColonies[0]
  var minDistance = int.high

  for colonyId in friendlyColonies:
    let pathResult = state.starMap.findPath(fleet.location, colonyId, fleet)
    if pathResult.found:
      let distance = pathResult.path.len - 1
      if distance < minDistance:
        minDistance = distance
        closestColony = colonyId

  # Check if already at closest colony - mission complete
  if fleet.location == closestColony:
    events.add(event_factory.orderCompleted(
      fleet.owner,
      fleet.id,
      "SeekHome",
      details = &"reached home at {closestColony}",
      systemId = some(closestColony)
    ))
    return OrderOutcome.Success

  # Create movement order to closest colony
  let moveOrder = FleetOrder(
    fleetId: fleet.id,
    orderType: FleetOrderType.Move,
    targetSystem: some(closestColony),
    targetFleet: none(FleetId),
    priority: order.priority
  )

  # Execute movement (delegated to fleet_orders.resolveMovementOrder)
  var moveEvents: seq[resolution_types.GameEvent] = @[]
  fleet_orders.resolveMovementOrder(state, fleet.owner, moveOrder, moveEvents)
  events.add(moveEvents)

  return OrderOutcome.Success

# =============================================================================
# Order 03: Patrol System
# =============================================================================

proc executePatrolOrder(
  state: var GameState,
  fleet: Fleet,
  order: FleetOrder,
  events: var seq[resolution_types.GameEvent]
): OrderOutcome =
  ## Order 03: Actively patrol system, engaging hostile forces
  ## Engagement rules per operations.md:6.2.4
  ## Persistent order - silent re-execution (only generates event on first execution)

  if order.targetSystem.isNone:
    events.add(event_factory.orderFailed(
      fleet.owner,
      fleet.id,
      "Patrol",
      reason = "no target system specified",
      systemId = some(fleet.location)
    ))
    return OrderOutcome.Failed

  let targetSystem = order.targetSystem.get()

  # Check if target system lost (conquered by enemy)
  if targetSystem in state.colonies:
    let colony = state.colonies[targetSystem]
    if colony.owner != fleet.owner:
      events.add(event_factory.orderAborted(
        fleet.owner,
        fleet.id,
        "Patrol",
        reason = "target system no longer friendly",
        systemId = some(targetSystem)
      ))
      return OrderOutcome.Aborted

  # Persistent order - stays active, combat happens in Conflict Phase
  # Silent - no OrderCompleted spam (would generate every turn)
  return OrderOutcome.Success

# =============================================================================
# Order 04: Guard Starbase
# =============================================================================

proc executeGuardStarbaseOrder(
  state: var GameState,
  fleet: Fleet,
  order: FleetOrder,
  events: var seq[resolution_types.GameEvent]
): OrderOutcome =
  ## Order 04: Protect starbase, join Task Force when confronted
  ## Requires combat ships
  ## Persistent order - silent re-execution

  if order.targetSystem.isNone:
    events.add(event_factory.orderFailed(
      fleet.owner,
      fleet.id,
      "GuardStarbase",
      reason = "no target system specified",
      systemId = some(fleet.location)
    ))
    return OrderOutcome.Failed

  # Check for combat capability
  var hasCombatShips = false
  for squadron in fleet.squadrons:
    if squadron.flagship.stats.attackStrength > 0:
      hasCombatShips = true
      break

  if not hasCombatShips:
    events.add(event_factory.orderFailed(
      fleet.owner,
      fleet.id,
      "GuardStarbase",
      reason = "no combat-capable ships",
      systemId = some(fleet.location)
    ))
    return OrderOutcome.Failed

  let targetSystem = order.targetSystem.get()

  # Validate starbase presence and ownership
  if targetSystem notin state.colonies:
    events.add(event_factory.orderAborted(
      fleet.owner,
      fleet.id,
      "GuardStarbase",
      reason = "target system has no colony",
      systemId = some(targetSystem)
    ))
    return OrderOutcome.Aborted

  let colony = state.colonies[targetSystem]
  if colony.owner != fleet.owner:
    events.add(event_factory.orderAborted(
      fleet.owner,
      fleet.id,
      "GuardStarbase",
      reason = "colony no longer friendly",
      systemId = some(targetSystem)
    ))
    return OrderOutcome.Aborted

  if colony.starbases.len == 0:
    events.add(event_factory.orderAborted(
      fleet.owner,
      fleet.id,
      "GuardStarbase",
      reason = "starbase destroyed",
      systemId = some(targetSystem)
    ))
    return OrderOutcome.Aborted

  # Persistent order - stays active, silent re-execution
  return OrderOutcome.Success

# =============================================================================
# Order 05: Guard/Blockade Planet
# =============================================================================

proc executeGuardPlanetOrder(
  state: var GameState,
  fleet: Fleet,
  order: FleetOrder,
  events: var seq[resolution_types.GameEvent]
): OrderOutcome =
  ## Order 05 (Guard): Protect friendly colony, rear guard position
  ## Does not auto-join starbase Task Force (allows Raiders)
  ## Persistent order - silent re-execution

  if order.targetSystem.isNone:
    events.add(event_factory.orderFailed(
      fleet.owner,
      fleet.id,
      "GuardPlanet",
      reason = "no target system specified",
      systemId = some(fleet.location)
    ))
    return OrderOutcome.Failed

  let targetSystem = order.targetSystem.get()

  # Check for combat capability
  var hasCombatShips = false
  for squadron in fleet.squadrons:
    if squadron.flagship.stats.attackStrength > 0:
      hasCombatShips = true
      break

  if not hasCombatShips:
    events.add(event_factory.orderFailed(
      fleet.owner,
      fleet.id,
      "GuardPlanet",
      reason = "no combat-capable ships",
      systemId = some(fleet.location)
    ))
    return OrderOutcome.Failed

  # Check target colony still exists and is friendly
  if targetSystem in state.colonies:
    let colony = state.colonies[targetSystem]
    if colony.owner != fleet.owner:
      events.add(event_factory.orderAborted(
        fleet.owner,
        fleet.id,
        "GuardPlanet",
        reason = "colony no longer friendly",
        systemId = some(targetSystem)
      ))
      return OrderOutcome.Aborted

  # Persistent order - stays active, silent re-execution
  return OrderOutcome.Success

proc executeBlockadeOrder(
  state: var GameState,
  fleet: Fleet,
  order: FleetOrder,
  events: var seq[resolution_types.GameEvent]
): OrderOutcome =
  ## Order 05 (Blockade): Block enemy planet, reduce GCO by 60%
  ## Per operations.md:6.2.6 - Immediate effect during Income Phase
  ## Prestige penalty: -2 per turn if colony under blockade
  ## Persistent order - silent re-execution

  if order.targetSystem.isNone:
    events.add(event_factory.orderFailed(
      fleet.owner,
      fleet.id,
      "BlockadePlanet",
      reason = "no target system specified",
      systemId = some(fleet.location)
    ))
    return OrderOutcome.Failed

  let targetSystem = order.targetSystem.get()

  # Check for combat capability
  var hasCombatShips = false
  for squadron in fleet.squadrons:
    if squadron.flagship.stats.attackStrength > 0:
      hasCombatShips = true
      break

  if not hasCombatShips:
    events.add(event_factory.orderFailed(
      fleet.owner,
      fleet.id,
      "BlockadePlanet",
      reason = "no combat-capable ships",
      systemId = some(fleet.location)
    ))
    return OrderOutcome.Failed

  # Check target colony exists and is hostile
  if targetSystem notin state.colonies:
    events.add(event_factory.orderAborted(
      fleet.owner,
      fleet.id,
      "BlockadePlanet",
      reason = "target system has no colony",
      systemId = some(targetSystem)
    ))
    return OrderOutcome.Aborted

  let colony = state.colonies[targetSystem]
  if colony.owner == fleet.owner:
    events.add(event_factory.orderAborted(
      fleet.owner,
      fleet.id,
      "BlockadePlanet",
      reason = "cannot blockade own colony",
      systemId = some(targetSystem)
    ))
    return OrderOutcome.Aborted

  # Validate target house is not eliminated (leaderboard is public info)
  if colony.owner in state.houses:
    let targetHouse = state.houses[colony.owner]
    if targetHouse.eliminated:
      events.add(event_factory.orderAborted(
        fleet.owner,
        fleet.id,
        "BlockadePlanet",
        reason = "target house eliminated",
        systemId = some(targetSystem)
      ))
      return OrderOutcome.Aborted

  # NOTE: Blockade tracking not yet implemented in Colony type
  # Blockade effects are calculated dynamically during Income Phase by checking
  # for BlockadePlanet fleet orders at colony systems (see income.nim)
  # Future enhancement: Add blockaded: bool field to Colony type for faster lookups

  # Persistent order - stays active, silent re-execution
  return OrderOutcome.Success

# =============================================================================
# Order 06: Bombard Planet
# =============================================================================

proc executeBombardOrder(
  state: var GameState,
  fleet: Fleet,
  order: FleetOrder,
  events: var seq[resolution_types.GameEvent]
): OrderOutcome =
  ## Order 06: Orbital bombardment of planet
  ## Resolved in Conflict Phase - this marks intent

  if order.targetSystem.isNone:
    return OrderOutcome.Failed

  let targetSystem = order.targetSystem.get()

  # Check target colony exists
  if targetSystem notin state.colonies:
    return OrderOutcome.Failed

  let colony = state.colonies[targetSystem]
  if colony.owner == fleet.owner:
    return OrderOutcome.Failed

  # Validate target house is not eliminated (leaderboard is public info)
  if colony.owner in state.houses:
    let targetHouse = state.houses[colony.owner]
    if targetHouse.eliminated:
      return OrderOutcome.Failed

  # Check for combat capability
  var hasCombatShips = false
  for squadron in fleet.squadrons:
    if squadron.flagship.stats.attackStrength > 0:
      hasCombatShips = true
      break

  if not hasCombatShips:
    return OrderOutcome.Failed

  return OrderOutcome.Success

# =============================================================================
# Order 07: Invade Planet
# =============================================================================

proc executeInvadeOrder(
  state: var GameState,
  fleet: Fleet,
  order: FleetOrder,
  events: var seq[resolution_types.GameEvent]
): OrderOutcome =
  ## Order 07: Three-round planetary invasion
  ## 1) Destroy ground batteries
  ## 2) Pound population/ground troops
  ## 3) Land Marines (if batteries destroyed)

  if order.targetSystem.isNone:
    return OrderOutcome.Failed

  let targetSystem = order.targetSystem.get()

  # Check target colony exists
  if targetSystem notin state.colonies:
    return OrderOutcome.Failed

  let colony = state.colonies[targetSystem]
  if colony.owner == fleet.owner:
    return OrderOutcome.Failed

  # Validate target house is not eliminated (leaderboard is public info)
  if colony.owner in state.houses:
    let targetHouse = state.houses[colony.owner]
    if targetHouse.eliminated:
      return OrderOutcome.Failed

  # Check for combat ships and loaded troop transports
  var hasCombatShips = false
  var hasLoadedTransports = false

  for squadron in fleet.squadrons:
    if squadron.flagship.stats.attackStrength > 0:
      hasCombatShips = true

  # Check Auxiliary squadrons for loaded marines
  for squadron in fleet.squadrons:
    if squadron.squadronType == SquadronType.Auxiliary:
      if squadron.flagship.cargo.isSome:
        let cargo = squadron.flagship.cargo.get()
        if squadron.flagship.shipClass == ShipClass.TroopTransport and
           cargo.cargoType == CargoType.Marines and
           cargo.quantity > 0:
          hasLoadedTransports = true
          break

  if not hasCombatShips:
    return OrderOutcome.Failed

  if not hasLoadedTransports:
    return OrderOutcome.Failed

  return OrderOutcome.Success

# =============================================================================
# Order 08: Blitz Planet
# =============================================================================

proc executeBlitzOrder(
  state: var GameState,
  fleet: Fleet,
  order: FleetOrder,
  events: var seq[resolution_types.GameEvent]
): OrderOutcome =
  ## Order 08: Fast assault - dodge batteries, drop Marines
  ## Less planet damage, but requires 2:1 Marine superiority
  ## Per operations.md:6.2.9

  if order.targetSystem.isNone:
    return OrderOutcome.Failed

  let targetSystem = order.targetSystem.get()

  # Check target colony exists
  if targetSystem notin state.colonies:
    return OrderOutcome.Failed

  let colony = state.colonies[targetSystem]
  if colony.owner == fleet.owner:
    return OrderOutcome.Failed

  # Validate target house is not eliminated (leaderboard is public info)
  if colony.owner in state.houses:
    let targetHouse = state.houses[colony.owner]
    if targetHouse.eliminated:
      return OrderOutcome.Failed

  # Check for loaded troop transports (Auxiliary squadrons)
  var hasLoadedTransports = false

  for squadron in fleet.squadrons:
    if squadron.squadronType == SquadronType.Auxiliary:
      if squadron.flagship.shipClass == ShipClass.TroopTransport:
        # Check if transport has Marines loaded
        if squadron.flagship.cargo.isSome:
          let cargo = squadron.flagship.cargo.get()
          if cargo.cargoType == CargoType.Marines and cargo.quantity > 0:
            hasLoadedTransports = true
            break

  if not hasLoadedTransports:
    return OrderOutcome.Failed

  return OrderOutcome.Success

# =============================================================================
# Order 09: Spy on Planet
# =============================================================================

proc executeSpyPlanetOrder(
  state: var GameState,
  fleet: Fleet,
  order: FleetOrder,
  events: var seq[resolution_types.GameEvent]
): OrderOutcome =
  ## Order 09: Deploy scout to gather planet intelligence
  ## Reserved for solo Scout operations per operations.md:6.2.10

  if order.targetSystem.isNone:
    events.add(event_factory.orderFailed(
      fleet.owner,
      fleet.id,
      "SpyPlanet",
      reason = "no target system specified",
      systemId = some(fleet.location)
    ))
    return OrderOutcome.Failed

  let targetSystem = order.targetSystem.get()

  # Validate target house is not eliminated (leaderboard is public info)
  if targetSystem in state.colonies:
    let colony = state.colonies[targetSystem]
    if colony.owner in state.houses:
      let targetHouse = state.houses[colony.owner]
      if targetHouse.eliminated:
        events.add(event_factory.orderFailed(
          fleet.owner,
          fleet.id,
          "SpyPlanet",
          reason = "target house eliminated",
          systemId = some(fleet.location)
        ))
        return OrderOutcome.Failed

  # Count scouts for mesh network bonus (validation already confirmed scout-only fleet)
  let scoutCount = fleet.squadrons.len

  # Set fleet mission state
  var updatedFleet = fleet
  updatedFleet.missionState = FleetMissionState.Traveling
  updatedFleet.missionTarget = some(targetSystem)

  # Create movement order to target (if not already there)
  if fleet.location != targetSystem:
    # Calculate jump lane path from current location to target
    let path = findPath(state.starMap, fleet.location, targetSystem, fleet)

    if path.path.len == 0:
      events.add(event_factory.orderFailed(
        fleet.owner,
        fleet.id,
        "SpyPlanet",
        reason = "no path to target system",
        systemId = some(fleet.location)
      ))
      return OrderOutcome.Failed

    # Create movement order
    let travelOrder = FleetOrder(
      fleetId: fleet.id,
      orderType: FleetOrderType.Move,
      targetSystem: some(targetSystem)
    )
    state.fleetOrders[fleet.id] = travelOrder

    # Update fleet in state
    state.fleets[fleet.id] = updatedFleet

    # Generate order accepted event
    events.add(event_factory.orderCompleted(
      fleet.owner,
      fleet.id,
      "SpyPlanet",
      details = &"scout fleet traveling to {targetSystem} for spy mission ({scoutCount} scouts)",
      systemId = some(fleet.location)
    ))
  else:
    # Already at target - start mission immediately
    updatedFleet.missionState = FleetMissionState.OnSpyMission
    updatedFleet.missionStartTurn = state.turn


    # Update fleet in state
    state.fleets[fleet.id] = updatedFleet

    # Generate mission start event
    events.add(event_factory.orderCompleted(
      fleet.owner,
      fleet.id,
      "SpyPlanet",
      details = &"spy mission started at {targetSystem} ({scoutCount} scouts)",
      systemId = some(targetSystem)
    ))

  return OrderOutcome.Success

# =============================================================================
# Order 10: Hack Starbase
# =============================================================================

proc executeHackStarbaseOrder(
  state: var GameState,
  fleet: Fleet,
  order: FleetOrder,
  events: var seq[resolution_types.GameEvent]
): OrderOutcome =
  ## Order 10: Electronic warfare against starbase
  ## Reserved for Scout operations per operations.md:6.2.11

  if order.targetSystem.isNone:
    events.add(event_factory.orderFailed(
      fleet.owner,
      fleet.id,
      "HackStarbase",
      reason = "no target system specified",
      systemId = some(fleet.location)
    ))
    return OrderOutcome.Failed

  let targetSystem = order.targetSystem.get()

  # Validate starbase presence at target
  if targetSystem notin state.colonies:
    events.add(event_factory.orderFailed(
      fleet.owner,
      fleet.id,
      "HackStarbase",
      reason = "target system has no colony",
      systemId = some(fleet.location)
    ))
    return OrderOutcome.Failed

  let colony = state.colonies[targetSystem]
  if colony.starbases.len == 0:
    events.add(event_factory.orderFailed(
      fleet.owner,
      fleet.id,
      "HackStarbase",
      reason = "target colony has no starbase",
      systemId = some(fleet.location)
    ))
    return OrderOutcome.Failed

  # Validate target house is not eliminated (leaderboard is public info)
  if colony.owner in state.houses:
    let targetHouse = state.houses[colony.owner]
    if targetHouse.eliminated:
      events.add(event_factory.orderFailed(
        fleet.owner,
        fleet.id,
        "HackStarbase",
        reason = "target house eliminated",
        systemId = some(fleet.location)
      ))
      return OrderOutcome.Failed

  # Count scouts for mission (validation already confirmed scout-only fleet)
  let scoutCount = fleet.squadrons.len

  # Set fleet mission state
  var updatedFleet = fleet
  updatedFleet.missionState = FleetMissionState.Traveling
  updatedFleet.missionTarget = some(targetSystem)

  # Create movement order to target (if not already there)
  if fleet.location != targetSystem:
    # Calculate jump lane path from current location to target
    let path = findPath(state.starMap, fleet.location, targetSystem, fleet)

    if path.path.len == 0:
      events.add(event_factory.orderFailed(
        fleet.owner,
        fleet.id,
        "HackStarbase",
        reason = "no path to target system",
        systemId = some(fleet.location)
      ))
      return OrderOutcome.Failed

    # Create movement order
    let travelOrder = FleetOrder(
      fleetId: fleet.id,
      orderType: FleetOrderType.Move,
      targetSystem: some(targetSystem)
    )
    state.fleetOrders[fleet.id] = travelOrder

    # Update fleet in state
    state.fleets[fleet.id] = updatedFleet

    # Generate order accepted event
    events.add(event_factory.orderCompleted(
      fleet.owner,
      fleet.id,
      "HackStarbase",
      details = &"scout fleet traveling to {targetSystem} to hack starbase ({scoutCount} scouts)",
      systemId = some(fleet.location)
    ))
  else:
    # Already at target - start mission immediately
    updatedFleet.missionState = FleetMissionState.OnSpyMission
    updatedFleet.missionStartTurn = state.turn


    # Update fleet in state
    state.fleets[fleet.id] = updatedFleet

    # Generate mission start event
    events.add(event_factory.orderCompleted(
      fleet.owner,
      fleet.id,
      "HackStarbase",
      details = &"starbase hack mission started at {targetSystem} ({scoutCount} scouts)",
      systemId = some(targetSystem)
    ))

  return OrderOutcome.Success

# =============================================================================
# Order 11: Spy on System
# =============================================================================

proc executeSpySystemOrder(
  state: var GameState,
  fleet: Fleet,
  order: FleetOrder,
  events: var seq[resolution_types.GameEvent]
): OrderOutcome =
  ## Order 11: Deploy scout for system reconnaissance
  ## Reserved for solo Scout operations per operations.md:6.2.12

  if order.targetSystem.isNone:
    events.add(event_factory.orderFailed(
      fleet.owner,
      fleet.id,
      "SpySystem",
      reason = "no target system specified",
      systemId = some(fleet.location)
    ))
    return OrderOutcome.Failed

  let targetSystem = order.targetSystem.get()

  # Validate target house is not eliminated (leaderboard is public info)
  if targetSystem in state.colonies:
    let colony = state.colonies[targetSystem]
    if colony.owner in state.houses:
      let targetHouse = state.houses[colony.owner]
      if targetHouse.eliminated:
        events.add(event_factory.orderFailed(
          fleet.owner,
          fleet.id,
          "SpySystem",
          reason = "target house eliminated",
          systemId = some(fleet.location)
        ))
        return OrderOutcome.Failed

  # Count scouts for mission (validation already confirmed scout-only fleet)
  let scoutCount = fleet.squadrons.len

  # Set fleet mission state
  var updatedFleet = fleet
  updatedFleet.missionState = FleetMissionState.Traveling
  updatedFleet.missionTarget = some(targetSystem)

  # Create movement order to target (if not already there)
  if fleet.location != targetSystem:
    # Calculate jump lane path from current location to target
    let path = findPath(state.starMap, fleet.location, targetSystem, fleet)

    if path.path.len == 0:
      events.add(event_factory.orderFailed(
        fleet.owner,
        fleet.id,
        "SpySystem",
        reason = "no path to target system",
        systemId = some(fleet.location)
      ))
      return OrderOutcome.Failed

    # Create movement order
    let travelOrder = FleetOrder(
      fleetId: fleet.id,
      orderType: FleetOrderType.Move,
      targetSystem: some(targetSystem)
    )
    state.fleetOrders[fleet.id] = travelOrder

    # Update fleet in state
    state.fleets[fleet.id] = updatedFleet

    # Generate order accepted event
    events.add(event_factory.orderCompleted(
      fleet.owner,
      fleet.id,
      "SpySystem",
      details = &"scout fleet traveling to {targetSystem} for system reconnaissance ({scoutCount} scouts)",
      systemId = some(fleet.location)
    ))
  else:
    # Already at target - start mission immediately
    updatedFleet.missionState = FleetMissionState.OnSpyMission
    updatedFleet.missionStartTurn = state.turn


    # Update fleet in state
    state.fleets[fleet.id] = updatedFleet

    # Generate mission start event
    events.add(event_factory.orderCompleted(
      fleet.owner,
      fleet.id,
      "SpySystem",
      details = &"system reconnaissance mission started at {targetSystem} ({scoutCount} scouts)",
      systemId = some(targetSystem)
    ))

  return OrderOutcome.Success

# =============================================================================
# Order 12: Colonize Planet
# =============================================================================

proc executeColonizeOrder(
  state: var GameState,
  fleet: Fleet,
  order: FleetOrder,
  events: var seq[resolution_types.GameEvent]
): OrderOutcome =
  ## Order 12: Establish colony with ETAC
  ## Reserved for ETAC under fleet escort per operations.md:6.2.13
  ## Calls resolveColonizationOrder to execute actual colonization

  if order.targetSystem.isNone:
    return OrderOutcome.Failed

  # Check fleet has ETAC with loaded colonists (Expansion squadrons)
  var hasLoadedETAC = false

  for squadron in fleet.squadrons:
    if squadron.squadronType == SquadronType.Expansion:
      if squadron.flagship.shipClass == ShipClass.ETAC and squadron.flagship.cargo.isSome:
        let cargo = squadron.flagship.cargo.get()
        if cargo.cargoType == CargoType.Colonists and cargo.quantity > 0:
          hasLoadedETAC = true
          break

  if not hasLoadedETAC:
    return OrderOutcome.Failed

  # Execute actual colonization using centralized colonization logic
  var colonizationEvents: seq[resolution_types.GameEvent] = @[]
  fleet_orders.resolveColonizationOrder(state, fleet.owner, order,
                                        colonizationEvents)
  events.add(colonizationEvents)

  return OrderOutcome.Success

# =============================================================================
# Order 13: Join Fleet
# =============================================================================

proc executeJoinFleetOrder(
  state: var GameState,
  fleet: Fleet,
  order: FleetOrder,
  events: var seq[resolution_types.GameEvent]
): OrderOutcome =
  ## Order 13: Seek and merge with another fleet
  ## Old fleet disbands, squadrons join target
  ## Per operations.md:6.2.14
  ##
  ## SCOUT MESH NETWORK BENEFITS:
  ## When merging scout squadrons, they automatically gain mesh network ELI bonuses:
  ## - 2-3 scouts: +1 ELI bonus
  ## - 4-5 scouts: +2 ELI bonus
  ## - 6+ scouts: +3 ELI bonus (maximum)
  ## These bonuses apply to detection, counter-intelligence, and spy missions.
  ## See assets.md:2.4.2 for mesh network modifier table.

  if order.targetFleet.isNone:
    events.add(event_factory.orderFailed(
      fleet.owner,
      fleet.id,
      "JoinFleet",
      reason = "no target fleet specified",
      systemId = some(fleet.location)
    ))
    return OrderOutcome.Failed

  let targetFleetId = order.targetFleet.get()

  # Target is a normal fleet
  let targetFleetOpt = state.getFleet(targetFleetId)

  if targetFleetOpt.isNone:
    # Target fleet destroyed or deleted - clear the order and fall back to standing orders
    # Standing orders will be used automatically by the order resolution system
    if fleet.id in state.fleetOrders:
      state.fleetOrders.del(fleet.id)
      standing_orders.resetStandingOrderGracePeriod(state, fleet.id)

    events.add(event_factory.orderAborted(
        houseId = fleet.owner,
        fleetId = fleet.id,
        orderType = "JoinFleet",
        reason = "target fleet no longer exists",
        systemId = some(fleet.location)
      ))

    return OrderOutcome.Failed

  let targetFleet = targetFleetOpt.get()

  # Check same owner
  if targetFleet.owner != fleet.owner:
    events.add(event_factory.orderFailed(
      fleet.owner,
      fleet.id,
      "JoinFleet",
      reason = "target fleet is not owned by same house",
      systemId = some(fleet.location)
    ))
    return OrderOutcome.Failed

  # Check if at same location - if not, move toward target
  if targetFleet.location != fleet.location:
    # Fleet will follow target - use centralized movement system
    # Create a movement order to target's current location
    let movementOrder = FleetOrder(
      fleetId: fleet.id,
      orderType: FleetOrderType.Move,
      targetSystem: some(targetFleet.location),
      targetFleet: none(FleetId),
      priority: order.priority
    )

    # Use the centralized movement arbiter (handles all lane logic, pathfinding, etc.)
    # This respects DoD principles - movement logic in ONE place
    var events: seq[resolution_types.GameEvent] = @[]
    resolveMovementOrder(state, fleet.owner, movementOrder, events)

    # Check if movement succeeded by comparing fleet location
    let updatedFleetOpt = state.getFleet(fleet.id)
    if updatedFleetOpt.isNone:
      return OrderOutcome.Failed

    let movedFleet = updatedFleetOpt.get()

    # Check if fleet actually moved (pathfinding succeeded)
    if movedFleet.location == fleet.location:
      # Fleet didn't move - no path found to target
      # Cancel order and fall back to standing orders
      if fleet.id in state.fleetOrders:
        state.fleetOrders.del(fleet.id)
        standing_orders.resetStandingOrderGracePeriod(state, fleet.id)

      events.add(event_factory.orderAborted(
          houseId = fleet.owner,
          fleetId = fleet.id,
          orderType = "JoinFleet",
          reason = "cannot reach target",
          systemId = some(fleet.location)
        ))

      return OrderOutcome.Failed

    # If still not at target location, keep order persistent
    if movedFleet.location != targetFleet.location:
      # Keep the Join Fleet order active so it continues pursuit next turn
      # Order remains in fleetOrders table
      # Silent - ongoing pursuit
      return OrderOutcome.Success

    # If we got here, fleet reached target - fall through to merge logic below

  # At same location - merge squadrons into target fleet (all squadron types)
  var updatedTargetFleet = targetFleet
  for squadron in fleet.squadrons:
    updatedTargetFleet.squadrons.add(squadron)

  state.fleets[targetFleetId] = updatedTargetFleet

  # Remove source fleet and clean up orders
  state.removeFleetFromIndices(fleet.id, fleet.owner, fleet.location)
  state.fleets.del(fleet.id)
  if fleet.id in state.fleetOrders:
    state.fleetOrders.del(fleet.id)
  if fleet.id in state.standingOrders:
    state.standingOrders.del(fleet.id)

  logInfo(LogCategory.lcFleet, "Fleet " & $fleet.id & " merged into fleet " & $targetFleetId & " (source fleet removed)")

  # Generate OrderCompleted event for successful fleet merge
  events.add(event_factory.orderCompleted(
    fleet.owner,
    fleet.id,
    "JoinFleet",
    details = &"merged into fleet {targetFleetId}",
    systemId = some(fleet.location)
  ))

  return OrderOutcome.Success

# =============================================================================
# Order 14: Rendezvous
# =============================================================================

proc executeRendezvousOrder(
  state: var GameState,
  fleet: Fleet,
  order: FleetOrder,
  events: var seq[resolution_types.GameEvent]
): OrderOutcome =
  ## Order 14: Move to system and merge with other rendezvous fleets
  ## Lowest fleet ID becomes host
  ## Per operations.md:6.2.15
  ##
  ## SCOUT MESH NETWORK BENEFITS:
  ## When multiple scout squadrons rendezvous, they automatically gain mesh network ELI bonuses:
  ## - 2-3 scouts: +1 ELI bonus
  ## - 4-5 scouts: +2 ELI bonus
  ## - 6+ scouts: +3 ELI bonus (maximum)
  ## All squadrons (including scouts) from all rendezvous fleets are merged into the host fleet.
  ## See assets.md:2.4.2 for mesh network modifier table.

  if order.targetSystem.isNone:
    events.add(event_factory.orderFailed(
      fleet.owner,
      fleet.id,
      "Rendezvous",
      reason = "no target system specified",
      systemId = some(fleet.location)
    ))
    return OrderOutcome.Failed

  let targetSystem = order.targetSystem.get()

  # Check if rendezvous point has hostile forces (enemy/neutral fleets)
  # Use fleetsByLocation index for O(1) lookup instead of O(F) scan
  let house = state.houses[fleet.owner]
  if targetSystem in state.fleetsByLocation:
    for otherFleetId in state.fleetsByLocation[targetSystem]:
      if otherFleetId notin state.fleets:
        continue  # Skip stale index entry
      let otherFleet = state.fleets[otherFleetId]
      if otherFleet.owner != fleet.owner:
        let relation = dip_types.getDiplomaticState(house.diplomaticRelations, otherFleet.owner)
        if relation == dip_types.DiplomaticState.Enemy or relation == dip_types.DiplomaticState.Hostile:
          # Hostile forces at rendezvous - abort
          events.add(event_factory.orderAborted(
            fleet.owner,
            fleet.id,
            "Rendezvous",
            reason = "hostile forces present at rendezvous point",
            systemId = some(fleet.location)
          ))
          return OrderOutcome.Aborted

  # Check if rendezvous point colony is enemy-controlled (additional check)
  if targetSystem in state.colonies:
    let colony = state.colonies[targetSystem]
    if colony.owner != fleet.owner:
      let relation = dip_types.getDiplomaticState(house.diplomaticRelations, colony.owner)
      if relation == dip_types.DiplomaticState.Enemy:
        # Rendezvous point is enemy territory - abort
        events.add(event_factory.orderAborted(
          fleet.owner,
          fleet.id,
          "Rendezvous",
          reason = "rendezvous point is enemy-controlled",
          systemId = some(fleet.location)
        ))
        return OrderOutcome.Aborted

  # Check if fleet is at rendezvous point
  if fleet.location != targetSystem:
    # Still moving to rendezvous
    return OrderOutcome.Success

  # Find other fleets at rendezvous with same order at same location
  # Use fleetsByLocation index for O(1) lookup instead of O(F) scan
  var rendezvousFleets: seq[Fleet] = @[]
  rendezvousFleets.add(fleet)

  # Collect all fleets with Rendezvous orders at this system
  if targetSystem in state.fleetsByLocation:
    for fleetId in state.fleetsByLocation[targetSystem]:
      if fleetId == fleet.id:
        continue  # Skip self
      if fleetId notin state.fleets:
        continue  # Skip stale index entry

      let otherFleet = state.fleets[fleetId]
      # Check if owned by same house
      if otherFleet.owner == fleet.owner:
        # Check if has Rendezvous order to same system
        if fleetId in state.fleetOrders:
          let otherOrder = state.fleetOrders[fleetId]
          if otherOrder.orderType == FleetOrderType.Rendezvous and
             otherOrder.targetSystem.isSome and
             otherOrder.targetSystem.get() == targetSystem:
            rendezvousFleets.add(otherFleet)

  # If only this fleet, wait for others
  if rendezvousFleets.len == 1:
    # Silent - waiting
    return OrderOutcome.Success

  # Multiple fleets at rendezvous - merge into lowest ID fleet
  var lowestId = fleet.id
  for f in rendezvousFleets:
    if f.id < lowestId:
      lowestId = f.id

  # Get host fleet
  var hostFleet = state.fleets[lowestId]

  # Merge all other fleets into host
  var mergedCount = 0
  for f in rendezvousFleets:
    if f.id == lowestId:
      continue  # Skip host

    # Merge squadrons (all squadron types)
    for squadron in f.squadrons:
      hostFleet.squadrons.add(squadron)

    # Remove merged fleet and clean up orders
    state.removeFleetFromIndices(f.id, f.owner, f.location)
    state.fleets.del(f.id)
    if f.id in state.fleetOrders:
      state.fleetOrders.del(f.id)
    if f.id in state.standingOrders:
      state.standingOrders.del(f.id)

    mergedCount += 1
    logInfo(LogCategory.lcFleet, "Fleet " & $f.id & " merged into rendezvous host " & $lowestId & " (source fleet removed)")

  # Update host fleet
  state.fleets[lowestId] = hostFleet

  var message = "Rendezvous complete at " & $targetSystem & ": " & $mergedCount & " fleets merged into " & $lowestId

  # Generate OrderCompleted event for successful rendezvous
  var details = &"{mergedCount} fleet(s) merged"

  events.add(event_factory.orderCompleted(
    fleet.owner,
    lowestId,
    "Rendezvous",
    details = details,
    systemId = some(targetSystem)
  ))

  return OrderOutcome.Success

# =============================================================================
# Order 15: Salvage
# =============================================================================

proc executeSalvageOrder(
  state: var GameState,
  fleet: Fleet,
  order: FleetOrder,
  events: var seq[resolution_types.GameEvent]
): OrderOutcome =
  ## Order 15: Salvage fleet at closest friendly colony with spaceport or shipyard
  ## Fleet disbands, ships salvaged for 50% PC
  ## Per operations.md:6.2.16
  ##
  ## AUTOMATIC EXECUTION: This order executes immediately when given
  ## FACILITIES: Works at colonies with either spaceport OR shipyard

  # Find closest friendly colony with salvage facilities (spaceport or shipyard)
  var closestColony: Option[SystemId] = none(SystemId)

  # Check if fleet is currently at a friendly colony with facilities
  if fleet.location in state.colonies:
    let colony = state.colonies[fleet.location]
    let hasFacilities = colony.spaceports.len > 0 or colony.shipyards.len > 0

    if colony.owner == fleet.owner and hasFacilities:
      # Already at a suitable colony - use it immediately
      closestColony = some(fleet.location)

  # If not at suitable colony, search all owned colonies for one with facilities
  # Note: For simplicity, we take the first colony with facilities found
  # A more sophisticated implementation would use pathfinding to find truly closest
  # Use coloniesByOwner index for O(1) lookup instead of O(c) scan
  if closestColony.isNone:
    if fleet.owner in state.coloniesByOwner:
      for colonyId in state.coloniesByOwner[fleet.owner]:
        if colonyId in state.colonies:
          let colony = state.colonies[colonyId]
          # Check if colony has salvage facilities
          let hasFacilities = colony.spaceports.len > 0 or colony.shipyards.len > 0

          if hasFacilities:
            closestColony = some(colonyId)
            break

  if closestColony.isNone:
    events.add(event_factory.orderFailed(
      fleet.owner,
      fleet.id,
      "Salvage",
      reason = "no friendly colonies with salvage facilities (spaceport or shipyard)",
      systemId = some(fleet.location)
    ))
    return OrderOutcome.Failed

  # Calculate salvage value (50% of ship PC per operations.md:6.2.16)
  var salvageValue = 0
  for squadron in fleet.squadrons:
    # Flagship
    salvageValue += (squadron.flagship.stats.buildCost div 2)
    # Other ships in squadron
    for ship in squadron.ships:
      salvageValue += (ship.stats.buildCost div 2)

  # Add salvage PP to house treasury
  state.withHouse(fleet.owner):
    house.treasury += salvageValue

  # Generate event
  let targetSystem = closestColony.get()
  let transitMessage = if fleet.location == targetSystem:
    "at colony"
  else:
    "after transit to " & $targetSystem

  # Remove fleet from game state
  state.removeFleetFromIndices(fleet.id, fleet.owner, fleet.location)
  state.fleets.del(fleet.id)
  if fleet.id in state.fleetOrders:
    state.fleetOrders.del(fleet.id)
  if fleet.id in state.standingOrders:
    state.standingOrders.del(fleet.id)

  # Generate OrderCompleted event for salvage operation
  events.add(event_factory.orderCompleted(
    fleet.owner,
    fleet.id,
    "Salvage",
    details = &"recovered {salvageValue} PP from {fleet.squadrons.len} squadron(s)",
    systemId = some(targetSystem)
  ))

  return OrderOutcome.Success

# =============================================================================
# Reserve / Mothball / Reactivate Orders
# =============================================================================

proc executeReserveOrder(
  state: var GameState,
  fleet: Fleet,
  order: FleetOrder,
  events: var seq[resolution_types.GameEvent]
): OrderOutcome =
  ## Place fleet on Reserve status (50% maintenance, half AS/DS, can't move)
  ## Per economy.md:3.9
  ## If not at friendly colony, auto-seeks nearest friendly colony first

  # Check if already at a friendly colony
  var atFriendlyColony = false
  if fleet.location in state.colonies:
    let colony = state.colonies[fleet.location]
    if colony.owner == fleet.owner:
      atFriendlyColony = true

  # If not at friendly colony, find closest one and move there
  if not atFriendlyColony:
    # Find all friendly colonies
    var friendlyColonies: seq[SystemId] = @[]
    for colonyId, colony in state.colonies:
      if colony.owner == fleet.owner:
        friendlyColonies.add(colonyId)

    if friendlyColonies.len == 0:
      return OrderOutcome.Failed

    # Find closest colony using pathfinding
    var closestColony = friendlyColonies[0]
    var minDistance = int.high

    for colonyId in friendlyColonies:
      let pathResult = state.starMap.findPath(fleet.location, colonyId, fleet)
      if pathResult.found:
        let distance = pathResult.path.len - 1
        if distance < minDistance:
          minDistance = distance
          closestColony = colonyId

    # Not at colony yet - move toward it
    if fleet.location != closestColony:
      # Create movement order to target colony
      let moveOrder = FleetOrder(
        fleetId: fleet.id,
        orderType: FleetOrderType.Move,
        targetSystem: some(closestColony),
        targetFleet: none(FleetId),
        priority: order.priority
      )

      # Use centralized movement arbiter
      var events: seq[resolution_types.GameEvent] = @[]
      resolveMovementOrder(state, fleet.owner, moveOrder, events)

      # Check if fleet moved
      let updatedFleetOpt = state.getFleet(fleet.id)
      if updatedFleetOpt.isNone:
        return OrderOutcome.Failed

      let movedFleet = updatedFleetOpt.get()

      # Check if actually moved (pathfinding succeeded)
      if movedFleet.location == fleet.location:
        # Fleet didn't move - no path found
        events.add(event_factory.orderFailed(
          houseId = fleet.owner,
          fleetId = fleet.id,
          orderType = "Reserve",
          reason = "cannot reach colony",
          systemId = some(fleet.location)
        ))
        return OrderOutcome.Failed

      # Keep order persistent - will execute when fleet arrives
      # Silent - movement in progress
      return OrderOutcome.Success

  # At friendly colony - apply reserve status
  var updatedFleet = fleet
  updatedFleet.status = FleetStatus.Reserve
  state.fleets[fleet.id] = updatedFleet

  # Generate OrderCompleted event for state change
  events.add(event_factory.orderCompleted(
    fleet.owner,
    fleet.id,
    "Reserve",
    details = "placed on reserve status",
    systemId = some(fleet.location)
  ))

  return OrderOutcome.Success

proc executeMothballOrder(
  state: var GameState,
  fleet: Fleet,
  order: FleetOrder,
  events: var seq[resolution_types.GameEvent]
): OrderOutcome =
  ## Mothball fleet (0% maintenance, offline, screened in combat)
  ## Per economy.md:3.9
  ## If not at friendly colony with spaceport, auto-seeks nearest one first

  # Check if already at a friendly colony with spaceport
  var atFriendlyColonyWithSpaceport = false
  if fleet.location in state.colonies:
    let colony = state.colonies[fleet.location]
    if colony.owner == fleet.owner and colony.spaceports.len > 0:
      atFriendlyColonyWithSpaceport = true

  # If not at friendly colony with spaceport, find closest one and move there
  if not atFriendlyColonyWithSpaceport:
    # Find all friendly colonies with spaceports
    var friendlyColoniesWithSpaceports: seq[SystemId] = @[]
    for colonyId, colony in state.colonies:
      if colony.owner == fleet.owner and colony.spaceports.len > 0:
        friendlyColoniesWithSpaceports.add(colonyId)

    if friendlyColoniesWithSpaceports.len == 0:
      return OrderOutcome.Failed

    # Find closest colony using pathfinding
    var closestColony = friendlyColoniesWithSpaceports[0]
    var minDistance = int.high

    for colonyId in friendlyColoniesWithSpaceports:
      let pathResult = state.starMap.findPath(fleet.location, colonyId, fleet)
      if pathResult.found:
        let distance = pathResult.path.len - 1
        if distance < minDistance:
          minDistance = distance
          closestColony = colonyId

    # Not at colony yet - move toward it
    if fleet.location != closestColony:
      # Create movement order to target colony
      let moveOrder = FleetOrder(
        fleetId: fleet.id,
        orderType: FleetOrderType.Move,
        targetSystem: some(closestColony),
        targetFleet: none(FleetId),
        priority: order.priority
      )

      # Use centralized movement arbiter
      var events: seq[resolution_types.GameEvent] = @[]
      resolveMovementOrder(state, fleet.owner, moveOrder, events)

      # Check if fleet moved
      let updatedFleetOpt = state.getFleet(fleet.id)
      if updatedFleetOpt.isNone:
        return OrderOutcome.Failed

      let movedFleet = updatedFleetOpt.get()

      # Check if actually moved (pathfinding succeeded)
      if movedFleet.location == fleet.location:
        # Fleet didn't move - no path found
        events.add(event_factory.orderFailed(
          houseId = fleet.owner,
          fleetId = fleet.id,
          orderType = "Mothball",
          reason = "cannot reach colony",
          systemId = some(fleet.location)
        ))
        return OrderOutcome.Failed

      # Keep order persistent - will execute when fleet arrives
      # Silent - movement in progress
      return OrderOutcome.Success

  # At friendly colony with spaceport - apply mothball status
  var updatedFleet = fleet
  updatedFleet.status = FleetStatus.Mothballed
  state.fleets[fleet.id] = updatedFleet

  # Generate OrderCompleted event for state change
  events.add(event_factory.orderCompleted(
    fleet.owner,
    fleet.id,
    "Mothball",
    details = "mothballed",
    systemId = some(fleet.location)
  ))

  return OrderOutcome.Success

proc executeReactivateOrder(
  state: var GameState,
  fleet: Fleet,
  order: FleetOrder,
  events: var seq[resolution_types.GameEvent]
): OrderOutcome =
  ## Return reserve or mothballed fleet to active duty

  if fleet.status == FleetStatus.Active:
    events.add(event_factory.orderFailed(
      houseId = fleet.owner,
      fleetId = fleet.id,
      orderType = "Reactivate",
      reason = "fleet already active",
      systemId = some(fleet.location)
    ))
    return OrderOutcome.Failed

  # Change status to Active
  var updatedFleet = fleet
  updatedFleet.status = FleetStatus.Active
  state.fleets[fleet.id] = updatedFleet

  # Generate OrderCompleted event for state change
  events.add(event_factory.orderCompleted(
    fleet.owner,
    fleet.id,
    "Reactivate",
    details = "reactivated",
    systemId = some(fleet.location)
  ))

  return OrderOutcome.Success

# =============================================================================
# Order 19: View World (Long-Range Planetary Reconnaissance)
# =============================================================================

proc executeViewWorldOrder(
  state: var GameState,
  fleet: Fleet,
  order: FleetOrder,
  events: var seq[resolution_types.GameEvent]
): OrderOutcome =
  ## Order 19: Perform long-range scan of planet from system edge
  ## Gathers: planet owner (if colonized) + planet class (production potential)
  ## Resolution logic handled by resolveViewWorldOrder in fleet_orders.nim

  if order.targetSystem.isNone:
    events.add(event_factory.orderFailed(
      fleet.owner,
      fleet.id,
      "ViewWorld",
      reason = "no target system specified",
      systemId = some(fleet.location)
    ))
    return OrderOutcome.Failed

  return OrderOutcome.Success
