## Diplomatic Event Factory
## Events for diplomatic state changes
##
## DRY Principle: Single source of truth for diplomatic event creation
## DoD Principle: Data (GameEvent) separated from creation logic

import std/[options, strformat]
import ../../../common/types/core
import ../types as res_types

proc warDeclared*(
  declaringHouse: HouseId,
  targetHouse: HouseId
): res_types.GameEvent =
  ## Create event for war declaration
  res_types.GameEvent(
    eventType: res_types.GameEventType.WarDeclared,
    houseId: declaringHouse,
    description: &"{declaringHouse} declared war on {targetHouse}",
    systemId: none(SystemId)
  )

proc peaceSigned*(
  house1: HouseId,
  house2: HouseId
): res_types.GameEvent =
  ## Create event for peace treaty
  res_types.GameEvent(
    eventType: res_types.GameEventType.PeaceSigned,
    houseId: house1,
    description: &"Peace treaty signed between {house1} and {house2}",
    systemId: none(SystemId)
  )

