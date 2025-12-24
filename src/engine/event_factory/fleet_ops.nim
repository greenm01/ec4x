## Fleet Operations Event Factory
## Events for standing commands, fleet encounters, reorganization, and scout operations
##
## DRY Principle: Single source of truth for fleet operations event creation
## DoD Principle: Data (GameEvent) separated from creation logic

import std/[options, strformat, sequtils, strutils]
import ../types/[core, ship, event as event_types]

# Export event_types alias
export event_types

# =============================================================================
# Standing Order Events
# =============================================================================

proc standingOrderSet*(
    houseId: HouseId,
    fleetId: FleetId,
    orderType: string,
    enabled: bool,
    activationDelay: int,
    systemId: SystemId,
): event_types.GameEvent =
  ## Create event for standing command configuration
  event_types.GameEvent(
    eventType: event_types.GameEventType.StandingOrderSet,
    houseId: some(houseId),
    description:
      &"Fleet {fleetId} standing command set: {orderType} " &
      &"(enabled={enabled}, delay={activationDelay} turns)",
    systemId: some(systemId),
    fleetId: some(fleetId),
    standingOrderType: some(orderType),
    standingOrderEnabled: some(enabled),
    activationDelay: some(activationDelay),
  )

proc standingOrderActivated*(
    houseId: HouseId,
    fleetId: FleetId,
    standingOrderType: string,
    generatedOrderType: string,
    triggerReason: string,
    systemId: SystemId,
): event_types.GameEvent =
  ## Create event for standing command activation
  event_types.GameEvent(
    eventType: event_types.GameEventType.StandingOrderActivated,
    houseId: some(houseId),
    description:
      &"Fleet {fleetId} standing command activated: {standingOrderType} " &
      &"generated {generatedOrderType} ({triggerReason})",
    systemId: some(systemId),
    fleetId: some(fleetId),
    activatedOrderType: some(standingOrderType),
    generatedFleetCommandType: some(generatedOrderType),
    triggerReason: some(triggerReason),
  )

proc standingOrderSuspended*(
    houseId: HouseId,
    fleetId: FleetId,
    orderType: string,
    reason: string,
    systemId: SystemId,
): event_types.GameEvent =
  ## Create event for standing command suspension
  event_types.GameEvent(
    eventType: event_types.GameEventType.StandingOrderSuspended,
    houseId: some(houseId),
    description: &"Fleet {fleetId} standing command suspended: {orderType} ({reason})",
    systemId: some(systemId),
    fleetId: some(fleetId),
    suspendedOrderType: some(orderType),
    suspendReason: some(reason),
  )

# =============================================================================
# Fleet Encounter Events
# =============================================================================

proc fleetEncounter*(
    houseId: HouseId,
    encounteringFleetId: FleetId,
    encounteredFleetIds: seq[FleetId],
    diplomaticStatus: string,
    systemId: SystemId,
): event_types.GameEvent =
  ## Create event for fleet encounter (detection before combat)
  let fleetList = encounteredFleetIds.mapIt($it).join(", ")
  event_types.GameEvent(
    eventType: event_types.GameEventType.FleetEncounter,
    houseId: some(houseId),
    description:
      &"Fleet {encounteringFleetId} encountered {encounteredFleetIds.len} " &
      &"{diplomaticStatus} fleet(s) at {systemId}: {fleetList}",
    systemId: some(systemId),
    fleetId: some(encounteringFleetId),
    encounteringFleetId: some(encounteringFleetId),
    encounteredFleetIds: some(encounteredFleetIds),
    encounterLocation: some(systemId),
    diplomaticStatus: some(diplomaticStatus),
  )

# =============================================================================
# Fleet Reorganization Events (Zero-Turn Commands)
# =============================================================================

proc fleetMerged*(
    houseId: HouseId,
    sourceFleetId: FleetId,
    targetFleetId: FleetId,
    squadronsMerged: int,
    systemId: SystemId,
): event_types.GameEvent =
  ## Create event for fleet merge
  event_types.GameEvent(
    eventType: event_types.GameEventType.FleetMerged,
    houseId: some(houseId),
    description:
      &"Fleet {sourceFleetId} merged into {targetFleetId}: " &
      &"{squadronsMerged} squadrons transferred",
    systemId: some(systemId),
    fleetId: some(targetFleetId),
    sourceFleetId: some(sourceFleetId),
    targetFleetIdMerge: some(targetFleetId),
    squadronsMerged: some(squadronsMerged),
    mergeLocation: some(systemId),
  )

proc fleetDetachment*(
    houseId: HouseId,
    parentFleetId: FleetId,
    newFleetId: FleetId,
    squadronsDetached: int,
    systemId: SystemId,
): event_types.GameEvent =
  ## Create event for fleet detachment
  event_types.GameEvent(
    eventType: event_types.GameEventType.FleetDetachment,
    houseId: some(houseId),
    description:
      &"Fleet {newFleetId} detached from {parentFleetId}: " &
      &"{squadronsDetached} squadrons split off",
    systemId: some(systemId),
    fleetId: some(newFleetId),
    parentFleetId: some(parentFleetId),
    newFleetId: some(newFleetId),
    squadronsDetached: some(squadronsDetached),
    detachmentLocation: some(systemId),
  )

proc fleetTransfer*(
    houseId: HouseId,
    sourceFleetId: FleetId,
    targetFleetId: FleetId,
    squadronsTransferred: int,
    systemId: SystemId,
): event_types.GameEvent =
  ## Create event for fleet squadron transfer
  event_types.GameEvent(
    eventType: event_types.GameEventType.FleetTransfer,
    houseId: some(houseId),
    description:
      &"{squadronsTransferred} squadrons transferred from " &
      &"fleet {sourceFleetId} to {targetFleetId}",
    systemId: some(systemId),
    fleetId: some(sourceFleetId),
    transferSourceFleetId: some(sourceFleetId),
    transferTargetFleetId: some(targetFleetId),
    squadronsTransferred: some(squadronsTransferred),
    transferLocation: some(systemId),
  )

proc cargoLoaded*(
    houseId: HouseId,
    fleetId: FleetId,
    cargoType: string,
    quantity: int,
    systemId: SystemId,
): event_types.GameEvent =
  ## Create event for cargo loading
  event_types.GameEvent(
    eventType: event_types.GameEventType.CargoLoaded,
    houseId: some(houseId),
    description: &"Fleet {fleetId} loaded {quantity} {cargoType} at {systemId}",
    systemId: some(systemId),
    fleetId: some(fleetId),
    loadingFleetId: some(fleetId),
    cargoType: some(cargoType),
    cargoQuantity: some(quantity),
    loadLocation: some(systemId),
  )

proc cargoUnloaded*(
    houseId: HouseId,
    fleetId: FleetId,
    cargoType: string,
    quantity: int,
    systemId: SystemId,
): event_types.GameEvent =
  ## Create event for cargo unloading
  event_types.GameEvent(
    eventType: event_types.GameEventType.CargoUnloaded,
    houseId: some(houseId),
    description: &"Fleet {fleetId} unloaded {quantity} {cargoType} at {systemId}",
    systemId: some(systemId),
    fleetId: some(fleetId),
    unloadingFleetId: some(fleetId),
    unloadCargoType: some(cargoType),
    unloadCargoQuantity: some(quantity),
    unloadLocation: some(systemId),
  )

# =============================================================================
# Fleet/Squadron Disbanding Events
# =============================================================================

proc fleetDisbanded*(
    houseId: HouseId,
    fleetId: FleetId,
    reason: string,
    salvageValue: int,
    systemId: SystemId,
): event_types.GameEvent =
  ## Create event for fleet disbanded (maintenance shortfall)
  event_types.GameEvent(
    eventType: event_types.GameEventType.FleetDisbanded,
    houseId: some(houseId),
    description:
      &"Fleet {fleetId} disbanded due to {reason} (salvage: {salvageValue} PP)",
    details: some(reason),
    systemId: some(systemId),
    fleetId: some(fleetId),
    fleetEventType: some("Disbanded"),
    salvageValue: some(salvageValue),
  )

proc squadronDisbanded*(
    houseId: HouseId,
    squadronId: string,
    shipClass: ShipClass,
    reason: string,
    systemId: SystemId,
): event_types.GameEvent =
  ## Create event for squadron auto-disbanded (capacity enforcement)
  event_types.GameEvent(
    eventType: event_types.GameEventType.SquadronDisbanded,
    houseId: some(houseId),
    description:
      &"Squadron {squadronId} ({shipClass}) auto-disbanded: {reason} (no salvage)",
    details: some(reason),
    systemId: some(systemId),
    fleetEventType: some("Disbanded"),
    shipClass: some(shipClass),
    salvageValue: some(0),
  )

proc squadronScrapped*(
    houseId: HouseId,
    squadronId: string,
    shipClass: ShipClass,
    reason: string,
    salvageValue: int,
    systemId: SystemId,
): event_types.GameEvent =
  ## Create event for squadron auto-scrapped (capacity enforcement)
  event_types.GameEvent(
    eventType: event_types.GameEventType.SquadronScrapped,
    houseId: some(houseId),
    description:
      &"Squadron {squadronId} ({shipClass}) auto-scrapped: {reason} (salvage: {salvageValue} PP)",
    details: some(reason),
    systemId: some(systemId),
    fleetEventType: some("Scrapped"),
    shipClass: some(shipClass),
    salvageValue: some(salvageValue),
  )
