## Fog-of-war event filtering for PlayerState
##
## Filters GameEvents to only include events visible to a
## specific house based on:
##   - Direct involvement (actor, target, source)
##   - System visibility (Scouted or better)
##   - Public game-wide information

import std/[tables, options]
import ../types/[core, event, player_state]

proc isEventVisibleToHouse*(
    evt: GameEvent,
    houseId: HouseId,
    visibleSystems: Table[SystemId, VisibleSystem]
): bool =
  ## Determine if a GameEvent is visible to the given house.

  # Events directly involving this house
  if evt.houseId == some(houseId):
    return true
  if evt.targetHouseId == some(houseId):
    return true
  if evt.sourceHouseId == some(houseId):
    return true

  # Public events visible to all houses
  case evt.eventType
  of GameEventType.HouseEliminated,
      GameEventType.DiplomaticRelationChanged,
      GameEventType.WarDeclared,
      GameEventType.PeaceSigned,
      GameEventType.TreatyAccepted,
      GameEventType.TreatyBroken:
    return true
  of GameEventType.PrestigeGained,
      GameEventType.PrestigeLost:
    # Prestige changes are public (leaderboard)
    return true
  else:
    discard

  # Events in visible systems (Scouted or better)
  if evt.systemId.isSome:
    let sysId = evt.systemId.get()
    if visibleSystems.hasKey(sysId):
      let vis = visibleSystems[sysId]
      if vis.visibility >= VisibilityLevel.Scouted:
        return true

  false

proc filterEventsForHouse*(
    events: seq[GameEvent],
    houseId: HouseId,
    visibleSystems: Table[SystemId, VisibleSystem]
): seq[GameEvent] =
  ## Filter a list of GameEvents to those visible to the
  ## given house.
  result = @[]
  for evt in events:
    if evt.isEventVisibleToHouse(houseId, visibleSystems):
      result.add(evt)
