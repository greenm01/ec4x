import std/[tables, sequtils, options, sets]
import ../types/[core, game_state, fleet, ship]
import ../state/[engine, id_gen]
import ./ship_ops
import ../systems/command/commands

# =============================================================================
# Fleet Label Operations
# =============================================================================

proc fleetLabelFromIndex*(index: int): string =
  ## Convert 0-based index to fleet label. 0→"A1", 34→"AZ", 35→"B1", 909→"ZZ"
  if index < 0 or index >= FleetLabelCapacity:
    return "??"
  let first = index div FleetLabelSecondChars.len
  let second = index mod FleetLabelSecondChars.len
  $FleetLabelFirstChars[first] & $FleetLabelSecondChars[second]

proc nextAvailableFleetLabel*(existingNames: openArray[string]): string =
  ## Find the lowest available fleet label not in existingNames.
  var used = initHashSet[string]()
  for name in existingNames:
    used.incl(name)
  for i in 0 ..< FleetLabelCapacity:
    let label = fleetLabelFromIndex(i)
    if label notin used:
      return label
  "??"

# =============================================================================
# Fleet Construction
# =============================================================================

proc newFleet*(
    shipIds: seq[ShipId] = @[],
    id: FleetId = FleetId(0),
    name: string = "",
    owner: HouseId = HouseId(0),
    location: SystemId = SystemId(0),
    status: FleetStatus = FleetStatus.Active,
    roe: int32 = 6,
): Fleet =
  ## Create a new fleet with the given ship IDs
  ## Use this for operations that need a Fleet value without state mutations
  ## Default ROE = 6 (engage if equal or better)
  Fleet(
    id: id,
    name: name,
    ships: shipIds,
    houseId: owner,
    location: location,
    status: status,
    roe: roe,
    command: createHoldCommand(id),
    missionState: MissionState.None,
    missionTarget: none(SystemId),
    missionStartTurn: 0,
  )

proc registerFleetLocation*(state: GameState, fleetId: FleetId, sysId: SystemId) =
  ## Add a fleet to the system index
  state.fleets.bySystem.mgetOrPut(sysId, @[]).add(fleetId)

proc unregisterFleetLocation*(
    state: GameState, fleetId: FleetId, sysId: SystemId
) =
  ## Remove a fleet from the system index
  if state.fleets.bySystem.contains(sysId):
    state.fleets.bySystem[sysId].keepIf(
      proc(id: FleetId): bool =
        id != fleetId
    )

proc registerFleetOwner*(state: GameState, fleetId: FleetId, owner: HouseId) =
  ## Add a fleet to the owner index
  state.fleets.byOwner.mgetOrPut(owner, @[]).add(fleetId)

proc unregisterFleetOwner*(state: GameState, fleetId: FleetId, owner: HouseId) =
  ## Remove a fleet from the owner index
  if state.fleets.byOwner.contains(owner):
    state.fleets.byOwner[owner].keepIf(
      proc(id: FleetId): bool =
        id != fleetId
    )

proc createFleet*(state: GameState, owner: HouseId, location: SystemId): Fleet =
  ## Creates a new, empty fleet and adds it to the game state.
  ## Automatically assigns the lowest available per-house label (A1-ZZ).
  let fleetId = state.generateFleetId()

  # Scan existing fleet names for this owner to find lowest available label
  var existingNames: seq[string] = @[]
  if state.fleets.byOwner.contains(owner):
    for fid in state.fleets.byOwner[owner]:
      let fOpt = state.fleet(fid)
      if fOpt.isSome:
        existingNames.add(fOpt.get().name)
  let label = nextAvailableFleetLabel(existingNames)

  # Use newFleet() for consistent field initialization
  let newFleet = newFleet(
    shipIds = @[],
    id = fleetId,
    name = label,
    owner = owner,
    location = location,
    status = FleetStatus.Active,
  )

  # 1. Add to entity manager
  state.addFleet(fleetId, newFleet)

  # 2. Update bySystem index
  state.registerFleetLocation(fleetId, location)

  # 3. Update byOwner index
  state.registerFleetOwner(fleetId, owner)

  return newFleet

proc destroyFleet*(state: GameState, fleetId: FleetId) =
  ## Destroys a fleet and all ships within it.
  let fleetOpt = state.fleet(fleetId)
  if fleetOpt.isNone:
    return
  let fleet = fleetOpt.get()

  # 1. Destroy all ships in the fleet
  # Iterate over a copy, as destroyShip will modify indexes
  for shipId in fleet.ships:
    destroyShip(state, shipId)

  # 2. Unregister location
  state.unregisterFleetLocation(fleetId, fleet.location)

  # 3. Unregister owner
  state.unregisterFleetOwner(fleetId, fleet.houseId)

  # 4. Remove from entity manager
  state.delFleet(fleetId)

proc moveFleet*(state: GameState, fleetId: FleetId, destId: SystemId) =
  ## Moves a fleet to a new system, updating the spatial index.
  let fleetOpt = state.fleet(fleetId)
  if fleetOpt.isNone:
    return

  var fleet = fleetOpt.get()
  let oldId = fleet.location

  if oldId == destId:
    return

  # 1. Update Index: Remove from old, add to new
  state.unregisterFleetLocation(fleetId, oldId)
  state.registerFleetLocation(fleetId, destId)

  # 2. Update Data: Change the field and save back
  fleet.location = destId
  state.updateFleet(fleetId, fleet)

proc changeFleetOwner*(state: GameState, fleetId: FleetId, newOwner: HouseId) =
  ## Transfers ownership of a fleet, updating the byOwner index
  let fleetOpt = state.fleet(fleetId)
  if fleetOpt.isNone:
    return
  var fleet = fleetOpt.get()

  let oldOwner = fleet.houseId
  if oldOwner == newOwner:
    return

  # 1. Remove from old owner's index
  state.unregisterFleetOwner(fleetId, oldOwner)

  # 2. Add to new owner's index
  state.registerFleetOwner(fleetId, newOwner)

  # 3. Update entity
  fleet.houseId = newOwner
  state.updateFleet(fleetId, fleet)

# ============================================================================
# Fleet-Ship Assignment Operations (Index-Aware Mutations)
# ============================================================================
# These operations maintain consistency between:
# - fleet.ships (ship list)
# - ship.fleetId (fleet assignment)
# - ships.byFleet (fleet → ships index)
#
# IMPORTANT: Caller is responsible for validation (see systems/fleet/entity.nim)
# ============================================================================

# Forward declaration
proc removeShipFromFleet*(state: GameState, fleetId: FleetId, shipId: ShipId)

proc addShipToFleet*(state: GameState, fleetId: FleetId, shipId: ShipId) =
  ## Add a ship to a fleet - maintains all indexes
  ## NOTE: Caller must validate compatibility (Intel/combat mixing rules)
  ##       Use systems/fleet/entity.canAddShip() before calling
  let fleetOpt = state.fleet(fleetId)
  let shipOpt = state.ship(shipId)

  if fleetOpt.isNone or shipOpt.isNone:
    return

  var fleet = fleetOpt.get()
  var ship = shipOpt.get()

  # Remove from old fleet if assigned
  if ship.fleetId != FleetId(0):
    removeShipFromFleet(state, ship.fleetId, shipId)

  # 1. Update fleet entity
  fleet.ships.add(shipId)
  state.updateFleet(fleetId, fleet)

  # 2. Update ship entity
  ship.fleetId = fleetId
  state.updateShip(shipId, ship)

  # 3. Update byFleet index
  state.ships.byFleet.mgetOrPut(fleetId, @[]).add(shipId)

proc removeShipFromFleet*(state: GameState, fleetId: FleetId, shipId: ShipId) =
  ## Remove a ship from a fleet - maintains all indexes
  let fleetOpt = state.fleet(fleetId)
  let shipOpt = state.ship(shipId)

  if fleetOpt.isNone or shipOpt.isNone:
    return

  var fleet = fleetOpt.get()
  var ship = shipOpt.get()

  # 1. Update fleet entity
  fleet.ships.keepIf(proc(id: ShipId): bool = id != shipId)
  state.updateFleet(fleetId, fleet)

  # 2. Update ship entity
  ship.fleetId = FleetId(0)  # Unassigned
  state.updateShip(shipId, ship)

  # 3. Update byFleet index
  if state.ships.byFleet.contains(fleetId):
    state.ships.byFleet[fleetId].keepIf(proc(id: ShipId): bool = id != shipId)

proc clearFleetShips*(state: GameState, fleetId: FleetId) =
  ## Remove all ships from a fleet - maintains all indexes
  let fleetOpt = state.fleet(fleetId)
  if fleetOpt.isNone:
    return

  let fleet = fleetOpt.get()

  # Remove each ship (updates ship.fleetId and indexes)
  for shipId in fleet.ships:
    var ship = state.ship(shipId).get()
    ship.fleetId = FleetId(0)
    state.updateShip(shipId, ship)

  # Clear fleet's ship list
  var updatedFleet = fleet
  updatedFleet.ships.setLen(0)
  state.updateFleet(fleetId, updatedFleet)

  # Clear byFleet index
  if state.ships.byFleet.contains(fleetId):
    state.ships.byFleet[fleetId].setLen(0)

proc mergeFleets*(
    state: GameState, sourceFleetId: FleetId, targetFleetId: FleetId
) =
  ## Merge source fleet into target fleet - maintains all indexes
  ## NOTE: Caller must validate compatibility (see systems/fleet/entity.canMergeWith)
  ## Source fleet is destroyed after merge
  let sourceOpt = state.fleet(sourceFleetId)
  let targetOpt = state.fleet(targetFleetId)

  if sourceOpt.isNone or targetOpt.isNone:
    return

  let sourceFleet = sourceOpt.get()

  # Transfer each ship from source to target via ship_ops.assignShipToFleet
  let shipsToMerge = sourceFleet.ships
  for shipId in shipsToMerge:
    assignShipToFleet(state, shipId, targetFleetId)

  # Destroy source fleet (already empty of ships)
  destroyFleet(state, sourceFleetId)

proc splitFleet*(
    state: GameState,
    sourceFleetId: FleetId,
    shipIds: seq[ShipId],
    newFleetLocation: SystemId,
): FleetId =
  ## Split ships from source fleet into a new fleet - maintains all indexes
  ## Returns: ID of newly created fleet
  ## NOTE: Caller must validate ship ownership and composition rules
  let sourceOpt = state.fleet(sourceFleetId)
  if sourceOpt.isNone:
    return FleetId(0)

  let sourceFleet = sourceOpt.get()

  # Create new fleet at specified location
  var newFleet = createFleet(state, sourceFleet.houseId, newFleetLocation)
  let newFleetId = newFleet.id

  # Move each specified ship to new fleet
  for shipId in shipIds:
    let shipOpt = state.ship(shipId)
    if shipOpt.isNone:
      continue

    var ship = shipOpt.get()

    # Verify ship is actually in source fleet
    if ship.fleetId != sourceFleetId:
      continue

    # Remove from source fleet
    removeShipFromFleet(state, sourceFleetId, shipId)

    # Add to new fleet
    addShipToFleet(state, newFleetId, shipId)

  return newFleetId
