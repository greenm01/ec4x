## Military Event Factory
## Events for combat, invasions, and fleet operations
##
## DRY Principle: Single source of truth for military event creation
## DoD Principle: Data (GameEvent) separated from creation logic

import std/[options, strformat]
import ../../../common/types/core
import ../types as event_types # Standardized alias for GameEvent types

# Export event_types alias for GameEvent types
export event_types

proc colonyEstablished*(
  houseId: HouseId,
  systemId: SystemId,
  prestigeAwarded: int = 0
): event_types.GameEvent =
  ## Create event for successful colonization
  let desc = if prestigeAwarded > 0:
    &"Colony established at system {systemId} (+{prestigeAwarded} prestige)"
  else:
    &"Colony established at system {systemId}"
  event_types.GameEvent(
    eventType: event_types.GameEventType.Colony, # Use generic Colony eventType for this
    houseId: some(houseId),
    description: desc,
    systemId: some(systemId),
    colonyEventType: some("Established") # Specific detail for case branch
  )

proc systemCaptured*(
  houseId: HouseId,
  systemId: SystemId,
  previousOwner: HouseId
): event_types.GameEvent =
  ## Create event for system capture via invasion
  event_types.GameEvent(
    eventType: event_types.GameEventType.Colony, # Use generic Colony eventType
    houseId: some(houseId),
    description: &"Captured system {systemId} from {previousOwner}",
    systemId: some(systemId),
    colonyEventType: some("Captured"),
    newOwner: some(houseId),
    oldOwner: some(previousOwner)
  )

proc battle*(
  houseId: HouseId,
  systemId: SystemId,
  description: string
): event_types.GameEvent =
  ## Create generic battle event (CombatResult will be used for specific outcomes)
  event_types.GameEvent(
    eventType: event_types.GameEventType.General, # Generic or Battle if exists
    houseId: some(houseId),
    description: description,
    systemId: some(systemId),
    message: description # Use message field for General kind
  )

proc fleetDestroyed*(
  houseId: HouseId,
  fleetId: FleetId,
  systemId: SystemId,
  destroyedBy: HouseId
): event_types.GameEvent =
  ## Create event for fleet destruction
  event_types.GameEvent(
    eventType: event_types.GameEventType.Fleet, # Use generic Fleet eventType
    houseId: some(houseId),
    description: &"Fleet {fleetId} destroyed by {destroyedBy} at system " &
                  &"{systemId}",
    systemId: some(systemId),
    fleetEventType: some("Destroyed"),
    fleetId: some(fleetId)
  )

proc invasionRepelled*(
  houseId: HouseId,
  systemId: SystemId,
  attacker: HouseId
): event_types.GameEvent =
  ## Create event for successful invasion defense
  event_types.GameEvent(
    eventType: event_types.GameEventType.CombatResult, # Or similar combat outcome type
    houseId: some(houseId),
    description: &"Repelled invasion by {attacker} at system {systemId}",
    systemId: some(systemId),
    attackingHouseId: some(attacker),
    defendingHouseId: some(houseId),
    outcome: some("Defeat") # Attacker defeated
  )
