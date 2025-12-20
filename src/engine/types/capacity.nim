## Shared types for unified capacity management system
##
## This module defines common types used across all capacity limit systems in EC4X.
## All capacity systems follow the Check → Track → Enforce pattern with these types.

import std/tables
import ./core

type
  CapacityType* {.pure.} = enum
    FighterSquadron    # Per-colony fighter squadron limits (IU-based)
    CapitalSquadron    # Per-house capital ship + carrier limits (PU-based)
    TotalSquadron      # Per-house total squadron limit (IU-based, prevents escort spam)
    PlanetBreaker      # Per-house planet-breaker limits (colony-count-based)
    ConstructionDock   # Per-colony construction dock capacity
    CarrierHangar      # Per-ship carrier hangar capacity (CV & CX)

  ViolationSeverity* {.pure.} = enum
    None        # No violation - within limits
    Warning     # Near limit (80%+), no enforcement yet
    Violation   # Over limit, grace period active
    Critical    # Grace period expired, enforcement needed

  EntityIdUnion* = object
    ## Tagged union for different entity ID types
    case kind*: CapacityType
    of FighterSquadron, ConstructionDock:
      colonyId*: ColonyId
    of CapitalSquadron, TotalSquadron, PlanetBreaker:
      houseId*: HouseId
    of CarrierHangar:
      shipId*: ShipId

  CapacityViolation* = object
    capacityType*: CapacityType
    entity*: EntityIdUnion         # Typed entity reference
    current*: int32
    maximum*: int32
    excess*: int32
    severity*: ViolationSeverity
    graceTurnsRemaining*: int32
    violationTurn*: int32

  EnforcementAction* = object
    capacityType*: CapacityType
    entity*: EntityIdUnion         # Typed entity reference
    actionType*: string
    affectedUnitIds*: seq[string]  # Could be SquadronId, ShipId, etc. depending on context
    description*: string

  GracePeriodTracker* = object
    totalSquadronsExpiry*: int32
    fighterCapacityExpiry*: Table[SystemId, int32]

