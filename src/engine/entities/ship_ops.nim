## @entities/ship_ops.nim
##
## Write API for creating, destroying, and modifying Ship entities.
## Ensures that the `bySquadron` secondary index is kept consistent.
import std/[tables, sequtils, options]
import ../state/[game_state as gs_helper, id_gen, entity_manager]
import ../types/[core, game_state, ship, squadron]

proc createShip*(state: var GameState, owner: HouseId, squadronId: SquadronId, shipClass: ShipClass): Ship =
  ## Creates a new ship, adds it to a squadron, and updates all indexes.
  let shipId = state.generateShipId()
  # In a real implementation, stats would come from config based on tech, etc.
  let newShip = Ship(id: shipId, squadronId: squadronId, shipClass: shipClass, shipRole: ShipRole.Escort) # Simplified role

  # 1. Add to entity manager
  state.ships.entities.addEntity(shipId, newShip)

  # 2. Update bySquadron index
  state.ships.bySquadron.mgetOrPut(squadronId, @[]).add(shipId)

  # 3. Add to squadron's ship list
  var squadron = state.getSquadrons(squadronId).get()
  squadron.ships.add(newShip) # Assuming the full Ship object is stored here
  state.squadrons.entities.updateEntity(squadronId, squadron)

  return newShip

proc destroyShip*(state: var GameState, shipId: ShipId) =
  ## Destroys a ship, removing it from all collections and indexes.
  let shipOpt = state.getShip(shipId)
  if shipOpt.isNone: return
  let ship = shipOpt.get()
  let squadronId = ship.squadronId

  # 1. Remove from bySquadron index
  if state.ships.bySquadron.contains(squadronId):
    state.ships.bySquadron[squadronId].keepIf(proc(id: ShipId): bool = id != shipId)

  # 2. Remove from squadron's ship list
  var squadron = state.getSquadrons(squadronId).get()
  squadron.ships.keepIf(proc(s: Ship): bool = s.id != shipId)
  state.squadrons.entities.updateEntity(squadronId, squadron)

  # 3. Remove from entity manager
  state.ships.entities.removeEntity(shipId)

proc transferShip*(state: var GameState, shipId: ShipId, newSquadronId: SquadronId) =
  ## Moves a ship from one squadron to another.
  let shipOpt = state.getShip(shipId)
  if shipOpt.isNone: return
  var ship = shipOpt.get()
  
  let oldSquadronId = ship.squadronId
  if oldSquadronId == newSquadronId: return

  # 1. Remove from old squadron's bySquadron index and ship list
  if state.ships.bySquadron.contains(oldSquadronId):
    state.ships.bySquadron[oldSquadronId].keepIf(proc(id: ShipId): bool = id != shipId)
  
  var oldSquadron = state.getSquadrons(oldSquadronId).get()
  oldSquadron.ships.keepIf(proc(s: Ship): bool = s.id != shipId)
  state.squadrons.entities.updateEntity(oldSquadronId, oldSquadron)

  # 2. Add to new squadron's bySquadron index and ship list
  state.ships.bySquadron.mgetOrPut(newSquadronId, @[]).add(shipId)

  var newSquadron = state.getSquadrons(newSquadronId).get()
  newSquadron.ships.add(ship)
  state.squadrons.entities.updateEntity(newSquadronId, newSquadron)

  # 3. Update the ship's own squadronId
  ship.squadronId = newSquadronId
  state.ships.entities.updateEntity(shipId, ship)
