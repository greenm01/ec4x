import std/[tables, sequtils, options]
import ../types/[core, game_state, fleet, squadron]
import ../state/[game_state, id_gen, entity_manager]
import ./squadron_ops

proc registerFleetLocation(state: var GameState, fleetId: FleetId, sysId: SystemId) =
  ## Internal helper to add a fleet to the system index
  state.fleets.bySystem.mgetOrPut(sysId, @[]).add(fleetId)

proc unregisterFleetLocation(state: var GameState, fleetId: FleetId, sysId: SystemId) =
  ## Internal helper to remove a fleet from the system index
  if state.fleets.bySystem.contains(sysId):
    state.fleets.bySystem[sysId].keepIf(
      proc(id: FleetId): bool =
        id != fleetId
    )

proc registerFleetOwner(state: var GameState, fleetId: FleetId, owner: HouseId) =
  ## Internal helper to add a fleet to the owner index
  state.fleets.byOwner.mgetOrPut(owner, @[]).add(fleetId)

proc unregisterFleetOwner(state: var GameState, fleetId: FleetId, owner: HouseId) =
  ## Internal helper to remove a fleet from the owner index
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
  state.fleets.entities.addEntity(fleetId, newFleet)

  # 2. Update bySystem index
  state.registerFleetLocation(fleetId, location)

  # 3. Update byOwner index
  state.registerFleetOwner(fleetId, owner)

  return newFleet

proc destroyFleet*(state: var GameState, fleetId: FleetId) =
  ## Destroys a fleet and all squadrons within it.
  let fleetOpt = state.getFleet(fleetId)
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
  state.fleets.entities.removeEntity(fleetId)

proc moveFleet*(state: var GameState, fleetId: FleetId, destId: SystemId) =
  ## Moves a fleet to a new system, updating the spatial index.
  let fleetOpt = state.getFleet(fleetId)
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
  state.fleets.entities.updateEntity(fleetId, fleet)

proc changeFleetOwner*(state: var GameState, fleetId: FleetId, newOwner: HouseId) =
  ## Transfers ownership of a fleet, updating the byOwner index
  let fleetOpt = state.getFleet(fleetId)
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
  state.fleets.entities.updateEntity(fleetId, fleet)
