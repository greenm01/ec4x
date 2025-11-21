## Starbase Combat Integration
##
## Starbases participate in space combat as part of Task Forces.
## This module extends the space combat system to handle starbase-specific rules.
##
## Based on EC4X specifications Section 7.0 Combat (operations.md)

import std/[options, sequtils]
import types, cer, targeting, damage
import ../../common/types/[core, units, combat as commonCombat]
import ../squadron

export CombatSquadron, TaskForce

## Starbase Detection (Section 7.2.4)
##
## Starbases have enhanced detection capabilities (ELI+2 modifier)
## and can counter cloaked raiders during pre-combat detection.

proc hasStarbaseDetection*(taskForce: TaskForce): bool =
  ## Check if task force contains a starbase for enhanced detection
  ## Starbases provide ELI+2 modifier for detection rolls
  for squadron in taskForce.squadrons:
    if squadron.squadron.flagship.shipClass == ShipClass.Starbase:
      return true
  return false

proc getStarbaseDetectionBonus*(taskForce: TaskForce): int =
  ## Get detection bonus from starbases in task force
  ## Per reference.md:9.1, Starbases have ELI+2 capability
  if hasStarbaseDetection(taskForce):
    return 2  # ELI+2 modifier
  return 0

## Starbase Combat Integration
##
## Starbases follow the same combat rules as capital ships:
## - Participate in Phase 3 (Main Engagement)
## - Use CER for effectiveness
## - Follow destruction protection rules
## - State transitions: Undamaged → Crippled → Destroyed
##
## Per reference.md:9.1 - Starbase (WEP1):
##   AS: 45, DS: 50, Tech: 3, Cost: 300 PP

proc createStarbaseCombatSquadron*(
  starbaseId: SquadronId,
  owner: HouseId,
  location: SystemId,
  techLevel: int = 3
): CombatSquadron =
  ## Create a combat squadron for a starbase
  ## Starbases are always solo units (one per squadron)
  ##
  ## TODO M3: Load starbase stats from system state
  ## TODO M3: Apply WEP tech modifiers
  ## TODO M3: Handle starbase damage persistence across turns

  let starbase = newEnhancedShip(
    ShipClass.Starbase,
    techLevel = techLevel,
    name = "Starbase"
  )

  let squadron = newSquadron(
    starbase,
    id = starbaseId,
    owner = owner,
    location = location
  )

  result = CombatSquadron(
    squadron: squadron,
    state: CombatState.Undamaged,
    damageThisTurn: 0,
    crippleRound: 0,
    bucket: TargetBucket.Capital,  # Starbases are in capital bucket
    targetWeight: 1.0
  )

## Starbase Guard Orders (Section 6.2.5)
##
## Starbases and guarding fleets form a defensive Task Force when
## confronted by hostile ships with orders 05-08 (Attack, Raid, Invade, Blitz)

proc shouldStarbaseJoinCombat*(
  attackerOrders: seq[int],  # Fleet orders from attacking forces
  defenderHasStarbase: bool
): bool =
  ## Determine if starbase should join combat based on attacker orders
  ## Per operations.md:6.2.5 - Starbases only engage against orders 05-08
  ##
  ## Order codes:
  ## 05 = Attack
  ## 06 = Raid
  ## 07 = Invade
  ## 08 = Blitz

  if not defenderHasStarbase:
    return false

  for order in attackerOrders:
    if order in [5, 6, 7, 8]:  # Attack, Raid, Invade, Blitz
      return true

  return false

## Starbase Hacking (Section 6.2.11)
##
## Scouts can hack starbases for intelligence gathering.
## This is NOT combat - it's a separate intelligence operation.
##
## TODO M3: Implement starbase hacking mechanics
## - Solo Scout requirement
## - Detection rolls
## - Intelligence gathering (economic & R&D data)
## - Success/failure outcomes

proc attemptStarbaseHack*(
  scout: Squadron,
  targetStarbase: Squadron,
  rng: var CombatRNG
): tuple[success: bool, detected: bool, intel: string] =
  ## Attempt to hack a starbase with a Scout
  ## Returns (success, detected, intel_gathered)
  ##
  ## TODO M3: Implement hacking mechanics
  ## TODO M3: Detection rolls based on ELI levels
  ## TODO M3: Intelligence data format

  result = (false, false, "")
  # STUB: Always fails for now
  echo "STUB: Starbase hacking not yet implemented"

## Notes for Future Implementation
##
## 1. Starbase Damage Persistence:
##    - Unlike fleet squadrons, starbases remain at systems between turns
##    - Starbase damage state must be saved in system state
##    - Crippled starbases have reduced AS (× 0.5)
##    - Destroyed starbases are removed from system
##
## 2. Starbase Construction:
##    - Built via colony production orders
##    - Tech requirements: CST3 (per reference.md)
##    - Cost: 300 PP, 15 MC upkeep (per reference.md:9.1)
##
## 3. Starbase Upgrades:
##    - Apply WEP tech modifiers like other ships
##    - Base stats at WEP1: AS=45, DS=50
##    - WEP upgrades increase both AS and DS by 10% per level
##
## 4. Multi-Starbase Systems:
##    - Spec doesn't explicitly limit starbases per system
##    - Implementation should probably allow 1 per system for balance
##    - Multiple starbases would form single squadron (unlikely scenario)
