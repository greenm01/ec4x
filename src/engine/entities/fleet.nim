# src/engine/entities/fleet_manager.nim

proc moveFleet*(state: var GameState, fleetId: FleetId, destination: SystemId) =
  let fleetOpt = state.getFleet(fleetId)
  if fleetOpt.isNone: return
  var fleet = fleetOpt.get()
  let oldSystem = fleet.location

  # 1. Update the actual fleet data
  fleet.location = destination
  state.fleets.entities.updateEntity(fleetId, fleet) # Assuming an update helper

  # 2. Update the Index: Remove from old system
  if state.fleets.bySystem.contains(oldSystem):
    state.fleets.bySystem[oldSystem].keepIf(proc(id: FleetId): bool = id != fleetId)

  # 3. Update the Index: Add to new system
  state.fleets.bySystem.mgetOrPut(destination, @[]).add(fleetId)
