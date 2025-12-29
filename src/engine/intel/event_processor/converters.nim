## Event to Intelligence Report Converters
## Converts GameEvents into structured intelligence reports
##
## DRY Principle: Centralized event-to-intel conversion logic
## DoD Principle: Data transformation without state mutation

import std/[options, strformat]
import ../../types/[core, event, intel]

proc convertCombatEvent*(
    event: GameEvent, observingHouse: HouseId, turn: int32
): Option[ScoutEncounterReport] =
  ## Convert combat GameEvent into ScoutEncounterReport
  ## Combat events (Battle, SystemCaptured, etc.) generate observations
  if event.systemId.isNone:
    return none(ScoutEncounterReport)

  let systemId = event.systemId.get()
  let report = ScoutEncounterReport(
    reportId: &"combat_{systemId}_{turn}_{event.houseId}",
    fleetId: FleetId(0), # Not actual fleet, observed event
    turn: turn,
    systemId: systemId,
    encounterType: ScoutEncounterType.Combat,
    observedHouses:
      if event.houseId.isSome:
        @[event.houseId.get()]
      else:
        @[],
    observedFleetIds: @[],
    colonyId: none(ColonyId),
    fleetMovements: @[],
    description: event.description,
    significance: int32(8), # Combat is high-priority
  )

  return some(report)

proc convertEspionageEvent*(
    event: GameEvent, observingHouse: HouseId, turn: int32
): Option[EspionageActivityReport] =
  ## Convert espionage GameEvent into EspionageActivityReport
  ## Records successful or detected espionage operations
  let report = EspionageActivityReport(
    turn: turn,
    perpetrator:
      if event.houseId.isSome:
        event.houseId.get()
      else:
        HouseId(0),
    action: $event.eventType,
    targetSystem: event.systemId,
    detected: (event.eventType == GameEventType.SpyMissionDetected),
    description: event.description,
  )

  return some(report)

proc convertColonizationEvent*(
    event: GameEvent, observingHouse: HouseId, turn: int32
): Option[ScoutEncounterReport] =
  ## Convert colonization GameEvent into ScoutEncounterReport
  ## Observing enemy colonization provides intelligence
  if event.systemId.isNone:
    return none(ScoutEncounterReport)

  let systemId = event.systemId.get()
  let report = ScoutEncounterReport(
    reportId: &"colonization_{systemId}_{turn}_{event.houseId}",
    fleetId: FleetId(0), # Not actual fleet, observed event
    turn: turn,
    systemId: systemId,
    encounterType: ScoutEncounterType.ColonyDiscovered,
    observedHouses:
      if event.houseId.isSome:
        @[event.houseId.get()]
      else:
        @[],
    observedFleetIds: @[],
    colonyId: none(ColonyId),
    fleetMovements: @[],
    description: event.description,
    significance: int32(7), # Colonization is important
  )

  return some(report)

proc convertScoutDetectionEvent*(
    event: GameEvent, observingHouse: HouseId, turn: int32
): Option[ScoutEncounterReport] =
  ## Convert scout detection GameEvent into ScoutEncounterReport
  ## Records enemy scout activity in your territory
  if event.systemId.isNone:
    return none(ScoutEncounterReport)

  let systemId = event.systemId.get()
  let report = ScoutEncounterReport(
    reportId: &"scout_detected_{systemId}_{turn}_{event.houseId}",
    fleetId: FleetId(0), # Enemy scout fleet
    turn: turn,
    systemId: systemId,
    encounterType: ScoutEncounterType.FleetSighting,
    observedHouses:
      if event.houseId.isSome:
        @[event.houseId.get()]
      else:
        @[],
    observedFleetIds: @[],
    colonyId: none(ColonyId),
    fleetMovements: @[],
    description: event.description,
    significance: int32(6), # Scout detection is moderately important
  )

  return some(report)
