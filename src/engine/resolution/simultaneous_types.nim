## Simultaneous Resolution Type Definitions
##
## Generic framework types for simultaneous fleet order resolution.
## Supports colonization, assault, fleet mergers, and other competitive orders.

import std/options
import ../order_types
import ../../common/types/core

type
  ResolutionOutcome* {.pure.} = enum
    ## Outcome of a competitive order resolution
    Success          ## Order succeeded (won conflict or no conflict)
    ConflictLost     ## Lost conflict to stronger competitor
    FallbackSuccess  ## Original target failed, but fallback succeeded
    NoViableTarget   ## No viable alternative target found
    TargetDestroyed  ## Target destroyed before operation completed
    InsufficientForce ## Not enough military force to succeed

  OrderResult*[T] = object
    ## Generic result type for competitive order resolution
    houseId*: HouseId
    fleetId*: FleetId
    originalTarget*: T                # Original intended target
    outcome*: ResolutionOutcome
    actualTarget*: Option[T]          # Actual target (if successful)
    prestigeAwarded*: int             # Prestige earned (if any)

  # Colonization-specific types
  ColonizationIntent* = object
    ## Intent to colonize a system
    houseId*: HouseId
    fleetId*: FleetId
    targetSystem*: SystemId
    fleetStrength*: int               # Total AS for conflict resolution
    hasStandingOrders*: bool          # For fallback logic

  ColonizationConflict* = object
    ## Multiple houses attempting to colonize same system
    targetSystem*: SystemId
    intents*: seq[ColonizationIntent]

  ColonizationResult* = OrderResult[SystemId]
    ## Result of colonization resolution

  # ===================================================================
  # PLANETARY COMBAT (Bombard, Invade, Blitz)
  # ===================================================================

  PlanetaryCombatIntent* = object
    ## Intent to attack a colony (bombardment or invasion)
    houseId*: HouseId
    fleetId*: FleetId
    targetColony*: SystemId
    orderType*: string                # "Bombard", "Invade", or "Blitz"
    attackStrength*: int              # Total AS for bombardment or ground troops for invasion

  PlanetaryCombatConflict* = object
    ## Multiple houses attacking same colony
    targetColony*: SystemId
    intents*: seq[PlanetaryCombatIntent]

  PlanetaryCombatResult* = OrderResult[SystemId]
    ## Result of planetary combat resolution

  # ===================================================================
  # BLOCKADE
  # ===================================================================

  BlockadeIntent* = object
    ## Intent to blockade a colony
    houseId*: HouseId
    fleetId*: FleetId
    targetColony*: SystemId
    blockadeStrength*: int            # Total AS for blockade strength

  BlockadeConflict* = object
    ## Multiple houses blockading same colony
    targetColony*: SystemId
    intents*: seq[BlockadeIntent]

  BlockadeResult* = OrderResult[SystemId]
    ## Result of blockade resolution

  # ===================================================================
  # ESPIONAGE (SpyPlanet, SpySystem, HackStarbase)
  # ===================================================================

  EspionageIntent* = object
    ## Intent to conduct espionage in a system
    houseId*: HouseId
    fleetId*: FleetId
    targetSystem*: SystemId
    orderType*: string                # "SpyPlanet", "SpySystem", or "HackStarbase"
    espionageStrength*: int           # House prestige (higher prestige = better intelligence)
    isDishonored*: bool               # Dishonored houses go to end of priority list

  EspionageConflict* = object
    ## Multiple houses conducting espionage in same system
    targetSystem*: SystemId
    intents*: seq[EspionageIntent]

  EspionageResult* = OrderResult[SystemId]
    ## Result of espionage resolution
