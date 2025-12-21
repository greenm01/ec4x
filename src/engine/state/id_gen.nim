import ../types/core
import ./game_state

template defineIdHelpers(IdType: typedesc, counterField: untyped) =
  proc `generate IdType`*(state: var GameState): IdType =
    result = IdType(state.counters.counterField)
    inc state.counters.counterField

# Group all your calls here
defineIdHelpers(PlayerId, nextPlayerId)
defineIdHelpers(HouseId, nextHouseId)
defineIdHelpers(SystemId, nextSystemId)
defineIdHelpers(ColonyId, nextColonyId)
defineIdHelpers(StarbaseId, nextStarbaseId)
defineIdHelpers(SpaceportId, nextSpaceportId)
defineIdHelpers(ShipyardId, nextShipyardId)
defineIdHelpers(DrydockId, nextDrydockId)
defineIdHelpers(FleetId, nextFleetId)
defineIdHelpers(SquadronId, nextSquadronId)
defineIdHelpers(ShipId, nextShipId)
defineIdHelpers(GroundUnitId, nextGroundUnitId)
defineIdHelpers(ConstructionProjectId, nextConstructionProjectId)
defineIdHelpers(RepairProjectId, nextRepairProjectId)
defineIdHelpers(PopulationTransferId, nextPopulationTransferId)
