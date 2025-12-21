import std/[options, tables]
import ../types/[core]

# Generic getter that works for any collection using our EntityManager pattern
proc getEntity*[ID, T](collection: EntityManager[ID, T], id: ID): Option[T] =
  if collection.index.contains(id):
    let idx = collection.index[id]
    return some(collection.data[idx])
  return none(T)

# Generic adder that works for any collection using our EntityManager pattern
proc addEntity*[ID, T](collection: var EntityManager[ID, T], id: ID, entity: T) =
  collection.data.add(entity)
  collection.index[id] = collection.data.len - 1

proc updateEntity*[ID, T](mgr: var EntityManager[ID, T], id: ID, newEntity: T) =
  ## Updates an existing entity in the entity manager.
  if not mgr.index.contains(id): return
  let idx = mgr.index[id]
  mgr.data[idx] = newEntity

proc removeEntity*[ID, T](mgr: var EntityManager[ID, T], id: ID) =
  if not mgr.index.contains(id): return

  let idxToRemove = mgr.index[id]
  let lastIdx = mgr.data.len - 1
  
  if idxToRemove != lastIdx:
    let lastEntity = mgr.data[lastIdx]
    mgr.data[idxToRemove] = lastEntity
    mgr.index[lastEntity.id] = idxToRemove 

  mgr.data.setLen(lastIdx)
  mgr.index.del(id)