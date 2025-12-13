import std/[options, strformat]
import ../../../common/types/core
import ../../../common/types/units # For ShipClass
import ../../../engine/espionage/types as esp_types # For EspionageAction (for operationType field in event)
import ../types as event_types # Now refers to src/engine/resolution/types.nim

# Export event_types alias for GameEvent types
export event_types

# =============================================================================
# Passive Intelligence Gathering (Legacy + New)
# =============================================================================

proc intelGathered*(
  houseId: HouseId,
  targetHouse: HouseId,
  systemId: SystemId,
  intelType: string
): event_types.GameEvent =
  ## Create event for successful intelligence gathering (legacy ViewWorld)
  event_types.GameEvent(
    eventType: event_types.GameEventType.IntelGathered, # Specific event type
    turn: 0, # Will be set by event dispatcher
    houseId: some(houseId),
    description: &"Gathered {intelType} intelligence on {targetHouse} at " &
                  &"system {systemId}",
    systemId: some(systemId),
    sourceHouseId: some(houseId), # Specific field for Intelligence type
    targetHouseId: some(targetHouse),
    intelType: some(intelType)
  )

proc spyMissionSucceeded*(
  attacker: HouseId,
  target: HouseId,
  systemId: SystemId,
  missionType: string
): event_types.GameEvent =
  ## Create event for successful passive intelligence mission (legacy)
  ## missionType: "SpyOnPlanet", "SpyOnSystem", or "HackStarbase"
  event_types.GameEvent(
    eventType: event_types.GameEventType.SpyMissionSucceeded, # Specific event type
    turn: 0, # Will be set by event dispatcher
    houseId: some(attacker),
    description: &"{missionType} mission succeeded against {target} at " &
                  &"system {systemId}",
    systemId: some(systemId),
    sourceHouseId: some(attacker),
    targetHouseId: some(target),
    operationType: none(esp_types.EspionageAction), # Passive intel, no specific operation
    success: some(true),
    detected: some(false)
  )

proc scoutColonyIntelGathered*(
  spyHouse: HouseId,
  targetHouse: HouseId,
  systemId: SystemId,
  fleetId: FleetId,
  defenses: int,
  economicValue: int,
  hasStarbase: bool,
  quality: string
): event_types.GameEvent =
  ## Create detailed event for scout-based colony intelligence gathering (SpyPlanet mission)
  ## Captures narrative of what was discovered by scout fleet
  var details = &"Defenses: {defenses} ground units"
  if hasStarbase:
    details &= ", Starbase detected"
  details &= &", Economic output: {economicValue} PP"
  details &= &", Intel quality: {quality}"

  event_types.GameEvent(
    eventType: event_types.GameEventType.SpyMissionSucceeded,
    turn: 0,
    houseId: some(spyHouse),
    description: &"Scout fleet {fleetId} gathered colony intelligence on " &
                  &"{targetHouse} at {systemId}: {details}",
    systemId: some(systemId),
    sourceHouseId: some(spyHouse),
    targetHouseId: some(targetHouse),
    success: some(true),
    detected: some(false),
    details: some(details)
  )

proc scoutSystemIntelGathered*(
  spyHouse: HouseId,
  targetHouse: HouseId,
  systemId: SystemId,
  fleetId: FleetId,
  fleetsDetected: int,
  shipsDetected: int,
  quality: string
): event_types.GameEvent =
  ## Create detailed event for scout-based system intelligence gathering (SpySystem mission)
  let details = &"Detected {fleetsDetected} enemy fleets ({shipsDetected} ships total), " &
                &"Intel quality: {quality}"

  event_types.GameEvent(
    eventType: event_types.GameEventType.SpyMissionSucceeded,
    turn: 0,
    houseId: some(spyHouse),
    description: &"Scout fleet {fleetId} gathered system intelligence at " &
                  &"{systemId}: {details}",
    systemId: some(systemId),
    sourceHouseId: some(spyHouse),
    targetHouseId: some(targetHouse),
    success: some(true),
    detected: some(false),
    details: some(details)
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
  quality: string
): event_types.GameEvent =
  ## Create detailed event for scout-based starbase intelligence gathering (HackStarbase mission)
  ## Reports on facilities, dock capacity, and construction/repair activities
  var details = &"Facilities: {starbaseCount} starbases, {spaceportCount} spaceports, {shipyardCount} shipyards"
  details &= &", Total docks: {totalDocks}"
  if shipsUnderConstruction > 0:
    details &= &", {shipsUnderConstruction} ships under construction"
  if shipsUnderRepair > 0:
    details &= &", {shipsUnderRepair} ships under repair"
  if economicData:
    details &= ", Economic/R&D data acquired"
  details &= &", Intel quality: {quality}"

  event_types.GameEvent(
    eventType: event_types.GameEventType.SpyMissionSucceeded,
    turn: 0,
    houseId: some(spyHouse),
    description: &"Scout fleet {fleetId} hacked starbase at {systemId}: {details}",
    systemId: some(systemId),
    sourceHouseId: some(spyHouse),
    targetHouseId: some(targetHouse),
    success: some(true),
    detected: some(false),
    details: some(details)
  )

# =============================================================================
# Active Espionage Operations
# =============================================================================

proc sabotageConducted*(
  attacker: HouseId,
  target: HouseId,
  systemId: SystemId,
  damage: int,
  sabotageType: string # e.g., "Low Impact", "High Impact"
): event_types.GameEvent =
  ## Create event for sabotage operation (Low or High)
  let opType = case sabotageType
    of "Low Impact": esp_types.EspionageAction.SabotageLow
    of "High Impact": esp_types.EspionageAction.SabotageHigh
    else: esp_types.EspionageAction.SabotageLow # Default

  event_types.GameEvent(
    eventType: event_types.GameEventType.SabotageConducted, # Specific event type
    turn: 0, # Will be set by event dispatcher
    houseId: some(attacker),
    description: &"Sabotage ({sabotageType}) conducted against {target} at " &
                  &"system {systemId}: {damage} IU destroyed",
    systemId: some(systemId),
    sourceHouseId: some(attacker),
    targetHouseId: some(target),
    targetSystemId: some(systemId),
    operationType: some(opType),
    success: some(true),
    detected: some(false),
    details: some(&"IU destroyed: {damage}")
  )

proc techTheftExecuted*(
  attacker: HouseId,
  target: HouseId,
  srpStolen: int
): event_types.GameEvent =
  ## Create event for technology theft
  event_types.GameEvent(
    eventType: event_types.GameEventType.TechTheftExecuted, # Specific event type
    turn: 0, # Will be set by event dispatcher
    houseId: some(attacker),
    description: &"Tech theft executed against {target}: {srpStolen} SRP " &
                  &"stolen",
    systemId: none(SystemId),
    sourceHouseId: some(attacker),
    targetHouseId: some(target),
    operationType: some(esp_types.EspionageAction.TechTheft),
    success: some(true),
    detected: some(false),
    details: some(&"SRP stolen: {srpStolen}")
  )

proc assassinationAttempted*(
  attacker: HouseId,
  target: HouseId,
  srpReduction: int
): event_types.GameEvent =
  ## Create event for assassination operation
  event_types.GameEvent(
    eventType: event_types.GameEventType.AssassinationAttempted, # Specific event type
    turn: 0, # Will be set by event dispatcher
    houseId: some(attacker),
    description: &"Assassination attempted against {target}: {srpReduction} " &
                  &"SRP disruption",
    systemId: none(SystemId),
    sourceHouseId: some(attacker),
    targetHouseId: some(target),
    operationType: some(esp_types.EspionageAction.Assassination),
    success: some(true), # Assume success for the event, actual effect is SRP reduction
    detected: some(false),
    details: some(&"SRP reduction: {srpReduction}")
  )

proc economicManipulationExecuted*(
  attacker: HouseId,
  target: HouseId,
  ncvReduction: int
): event_types.GameEvent =
  ## Create event for economic manipulation
  event_types.GameEvent(
    eventType: event_types.GameEventType.EconomicManipulationExecuted, # Specific event type
    turn: 0, # Will be set by event dispatcher
    houseId: some(attacker),
    description: &"Economic manipulation executed against {target}: " &
                  &"{ncvReduction} NCV reduction",
    systemId: none(SystemId),
    sourceHouseId: some(attacker),
    targetHouseId: some(target),
    operationType: some(esp_types.EspionageAction.EconomicManipulation),
    success: some(true),
    detected: some(false),
    details: some(&"NCV reduction: {ncvReduction}")
  )

proc cyberAttackConducted*(
  attacker: HouseId,
  target: HouseId,
  targetSystem: SystemId
): event_types.GameEvent =
  ## Create event for cyber attack on starbase
  event_types.GameEvent(
    eventType: event_types.GameEventType.CyberAttackConducted, # Specific event type
    turn: 0, # Will be set by event dispatcher
    houseId: some(attacker),
    description: &"Cyber attack conducted against {target} starbase at " &
                  &"system {targetSystem}",
    systemId: some(targetSystem),
    sourceHouseId: some(attacker),
    targetHouseId: some(target),
    targetSystemId: some(targetSystem),
    operationType: some(esp_types.EspionageAction.CyberAttack),
    success: some(true),
    detected: some(false)
  )

proc psyopsCampaignLaunched*(
  attacker: HouseId,
  target: HouseId,
  taxIncrease: int
): event_types.GameEvent =
  ## Create event for psychological operations campaign
  event_types.GameEvent(
    eventType: event_types.GameEventType.PsyopsCampaignLaunched, # Specific event type
    turn: 0, # Will be set by event dispatcher
    houseId: some(attacker),
    description: &"Psyops campaign launched against {target}: {taxIncrease}% " &
                  &"tax increase",
    systemId: none(SystemId),
    sourceHouseId: some(attacker),
    targetHouseId: some(target),
    operationType: some(esp_types.EspionageAction.PsyopsCampaign),
    success: some(true),
    detected: some(false),
    details: some(&"Tax increase: {taxIncrease}%")
  )

proc intelligenceTheftExecuted*(
  attacker: HouseId,
  target: HouseId
): event_types.GameEvent =
  ## Create event for intelligence database theft
  event_types.GameEvent(
    eventType: event_types.GameEventType.IntelligenceTheftExecuted, # Specific event type
    turn: 0, # Will be set by event dispatcher
    houseId: some(attacker),
    description: &"Intelligence database stolen from {target}",
    systemId: none(SystemId),
    sourceHouseId: some(attacker),
    targetHouseId: some(target),
    operationType: some(esp_types.EspionageAction.IntelligenceTheft),
    success: some(true),
    detected: some(false)
  )

proc disinformationPlanted*(
  attacker: HouseId,
  target: HouseId
): event_types.GameEvent =
  ## Create event for disinformation operation
  event_types.GameEvent(
    eventType: event_types.GameEventType.DisinformationPlanted, # Specific event type
    turn: 0, # Will be set by event dispatcher
    houseId: some(attacker),
    description: &"Disinformation planted in {target}'s intelligence network",
    systemId: none(SystemId),
    sourceHouseId: some(attacker),
    targetHouseId: some(target),
    operationType: some(esp_types.EspionageAction.PlantDisinformation),
    success: some(true),
    detected: some(false)
  )

# =============================================================================
# Counter-Intelligence Operations
# =============================================================================

proc counterIntelSweepExecuted*(
  defender: HouseId,
  targetSystem: SystemId # Can be none if house-wide
): event_types.GameEvent =
  ## Create event for counter-intelligence sweep
  event_types.GameEvent(
    eventType: event_types.GameEventType.CounterIntelSweepExecuted, # Specific event type
    turn: 0, # Will be set by event dispatcher
    houseId: some(defender),
    description: &"Counter-intelligence sweep executed at system {targetSystem}",
    systemId: some(targetSystem),
    sourceHouseId: some(defender), # The house performing the sweep
    targetHouseId: some(defender), # Target is self
    operationType: some(esp_types.EspionageAction.CounterIntelSweep),
    success: some(true), # Assume sweep itself is successful
    detected: some(false) # Sweep cannot be detected as it's defensive
  )

# =============================================================================
# Detection Events
# =============================================================================

proc spyMissionDetected*(
  attacker: HouseId,
  target: HouseId,
  targetSystem: SystemId,
  missionType: string # e.g., "Sabotage", "Tech Theft"
): event_types.GameEvent =
  ## Create event for detected espionage mission
  let opType = case missionType
    of "Sabotage": esp_types.EspionageAction.SabotageLow # Generic for detection
    of "Tech Theft": esp_types.EspionageAction.TechTheft
    else: esp_types.EspionageAction.IntelligenceTheft

  event_types.GameEvent(
    eventType: event_types.GameEventType.SpyMissionDetected, # Specific event type
    turn: 0, # Will be set by event dispatcher
    houseId: some(attacker), # The house whose mission was detected
    description: &"{missionType} mission detected by {target} at " &
                  &"system {targetSystem}",
    systemId: some(targetSystem),
    sourceHouseId: some(attacker), # The attacker's house
    targetHouseId: some(target), # The defender's house
    targetSystemId: some(targetSystem),
    operationType: some(opType),
    success: some(false), # Mission failed due to detection
    detected: some(true),
    details: some(&"Detected by {target}")
  )

# =============================================================================
# Scout Detection Events
# =============================================================================

proc scoutDetected*(
  owner: HouseId,
  detector: HouseId,
  systemId: SystemId,
  scoutType: string
): event_types.GameEvent =
  ## Create event for scout detection
  event_types.GameEvent(
    eventType: event_types.GameEventType.ScoutDetected, # Specific event type
    turn: 0, # Will be set by event dispatcher
    houseId: some(owner), # The scout's owner
    description: &"{scoutType} scout detected by {detector} at " &
                  &"system {systemId}",
    systemId: some(systemId),
    sourceHouseId: some(detector), # The house that detected
    targetHouseId: some(owner), # The house whose scout was detected
    targetSystemId: some(systemId),
    intelType: some("ScoutDetection"), # Specific detail for case branch
    details: some(&"ScoutType: {scoutType}")
  )

proc scoutDestroyed*(
  owner: HouseId,
  destroyer: HouseId,
  systemId: SystemId
): event_types.GameEvent =
  ## Create event for scout destruction
  event_types.GameEvent(
    eventType: event_types.GameEventType.ScoutDestroyed, # Specific event type
    turn: 0, # Will be set by event dispatcher
    houseId: some(owner), # The scout's owner
    description: &"Scout destroyed by {destroyer} at system {systemId}",
    systemId: some(systemId),
    fleetEventType: some("Destroyed"),
    fleetId: none(FleetId), # No specific fleetId for a single scout
    shipClass: some(ShipClass.Scout),
    details: some(&"Destroyed by {destroyer}")
  )

proc starbaseSurveillanceDetection*(
  starbaseId: string,
  owner: HouseId,
  systemId: SystemId,
  detectedCount: int,
  undetectedCount: int
): event_types.GameEvent =
  ## Create event for starbase surveillance detection
  ## For diagnostics - tracks passive sensor monitoring
  event_types.GameEvent(
    eventType: event_types.GameEventType.StarbaseSurveillanceDetection,
    turn: 0,
    houseId: some(owner),
    description: &"Starbase {starbaseId} surveillance at {systemId}: " &
                 &"{detectedCount} fleets detected, {undetectedCount} evaded",
    systemId: some(systemId),
    surveillanceStarbaseId: some(starbaseId),
    surveillanceOwner: some(owner),
    detectedFleetsCount: some(detectedCount),
    undetectedFleetsCount: some(undetectedCount)
  )
