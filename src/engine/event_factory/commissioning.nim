## Commissioning Event Factory
## Events for ship/building/unit commissioning and disbanding
##
## DRY Principle: Single source of truth for commissioning event creation
## DoD Principle: Data (GameEvent) separated from creation logic

import std/[options, strformat]
import ../types/[core, ship, event, facilities, production]

# Export event module for GameEvent types
export event

proc shipCommissioned*(
    houseId: HouseId, shipClass: ShipClass, systemId: SystemId
): event.GameEvent =
  ## Create event for ship commissioning
  event.GameEvent(
    eventType: event.GameEventType.ShipCommissioned, # Specific event type
    houseId: some(houseId),
    description: &"{shipClass} commissioned at system {systemId}",
    systemId: some(systemId),
    fleetEventType: some("Created"),
      # Specific detail for case branch (redundant but for clarity)
    shipClass: some(shipClass),
    details: some(&"ShipClass: {shipClass}"),
  )

proc buildingCompleted*(
    houseId: HouseId, buildingType: string, systemId: SystemId
): event.GameEvent =
  ## Create event for building completion
  event.GameEvent(
    eventType: event.GameEventType.BuildingCompleted, # Specific event type
    houseId: some(houseId),
    description: &"{buildingType} completed at system {systemId}",
    systemId: some(systemId),
    colonyEventType: some("BuildingCompleted"),
      # Specific detail for case branch (redundant but for clarity)
    details: some(&"BuildingType: {buildingType}"),
  )

proc unitRecruited*(
    houseId: HouseId, unitType: string, systemId: SystemId, quantity: int = 1
): event.GameEvent =
  ## Create event for ground unit recruitment
  let desc =
    if quantity == 1:
      &"{unitType} recruited at system {systemId}"
    else:
      &"{quantity} {unitType} units recruited at system {systemId}"
  event.GameEvent(
    eventType: event.GameEventType.UnitRecruited, # Specific event type
    houseId: some(houseId),
    description: desc,
    systemId: some(systemId),
    colonyEventType: some("UnitRecruited"),
      # Specific detail for case branch (redundant but for clarity)
    details: some(&"UnitType: {unitType}, Quantity: {quantity}"),
  )

proc unitDisbanded*(
    houseId: HouseId,
    unitType: string,
    reason: string,
    systemId: Option[SystemId] = none(SystemId),
): event.GameEvent =
  ## Create event for unit disbanding (manual or capacity enforcement)
  event.GameEvent(
    eventType: event.GameEventType.UnitDisbanded, # Specific event type
    houseId: some(houseId),
    description: &"{unitType} disbanded: {reason}",
    systemId: systemId,
    colonyEventType: some("UnitDisbanded"),
      # Specific detail for case branch (redundant but for clarity)
    details: some(&"UnitType: {unitType}, Reason: {reason}"),
  )

proc constructionLostToCombat*(
    turn: int,
    colonyId: ColonyId,
    neoriaId: NeoriaId,
    facilityType: NeoriaClass,
    itemId: string,
): event.GameEvent =
  ## Create event for construction project lost due to facility damage
  event.GameEvent(
    turn: turn,
    eventType: event.GameEventType.ColonyProjectsLost,
    houseId: none(HouseId), # Filled in by caller if needed
    description: &"Construction project '{itemId}' lost - {facilityType} was damaged in combat",
    systemId: none(SystemId), # Can be filled by caller
  )

proc repairLostToCombat*(
    turn: int,
    colonyId: ColonyId,
    neoriaId: NeoriaId,
    targetType: RepairTargetType,
    shipClass: Option[ShipClass],
): event.GameEvent =
  ## Create event for repair project lost due to facility damage
  let targetDesc = if shipClass.isSome:
    $shipClass.get()
  else:
    $targetType
  event.GameEvent(
    turn: turn,
    eventType: event.GameEventType.ColonyProjectsLost,
    houseId: none(HouseId), # Filled in by caller if needed
    description: &"Repair of {targetDesc} lost - drydock was damaged in combat",
    systemId: none(SystemId), # Can be filled by caller
  )

proc repairStalled*(
    houseId: HouseId,
    shipClass: ShipClass,
    colonyId: ColonyId,
    cost: int32,
): event.GameEvent =
  ## Create event for repair stalled due to insufficient funds (CMD2b)
  ## Per ec4x_canonical_turn_cycle.md CMD2b: Repairs with insufficient funds
  ## are marked Stalled and remain in queue occupying dock space
  event.GameEvent(
    eventType: event.GameEventType.RepairStalled,
    houseId: some(houseId),
    description: &"Repair of {shipClass} stalled - insufficient funds ({cost} PP required)",
    systemId: none(SystemId), # Can be filled if needed
    shipClass: some(shipClass),
    details: some(&"ShipClass: {shipClass}, Cost: {cost} PP, Reason: insufficient_funds"),
  )
