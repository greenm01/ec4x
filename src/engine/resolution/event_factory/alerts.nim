## Alert Event Factory
## Events for warnings, threats, and automation notifications
##
## DRY Principle: Single source of truth for alert event creation
## DoD Principle: Data (GameEvent) separated from creation logic

import std/[options, strformat]
import ../../../common/types/core
import ../types as res_types

proc resourceWarning*(
  houseId: HouseId,
  resourceType: string,
  currentAmount: int,
  warningThreshold: int
): res_types.GameEvent =
  ## Create event for low resource warning
  res_types.GameEvent(
    eventType: res_types.GameEventType.ResourceWarning,
    houseId: houseId,
    description: &"Low {resourceType}: {currentAmount} (threshold: " &
                  &"{warningThreshold})",
    systemId: none(SystemId)
  )

proc threatDetected*(
  houseId: HouseId,
  threatType: string,
  threatSource: HouseId,
  systemId: SystemId
): res_types.GameEvent =
  ## Create event for detected threat (enemy fleet, spy, etc.)
  res_types.GameEvent(
    eventType: res_types.GameEventType.ThreatDetected,
    houseId: houseId,
    description: &"{threatType} detected from {threatSource} at system " &
                  &"{systemId}",
    systemId: some(systemId)
  )

proc automationCompleted*(
  houseId: HouseId,
  actionType: string,
  systemId: SystemId
): res_types.GameEvent =
  ## Create event for completed automation (auto-repair, auto-load, etc.)
  res_types.GameEvent(
    eventType: res_types.GameEventType.AutomationCompleted,
    houseId: houseId,
    description: &"Automation completed: {actionType} at system {systemId}",
    systemId: some(systemId)
  )
