## Commissioning Event Factory
## Events for ship/building/unit commissioning and disbanding
##
## DRY Principle: Single source of truth for commissioning event creation
## DoD Principle: Data (GameEvent) separated from creation logic

import std/[options, strformat]
import ../../../common/types/[core, units]
import ../types as res_types

proc shipCommissioned*(
  houseId: HouseId,
  shipClass: ShipClass,
  systemId: SystemId
): res_types.GameEvent =
  ## Create event for ship commissioning
  res_types.GameEvent(
    eventType: res_types.GameEventType.ShipCommissioned,
    houseId: houseId,
    description: &"{shipClass} commissioned at system {systemId}",
    systemId: some(systemId)
  )

proc buildingCompleted*(
  houseId: HouseId,
  buildingType: string,
  systemId: SystemId
): res_types.GameEvent =
  ## Create event for building completion
  res_types.GameEvent(
    eventType: res_types.GameEventType.BuildingCompleted,
    houseId: houseId,
    description: &"{buildingType} completed at system {systemId}",
    systemId: some(systemId)
  )

proc unitRecruited*(
  houseId: HouseId,
  unitType: string,
  systemId: SystemId,
  quantity: int = 1
): res_types.GameEvent =
  ## Create event for ground unit recruitment
  let desc = if quantity == 1:
    &"{unitType} recruited at system {systemId}"
  else:
    &"{quantity} {unitType} units recruited at system {systemId}"
  res_types.GameEvent(
    eventType: res_types.GameEventType.UnitRecruited,
    houseId: houseId,
    description: desc,
    systemId: some(systemId)
  )

proc unitDisbanded*(
  houseId: HouseId,
  unitType: string,
  reason: string,
  systemId: Option[SystemId] = none(SystemId)
): res_types.GameEvent =
  ## Create event for unit disbanding (manual or capacity enforcement)
  res_types.GameEvent(
    eventType: res_types.GameEventType.UnitDisbanded,
    houseId: houseId,
    description: &"{unitType} disbanded: {reason}",
    systemId: systemId
  )
