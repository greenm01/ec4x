## Victory Event Factory
## Events for house elimination and technology advances
##
## DRY Principle: Single source of truth for victory event creation
## DoD Principle: Data (GameEvent) separated from creation logic

import std/[options, strformat, strutils]
import ../types/[core, tech, event]

# Export event module for GameEvent types
export event

proc houseEliminated*(
    eliminatedHouse: HouseId, eliminatedBy: HouseId
): event.GameEvent =
  ## Create event for house elimination
  event.GameEvent(
    eventType: event.GameEventType.HouseEliminated,
      # Use specific HouseEliminated type
    description: &"{eliminatedHouse} eliminated by {eliminatedBy}",
    systemId: none(SystemId),
    eliminatedBy: some(eliminatedBy),
  )

proc techAdvance*(
    houseId: HouseId,
    techType: string, # TechField enum name OR "Economic Level" / "Science Level"
    newLevel: int,
): event.GameEvent =
  ## Create event for technology advancement
  ## Handles both tech fields (CST, WEP, etc.) and research levels (EL, SL)

  # EL and SL are not TechField enum values, so use TechAdvance event with first tech field as placeholder
  if techType in ["Economic Level", "Science Level"]:
    return event.GameEvent(
      eventType: event.GameEventType.TechAdvance,
      description: &"{techType} advanced to level {newLevel}",
      systemId: none(SystemId),
      techField: TechField.ConstructionTech, # Placeholder for EL/SL
      newLevel: some(newLevel),
    )

  # Regular tech field advancement
  event.GameEvent(
    eventType: event.GameEventType.TechAdvance,
    description: &"{techType} advanced to level {newLevel}",
    systemId: none(SystemId),
    techField: parseEnum[TechField](techType),
    newLevel: some(newLevel),
  )
