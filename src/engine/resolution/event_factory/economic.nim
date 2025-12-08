## Economic Event Factory
## Events for construction, population transfers, terraforming
##
## DRY Principle: Single source of truth for economic event creation
## DoD Principle: Data (GameEvent) separated from creation logic

import std/[options, strformat]
import ../../../common/types/core
import ../types as res_types

proc constructionStarted*(
  houseId: HouseId,
  itemType: string,
  systemId: SystemId,
  cost: int
): res_types.GameEvent =
  ## Create event for construction order acceptance
  res_types.GameEvent(
    eventType: res_types.GameEventType.ConstructionStarted,
    houseId: houseId,
    description: &"Started construction: {itemType} (cost: {cost} PP)",
    systemId: some(systemId)
  )

proc populationTransfer*(
  houseId: HouseId,
  ptuAmount: int,
  sourceSystem: SystemId,
  destSystem: SystemId,
  success: bool,
  reason: string = ""
): res_types.GameEvent =
  ## Create event for population transfer via Space Guild
  let desc = if success:
    &"Population transfer: {ptuAmount} PTU from {sourceSystem} to " &
    &"{destSystem}"
  else:
    &"Population transfer failed: {ptuAmount} PTU from {sourceSystem} to " &
    &"{destSystem} - {reason}"
  res_types.GameEvent(
    eventType: res_types.GameEventType.PopulationTransfer,
    houseId: houseId,
    description: desc,
    systemId: some(destSystem)
  )

proc terraformComplete*(
  houseId: HouseId,
  systemId: SystemId,
  newEnvironment: string
): res_types.GameEvent =
  ## Create event for terraforming completion
  res_types.GameEvent(
    eventType: res_types.GameEventType.TerraformComplete,
    houseId: houseId,
    description: &"Terraforming complete at system {systemId}: now " &
                  &"{newEnvironment}",
    systemId: some(systemId)
  )
