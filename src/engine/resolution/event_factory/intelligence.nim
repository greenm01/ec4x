## Intelligence Event Factory
## Events for espionage and intel gathering
##
## DRY Principle: Single source of truth for intelligence event creation
## DoD Principle: Data (GameEvent) separated from creation logic

import std/[options, strformat]
import ../../../common/types/core
import ../types as res_types

# =============================================================================
# Passive Intelligence Gathering (Legacy + New)
# =============================================================================

proc intelGathered*(
  houseId: HouseId,
  targetHouse: HouseId,
  systemId: SystemId,
  intelType: string
): res_types.GameEvent =
  ## Create event for successful intelligence gathering (legacy ViewWorld)
  res_types.GameEvent(
    eventType: res_types.GameEventType.IntelGathered,
    houseId: houseId,
    description: &"Gathered {intelType} intelligence on {targetHouse} at " &
                  &"system {systemId}",
    systemId: some(systemId),
    targetHouseId: some(targetHouse)
  )

proc spyMissionSucceeded*(
  attacker: HouseId,
  target: HouseId,
  systemId: SystemId,
  missionType: string
): res_types.GameEvent =
  ## Create event for successful passive intelligence mission
  ## missionType: "SpyOnPlanet", "SpyOnSystem", or "HackStarbase"
  res_types.GameEvent(
    eventType: res_types.GameEventType.SpyMissionSucceeded,
    houseId: attacker,
    description: &"{missionType} mission succeeded against {target} at " &
                  &"system {systemId}",
    systemId: some(systemId),
    targetHouseId: some(target)
  )

# =============================================================================
# Active Espionage Operations
# =============================================================================

proc sabotageConducted*(
  attacker: HouseId,
  target: HouseId,
  systemId: SystemId,
  damage: int,
  sabotageType: string
): res_types.GameEvent =
  ## Create event for sabotage operation (Low or High)
  res_types.GameEvent(
    eventType: res_types.GameEventType.SabotageConducted,
    houseId: attacker,
    description: &"Sabotage ({sabotageType}) conducted against {target} at " &
                  &"system {systemId}: {damage} IU destroyed",
    systemId: some(systemId),
    targetHouseId: some(target)
  )

proc techTheftExecuted*(
  attacker: HouseId,
  target: HouseId,
  srpStolen: int
): res_types.GameEvent =
  ## Create event for technology theft
  res_types.GameEvent(
    eventType: res_types.GameEventType.TechTheftExecuted,
    houseId: attacker,
    description: &"Tech theft executed against {target}: {srpStolen} SRP " &
                  &"stolen",
    systemId: none(SystemId),
    targetHouseId: some(target)
  )

proc assassinationAttempted*(
  attacker: HouseId,
  target: HouseId,
  srpReduction: int
): res_types.GameEvent =
  ## Create event for assassination operation
  res_types.GameEvent(
    eventType: res_types.GameEventType.AssassinationAttempted,
    houseId: attacker,
    description: &"Assassination attempted against {target}: {srpReduction} " &
                  &"SRP disruption",
    systemId: none(SystemId),
    targetHouseId: some(target)
  )

proc economicManipulationExecuted*(
  attacker: HouseId,
  target: HouseId,
  ncvReduction: int
): res_types.GameEvent =
  ## Create event for economic manipulation
  res_types.GameEvent(
    eventType: res_types.GameEventType.EconomicManipulationExecuted,
    houseId: attacker,
    description: &"Economic manipulation executed against {target}: " &
                  &"{ncvReduction} NCV reduction",
    systemId: none(SystemId),
    targetHouseId: some(target)
  )

proc cyberAttackConducted*(
  attacker: HouseId,
  target: HouseId,
  targetSystem: SystemId
): res_types.GameEvent =
  ## Create event for cyber attack on starbase
  res_types.GameEvent(
    eventType: res_types.GameEventType.CyberAttackConducted,
    houseId: attacker,
    description: &"Cyber attack conducted against {target} starbase at " &
                  &"system {targetSystem}",
    systemId: some(targetSystem)
  )

proc psyopsCampaignLaunched*(
  attacker: HouseId,
  target: HouseId,
  taxIncrease: int
): res_types.GameEvent =
  ## Create event for psychological operations campaign
  res_types.GameEvent(
    eventType: res_types.GameEventType.PsyopsCampaignLaunched,
    houseId: attacker,
    description: &"Psyops campaign launched against {target}: {taxIncrease}% " &
                  &"tax increase",
    systemId: none(SystemId),
    targetHouseId: some(target)
  )

proc intelligenceTheftExecuted*(
  attacker: HouseId,
  target: HouseId
): res_types.GameEvent =
  ## Create event for intelligence database theft
  res_types.GameEvent(
    eventType: res_types.GameEventType.IntelligenceTheftExecuted,
    houseId: attacker,
    description: &"Intelligence database stolen from {target}",
    systemId: none(SystemId),
    targetHouseId: some(target)
  )

proc disinformationPlanted*(
  attacker: HouseId,
  target: HouseId
): res_types.GameEvent =
  ## Create event for disinformation operation
  res_types.GameEvent(
    eventType: res_types.GameEventType.DisinformationPlanted,
    houseId: attacker,
    description: &"Disinformation planted in {target}'s intelligence network",
    systemId: none(SystemId),
    targetHouseId: some(target)
  )

# =============================================================================
# Counter-Intelligence Operations
# =============================================================================

proc counterIntelSweepExecuted*(
  defender: HouseId,
  targetSystem: SystemId
): res_types.GameEvent =
  ## Create event for counter-intelligence sweep
  res_types.GameEvent(
    eventType: res_types.GameEventType.CounterIntelSweepExecuted,
    houseId: defender,
    description: &"Counter-intelligence sweep executed at system {targetSystem}",
    systemId: some(targetSystem),
    targetHouseId: none(HouseId)
  )

# =============================================================================
# Detection Events
# =============================================================================

proc spyMissionDetected*(
  attacker: HouseId,
  target: HouseId,
  targetSystem: SystemId,
  missionType: string
): res_types.GameEvent =
  ## Create event for detected espionage mission
  res_types.GameEvent(
    eventType: res_types.GameEventType.SpyMissionDetected,
    houseId: attacker,
    description: &"{missionType} mission detected by {target} at " &
                  &"system {targetSystem}",
    systemId: some(targetSystem),
    targetHouseId: some(target)
  )

# =============================================================================
# Scout Detection Events
# =============================================================================

proc scoutDetected*(
  owner: HouseId,
  detector: HouseId,
  systemId: SystemId,
  scoutType: string
): res_types.GameEvent =
  ## Create event for scout detection
  res_types.GameEvent(
    eventType: res_types.GameEventType.ScoutDetected,
    houseId: owner,
    description: &"{scoutType} scout detected by {detector} at " &
                  &"system {systemId}",
    systemId: some(systemId),
    targetHouseId: some(detector)
  )

proc scoutDestroyed*(
  owner: HouseId,
  destroyer: HouseId,
  systemId: SystemId
): res_types.GameEvent =
  ## Create event for scout destruction
  res_types.GameEvent(
    eventType: res_types.GameEventType.ScoutDestroyed,
    houseId: owner,
    description: &"Scout destroyed by {destroyer} at system {systemId}",
    systemId: some(systemId),
    targetHouseId: some(destroyer)
  )
