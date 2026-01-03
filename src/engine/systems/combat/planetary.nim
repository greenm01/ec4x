## Planetary Combat Simultaneous Resolution
##
## Handles simultaneous resolution of Bombard, Invade, and Blitz orders
## to prevent first-mover advantages in planetary assaults.
##
## Per architecture.md: Simultaneous resolution ensures fair multi-house
## combat where all attacking fleets are evaluated before outcomes are applied.

import std/[tables, options, random, strformat]
import ../../types/[simultaneous, game_state, core, event, command, fleet]
import simultaneous_resolver
import ../../../common/logger
import ../squadron/entity
import ../colony/planetary_combat
import ../../state/[engine, iterators]

proc collectPlanetaryCombatIntents*(
    state: GameState, orders: Table[HouseId, CommandPacket]
): seq[PlanetaryCombatIntent] =
  ## Collect all planetary combat attempts (Bombard, Invade, Blitz)
  result = @[]

  for house in state.allHouses:
    if house.id notin orders:
      continue
    let houseId = house.id

    for command in orders[houseId].fleetCommands:
      # Skip non-planetary combat orders
      if command.commandType notin
          [FleetCommandType.Bombard, FleetCommandType.Invade, FleetCommandType.Blitz]:
        continue

      # Validate: fleet exists
      let fleetOpt = state.fleet(command.fleetId)
      if fleetOpt.isNone:
        continue

      let fleet = fleetOpt.get()

      # Calculate attack strength (use total AS for all types)
      var attackStrength: int32 = 0
      for sqId in fleet.squadrons:
        let sq = state.squadron(sqId).get
        attackStrength += state.combatStrength(sq)

      # Get target from order
      if command.targetSystem.isNone:
        continue

      let targetSystem = command.targetSystem.get()

      # Add validated intent (cast SystemId → ColonyId, 1:1 relationship)
      result.add(
        PlanetaryCombatIntent(
          houseId: houseId,
          fleetId: command.fleetId,
          targetColony: ColonyId(targetSystem),
          orderType: $command.commandType,
          attackStrength: attackStrength,
        )
      )

proc detectPlanetaryCombatConflicts*(
    intents: seq[PlanetaryCombatIntent]
): seq[PlanetaryCombatConflict] =
  ## Group planetary combat intents by target colony
  var targetColonies = initTable[ColonyId, seq[PlanetaryCombatIntent]]()

  for intent in intents:
    if intent.targetColony notin targetColonies:
      targetColonies[intent.targetColony] = @[]
    targetColonies[intent.targetColony].add(intent)

  result = @[]
  for colonyId, conflictingIntents in targetColonies:
    result.add(
      PlanetaryCombatConflict(targetColony: colonyId, intents: conflictingIntents)
    )

proc resolvePlanetaryCombatConflict*(
    state: var GameState, conflict: PlanetaryCombatConflict, rng: var Rand
): seq[PlanetaryCombatResult] =
  ## Resolve planetary combat conflict - strongest attacker wins (like colonization)
  result = @[]

  if conflict.intents.len == 0:
    return

  # Single intent = no conflict, just attack
  if conflict.intents.len == 1:
    let intent = conflict.intents[0]
    result.add(
      PlanetaryCombatResult(
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
  let seed = tiebreakerSeed(state.turn, SystemId(conflict.targetColony))
  let winner = resolveConflictByStrength(
    conflict.intents,
    proc(intent: PlanetaryCombatIntent): int = intent.attackStrength,
    seed,
    rng
  )

  logInfo(
    "Combat",
    &"Planetary combat conflict at {conflict.targetColony}: {conflict.intents.len} attackers competing, {winner.houseId} wins",
  )

  # Winner attacks
  result.add(
    PlanetaryCombatResult(
      houseId: winner.houseId,
      fleetId: winner.fleetId,
      originalTarget: winner.targetColony,
      outcome: ResolutionOutcome.Success,
      actualTarget: some(winner.targetColony),
      prestigeAwarded: 0, # Prestige handled by combat resolution
    )
  )

  # All others lose the conflict
  for loser in conflict.intents:
    if loser.houseId != winner.houseId or loser.fleetId != winner.fleetId:
      result.add(
        PlanetaryCombatResult(
          houseId: loser.houseId,
          fleetId: loser.fleetId,
          originalTarget: loser.targetColony,
          outcome: ResolutionOutcome.ConflictLost,
          actualTarget: none(ColonyId),
          prestigeAwarded: 0,
        )
      )

proc resolvePlanetaryCombat*(
    state: var GameState,
    orders: Table[HouseId, CommandPacket],
    rng: var Rand,
    events: var seq[GameEvent],
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
      let fleetOpt = state.fleet(res.fleetId)
      if fleetOpt.isSome:
        let fleet = fleetOpt.get()
        let targetColony = res.actualTarget.get()
        let targetSystem = SystemId(targetColony)  # Cast ColonyId → SystemId (1:1 relationship)

        if fleet.location == targetSystem:
          # Fleet is at target - execute the assault
          logInfo(
            "Combat",
            &"Executing planetary assault: {res.fleetId} at {targetSystem}",
          )
          let winnerHouse = res.houseId
          if winnerHouse in orders:
            for command in orders[winnerHouse].fleetCommands:
              if command.fleetId == res.fleetId and
                  command.commandType in [
                    FleetCommandType.Bombard, FleetCommandType.Invade,
                    FleetCommandType.Blitz,
                  ]:
                # Execute the planetary assault
                case command.commandType
                of FleetCommandType.Bombard:
                  resolveBombardment(state, winnerHouse, command, events)
                of FleetCommandType.Invade:
                  resolveInvasion(state, winnerHouse, command, events)
                of FleetCommandType.Blitz:
                  resolveBlitz(state, winnerHouse, command, events)
                else:
                  discard
                break # Found and executed the command
        else:
          # Fleet not at target - skip this turn (will retry next turn if order persists)
          logDebug(
            "Combat",
            &"Skipping planetary assault: {res.fleetId} not at {targetSystem} (currently at {fleet.location})",
          )

proc wasPlanetaryCombatHandled*(
    results: seq[PlanetaryCombatResult], houseId: HouseId, fleetId: FleetId
): bool =
  ## Check if a planetary combat order was already handled
  for result in results:
    if result.houseId == houseId and result.fleetId == fleetId:
      return true
  return false
