## Alert Event Factory
## Events for warnings, threats, and automation notifications
##
## DRY Principle: Single source of truth for alert event creation
## DoD Principle: Data (GameEvent) separated from creation logic

import std/[options, strformat]
import ../types/core
import ../types/event as event_types

# Export event_types alias for GameEvent types
export event_types

proc resourceWarning*(
  houseId: HouseId,
  resourceType: string,
  currentAmount: int,
  warningThreshold: int
): event_types.GameEvent =
  ## Create event for low resource warning
  event_types.GameEvent(
    eventType: event_types.GameEventType.ResourceWarning, # Specific event type
    houseId: some(houseId),
    description: &"Low {resourceType}: {currentAmount} (threshold: " &
                  &"{warningThreshold})",
    systemId: none(SystemId),
    message: &"Resource Warning: Low {resourceType} ({currentAmount}/{warningThreshold})"
  )

proc threatDetected*(
  houseId: HouseId,
  threatType: string,
  threatSource: HouseId,
  systemId: SystemId
): event_types.GameEvent =
  ## Create event for detected threat (enemy fleet, spy, etc.)
  event_types.GameEvent(
    eventType: event_types.GameEventType.ThreatDetected, # Specific event type
    houseId: some(houseId),
    description: &"{threatType} detected from {threatSource} at system " &
                  &"{systemId}",
    systemId: some(systemId),
    message: &"Threat Detected: {threatType} from {threatSource} at {systemId}"
  )

proc automationCompleted*(
  houseId: HouseId,
  actionType: string,
  systemId: SystemId
): event_types.GameEvent =
  ## Create event for completed automation (auto-repair, auto-load, etc.)
  event_types.GameEvent(
    eventType: event_types.GameEventType.AutomationCompleted, # Specific event type
    houseId: some(houseId),
    description: &"Automation completed: {actionType} at system {systemId}",
    systemId: some(systemId),
    message: &"Automation Completed: {actionType} at {systemId}"
  )
