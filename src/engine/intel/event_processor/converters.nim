## Event to Intelligence Report Converters
## Converts GameEvents into structured intelligence reports
##
## DRY Principle: Centralized event-to-intel conversion logic
## DoD Principle: Data transformation without state mutation

import std/[options, strformat]
import ../../../common/types/core
import ../types as intel_types
import ../../resolution/types as res_types

proc convertCombatEvent*(
    event: res_types.GameEvent, observingHouse: HouseId, turn: int
): Option[intel_types.ScoutEncounterReport] =
  ## Convert combat GameEvent into ScoutEncounterReport
  ## Combat events (Battle, SystemCaptured, etc.) generate observations
  if event.systemId.isNone:
    return none(intel_types.ScoutEncounterReport)

  let systemId = event.systemId.get()
  let report = intel_types.ScoutEncounterReport(
    reportId: &"combat_{systemId}_{turn}_{event.houseId}",
    scoutId: "observation", # Not actual scout, but observed event
    turn: turn,
    systemId: systemId,
    encounterType: intel_types.ScoutEncounterType.Combat,
    observedHouses:
      if event.houseId.isSome:
        @[event.houseId.get()]
      else:
        @[],
    fleetDetails: @[], # Simplified - no detailed composition
    description: event.description,
    significance: 8, # Combat is high-priority
  )

  return some(report)

proc convertEspionageEvent*(
    event: res_types.GameEvent, observingHouse: HouseId, turn: int
): Option[intel_types.EspionageActivityReport] =
  ## Convert espionage GameEvent into EspionageActivityReport
  ## Records successful or detected espionage operations
  let report = intel_types.EspionageActivityReport(
    turn: turn,
    perpetrator:
      if event.houseId.isSome:
        event.houseId.get()
      else:
        "",
    action: $event.eventType,
    targetSystem: event.systemId,
    detected: (event.eventType == res_types.GameEventType.SpyMissionDetected),
    description: event.description,
  )

  return some(report)

proc convertColonizationEvent*(
    event: res_types.GameEvent, observingHouse: HouseId, turn: int
): Option[intel_types.ScoutEncounterReport] =
  ## Convert colonization GameEvent into ScoutEncounterReport
  ## Observing enemy colonization provides intelligence
  if event.systemId.isNone:
    return none(intel_types.ScoutEncounterReport)

  let systemId = event.systemId.get()
  let report = intel_types.ScoutEncounterReport(
    reportId: &"colonization_{systemId}_{turn}_{event.houseId}",
    scoutId: "observation",
    turn: turn,
    systemId: systemId,
    encounterType: intel_types.ScoutEncounterType.ColonyDiscovered,
    observedHouses:
      if event.houseId.isSome:
        @[event.houseId.get()]
      else:
        @[],
    fleetDetails: @[],
    description: event.description,
    significance: 7, # Colonization is important
  )

  return some(report)

proc convertScoutDetectionEvent*(
    event: res_types.GameEvent, observingHouse: HouseId, turn: int
): Option[intel_types.ScoutEncounterReport] =
  ## Convert scout detection GameEvent into ScoutEncounterReport
  ## Records enemy scout activity in your territory
  if event.systemId.isNone:
    return none(intel_types.ScoutEncounterReport)

  let systemId = event.systemId.get()
  let report = intel_types.ScoutEncounterReport(
    reportId: &"scout_detected_{systemId}_{turn}_{event.houseId}",
    scoutId: "enemy_scout",
    turn: turn,
    systemId: systemId,
    encounterType: intel_types.ScoutEncounterType.FleetSighting,
    observedHouses:
      if event.houseId.isSome:
        @[event.houseId.get()]
      else:
        @[],
    fleetDetails: @[],
    description: event.description,
    significance: 6, # Scout detection is moderately important
  )

  return some(report)
