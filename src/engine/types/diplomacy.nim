## Diplomacy System Types
##
## Type definitions for diplomatic relations per diplomacy.md:8.1
##
## Core diplomatic concepts:
## - DiplomaticState: Neutral, Ally, Enemy
## - Violations: Track pact violations and penalties
## - Dishonored Status: Reputational damage after violation

import std/tables
import ../../common/types/[core, diplomacy, units]
import ../prestige # Re-added for PrestigeEvent
import ../config/diplomacy_config

export core.HouseId
export diplomacy.DiplomaticState
export prestige.PrestigeEvent
export diplomacy_config.globalDiplomacyConfig
export units.ShipClass

type
  ## Diplomatic Relations

  DiplomaticRelation* = object
    ## Bilateral relationship between two houses
    state*: DiplomaticState
    sinceTurn*: int  # When this state was established

  DiplomaticRelations* = object
    ## All diplomatic relations for a house
    ## Key is other HouseId, value is relation with that house
    relations*: Table[HouseId, DiplomaticRelation]

  ## Violation Tracking (simplified to match 3-state system)

  ViolationRecord* = object
    ## Record of diplomatic violation (e.g., attacking a Neutral house)
    violator*: HouseId
    victim*: HouseId
    turn*: int
    description*: string

  # DishonoredStatus and DiplomaticIsolation are no longer distinct types
  # They are handled directly by `ViolationHistory` and diplomatic rules.

  ViolationHistory* = object
    ## Track violation history and associated penalties.
    ## Per docs/engine/mechanics/diplomatic-combat-resolution.md
    violations*: seq[ViolationRecord]
    # No explicit `dishonored` or `isolation` objects, just `violations`

  ## Diplomatic Events

  DiplomaticEvent* = object
    ## Diplomatic status change event
    houseId*: HouseId
    otherHouse*: HouseId
    oldState*: DiplomaticState
    newState*: DiplomaticState
    turn*: int
    reason*: string
    prestigeEvents*: seq[PrestigeEvent]  # Prestige changes from this event

  DiplomaticReport* = object
    ## Diplomacy phase report
    turn*: int
    events*: seq[DiplomaticEvent]
    violations*: seq[ViolationRecord]

# FleetClassification and classifyFleet are no longer needed with the 3-state system.

## Configuration accessors (updated for 3-state system)

# These functions are removed as DishonoredStatus and DiplomaticIsolation are removed.
# proc dishonoredDuration*(): int = ...
# proc isolationDuration*(): int = ...
# proc pactReinstatementCooldown*(): int = ...
# proc violationRepeatWindow*(): int = ...

# Prestige penalties are now derived directly from actions and `globalPrestigeConfig.diplomacy`.
# The multipliers are applied where the prestige event is created, not through these accessors.
# proc violationPrestigePenalty*(): int = ...
# proc violationRepeatPenalty*(): int = ...
# proc dishonoredBonusPrestige*(): int = ...

## Helper Procs

proc initDiplomaticRelations*(): DiplomaticRelations =
  ## Initialize empty diplomatic relations
  result = DiplomaticRelations(
    relations: initTable[HouseId, DiplomaticRelation]()
  )

proc initViolationHistory*(): ViolationHistory =
  ## Initialize empty violation history
  result = ViolationHistory(
    violations: @[]
  )

proc getDiplomaticState*(relations: DiplomaticRelations, otherHouse: HouseId): DiplomaticState =
  ## Get diplomatic state with another house (defaults to Neutral)
  if otherHouse in relations.relations:
    return relations.relations[otherHouse].state
  return DiplomaticState.Neutral

proc setDiplomaticState*(relations: var DiplomaticRelations, otherHouse: HouseId,
                        state: DiplomaticState, turn: int) =
  ## Set diplomatic state with another house
  relations.relations[otherHouse] = DiplomaticRelation(
    state: state,
    sinceTurn: turn
  )

# isInPact is removed as there are no "pacts" in the new 3-state system.
# proc isInPact*(relations: DiplomaticRelations, otherHouse: HouseId): bool = ...

proc isEnemy*(relations: DiplomaticRelations, otherHouse: HouseId): bool =
  ## Check if house is enemy (open war)
  return getDiplomaticState(relations, otherHouse) == DiplomaticState.Enemy

proc isHostile*(relations: DiplomaticRelations, otherHouse: HouseId): bool =
  ## Check if house is hostile (tensions escalated)
  return getDiplomaticState(relations, otherHouse) == DiplomaticState.Hostile

proc isHostileOrEnemy*(relations: DiplomaticRelations, otherHouse: HouseId): bool =
  ## Check if house is hostile or enemy (any combat allowed)
  let state = getDiplomaticState(relations, otherHouse)
  return state in {DiplomaticState.Hostile, DiplomaticState.Enemy}

# canFormPact and canReinstatePact are removed as there are no "pacts" in the new 3-state system.
# proc canFormPact*(history: ViolationHistory): bool = ...
# proc canReinstatePact*(history: ViolationHistory, otherHouse: HouseId, currentTurn: int): bool = ...
# proc countRecentViolations*(history: ViolationHistory, currentTurn: int): int = ...
