## Prestige Event Factory
## Events for prestige gains and losses
##
## DRY Principle: Single source of truth for prestige event creation
## DoD Principle: Data (GameEvent) separated from creation logic

import std/[options, strformat]
import ../../../common/types/core
import ../types as res_types

proc prestigeGained*(
  houseId: HouseId,
  amount: int,
  reason: string,
  systemId: Option[SystemId] = none(SystemId)
): res_types.GameEvent =
  ## Create event for prestige gain
  res_types.GameEvent(
    eventType: res_types.GameEventType.PrestigeGained,
    houseId: houseId,
    description: &"Gained {amount} prestige: {reason}",
    systemId: systemId
  )

proc prestigeLost*(
  houseId: HouseId,
  amount: int,
  reason: string,
  systemId: Option[SystemId] = none(SystemId)
): res_types.GameEvent =
  ## Create event for prestige loss
  res_types.GameEvent(
    eventType: res_types.GameEventType.PrestigeLost,
    houseId: houseId,
    description: &"Lost {amount} prestige: {reason}",
    systemId: systemId
  )
