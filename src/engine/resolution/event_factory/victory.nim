## Victory Event Factory
## Events for house elimination and technology advances
##
## DRY Principle: Single source of truth for victory event creation
## DoD Principle: Data (GameEvent) separated from creation logic

import std/[options, strformat, strutils]
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
  techType: string, # TechField enum name OR "Economic Level" / "Science Level"
  newLevel: int
): event_types.GameEvent =
  ## Create event for technology advancement
  ## Handles both tech fields (CST, WEP, etc.) and research levels (EL, SL)

  # EL and SL are not TechField enum values, so use TechAdvance event with first tech field as placeholder
  if techType in ["Economic Level", "Science Level"]:
    return event_types.GameEvent(
      eventType: event_types.GameEventType.TechAdvance,
      houseId: some(houseId),
      description: &"{techType} advanced to level {newLevel}",
      systemId: none(SystemId),
      techField: TechField.ConstructionTech, # Placeholder for EL/SL
      newLevel: some(newLevel)
    )

  # Regular tech field advancement
  event_types.GameEvent(
    eventType: event_types.GameEventType.TechAdvance,
    houseId: some(houseId),
    description: &"{techType} advanced to level {newLevel}",
    systemId: none(SystemId),
    techField: parseEnum[TechField](techType),
    newLevel: some(newLevel)
  )
