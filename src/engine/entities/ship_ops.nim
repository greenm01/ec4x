## @entities/ship_ops.nim
##
## Write API for creating, destroying, and modifying Ship entities.
## Ensures that the `byFleet` and `byCarrier` secondary indexes are kept consistent.
import std/[tables, sequtils, options]
import ../state/[engine, id_gen]
import ../types/[core, game_state, ship, fleet]
import ../systems/ship/entity

proc registerShipIndexes*(state: GameState, shipId: ShipId) =
  ## Register an existing ship in the byFleet, byCarrier, and byHouse indexes
  ## Use this when a ship is created outside the normal createShip() flow
  ## (e.g., during commissioning where fleet doesn't exist yet)
  let shipOpt = state.ship(shipId)
  if shipOpt.isNone:
    return

  let ship = shipOpt.get()

  # Add to byFleet index (if assigned to fleet)
  if ship.fleetId != FleetId(0):
    state.ships.byFleet.mgetOrPut(ship.fleetId, @[]).add(shipId)

  # Add to byCarrier index (if embarked on carrier)
  if ship.assignedToCarrier.isSome:
    let carrierId = ship.assignedToCarrier.get()
    state.ships.byCarrier.mgetOrPut(carrierId, @[]).add(shipId)

  # Add to byHouse index
  state.ships.byHouse.mgetOrPut(ship.houseId, @[]).add(shipId)

proc newShip*(
    shipClass: ShipClass,
    weaponsTech: int32,
    id: ShipId,
    fleetId: FleetId,
    houseId: HouseId,
): Ship =
  ## Create a new ship with WEP-modified stats
  ## Use this for commissioning where fleet assignment is specified
  ##
  ## Stats (AS, DS, WEP) are calculated once at construction and never change
  ## Config values (role, costs, CC) looked up via shipClass
  ## Cargo is initialized as None (use initCargo to add cargo)
  ## fleetId = 0 means unassigned (colony-based fighters)
  let stats = getShipStats(shipClass, weaponsTech)

  Ship(
    id: id,
    houseId: houseId,
    fleetId: fleetId,
    shipClass: shipClass,
    stats: stats,
    state: CombatState.Undamaged,
    cargo: none(ShipCargo),
    assignedToCarrier: none(ShipId),
    embarkedFighters: @[],
  )

proc createShip*(
    state: GameState, owner: HouseId, fleetId: FleetId, shipClass: ShipClass
): Ship =
  ## Creates a new ship, adds it to a fleet, and updates all indexes.
  ## If fleetId = 0, ship is unassigned (colony-based fighters)
  let shipId = state.generateShipId()

  # Get house's current WEP tech level
  let house = state.house(owner).get()
  let weaponsTech = house.techTree.levels.wep

  # Use getShipStats() for correct compound WEP calculation
  let stats = getShipStats(shipClass, weaponsTech)

  let newShip = Ship(
    id: shipId,
    houseId: owner,
    fleetId: fleetId,
    shipClass: shipClass,
    stats: stats,
    state: CombatState.Undamaged,
    cargo: none(ShipCargo),
    assignedToCarrier: none(ShipId),
    embarkedFighters: @[],
  )

  # 1. Add to entity manager
  state.updateShip(shipId, newShip)

  # 2. Update indexes
  if fleetId != FleetId(0):
    state.ships.byFleet.mgetOrPut(fleetId, @[]).add(shipId)
  state.ships.byHouse.mgetOrPut(owner, @[]).add(shipId)

  # 3. Add to fleet's ship list (if assigned to fleet)
  if fleetId != FleetId(0):
    var fleet = state.fleet(fleetId).get()
    fleet.ships.add(shipId)
    state.updateFleet(fleetId, fleet)

  return newShip

proc destroyShip*(state: GameState, shipId: ShipId) =
  ## Destroys a ship, removing it from all collections and indexes.
  let shipOpt = state.ship(shipId)
  if shipOpt.isNone:
    return
  let ship = shipOpt.get()
  let fleetId = ship.fleetId

  # 1. Remove from byFleet index
  if fleetId != FleetId(0) and state.ships.byFleet.contains(fleetId):
    state.ships.byFleet[fleetId].keepIf(
      proc(id: ShipId): bool =
        id != shipId
    )

  # 2. Remove from byCarrier index (if embarked)
  if ship.assignedToCarrier.isSome:
    let carrierId = ship.assignedToCarrier.get()
    if state.ships.byCarrier.contains(carrierId):
      state.ships.byCarrier[carrierId].keepIf(
        proc(id: ShipId): bool =
          id != shipId
      )

  # 3. Remove from fleet's ship list
  if fleetId != FleetId(0):
    let fleetOpt = state.fleet(fleetId)
    if fleetOpt.isSome:
      var fleet = fleetOpt.get()
      fleet.ships.keepIf(
        proc(id: ShipId): bool =
          id != shipId
      )
      state.updateFleet(fleetId, fleet)

  # 4. Delete from entity manager
  state.delShip(shipId)

proc assignShipToFleet*(state: GameState, shipId: ShipId, newFleetId: FleetId) =
  ## Moves a ship from one fleet to another (or assigns unassigned ship to fleet).
  let shipOpt = state.ship(shipId)
  if shipOpt.isNone:
    return
  var ship = shipOpt.get()

  let oldFleetId = ship.fleetId
  if oldFleetId == newFleetId:
    return

  # 1. Remove from old fleet's byFleet index and ship list
  if oldFleetId != FleetId(0):
    if state.ships.byFleet.contains(oldFleetId):
      state.ships.byFleet[oldFleetId].keepIf(
        proc(id: ShipId): bool =
          id != shipId
      )

    let oldFleetOpt = state.fleet(oldFleetId)
    if oldFleetOpt.isSome:
      var oldFleet = oldFleetOpt.get()
      oldFleet.ships.keepIf(
        proc(id: ShipId): bool =
          id != shipId
      )
      state.updateFleet(oldFleetId, oldFleet)

  # 2. Add to new fleet's byFleet index and ship list
  if newFleetId != FleetId(0):
    state.ships.byFleet.mgetOrPut(newFleetId, @[]).add(shipId)

    var newFleet = state.fleet(newFleetId).get()
    newFleet.ships.add(shipId)
    state.updateFleet(newFleetId, newFleet)

  # 3. Update the ship's own fleetId
  ship.fleetId = newFleetId
  state.updateShip(shipId, ship)

proc unassignShipFromFleet*(state: GameState, shipId: ShipId) =
  ## Removes ship from its fleet (sets fleetId to 0)
  assignShipToFleet(state, shipId, FleetId(0))

proc assignFighterToCarrier*(state: GameState, fighterId: ShipId, carrierId: ShipId) =
  ## Embarks a fighter onto a carrier
  let fighterOpt = state.ship(fighterId)
  let carrierOpt = state.ship(carrierId)
  if fighterOpt.isNone or carrierOpt.isNone:
    return

  var fighter = fighterOpt.get()
  var carrier = carrierOpt.get()

  # Update fighter assignment
  fighter.assignedToCarrier = some(carrierId)
  fighter.fleetId = carrier.fleetId  # Inherit carrier's fleet
  state.updateShip(fighterId, fighter)

  # Add to carrier's embarked list
  carrier.embarkedFighters.add(fighterId)
  state.updateShip(carrierId, carrier)

  # Update byCarrier index
  state.ships.byCarrier.mgetOrPut(carrierId, @[]).add(fighterId)

proc unassignFighterFromCarrier*(state: GameState, fighterId: ShipId) =
  ## Disembarks a fighter from its carrier
  let fighterOpt = state.ship(fighterId)
  if fighterOpt.isNone:
    return

  var fighter = fighterOpt.get()
  if fighter.assignedToCarrier.isNone:
    return

  let carrierId = fighter.assignedToCarrier.get()

  # Remove from carrier's embarked list
  let carrierOpt = state.ship(carrierId)
  if carrierOpt.isSome:
    var carrier = carrierOpt.get()
    carrier.embarkedFighters.keepIf(proc(id: ShipId): bool = id != fighterId)
    state.updateShip(carrierId, carrier)

  # Remove from byCarrier index
  if state.ships.byCarrier.contains(carrierId):
    state.ships.byCarrier[carrierId].keepIf(proc(id: ShipId): bool = id != fighterId)

  # Clear fighter's carrier assignment
  fighter.assignedToCarrier = none(ShipId)
  fighter.fleetId = FleetId(0)  # Unassign from fleet
  state.updateShip(fighterId, fighter)
