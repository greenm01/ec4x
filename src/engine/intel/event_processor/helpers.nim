## Event Processor Helpers
## Shared utility functions for event processing
##
## DRY Principle: Single implementation for presence detection
## DoD Principle: Pure functions operating on GameState data

import std/tables
import ../../../common/types/core
import ../../gamestate
import ../../starmap

proc hasFleetInSystem*(
  state: GameState,
  houseId: HouseId,
  systemId: SystemId
): bool =
  ## Check if house has any fleet in system
  for fleetId, fleet in state.fleets:
    if fleet.owner == houseId and fleet.location == systemId:
      return true
  return false

proc hasColonyInSystem*(
  state: GameState,
  houseId: HouseId,
  systemId: SystemId
): bool =
  ## Check if house owns colony in system
  if state.colonies.hasKey(systemId):
    return state.colonies[systemId].owner == houseId
  return false

proc hasStarbaseSurveillance*(
  state: GameState,
  houseId: HouseId,
  systemId: SystemId
): bool =
  ## Check if house has starbase that can see this system
  ## Starbases provide surveillance of their system + adjacent systems

  # Direct starbase in system
  if state.colonies.hasKey(systemId):
    let colony = state.colonies[systemId]
    if colony.owner == houseId and colony.starbases.len > 0:
      return true

  # Adjacent system starbase (surveillance range)
  for adjSystemId in state.starMap.getAdjacentSystems(systemId):
    if state.colonies.hasKey(adjSystemId):
      let adjColony = state.colonies[adjSystemId]
      if adjColony.owner == houseId and adjColony.starbases.len > 0:
        return true

  return false

proc hasPresenceInSystem*(
  state: GameState,
  houseId: HouseId,
  systemId: SystemId
): bool =
  ## Check if house has any presence (fleet, colony, or surveillance) in system
  ## Used to determine combat event visibility
  return hasFleetInSystem(state, houseId, systemId) or
         hasColonyInSystem(state, houseId, systemId) or
         hasStarbaseSurveillance(state, houseId, systemId)
