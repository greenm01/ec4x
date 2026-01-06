## Shared types for unified capacity management system
##
## This module defines common types used across all capacity limit systems in EC4X.
## All capacity systems follow the Check → Track → Enforce pattern with these types.

import std/tables
import ./core

type
  CapacityType* {.pure.} = enum
    FighterSquadron # Per-colony fighter squadron limits (IU-based)
    CapitalSquadron # Per-house capital ship + carrier limits (PU-based)
    TotalSquadron # Per-house total squadron limit (IU-based, prevents escort spam)
    PlanetBreaker # Per-house planet-breaker limits (colony-count-based)
    ConstructionDock # Per-colony construction dock capacity
    CarrierHangar # Per-ship carrier hangar capacity (CV & CX)
    FleetSize # Per-fleet ship count limit (FC tech)
    FleetCount # Per-house combat fleet count limit (SC tech)
    C2Pool # Per-house command & control pool (soft cap with PP penalty)

  ViolationSeverity* {.pure.} = enum
    None # No violation - within limits
    Warning # Near limit (80%+), no enforcement yet
    Violation # Over limit, grace period active
    Critical # Grace period expired, enforcement needed

  EntityIdUnion* = object ## Tagged union for different entity ID types
    case kind*: CapacityType
    of FighterSquadron, ConstructionDock:
      colonyId*: ColonyId
    of CapitalSquadron, TotalSquadron, PlanetBreaker, FleetCount, C2Pool:
      houseId*: HouseId
    of CarrierHangar:
      shipId*: ShipId
    of FleetSize:
      fleetId*: FleetId

  CapacityViolation* = object
    capacityType*: CapacityType
    entity*: EntityIdUnion # Typed entity reference
    current*: int32
    maximum*: int32
    excess*: int32
    severity*: ViolationSeverity
    graceTurnsRemaining*: int32
    violationTurn*: int32

  EnforcementAction* = object
    capacityType*: CapacityType
    entity*: EntityIdUnion # Typed entity reference
    actionType*: string
    affectedUnitIds*: seq[string]
      # Could be SquadronId, ShipId, etc. depending on context
    description*: string

  GracePeriodTracker* = object
    fighterCapacityExpiry*: Table[SystemId, int32]

  ## C2 Pool Analysis Types

  C2PoolAnalysis* = object
    ## Analysis result for house C2 Pool capacity
    houseId*: HouseId
    totalIU*: int32
    scLevel*: int32
    scBonus*: int32
    c2Pool*: int32
    totalFleetCC*: int32
    excess*: int32
    logisticalStrain*: int32
