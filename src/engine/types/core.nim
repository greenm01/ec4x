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

import std/hashes

type
  # Player and House IDs
  PlayerId* = distinct uint32
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

# Hash and equality procs for all ID types
proc `==`*(a, b: PlayerId): bool {.borrow.}
proc hash*(id: PlayerId): Hash {.borrow.}

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
