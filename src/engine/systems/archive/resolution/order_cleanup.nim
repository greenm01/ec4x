## Centralized Order Cleanup Based on GameEvents
##
## Runs at start of Command Phase to clean up orders from previous turn.
## Uses event-driven approach: GameEvents from previous turn determine cleanup.
##
## Design:
## - Single source of truth for order cleanup logic (DRY)
## - Event-driven: OrderCompleted/OrderFailed/OrderAborted trigger cleanup
## - Category-aware: One-shot vs persistent orders
##
## Benefits:
## - 1 module vs 22 scattered inline cleanup points
## - Maintainable: Changes in one place
## - Testable: Isolated logic with clear inputs/outputs

import std/[tables, options, strformat]
import ../gamestate, ../order_types, ../standing_orders, ../logger
import ./types as res_types

proc isOneShotOrderType(orderType: FleetOrderType): bool =
  ## Check if order is one-shot (executes once and completes)
  ## Per docs/engine/architecture/active_fleet_order_game_events.md:143-157
  ##
  ## One-Shot Orders: Execute once, then remove from queue
  ## - Movement: Move, SeekHome
  ## - Colonization: Colonize
  ## - Combat: Bombard, Invade, Blitz
  ## - Fleet Operations: JoinFleet, Rendezvous, Salvage
  ## - Espionage: SpyPlanet, SpySystem, HackStarbase
  ## - Misc: ViewWorld
  ## - State-Change: Reserve, Mothball, Reactivate
  ##
  ## Persistent Orders: Execute every turn until overridden
  ## - Hold, Patrol, GuardStarbase, GuardPlanet, BlockadePlanet
  orderType in {
    FleetOrderType.Move,
    FleetOrderType.SeekHome,
    FleetOrderType.Colonize,
    FleetOrderType.Salvage,
    FleetOrderType.JoinFleet,
    FleetOrderType.Rendezvous,
    FleetOrderType.Bombard,
    FleetOrderType.Invade,
    FleetOrderType.Blitz,
    FleetOrderType.SpyPlanet,
    FleetOrderType.SpySystem,
    FleetOrderType.HackStarbase,
    FleetOrderType.ViewWorld,
    FleetOrderType.Reserve,
    FleetOrderType.Mothball,
    FleetOrderType.Reactivate
  }

proc cleanFleetOrders*(state: var GameState, events: seq[res_types.GameEvent]) =
  ## Clean up completed/failed/aborted orders based on events
  ## Called at START of Command Phase (before accepting new orders)
  ##
  ## Cleanup Rules:
  ## - OrderFailed: ALWAYS clear (all order types)
  ## - OrderAborted: ALWAYS clear (all order types)
  ## - OrderCompleted: Clear ONLY for one-shot orders (persistent orders continue)
  ##
  ## This allows standing orders to activate when explicit orders are no longer active.

  var ordersCleared = 0

  for event in events:
    # Only process order lifecycle events with fleet context
    if event.eventType notin {res_types.GameEventType.OrderCompleted,
                               res_types.GameEventType.OrderFailed,
                               res_types.GameEventType.OrderAborted}:
      continue

    if event.fleetId.isNone:
      continue  # Event not associated with a fleet

    let fleetId = event.fleetId.get()

    # Check if fleet order exists
    if fleetId notin state.fleetOrders:
      continue  # Already cleared or never existed

    let order = state.fleetOrders[fleetId]

    # Apply cleanup rules based on event type
    var shouldClear = false
    var reason = ""

    case event.eventType
    of res_types.GameEventType.OrderFailed:
      shouldClear = true
      reason = "failed"

    of res_types.GameEventType.OrderAborted:
      shouldClear = true
      reason = "aborted"

    of res_types.GameEventType.OrderCompleted:
      # Only clear one-shot orders on completion
      # Persistent orders (Patrol, GuardStarbase, etc.) continue executing
      if order.orderType.isOneShotOrderType():
        shouldClear = true
        reason = "completed"
      else:
        logDebug(LogCategory.lcOrders,
                 &"Persistent order {order.orderType} for fleet {fleetId} " &
                 &"completed but not cleared (continues executing)")

    else:
      discard

    # Perform cleanup
    if shouldClear:
      state.fleetOrders.del(fleetId)
      standing_orders.resetStandingOrderGracePeriod(state, fleetId)
      ordersCleared += 1
      logDebug(LogCategory.lcOrders,
               &"Cleared {reason} order {order.orderType} for fleet {fleetId}")

  if ordersCleared > 0:
    logInfo(LogCategory.lcOrders,
            &"Command Phase: Cleaned {ordersCleared} completed/failed/aborted orders")
