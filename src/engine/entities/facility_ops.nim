## @entities/facility_ops.nim
##
## Write API for creating and destroying facility entities (Starbases, Spaceports, etc.).
## Ensures consistency between the main facility collections, the `byColony` indexes,
## and the ID lists within each `Colony` object.

import std/[options, tables, sequtils]
import ../types/game_state
import ../state/engine as gs_helpers
import ../state/id_gen
import ../state/entity_manager
import ../types/[core, facilities, colony]

template createFacilityImpl(
    state: var GameState,
    colonyId: ColonyId,
    facilityType: untyped,
    idField: untyped,
    collection: untyped,
    byColonyIndex: untyped,
    colonyList: untyped,
): untyped =
  let facilityId = idField(state)
  let newFacility = facilityType(id: facilityId, colonyId: colonyId)

  collection.entities.addEntity(facilityId, newFacility)
  collection.byColony.mgetOrPut(colonyId, @[]).add(facilityId)

  var colony = gs_helpers.colony(state, colonyId).get()
  colony.colonyList.add(facilityId)
  state.colonies.entities.updateEntity(colonyId, colony)

  return facilityId

template destroyFacilityImpl(
    state: var GameState,
    facilityId: untyped,
    collection: untyped,
    byColonyIndex: untyped,
    colonyList: untyped,
    idType: typedesc,
): untyped =
  let typedId = idType(facilityId)
  let facilityOpt = collection.entities.getEntity(typedId)
  if facilityOpt.isNone:
    return
  let facility = facilityOpt.get()

  var colony = gs_helpers.colony(state, facility.colonyId).get()
  colony.colonyList.keepIf(
    proc(id: idType): bool =
      id != typedId
  )
  state.colonies.entities.updateEntity(colony.id, colony)

  if collection.byColony.contains(facility.colonyId):
    collection.byColony[facility.colonyId].keepIf(
      proc(id: idType): bool =
        id != typedId
    )

  collection.entities.removeEntity(typedId)

proc createStarbase*(state: var GameState, colonyId: ColonyId): StarbaseId =
  createFacilityImpl(
    state, colonyId, Starbase, generateStarbaseId, state.starbases, byColony,
    starbaseIds,
  )

proc destroyStarbase*(state: var GameState, facilityId: StarbaseId) =
  destroyFacilityImpl(
    state, facilityId, state.starbases, byColony, starbaseIds, StarbaseId
  )

proc createSpaceport*(state: var GameState, colonyId: ColonyId): SpaceportId =
  createFacilityImpl(
    state, colonyId, Spaceport, generateSpaceportId, state.spaceports, byColony,
    spaceportIds,
  )

proc destroySpaceport*(state: var GameState, facilityId: SpaceportId) =
  destroyFacilityImpl(
    state, facilityId, state.spaceports, byColony, spaceportIds, SpaceportId
  )

proc createShipyard*(state: var GameState, colonyId: ColonyId): ShipyardId =
  createFacilityImpl(
    state, colonyId, Shipyard, generateShipyardId, state.shipyards, byColony,
    shipyardIds,
  )

proc destroyShipyard*(state: var GameState, facilityId: ShipyardId) =
  destroyFacilityImpl(
    state, facilityId, state.shipyards, byColony, shipyardIds, ShipyardId
  )

proc createDrydock*(state: var GameState, colonyId: ColonyId): DrydockId =
  createFacilityImpl(
    state, colonyId, Drydock, generateDrydockId, state.drydocks, byColony, drydockIds
  )

proc destroyDrydock*(state: var GameState, facilityId: DrydockId) =
  destroyFacilityImpl(
    state, facilityId, state.drydocks, byColony, drydockIds, DrydockId
  )
