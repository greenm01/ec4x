import ../types/[core, ship]
import std/[tables, options]

proc add*(collection: var Ships, ship: Ship) =
  ## Adds a ship and updates all internal indices
  let idx = collection.data.len
  collection.data.add(ship)
  collection.index[ship.id] = idx
  
  # Update the squadron secondary lookup
  if not collection.bySquadron.contains(ship.squadronId):
    collection.bySquadron[ship.squadronId] = @[]
  collection.bySquadron[ship.squadronId].add(ship.id)

proc remove*(collection: var Ships, id: ShipId) =
  ## Removes a ship using Swap-and-Pop to keep memory contiguous
  if not collection.index.contains(id): return

  let idxToRemove = collection.index[id]
  let shipToRemove = collection.data[idxToRemove]
  let lastIdx = collection.data.high
  
  # 1. Update the Squadron lookup (remove this ship from its squadron's list)
  if collection.bySquadron.contains(shipToRemove.squadronId):
    let sId = shipToRemove.squadronId
    collection.bySquadron[sId].keepIf(proc(x: ShipId): bool = x != id)

  # 2. Swap and Pop logic
  if idxToRemove != lastIdx:
    let movedShip = collection.data[lastIdx]
    collection.data[idxToRemove] = movedShip
    collection.index[movedShip.id] = idxToRemove
  
  collection.data.setLen(lastIdx)
  collection.index.del(id)
