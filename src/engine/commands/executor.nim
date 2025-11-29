## Fleet Order Execution Engine
## Implements all 16 fleet order types from operations.md Section 6.2

import std/[options, tables]
import ../../common/types/[core, units]
import ../gamestate, ../orders, ../fleet, ../squadron, ../state_helpers, ../logger
import ../intelligence/detection
import ../combat/[types as combat_types]

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

  # Find closest colony (simple distance calculation)
  # TODO: Use proper pathfinding when starmap has coordinate system
  let targetColony = friendlyColonies[0]

  result = OrderExecutionResult(
    success: true,
    message: "Fleet " & $fleet.id & " seeking home at " & $targetColony,
    eventsGenerated: @["Fleet seeking home"]
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

  # Check starbase exists in target system
  # TODO: Validate starbase presence once starbase tracking added to GameState

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

  # Mark colony as blockaded
  # TODO: Add blockade tracking to Colony type

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
    message: "Fleet " & $fleet.id & " preparing bombardment",
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
    message: "Fleet " & $fleet.id & " launching invasion",
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
    message: "Fleet " & $fleet.id & " executing blitz assault",
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

  # Check fleet has exactly one Scout
  var scoutCount = 0
  var scoutELI = 0

  for squadron in fleet.squadrons:
    if squadron.flagship.shipClass == ShipClass.Scout:
      scoutCount += 1
      scoutELI = squadron.flagship.stats.techLevel

  if scoutCount != 1:
    return OrderExecutionResult(
      success: false,
      message: "Spy Planet requires exactly one Scout (found " & $scoutCount & ")",
      eventsGenerated: @[]
    )

  # Deploy spy scout
  let targetSystem = order.targetSystem.get()

  # Create spy scout and add to game state
  let spyId = "spy-" & $fleet.owner & "-" & $state.turn & "-" & $targetSystem
  let spyScout = SpyScout(
    id: spyId,
    owner: fleet.owner,
    location: targetSystem,
    eliLevel: scoutELI,
    mission: SpyMissionType.SpyOnPlanet,
    commissionedTurn: state.turn,
    detected: false
  )

  state.spyScouts[spyId] = spyScout

  # Remove scout from fleet (it operates independently now, permanently consumed)
  var updatedFleet = fleet
  for i in 0..<updatedFleet.squadrons.len:
    if updatedFleet.squadrons[i].flagship.shipClass == ShipClass.Scout:
      updatedFleet.squadrons.delete(i)
      break

  # Check if fleet is now empty and clean up if needed
  if updatedFleet.squadrons.len == 0:
    # Fleet is empty - remove it completely
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
    message: "Scout deployed to spy on planet at " & $targetSystem,
    eventsGenerated: @[
      "Spy scout deployed (ELI " & $scoutELI & ")",
      "Intelligence gathering mission started"
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
  ## Reserved for solo Scout operations per operations.md:6.2.11

  if order.targetSystem.isNone:
    return OrderExecutionResult(
      success: false,
      message: "Hack Starbase requires target system",
      eventsGenerated: @[]
    )

  # Check fleet has exactly one Scout
  var scoutCount = 0
  var scoutELI = 0

  for squadron in fleet.squadrons:
    if squadron.flagship.shipClass == ShipClass.Scout:
      scoutCount += 1
      scoutELI = squadron.flagship.stats.techLevel

  if scoutCount != 1:
    return OrderExecutionResult(
      success: false,
      message: "Hack Starbase requires exactly one Scout (found " & $scoutCount & ")",
      eventsGenerated: @[]
    )

  let targetSystem = order.targetSystem.get()

  # TODO: Check starbase exists at target

  # Create spy scout and add to game state
  let spyId = "spy-" & $fleet.owner & "-" & $state.turn & "-" & $targetSystem
  let spyScout = SpyScout(
    id: spyId,
    owner: fleet.owner,
    location: targetSystem,
    eliLevel: scoutELI,
    mission: SpyMissionType.HackStarbase,
    commissionedTurn: state.turn,
    detected: false
  )

  state.spyScouts[spyId] = spyScout

  # Remove scout from fleet (it operates independently now, permanently consumed)
  var updatedFleet = fleet
  for i in 0..<updatedFleet.squadrons.len:
    if updatedFleet.squadrons[i].flagship.shipClass == ShipClass.Scout:
      updatedFleet.squadrons.delete(i)
      break

  # Check if fleet is now empty and clean up if needed
  if updatedFleet.squadrons.len == 0:
    # Fleet is empty - remove it completely
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
    message: "Scout infiltrating starbase at " & $targetSystem,
    eventsGenerated: @[
      "Spy scout deployed (ELI " & $scoutELI & ")",
      "Starbase hacking mission started"
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

  # Check fleet has exactly one Scout
  var scoutCount = 0
  var scoutELI = 0

  for squadron in fleet.squadrons:
    if squadron.flagship.shipClass == ShipClass.Scout:
      scoutCount += 1
      scoutELI = squadron.flagship.stats.techLevel

  if scoutCount != 1:
    return OrderExecutionResult(
      success: false,
      message: "Spy System requires exactly one Scout (found " & $scoutCount & ")",
      eventsGenerated: @[]
    )

  let targetSystem = order.targetSystem.get()

  # Create spy scout and add to game state
  let spyId = "spy-" & $fleet.owner & "-" & $state.turn & "-" & $targetSystem
  let spyScout = SpyScout(
    id: spyId,
    owner: fleet.owner,
    location: targetSystem,
    eliLevel: scoutELI,
    mission: SpyMissionType.SpyOnSystem,
    commissionedTurn: state.turn,
    detected: false
  )

  state.spyScouts[spyId] = spyScout

  # Remove scout from fleet (it operates independently now, permanently consumed)
  var updatedFleet = fleet
  for i in 0..<updatedFleet.squadrons.len:
    if updatedFleet.squadrons[i].flagship.shipClass == ShipClass.Scout:
      updatedFleet.squadrons.delete(i)
      break

  # Check if fleet is now empty and clean up if needed
  if updatedFleet.squadrons.len == 0:
    # Fleet is empty - remove it completely
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
    message: "Scout deployed to spy on system " & $targetSystem,
    eventsGenerated: @[
      "Spy scout deployed (ELI " & $scoutELI & ")",
      "System surveillance mission started"
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

  if order.targetFleet.isNone:
    return OrderExecutionResult(
      success: false,
      message: "Join Fleet requires target fleet",
      eventsGenerated: @[]
    )

  let targetFleetId = order.targetFleet.get()
  let targetFleetOpt = state.getFleet(targetFleetId)

  if targetFleetOpt.isNone:
    return OrderExecutionResult(
      success: false,
      message: "Target fleet " & $targetFleetId & " not found",
      eventsGenerated: @[]
    )

  let targetFleet = targetFleetOpt.get()

  # Check same owner
  if targetFleet.owner != fleet.owner:
    return OrderExecutionResult(
      success: false,
      message: "Cannot join fleet owned by different house",
      eventsGenerated: @[]
    )

  # Check same location
  if targetFleet.location != fleet.location:
    return OrderExecutionResult(
      success: false,
      message: "Fleets must be at same location to join",
      eventsGenerated: @[]
    )

  # Merge squadrons and spacelift ships into target fleet
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
    message: "Fleet " & $fleet.id & " joined " & $targetFleetId & " (" & $fleet.squadrons.len & " squadrons merged)",
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

  # If only this fleet, wait for others
  if rendezvousFleets.len == 1:
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

  # Update host fleet
  state.fleets[lowestId] = hostFleet

  result = OrderExecutionResult(
    success: true,
    message: "Rendezvous complete at " & $targetSystem & ": " & $mergedCount & " fleets merged into " & $lowestId,
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
  ## Place fleet on reserve status
  ## Per economy.md:3.9 - 50% maintenance, half AS/DS, can't move, must be at colony

  # Validate fleet is at a colony
  if fleet.location notin state.colonies:
    return OrderExecutionResult(
      success: false,
      message: "Fleet must be at a colony to be placed on reserve"
    )

  let colony = state.colonies[fleet.location]
  if colony.owner != fleet.owner:
    return OrderExecutionResult(
      success: false,
      message: "Fleet must be at a friendly colony to be placed on reserve"
    )

  result = OrderExecutionResult(
    success: true,
    message: "Fleet " & $fleet.id & " placed on reserve (50% maint, half AS/DS)",
    eventsGenerated: @["Fleet placed on reserve status"]
  )

proc executeMothballOrder(
  state: var GameState,
  fleet: Fleet,
  order: FleetOrder
): OrderExecutionResult =
  ## Mothball fleet
  ## Per economy.md:3.9 - 0% maintenance, offline, screened in combat, must be at colony with spaceport

  # Validate fleet is at a colony
  if fleet.location notin state.colonies:
    return OrderExecutionResult(
      success: false,
      message: "Fleet must be at a colony to be mothballed"
    )

  let colony = state.colonies[fleet.location]
  if colony.owner != fleet.owner:
    return OrderExecutionResult(
      success: false,
      message: "Fleet must be at a friendly colony to be mothballed"
    )

  # Per spec: mothballed ships stored at spaceport
  if colony.spaceports.len == 0:
    return OrderExecutionResult(
      success: false,
      message: "Colony must have a spaceport to mothball ships"
    )

  result = OrderExecutionResult(
    success: true,
    message: "Fleet " & $fleet.id & " mothballed (0% maint, offline)",
    eventsGenerated: @["Fleet mothballed"]
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
