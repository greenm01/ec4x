## Fleet Order Execution Dispatcher
##
## This module acts as the main dispatcher for fleet orders, routing them to
## specialized handler modules within `src/engine/systems/orders/execution/`.
## It also defines the `OrderOutcome` enum and forward declarations for order handlers.

import std/[options, tables, strformat]
import ../../../common/types/[core, units]
import ../../gamestate, ../main as orders, ../../fleet, ../../squadron, ../../state_helpers, ../../logger, ../../starmap
import ../../index_maintenance
import ../../intelligence/detection
import ../../types/combat as combat_types
import ../../types/diplomacy as dip_types
import ../../types/resolution as resolution_types
import ../../standing_orders
import ../../events/init as event_factory

# Import individual order execution modules
import ./execution/hold
import ./execution/move
import ./execution/seek_home
import ./execution/patrol # Add this import as well, as patrol.nim will be created
import ./execution/guard_starbase
import ./execution/guard_colony
import ./execution/blockade_colony
import ./execution/combat_assault
import ./execution/espionage
import ./execution/economic_fleet_management
import ./execution/state_change
import ./execution/recon # For Recon orders
import ./execution/colonize
import ./execution/join_fleet
import ./execution/rendezvous
import ./execution/salvage
import ./execution/bombard
import ./execution/invade
import ./execution/blitz
import ./execution/spy_colony
import ./execution/hack_starbase
import ./execution/spy_system
# TODO: Remove this placeholder comment when all imports are added

type
  OrderOutcome* {.pure.} = enum
    Success,  # Order executed successfully, continue if persistent
    Failed,   # Order failed validation/execution, remove from queue
    Aborted   # Order cancelled (conditions changed), remove from queue

# =============================================================================
# Forward Declarations (now reference specific execution modules)
# =============================================================================

# Movement orders
proc executeHoldOrder*(state: var GameState, fleet: Fleet, order: orders.FleetOrder, events: var seq[resolution_types.GameEvent]): OrderOutcome =
  return hold.executeHoldOrder(state, fleet, order, events)
proc executeMoveOrder*(state: var GameState, fleet: Fleet, order: orders.FleetOrder, events: var seq[resolution_types.GameEvent]): OrderOutcome =
  return move.executeMoveOrder(state, fleet, order, events)
proc executeSeekHomeOrder*(state: var GameState, fleet: Fleet, order: orders.FleetOrder, events: var seq[resolution_types.GameEvent]): OrderOutcome =
  return seek_home.executeSeekHomeOrder(state, fleet, order, events)

proc executePatrolOrder*(state: var GameState, fleet: Fleet, order: orders.FleetOrder, events: var seq[resolution_types.GameEvent]): OrderOutcome =
  return patrol.executePatrolOrder(state, fleet, order, events)

# Combat orders
proc executeGuardStarbaseOrder*(state: var GameState, fleet: Fleet, order: orders.FleetOrder, events: var seq[resolution_types.GameEvent]): OrderOutcome =
  return guard_starbase.executeGuardStarbaseOrder(state, fleet, order, events)
proc executeGuardPlanetOrder*(state: var GameState, fleet: Fleet, order: orders.FleetOrder, events: var seq[resolution_types.GameEvent]): OrderOutcome =
  return guard_colony.executeGuardColonyOrder(state, fleet, order, events)
proc executeBlockadeOrder*(state: var GameState, fleet: Fleet, order: orders.FleetOrder, events: var seq[resolution_types.GameEvent]): OrderOutcome =
  return blockade_colony.executeBlockadeColonyOrder(state, fleet, order, events)
proc executeBombardOrder*(state: var GameState, fleet: Fleet, order: orders.FleetOrder, events: var seq[resolution_types.GameEvent]): OrderOutcome =
  return bombard.executeBombardOrder(state, fleet, order, events)
proc executeInvadeOrder*(state: var GameState, fleet: Fleet, order: orders.FleetOrder, events: var seq[resolution_types.GameEvent]): OrderOutcome =
  return invade.executeInvadeOrder(state, fleet, order, events)
proc executeBlitzOrder*(state: var GameState, fleet: Fleet, order: orders.FleetOrder, events: var seq[resolution_types.GameEvent]): OrderOutcome =
  return blitz.executeBlitzOrder(state, fleet, order, events)
# Espionage orders
proc executeSpyPlanetOrder*(state: var GameState, fleet: Fleet, order: orders.FleetOrder, events: var seq[resolution_types.GameEvent]): OrderOutcome =
  return spy_colony.executeSpyColonyOrder(state, fleet, order, events)
proc executeHackStarbaseOrder*(state: var GameState, fleet: Fleet, order: orders.FleetOrder, events: var seq[resolution_types.GameEvent]): OrderOutcome =
  return hack_starbase.executeHackStarbaseOrder(state, fleet, order, events)
proc executeSpySystemOrder*(state: var GameState, fleet: Fleet, order: orders.FleetOrder, events: var seq[resolution_types.GameEvent]): OrderOutcome =
  return spy_system.executeSpySystemOrder(state, fleet, order, events)
# Economic/Fleet Management orders
proc executeColonizeOrder*(state: var GameState, fleet: Fleet, order: orders.FleetOrder, events: var seq[resolution_types.GameEvent]): OrderOutcome =
  return colonize.executeColonizeOrder(state, fleet, order, events)
proc executeJoinFleetOrder*(state: var GameState, fleet: Fleet, order: orders.FleetOrder, events: var seq[resolution_types.GameEvent]): OrderOutcome =
  return join_fleet.executeJoinFleetOrder(state, fleet, order, events)
proc executeRendezvousOrder*(state: var GameState, fleet: Fleet, order: orders.FleetOrder, events: var seq[resolution_types.GameEvent]): OrderOutcome =
  return rendezvous.executeRendezvousOrder(state, fleet, order, events)
proc executeSalvageOrder*(state: var GameState, fleet: Fleet, order: orders.FleetOrder, events: var seq[resolution_types.GameEvent]): OrderOutcome =
  return salvage.executeSalvageOrder(state, fleet, order, events)
# State Change orders
proc executeReserveOrder*(state: var GameState, fleet: Fleet, order: orders.FleetOrder, events: var seq[resolution_types.GameEvent]): OrderOutcome = 
  return state_change.executeReserveOrder(state, fleet, order, events)

proc executeMothballOrder*(state: var GameState, fleet: Fleet, order: orders.FleetOrder, events: var seq[resolution_types.GameEvent]): OrderOutcome = 
  return state_change.executeMothballOrder(state, fleet, order, events)

proc executeReactivateOrder*(state: var GameState, fleet: Fleet, order: orders.FleetOrder, events: var seq[resolution_types.GameEvent]): OrderOutcome = 
  return state_change.executeReactivateOrder(state, fleet, order, events)

# Recon orders
proc executeViewWorldOrder*(state: var GameState, fleet: Fleet, order: orders.FleetOrder, events: var seq[resolution_types.GameEvent]): OrderOutcome = 
  return recon.executeViewWorldOrder(state, fleet, order, events)

# =============================================================================
# Order Execution Dispatcher
# =============================================================================

proc executeFleetOrder*(
  state: var GameState,
  houseId: HouseId,
  order: orders.FleetOrder,
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
  of orders.FleetOrderType.Hold:
    return executeHoldOrder(state, fleet, order, events)
  of orders.FleetOrderType.Move:
    return executeMoveOrder(state, fleet, order, events)
  of orders.FleetOrderType.SeekHome:
    return executeSeekHomeOrder(state, fleet, order, events)
  of orders.FleetOrderType.Patrol:
    return executePatrolOrder(state, fleet, order, events)
  of orders.FleetOrderType.GuardStarbase:
    return executeGuardStarbaseOrder(state, fleet, order, events)
  of orders.FleetOrderType.GuardPlanet:
    return executeGuardPlanetOrder(state, fleet, order, events)
  of orders.FleetOrderType.BlockadePlanet:
    return executeBlockadeOrder(state, fleet, order, events)
  of orders.FleetOrderType.Bombard:
    return executeBombardOrder(state, fleet, order, events)
  of orders.FleetOrderType.Invade:
    return executeInvadeOrder(state, fleet, order, events)
  of orders.FleetOrderType.Blitz:
    return executeBlitzOrder(state, fleet, order, events)
  of orders.FleetOrderType.SpyPlanet:
    return executeSpyPlanetOrder(state, fleet, order, events)
  of orders.FleetOrderType.HackStarbase:
    return executeHackStarbaseOrder(state, fleet, order, events)
  of orders.FleetOrderType.SpySystem:
    return executeSpySystemOrder(state, fleet, order, events)
  of orders.FleetOrderType.Colonize:
    return executeColonizeOrder(state, fleet, order, events)
  of orders.FleetOrderType.JoinFleet:
    return executeJoinFleetOrder(state, fleet, order, events)
  of orders.FleetOrderType.Rendezvous:
    return executeRendezvousOrder(state, fleet, order, events)
  of orders.FleetOrderType.Salvage:
    return executeSalvageOrder(state, fleet, order, events)
  of orders.FleetOrderType.Reserve:
    return executeReserveOrder(state, fleet, order, events)
  of orders.FleetOrderType.Mothball:
    return executeMothballOrder(state, fleet, order, events)
  of orders.FleetOrderType.Reactivate:
    return executeReactivateOrder(state, fleet, order, events)
  of orders.FleetOrderType.ViewWorld:
    return executeViewWorldOrder(state, fleet, order, events)
