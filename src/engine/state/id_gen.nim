import ../types/[core, game_state]

template defineIdHelpers(IdType: typedesc, counterField: untyped) =
  proc `generate IdType`*(state: GameState): IdType =
    result = IdType(state.counters.counterField)
    inc state.counters.counterField

# This becomes generateFleetID(), etc....
defineIdHelpers(HouseId, nextHouseId)
defineIdHelpers(SystemId, nextSystemId)
defineIdHelpers(ColonyId, nextColonyId)
defineIdHelpers(NeoriaId, nextNeoriaId)
defineIdHelpers(KastraId, nextKastraId)
defineIdHelpers(FleetId, nextFleetId)
defineIdHelpers(ShipId, nextShipId)
defineIdHelpers(GroundUnitId, nextGroundUnitId)
defineIdHelpers(ConstructionProjectId, nextConstructionProjectId)
defineIdHelpers(RepairProjectId, nextRepairProjectId)
defineIdHelpers(PopulationTransferId, nextPopulationTransferId)
