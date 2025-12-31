## @entities/squadron_ops.nim
##
## Write API for creating, destroying, and modifying Squadron entities.
## Ensures that the `byFleet` secondary index is kept consistent.

import std/[tables, sequtils, options]
import ../types/game_state
import ../state/id_gen
import ../state/entity_manager
import ../state/engine as gs_helpers
import ../types/[core, squadron, fleet]

proc createSquadron*(
    state: var GameState,
    owner: HouseId,
    fleetId: FleetId,
    flagshipId: ShipId,
    squadronType: SquadronClass,
): Squadron =
  ## Creates a new squadron, adds it to a fleet, and updates all indexes.
  let squadronId = state.generateSquadronId()
  let fleetLocation = gs_helpers.fleet(state, fleetId).get().location
  let newSquadron = Squadron(
    id: squadronId,
    flagshipId: flagshipId,
    ships: @[],
    houseId: owner,
    location: fleetLocation,
    squadronType: squadronType,
    destroyed: false,
    embarkedFighters: @[],
  )

  state[].squadrons[].entities.addEntity(squadronId, newSquadron)

  state[].squadrons[].byFleet.mgetOrPut(fleetId, @[]).add(squadronId)

  var fleet = gs_helpers.fleet(state, fleetId).get()
  fleet.squadrons.add(squadronId)
  state[].fleets.entities.updateEntity(fleetId, fleet)

  return newSquadron

proc destroySquadron*(state: var GameState, squadronId: SquadronId) =
  ## Destroys a squadron, removing it from the entity manager and all indexes.
  let squadronOpt = gs_helpers.squadrons(state, squadronId)
  if squadronOpt.isNone:
    return

  var ownerFleetId: FleetId
  for fId, sIds in state[].squadrons[].byFleet.pairs:
    if squadronId in sIds:
      ownerFleetId = fId
      break

  if ownerFleetId != FleetId(0):
    var fleetSquadrons = state[].squadrons[].byFleet[ownerFleetId]
    fleetSquadrons.keepIf(
      proc(id: SquadronId): bool =
        id != squadronId
    )
    state[].squadrons[].byFleet[ownerFleetId] = fleetSquadrons

    var fleet = gs_helpers.fleet(state, ownerFleetId).get()
    fleet.squadrons.keepIf(
      proc(id: SquadronId): bool =
        id != squadronId
    )
    state[].fleets.entities.updateEntity(ownerFleetId, fleet)

  state[].squadrons[].entities.removeEntity(squadronId)

proc transferSquadron*(
    state: var GameState, squadronId: SquadronId, newFleetId: FleetId
) =
  ## Moves a squadron from one fleet to another, updating all indexes.
  let squadronOpt = gs_helpers.squadrons(state, squadronId)
  if squadronOpt.isNone:
    return

  var oldFleetId: FleetId
  for fId, sIds in state[].squadrons[].byFleet.pairs:
    if squadronId in sIds:
      oldFleetId = fId
      break

  if oldFleetId != FleetId(0):
    var oldFleetSquadrons = state[].squadrons[].byFleet[oldFleetId]
    oldFleetSquadrons.keepIf(
      proc(id: SquadronId): bool =
        id != squadronId
    )
    state[].squadrons[].byFleet[oldFleetId] = oldFleetSquadrons

    var oldFleet = gs_helpers.fleet(state, oldFleetId).get()
    oldFleet.squadrons.keepIf(
      proc(id: SquadronId): bool =
        id != squadronId
    )
    state[].fleets.entities.updateEntity(oldFleetId, oldFleet)

  state[].squadrons[].byFleet.mgetOrPut(newFleetId, @[]).add(squadronId)

  var newFleet = gs_helpers.fleet(state, newFleetId).get()
  newFleet.squadrons.add(squadronId)
  state[].fleets.entities.updateEntity(newFleetId, newFleet)
