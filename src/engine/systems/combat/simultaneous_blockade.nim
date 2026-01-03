## Simultaneous Blockade Resolution
##
## Handles simultaneous resolution of BlockadePlanet orders
## to prevent first-mover advantages.

import std/[tables, options, random, strformat]
import ../../types/simultaneous as simultaneous_types
import simultaneous_resolver
import ../../types/[game_state, fleet, command, core]
import ../../../common/logger
import ../squadron/entity
import ../../state/[engine, iterators]

proc collectBlockadeIntents*(
    state: GameState, orders: Table[HouseId, CommandPacket]
): seq[BlockadeIntent] =
  ## Collect all blockade attempts
  result = @[]

  for house in state.allHouses:
    if house.id notin orders:
      continue

    for command in orders[house.id].fleetCommands:
      if command.commandType != FleetCommandType.Blockade:
        continue

      # Validate: fleet exists
      let fleetOpt = state.fleet(command.fleetId)
      if fleetOpt.isNone:
        continue

      let fleet = fleetOpt.get()

      # Calculate blockade strength (total AS)
      var blockadeStrength: int32 = 0
      for sqId in fleet.squadrons:
        let sq = state.squadron(sqId).get
        blockadeStrength += state.combatStrength(sq)

      # Get target from order
      if command.targetSystem.isNone:
        continue

      let targetSystem: SystemId = command.targetSystem.get()

      result.add(
        BlockadeIntent(
          houseId: house.id,
          fleetId: command.fleetId,
          targetColony: state.colonyIdBySystem(targetSystem).get(),  # Lookup ColonyId from SystemId (1:1 relationship)
          blockadeStrength: blockadeStrength,
        )
      )

proc detectBlockadeConflicts*(intents: seq[BlockadeIntent]): seq[BlockadeConflict] =
  ## Group blockade intents by target colony
  var targetColonies = initTable[ColonyId, seq[BlockadeIntent]]()

  for intent in intents:
    if intent.targetColony notin targetColonies:
      targetColonies[intent.targetColony] = @[]
    targetColonies[intent.targetColony].add(intent)

  result = @[]
  for colonyId, conflictingIntents in targetColonies:
    result.add(BlockadeConflict(targetColony: colonyId, intents: conflictingIntents))

proc resolveBlockadeConflict*(
    state: var GameState, conflict: BlockadeConflict, rng: var Rand
): seq[BlockadeResult] =
  ## Resolve blockade conflict - strongest blockader wins (like colonization)
  result = @[]

  if conflict.intents.len == 0:
    return

  # Single intent = no conflict, just blockade
  if conflict.intents.len == 1:
    let intent = conflict.intents[0]
    result.add(
      BlockadeResult(
        houseId: intent.houseId,
        fleetId: intent.fleetId,
        originalTarget: intent.targetColony,
        outcome: ResolutionOutcome.Success,
        actualTarget: some(intent.targetColony),
        prestigeAwarded: 0,
      )
    )
    return

  # Multiple intents = conflict, strongest wins
  # Get systemId from colony (no cast)
  let targetColony = state.colony(conflict.targetColony).get()
  let seed = tiebreakerSeed(state.turn, targetColony.systemId)
  let winner = resolveConflictByStrength(
    conflict.intents,
    proc(intent: BlockadeIntent): int = intent.blockadeStrength,
    seed,
    rng
  )

  logInfo(
    "Combat",
    &"Blockade conflict at {conflict.targetColony}: {conflict.intents.len} houses competing, {winner.houseId} wins"
  )

  # Winner blockades
  result.add(
    BlockadeResult(
      houseId: winner.houseId,
      fleetId: winner.fleetId,
      originalTarget: winner.targetColony,
      outcome: ResolutionOutcome.Success,
      actualTarget: some(winner.targetColony),
      prestigeAwarded: 0,
    )
  )

  # All others lose the conflict
  for loser in conflict.intents:
    if loser.houseId != winner.houseId or loser.fleetId != winner.fleetId:
      result.add(
        BlockadeResult(
          houseId: loser.houseId,
          fleetId: loser.fleetId,
          originalTarget: loser.targetColony,
          outcome: ResolutionOutcome.ConflictLost,
          actualTarget: none(ColonyId),
          prestigeAwarded: 0,
        )
      )

proc resolveBlockades*(
    state: var GameState, orders: Table[HouseId, CommandPacket], rng: var Rand
): seq[BlockadeResult] =
  ## Main entry point: Resolve all blockade orders simultaneously
  result = @[]

  let intents = collectBlockadeIntents(state, orders)
  if intents.len == 0:
    return

  let conflicts = detectBlockadeConflicts(intents)

  for conflict in conflicts:
    let conflictResults = resolveBlockadeConflict(state, conflict, rng)
    result.add(conflictResults)

proc wasBlockadeHandled*(
    results: seq[BlockadeResult], houseId: HouseId, fleetId: FleetId
): bool =
  ## Check if a blockade order was already handled
  for result in results:
    if result.houseId == houseId and result.fleetId == fleetId:
      return true
  return false
