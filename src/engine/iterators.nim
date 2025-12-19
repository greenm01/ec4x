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

import std/tables
import ./gamestate, ./fleet
import ./types/orders as order_types
import ../common/types/core

# House-based iterators (entities owned by a house)

iterator coloniesOwned*(state: GameState, houseId: HouseId): Colony =
  ## Iterate all colonies owned by a house (O(1) lookup via index)
  ##
  ## Example:
  ##   var totalProduction = 0
  ##   for colony in state.coloniesOwned(houseId):
  ##     totalProduction += colony.production
  if houseId in state.coloniesByOwner:
    for systemId in state.coloniesByOwner[houseId]:
      if systemId in state.colonies:
        yield state.colonies[systemId]

iterator coloniesOwnedWithId*(state: GameState, houseId: HouseId): tuple[id: SystemId, colony: Colony] =
  ## Iterate colonies with system IDs (for mutations, O(1) lookup via index)
  ##
  ## Example:
  ##   for (systemId, colony) in state.coloniesOwnedWithId(houseId):
  ##     state.withColony(systemId):
  ##       colony.production = calculateProduction(colony)
  if houseId in state.coloniesByOwner:
    for systemId in state.coloniesByOwner[houseId]:
      if systemId in state.colonies:
        yield (systemId, state.colonies[systemId])

iterator fleetsOwned*(state: GameState, houseId: HouseId): Fleet =
  ## Iterate all fleets owned by a house (O(1) lookup via index)
  ##
  ## Example:
  ##   var totalMaintenance = 0
  ##   for fleet in state.fleetsOwned(houseId):
  ##     totalMaintenance += fleet.maintenanceCost
  if houseId in state.fleetsByOwner:
    for fleetId in state.fleetsByOwner[houseId]:
      if fleetId in state.fleets:
        yield state.fleets[fleetId]

iterator fleetsOwnedWithId*(state: GameState, houseId: HouseId): tuple[id: FleetId, fleet: Fleet] =
  ## Iterate fleets with IDs (for mutations, O(1) lookup via index)
  ##
  ## Example:
  ##   for (fleetId, fleet) in state.fleetsOwnedWithId(houseId):
  ##     state.withFleet(fleetId):
  ##       fleet.status = FleetStatus.Reserve
  if houseId in state.fleetsByOwner:
    for fleetId in state.fleetsByOwner[houseId]:
      if fleetId in state.fleets:
        yield (fleetId, state.fleets[fleetId])

# Location-based iterators (entities at a location)

iterator fleetsAtSystem*(state: GameState, systemId: SystemId): Fleet =
  ## Iterate all fleets at a system (O(1) lookup via index)
  ##
  ## Example:
  ##   var fleetsPresent: seq[Fleet] = @[]
  ##   for fleet in state.fleetsAtSystem(systemId):
  ##     fleetsPresent.add(fleet)
  if systemId in state.fleetsByLocation:
    for fleetId in state.fleetsByLocation[systemId]:
      if fleetId in state.fleets:
        yield state.fleets[fleetId]

iterator fleetsAtSystemWithId*(state: GameState, systemId: SystemId): tuple[id: FleetId, fleet: Fleet] =
  ## Iterate fleets at system with IDs (for mutations, O(1) lookup via index)
  ##
  ## Example:
  ##   for (fleetId, fleet) in state.fleetsAtSystemWithId(systemId):
  ##     if shouldRetreat(fleet):
  ##       state.withFleet(fleetId):
  ##         fleet.retreating = true
  if systemId in state.fleetsByLocation:
    for fleetId in state.fleetsByLocation[systemId]:
      if fleetId in state.fleets:
        yield (fleetId, state.fleets[fleetId])

iterator fleetsAtSystemForHouse*(state: GameState, systemId: SystemId, houseId: HouseId): Fleet =
  ## Iterate fleets of a specific house at a system (O(1) lookup via index)
  ##
  ## Example:
  ##   var myFleetsHere: seq[Fleet] = @[]
  ##   for fleet in state.fleetsAtSystemForHouse(systemId, myHouseId):
  ##     myFleetsHere.add(fleet)
  if systemId in state.fleetsByLocation:
    for fleetId in state.fleetsByLocation[systemId]:
      if fleetId in state.fleets:
        let fleet = state.fleets[fleetId]
        if fleet.owner == houseId:
          yield fleet

iterator fleetsAtSystemForHouseWithId*(state: GameState, systemId: SystemId, houseId: HouseId): tuple[id: FleetId, fleet: Fleet] =
  ## Iterate house fleets at system with IDs (for mutations, O(1) lookup via index)
  if systemId in state.fleetsByLocation:
    for fleetId in state.fleetsByLocation[systemId]:
      if fleetId in state.fleets:
        let fleet = state.fleets[fleetId]
        if fleet.owner == houseId:
          yield (fleetId, fleet)

# Condition-based iterators (entities matching criteria)

iterator blockadedColonies*(state: GameState): Colony =
  ## Iterate all currently blockaded colonies
  ##
  ## Example:
  ##   var blockadeCount = 0
  ##   for colony in state.blockadedColonies():
  ##     blockadeCount += 1
  for systemId, colony in state.colonies:
    if colony.blockaded:
      yield colony

iterator blockadedColoniesWithId*(state: GameState): tuple[id: SystemId, colony: Colony] =
  ## Iterate blockaded colonies with IDs (for mutations)
  for systemId, colony in state.colonies:
    if colony.blockaded:
      yield (systemId, colony)

iterator fleetsWithOrders*(state: GameState): tuple[id: FleetId, fleet: Fleet, order: FleetOrder] =
  ## Iterate fleets that have persistent orders
  ##
  ## Example:
  ##   for (fleetId, fleet, order) in state.fleetsWithOrders():
  ##     # Execute fleet order
  for fleetId, order in state.fleetOrders:
    if fleetId in state.fleets:
      yield (fleetId, state.fleets[fleetId], order)

iterator fleetsWithStandingOrders*(state: GameState): tuple[id: FleetId, fleet: Fleet, order: StandingOrder] =
  ## Iterate fleets that have standing orders
  ##
  ## Example:
  ##   for (fleetId, fleet, standingOrder) in state.fleetsWithStandingOrders():
  ##     # Activate standing order
  for fleetId, standingOrder in state.standingOrders:
    if fleetId in state.fleets:
      yield (fleetId, state.fleets[fleetId], standingOrder)

iterator eliminatedHouses*(state: GameState): House =
  ## Iterate eliminated houses
  ##
  ## Example:
  ##   for house in state.eliminatedHouses():
  ##     echo house.name, " has been eliminated"
  for houseId, house in state.houses:
    if house.eliminated:
      yield house

iterator activeHouses*(state: GameState): House =
  ## Iterate non-eliminated houses
  ##
  ## Example:
  ##   for house in state.activeHouses():
  ##     # Process active house
  for houseId, house in state.houses:
    if not house.eliminated:
      yield house

iterator activeHousesWithId*(state: GameState): tuple[id: HouseId, house: House] =
  ## Iterate active houses with IDs (for mutations)
  ##
  ## Example:
  ##   for (houseId, house) in state.activeHousesWithId():
  ##     state.withHouse(houseId):
  ##       house.prestige += bonus
  for houseId, house in state.houses:
    if not house.eliminated:
      yield (houseId, house)

# Utility iterators (helper patterns)

iterator allColoniesWithId*(state: GameState): tuple[id: SystemId, colony: Colony] =
  ## Iterate all colonies with IDs (for batch processing)
  ##
  ## Example:
  ##   for (systemId, colony) in state.allColoniesWithId():
  ##     state.withColony(systemId):
  ##       colony.production = calculateProduction(colony)
  for systemId, colony in state.colonies:
    yield (systemId, colony)

iterator allFleetsWithId*(state: GameState): tuple[id: FleetId, fleet: Fleet] =
  ## Iterate all fleets with IDs (for batch processing)
  ##
  ## Example:
  ##   for (fleetId, fleet) in state.allFleetsWithId():
  ##     state.withFleet(fleetId):
  ##       fleet.fuelRemaining -= 1
  for fleetId, fleet in state.fleets:
    yield (fleetId, fleet)

iterator allHousesWithId*(state: GameState): tuple[id: HouseId, house: House] =
  ## Iterate all houses with IDs (for batch processing)
  ##
  ## Example:
  ##   for (houseId, house) in state.allHousesWithId():
  ##     state.withHouse(houseId):
  ##       house.turnsWithoutOrders += 1
  for houseId, house in state.houses:
    yield (houseId, house)

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
