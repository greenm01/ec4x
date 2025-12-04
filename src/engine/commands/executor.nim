## Fleet Order Execution Engine
## Implements all 16 fleet order types from operations.md Section 6.2

import std/[options, tables]
import ../../common/types/[core, units]
import ../gamestate, ../orders, ../fleet, ../squadron, ../state_helpers, ../logger, ../starmap
import ../intelligence/detection
import ../combat/[types as combat_types]
import ../resolution/[types as resolution_types, fleet_orders]

type
  OrderExecutionResult* = object
    success*: bool
    message*: string
    eventsGenerated*: seq[string]

# =============================================================================
# Forward Declarations
# =============================================================================

proc executeHoldOrder(state: var GameState, fleet: Fleet, order: FleetOrder): OrderExecutionResult
proc executeMoveOrder(state: var GameState, fleet: Fleet, order: FleetOrder): OrderExecutionResult
proc executeSeekHomeOrder(state: var GameState, fleet: Fleet, order: FleetOrder): OrderExecutionResult
proc executePatrolOrder(state: var GameState, fleet: Fleet, order: FleetOrder): OrderExecutionResult
proc executeGuardStarbaseOrder(state: var GameState, fleet: Fleet, order: FleetOrder): OrderExecutionResult
proc executeGuardPlanetOrder(state: var GameState, fleet: Fleet, order: FleetOrder): OrderExecutionResult
proc executeBlockadeOrder(state: var GameState, fleet: Fleet, order: FleetOrder): OrderExecutionResult
proc executeBombardOrder(state: var GameState, fleet: Fleet, order: FleetOrder): OrderExecutionResult
proc executeInvadeOrder(state: var GameState, fleet: Fleet, order: FleetOrder): OrderExecutionResult
proc executeBlitzOrder(state: var GameState, fleet: Fleet, order: FleetOrder): OrderExecutionResult
proc executeSpyPlanetOrder(state: var GameState, fleet: Fleet, order: FleetOrder): OrderExecutionResult
proc executeHackStarbaseOrder(state: var GameState, fleet: Fleet, order: FleetOrder): OrderExecutionResult
proc executeSpySystemOrder(state: var GameState, fleet: Fleet, order: FleetOrder): OrderExecutionResult
proc executeColonizeOrder(state: var GameState, fleet: Fleet, order: FleetOrder): OrderExecutionResult
proc executeJoinFleetOrder(state: var GameState, fleet: Fleet, order: FleetOrder): OrderExecutionResult
proc executeRendezvousOrder(state: var GameState, fleet: Fleet, order: FleetOrder): OrderExecutionResult
proc executeSalvageOrder(state: var GameState, fleet: Fleet, order: FleetOrder): OrderExecutionResult
proc executeReserveOrder(state: var GameState, fleet: Fleet, order: FleetOrder): OrderExecutionResult
proc executeMothballOrder(state: var GameState, fleet: Fleet, order: FleetOrder): OrderExecutionResult
proc executeReactivateOrder(state: var GameState, fleet: Fleet, order: FleetOrder): OrderExecutionResult
proc executeViewWorldOrder(state: var GameState, fleet: Fleet, order: FleetOrder): OrderExecutionResult

# =============================================================================
# Order Execution Dispatcher
# =============================================================================

proc executeFleetOrder*(
  state: var GameState,
  houseId: HouseId,
  order: FleetOrder
): OrderExecutionResult =
  ## Main dispatcher for fleet order execution
  ## Routes to appropriate handler based on order type

  result = OrderExecutionResult(
    success: false,
    message: "Order not executed",
    eventsGenerated: @[]
  )

  # Validate fleet exists
  let fleetOpt = state.getFleet(order.fleetId)
  if fleetOpt.isNone:
    result.message = "Fleet " & $order.fleetId & " not found"
    return result

  let fleet = fleetOpt.get()

  # Validate fleet ownership
  if fleet.owner != houseId:
    result.message = "Fleet " & $order.fleetId & " not owned by house " & $houseId
    return result

  # Route to order type handler
  case order.orderType
  of FleetOrderType.Hold:
    result = executeHoldOrder(state, fleet, order)
  of FleetOrderType.Move:
    result = executeMoveOrder(state, fleet, order)
  of FleetOrderType.SeekHome:
    result = executeSeekHomeOrder(state, fleet, order)
  of FleetOrderType.Patrol:
    result = executePatrolOrder(state, fleet, order)
  of FleetOrderType.GuardStarbase:
    result = executeGuardStarbaseOrder(state, fleet, order)
  of FleetOrderType.GuardPlanet:
    result = executeGuardPlanetOrder(state, fleet, order)
  of FleetOrderType.BlockadePlanet:
    result = executeBlockadeOrder(state, fleet, order)
  of FleetOrderType.Bombard:
    result = executeBombardOrder(state, fleet, order)
  of FleetOrderType.Invade:
    result = executeInvadeOrder(state, fleet, order)
  of FleetOrderType.Blitz:
    result = executeBlitzOrder(state, fleet, order)
  of FleetOrderType.SpyPlanet:
    result = executeSpyPlanetOrder(state, fleet, order)
  of FleetOrderType.HackStarbase:
    result = executeHackStarbaseOrder(state, fleet, order)
  of FleetOrderType.SpySystem:
    result = executeSpySystemOrder(state, fleet, order)
  of FleetOrderType.Colonize:
    result = executeColonizeOrder(state, fleet, order)
  of FleetOrderType.JoinFleet:
    result = executeJoinFleetOrder(state, fleet, order)
  of FleetOrderType.Rendezvous:
    result = executeRendezvousOrder(state, fleet, order)
  of FleetOrderType.Salvage:
    result = executeSalvageOrder(state, fleet, order)
  of FleetOrderType.Reserve:
    result = executeReserveOrder(state, fleet, order)
  of FleetOrderType.Mothball:
    result = executeMothballOrder(state, fleet, order)
  of FleetOrderType.Reactivate:
    result = executeReactivateOrder(state, fleet, order)
  of FleetOrderType.ViewWorld:
    result = executeViewWorldOrder(state, fleet, order)

# =============================================================================
# Order 00: Hold Position
# =============================================================================

proc executeHoldOrder(
  state: var GameState,
  fleet: Fleet,
  order: FleetOrder
): OrderExecutionResult =
  ## Order 00: Hold position and standby
  ## Always succeeds - fleet does nothing this turn

  result = OrderExecutionResult(
    success: true,
    message: "Fleet " & $fleet.id & " holding position at " & $fleet.location,
    eventsGenerated: @[]
  )

# =============================================================================
# Order 01: Move Fleet
# =============================================================================

proc executeMoveOrder(
  state: var GameState,
  fleet: Fleet,
  order: FleetOrder
): OrderExecutionResult =
  ## Order 01: Move to new system and hold position
  ## Movement logic handled by resolveMovementOrder in resolve.nim
  ## This proc marks the order as executed

  # Per economy.md:3.9 - Reserve and Mothballed fleets cannot move
  if fleet.status == FleetStatus.Reserve:
    return OrderExecutionResult(
      success: false,
      message: "Reserve fleets cannot move - must be reactivated first",
      eventsGenerated: @[]
    )

  if fleet.status == FleetStatus.Mothballed:
    return OrderExecutionResult(
      success: false,
      message: "Mothballed fleets cannot move - must be reactivated first",
      eventsGenerated: @[]
    )

  if order.targetSystem.isNone:
    return OrderExecutionResult(
      success: false,
      message: "Move order requires target system",
      eventsGenerated: @[]
    )

  result = OrderExecutionResult(
    success: true,
    message: "Fleet " & $fleet.id & " moving to " & $order.targetSystem.get(),
    eventsGenerated: @["Fleet movement initiated"]
  )

# =============================================================================
# Order 02: Seek Home
# =============================================================================

proc executeSeekHomeOrder(
  state: var GameState,
  fleet: Fleet,
  order: FleetOrder
): OrderExecutionResult =
  ## Order 02: Find closest friendly colony and move there
  ## If that colony is conquered, find next closest

  # Find all friendly colonies
  var friendlyColonies: seq[SystemId] = @[]
  for colonyId, colony in state.colonies:
    if colony.owner == fleet.owner:
      friendlyColonies.add(colonyId)

  if friendlyColonies.len == 0:
    return OrderExecutionResult(
      success: false,
      message: "No friendly colonies found for fleet " & $fleet.id,
      eventsGenerated: @[]
    )

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

  result = OrderExecutionResult(
    success: true,
    message: "Fleet " & $fleet.id & " seeking home at " & $closestColony & " (" & $minDistance & " jumps)",
    eventsGenerated: @["Fleet seeking home (" & $minDistance & " jumps)"]
  )

# =============================================================================
# Order 03: Patrol System
# =============================================================================

proc executePatrolOrder(
  state: var GameState,
  fleet: Fleet,
  order: FleetOrder
): OrderExecutionResult =
  ## Order 03: Actively patrol system, engaging hostile forces
  ## Engagement rules per operations.md:6.2.4

  if order.targetSystem.isNone:
    return OrderExecutionResult(
      success: false,
      message: "Patrol order requires target system",
      eventsGenerated: @[]
    )

  let targetSystem = order.targetSystem.get()

  result = OrderExecutionResult(
    success: true,
    message: "Fleet " & $fleet.id & " patrolling " & $targetSystem,
    eventsGenerated: @["Fleet on patrol"]
  )

# =============================================================================
# Order 04: Guard Starbase
# =============================================================================

proc executeGuardStarbaseOrder(
  state: var GameState,
  fleet: Fleet,
  order: FleetOrder
): OrderExecutionResult =
  ## Order 04: Protect starbase, join Task Force when confronted
  ## Requires combat ships

  if order.targetSystem.isNone:
    return OrderExecutionResult(
      success: false,
      message: "Guard Starbase requires target system",
      eventsGenerated: @[]
    )

  # Check for combat capability
  var hasCombatShips = false
  for squadron in fleet.squadrons:
    if squadron.flagship.stats.attackStrength > 0:
      hasCombatShips = true
      break

  if not hasCombatShips:
    return OrderExecutionResult(
      success: false,
      message: "Guard Starbase requires combat-capable ships",
      eventsGenerated: @[]
    )

  let targetSystem = order.targetSystem.get()

  # Validate starbase presence and ownership
  if targetSystem notin state.colonies:
    return OrderExecutionResult(
      success: false,
      message: "No colony at " & $targetSystem & " for starbase guard duty",
      eventsGenerated: @[]
    )

  let colony = state.colonies[targetSystem]
  if colony.owner != fleet.owner:
    return OrderExecutionResult(
      success: false,
      message: "Cannot guard starbase at enemy colony " & $targetSystem,
      eventsGenerated: @[]
    )

  if colony.starbases.len == 0:
    return OrderExecutionResult(
      success: false,
      message: "No starbase at " & $targetSystem & " to guard",
      eventsGenerated: @[]
    )

  result = OrderExecutionResult(
    success: true,
    message: "Fleet " & $fleet.id & " guarding starbase at " & $targetSystem,
    eventsGenerated: @["Fleet guarding starbase"]
  )

# =============================================================================
# Order 05: Guard/Blockade Planet
# =============================================================================

proc executeGuardPlanetOrder(
  state: var GameState,
  fleet: Fleet,
  order: FleetOrder
): OrderExecutionResult =
  ## Order 05 (Guard): Protect friendly colony, rear guard position
  ## Does not auto-join starbase Task Force (allows Raiders)

  if order.targetSystem.isNone:
    return OrderExecutionResult(
      success: false,
      message: "Guard Planet requires target system",
      eventsGenerated: @[]
    )

  let targetSystem = order.targetSystem.get()

  # Check for combat capability
  var hasCombatShips = false
  for squadron in fleet.squadrons:
    if squadron.flagship.stats.attackStrength > 0:
      hasCombatShips = true
      break

  if not hasCombatShips:
    return OrderExecutionResult(
      success: false,
      message: "Guard Planet requires combat-capable ships",
      eventsGenerated: @[]
    )

  result = OrderExecutionResult(
    success: true,
    message: "Fleet " & $fleet.id & " guarding planet at " & $targetSystem,
    eventsGenerated: @["Fleet guarding colony"]
  )

proc executeBlockadeOrder(
  state: var GameState,
  fleet: Fleet,
  order: FleetOrder
): OrderExecutionResult =
  ## Order 05 (Blockade): Block enemy planet, reduce GCO by 60%
  ## Per operations.md:6.2.6 - Immediate effect during Income Phase
  ## Prestige penalty: -2 per turn if colony under blockade

  if order.targetSystem.isNone:
    return OrderExecutionResult(
      success: false,
      message: "Blockade requires target system",
      eventsGenerated: @[]
    )

  let targetSystem = order.targetSystem.get()

  # Check for combat capability
  var hasCombatShips = false
  for squadron in fleet.squadrons:
    if squadron.flagship.stats.attackStrength > 0:
      hasCombatShips = true
      break

  if not hasCombatShips:
    return OrderExecutionResult(
      success: false,
      message: "Blockade requires combat-capable ships",
      eventsGenerated: @[]
    )

  # Check target colony exists and is hostile
  if targetSystem notin state.colonies:
    return OrderExecutionResult(
      success: false,
      message: "No colony at " & $targetSystem & " to blockade",
      eventsGenerated: @[]
    )

  let colony = state.colonies[targetSystem]
  if colony.owner == fleet.owner:
    return OrderExecutionResult(
      success: false,
      message: "Cannot blockade own colony",
      eventsGenerated: @[]
    )

  # Validate target house is not eliminated (leaderboard is public info)
  if colony.owner in state.houses:
    let targetHouse = state.houses[colony.owner]
    if targetHouse.eliminated:
      return OrderExecutionResult(
        success: false,
        message: "Cannot blockade colony of eliminated house " & $colony.owner,
        eventsGenerated: @[]
      )

  # NOTE: Blockade tracking not yet implemented in Colony type
  # Blockade effects are calculated dynamically during Income Phase by checking
  # for BlockadePlanet fleet orders at colony systems (see income.nim)
  # Future enhancement: Add blockaded: bool field to Colony type for faster lookups

  result = OrderExecutionResult(
    success: true,
    message: "Fleet " & $fleet.id & " blockading " & $targetSystem,
    eventsGenerated: @[
      "Blockade established at " & $targetSystem,
      "Target colony GCO reduced by 60%"
    ]
  )

# =============================================================================
# Order 06: Bombard Planet
# =============================================================================

proc executeBombardOrder(
  state: var GameState,
  fleet: Fleet,
  order: FleetOrder
): OrderExecutionResult =
  ## Order 06: Orbital bombardment of planet
  ## Resolved in Conflict Phase - this marks intent

  if order.targetSystem.isNone:
    return OrderExecutionResult(
      success: false,
      message: "Bombard order requires target system",
      eventsGenerated: @[]
    )

  let targetSystem = order.targetSystem.get()

  # Check target colony exists
  if targetSystem notin state.colonies:
    return OrderExecutionResult(
      success: false,
      message: "No colony at " & $targetSystem & " to bombard",
      eventsGenerated: @[]
    )

  let colony = state.colonies[targetSystem]
  if colony.owner == fleet.owner:
    return OrderExecutionResult(
      success: false,
      message: "Cannot bombard own colony",
      eventsGenerated: @[]
    )

  # Validate target house is not eliminated (leaderboard is public info)
  if colony.owner in state.houses:
    let targetHouse = state.houses[colony.owner]
    if targetHouse.eliminated:
      return OrderExecutionResult(
        success: false,
        message: "Cannot bombard colony of eliminated house " & $colony.owner,
        eventsGenerated: @[]
      )

  # Check for combat capability
  var hasCombatShips = false
  for squadron in fleet.squadrons:
    if squadron.flagship.stats.attackStrength > 0:
      hasCombatShips = true
      break

  if not hasCombatShips:
    return OrderExecutionResult(
      success: false,
      message: "Bombardment requires combat-capable ships",
      eventsGenerated: @[]
    )

  result = OrderExecutionResult(
    success: true,
    message: "Fleet " & $fleet.id & " preparing bombardment of " & $targetSystem,
    eventsGenerated: @["Bombardment order issued"]
  )

# =============================================================================
# Order 07: Invade Planet
# =============================================================================

proc executeInvadeOrder(
  state: var GameState,
  fleet: Fleet,
  order: FleetOrder
): OrderExecutionResult =
  ## Order 07: Three-round planetary invasion
  ## 1) Destroy ground batteries
  ## 2) Pound population/ground troops
  ## 3) Land Marines (if batteries destroyed)

  if order.targetSystem.isNone:
    return OrderExecutionResult(
      success: false,
      message: "Invasion requires target system",
      eventsGenerated: @[]
    )

  let targetSystem = order.targetSystem.get()

  # Check target colony exists
  if targetSystem notin state.colonies:
    return OrderExecutionResult(
      success: false,
      message: "No colony at " & $targetSystem & " to invade",
      eventsGenerated: @[]
    )

  let colony = state.colonies[targetSystem]
  if colony.owner == fleet.owner:
    return OrderExecutionResult(
      success: false,
      message: "Cannot invade own colony",
      eventsGenerated: @[]
    )

  # Validate target house is not eliminated (leaderboard is public info)
  if colony.owner in state.houses:
    let targetHouse = state.houses[colony.owner]
    if targetHouse.eliminated:
      return OrderExecutionResult(
        success: false,
        message: "Cannot invade colony of eliminated house " & $colony.owner,
        eventsGenerated: @[]
      )

  # Check for combat ships and loaded troop transports
  var hasCombatShips = false
  var hasLoadedTransports = false

  for squadron in fleet.squadrons:
    if squadron.flagship.stats.attackStrength > 0:
      hasCombatShips = true

  # Check spacelift ships for loaded marines
  for ship in fleet.spaceLiftShips:
    if ship.shipClass == ShipClass.TroopTransport and
       ship.cargo.cargoType == CargoType.Marines and
       ship.cargo.quantity > 0:
      hasLoadedTransports = true
      break

  if not hasCombatShips:
    return OrderExecutionResult(
      success: false,
      message: "Invasion requires combat ships",
      eventsGenerated: @[]
    )

  if not hasLoadedTransports:
    return OrderExecutionResult(
      success: false,
      message: "Invasion requires loaded Troop Transports",
      eventsGenerated: @[]
    )

  result = OrderExecutionResult(
    success: true,
    message: "Fleet " & $fleet.id & " launching invasion of " & $targetSystem,
    eventsGenerated: @["Invasion order issued"]
  )

# =============================================================================
# Order 08: Blitz Planet
# =============================================================================

proc executeBlitzOrder(
  state: var GameState,
  fleet: Fleet,
  order: FleetOrder
): OrderExecutionResult =
  ## Order 08: Fast assault - dodge batteries, drop Marines
  ## Less planet damage, but requires 2:1 Marine superiority
  ## Per operations.md:6.2.9

  if order.targetSystem.isNone:
    return OrderExecutionResult(
      success: false,
      message: "Blitz requires target system",
      eventsGenerated: @[]
    )

  let targetSystem = order.targetSystem.get()

  # Check target colony exists
  if targetSystem notin state.colonies:
    return OrderExecutionResult(
      success: false,
      message: "No colony at " & $targetSystem & " to blitz",
      eventsGenerated: @[]
    )

  let colony = state.colonies[targetSystem]
  if colony.owner == fleet.owner:
    return OrderExecutionResult(
      success: false,
      message: "Cannot blitz own colony",
      eventsGenerated: @[]
    )

  # Validate target house is not eliminated (leaderboard is public info)
  if colony.owner in state.houses:
    let targetHouse = state.houses[colony.owner]
    if targetHouse.eliminated:
      return OrderExecutionResult(
        success: false,
        message: "Cannot blitz colony of eliminated house " & $colony.owner,
        eventsGenerated: @[]
      )

  # Check for loaded troop transports (spacelift ships, NOT squadrons)
  # Per ARCHITECTURE FIX 2025-11-23: Spacelift ships are separate from squadrons
  var hasLoadedTransports = false

  for spaceliftShip in fleet.spaceLiftShips:
    if spaceliftShip.shipClass == ShipClass.TroopTransport:
      # Check if transport has Marines loaded
      if spaceliftShip.cargo.cargoType == CargoType.Marines and spaceliftShip.cargo.quantity > 0:
        hasLoadedTransports = true
        break

  if not hasLoadedTransports:
    return OrderExecutionResult(
      success: false,
      message: "Blitz requires loaded Troop Transports",
      eventsGenerated: @[]
    )

  result = OrderExecutionResult(
    success: true,
    message: "Fleet " & $fleet.id & " executing blitz assault on " & $targetSystem,
    eventsGenerated: @["Blitz order issued"]
  )

# =============================================================================
# Order 09: Spy on Planet
# =============================================================================

proc executeSpyPlanetOrder(
  state: var GameState,
  fleet: Fleet,
  order: FleetOrder
): OrderExecutionResult =
  ## Order 09: Deploy scout to gather planet intelligence
  ## Reserved for solo Scout operations per operations.md:6.2.10

  if order.targetSystem.isNone:
    return OrderExecutionResult(
      success: false,
      message: "Spy Planet requires target system",
      eventsGenerated: @[]
    )

  let targetSystem = order.targetSystem.get()

  # Validate target house is not eliminated (leaderboard is public info)
  if targetSystem in state.colonies:
    let colony = state.colonies[targetSystem]
    if colony.owner in state.houses:
      let targetHouse = state.houses[colony.owner]
      if targetHouse.eliminated:
        return OrderExecutionResult(
          success: false,
          message: "Cannot spy on eliminated house " & $colony.owner,
          eventsGenerated: @[]
        )

  # Count scouts for mesh network bonus (validation already confirmed scout-only fleet)
  var totalScouts = 0
  var scoutELI = 0  # Use first scout's ELI level

  for squadron in fleet.squadrons:
    totalScouts += 1
    if scoutELI == 0:  # Take ELI from first scout
      scoutELI = squadron.flagship.stats.techLevel

  # Deploy spy scout (already validated targetSystem above)

  # Calculate jump lane path from current location to target
  let path = findPath(state.starMap, fleet.location, targetSystem, fleet)

  if path.path.len == 0:
    return OrderExecutionResult(
      success: false,
      message: "No jump lane route to " & $targetSystem,
      eventsGenerated: @[]
    )

  # Create spy scout with travel state
  let spyId = "spy-" & $fleet.owner & "-" & $state.turn & "-" & $targetSystem
  let spyScout = SpyScout(
    id: spyId,
    owner: fleet.owner,
    location: fleet.location,           # Starting location (not target)
    eliLevel: scoutELI,
    mission: SpyMissionType.SpyOnPlanet,
    commissionedTurn: state.turn,
    detected: false,
    # NEW: Travel tracking
    state: SpyScoutState.Traveling,     # Traveling state
    targetSystem: targetSystem,          # Final destination
    travelPath: path.path,               # Jump lane route
    currentPathIndex: 0,                 # Start at beginning
    mergedScoutCount: totalScouts        # All scouts in fleet (mesh network bonus)
  )

  state.spyScouts[spyId] = spyScout

  # Remove ALL scouts from fleet (they all become the spy scout)
  var updatedFleet = fleet
  updatedFleet.squadrons = @[]  # Clear all squadrons (validated as scout-only)

  # Check if fleet is now empty and clean up if needed
  if updatedFleet.isEmpty():
    # Fleet is empty (no squadrons AND no spacelift ships) - remove it completely
    state.fleets.del(fleet.id)
    if fleet.id in state.fleetOrders:
      state.fleetOrders.del(fleet.id)
    if fleet.id in state.standingOrders:
      state.standingOrders.del(fleet.id)
    logInfo(LogCategory.lcFleet, "Removed empty fleet " & $fleet.id & " after scout deployment (Order 09: Spy on Planet)")
  else:
    # Fleet still has squadrons - update it
    state.fleets[fleet.id] = updatedFleet

  result = OrderExecutionResult(
    success: true,
    message: "Scout deployed, traveling to " & $targetSystem & " (" & $path.path.len & " jumps)",
    eventsGenerated: @[
      "Spy scout deployed (ELI " & $scoutELI & ")",
      "Scout traveling to target via jump lanes"
    ]
  )

# =============================================================================
# Order 10: Hack Starbase
# =============================================================================

proc executeHackStarbaseOrder(
  state: var GameState,
  fleet: Fleet,
  order: FleetOrder
): OrderExecutionResult =
  ## Order 10: Electronic warfare against starbase
  ## Reserved for Scout operations per operations.md:6.2.11

  if order.targetSystem.isNone:
    return OrderExecutionResult(
      success: false,
      message: "Hack Starbase requires target system",
      eventsGenerated: @[]
    )

  let targetSystem = order.targetSystem.get()

  # Validate starbase presence at target
  if targetSystem notin state.colonies:
    return OrderExecutionResult(
      success: false,
      message: "No colony at " & $targetSystem & " for starbase hacking",
      eventsGenerated: @[]
    )

  let colony = state.colonies[targetSystem]
  if colony.starbases.len == 0:
    return OrderExecutionResult(
      success: false,
      message: "No starbase at " & $targetSystem & " to hack",
      eventsGenerated: @[]
    )

  # Validate target house is not eliminated (leaderboard is public info)
  if colony.owner in state.houses:
    let targetHouse = state.houses[colony.owner]
    if targetHouse.eliminated:
      return OrderExecutionResult(
        success: false,
        message: "Cannot hack starbase of eliminated house " & $colony.owner,
        eventsGenerated: @[]
      )

  # Count scouts for mesh network bonus (validation already confirmed scout-only fleet)
  var totalScouts = 0
  var scoutELI = 0  # Use first scout's ELI level

  for squadron in fleet.squadrons:
    totalScouts += 1
    if scoutELI == 0:  # Take ELI from first scout
      scoutELI = squadron.flagship.stats.techLevel

  # Calculate jump lane path from current location to target
  let path = findPath(state.starMap, fleet.location, targetSystem, fleet)

  if path.path.len == 0:
    return OrderExecutionResult(
      success: false,
      message: "No jump lane route to " & $targetSystem,
      eventsGenerated: @[]
    )

  # Create spy scout with travel state
  let spyId = "spy-" & $fleet.owner & "-" & $state.turn & "-" & $targetSystem
  let spyScout = SpyScout(
    id: spyId,
    owner: fleet.owner,
    location: fleet.location,           # Starting location (not target)
    eliLevel: scoutELI,
    mission: SpyMissionType.HackStarbase,
    commissionedTurn: state.turn,
    detected: false,
    # NEW: Travel tracking
    state: SpyScoutState.Traveling,     # Traveling state
    targetSystem: targetSystem,          # Final destination
    travelPath: path.path,               # Jump lane route
    currentPathIndex: 0,                 # Start at beginning
    mergedScoutCount: totalScouts        # All scouts in fleet (mesh network bonus)
  )

  state.spyScouts[spyId] = spyScout

  # Remove ALL scouts from fleet (they all become the spy scout)
  var updatedFleet = fleet
  updatedFleet.squadrons = @[]  # Clear all squadrons (validated as scout-only)

  # Check if fleet is now empty and clean up if needed
  if updatedFleet.isEmpty():
    # Fleet is empty (no squadrons AND no spacelift ships) - remove it completely
    state.fleets.del(fleet.id)
    if fleet.id in state.fleetOrders:
      state.fleetOrders.del(fleet.id)
    if fleet.id in state.standingOrders:
      state.standingOrders.del(fleet.id)
    logInfo(LogCategory.lcFleet, "Removed empty fleet " & $fleet.id & " after scout deployment (Order 10: Hack Starbase)")
  else:
    # Fleet still has squadrons - update it
    state.fleets[fleet.id] = updatedFleet

  result = OrderExecutionResult(
    success: true,
    message: "Scout deployed, traveling to " & $targetSystem & " (" & $path.path.len & " jumps)",
    eventsGenerated: @[
      "Spy scout deployed (ELI " & $scoutELI & ")",
      "Scout traveling to hack starbase"
    ]
  )

# =============================================================================
# Order 11: Spy on System
# =============================================================================

proc executeSpySystemOrder(
  state: var GameState,
  fleet: Fleet,
  order: FleetOrder
): OrderExecutionResult =
  ## Order 11: Deploy scout for system reconnaissance
  ## Reserved for solo Scout operations per operations.md:6.2.12

  if order.targetSystem.isNone:
    return OrderExecutionResult(
      success: false,
      message: "Spy System requires target system",
      eventsGenerated: @[]
    )

  let targetSystem = order.targetSystem.get()

  # Validate target house is not eliminated (leaderboard is public info)
  if targetSystem in state.colonies:
    let colony = state.colonies[targetSystem]
    if colony.owner in state.houses:
      let targetHouse = state.houses[colony.owner]
      if targetHouse.eliminated:
        return OrderExecutionResult(
          success: false,
          message: "Cannot spy on system of eliminated house " & $colony.owner,
          eventsGenerated: @[]
        )

  # Count scouts for mesh network bonus (validation already confirmed scout-only fleet)
  var totalScouts = 0
  var scoutELI = 0  # Use first scout's ELI level

  for squadron in fleet.squadrons:
    totalScouts += 1
    if scoutELI == 0:  # Take ELI from first scout
      scoutELI = squadron.flagship.stats.techLevel

  # Calculate jump lane path from current location to target
  let path = findPath(state.starMap, fleet.location, targetSystem, fleet)

  if path.path.len == 0:
    return OrderExecutionResult(
      success: false,
      message: "No jump lane route to " & $targetSystem,
      eventsGenerated: @[]
    )

  # Create spy scout with travel state
  let spyId = "spy-" & $fleet.owner & "-" & $state.turn & "-" & $targetSystem
  let spyScout = SpyScout(
    id: spyId,
    owner: fleet.owner,
    location: fleet.location,           # Starting location (not target)
    eliLevel: scoutELI,
    mission: SpyMissionType.SpyOnSystem,
    commissionedTurn: state.turn,
    detected: false,
    # NEW: Travel tracking
    state: SpyScoutState.Traveling,     # Traveling state
    targetSystem: targetSystem,          # Final destination
    travelPath: path.path,               # Jump lane route
    currentPathIndex: 0,                 # Start at beginning
    mergedScoutCount: totalScouts        # All scouts in fleet (mesh network bonus)
  )

  state.spyScouts[spyId] = spyScout

  # Remove ALL scouts from fleet (they all become the spy scout)
  var updatedFleet = fleet
  updatedFleet.squadrons = @[]  # Clear all squadrons (validated as scout-only)

  # Check if fleet is now empty and clean up if needed
  if updatedFleet.isEmpty():
    # Fleet is empty (no squadrons AND no spacelift ships) - remove it completely
    state.fleets.del(fleet.id)
    if fleet.id in state.fleetOrders:
      state.fleetOrders.del(fleet.id)
    if fleet.id in state.standingOrders:
      state.standingOrders.del(fleet.id)
    logInfo(LogCategory.lcFleet, "Removed empty fleet " & $fleet.id & " after scout deployment (Order 11: Spy on System)")
  else:
    # Fleet still has squadrons - update it
    state.fleets[fleet.id] = updatedFleet

  result = OrderExecutionResult(
    success: true,
    message: "Scout deployed, traveling to " & $targetSystem & " (" & $path.path.len & " jumps)",
    eventsGenerated: @[
      "Spy scout deployed (ELI " & $scoutELI & ")",
      "Scout traveling to survey system"
    ]
  )

# =============================================================================
# Order 12: Colonize Planet
# =============================================================================

proc executeColonizeOrder(
  state: var GameState,
  fleet: Fleet,
  order: FleetOrder
): OrderExecutionResult =
  ## Order 12: Establish colony with ETAC
  ## Reserved for ETAC under fleet escort per operations.md:6.2.13
  ## Colonization logic handled in resolve.nim

  if order.targetSystem.isNone:
    return OrderExecutionResult(
      success: false,
      message: "Colonize requires target system",
      eventsGenerated: @[]
    )

  # Check fleet has ETAC with loaded colonists
  var hasLoadedETAC = false

  for ship in fleet.spaceLiftShips:
    if ship.shipClass == ShipClass.ETAC and
       ship.cargo.cargoType == CargoType.Colonists and
       ship.cargo.quantity > 0:
      hasLoadedETAC = true
      break

  if not hasLoadedETAC:
    return OrderExecutionResult(
      success: false,
      message: "Colonize requires ETAC with loaded colonists (PTU)",
      eventsGenerated: @[]
    )

  result = OrderExecutionResult(
    success: true,
    message: "Fleet " & $fleet.id & " colonizing planet",
    eventsGenerated: @["Colonization order issued"]
  )

# =============================================================================
# Order 13: Join Fleet
# =============================================================================

proc executeJoinFleetOrder(
  state: var GameState,
  fleet: Fleet,
  order: FleetOrder
): OrderExecutionResult =
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
    return OrderExecutionResult(
      success: false,
      message: "Join Fleet requires target fleet",
      eventsGenerated: @[]
    )

  let targetFleetId = order.targetFleet.get()

  # Check if target is a SpyScout object
  if targetFleetId in state.spyScouts:
    # Normal fleet joining spy scout - convert spy scout to squadrons, merge into normal fleet
    let spyScout = state.spyScouts[targetFleetId]

    # Check same owner
    if spyScout.owner != fleet.owner:
      return OrderExecutionResult(
        success: false,
        message: "Cannot join spy scout owned by different house",
        eventsGenerated: @[]
      )

    # Check same location
    if spyScout.location != fleet.location:
      return OrderExecutionResult(
        success: false,
        message: "Fleet and spy scout must be at same location to join",
        eventsGenerated: @[]
      )

    # Convert spy scout back to squadrons
    var updatedFleet = fleet
    let scoutShip = newEnhancedShip(ShipClass.Scout, techLevel = spyScout.eliLevel)

    for i in 0..<spyScout.mergedScoutCount:
      let squadron = newSquadron(scoutShip, spyScout.id & "-sq-" & $i, spyScout.owner, spyScout.location)
      updatedFleet.squadrons.add(squadron)

    # Update the normal fleet (now contains scouts)
    state.fleets[fleet.id] = updatedFleet

    # Remove spy scout object
    state.spyScouts.del(targetFleetId)
    if targetFleetId in state.spyScoutOrders:
      state.spyScoutOrders.del(targetFleetId)

    logInfo(LogCategory.lcFleet, "Fleet " & $fleet.id & " absorbed spy scout " & $targetFleetId &
            " (" & $spyScout.mergedScoutCount & " scout squadrons added)")

    return OrderExecutionResult(
      success: true,
      message: "Fleet " & $fleet.id & " absorbed spy scout " & $targetFleetId &
              " (" & $spyScout.mergedScoutCount & " scouts merged)",
      eventsGenerated: @["Spy scout " & $targetFleetId & " merged into fleet " & $fleet.id]
    )

  # Target is a normal fleet
  let targetFleetOpt = state.getFleet(targetFleetId)

  if targetFleetOpt.isNone:
    # Target fleet destroyed or deleted - clear the order and fall back to standing orders
    # Standing orders will be used automatically by the order resolution system
    if fleet.id in state.fleetOrders:
      state.fleetOrders.del(fleet.id)

    return OrderExecutionResult(
      success: false,
      message: "Target fleet " & $targetFleetId & " not found (destroyed or deleted). Order cancelled, falling back to standing orders.",
      eventsGenerated: @["Fleet " & $fleet.id & " order cancelled: target " & $targetFleetId & " no longer exists"]
    )

  let targetFleet = targetFleetOpt.get()

  # Check same owner
  if targetFleet.owner != fleet.owner:
    return OrderExecutionResult(
      success: false,
      message: "Cannot join fleet owned by different house",
      eventsGenerated: @[]
    )

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
      return OrderExecutionResult(
        success: false,
        message: "Fleet " & $fleet.id & " disappeared during movement",
        eventsGenerated: @[]
      )

    let movedFleet = updatedFleetOpt.get()

    # Check if fleet actually moved (pathfinding succeeded)
    if movedFleet.location == fleet.location:
      # Fleet didn't move - no path found to target
      # Cancel order and fall back to standing orders
      if fleet.id in state.fleetOrders:
        state.fleetOrders.del(fleet.id)

      return OrderExecutionResult(
        success: false,
        message: "No path to target fleet " & $targetFleetId & " at system " & $targetFleet.location & ". Order cancelled.",
        eventsGenerated: @["Fleet " & $fleet.id & " cannot reach target"]
      )

    # If still not at target location, keep order persistent
    if movedFleet.location != targetFleet.location:
      # Keep the Join Fleet order active so it continues pursuit next turn
      # Order remains in fleetOrders table
      return OrderExecutionResult(
        success: true,
        message: "Fleet " & $fleet.id & " moving toward " & $targetFleetId & " (now at system " & $movedFleet.location & ")",
        eventsGenerated: @["Fleet " & $fleet.id & " pursuing " & $targetFleetId]
      )

    # If we got here, fleet reached target - fall through to merge logic below

  # At same location - merge squadrons and spacelift ships into target fleet
  var updatedTargetFleet = targetFleet
  for squadron in fleet.squadrons:
    updatedTargetFleet.squadrons.add(squadron)
  for ship in fleet.spaceLiftShips:
    updatedTargetFleet.spaceLiftShips.add(ship)

  state.fleets[targetFleetId] = updatedTargetFleet

  # Remove source fleet and clean up orders
  state.fleets.del(fleet.id)
  if fleet.id in state.fleetOrders:
    state.fleetOrders.del(fleet.id)
  if fleet.id in state.standingOrders:
    state.standingOrders.del(fleet.id)

  logInfo(LogCategory.lcFleet, "Fleet " & $fleet.id & " merged into fleet " & $targetFleetId & " (source fleet removed)")

  result = OrderExecutionResult(
    success: true,
    message: "Fleet " & $fleet.id & " joining " & $targetFleetId & " (" & $fleet.squadrons.len & " squadrons merged)",
    eventsGenerated: @["Fleet " & $fleet.id & " merged into " & $targetFleetId]
  )

# =============================================================================
# Order 14: Rendezvous
# =============================================================================

proc executeRendezvousOrder(
  state: var GameState,
  fleet: Fleet,
  order: FleetOrder
): OrderExecutionResult =
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
    return OrderExecutionResult(
      success: false,
      message: "Rendezvous requires target system",
      eventsGenerated: @[]
    )

  let targetSystem = order.targetSystem.get()

  # Check if fleet is at rendezvous point
  if fleet.location != targetSystem:
    # Still moving to rendezvous
    result = OrderExecutionResult(
      success: true,
      message: "Fleet " & $fleet.id & " moving to rendezvous at " & $targetSystem,
      eventsGenerated: @["Rendezvous movement initiated"]
    )
    return result

  # Find other fleets at rendezvous with same order at same location
  var rendezvousFleets: seq[Fleet] = @[]
  rendezvousFleets.add(fleet)

  # Collect spy scouts with Rendezvous orders at this system
  var rendezvousSpyScouts: seq[SpyScout] = @[]
  for spyScoutId, spyScout in state.spyScouts:
    # Check if at same location and owned by same house
    if spyScout.location == targetSystem and spyScout.owner == fleet.owner:
      # Check if has Rendezvous order to same system
      if spyScoutId in state.spyScoutOrders:
        let spyOrder = state.spyScoutOrders[spyScoutId]
        if spyOrder.orderType == SpyScoutOrderType.Rendezvous and
           spyOrder.targetSystem.isSome and
           spyOrder.targetSystem.get() == targetSystem:
          rendezvousSpyScouts.add(spyScout)

  # Collect all fleets with Rendezvous orders at this system
  for fleetId, otherFleet in state.fleets:
    if fleetId == fleet.id:
      continue  # Skip self

    # Check if at same location and owned by same house
    if otherFleet.location == targetSystem and otherFleet.owner == fleet.owner:
      # Check if has Rendezvous order to same system
      if fleetId in state.fleetOrders:
        let otherOrder = state.fleetOrders[fleetId]
        if otherOrder.orderType == FleetOrderType.Rendezvous and
           otherOrder.targetSystem.isSome and
           otherOrder.targetSystem.get() == targetSystem:
          rendezvousFleets.add(otherFleet)

  # If only this fleet and no spy scouts, wait for others
  if rendezvousFleets.len == 1 and rendezvousSpyScouts.len == 0:
    return OrderExecutionResult(
      success: true,
      message: "Fleet " & $fleet.id & " waiting at rendezvous point " & $targetSystem,
      eventsGenerated: @["At rendezvous point, waiting for other fleets"]
    )

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

    # Merge squadrons and spacelift ships
    for squadron in f.squadrons:
      hostFleet.squadrons.add(squadron)
    for ship in f.spaceLiftShips:
      hostFleet.spaceLiftShips.add(ship)

    # Remove merged fleet and clean up orders
    state.fleets.del(f.id)
    if f.id in state.fleetOrders:
      state.fleetOrders.del(f.id)
    if f.id in state.standingOrders:
      state.standingOrders.del(f.id)

    mergedCount += 1
    logInfo(LogCategory.lcFleet, "Fleet " & $f.id & " merged into rendezvous host " & $lowestId & " (source fleet removed)")

  # Merge spy scouts into host fleet (convert to squadrons)
  var scoutsMerged = 0
  for spyScout in rendezvousSpyScouts:
    let scoutShip = newEnhancedShip(ShipClass.Scout, techLevel = spyScout.eliLevel)

    for i in 0..<spyScout.mergedScoutCount:
      let squadron = newSquadron(scoutShip, spyScout.id & "-sq-" & $i, spyScout.owner, spyScout.location)
      hostFleet.squadrons.add(squadron)

    # Remove spy scout object
    state.spyScouts.del(spyScout.id)
    if spyScout.id in state.spyScoutOrders:
      state.spyScoutOrders.del(spyScout.id)

    scoutsMerged += spyScout.mergedScoutCount
    logInfo(LogCategory.lcFleet, "Spy scout " & $spyScout.id & " merged into rendezvous host " & $lowestId &
            " (" & $spyScout.mergedScoutCount & " scout squadrons added)")

  # Update host fleet
  state.fleets[lowestId] = hostFleet

  var message = "Rendezvous complete at " & $targetSystem & ": " & $mergedCount & " fleets merged into " & $lowestId
  if scoutsMerged > 0:
    message = message & ", " & $scoutsMerged & " scouts merged"

  result = OrderExecutionResult(
    success: true,
    message: message,
    eventsGenerated: @["Rendezvous complete: " & $(rendezvousFleets.len) & " fleets merged"]
  )

# =============================================================================
# Order 15: Salvage
# =============================================================================

proc executeSalvageOrder(
  state: var GameState,
  fleet: Fleet,
  order: FleetOrder
): OrderExecutionResult =
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
  if closestColony.isNone:
    for colonyId, colony in state.colonies:
      if colony.owner == fleet.owner:
        # Check if colony has salvage facilities
        let hasFacilities = colony.spaceports.len > 0 or colony.shipyards.len > 0

        if hasFacilities:
          closestColony = some(colonyId)
          break

  if closestColony.isNone:
    return OrderExecutionResult(
      success: false,
      message: "No friendly colony with spaceport or shipyard found for salvage",
      eventsGenerated: @[]
    )

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
  state.fleets.del(fleet.id)
  if fleet.id in state.fleetOrders:
    state.fleetOrders.del(fleet.id)
  if fleet.id in state.standingOrders:
    state.standingOrders.del(fleet.id)

  result = OrderExecutionResult(
    success: true,
    message: "Fleet " & $fleet.id & " salvaged " & transitMessage & " for " & $salvageValue & " PP",
    eventsGenerated: @[
      "Fleet " & $fleet.id & " salvaged",
      "Recovered " & $salvageValue & " PP from " & $fleet.squadrons.len & " squadron(s)"
    ]
  )

# =============================================================================
# Reserve / Mothball / Reactivate Orders
# =============================================================================

proc executeReserveOrder(
  state: var GameState,
  fleet: Fleet,
  order: FleetOrder
): OrderExecutionResult =
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
      return OrderExecutionResult(
        success: false,
        message: "No friendly colonies available for reserve status",
        eventsGenerated: @[]
      )

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
        return OrderExecutionResult(
          success: false,
          message: "Fleet " & $fleet.id & " disappeared during movement",
          eventsGenerated: @[]
        )

      let movedFleet = updatedFleetOpt.get()

      # Check if actually moved (pathfinding succeeded)
      if movedFleet.location == fleet.location:
        # Fleet didn't move - no path found
        return OrderExecutionResult(
          success: false,
          message: "No path to nearest friendly colony. Order cancelled.",
          eventsGenerated: @["Fleet " & $fleet.id & " cannot reach colony"]
        )

      # Keep order persistent - will execute when fleet arrives
      return OrderExecutionResult(
        success: true,
        message: "Fleet " & $fleet.id & " moving to colony for reserve status (" & $minDistance & " jumps)",
        eventsGenerated: @["Fleet seeking colony for Reserve"]
      )

  # At friendly colony - apply reserve status
  var updatedFleet = fleet
  updatedFleet.status = FleetStatus.Reserve
  state.fleets[fleet.id] = updatedFleet

  result = OrderExecutionResult(
    success: true,
    message: "Fleet " & $fleet.id & " placed on reserve at " & $fleet.location & " (50% maint, half AS/DS)",
    eventsGenerated: @["Fleet " & $fleet.id & " placed on reserve status"]
  )

proc executeMothballOrder(
  state: var GameState,
  fleet: Fleet,
  order: FleetOrder
): OrderExecutionResult =
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
      return OrderExecutionResult(
        success: false,
        message: "No friendly colonies with spaceports available for mothball",
        eventsGenerated: @[]
      )

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
        return OrderExecutionResult(
          success: false,
          message: "Fleet " & $fleet.id & " disappeared during movement",
          eventsGenerated: @[]
        )

      let movedFleet = updatedFleetOpt.get()

      # Check if actually moved (pathfinding succeeded)
      if movedFleet.location == fleet.location:
        # Fleet didn't move - no path found
        return OrderExecutionResult(
          success: false,
          message: "No path to nearest colony with spaceport. Order cancelled.",
          eventsGenerated: @["Fleet " & $fleet.id & " cannot reach colony"]
        )

      # Keep order persistent - will execute when fleet arrives
      return OrderExecutionResult(
        success: true,
        message: "Fleet " & $fleet.id & " moving to colony for mothball (" & $minDistance & " jumps)",
        eventsGenerated: @["Fleet seeking colony for Mothball"]
      )

  # At friendly colony with spaceport - apply mothball status
  var updatedFleet = fleet
  updatedFleet.status = FleetStatus.Mothballed
  state.fleets[fleet.id] = updatedFleet

  result = OrderExecutionResult(
    success: true,
    message: "Fleet " & $fleet.id & " mothballed at " & $fleet.location & " (0% maint, offline)",
    eventsGenerated: @["Fleet " & $fleet.id & " mothballed"]
  )

proc executeReactivateOrder(
  state: var GameState,
  fleet: Fleet,
  order: FleetOrder
): OrderExecutionResult =
  ## Return reserve or mothballed fleet to active duty

  if fleet.status == FleetStatus.Active:
    return OrderExecutionResult(
      success: false,
      message: "Fleet is already on active duty"
    )

  result = OrderExecutionResult(
    success: true,
    message: "Fleet " & $fleet.id & " returned to active duty",
    eventsGenerated: @["Fleet reactivated"]
  )

# =============================================================================
# Order 19: View World (Long-Range Planetary Reconnaissance)
# =============================================================================

proc executeViewWorldOrder(
  state: var GameState,
  fleet: Fleet,
  order: FleetOrder
): OrderExecutionResult =
  ## Order 19: Perform long-range scan of planet from system edge
  ## Gathers: planet owner (if colonized) + planet class (production potential)
  ## Resolution logic handled by resolveViewWorldOrder in fleet_orders.nim

  if order.targetSystem.isNone:
    return OrderExecutionResult(
      success: false,
      message: "View World order requires target system",
      eventsGenerated: @[]
    )

  result = OrderExecutionResult(
    success: true,
    message: "Fleet " & $fleet.id & " viewing world at " & $order.targetSystem.get(),
    eventsGenerated: @["Long-range planetary scan initiated"]
  )
