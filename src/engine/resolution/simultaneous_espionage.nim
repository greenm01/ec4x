## Simultaneous Espionage Resolution
##
## Handles simultaneous resolution of SpyPlanet, SpySystem, and HackStarbase orders
## to prevent first-mover advantages in intelligence operations.

import std/[tables, options, random, sequtils, strformat, algorithm]
import simultaneous_types
import simultaneous_resolver
import ../gamestate
import ../orders
import ../order_types
import ../logger
import ../squadron
import ../../common/types/core

proc collectEspionageIntents*(
  state: GameState,
  orders: Table[HouseId, OrderPacket]
): seq[EspionageIntent] =
  ## Collect all espionage attempts
  result = @[]

  for houseId in state.houses.keys:
    if houseId notin orders:
      continue

    for order in orders[houseId].fleetOrders:
      if order.orderType notin [FleetOrderType.SpyPlanet, FleetOrderType.SpySystem, FleetOrderType.HackStarbase]:
        continue

      # Validate: fleet exists
      if order.fleetId notin state.fleets:
        continue

      let fleet = state.fleets[order.fleetId]

      # Calculate espionage strength using house prestige
      # Higher prestige = better intelligence operations
      let espionageStrength = state.houses[houseId].prestige

      # Check if house is dishonored
      let isDishonored = state.houses[houseId].dishonoredStatus.active

      # Get target from order
      if order.targetSystem.isNone:
        continue

      let targetSystem = order.targetSystem.get()

      result.add(EspionageIntent(
        houseId: houseId,
        fleetId: order.fleetId,
        targetSystem: targetSystem,
        orderType: $order.orderType,
        espionageStrength: espionageStrength,
        isDishonored: isDishonored
      ))

proc detectEspionageConflicts*(
  intents: seq[EspionageIntent]
): seq[EspionageConflict] =
  ## Group espionage intents by target system
  var targetSystems = initTable[SystemId, seq[EspionageIntent]]()

  for intent in intents:
    if intent.targetSystem notin targetSystems:
      targetSystems[intent.targetSystem] = @[]
    targetSystems[intent.targetSystem].add(intent)

  result = @[]
  for systemId, conflictingIntents in targetSystems:
    result.add(EspionageConflict(
      targetSystem: systemId,
      intents: conflictingIntents
    ))

proc resolveEspionageConflict*(
  state: var GameState,
  conflict: EspionageConflict,
  rng: var Rand
): seq[EspionageResult] =
  ## Resolve espionage conflict using prestige-based priority
  ## Dishonored houses go to end of list, if both dishonored then random
  result = @[]

  if conflict.intents.len == 0:
    return

  # Sort by: 1) honored status (honored first), 2) prestige (highest first), 3) random tiebreaker
  var sorted = conflict.intents

  # Separate honored and dishonored houses
  var honored: seq[EspionageIntent] = @[]
  var dishonored: seq[EspionageIntent] = @[]

  for intent in sorted:
    if intent.isDishonored:
      dishonored.add(intent)
    else:
      honored.add(intent)

  # Sort honored houses by prestige (descending)
  if honored.len > 0:
    let seed = tiebreakerSeed(state.turn, conflict.targetSystem)
    var honoredRng = initRand(seed)

    honored.sort do (a, b: EspionageIntent) -> int:
      if a.espionageStrength != b.espionageStrength:
        return cmp(b.espionageStrength, a.espionageStrength)  # Descending
      else:
        return honoredRng.rand(1) * 2 - 1  # Random: -1 or 1

  # Sort dishonored houses randomly
  if dishonored.len > 0:
    let seed = tiebreakerSeed(state.turn, conflict.targetSystem) + 1000  # Different seed
    var dishonoredRng = initRand(seed)

    dishonored.sort do (a, b: EspionageIntent) -> int:
      return dishonoredRng.rand(1) * 2 - 1  # Pure random

  # Combine: honored first, then dishonored
  sorted = honored & dishonored

  let first = sorted[0]
  logDebug(LogCategory.lcCombat,
           &"{conflict.intents.len} houses conducting espionage at {conflict.targetSystem}, priority: {first.houseId} (prestige: {first.espionageStrength}, dishonored: {first.isDishonored})")

  # All espionage attempts succeed, but in priority order
  # (Actual espionage resolution happens in main loop with proper detection rolls)
  for intent in sorted:
    result.add(EspionageResult(
      houseId: intent.houseId,
      fleetId: intent.fleetId,
      originalTarget: intent.targetSystem,
      outcome: ResolutionOutcome.Success,
      actualTarget: some(intent.targetSystem),
      prestigeAwarded: 0  # Prestige handled by espionage engine
    ))

proc resolveEspionage*(
  state: var GameState,
  orders: Table[HouseId, OrderPacket],
  rng: var Rand
): seq[EspionageResult] =
  ## Main entry point: Resolve all espionage orders simultaneously
  result = @[]

  let intents = collectEspionageIntents(state, orders)
  if intents.len == 0:
    return

  let conflicts = detectEspionageConflicts(intents)

  for conflict in conflicts:
    let conflictResults = resolveEspionageConflict(state, conflict, rng)
    result.add(conflictResults)

proc wasEspionageHandled*(
  results: seq[EspionageResult],
  houseId: HouseId,
  fleetId: FleetId
): bool =
  ## Check if an espionage order was already handled
  for result in results:
    if result.houseId == houseId and result.fleetId == fleetId:
      return true
  return false
