## Movement and Intelligence Utility Functions
##
## This module provides helper functions related to fleet movement, pathfinding,
## risk assessment, and intelligence gathering based on fog-of-war. These utilities
## are shared across various fleet order execution modules.

import std/[tables, options, math, algorithm, strformat]
import ../../../../common/types/[core, units]
import ../../gamestate
import ../../types/military/fleet_types
import ../../systems/starmap_engine/engine as starmap_engine
import ../../logger
import ../../intelligence/types as intel_types
import ../../diplomacy/types as dip_types
import ../main as orders # For FleetOrderType and AutoRetreatPolicy

proc isSystemHostile*(state: GameState, systemId: SystemId, houseId: HouseId): bool =
  ## Check if a system is hostile to a house based on known intel (fog-of-war)
  ## System is hostile if player KNOWS it contains:
  ## 1. Enemy colony (from intelligence database or visibility)
  ## 2. Enemy fleets (from intelligence database or visibility)
  ## IMPORTANT: This respects fog-of-war - only uses information available to the house

  let house = state.houses[houseId]

  # Check if system has enemy colony (visible or from intel database)
  if systemId in state.colonies:
    let colony = state.colonies[systemId]
    if colony.owner != houseId:
      # Check diplomatic status
      if house.diplomaticRelations.isEnemy(colony.owner):
        # Player can see this colony - it's hostile
        return true

  # Check intelligence database for known enemy colonies
  if systemId in house.intelligence.colonyReports:
    let colonyIntel = house.intelligence.colonyReports[systemId]
    if colonyIntel.targetOwner != houseId and house.diplomaticRelations.isEnemy(colonyIntel.targetOwner):
      return true

  # Check for enemy fleets at system (visible or from intel)
  for fleetId, fleet in state.fleets:
    if fleet.location == systemId and fleet.owner != houseId:
      if house.diplomaticRelations.isEnemy(fleet.owner):
        return true

  return false

proc estimatePathRisk*(state: GameState, path: seq[SystemId], houseId: HouseId): int =
  ## Estimate risk level of a path (0 = safe, higher = more risky)
  ## Uses fog-of-war information available to the house
  result = 0

  for systemId in path:
    if isSystemHostile(state, systemId, houseId):
      result += 10  # Known enemy system - high risk
    elif systemId in state.colonies:
      let colony = state.colonies[systemId]
      if colony.owner != houseId:
        # Foreign but not enemy (neutral) - moderate risk
        result += 3
    else:
      # Unexplored or empty - low risk
      result += 1

  return result

proc findClosestOwnedColony*(state: GameState, fromSystem: SystemId, houseId: HouseId): Option[SystemId] =
  ## Find the closest owned colony for a house, excluding the fromSystem
  ## Returns None if house has no colonies
  ## Used by Space Guild to find alternative delivery destination
  ## Also used for automated Seek Home behavior for stranded fleets
  ##
  ## INTEGRATION: Checks house's pre-planned fallback routes first for optimal retreat paths

  # Check if house has a pre-planned fallback route from this region
  if houseId in state.houses:
    let house = state.houses[houseId]
    for route in house.fallbackRoutes:
      # Route is valid if it matches our region and hasn't expired (< 20 turns old)
      if route.region == fromSystem and state.turn - route.lastUpdated < 20:
        # Verify fallback system still exists and is owned
        if route.fallbackSystem in state.colonies and \
           state.colonies[route.fallbackSystem].owner == houseId:
          return some(route.fallbackSystem)

  # Fallback: Calculate best retreat route balancing distance and risk
  # IMPORTANT: Uses fog-of-war information only (player's knowledge)
  var bestColony: Option[SystemId] = none(SystemId)
  var bestScore = int.high  # Lower is better (combines distance and risk)

  # Iterate through all colonies owned by this house
  for systemId, colony in state.colonies:
    if colony.owner == houseId and systemId != fromSystem:
      # Calculate distance (jump count) to this colony
      # Create dummy fleet for pathfinding
      let dummyFleet = Fleet(
        id: "temp",
        owner: houseId,
        location: fromSystem,
        squadrons: @[],
        status: FleetStatus.Active
      )

      let pathResult = starmap_engine.findPath(fromSystem, systemId, dummyFleet)
      if pathResult.path.len > 0:
        let distance = pathResult.path.len - 1  # Number of jumps

        # Calculate path risk using fog-of-war intel
        let risk = estimatePathRisk(state, pathResult.path, houseId)

        # Score combines distance and risk
        # Risk is weighted heavily (x3) to strongly prefer safer routes
        # But will accept risky routes if they're much shorter
        let score = distance + (risk * 3)

        if score < bestScore:
          bestScore = score
          bestColony = some(systemId)

  return bestColony

proc shouldAutoSeekHome*(state: GameState, fleet: Fleet, order: orders.FleetOrder): bool =
  ## Determine if a fleet should automatically seek home due to dangerous situation
  ## Respects house's auto-retreat policy setting
  ## Triggers based on policy:
  ## - Never: Never auto-retreat
  ## - MissionsOnly: Abort missions (ETAC, Guard, Blockade) when target lost
  ## - ConservativeLosing: Also retreat fleets clearly losing combat
  ## - AggressiveSurvival: Also retreat any fleet at risk

  # Check house's auto-retreat policy
  let house = state.houses[fleet.owner]

  # Never policy: player always controls retreats
  if house.autoRetreatPolicy == orders.AutoRetreatPolicy.Never:
    return false

  # Check if fleet is executing an order that becomes invalid due to hostility
  # (MissionsOnly and higher policies)
  case order.orderType
  of orders.FleetOrderType.Colonize:
    # ETAC missions abort if destination becomes enemy-controlled
    if order.targetSystem.isSome:
      let targetId = order.targetSystem.get()
      if isSystemHostile(state, targetId, fleet.owner):
        return true

  of orders.FleetOrderType.GuardStarbase, orders.FleetOrderType.GuardPlanet, orders.FleetOrderType.BlockadePlanet:
    # Guard/blockade orders abort if system lost to enemy
    if order.targetSystem.isSome:
      let targetId = order.targetSystem.get()
      if targetId in state.colonies:
        let colony = state.colonies[targetId]
        # If colony ownership changed to enemy, abort
        if colony.owner != fleet.owner:
          let house = state.houses[fleet.owner]
          if house.diplomaticRelations.isEnemy(colony.owner):
            return true
      else:
        # Colony destroyed - abort
        return true

  of orders.FleetOrderType.Patrol:
    # Patrols abort if their patrol zone becomes enemy territory
    # Check if current location is hostile
    if fleet.location in state.colonies:
      let colony = state.colonies[fleet.location]
      if colony.owner != fleet.owner:
        let house = state.houses[fleet.owner]
        if house.diplomaticRelations.isEnemy(colony.owner):
          return true

    # Also check if patrol target destination is hostile
    if order.targetSystem.isSome:
      let targetId = order.targetSystem.get()
      if isSystemHostile(state, targetId, fleet.owner):
        return true

  else:
    discard

  return false
