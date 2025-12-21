import std/[tables, sequtils]
import ../types/[core, fleet]
import ../state/game_state

proc registerFleetLocation(state: var GameState, fleetId: FleetId, sysId: SystemId) =
  ## Internal helper to add a fleet to the system index
  state.fleets.bySystem.mgetOrPut(sysId, @[]).add(fleetId)

proc unregisterFleetLocation(state: var GameState, fleetId: FleetId, sysId: SystemId) =
  ## Internal helper to remove a fleet from the system index
  if state.fleets.bySystem.contains(sysId):
    state.fleets.bySystem[sysId].keepIf(proc(id: FleetId): bool = id != fleetId)

proc moveFleet*(state: var GameState, fleetId: FleetId, destId: SystemId) =
  let fleetOpt = state.getFleet(fleetId)
  if fleetOpt.isNone: return
  
  var fleet = fleetOpt.get()
  let oldId = fleet.location # 'location' is the SystemId field
  
  if oldId == destId: return # Already there
  
  # 1. Update Index: Remove from old, add to new
  state.unregisterFleetLocation(fleetId, oldId)
  state.registerFleetLocation(fleetId, destId)
  
  # 2. Update Data: Change the field and save back to EntityManager
  fleet.location = destId
  state.fleets.entities.updateEntity(fleetId, fleet)
