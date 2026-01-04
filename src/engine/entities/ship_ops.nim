## @entities/ship_ops.nim
##
## Write API for creating, destroying, and modifying Ship entities.
## Ensures that the `bySquadron` secondary index is kept consistent.
import std/[tables, sequtils, options]
import ../state/[engine, id_gen]
import ../types/[core, game_state, ship, squadron]
import ../systems/ship/entity as ship_entity

proc registerShipIndexes*(state: var GameState, shipId: ShipId) =
  ## Register an existing ship in the bySquadron and byHouse indexes
  ## Use this when a ship is created outside the normal createShip() flow
  ## (e.g., during commissioning where squadron doesn't exist yet)
  let shipOpt = state.ship(shipId)
  if shipOpt.isNone:
    return

  let ship = shipOpt.get()

  # Add to bySquadron index
  if ship.squadronId != SquadronId(0):
    state.ships.bySquadron.mgetOrPut(ship.squadronId, @[]).add(shipId)

  # Add to byHouse index
  state.ships.byHouse.mgetOrPut(ship.houseId, @[]).add(shipId)

proc newShip*(
    shipClass: ShipClass,
    weaponsTech: int32,
    id: ShipId,
    squadronId: SquadronId,
    houseId: HouseId,
): Ship =
  ## Create a new ship with WEP-modified stats
  ## Use this for commissioning where squadron doesn't exist yet
  ##
  ## Stats (AS, DS, WEP) are calculated once at construction and never change
  ## Config values (role, costs, CC, CR) looked up via shipClass
  ## Cargo is initialized as None (use initCargo to add cargo)
  let stats = ship_entity.getShipStats(shipClass, weaponsTech)

  Ship(
    id: id,
    houseId: houseId,
    squadronId: squadronId,
    shipClass: shipClass,
    stats: stats,
    state: CombatState.Undamaged,
    cargo: none(ShipCargo),
  )

proc createShip*(
    state: var GameState, owner: HouseId, squadronId: SquadronId, shipClass: ShipClass
): Ship =
  ## Creates a new ship, adds it to a squadron, and updates all indexes.
  let shipId = state.generateShipId()

  # Get house's current WEP tech level
  let house = state.house(owner).get()
  let weaponsTech = house.techTree.levels.wep

  # Use ship_entity.getShipStats() for correct compound WEP calculation
  let stats = ship_entity.getShipStats(shipClass, weaponsTech)

  let newShip = Ship(
    id: shipId,
    houseId: owner,
    squadronId: squadronId,
    shipClass: shipClass,
    stats: stats,
    state: CombatState.Undamaged,
    cargo: none(ShipCargo)
  )
  
  # 1. Add to entity manager
  state.updateShip(shipId, newShip)

  # 2. Update indexes
  state.ships.bySquadron.mgetOrPut(squadronId, @[]).add(shipId)
  state.ships.byHouse.mgetOrPut(owner, @[]).add(shipId)

  # 3. Add to squadron's ship list
  var squadron = state.squadron(squadronId).get()
  squadron.ships.add(shipId)
  state.updateSquadron(squadronId, squadron)
  
  return newShip

proc destroyShip*(state: var GameState, shipId: ShipId) =
  ## Destroys a ship, removing it from all collections and indexes.
  let shipOpt = state.ship(shipId)
  if shipOpt.isNone:
    return
  let ship = shipOpt.get()
  let squadronId = ship.squadronId

  # 1. Remove from bySquadron index
  if state.ships.bySquadron.contains(squadronId):
    state.ships.bySquadron[squadronId].keepIf(
      proc(id: ShipId): bool =
        id != shipId
    )

  # 2. Remove from squadron's ship list
  var squadron = state.squadron(squadronId).get()
  squadron.ships.keepIf(
    proc(id: ShipId): bool =
      id != shipId
  )
  state.updateSquadron(squadronId, squadron)

  # 3. Delete from entity manager
  state.delShip(shipId)

proc transferShip*(state: var GameState, shipId: ShipId, newSquadronId: SquadronId) =
  ## Moves a ship from one squadron to another.
  let shipOpt = state.ship(shipId)
  if shipOpt.isNone:
    return
  var ship = shipOpt.get()

  let oldSquadronId = ship.squadronId
  if oldSquadronId == newSquadronId:
    return

  # 1. Remove from old squadron's bySquadron index and ship list
  if state.ships.bySquadron.contains(oldSquadronId):
    state.ships.bySquadron[oldSquadronId].keepIf(
      proc(id: ShipId): bool =
        id != shipId
    )

  var oldSquadron = state.squadron(oldSquadronId).get()
  oldSquadron.ships.keepIf(
    proc(id: ShipId): bool =
      id != shipId
  )
  state.updateSquadron(oldSquadronId, oldSquadron)
  # 2. Add to new squadron's bySquadron index and ship list
  state.ships.bySquadron.mgetOrPut(newSquadronId, @[]).add(shipId)

  var newSquadron = state.squadron(newSquadronId).get()
  newSquadron.ships.add(shipId)
  state.updateSquadron(newSquadronId, newSquadron)
  # 3. Update the ship's own squadronId
  ship.squadronId = newSquadronId
  state.updateShip(shipId, ship)
