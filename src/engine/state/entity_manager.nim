import std/options
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
  collection.index[id] = collection.data.high # Store the index of the last element

proc removeEntity*[ID, T](mgr: var EntityManager[ID, T], id: ID) =
  if not mgr.index.contains(id): return

  let idxToRemove = mgr.index[id]
  let lastIdx = mgr.data.high
  
  if idxToRemove != lastIdx:
    let lastEntity = mgr.data[lastIdx]
    # 1. Move last element to the hole
    mgr.data[idxToRemove] = lastEntity
    # 2. Update the index for the moved element
    # Note: This assumes T has an 'id' field.
    mgr.index[lastEntity.id] = idxToRemove 

  # 3. Shrink and cleanup
  mgr.data.setLen(lastIdx)
  mgr.index.del(id)
