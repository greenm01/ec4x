## Prestige Event Factory
## Events for prestige gains and losses
##
## DRY Principle: Single source of truth for prestige event creation
## DoD Principle: Data (GameEvent) separated from creation logic

import std/[options, strformat]
import ../types/[core, event]

# Export event module for GameEvent types
export event

proc prestigeGained*(
    houseId: HouseId,
    amount: int,
    reason: string,
    systemId: Option[SystemId] = none(SystemId),
): event.GameEvent =
  ## Create event for prestige gain
  event.GameEvent(
    eventType: event.GameEventType.Prestige, # Use specific Prestige event type
    houseId: some(houseId),
    description: &"Gained {amount} prestige: {reason}",
    systemId: systemId,
    sourceHouseId: some(houseId),
    changeAmount: some(amount),
    details: some(reason),
  )

proc prestigeLost*(
    houseId: HouseId,
    amount: int,
    reason: string,
    systemId: Option[SystemId] = none(SystemId),
): event.GameEvent =
  ## Create event for prestige loss
  event.GameEvent(
    eventType: event.GameEventType.Prestige, # Use specific Prestige event type
    houseId: some(houseId),
    description: &"Lost {amount} prestige: {reason}",
    systemId: systemId,
    sourceHouseId: some(houseId),
    changeAmount: some(-amount), # Negative amount for loss
    details: some(reason),
  )
