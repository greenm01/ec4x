## Diplomatic Event Factory
## Events for diplomatic state changes
##
## DRY Principle: Single source of truth for diplomatic event creation
## DoD Principle: Data (GameEvent) separated from creation logic

import std/[options, strformat]
import ../../../common/types/core
import ../../../common/types/diplomacy # For DiplomaticActionType (needed for event field)
import ../types as event_types # Now refers to src/engine/resolution/types.nim

# Export event_types alias for GameEvent types
export event_types

proc warDeclared*(
  declaringHouse: HouseId,
  targetHouse: HouseId
): event_types.GameEvent =
  ## Create event for war declaration
  event_types.GameEvent(
    eventType: event_types.GameEventType.WarDeclared, # Specific event type
    turn: 0, # Will be set by event dispatcher
    houseId: some(declaringHouse),
    description: &"{declaringHouse} declared war on {targetHouse}",
    systemId: none(SystemId),
    sourceHouseId: some(declaringHouse),
    targetHouseId: some(targetHouse),
    action: some("DeclareWar"), # Specific action field for case branch
    success: some(true),
    newState: some(DiplomaticState.Enemy)
  )

proc peaceSigned*(
  house1: HouseId,
  house2: HouseId
): event_types.GameEvent =
  ## Create event for peace treaty
  event_types.GameEvent(
    eventType: event_types.GameEventType.PeaceSigned, # Specific event type
    turn: 0, # Will be set by event dispatcher
    houseId: some(house1),
    description: &"Peace treaty signed between {house1} and {house2}",
    systemId: none(SystemId),
    sourceHouseId: some(house1), # One of the signing parties
    targetHouseId: some(house2), # The other signing party
    action: some("ProposePeace"), # Specific action field for case branch
    success: some(true),
    newState: some(DiplomaticState.Neutral) # Assuming peace leads to neutral
  )

