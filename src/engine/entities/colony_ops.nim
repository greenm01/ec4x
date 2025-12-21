## @entities/colony_ops.nim
##
## Write API for creating, destroying, and modifying Colony entities.
## Ensures that all secondary indexes (`bySystem`, `byOwner`) are kept consistent.
import std/[tables, sequtils, options]
import ../state/[id_gen, entity_manager, game_state as gs_helpers]
import ../types/[game_state, core, colony, starmap, production, capacity]
import ../initialization/colony as colony_init

proc createColony*(state: var GameState, owner: HouseId, systemId: SystemId, planetClass: PlanetClass, resources: ResourceRating, startingPTU: int32): Colony =
  ## Creates a new colony, adds it to the entity manager, and updates all indexes.
  let colonyId = state.generateColonyId()
  var newColony = colony_init.initColony(colonyId, systemId, owner, planetClass, resources, startingPTU)
  
  state[].colonies.entities.addEntity(colonyId, newColony)
  state[].colonies.bySystem[systemId] = colonyId
  state[].colonies.byOwner.mgetOrPut(owner, @[]).add(colonyId)
  
  return newColony

proc destroyColony*(state: var GameState, colonyId: ColonyId) =
  ## Destroys a colony, removing it from the entity manager and all indexes.
  let colonyOpt = gs_helpers.getColony(state, colonyId)
  if colonyOpt.isNone: return
  let colony = colonyOpt.get()

  if state[].colonies.byOwner.contains(colony.owner):
    var ownerColonies = state[].colonies.byOwner[colony.owner]
    ownerColonies.keepIf(proc(id: ColonyId): bool = id != colonyId)
    state[].colonies.byOwner[colony.owner] = ownerColonies

  if state[].colonies.bySystem.contains(colony.systemId):
    state[].colonies.bySystem.del(colony.systemId)

  state[].colonies.entities.removeEntity(colonyId)


proc changeColonyOwner*(state: var GameState, colonyId: ColonyId, newOwner: HouseId) =
  ## Transfers ownership of a colony, updating the `byOwner` index.
  let colonyOpt = gs_helpers.getColony(state, colonyId)
  if colonyOpt.isNone: return
  var colony = colonyOpt.get()
  
  let oldOwner = colony.owner
  if oldOwner == newOwner: return

  if state[].colonies.byOwner.contains(oldOwner):
    var oldOwnerColonies = state[].colonies.byOwner[oldOwner]
    oldOwnerColonies.keepIf(proc(id: ColonyId): bool = id != colonyId)
    state[].colonies.byOwner[oldOwner] = oldOwnerColonies

  var newOwnerColonies = state[].colonies.byOwner.getOrDefault(newOwner, @[])
  newOwnerColonies.add(colonyId)
  state[].colonies.byOwner[newOwner] = newOwnerColonies

  colony.owner = newOwner
  state[].colonies.entities.updateEntity(colonyId, colony)
