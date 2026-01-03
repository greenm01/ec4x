## Batch Iteration Patterns for Data-Oriented Processing
##
## Provides iterators for common game state access patterns,
## enabling cache-friendly batch processing during turn resolution.
##
## Design Philosophy:
## - Eliminate 99 repeated loop patterns across 22 files
## - Clear intent (coloniesOwned vs manual filtering)
## - Consistent semantics (always yields same entity type)
## - Batch-friendly (process all entities of type together)
##
## Usage:
##   for colony in state.coloniesOwned(houseId):
##     # Process colony
##
## NOTE: These are read-only iterators. For mutations, use state_helpers.
import std/tables, std/options
import
  ../types/[colony, core, fleet, game_state, house, ship, squadron, facilities, starmap]

include ./entity_manager

# src/engine/state/queries.nim
iterator fleetsInSystem*(state: GameState, sysId: SystemId): Fleet =
  if state.fleets.bySystem.contains(sysId):
    for fId in state.fleets.bySystem[sysId]:
      if state.fleets.entities.index.contains(fId):
        yield state.fleets.entities.entity(fId).get()

iterator squadronsInSystem*(state: GameState, sysId: SystemId): Squadron =
  for fleetEntity in state.fleetsInSystem(sysId):
    for sqId in fleetEntity.squadrons:
      if state.squadrons.entities.index.contains(sqId):
        yield state.squadrons.entities.entity(sqId).get()

iterator allShips*(state: GameState): Ship =
  for shipId in state.ships.entities.index.keys:
    yield state.ships.entities.entity(shipId).get()

iterator allHouses*(state: GameState): House =
  for houseId in state.houses.entities.index.keys:
    yield state.houses.entities.entity(houseId).get()

iterator coloniesOwned*(state: GameState, houseId: HouseId): Colony =
  ## Iterate all colonies owned by a house (O(1) lookup via index)
  ##
  ## Example:
  ##   var totalProduction = 0
  ##   for colony in state.coloniesOwned(houseId):
  ##     totalProduction += colony.production
  if state.colonies.byOwner.contains(houseId):
    for colonyId in state.colonies.byOwner[houseId]:
      if state.colonies.entities.index.contains(colonyId):
        yield state.colonies.entities.entity(colonyId).get()

iterator coloniesOwnedWithId*(
    state: GameState, houseId: HouseId
): tuple[id: SystemId, colony: Colony] =
  ## Iterate colonies with system IDs (for mutations, O(1) lookup via index)
  ##
  ## Example:
  ##   for (systemId, colony) in state.coloniesOwnedWithId(houseId):
  ##     state.withColony(systemId):
  ##       colony.production = calculateProduction(colony)
  if state.colonies.byOwner.contains(houseId):
    for colonyId in state.colonies.byOwner[houseId]:
      if state.colonies.entities.index.contains(colonyId):
        let colony = state.colonies.entities.entity(colonyId).get()
        yield (colony.systemId, colony)

iterator fleetsOwned*(state: GameState, houseId: HouseId): Fleet =
  ## Iterate all fleets owned by a house
  ##
  ## Example:
  ##   var totalMaintenance = 0
  ##   for fleet in state.fleetsOwned(houseId):
  ##     totalMaintenance += fleet.maintenanceCost
  for fleetId in state.fleets.entities.index.keys:
    let fleet = state.fleets.entities.entity(fleetId).get()
    if fleet.houseId == houseId:
      yield fleet

iterator fleetsOwnedWithId*(
    state: GameState, houseId: HouseId
): tuple[id: FleetId, fleet: Fleet] =
  ## Iterate fleets with IDs (for mutations)
  ##
  ## Example:
  ##   for (fleetId, fleet) in state.fleetsOwnedWithId(houseId):
  ##     state.withFleet(fleetId):
  ##       fleet.status = FleetStatus.Reserve
  for fleetId in state.fleets.entities.index.keys:
    let fleet = state.fleets.entities.entity(fleetId).get()
    if fleet.houseId == houseId:
      yield (fleetId, fleet)

# Location-based iterators (entities at a location)

iterator fleetsAtSystem*(state: GameState, systemId: SystemId): Fleet =
  ## Iterate all fleets at a system (O(1) lookup via index)
  ##
  ## Example:
  ##   var fleetsPresent: seq[Fleet] = @[]
  ##   for fleet in state.fleetsAtSystem(systemId):
  ##     fleetsPresent.add(fleet)
  if state.fleets.bySystem.contains(systemId):
    for fleetId in state.fleets.bySystem[systemId]:
      if state.fleets.entities.index.contains(fleetId):
        yield state.fleets.entities.entity(fleetId).get()

iterator fleetsAtSystemWithId*(
    state: GameState, systemId: SystemId
): tuple[id: FleetId, fleet: Fleet] =
  ## Iterate fleets at system with IDs (for mutations, O(1) lookup via index)
  ##
  ## Example:
  ##   for (fleetId, fleet) in state.fleetsAtSystemWithId(systemId):
  ##     if shouldRetreat(fleet):
  ##       state.withFleet(fleetId):
  ##         fleet.retreating = true
  if state.fleets.bySystem.contains(systemId):
    for fleetId in state.fleets.bySystem[systemId]:
      if state.fleets.entities.index.contains(fleetId):
        let fleet = state.fleets.entities.entity(fleetId).get()
        yield (fleetId, fleet)

iterator fleetsAtSystemForHouse*(
    state: GameState, systemId: SystemId, houseId: HouseId
): Fleet =
  ## Iterate fleets of a specific house at a system (O(1) lookup via index)
  ##
  ## Example:
  ##   var myFleetsHere: seq[Fleet] = @[]
  ##   for fleet in state.fleetsAtSystemForHouse(systemId, myHouseId):
  ##     myFleetsHere.add(fleet)
  if state.fleets.bySystem.contains(systemId):
    for fleetId in state.fleets.bySystem[systemId]:
      if state.fleets.entities.index.contains(fleetId):
        let fleet = state.fleets.entities.entity(fleetId).get()
        if fleet.houseId == houseId:
          yield fleet

iterator fleetsAtSystemForHouseWithId*(
    state: GameState, systemId: SystemId, houseId: HouseId
): tuple[id: FleetId, fleet: Fleet] =
  ## Iterate house fleets at system with IDs (for mutations, O(1) lookup via index)
  if state.fleets.bySystem.contains(systemId):
    for fleetId in state.fleets.bySystem[systemId]:
      if state.fleets.entities.index.contains(fleetId):
        let fleet = state.fleets.entities.entity(fleetId).get()
        if fleet.houseId == houseId:
          yield (fleetId, fleet)

# Condition-based iterators (entities matching criteria)

iterator blockadedColonies*(state: GameState): Colony =
  ## Iterate all currently blockaded colonies
  ##
  ## Example:
  ##   var blockadeCount = 0
  ##   for colony in state.blockadedColonies():
  ##     blockadeCount += 1
  for colonyId in state.colonies.entities.index.keys:
    let colony = state.colonies.entities.entity(colonyId).get()
    if colony.blockaded:
      yield colony

iterator blockadedColoniesWithId*(
    state: GameState
): tuple[id: ColonyId, colony: Colony] =
  ## Iterate blockaded colonies with IDs (for mutations)
  for colonyId in state.colonies.entities.index.keys:
    let colony = state.colonies.entities.entity(colonyId).get()
    if colony.blockaded:
      yield (colonyId, colony)

iterator fleetsWithOrders*(
    state: GameState
): tuple[id: FleetId, fleet: Fleet, command: FleetCommand] =
  ## Iterate fleets that have persistent orders
  ##
  ## Example:
  ##   for (fleetId, fleet, command) in state.fleetsWithOrders():
  ##     # Execute fleet order
  for (id, fleet) in state.allFleetsWithId():
    if fleet.command.isSome():
      yield (id, fleet, fleet.command.get())

iterator eliminatedHouses*(state: GameState): House =
  ## Iterate eliminated houses
  ##
  ## Example:
  ##   for house in state.eliminatedHouses():
  ##     echo house.name, " has been eliminated"
  for (id, house) in state.allHousesWithId():
    if house.isEliminated:
      yield house

iterator activeHouses*(state: GameState): House =
  ## Iterate non-eliminated houses
  ##
  ## Example:
  ##   for house in state.activeHouses():
  ##     # Process active house
  for (id, house) in state.allHousesWithId():
    if not house.isEliminated:
      yield house

iterator activeHousesWithId*(state: GameState): tuple[id: HouseId, house: House] =
  ## Iterate active houses with IDs (for mutations)
  ##
  ## Example:
  ##   for (houseId, house) in state.activeHousesWithId():
  ##     state.withHouse(houseId):
  ##       house.prestige += bonus
  for (id, house) in state.allHousesWithId():
    if not house.isEliminated:
      yield (id, house)

# Utility iterators (helper patterns)

iterator allColoniesWithId*(state: GameState): tuple[id: SystemId, colony: Colony] =
  ## Iterate all colonies with IDs (for batch processing)
  ##
  ## Example:
  ##   for (systemId, colony) in state.allColoniesWithId():
  ##     state.withColony(systemId):
  ##       colony.production = calculateProduction(colony)
  for colonyId in state.colonies.entities.index.keys:
    yield (colonyId, state.colonies.entities.entity(colonyId).get())

iterator allFleetsWithId*(state: GameState): tuple[id: FleetId, fleet: Fleet] =
  ## Iterate all fleets with IDs (for batch processing)
  ##
  ## Example:
  ##   for (fleetId, fleet) in state.allFleetsWithId():
  ##     state.withFleet(fleetId):
  ##       fleet.fuelRemaining -= 1
  for fleetId in state.fleets.entities.index.keys:
    yield (fleetId, state.fleets.entities.entity(fleetId).get())

iterator allHousesWithId*(state: GameState): tuple[id: HouseId, house: House] =
  ## Iterate all houses with IDs (for batch processing)
  ##
  ## Example:
  ##   for (houseId, house) in state.allHousesWithId():
  ##     state.withHouse(houseId):
  ##       house.turnsWithoutOrders += 1
  for houseId in state.houses.entities.index.keys:
    yield (houseId, state.houses.entities.entity(houseId).get())

iterator allShipsWithId*(state: GameState): tuple[id: ShipId, ship: Ship] =
  ## Iterate all ships with IDs (for batch processing)
  ##
  ## Example:
  ##   for (shipId, ship) in state.allShipsWithId():
  ##     if ship.isCrippled:
  ##       echo "Ship ", shipId, " needs repair"
  for shipId in state.ships.entities.index.keys:
    yield (shipId, state.ships.entities.entity(shipId).get())

# Military asset iterators (O(1) lookups via byHouse index)

iterator squadronsOwned*(state: GameState, houseId: HouseId): Squadron =
  ## Iterate all squadrons owned by a house (O(1) lookup via byHouse index)
  ##
  ## Example:
  ##   var totalSquadrons = 0
  ##   for squadron in state.squadronsOwned(houseId):
  ##     totalSquadrons += 1
  if state.squadrons.byHouse.contains(houseId):
    for squadronId in state.squadrons.byHouse[houseId]:
      if state.squadrons.entities.index.contains(squadronId):
        yield state.squadrons.entities.entity(squadronId).get()

iterator shipsOwned*(state: GameState, houseId: HouseId): Ship =
  ## Iterate all ships owned by a house (O(1) lookup via byHouse index)
  ##
  ## Example:
  ##   var crippledShips = 0
  ##   for ship in state.shipsOwned(houseId):
  ##     if ship.isCrippled:
  ##       crippledShips += 1
  if state.ships.byHouse.contains(houseId):
    for shipId in state.ships.byHouse[houseId]:
      if state.ships.entities.index.contains(shipId):
        yield state.ships.entities.entity(shipId).get()

# Facility iterators (O(colonies_owned * facilities_per_colony) via byColony index)

iterator neoriasOwned*(state: GameState, houseId: HouseId): Neoria =
  ## Iterate all neorias (production facilities) owned by a house
  ## O(colonies_owned * neorias_per_colony) via coloniesOwned + byColony index
  for colony in state.coloniesOwned(houseId):
    if state.neorias.byColony.contains(colony.id):
      for neoriaId in state.neorias.byColony[colony.id]:
        if state.neorias.entities.index.contains(neoriaId):
          yield state.neoria(neoriaId).get()

iterator kastrasOwned*(state: GameState, houseId: HouseId): Kastra =
  ## Iterate all kastras (defensive facilities) owned by a house
  ## O(colonies_owned * kastras_per_colony) via coloniesOwned + byColony index
  for colony in state.coloniesOwned(houseId):
    if state.kastras.byColony.contains(colony.id):
      for kastraId in state.kastras.byColony[colony.id]:
        if state.kastras.entities.index.contains(kastraId):
          yield state.kastra(kastraId).get()

# ============================================================================
# All-Entity Iterators (Added 2025-12-22)
# ============================================================================

iterator allColonies*(state: GameState): Colony =
  ## Iterate all colonies (read-only)
  ## O(n) where n = total colonies
  ## Use when you need to process ALL colonies regardless of owner
  for colonyId in state.colonies.entities.index.keys:
    let colony = state.colonies.entities.entity(colonyId).get()
    yield colony

iterator allFleets*(state: GameState): Fleet =
  ## Iterate all fleets (read-only)
  ## O(n) where n = total fleets
  ## Use when you need to process ALL fleets regardless of owner
  for (id, fleet) in state.allFleetsWithId():
    yield fleet

iterator allSquadrons*(state: GameState): Squadron =
  ## Iterate all squadrons (read-only)
  ## O(n) where n = total squadrons
  ## Use when you need to process ALL squadrons regardless of owner
  for (id, squadron) in state.allSquadronsWithId():
    yield squadron

iterator allSystems*(state: GameState): System =
  ## Iterate all star systems (read-only)
  ## O(n) where n = total systems
  ## Use when you need to process ALL systems
  for (id, system) in state.allSystemsWithId():
    yield system

iterator allSystemsWithId*(state: GameState): tuple[id: SystemId, system: System] =
  ## Iterate all systems with IDs (for mutations)
  ## O(n) where n = total systems
  ## Use when you need to mutate systems or need their IDs
  for systemId in state.systems.entities.index.keys:
    yield (systemId, state.system(systemId).get())

iterator allSquadronsWithId*(
    state: GameState
): tuple[id: SquadronId, squadron: Squadron] =
  ## Iterate all squadrons with IDs (for mutations)
  ## O(n) where n = total squadrons
  ## Use when you need to mutate squadrons or need their IDs
  for squadronId in state.squadrons.entities.index.keys:
    yield (squadronId, state.squadrons.entities.entity(squadronId).get())

iterator squadronsOwnedWithId*(
    state: GameState, houseId: HouseId
): tuple[id: SquadronId, squadron: Squadron] =
  ## Iterate squadrons owned by house with IDs (for mutations)
  ## O(1) lookup via byHouse index
  ## Use when you need to mutate house-owned squadrons
  if state.squadrons.byHouse.contains(houseId):
    for squadronId in state.squadrons.byHouse[houseId]:
      if state.squadrons.entities.index.contains(squadronId):
        let squadron =
          state.squadrons.entities.entity(squadronId).get()
        yield (squadronId, squadron)

iterator shipsOwnedWithId*(
    state: GameState, houseId: HouseId
): tuple[id: ShipId, ship: Ship] =
  ## Iterate ships owned by house with IDs (for mutations)
  ## O(1) lookup via byHouse index
  ## Use when you need to mutate house-owned ships
  if state.ships.byHouse.contains(houseId):
    for shipId in state.ships.byHouse[houseId]:
      if state.ships.entities.index.contains(shipId):
        let ship = state.ships.entities.entity(shipId).get()
        yield (shipId, ship)

iterator allNeoriasWithId*(
    state: GameState
): tuple[id: NeoriaId, neoria: Neoria] =
  ## Iterate all neorias with IDs (for mutations)
  ## O(n) where n = total neorias
  ## Use when you need to mutate neorias or need their IDs
  for neoriaId in state.neorias.entities.index.keys:
    yield (neoriaId, state.neoria(neoriaId).get())

iterator allKastrasWithId*(
    state: GameState
): tuple[id: KastraId, kastra: Kastra] =
  ## Iterate all kastras with IDs (for mutations)
  ## O(n) where n = total kastras
  ## Use when you need to mutate kastras or need their IDs
  for kastraId in state.kastras.entities.index.keys:
    yield (kastraId, state.kastra(kastraId).get())

## Design Notes:
##
## **Data-Oriented Benefits:**
## - Batch processing: Process all entities of type together (cache-friendly)
## - Clear intent: coloniesOwned() vs manual `if colony.owner == houseId`
## - Consistent patterns: Always same iterator style across codebase
## - Type safety: Compiler ensures correct entity type usage
##
## **Read-Only Philosophy:**
## These iterators are read-only to:
## 1. Separate data access from mutation (clear separation of concerns)
## 2. Force explicit mutations via state_helpers templates
## 3. Enable parallel processing (read-only is parallelizable)
## 4. Prevent accidental mutations via reference escaping
##
## **WithId Variants:**
## Iterators with `WithId` suffix return tuples with IDs for cases where:
## - You need to mutate the entity (use with state_helpers)
## - You need the entity's identifier for logging/events
## - You're building a seq of (id, entity) pairs
##
## **Performance:**
## - Iterators have zero allocation overhead (compiler optimizes to loops)
## - No closures created (inline expansion)
## - Same performance as hand-written loops
## - Better cache locality than scattered access patterns
##
## **Historical Context:**
## 99 repeated loop patterns were found across 22 files.
## These iterators eliminate that duplication while improving readability.
