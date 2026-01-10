## Alert Event Factory
## Events for warnings, threats, and automation notifications
##
## DRY Principle: Single source of truth for alert event creation
## DoD Principle: Data (GameEvent) separated from creation logic

import std/[options, strformat]
import ../types/[core, event]

# Export event module for GameEvent types
export event

proc resourceWarning*(
    houseId: HouseId, resourceType: string, currentAmount: int, warningThreshold: int
): event.GameEvent =
  ## Create event for low resource warning
  event.GameEvent(
    eventType: event.GameEventType.ResourceWarning, # Specific event type
    houseId: some(houseId),
    description:
      &"Low {resourceType}: {currentAmount} (threshold: " & &"{warningThreshold})",
    systemId: none(SystemId),
    message:
      &"Resource Warning: Low {resourceType} ({currentAmount}/{warningThreshold})",
  )

proc threatDetected*(
    houseId: HouseId, threatType: string, threatSource: HouseId, systemId: SystemId
): event.GameEvent =
  ## Create event for detected threat (enemy fleet, spy, etc.)
  event.GameEvent(
    eventType: event.GameEventType.ThreatDetected, # Specific event type
    houseId: some(houseId),
    description: &"{threatType} detected from {threatSource} at system " & &"{systemId}",
    systemId: some(systemId),
    message: &"Threat Detected: {threatType} from {threatSource} at {systemId}",
  )

proc automationCompleted*(
    houseId: HouseId, actionType: string, systemId: SystemId
): event.GameEvent =
  ## Create event for completed automation (auto-repair, auto-load, etc.)
  event.GameEvent(
    eventType: event.GameEventType.AutomationCompleted, # Specific event type
    houseId: some(houseId),
    description: &"Automation completed: {actionType} at system {systemId}",
    systemId: some(systemId),
    message: &"Automation Completed: {actionType} at {systemId}",
  )
