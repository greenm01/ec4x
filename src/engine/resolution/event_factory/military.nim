## Military Event Factory
## Events for combat, invasions, and fleet operations
##
## DRY Principle: Single source of truth for military event creation
## DoD Principle: Data (GameEvent) separated from creation logic

import std/[options, strformat]
import ../../../common/types/core
import ../types as res_types

proc colonyEstablished*(
  houseId: HouseId,
  systemId: SystemId,
  prestigeAwarded: int = 0
): res_types.GameEvent =
  ## Create event for successful colonization
  let desc = if prestigeAwarded > 0:
    &"Colony established at system {systemId} (+{prestigeAwarded} prestige)"
  else:
    &"Colony established at system {systemId}"
  res_types.GameEvent(
    eventType: res_types.GameEventType.ColonyEstablished,
    houseId: houseId,
    description: desc,
    systemId: some(systemId)
  )

proc systemCaptured*(
  houseId: HouseId,
  systemId: SystemId,
  previousOwner: HouseId
): res_types.GameEvent =
  ## Create event for system capture via invasion
  res_types.GameEvent(
    eventType: res_types.GameEventType.SystemCaptured,
    houseId: houseId,
    description: &"Captured system {systemId} from {previousOwner}",
    systemId: some(systemId)
  )

proc battle*(
  houseId: HouseId,
  systemId: SystemId,
  description: string
): res_types.GameEvent =
  ## Create generic battle event
  res_types.GameEvent(
    eventType: res_types.GameEventType.Battle,
    houseId: houseId,
    description: description,
    systemId: some(systemId)
  )

proc fleetDestroyed*(
  houseId: HouseId,
  fleetId: FleetId,
  systemId: SystemId,
  destroyedBy: HouseId
): res_types.GameEvent =
  ## Create event for fleet destruction
  res_types.GameEvent(
    eventType: res_types.GameEventType.FleetDestroyed,
    houseId: houseId,
    description: &"Fleet {fleetId} destroyed by {destroyedBy} at system " &
                  &"{systemId}",
    systemId: some(systemId)
  )

proc invasionRepelled*(
  houseId: HouseId,
  systemId: SystemId,
  attacker: HouseId
): res_types.GameEvent =
  ## Create event for successful invasion defense
  res_types.GameEvent(
    eventType: res_types.GameEventType.InvasionRepelled,
    houseId: houseId,
    description: &"Repelled invasion by {attacker} at system {systemId}",
    systemId: some(systemId)
  )
