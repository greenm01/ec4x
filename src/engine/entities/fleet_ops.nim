import std/[tables, sequtils, options]
import ../types/[core, game_state, fleet, squadron]
import ../state/[engine, id_gen]
import ./squadron_ops

proc newFleet*(
    squadronIds: seq[SquadronId] = @[],
    id: FleetId = FleetId(0),
    owner: HouseId = HouseId(0),
    location: SystemId = SystemId(0),
    status: FleetStatus = FleetStatus.Active,
    autoBalanceSquadrons: bool = true,
): Fleet =
  ## Create a new fleet with the given squadron IDs
  ## Use this for operations that need a Fleet value without state mutations
  ## Supports all squadron types: Combat, Intel, Expansion, Auxiliary, Fighter
  Fleet(
    id: id,
    squadrons: squadronIds,
    houseId: owner,
    location: location,
    status: status,
    autoBalanceSquadrons: autoBalanceSquadrons,
    missionState: FleetMissionState.None,
    missionType: none(int32),
    missionTarget: none(SystemId),
    missionStartTurn: 0,
  )

proc registerFleetLocation*(state: var GameState, fleetId: FleetId, sysId: SystemId) =
  ## Add a fleet to the system index
  state.fleets.bySystem.mgetOrPut(sysId, @[]).add(fleetId)

proc unregisterFleetLocation*(
    state: var GameState, fleetId: FleetId, sysId: SystemId
) =
  ## Remove a fleet from the system index
  if state.fleets.bySystem.contains(sysId):
    state.fleets.bySystem[sysId].keepIf(
      proc(id: FleetId): bool =
        id != fleetId
    )

proc registerFleetOwner*(state: var GameState, fleetId: FleetId, owner: HouseId) =
  ## Add a fleet to the owner index
  state.fleets.byOwner.mgetOrPut(owner, @[]).add(fleetId)

proc unregisterFleetOwner*(state: var GameState, fleetId: FleetId, owner: HouseId) =
  ## Remove a fleet from the owner index
  if state.fleets.byOwner.contains(owner):
    state.fleets.byOwner[owner].keepIf(
      proc(id: FleetId): bool =
        id != fleetId
    )

proc createFleet*(state: var GameState, owner: HouseId, location: SystemId): Fleet =
  ## Creates a new, empty fleet and adds it to the game state.
  let fleetId = state.generateFleetId()
  let newFleet = Fleet(id: fleetId, houseId: owner, location: location, squadrons: @[])

  # 1. Add to entity manager
  state.addFleet(fleetId, newFleet)

  # 2. Update bySystem index
  state.registerFleetLocation(fleetId, location)

  # 3. Update byOwner index
  state.registerFleetOwner(fleetId, owner)

  return newFleet

proc destroyFleet*(state: var GameState, fleetId: FleetId) =
  ## Destroys a fleet and all squadrons within it.
  let fleetOpt = state.fleet(fleetId)
  if fleetOpt.isNone:
    return
  let fleet = fleetOpt.get()

  # 1. Destroy all squadrons in the fleet
  # Iterate over a copy, as destroySquadron will modify the list
  for squadronId in fleet.squadrons:
    destroySquadron(state, squadronId)

  # 2. Unregister location
  state.unregisterFleetLocation(fleetId, fleet.location)

  # 3. Unregister owner
  state.unregisterFleetOwner(fleetId, fleet.houseId)

  # 4. Remove from entity manager
  state.delFleet(fleetId)

proc moveFleet*(state: var GameState, fleetId: FleetId, destId: SystemId) =
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

proc changeFleetOwner*(state: var GameState, fleetId: FleetId, newOwner: HouseId) =
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
