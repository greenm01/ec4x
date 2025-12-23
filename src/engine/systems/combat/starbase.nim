## Starbase Combat Integration
##
## Starbases participate in space combat as part of Task Forces.
## This module extends the space combat system to handle starbase-specific rules.
##
## Based on EC4X specifications Section 7.0 Combat (operations.md)

import std/[options, sequtils]
import types, cer, targeting, damage
import ../../common/types/[core, units, combat as commonCombat]
import ../../common/logger
import ../squadron

export CombatSquadron, TaskForce

## Starbase Detection (Section 7.2.4)
##
## Starbases have enhanced detection capabilities (ELI+2 modifier)
## and can counter cloaked raiders during pre-combat detection.

proc hasStarbaseDetection*(taskForce: TaskForce): bool =
  ## Check if task force has starbase facilities for enhanced detection
  ## Starbases provide ELI+2 modifier for detection rolls
  ##
  ## NOTE: Starbases are facilities (not squadrons), loaded from colony.starbases
  ## into TaskForce.facilities during combat initialization
  return taskForce.facilities.len > 0

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
  ## NOTE: This function is a legacy helper that's not actually used.
  ## Real starbase combat implementation is in combat_resolution.nim:105-140 which:
  ## ✅ Loads starbase data from colony.starbases (state)
  ## ✅ Applies WEP tech modifiers via getShipStats()
  ## ✅ Handles damage persistence via starbase.isCrippled field

  let starbase = newShip(
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
## **IMPLEMENTATION STATUS: ✅ COMPLETE**
##
## Starbase hacking is fully implemented through the spy scout system (NOT through combat).
## The stub below is orphaned code from an earlier design and is never called.
##
## **Complete Implementation Path:**
##
## 1. **Order Execution** (commands/executor.nim)
##    - executeHackStarbaseOrder() validates single-scout requirement
##    - Creates ActiveSpyMission for persistent tracking
##    - Scouts remain in system gathering intelligence per turn
##
## 2. **Detection Mechanics** (intelligence/detection.nim)
##    Per espionage.toml: ELI vs CLK detection rolls
##    - Opposed rolls: 1d10 + ELI vs 1d10 + CLK
##    - Starbase bonus to defender's ELI
##    - ELI >= CLK = Detected
##
## 3. **Turn Resolution** (resolution/phases/conflict_phase.nim)
##    - Fleet-based spy missions resolved in Conflict Phase
##    - Uses ELI vs CLK detection mechanics
##    - Detected missions fail, generate detection events
##
## 4. **Intelligence Generation** (intelligence/generator.nim:156)
##    Per operations.md:6.2.11 - Economic and R&D intelligence:
##    - generateStarbaseIntelReport(): Economic (treasury, income, tax) + R&D (tech levels, allocations)
##    - Intelligence corruption handling (disinformation, dishonor effects)
##    - Returns StarbaseIntelReport with complete house-level strategic intelligence
##
## 5. **Integration** (resolution/economy_resolution.nim:2004)
##    - Called during Maintenance phase for all active spy scouts
##    - Reports delivered to player's intelligence database
##
## **Architectural Separation:**
## - Combat module: Handles starbase combat mechanics (AS/DS, CER rolls, critical hits)
## - Intelligence module: Handles covert espionage operations (no combat involvement)

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
