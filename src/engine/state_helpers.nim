## Safe State Mutation Helpers
##
## Data-oriented helpers for safely mutating Nim Tables in GameState.
## Prevents Table copy semantic bugs through explicit get-modify-write pattern.
##
## CRITICAL: Nim's Table[K, V] returns COPIES when accessed via table[key].
## Direct mutations like `state.houses[id].field = value` are LOST.
##
## These templates provide safe mutation with:
## - Zero abstraction cost (inline expansion)
## - Visible mutations at call site
## - Automatic write-back to ensure persistence
##
## Usage:
##   state.withHouse(houseId):
##     house.treasury += 100
##     house.prestige -= 5
##   # Automatic write-back happens here

import ./gamestate
import ./types/colony
import ../common/types/core

template withHouse*(state: var GameState, houseId: HouseId, body: untyped): untyped =
  ## Safe house mutation - ensures write-back
  ##
  ## Example:
  ##   state.withHouse("house-alpha"):
  ##     house.treasury += income
  ##     house.prestige += prestigeBonus
  ##
  ## The `house` variable is injected and modifications persist.
  var house {.inject.} = state.houses[houseId]
  body
  state.houses[houseId] = house

template withColony*(state: var GameState, systemId: SystemId, body: untyped): untyped =
  ## Safe colony mutation - ensures write-back
  ##
  ## Example:
  ##   state.withColony(systemId):
  ##     colony.population += ptuToPu(transfer.ptu)
  ##     colony.blockaded = false
  var colony {.inject.} = state.colonies[systemId]
  body
  state.colonies[systemId] = colony

template withFleet*(state: var GameState, fleetId: FleetId, body: untyped): untyped =
  ## Safe fleet mutation - ensures write-back
  ##
  ## Example:
  ##   state.withFleet(fleetId):
  ##     fleet.location = targetSystem
  ##     fleet.squadrons.add(newSquadron)
  var fleet {.inject.} = state.fleets[fleetId]
  body
  state.fleets[fleetId] = fleet

template withFleetOrder*(state: var GameState, fleetId: FleetId, body: untyped): untyped =
  ## Safe fleet order mutation - ensures write-back
  ##
  ## Example:
  ##   state.withFleetOrder(fleetId):
  ##     fleetOrder.currentWaypoint += 1
  var fleetOrder {.inject.} = state.fleetOrders[fleetId]
  body
  state.fleetOrders[fleetId] = fleetOrder

template withStandingOrder*(state: var GameState, fleetId: FleetId, body: untyped): untyped =
  ## Safe standing order mutation - ensures write-back
  ##
  ## Example:
  ##   state.withStandingOrder(fleetId):
  ##     standingOrder.lastExecuted = state.turn
  var standingOrder {.inject.} = state.standingOrders[fleetId]
  body
  state.standingOrders[fleetId] = standingOrder

template withDiplomacy*(state: var GameState, housePair: (HouseId, HouseId), body: untyped): untyped =
  ## Safe diplomacy mutation - ensures write-back
  ##
  ## Example:
  ##   state.withDiplomacy((houseA, houseB)):
  ##     diplomaticState.relation = DiplomaticRelation.War
  ##     diplomaticState.lastChange = state.turn
  var diplomaticState {.inject.} = state.diplomacy[housePair]
  body
  state.diplomacy[housePair] = diplomaticState

# Conditional mutation helpers (when entry might not exist)

template withHouseIfExists*(state: var GameState, houseId: HouseId, body: untyped): untyped =
  ## Safe house mutation if house exists, no-op otherwise
  ##
  ## Example:
  ##   state.withHouseIfExists(houseId):
  ##     house.treasury += bonus
  if houseId in state.houses:
    var house {.inject.} = state.houses[houseId]
    body
    state.houses[houseId] = house

template withColonyIfExists*(state: var GameState, systemId: SystemId, body: untyped): untyped =
  ## Safe colony mutation if colony exists, no-op otherwise
  ##
  ## Example:
  ##   state.withColonyIfExists(systemId):
  ##     colony.infrastructureDamage += 0.1
  if systemId in state.colonies:
    var colony {.inject.} = state.colonies[systemId]
    body
    state.colonies[systemId] = colony

template withFleetIfExists*(state: var GameState, fleetId: FleetId, body: untyped): untyped =
  ## Safe fleet mutation if fleet exists, no-op otherwise
  ##
  ## Example:
  ##   state.withFleetIfExists(fleetId):
  ##     fleet.damaged = true
  if fleetId in state.fleets:
    var fleet {.inject.} = state.fleets[fleetId]
    body
    state.fleets[fleetId] = fleet

# Batch mutation helper (process multiple entities)

template batchMutateHouses*(state: var GameState, houseIds: openArray[HouseId], body: untyped): untyped =
  ## Batch process multiple houses safely
  ##
  ## Example:
  ##   state.batchMutateHouses(allHouseIds):
  ##     house.prestige -= maintenanceCost
  for houseId {.inject.} in houseIds:
    var house {.inject.} = state.houses[houseId]
    body
    state.houses[houseId] = house

template batchMutateColonies*(state: var GameState, systemIds: openArray[SystemId], body: untyped): untyped =
  ## Batch process multiple colonies safely
  ##
  ## Example:
  ##   state.batchMutateColonies(colonyIds):
  ##     colony.production = calculateProduction(colony)
  for systemId {.inject.} in systemIds:
    var colony {.inject.} = state.colonies[systemId]
    body
    state.colonies[systemId] = colony

template batchMutateFleets*(state: var GameState, fleetIds: openArray[FleetId], body: untyped): untyped =
  ## Batch process multiple fleets safely
  ##
  ## Example:
  ##   state.batchMutateFleets(fleetIds):
  ##     fleet.status = FleetStatus.Reserve
  for fleetId {.inject.} in fleetIds:
    var fleet {.inject.} = state.fleets[fleetId]
    body
    state.fleets[fleetId] = fleet

## Design Notes:
##
## **Why Templates?**
## - Zero runtime cost (inline expansion)
## - Type safety (compile-time checking)
## - Debuggable (mutations visible in stack traces)
## - No boxing/allocation overhead
##
## **Why Inject Variables?**
## - Makes mutations explicit at call site
## - Clear scoping (mutations only in block)
## - Prevents accidental escaping of references
##
## **Data-Oriented Alignment:**
## - Explicit data flow (get → modify → write)
## - No hidden indirection
## - Batch helpers for cache-friendly processing
## - Templates expand to simple data transformations
##
## **Historical Context:**
## 65% of engine bugs (46 total) were Table copy semantic issues
## where direct mutations like `state.table[key].field = value` were lost.
## These templates prevent such bugs while keeping data access visible.
