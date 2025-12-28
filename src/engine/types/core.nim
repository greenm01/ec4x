## Core Type Definitions for EC4X
##
## This module defines all entity ID types used throughout the game engine.
## All IDs are distinct uint32 types for type safety and efficient storage.
##
## ## Design Rationale
##
## **Centralized ID Definitions:**
## - Single source of truth for all entity identifiers
## - Prevents circular dependencies between type modules
## - Enables any module to reference any entity type
##
## **Type Safety:**
## - Distinct types prevent ID confusion (can't use FleetId where ColonyId expected)
## - Compile-time enforcement of correct ID usage
## - Zero runtime overhead (compiles to uint32)
##
## **Data-Oriented Design:**
## - Fixed-size IDs (4 bytes) enable efficient table lookups
## - Hash/equality procs enable use as Table/HashSet keys
## - Sequential allocation supports cache-friendly iteration

import std/[hashes, tables]

type
  # House IDs
  HouseId* = distinct uint32

  # Map IDs
  SystemId* = distinct uint32

  # Colony and Facility IDs
  ColonyId* = distinct uint32
  StarbaseId* = distinct uint32
  SpaceportId* = distinct uint32
  ShipyardId* = distinct uint32
  DrydockId* = distinct uint32

  # Military IDs
  FleetId* = distinct uint32
  SquadronId* = distinct uint32
  ShipId* = distinct uint32
  GroundUnitId* = distinct uint32

  # Production
  ConstructionProjectId* = distinct uint32
  RepairProjectId* = distinct uint32

  # Population transfers (Guild Services)
  PopulationTransferId* = distinct uint32

  # Reusable game entity manager for all game assets
  EntityManager*[ID, T] = object
    data*: seq[T]
    index*: Table[ID, int] # Maps ID to the index in the 'data' sequence

  # Counters for DoD collections
  IdCounters* = object
    nextHouseId*: uint32
    nextSystemId*: uint32
    nextColonyId*: uint32
    nextStarbaseId*: uint32
    nextSpaceportId*: uint32
    nextShipyardId*: uint32
    nextDrydockId*: uint32
    nextFleetId*: uint32
    nextSquadronId*: uint32
    nextShipId*: uint32
    nextGroundUnitId*: uint32
    nextConstructionProjectId*: uint32
    nextRepairProjectId*: uint32
    nextPopulationTransferId*: uint32

# Hash and equality procs for all ID types
proc `==`*(a, b: HouseId): bool {.borrow.}
proc hash*(id: HouseId): Hash {.borrow.}

proc `==`*(a, b: SystemId): bool {.borrow.}
proc hash*(id: SystemId): Hash {.borrow.}

proc `==`*(a, b: ColonyId): bool {.borrow.}
proc hash*(id: ColonyId): Hash {.borrow.}

proc `==`*(a, b: StarbaseId): bool {.borrow.}
proc hash*(id: StarbaseId): Hash {.borrow.}

proc `==`*(a, b: SpaceportId): bool {.borrow.}
proc hash*(id: SpaceportId): Hash {.borrow.}

proc `==`*(a, b: ShipyardId): bool {.borrow.}
proc hash*(id: ShipyardId): Hash {.borrow.}

proc `==`*(a, b: DrydockId): bool {.borrow.}
proc hash*(id: DrydockId): Hash {.borrow.}

proc `==`*(a, b: FleetId): bool {.borrow.}
proc hash*(id: FleetId): Hash {.borrow.}

proc `==`*(a, b: SquadronId): bool {.borrow.}
proc hash*(id: SquadronId): Hash {.borrow.}

proc `==`*(a, b: ShipId): bool {.borrow.}
proc hash*(id: ShipId): Hash {.borrow.}

proc `==`*(a, b: GroundUnitId): bool {.borrow.}
proc hash*(id: GroundUnitId): Hash {.borrow.}

proc `==`*(a, b: ConstructionProjectId): bool {.borrow.}
proc hash*(id: ConstructionProjectId): Hash {.borrow.}
proc `==`*(a, b: RepairProjectId): bool {.borrow.}
proc hash*(id: RepairProjectId): Hash {.borrow.}

proc `==`*(a, b: PopulationTransferId): bool {.borrow.}
proc hash*(id: PopulationTransferId): Hash {.borrow.}

proc `$`*(id: SystemId): string {.borrow.}
proc `$`*(id: ColonyId): string {.borrow.}
proc `$`*(id: FleetId): string {.borrow.}
proc `$`*(id: HouseId): string {.borrow.}
proc `$`*(id: SquadronId): string {.borrow.}
proc `$`*(id: ShipId): string {.borrow.}
proc `$`*(id: GroundUnitId): string {.borrow.}
proc `$`*(id: ConstructionProjectId): string {.borrow.}
proc `$`*(id: RepairProjectId): string {.borrow.}
proc `$`*(id: PopulationTransferId): string {.borrow.}
proc `$`*(id: StarbaseId): string {.borrow.}
proc `$`*(id: SpaceportId): string {.borrow.}
proc `$`*(id: ShipyardId): string {.borrow.}
proc `$`*(id: DrydockId): string {.borrow.}
