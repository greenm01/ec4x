## Economic Event Factory
## Events for construction, population transfers, terraforming
##
## DRY Principle: Single source of truth for economic event creation
## DoD Principle: Data (GameEvent) separated from creation logic

import std/[options, strformat]
import ../../../common/types/core
import ../types as event_types # Now refers to src/engine/resolution/types.nim

# Export event_types alias for GameEvent types
export event_types

proc constructionStarted*(
  houseId: HouseId,
  itemType: string,
  systemId: SystemId,
  cost: int
): event_types.GameEvent =
  ## Create event for construction order acceptance
  event_types.GameEvent(
    eventType: event_types.GameEventType.ConstructionStarted, # Specific event type
    turn: 0, # Will be set by event dispatcher
    houseId: some(houseId),
    description: &"Started construction: {itemType} (cost: {cost} PP)",
    systemId: some(systemId),
    category: some("Construction"), # Specific detail for case branch (redundant but for clarity)
    details: some(&"Item: {itemType}, Cost: {cost}PP")
  )

proc populationTransfer*(
  houseId: HouseId,
  ptuAmount: int,
  sourceSystem: SystemId,
  destSystem: SystemId,
  success: bool,
  reason: string = ""
): event_types.GameEvent =
  ## Create event for population transfer via Space Guild
  let desc = if success:
    &"Population transfer: {ptuAmount} PTU from {sourceSystem} to " &
    &"{destSystem}"
  else:
    &"Population transfer failed: {ptuAmount} PTU from {sourceSystem} to " &
    &"{destSystem} - {reason}"
  event_types.GameEvent(
    eventType: event_types.GameEventType.PopulationTransfer, # Specific event type
    turn: 0, # Will be set by event dispatcher
    houseId: some(houseId),
    description: desc,
    systemId: some(destSystem),
    category: some("PopulationTransfer"), # Specific detail for case branch (redundant but for clarity)
    amount: some(ptuAmount),
    details: some(&"From {sourceSystem}, Success: {success}, Reason: {reason}")
  )

proc terraformComplete*(
  houseId: HouseId,
  systemId: SystemId,
  newEnvironment: string
): event_types.GameEvent =
  ## Create event for terraforming completion
  event_types.GameEvent(
    eventType: event_types.GameEventType.TerraformComplete, # Specific event type
    turn: 0, # Will be set by event dispatcher
    houseId: some(houseId),
    description: &"Terraforming complete at system {systemId}: now " &
                  &"{newEnvironment}",
    systemId: some(systemId),
    colonyEventType: some("TerraformComplete"), # Specific detail for case branch (redundant but for clarity)
    details: some(&"New Planet Class: {newEnvironment}")
  )
