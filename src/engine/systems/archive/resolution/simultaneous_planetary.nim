## Simultaneous Planetary Combat Resolution
##
## Handles simultaneous resolution of Bombard, Invade, and Blitz orders
## to prevent first-mover advantages in planetary assaults.

import std/[tables, options, random, strformat]
import ../types/simultaneous as simultaneous_types
import ../systems/shared/simultaneous_resolver
import ../gamestate
import ../orders
import ../types/orders as order_types
import ../logger
import ../squadron
import ../../common/types/core
import ../types/resolution as res_types


proc collectPlanetaryCombatIntents*(
  state: GameState,
  orders: Table[HouseId, OrderPacket]
): seq[PlanetaryCombatIntent] =
  ## Collect all planetary combat attempts (Bombard, Invade, Blitz)
  result = @[]

  for houseId in state.houses.keys:
    if houseId notin orders:
      continue

    for order in orders[houseId].fleetOrders:
      # Skip non-planetary combat orders
      if order.orderType notin [FleetOrderType.Bombard, FleetOrderType.Invade, FleetOrderType.Blitz]:
        continue

      # Validate: fleet exists
      if order.fleetId notin state.fleets:
        continue

      let fleet = state.fleets[order.fleetId]

      # Calculate attack strength (use total AS for all types)
      var attackStrength = 0
      for squadron in fleet.squadrons:
        attackStrength += squadron.combatStrength()

      # Get target from order
      if order.targetSystem.isNone:
        continue

      let targetSystem = order.targetSystem.get()

      # Add validated intent
      result.add(PlanetaryCombatIntent(
        houseId: houseId,
        fleetId: order.fleetId,
        targetColony: targetSystem,
        orderType: $order.orderType,
        attackStrength: attackStrength
      ))

proc detectPlanetaryCombatConflicts*(
  intents: seq[PlanetaryCombatIntent]
): seq[PlanetaryCombatConflict] =
  ## Group planetary combat intents by target colony
  var targetColonies = initTable[SystemId, seq[PlanetaryCombatIntent]]()

  for intent in intents:
    if intent.targetColony notin targetColonies:
      targetColonies[intent.targetColony] = @[]
    targetColonies[intent.targetColony].add(intent)

  result = @[]
  for colonyId, conflictingIntents in targetColonies:
    result.add(PlanetaryCombatConflict(
      targetColony: colonyId,
      intents: conflictingIntents
    ))

proc resolvePlanetaryCombatConflict*(
  state: var GameState,
  conflict: PlanetaryCombatConflict,
  rng: var Rand
): seq[PlanetaryCombatResult] =
  ## Resolve planetary combat conflict - strongest attacker wins (like colonization)
  result = @[]

  if conflict.intents.len == 0:
    return

  # Single intent = no conflict, just attack
  if conflict.intents.len == 1:
    let intent = conflict.intents[0]
    result.add(PlanetaryCombatResult(
      houseId: intent.houseId,
      fleetId: intent.fleetId,
      originalTarget: intent.targetColony,
      outcome: ResolutionOutcome.Success,
      actualTarget: some(intent.targetColony),
      prestigeAwarded: 0
    ))
    return

  # Multiple intents = conflict, strongest wins
  let seed = tiebreakerSeed(state.turn, conflict.targetColony)
  let winner = resolveConflictByStrength(
    conflict.intents,
    planetaryCombatStrength,
    seed,
    rng
  )

  logInfo(LogCategory.lcCombat,
          &"Planetary combat conflict at {conflict.targetColony}: {conflict.intents.len} attackers competing, {winner.houseId} wins")

  # Winner attacks
  result.add(PlanetaryCombatResult(
    houseId: winner.houseId,
    fleetId: winner.fleetId,
    originalTarget: winner.targetColony,
    outcome: ResolutionOutcome.Success,
    actualTarget: some(winner.targetColony),
    prestigeAwarded: 0  # Prestige handled by combat resolution
  ))

  # All others lose the conflict
  for loser in conflict.intents:
    if loser.houseId != winner.houseId or loser.fleetId != winner.fleetId:
      result.add(PlanetaryCombatResult(
        houseId: loser.houseId,
        fleetId: loser.fleetId,
        originalTarget: loser.targetColony,
        outcome: ResolutionOutcome.ConflictLost,
        actualTarget: none(SystemId),
        prestigeAwarded: 0
      ))

proc resolvePlanetaryCombat*(
  state: var GameState,
  orders: Table[HouseId, OrderPacket],
  rng: var Rand,
  events: var seq[res_types.GameEvent]
): seq[PlanetaryCombatResult] =
  ## Main entry point: Resolve all planetary combat orders simultaneously
  ## Then execute invasions/bombardments for winners at target
  result = @[]

  let intents = collectPlanetaryCombatIntents(state, orders)
  if intents.len == 0:
    return

  let conflicts = detectPlanetaryCombatConflicts(intents)

  for conflict in conflicts:
    let conflictResults = resolvePlanetaryCombatConflict(state, conflict, rng)
    result.add(conflictResults)

  # Execute invasions/bombardments for winners WHO ARE AT THE TARGET
  for res in result:
    if res.outcome == ResolutionOutcome.Success and res.actualTarget.isSome:
      # Verify fleet is at target location before executing
      if res.fleetId in state.fleets:
        let fleet = state.fleets[res.fleetId]
        let targetSystem = res.actualTarget.get()

        if fleet.location == targetSystem:
          # Fleet is at target - execute the assault
          logInfo(LogCategory.lcCombat, &"Executing planetary assault: {res.fleetId} at {targetSystem}")
          let winnerHouse = res.houseId
          if winnerHouse in orders:
            for order in orders[winnerHouse].fleetOrders:
              if order.fleetId == res.fleetId and
                 order.orderType in [FleetOrderType.Bombard, FleetOrderType.Invade, FleetOrderType.Blitz]:
                # Execute the planetary assault
                case order.orderType
                of FleetOrderType.Bombard:
                  planetary.resolveBombardment(state, winnerHouse, order, events)
                of FleetOrderType.Invade:
                  planetary.resolveInvasion(state, winnerHouse, order, events)
                of FleetOrderType.Blitz:
                  planetary.resolveBlitz(state, winnerHouse, order, events)
                else:
                  discard
                break  # Found and executed the order
        else:
          # Fleet not at target - skip this turn (will retry next turn if order persists)
          logDebug(LogCategory.lcCombat, &"Skipping planetary assault: {res.fleetId} not at {targetSystem} (currently at {fleet.location})")

proc wasPlanetaryCombatHandled*(
  results: seq[PlanetaryCombatResult],
  houseId: HouseId,
  fleetId: FleetId
): bool =
  ## Check if a planetary combat order was already handled
  for result in results:
    if result.houseId == houseId and result.fleetId == fleetId:
      return true
  return false
