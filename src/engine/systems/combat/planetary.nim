## Planetary Combat Simultaneous Resolution
##
## Handles simultaneous resolution of Bombard, Invade, and Blitz orders
## to prevent first-mover advantages in planetary assaults.
##
## Per architecture.md: Simultaneous resolution ensures fair multi-house
## combat where all attacking fleets are evaluated before outcomes are applied.

import std/[tables, options, random, strformat]
import ../../types/simultaneous as simultaneous_types
import simultaneous_resolver
import ../../types/game_state
import ../command/commands
import ../../../common/logger
import ../squadron/entity
import ../../types/core
import ./types as res_types
import ../colony/planetary_combat  # Planetary combat (resolveBombardment, resolveInvasion, resolveBlitz)
import ../../state/entity_manager

proc collectPlanetaryCombatIntents*(
  state: GameState,
  orders: Table[HouseId, OrderPacket]
): seq[PlanetaryCombatIntent] =
  ## Collect all planetary combat attempts (Bombard, Invade, Blitz)
  result = @[]

  for houseId in state.houses.entities.keys:
    if houseId notin orders:
      continue

    for command in orders[houseId].fleetCommands:
      # Skip non-planetary combat orders
      if command.commandType notin [FleetCommandType.Bombard, FleetCommandType.Invade, FleetCommandType.Blitz]:
        continue

      # Validate: fleet exists - using entity_manager
      let fleetOpt = state.fleets.entities.getEntity(command.fleetId)
      if fleetOpt.isNone:
        continue

      let fleet = fleetOpt.get()

      # Calculate attack strength (use total AS for all types)
      var attackStrength = 0
      for squadron in fleet.squadrons:
        attackStrength += squadron.combatStrength()

      # Get target from order
      if command.targetSystem.isNone:
        continue

      let targetSystem = command.targetSystem.get()

      # Add validated intent
      result.add(PlanetaryCombatIntent(
        houseId: houseId,
        fleetId: command.fleetId,
        targetColony: targetSystem,
        orderType: $command.commandType,
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
      # Verify fleet is at target location before executing - using entity_manager
      let fleetOpt = state.fleets.entities.getEntity(res.fleetId)
      if fleetOpt.isSome:
        let fleet = fleetOpt.get()
        let targetSystem = res.actualTarget.get()

        if fleet.location == targetSystem:
          # Fleet is at target - execute the assault
          logInfo(LogCategory.lcCombat, &"Executing planetary assault: {res.fleetId} at {targetSystem}")
          let winnerHouse = res.houseId
          if winnerHouse in orders:
            for command in orders[winnerHouse].fleetCommands:
              if command.fleetId == res.fleetId and
                 command.commandType in [FleetCommandType.Bombard, FleetCommandType.Invade, FleetCommandType.Blitz]:
                # Execute the planetary assault
                case command.commandType
                of FleetCommandType.Bombard:
                  resolveBombardment(state, winnerHouse, order, events)
                of FleetCommandType.Invade:
                  resolveInvasion(state, winnerHouse, order, events)
                of FleetCommandType.Blitz:
                  resolveBlitz(state, winnerHouse, order, events)
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
