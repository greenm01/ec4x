## Victory Event Factory
## Events for house elimination and technology advances
##
## DRY Principle: Single source of truth for victory event creation
## DoD Principle: Data (GameEvent) separated from creation logic

import std/[options, strformat]
import ../../../common/types/core
import ../types as res_types

proc houseEliminated*(
  eliminatedHouse: HouseId,
  eliminatedBy: HouseId
): res_types.GameEvent =
  ## Create event for house elimination
  res_types.GameEvent(
    eventType: res_types.GameEventType.HouseEliminated,
    houseId: eliminatedHouse,
    description: &"{eliminatedHouse} eliminated by {eliminatedBy}",
    systemId: none(SystemId)
  )

proc techAdvance*(
  houseId: HouseId,
  techType: string,
  newLevel: int
): res_types.GameEvent =
  ## Create event for technology advancement
  res_types.GameEvent(
    eventType: res_types.GameEventType.TechAdvance,
    houseId: houseId,
    description: &"{techType} advanced to level {newLevel}",
    systemId: none(SystemId)
  )
