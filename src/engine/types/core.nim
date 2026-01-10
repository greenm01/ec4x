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
  # Unified facility IDs (Neoria = production, Kastra = defense)
  NeoriaId* = distinct uint32
  KastraId* = distinct uint32

  # Military IDs
  FleetId* = distinct uint32
  ShipId* = distinct uint32
  GroundUnitId* = distinct uint32

  # Production
  ConstructionProjectId* = distinct uint32
  RepairProjectId* = distinct uint32

  # Population transfers (Guild Services)
  PopulationTransferId* = distinct uint32

  # Diplomacy
  ProposalId* = distinct uint32

  # Reusable game entity manager for all game assets
  EntityManager*[ID, T] = object
    data*: seq[T]
    index*: Table[ID, int] # Maps ID to the index in the 'data' sequence

  # Counters for DoD collections
  IdCounters* = object
    nextHouseId*: uint32
    nextSystemId*: uint32
    nextColonyId*: uint32
    nextNeoriaId*: uint32  # Unified production facilities
    nextKastraId*: uint32  # Unified defense facilities
    nextFleetId*: uint32
    nextShipId*: uint32
    nextGroundUnitId*: uint32
    nextConstructionProjectId*: uint32
    nextRepairProjectId*: uint32
    nextPopulationTransferId*: uint32
    nextProposalId*: uint32

# Hash and equality procs for all ID types
proc `==`*(a, b: HouseId): bool {.borrow.}
proc hash*(id: HouseId): Hash {.borrow.}

proc `==`*(a, b: SystemId): bool {.borrow.}
proc hash*(id: SystemId): Hash {.borrow.}

proc `==`*(a, b: ColonyId): bool {.borrow.}
proc hash*(id: ColonyId): Hash {.borrow.}

proc `==`*(a, b: NeoriaId): bool {.borrow.}
proc hash*(id: NeoriaId): Hash {.borrow.}

proc `==`*(a, b: KastraId): bool {.borrow.}
proc hash*(id: KastraId): Hash {.borrow.}

proc `==`*(a, b: FleetId): bool {.borrow.}
proc hash*(id: FleetId): Hash {.borrow.}

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

proc `==`*(a, b: ProposalId): bool {.borrow.}
proc hash*(id: ProposalId): Hash {.borrow.}

proc `$`*(id: SystemId): string {.borrow.}
proc `$`*(id: ColonyId): string {.borrow.}
proc `$`*(id: FleetId): string {.borrow.}
proc `$`*(id: HouseId): string {.borrow.}
proc `$`*(id: ShipId): string {.borrow.}
proc `$`*(id: GroundUnitId): string {.borrow.}
proc `$`*(id: ConstructionProjectId): string {.borrow.}
proc `$`*(id: RepairProjectId): string {.borrow.}
proc `$`*(id: PopulationTransferId): string {.borrow.}
proc `$`*(id: NeoriaId): string {.borrow.}
proc `$`*(id: KastraId): string {.borrow.}
proc `$`*(id: ProposalId): string {.borrow.}
