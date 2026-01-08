## Simultaneous Resolution Type Definitions
##
## Generic framework types for simultaneous fleet order resolution.
import std/options
import ./core

type
  ResolutionOutcome* {.pure.} = enum
    Success
    ConflictLost
    FallbackSuccess
    NoViableTarget
    TargetDestroyed
    InsufficientForce

  OrderResult*[T] = object
    houseId*: HouseId
    fleetId*: FleetId
    originalTarget*: T
    outcome*: ResolutionOutcome
    actualTarget*: Option[T]
    prestigeAwarded*: int32

  # Colonization
  ColonizationIntent* = object
    houseId*: HouseId
    fleetId*: FleetId
    targetSystem*: SystemId
    fleetStrength*: int32

  ColonizationConflict* = object
    targetSystem*: SystemId
    intents*: seq[ColonizationIntent]

  ColonizationResult* = OrderResult[SystemId]

  # Planetary Combat
  PlanetaryCombatIntent* = object
    houseId*: HouseId
    fleetId*: FleetId
    targetColony*: ColonyId # Use ColonyId, not SystemId
    orderType*: string
    attackStrength*: int32

  PlanetaryCombatConflict* = object
    targetColony*: ColonyId
    intents*: seq[PlanetaryCombatIntent]

  PlanetaryCombatResult* = OrderResult[ColonyId]

  # Blockade
  BlockadeIntent* = object
    houseId*: HouseId
    fleetId*: FleetId
    targetColony*: ColonyId
    blockadeStrength*: int32

  BlockadeConflict* = object
    targetColony*: ColonyId
    intents*: seq[BlockadeIntent]

  BlockadeResult* = OrderResult[ColonyId]
