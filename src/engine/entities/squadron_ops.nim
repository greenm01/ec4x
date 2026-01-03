## @entities/squadron_ops.nim
##
## Write API for creating, destroying, and modifying Squadron entities.
## Ensures that the `byFleet` secondary index is kept consistent.

import std/[tables, sequtils, options]
import ../types/game_state
import ../state/[engine, id_gen]
import ../types/[core, squadron, fleet, ship]
import ../systems/squadron/entity as squadron_entity

proc newSquadron*(
    flagshipId: ShipId,
    flagshipClass: ShipClass,
    id: SquadronId,
    owner: HouseId,
    location: SystemId,
): Squadron =
  ## Create a new squadron with flagship
  ## Use this for commissioning where fleet doesn't exist yet
  ## DoD: Takes ShipId reference and ship class for squadron type determination
  let squadronType = squadron_entity.getSquadronType(flagshipClass)

  Squadron(
    id: id,
    flagshipId: flagshipId,
    ships: @[],
    houseId: owner,
    location: location,
    squadronType: squadronType,
    embarkedFighters: @[],
  )

proc registerSquadronInFleet*(state: var GameState, squadronId: SquadronId, fleetId: FleetId) =
  ## Register a squadron in the byFleet index
  ## Use this when a squadron is added to a fleet outside normal createSquadron() flow
  state[].squadrons[].byFleet.mgetOrPut(fleetId, @[]).add(squadronId)

proc createSquadron*(
    state: var GameState,
    owner: HouseId,
    fleetId: FleetId,
    flagshipId: ShipId,
): Squadron =
  ## Creates a new squadron, adds it to a fleet, and updates all indexes.
  ## Squadron type is derived from flagship's ship class.
  let squadronId = state.generateSquadronId()
  let fleetLocation = state.fleet(fleetId).get().location

  # Derive squadron type from flagship's ship class
  let flagship = state.ship(flagshipId).get()

  # Use newSquadron() for consistent value construction
  let newSquadron = newSquadron(
    flagshipId = flagshipId,
    flagshipClass = flagship.shipClass,
    id = squadronId,
    owner = owner,
    location = fleetLocation,
  )

  state.addSquadron(squadronId, newSquadron)
  state[].squadrons[].byFleet.mgetOrPut(fleetId, @[]).add(squadronId)

  var fleet = state.fleet(fleetId).get()
  fleet.squadrons.add(squadronId)
  state.updateFleet(fleetId, fleet)

  return newSquadron

proc destroySquadron*(state: var GameState, squadronId: SquadronId) =
  ## Destroys a squadron, removing it from the entity manager and all indexes.
  let squadronOpt = state.squadron(squadronId)
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

    var fleet = state.fleet(ownerFleetId).get()
    fleet.squadrons.keepIf(
      proc(id: SquadronId): bool =
        id != squadronId
    )
    state.updateFleet(ownerFleetId, fleet)

  state.delSquadron(squadronId)

proc transferSquadron*(
    state: var GameState, squadronId: SquadronId, newFleetId: FleetId
) =
  ## Moves a squadron from one fleet to another, updating all indexes.
  let squadronOpt = state.squadron(squadronId)
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

    var oldFleet = state.fleet(oldFleetId).get()
    oldFleet.squadrons.keepIf(
      proc(id: SquadronId): bool =
        id != squadronId
    )
    state.updateFleet(oldFleetId, oldFleet)

  state[].squadrons[].byFleet.mgetOrPut(newFleetId, @[]).add(squadronId)

  var newFleet = state.fleet(newFleetId).get()
  newFleet.squadrons.add(squadronId)
  state.updateFleet(newFleetId, newFleet)
