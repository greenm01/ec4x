## Special AI Modes: Defensive Collapse & MIA Autopilot
##
## Implements automated AI behavior for eliminated or absent players
## per gameplay.md:1.4 (Player Elimination & Autopilot)

import std/[tables, options]
import ../common/types/core
import ../common/logger
import ./gamestate
import ./fleet
import ./starmap
import ./types/orders as order_types
import ./types/diplomacy as dip_types

export core.HouseId, core.SystemId, core.FleetId

## Defensive Collapse AI (gameplay.md:1.4.1)
##
## When a house has prestige < 0 for 3 consecutive turns, it enters
## permanent Defensive Collapse. The empire becomes a purely defensive
## AI that cannot perform offensive operations.
##
## Behavior:
## - All fleets return to nearest controlled system
## - Fleets defend colonies against Enemy-status houses
## - No offensive operations or expansion
## - No new construction orders
## - No diplomatic changes
## - Economy ceases (no income, no R&D, no maintenance)

proc getDefensiveCollapseOrders*(state: GameState, houseId: HouseId): seq[(FleetId, FleetOrder)] =
  ## Generate defensive collapse AI orders
  ## Returns fleet orders only - all other activity ceases
  result = @[]

  let house = state.houses.getOrDefault(houseId)
  if house.status != HouseStatus.DefensiveCollapse:
    return result

  # Find all controlled systems for retreat destinations
  var controlledSystems: seq[SystemId] = @[]
  for systemId, colony in state.colonies:
    if colony.owner == houseId:
      controlledSystems.add(systemId)

  if controlledSystems.len == 0:
    # No colonies left, no orders needed
    return result

  # For each fleet, determine action
  for fleetId, fleet in state.fleets:
    if fleet.owner != houseId:
      continue

    # Get current fleet order (if any)
    let currentOrder = state.fleetOrders.getOrDefault(fleetId)

    # Check if fleet is already defending a home system
    if fleet.location in controlledSystems:
      # Fleet is at home colony
      # Check if there's an enemy presence
      var hasEnemies = false
      for otherFleetId, otherFleet in state.fleets:
        if otherFleet.owner == houseId:
          continue

        if otherFleet.location == fleet.location:
          # Check diplomatic status
          let relation = dip_types.getDiplomaticState(house.diplomaticRelations, otherFleet.owner)
          if relation == dip_types.DiplomaticState.Enemy:
            hasEnemies = true
            break

      if hasEnemies:
        # Stay and defend
        if currentOrder.orderType != FleetOrderType.GuardPlanet:
          result.add((fleetId, FleetOrder(
            fleetId: fleetId,
            orderType: FleetOrderType.GuardPlanet,
            targetSystem: some(fleet.location),
            targetFleet: none(FleetId),
            priority: 0
          )))
      else:
        # Patrol home system
        if currentOrder.orderType != FleetOrderType.Patrol:
          result.add((fleetId, FleetOrder(
            fleetId: fleetId,
            orderType: FleetOrderType.Patrol,
            targetSystem: some(fleet.location),
            targetFleet: none(FleetId),
            priority: 0
          )))
    else:
      # Fleet is away from home - return to nearest controlled system
      # Find nearest reachable controlled system via jump lanes
      var nearestSystem = controlledSystems[0]
      var minDistance = int.high

      for systemId in controlledSystems:
        # Calculate distance via jump lanes pathfinding
        let pathResult = state.starMap.findPath(fleet.location, systemId, fleet)
        if pathResult.found:
          let dist = pathResult.path.len - 1  # Number of jumps
          if dist < minDistance:
            minDistance = dist
            nearestSystem = systemId

      # Issue move order to nearest home system
      if currentOrder.orderType != FleetOrderType.Move or
         currentOrder.targetSystem != some(nearestSystem):
        result.add((fleetId, FleetOrder(
          fleetId: fleetId,
          orderType: FleetOrderType.Move,
          targetSystem: some(nearestSystem),
          targetFleet: none(FleetId),
          priority: 0
        )))

## MIA Autopilot (gameplay.md:1.4.2)
##
## When a player fails to submit orders for 3 consecutive turns, the
## empire enters temporary Autopilot mode. The player can rejoin at any
## time by submitting orders.
##
## Behavior:
## - Fleets continue executing standing orders until completion
## - Fleets without orders patrol and defend home systems
## - No new construction or research
## - Economy maintains at low tax rate (20%) with minimal maintenance
## - No diplomatic changes
## - No offensive operations

proc getAutopilotOrders*(state: GameState, houseId: HouseId): seq[(FleetId, FleetOrder)] =
  ## Generate autopilot AI orders
  ## Returns fleet orders only - construction/research/diplomacy frozen
  result = @[]

  let house = state.houses.getOrDefault(houseId)
  if house.status != HouseStatus.Autopilot:
    return result

  # Find all controlled systems for fallback destinations
  var controlledSystems: seq[SystemId] = @[]
  for systemId, colony in state.colonies:
    if colony.owner == houseId:
      controlledSystems.add(systemId)

  if controlledSystems.len == 0:
    # No colonies left, no orders needed
    return result

  # For each fleet, check if it has standing orders
  for fleetId, fleet in state.fleets:
    if fleet.owner != houseId:
      continue

    let currentOrder = state.fleetOrders.getOrDefault(fleetId)

    # Check if fleet has active standing orders (let them continue)
    var needsNewOrder = false

    if currentOrder.fleetId == "":  # No current order
      needsNewOrder = true
    else:
      # Check if order is still valid
      case currentOrder.orderType
      of FleetOrderType.Move:
        # Move orders continue
        continue
      of FleetOrderType.GuardPlanet, FleetOrderType.GuardStarbase:
        # Guard orders continue
        continue
      of FleetOrderType.Patrol:
        # Patrol orders continue
        continue
      of FleetOrderType.Hold:
        # Hold is passive, let it continue
        continue
      of FleetOrderType.BlockadePlanet:
        # Blockade continues if target still exists
        if currentOrder.targetSystem.isSome:
          let targetSystem = currentOrder.targetSystem.get()
          if targetSystem in state.colonies:
            continue
        # Target lost - revert to patrol home
        needsNewOrder = true
      else:
        # Other orders (offensive/complex) - revert to patrol home
        needsNewOrder = true

    # Fleet has no valid orders - patrol nearest home system
    if needsNewOrder:
      if fleet.location in controlledSystems:
        # Already at home - patrol
        result.add((fleetId, FleetOrder(
          fleetId: fleetId,
          orderType: FleetOrderType.Patrol,
          targetSystem: some(fleet.location),
          targetFleet: none(FleetId),
          priority: 0
        )))
      else:
        # Return to nearest home system via jump lanes
        var nearestSystem = controlledSystems[0]
        var minDistance = int.high

        for systemId in controlledSystems:
          # Calculate distance via jump lanes pathfinding
          let pathResult = state.starMap.findPath(fleet.location, systemId, fleet)
          if pathResult.found:
            let dist = pathResult.path.len - 1  # Number of jumps
            if dist < minDistance:
              minDistance = dist
            nearestSystem = systemId

        result.add((fleetId, FleetOrder(
          fleetId: fleetId,
          orderType: FleetOrderType.Move,
          targetSystem: some(nearestSystem),
          targetFleet: none(FleetId),
          priority: 0
        )))

## MIA Detection and Status Updates

proc updateMIAStatus*(state: var GameState, housesWithOrders: seq[HouseId]) =
  ## Update MIA autopilot status for houses
  ## Call this at the end of order submission phase
  ## housesWithOrders: Houses that submitted orders this turn

  for houseId, house in state.houses.mpairs:
    if house.eliminated:
      continue

    # Check if house submitted orders
    if houseId in housesWithOrders:
      # House is active - reset counter
      house.turnsWithoutOrders = 0
      if house.status == HouseStatus.Autopilot:
        # House returned from autopilot
        house.status = HouseStatus.Active
        logInfo("AI", "House returned from autopilot", "house=", house.name)
    else:
      # House missed orders
      house.turnsWithoutOrders += 1
      logDebug("AI", "House missed orders", "house=", house.name, " turns=", $house.turnsWithoutOrders, "/3")

      if house.turnsWithoutOrders >= 3 and house.status != HouseStatus.Autopilot:
        # Enter autopilot mode
        house.status = HouseStatus.Autopilot
        logInfo("AI", "House entered autopilot mode", "house=", house.name, " reason=MIA_3_turns")
