## @entities/ship_ops.nim
##
## Write API for creating, destroying, and modifying Ship entities.
## Ensures that the `bySquadron` secondary index is kept consistent.
import std/[tables, sequtils, options]
import ../state/[engine, id_gen]
import ../types/[core, game_state, ship, squadron]
import ../utils

proc role*(ship: Ship): ShipRole =
  ## Get the role for this ship based on its class
  ShipClassRoles[ship.shipClass]

proc createShip*(
    state: var GameState, owner: HouseId, squadronId: SquadronId, shipClass: ShipClass
): Ship =
  ## Creates a new ship, adds it to a squadron, and updates all indexes.
  let shipId = state.generateShipId()
  let config = shipConfig(shipClass)
  
  # Get house's current WEP tech level
  let house = state.house(owner).get()
  let weaponsTech = house.techTree.levels.wep
  
  # Apply WEP modifiers: +10% AS/DS per level above 1
  let wepMultiplier = 1.0 + (weaponsTech - 1).float * 0.10
  let stats = ShipStats(
    attackStrength: (config.attack_strength.float * wepMultiplier).int32,
    defenseStrength: (config.defense_strength.float * wepMultiplier).int32,
    weaponsTech: weaponsTech
  )
  
  let newShip = Ship(
    id: shipId,
    houseId: owner,
    squadronId: squadronId,
    shipClass: shipClass,
    stats: stats,
    isCrippled: false,
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

  var oldSquadron = state.squadrons(oldSquadronId).get()
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
