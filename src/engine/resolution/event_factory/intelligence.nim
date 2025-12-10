import std/[options, strformat]
import ../../../common/types/core
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
    eventType: event_types.GameEventType.Intelligence, # Use specific Intelligence event type
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
  ## Create event for successful passive intelligence mission
  ## missionType: "SpyOnPlanet", "SpyOnSystem", or "HackStarbase"
  event_types.GameEvent(
    eventType: event_types.GameEventType.Espionage, # Use specific Espionage event type
    houseId: some(attacker),
    description: &"{missionType} mission succeeded against {target} at " &
                  &"system {systemId}",
    systemId: some(systemId),
    sourceHouseId: some(attacker),
    targetHouseId: target,
    operationType: some(esp_types.EspionageAction.GatherIntelligence), # Generic for passive intel
    success: some(true),
    detected: some(false)
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
    of "Low Impact": esp_types.EspionageAction.SabotageLowImpact
    of "High Impact": esp_types.EspionageAction.SabotageHighImpact
    else: esp_types.EspionageAction.SabotageLowImpact # Default
  
  event_types.GameEvent(
    eventType: event_types.GameEventType.Espionage,
    houseId: some(attacker),
    description: &"Sabotage ({sabotageType}) conducted against {target} at " &
                  &"system {systemId}: {damage} IU destroyed",
    systemId: some(systemId),
    sourceHouseId: some(attacker),
    targetHouseId: target,
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
    eventType: event_types.GameEventType.Espionage,
    houseId: some(attacker),
    description: &"Tech theft executed against {target}: {srpStolen} SRP " &
                  &"stolen",
    systemId: none(SystemId),
    sourceHouseId: some(attacker),
    targetHouseId: target,
    operationType: some(esp_types.EspionageAction.StealTechnology),
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
    eventType: event_types.GameEventType.Espionage,
    houseId: some(attacker),
    description: &"Assassination attempted against {target}: {srpReduction} " &
                  &"SRP disruption",
    systemId: none(SystemId),
    sourceHouseId: some(attacker),
    targetHouseId: target,
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
    eventType: event_types.GameEventType.Espionage,
    houseId: some(attacker),
    description: &"Economic manipulation executed against {target}: " &
                  &"{ncvReduction} NCV reduction",
    systemId: none(SystemId),
    sourceHouseId: some(attacker),
    targetHouseId: target,
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
    eventType: event_types.GameEventType.Espionage,
    houseId: some(attacker),
    description: &"Cyber attack conducted against {target} starbase at " &
                  &"system {targetSystem}",
    systemId: some(targetSystem),
    sourceHouseId: some(attacker),
    targetHouseId: target,
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
    eventType: event_types.GameEventType.Espionage,
    houseId: some(attacker),
    description: &"Psyops campaign launched against {target}: {taxIncrease}% " &
                  &"tax increase",
    systemId: none(SystemId),
    sourceHouseId: some(attacker),
    targetHouseId: target,
    operationType: some(esp_types.EspionageAction.PropagandaCampaign),
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
    eventType: event_types.GameEventType.Espionage,
    houseId: some(attacker),
    description: &"Intelligence database stolen from {target}",
    systemId: none(SystemId),
    sourceHouseId: some(attacker),
    targetHouseId: target,
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
    eventType: event_types.GameEventType.Espionage,
    houseId: some(attacker),
    description: &"Disinformation planted in {target}'s intelligence network",
    systemId: none(SystemId),
    sourceHouseId: some(attacker),
    targetHouseId: target,
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
    eventType: event_types.GameEventType.Espionage,
    houseId: some(defender),
    description: &"Counter-intelligence sweep executed at system {targetSystem}",
    systemId: some(targetSystem),
    sourceHouseId: some(defender), # The house performing the sweep
    targetHouseId: defender, # Target is self
    operationType: some(esp_types.EspionageAction.CounterIntelligenceSweep),
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
    of "Sabotage": esp_types.EspionageAction.SabotageLowImpact # Generic for detection
    of "Tech Theft": esp_types.EspionageAction.StealTechnology
    else: esp_types.EspionageAction.GatherIntelligence

  event_types.GameEvent(
    eventType: event_types.GameEventType.Espionage,
    houseId: some(attacker), # The house whose mission was detected
    description: &"{missionType} mission detected by {target} at " &
                  &"system {targetSystem}",
    systemId: some(targetSystem),
    sourceHouseId: some(attacker), # The attacker's house
    targetHouseId: target, # The defender's house
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
    eventType: event_types.GameEventType.Intelligence, # Use Intelligence event type
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
    eventType: event_types.GameEventType.Fleet, # Use Fleet event type for destruction
    houseId: some(owner), # The scout's owner
    description: &"Scout destroyed by {destroyer} at system {systemId}",
    systemId: some(systemId),
    fleetEventType: some("Destroyed"),
    fleetId: none(FleetId), # No specific fleetId for a single scout
    shipClass: some(ShipClass.Scout),
    details: some(&"Destroyed by {destroyer}")
  )
