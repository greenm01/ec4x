## Victory Event Factory
## Events for house elimination and technology advances
##
## DRY Principle: Single source of truth for victory event creation
## DoD Principle: Data (GameEvent) separated from creation logic

import std/[options, strformat]
import ../../../common/types/core
import ../../../common/types/tech # For TechField (for techType field in event)
import ../types as event_types # Now refers to src/engine/resolution/types.nim

# Export event_types alias for GameEvent types
export event_types

proc houseEliminated*(
  eliminatedHouse: HouseId,
  eliminatedBy: HouseId
): event_types.GameEvent =
  ## Create event for house elimination
  event_types.GameEvent(
    eventType: event_types.GameEventType.HouseEliminated, # Use specific HouseEliminated type
    houseId: some(eliminatedHouse),
    description: &"{eliminatedHouse} eliminated by {eliminatedBy}",
    systemId: none(SystemId),
    eliminatedBy: some(eliminatedBy)
  )

proc techAdvance*(
  houseId: HouseId,
  techType: string, # This should be TechField.str
  newLevel: int
): event_types.GameEvent =
  ## Create event for technology advancement
  event_types.GameEvent(
    eventType: event_types.GameEventType.Research, # Use specific Research event type
    houseId: some(houseId),
    description: &"{techType} advanced to level {newLevel}",
    systemId: none(SystemId),
    techField: some(parseEnum[TechField](techType)), # Convert string to TechField
    newLevel: some(newLevel)
  )
