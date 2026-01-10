import std/[options, strformat]
import ../types/[core, ship, espionage, event]

# Export event module for GameEvent types
export event

# =============================================================================
# Passive Intelligence Gathering (Legacy + New)
# =============================================================================

proc intelGathered*(
    houseId: HouseId, targetHouse: HouseId, systemId: SystemId, intelType: string
): event.GameEvent =
  ## Create event for successful intelligence gathering (legacy ViewWorld)
  event.GameEvent(
    eventType: event.GameEventType.IntelGathered, # Specific event type
    houseId: some(houseId),
    description:
      &"Gathered {intelType} intelligence on {targetHouse} at " & &"system {systemId}",
    systemId: some(systemId),
    sourceHouseId: some(houseId), # Specific field for Intelligence type
    targetHouseId: some(targetHouse),
    intelType: some(intelType),
  )

proc spyMissionSucceeded*(
    attacker: HouseId, target: HouseId, systemId: SystemId, missionType: string
): event.GameEvent =
  ## Create event for successful passive intelligence mission (legacy)
  ## missionType: "SpyOnPlanet", "SpyOnSystem", or "HackStarbase"
  event.GameEvent(
    eventType: event.GameEventType.SpyMissionSucceeded, # Specific event type
    houseId: some(attacker),
    description:
      &"{missionType} mission succeeded against {target} at " & &"system {systemId}",
    systemId: some(systemId),
    sourceHouseId: some(attacker),
    targetHouseId: some(target),
    operationType: none(EspionageAction), # Passive intel, no specific operation
    success: some(true),
    detected: some(false),
  )

proc scoutColonyIntelGathered*(
    spyHouse: HouseId,
    targetHouse: HouseId,
    systemId: SystemId,
    fleetId: FleetId,
    defenses: int,
    economicValue: int,
    hasStarbase: bool,
    quality: string,
): event.GameEvent =
  ## Create detailed event for scout-based colony intelligence gathering (SpyPlanet mission)
  ## Captures narrative of what was discovered by scout fleet
  var details = &"Defenses: {defenses} ground units"
  if hasStarbase:
    details &= ", Starbase detected"
  details &= &", Economic output: {economicValue} PP"
  details &= &", Intel quality: {quality}"

  event.GameEvent(
    eventType: event.GameEventType.SpyMissionSucceeded,
    houseId: some(spyHouse),
    description:
      &"Scout fleet {fleetId} gathered colony intelligence on " &
      &"{targetHouse} at {systemId}: {details}",
    systemId: some(systemId),
    sourceHouseId: some(spyHouse),
    targetHouseId: some(targetHouse),
    success: some(true),
    detected: some(false),
    details: some(details),
  )

proc scoutSystemIntelGathered*(
    spyHouse: HouseId,
    targetHouse: HouseId,
    systemId: SystemId,
    fleetId: FleetId,
    fleetsDetected: int,
    shipsDetected: int,
    quality: string,
): event.GameEvent =
  ## Create detailed event for scout-based system intelligence gathering (ScoutSystem mission)
  let details =
    &"Detected {fleetsDetected} enemy fleets ({shipsDetected} ships total), " &
    &"Intel quality: {quality}"

  event.GameEvent(
    eventType: event.GameEventType.SpyMissionSucceeded,
    houseId: some(spyHouse),
    description:
      &"Scout fleet {fleetId} gathered system intelligence at " &
      &"{systemId}: {details}",
    systemId: some(systemId),
    sourceHouseId: some(spyHouse),
    targetHouseId: some(targetHouse),
    success: some(true),
    detected: some(false),
    details: some(details),
  )

proc scoutStarbaseIntelGathered*(
    spyHouse: HouseId,
    targetHouse: HouseId,
    systemId: SystemId,
    fleetId: FleetId,
    starbaseCount: int,
    spaceportCount: int,
    shipyardCount: int,
    totalDocks: int,
    shipsUnderConstruction: int,
    shipsUnderRepair: int,
    economicData: bool,
    quality: string,
): event.GameEvent =
  ## Create detailed event for scout-based starbase intelligence gathering (HackStarbase mission)
  ## Reports on facilities, dock capacity, and construction/repair activities
  var details =
    &"Facilities: {starbaseCount} starbases, {spaceportCount} spaceports, {shipyardCount} shipyards"
  details &= &", Total docks: {totalDocks}"
  if shipsUnderConstruction > 0:
    details &= &", {shipsUnderConstruction} ships under construction"
  if shipsUnderRepair > 0:
    details &= &", {shipsUnderRepair} ships under repair"
  if economicData:
    details &= ", Economic/R&D data acquired"
  details &= &", Intel quality: {quality}"

  event.GameEvent(
    eventType: event.GameEventType.SpyMissionSucceeded,
    houseId: some(spyHouse),
    description: &"Scout fleet {fleetId} hacked starbase at {systemId}: {details}",
    systemId: some(systemId),
    sourceHouseId: some(spyHouse),
    targetHouseId: some(targetHouse),
    success: some(true),
    detected: some(false),
    details: some(details),
  )

# =============================================================================
# Active Espionage Operations
# =============================================================================

proc sabotageConducted*(
    attacker: HouseId,
    target: HouseId,
    systemId: SystemId,
    damage: int,
    sabotageType: string, # e.g., "Low Impact", "High Impact"
): event.GameEvent =
  ## Create event for sabotage operation (Low or High)
  let opType =
    case sabotageType
    of "Low Impact": EspionageAction.SabotageLow
    of "High Impact": EspionageAction.SabotageHigh
    else: EspionageAction.SabotageLow
    # Default

  event.GameEvent(
    eventType: event.GameEventType.SabotageConducted, # Specific event type
    houseId: some(attacker),
    description:
      &"Sabotage ({sabotageType}) conducted against {target} at " &
      &"system {systemId}: {damage} IU destroyed",
    systemId: some(systemId),
    sourceHouseId: some(attacker),
    targetHouseId: some(target),
    targetSystemId: some(systemId),
    operationType: some(opType),
    success: some(true),
    detected: some(false),
    details: some(&"IU destroyed: {damage}"),
  )

proc techTheftExecuted*(
    attacker: HouseId, target: HouseId, srpStolen: int
): event.GameEvent =
  ## Create event for technology theft
  event.GameEvent(
    eventType: event.GameEventType.TechTheftExecuted, # Specific event type
    houseId: some(attacker),
    description: &"Tech theft executed against {target}: {srpStolen} SRP " & &"stolen",
    systemId: none(SystemId),
    sourceHouseId: some(attacker),
    targetHouseId: some(target),
    operationType: some(EspionageAction.TechTheft),
    success: some(true),
    detected: some(false),
    details: some(&"SRP stolen: {srpStolen}"),
  )

proc assassinationAttempted*(
    attacker: HouseId, target: HouseId, srpReduction: int
): event.GameEvent =
  ## Create event for assassination operation
  event.GameEvent(
    eventType: event.GameEventType.AssassinationAttempted, # Specific event type
    houseId: some(attacker),
    description:
      &"Assassination attempted against {target}: {srpReduction} " & &"SRP disruption",
    systemId: none(SystemId),
    sourceHouseId: some(attacker),
    targetHouseId: some(target),
    operationType: some(EspionageAction.Assassination),
    success: some(true), # Assume success for the event, actual effect is SRP reduction
    detected: some(false),
    details: some(&"SRP reduction: {srpReduction}"),
  )

proc economicManipulationExecuted*(
    attacker: HouseId, target: HouseId, ncvReduction: int
): event.GameEvent =
  ## Create event for economic manipulation
  event.GameEvent(
    eventType: event.GameEventType.EconomicManipulationExecuted,
      # Specific event type
    houseId: some(attacker),
    description:
      &"Economic manipulation executed against {target}: " &
      &"{ncvReduction} NCV reduction",
    systemId: none(SystemId),
    sourceHouseId: some(attacker),
    targetHouseId: some(target),
    operationType: some(EspionageAction.EconomicManipulation),
    success: some(true),
    detected: some(false),
    details: some(&"NCV reduction: {ncvReduction}"),
  )

proc cyberAttackConducted*(
    attacker: HouseId, target: HouseId, targetSystem: SystemId
): event.GameEvent =
  ## Create event for cyber attack on starbase
  event.GameEvent(
    eventType: event.GameEventType.CyberAttackConducted, # Specific event type
    houseId: some(attacker),
    description:
      &"Cyber attack conducted against {target} starbase at " & &"system {targetSystem}",
    systemId: some(targetSystem),
    sourceHouseId: some(attacker),
    targetHouseId: some(target),
    targetSystemId: some(targetSystem),
    operationType: some(EspionageAction.CyberAttack),
    success: some(true),
    detected: some(false),
  )

proc psyopsCampaignLaunched*(
    attacker: HouseId, target: HouseId, taxIncrease: int
): event.GameEvent =
  ## Create event for psychological operations campaign
  event.GameEvent(
    eventType: event.GameEventType.PsyopsCampaignLaunched, # Specific event type
    houseId: some(attacker),
    description:
      &"Psyops campaign launched against {target}: {taxIncrease}% " & &"tax increase",
    systemId: none(SystemId),
    sourceHouseId: some(attacker),
    targetHouseId: some(target),
    operationType: some(EspionageAction.PsyopsCampaign),
    success: some(true),
    detected: some(false),
    details: some(&"Tax increase: {taxIncrease}%"),
  )

proc intelTheftExecuted*(
    attacker: HouseId, target: HouseId
): event.GameEvent =
  ## Create event for intelligence database theft
  event.GameEvent(
    eventType: event.GameEventType.IntelTheftExecuted,
      # Specific event type
    houseId: some(attacker),
    description: &"Intelligence database stolen from {target}",
    systemId: none(SystemId),
    sourceHouseId: some(attacker),
    targetHouseId: some(target),
    operationType: some(EspionageAction.IntelTheft),
    success: some(true),
    detected: some(false),
  )

proc disinformationPlanted*(attacker: HouseId, target: HouseId): event.GameEvent =
  ## Create event for disinformation operation
  event.GameEvent(
    eventType: event.GameEventType.DisinformationPlanted, # Specific event type
    houseId: some(attacker),
    description: &"Disinformation planted in {target}'s intelligence network",
    systemId: none(SystemId),
    sourceHouseId: some(attacker),
    targetHouseId: some(target),
    operationType: some(EspionageAction.PlantDisinformation),
    success: some(true),
    detected: some(false),
  )

# =============================================================================
# Counter-Intelligence Operations
# =============================================================================

proc counterIntelSweepExecuted*(
    defender: HouseId, targetSystem: SystemId, # Can be none if house-wide
): event.GameEvent =
  ## Create event for counter-intelligence sweep
  event.GameEvent(
    eventType: event.GameEventType.CounterIntelSweepExecuted,
      # Specific event type
    houseId: some(defender),
    description: &"Counter-intelligence sweep executed at system {targetSystem}",
    systemId: some(targetSystem),
    sourceHouseId: some(defender), # The house performing the sweep
    targetHouseId: some(defender), # Target is self
    operationType: some(EspionageAction.CounterIntelSweep),
    success: some(true), # Assume sweep itself is successful
    detected: some(false), # Sweep cannot be detected as it's defensive
  )

# =============================================================================
# Detection Events
# =============================================================================

proc spyMissionDetected*(
    attacker: HouseId,
    target: HouseId,
    targetSystem: SystemId,
    missionType: string, # e.g., "Sabotage", "Tech Theft"
): event.GameEvent =
  ## Create event for detected espionage mission
  let opType =
    case missionType
    of "Sabotage":
      EspionageAction.SabotageLow
    # Generic for detection
    of "Tech Theft":
      EspionageAction.TechTheft
    else:
      EspionageAction.IntelTheft

  event.GameEvent(
    eventType: event.GameEventType.SpyMissionDetected, # Specific event type
    houseId: some(attacker), # The house whose mission was detected
    description:
      &"{missionType} mission detected by {target} at " & &"system {targetSystem}",
    systemId: some(targetSystem),
    sourceHouseId: some(attacker), # The attacker's house
    targetHouseId: some(target), # The defender's house
    targetSystemId: some(targetSystem),
    operationType: some(opType),
    success: some(false), # Mission failed due to detection
    detected: some(true),
    details: some(&"Detected by {target}"),
  )

# =============================================================================
# Scout Detection Events
# =============================================================================

proc scoutDetected*(
    owner: HouseId, detector: HouseId, systemId: SystemId, scoutType: string
): event.GameEvent =
  ## Create event for scout detection
  event.GameEvent(
    eventType: event.GameEventType.ScoutDetected, # Specific event type
    houseId: some(owner), # The scout's owner
    description: &"{scoutType} scout detected by {detector} at " & &"system {systemId}",
    systemId: some(systemId),
    sourceHouseId: some(detector), # The house that detected
    targetHouseId: some(owner), # The house whose scout was detected
    targetSystemId: some(systemId),
    intelType: some("ScoutDetection"), # Specific detail for case branch
    details: some(&"ScoutType: {scoutType}"),
  )

proc scoutDestroyed*(
    owner: HouseId, destroyer: HouseId, systemId: SystemId
): event.GameEvent =
  ## Create event for scout destruction
  event.GameEvent(
    eventType: event.GameEventType.ScoutDestroyed, # Specific event type
    houseId: some(owner), # The scout's owner
    description: &"Scout destroyed by {destroyer} at system {systemId}",
    systemId: some(systemId),
    fleetEventType: some("Destroyed"),
    fleetId: none(FleetId), # No specific fleetId for a single scout
    shipClass: some(ship.ShipClass.Scout),
    details: some(&"Destroyed by {destroyer}"),
  )

proc starbaseSurveillanceDetection*(
    starbaseId: string,
    owner: HouseId,
    systemId: SystemId,
    detectedCount: int,
    undetectedCount: int,
): event.GameEvent =
  ## Create event for starbase surveillance detection
  ## For diagnostics - tracks passive sensor monitoring
  event.GameEvent(
    eventType: event.GameEventType.StarbaseSurveillanceDetection,
    houseId: some(owner),
    description:
      &"Starbase {starbaseId} surveillance at {systemId}: " &
      &"{detectedCount} fleets detected, {undetectedCount} evaded",
    systemId: some(systemId),
    surveillanceStarbaseId: some(starbaseId),
    surveillanceOwner: some(owner),
    detectedFleetsCount: some(detectedCount),
    undetectedFleetsCount: some(undetectedCount),
  )
