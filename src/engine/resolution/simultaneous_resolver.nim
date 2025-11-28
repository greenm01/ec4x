## Generic Simultaneous Conflict Resolver
##
## Reusable conflict resolution framework for any competitive fleet order type.
## Uses fleet strength + deterministic random tiebreaker.

import std/[algorithm, random, hashes]
import simultaneous_types
import ../../common/types/core

proc resolveConflictByStrength*[IntentType](
  intents: seq[IntentType],
  strengthGetter: proc(intent: IntentType): int,
  tiebreakerSeed: int64,
  rng: var Rand
): IntentType =
  ## Generic conflict resolver using strength + deterministic random tiebreaker
  ##
  ## intents: All competing intents for the same target
  ## strengthGetter: Function to extract strength from intent
  ## tiebreakerSeed: Seed for deterministic random selection (turn + targetId hash)
  ## rng: Random number generator (not used if no ties)
  ##
  ## Returns: The winning intent

  if intents.len == 0:
    raise newException(ValueError, "Cannot resolve conflict with no intents")

  if intents.len == 1:
    return intents[0]

  # Sort by strength (descending)
  var sorted = intents
  sorted.sort do (a, b: IntentType) -> int:
    cmp(strengthGetter(b), strengthGetter(a))  # Descending order

  # Find all intents tied at max strength
  let maxStrength = strengthGetter(sorted[0])
  var topContenders: seq[IntentType] = @[]

  for intent in sorted:
    if strengthGetter(intent) == maxStrength:
      topContenders.add(intent)
    else:
      break  # Sorted, so we can stop at first lower strength

  # If only one at max strength, return it
  if topContenders.len == 1:
    return topContenders[0]

  # Multiple tied at max strength - use deterministic random
  var conflictRng = initRand(tiebreakerSeed)
  let winnerIndex = conflictRng.rand(topContenders.len - 1)
  return topContenders[winnerIndex]

proc colonizationStrength*(intent: ColonizationIntent): int =
  ## Extract fleet strength from colonization intent
  return intent.fleetStrength

proc planetaryCombatStrength*(intent: PlanetaryCombatIntent): int =
  ## Extract attack strength from planetary combat intent
  return intent.attackStrength

proc blockadeStrength*(intent: BlockadeIntent): int =
  ## Extract blockade strength from blockade intent
  return intent.blockadeStrength

proc espionageStrength*(intent: EspionageIntent): int =
  ## Extract espionage strength from espionage intent
  return intent.espionageStrength

proc tiebreakerSeed*(turn: int, targetId: SystemId): int64 =
  ## Generate deterministic tiebreaker seed from turn and target
  return turn.int64 xor hash(targetId).int64
