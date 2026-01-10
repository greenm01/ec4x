## Fleet Operations Event Factory
## Events for fleet encounters, reorganization, and scout operations
##
## DRY Principle: Single source of truth for fleet operations event creation
## DoD Principle: Data (GameEvent) separated from creation logic

import std/[options, strformat, sequtils, strutils]
import ../types/[core, ship, event]

# Export event_types alias
export event

# =============================================================================
# Fleet Encounter Events
# =============================================================================

proc fleetEncounter*(
    houseId: HouseId,
    encounteringFleetId: FleetId,
    encounteredFleetIds: seq[FleetId],
    diplomaticStatus: string,
    systemId: SystemId,
): event.GameEvent =
  ## Create event for fleet encounter (detection before combat)
  let fleetList = encounteredFleetIds.mapIt($it).join(", ")
  event.GameEvent(
    eventType: event.GameEventType.FleetEncounter,
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
): event.GameEvent =
  ## Create event for fleet merge
  event.GameEvent(
    eventType: event.GameEventType.FleetMerged,
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
): event.GameEvent =
  ## Create event for fleet detachment
  event.GameEvent(
    eventType: event.GameEventType.FleetDetachment,
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
): event.GameEvent =
  ## Create event for fleet squadron transfer
  event.GameEvent(
    eventType: event.GameEventType.FleetTransfer,
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
): event.GameEvent =
  ## Create event for cargo loading
  event.GameEvent(
    eventType: event.GameEventType.CargoLoaded,
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
): event.GameEvent =
  ## Create event for cargo unloading
  event.GameEvent(
    eventType: event.GameEventType.CargoUnloaded,
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
): event.GameEvent =
  ## Create event for fleet disbanded (maintenance shortfall)
  event.GameEvent(
    eventType: event.GameEventType.FleetDisbanded,
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
): event.GameEvent =
  ## Create event for squadron auto-disbanded (capacity enforcement)
  event.GameEvent(
    eventType: event.GameEventType.SquadronDisbanded,
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
): event.GameEvent =
  ## Create event for squadron auto-scrapped (capacity enforcement)
  event.GameEvent(
    eventType: event.GameEventType.SquadronScrapped,
    houseId: some(houseId),
    description:
      &"Squadron {squadronId} ({shipClass}) auto-scrapped: {reason} (salvage: {salvageValue} PP)",
    details: some(reason),
    systemId: some(systemId),
    fleetEventType: some("Scrapped"),
    shipClass: some(shipClass),
    salvageValue: some(salvageValue),
  )
