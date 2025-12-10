## Commissioning Event Factory
## Events for ship/building/unit commissioning and disbanding
##
## DRY Principle: Single source of truth for commissioning event creation
## DoD Principle: Data (GameEvent) separated from creation logic

import std/[options, strformat]
import ../../../common/types/[core, units]
import ../types as event_types # Now refers to src/engine/resolution/types.nim

# Export event_types alias for GameEvent types
export event_types

proc shipCommissioned*(
  houseId: HouseId,
  shipClass: ShipClass,
  systemId: SystemId
): event_types.GameEvent =
  ## Create event for ship commissioning
  event_types.GameEvent(
    eventType: event_types.GameEventType.ShipCommissioned, # Specific event type
    turn: 0, # Will be set by event dispatcher
    houseId: some(houseId),
    description: &"{shipClass} commissioned at system {systemId}",
    systemId: some(systemId),
    fleetEventType: some("Created"), # Specific detail for case branch (redundant but for clarity)
    shipClass: some(shipClass),
    details: some(&"ShipClass: {shipClass}")
  )

proc buildingCompleted*(
  houseId: HouseId,
  buildingType: string,
  systemId: SystemId
): event_types.GameEvent =
  ## Create event for building completion
  event_types.GameEvent(
    eventType: event_types.GameEventType.BuildingCompleted, # Specific event type
    turn: 0, # Will be set by event dispatcher
    houseId: some(houseId),
    description: &"{buildingType} completed at system {systemId}",
    systemId: some(systemId),
    colonyEventType: some("BuildingCompleted"), # Specific detail for case branch (redundant but for clarity)
    details: some(&"BuildingType: {buildingType}")
  )

proc unitRecruited*(
  houseId: HouseId,
  unitType: string,
  systemId: SystemId,
  quantity: int = 1
): event_types.GameEvent =
  ## Create event for ground unit recruitment
  let desc = if quantity == 1:
    &"{unitType} recruited at system {systemId}"
  else:
    &"{quantity} {unitType} units recruited at system {systemId}"
  event_types.GameEvent(
    eventType: event_types.GameEventType.UnitRecruited, # Specific event type
    turn: 0, # Will be set by event dispatcher
    houseId: some(houseId),
    description: desc,
    systemId: some(systemId),
    colonyEventType: some("UnitRecruited"), # Specific detail for case branch (redundant but for clarity)
    details: some(&"UnitType: {unitType}, Quantity: {quantity}")
  )

proc unitDisbanded*(
  houseId: HouseId,
  unitType: string,
  reason: string,
  systemId: Option[SystemId] = none(SystemId)
): event_types.GameEvent =
  ## Create event for unit disbanding (manual or capacity enforcement)
  event_types.GameEvent(
    eventType: event_types.GameEventType.UnitDisbanded, # Specific event type
    turn: 0, # Will be set by event dispatcher
    houseId: some(houseId),
    description: &"{unitType} disbanded: {reason}",
    systemId: systemId,
    colonyEventType: some("UnitDisbanded"), # Specific detail for case branch (redundant but for clarity)
    details: some(&"UnitType: {unitType}, Reason: {reason}")
  )
