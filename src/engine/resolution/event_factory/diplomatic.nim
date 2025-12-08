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

proc allianceFormed*(
  house1: HouseId,
  house2: HouseId
): res_types.GameEvent =
  ## Create event for alliance formation
  res_types.GameEvent(
    eventType: res_types.GameEventType.AllianceFormed,
    houseId: house1,
    description: &"Alliance formed between {house1} and {house2}",
    systemId: none(SystemId)
  )

proc allianceBroken*(
  house1: HouseId,
  house2: HouseId,
  breakingHouse: HouseId
): res_types.GameEvent =
  ## Create event for alliance breaking
  let otherHouse = if breakingHouse == house1: house2 else: house1
  res_types.GameEvent(
    eventType: res_types.GameEventType.AllianceBroken,
    houseId: breakingHouse,
    description: &"{breakingHouse} broke alliance with {otherHouse}",
    systemId: none(SystemId)
  )
