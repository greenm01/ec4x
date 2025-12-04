## Shared types for unified capacity management system
##
## This module defines common types used across all capacity limit systems in EC4X.
## All capacity systems follow the Check → Track → Enforce pattern with these types.

import ../../../common/types/core

type
  CapacityType* {.pure.} = enum
    ## Type of capacity being limited
    FighterSquadron    # Per-colony fighter squadron limits (IU-based)
    CapitalSquadron    # Per-house capital ship + carrier limits (PU-based)
    PlanetBreaker      # Per-house planet-breaker limits (colony-count-based)
    ConstructionDock   # Per-colony construction dock capacity
    CarrierHangar      # Per-ship carrier hangar capacity (CV & CX)

  ViolationSeverity* {.pure.} = enum
    ## Severity level of capacity violation
    None        # No violation - within limits
    Warning     # Near limit (80%+), no enforcement yet
    Violation   # Over limit, grace period active
    Critical    # Grace period expired, enforcement needed

  CapacityViolation* = object
    ## Status of a capacity check for an entity
    capacityType*: CapacityType
    entityId*: string              # Colony ID, House ID, or Ship ID
    current*: int                  # Current count
    maximum*: int                  # Maximum allowed
    excess*: int                   # Amount over limit (0 if within)
    severity*: ViolationSeverity
    graceTurnsRemaining*: int      # Turns until enforcement (0 = enforce now)
    violationTurn*: int            # Turn when violation started

  EnforcementAction* = object
    ## Action taken to enforce a capacity limit
    capacityType*: CapacityType
    entityId*: string              # Colony ID, House ID, or Ship ID
    actionType*: string            # "disband", "block_commission", "auto_scrap", etc.
    affectedUnits*: seq[string]    # IDs of units affected
    description*: string           # Human-readable description for logging/events

export core.SystemId, core.HouseId
