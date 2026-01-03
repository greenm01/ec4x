## Colony Conflicts - Simultaneous Colonization Resolution
##
## Handles conflicts when multiple houses attempt to colonize the same system
## on the same turn. Determines priority and winners.
##
## Called by @systems/conflict/simultaneous.nim during conflict phase

import std/[tables, options, random]
import ../../types/[core, game_state, starmap]
import ../../state/engine
import ./engine as colony_engine

type
  ColonizationIntent* = object ## Intent to colonize a system
    houseId*: HouseId
    fleetId*: FleetId
    targetSystem*: SystemId
    fleetStrength*: int32 # For priority determination
    hasStandingOrders*: bool # Manual orders take priority

  ColonizationConflict* = object
    ## Multiple houses attempting to colonize the same system
    targetSystem*: SystemId
    intents*: seq[ColonizationIntent]

  ConflictResolution* = object ## Result of resolving a colonization conflict
    winner*: Option[ColonizationIntent]
    losers*: seq[ColonizationIntent]
    colonyId*: Option[ColonyId]

proc determineWinner*(
    conflict: ColonizationConflict, rng: var Rand
): ColonizationIntent =
  ## Determine winner from competing intents
  ##
  ## Priority rules:
  ## 1. Manual orders beat standing commands
  ## 2. Stronger fleet wins
  ## 3. Random tiebreaker

  if conflict.intents.len == 0:
    raise newException(ValueError, "Cannot determine winner from empty intents")

  if conflict.intents.len == 1:
    return conflict.intents[0]

  # Separate manual vs standing commands
  var manualIntents: seq[ColonizationIntent] = @[]
  var standingIntents: seq[ColonizationIntent] = @[]

  for intent in conflict.intents:
    if intent.hasStandingOrders:
      standingIntents.add(intent)
    else:
      manualIntents.add(intent)

  # Manual orders take priority
  let candidates = if manualIntents.len > 0: manualIntents else: standingIntents

  # Find strongest fleet(s)
  var maxStrength: int32 = 0
  for intent in candidates:
    if intent.fleetStrength > maxStrength:
      maxStrength = intent.fleetStrength

  var strongest: seq[ColonizationIntent] = @[]
  for intent in candidates:
    if intent.fleetStrength == maxStrength:
      strongest.add(intent)

  # Random tiebreaker among equally strong fleets
  if strongest.len == 1:
    return strongest[0]
  else:
    let idx = rng.rand(strongest.len - 1)
    return strongest[idx]

proc resolveConflict*(
    state: var GameState,
    conflict: ColonizationConflict,
    planetClass: PlanetClass,
    resources: ResourceRating,
    ptuCount: int32,
    rng: var Rand,
): ConflictResolution =
  ## Resolve a colonization conflict
  ##
  ## Returns winner, losers, and colony ID if successful

  if conflict.intents.len == 0:
    return ConflictResolution(
      winner: none(ColonizationIntent), losers: @[], colonyId: none(ColonyId)
    )

  # Determine winner
  let winner = determineWinner(conflict, rng)

  # Attempt colonization for winner
  let result = colony_engine.establishColony(
    state, winner.houseId, winner.targetSystem, planetClass, resources, ptuCount
  )

  # Collect losers
  var losers: seq[ColonizationIntent] = @[]
  for intent in conflict.intents:
    if intent.fleetId != winner.fleetId:
      losers.add(intent)

  return
    ConflictResolution(winner: some(winner), losers: losers, colonyId: result.colonyId)

proc detectConflicts*(intents: seq[ColonizationIntent]): seq[ColonizationConflict] =
  ## Group colonization intents by target system to detect conflicts
  ##
  ## Returns sequence of conflicts (one per contested system)
  var systemTargets = initTable[SystemId, seq[ColonizationIntent]]()

  # Group by target system
  for intent in intents:
    if intent.targetSystem notin systemTargets:
      systemTargets[intent.targetSystem] = @[]
    systemTargets[intent.targetSystem].add(intent)

  # Create conflict objects for contested systems
  result = @[]
  for systemId, conflictingIntents in systemTargets:
    result.add(
      ColonizationConflict(targetSystem: systemId, intents: conflictingIntents)
    )
