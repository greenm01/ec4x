import std/[options, sequtils, tables, strformat]
import ../../engine/types/[core, zero_turn, player_state, fleet, ship, colony, ground_unit, game_state]
import ../../engine/types/cargo
import ../../engine/utils # soulsPerPtu
import ./actions # specific client actions if needed

# We need to mimic the GameState operations but on PlayerState
# This allows us to "preview" the result of zero-turn commands immediately

type
  ZeroTurnContext* = object
    playerState*: ref PlayerState # Reference to modify in-place (or we return a new one)

# --- Helpers ---

proc findFleet(ps: PlayerState, id: FleetId): Option[Fleet] =
  for f in ps.ownFleets:
    if f.id == id: return some(f)
  return none(Fleet)

proc findFleetIdx(ps: PlayerState, id: FleetId): int =
  for i, f in ps.ownFleets:
    if f.id == id: return i
  return -1

proc findColonyBySystem(ps: PlayerState, systemId: SystemId): Option[Colony] =
  for c in ps.ownColonies:
    if c.systemId == systemId: return some(c)
  return none(Colony)

proc findColonyIdxBySystem(ps: PlayerState, systemId: SystemId): int =
  for i, c in ps.ownColonies:
    if c.systemId == systemId: return i
  return -1

proc findShip(ps: PlayerState, id: ShipId): Option[Ship] =
  for s in ps.ownShips:
    if s.id == id: return some(s)
  return none(Ship)

# --- Execution Logic (Ported/Adapted from Engine) ---

proc clientLoadCargo*(ps: var PlayerState, cmd: ZeroTurnCommand): ZeroTurnResult =
  ## Client-side implementation of LoadCargo
  
  if cmd.sourceFleetId.isNone or cmd.cargoType.isNone:
    return ZeroTurnResult(success: false, error: "Missing parameters")

  let fleetId = cmd.sourceFleetId.get()
  let cargoType = cmd.cargoType.get()
  let fleetIdx = ps.findFleetIdx(fleetId)
  
  if fleetIdx == -1:
    return ZeroTurnResult(success: false, error: "Fleet not found")
    
  let fleet = ps.ownFleets[fleetIdx]
  let colIdx = ps.findColonyIdxBySystem(fleet.location)
  
  if colIdx == -1:
    return ZeroTurnResult(success: false, error: "No colony at fleet location")
    
  # We modify entities in place within the sequence
  # Note: In Nim, we need to be careful with value types in seqs.
  # Using 'var' accessor or pointers if possible, or just updating the seq.
  
  var colony = ps.ownColonies[colIdx]
  var ships = ps.ownShips # We'll need to update ships too
  
  # Calculate available
  var availableUnits = 0
  case cargoType
  of CargoClass.Marines:
    for u in ps.ownGroundUnits:
      if u.location == GroundLocation.Colony and u.locationId == colony.id.int and u.stats.unitType == GroundClass.Marine:
        availableUnits.inc
  of CargoClass.Colonists:
    let minSouls = 1_000_000
    if colony.souls > minSouls:
      availableUnits = (colony.souls - minSouls) div soulsPerPtu()
  else: discard

  if availableUnits <= 0:
    return ZeroTurnResult(success: false, error: "No cargo available")

  var requestedQty = if cmd.cargoQuantity.isSome: cmd.cargoQuantity.get() else: availableUnits
  var remainingToLoad = min(requestedQty, availableUnits)
  var totalLoaded = 0

  # Iterate fleet ships
  for shipId in fleet.ships:
    if remainingToLoad <= 0: break
    
    # Find ship in global list
    var shipIdx = -1
    for i, s in ps.ownShips:
      if s.id == shipId:
        shipIdx = i
        break
    
    if shipIdx == -1: continue
    
    var ship = ps.ownShips[shipIdx]
    
    # Check compatibility (Simplified for client prototype)
    let canCarry = case ship.shipClass
                   of ShipClass.TroopTransport: cargoType == CargoClass.Marines
                   of ShipClass.ETAC: cargoType == CargoClass.Colonists
                   else: false
                   
    if not canCarry: continue
    
    # Load
    let cap = 5000 # Hardcoded for now, should read from ship stats/design
    # TODO: Real capacity logic
    
    var currentQty = 0
    if ship.cargo.isSome:
      if ship.cargo.get().cargoType == cargoType:
        currentQty = ship.cargo.get().quantity
      elif ship.cargo.get().quantity > 0:
        continue # Mixed cargo not allowed in this simple logic
        
    let space = cap - currentQty
    let load = min(remainingToLoad, space)
    
    if load > 0:
      var newCargo = if ship.cargo.isSome: ship.cargo.get() else: ShipCargo(cargoType: cargoType, capacity: cap, quantity: 0)
      newCargo.cargoType = cargoType
      newCargo.quantity += load.int32
      
      ps.ownShips[shipIdx].cargo = some(newCargo)
      totalLoaded += load
      remainingToLoad -= load

  # Update Colony
  if totalLoaded > 0:
    case cargoType
    of CargoClass.Marines:
      # Remove marines
      var removed = 0
      var keepIndices: seq[int] = @[]
      for i, u in ps.ownGroundUnits:
        if removed < totalLoaded and u.location == GroundLocation.Colony and u.locationId == colony.id.int and u.stats.unitType == GroundClass.Marine:
          removed.inc
        else:
          keepIndices.add(i)
      
      # Rebuild ground units list (inefficient but safe)
      var newUnits: seq[GroundUnit] = @[]
      for i in keepIndices: newUnits.add(ps.ownGroundUnits[i])
      ps.ownGroundUnits = newUnits
      
    of CargoClass.Colonists:
      let souls = totalLoaded * soulsPerPtu()
      ps.ownColonies[colIdx].souls -= souls
      ps.ownColonies[colIdx].population = ps.ownColonies[colIdx].souls div 1_000_000
    else: discard

  return ZeroTurnResult(
    success: true,
    cargoLoaded: totalLoaded.int32
  )

# --- Dispatcher ---

proc executeZeroTurn*(ps: var PlayerState, cmd: ZeroTurnCommand): ZeroTurnResult =
  case cmd.commandType
  of ZeroTurnCommandType.LoadCargo:
    return clientLoadCargo(ps, cmd)
  else:
    return ZeroTurnResult(success: false, error: "Command not implemented in client yet")
