## Event Processor Helpers
## Shared utility functions for event processing
##
## DRY Principle: Single implementation for presence detection
## DoD Principle: Pure functions operating on GameState data

import std/[options, tables]
import ../../types/[core, game_state]
import ../../state/[engine as state_helpers, iterators]

proc hasFleetInSystem*(state: GameState, houseId: HouseId, systemId: SystemId): bool =
  ## Check if house has any fleet in system
  ## Uses iterator for efficient lookup
  for fleet in state.fleetsAtSystem(systemId):
    if fleet.houseId == houseId:
      return true
  return false

proc hasColonyInSystem*(state: GameState, houseId: HouseId, systemId: SystemId): bool =
  ## Check if house owns colony in system
  ## Uses safe accessor
  let colonyOpt = state_helpers.colonyBySystem(state, systemId)
  if colonyOpt.isSome:
    let colony = colonyOpt.get()
    return colony.owner == houseId
  return false

proc hasStarbaseSurveillance*(
    state: GameState, houseId: HouseId, systemId: SystemId
): bool =
  ## Check if house has starbase that can see this system
  ## Starbases provide surveillance of their system + adjacent systems

  # Direct starbase in system
  let colonyOpt = state_helpers.colonyBySystem(state, systemId)
  if colonyOpt.isSome:
    let colony = colonyOpt.get()
    if colony.owner == houseId and colony.starbaseIds.len > 0:
      return true

  # Adjacent system starbase (surveillance range)
  if state.starMap.lanes.neighbors.hasKey(systemId):
    let adjacentSystems = state.starMap.lanes.neighbors[systemId]
    for adjSystemId in adjacentSystems:
      let adjColonyOpt = state_helpers.colonyBySystem(state, adjSystemId)
      if adjColonyOpt.isSome:
        let adjColony = adjColonyOpt.get()
        if adjColony.owner == houseId and adjColony.starbaseIds.len > 0:
          return true

  return false

proc hasPresenceInSystem*(
    state: GameState, houseId: HouseId, systemId: SystemId
): bool =
  ## Check if house has any presence (fleet, colony, or surveillance) in system
  ## Used to determine combat event visibility
  return
    hasFleetInSystem(state, houseId, systemId) or
    hasColonyInSystem(state, houseId, systemId) or
    hasStarbaseSurveillance(state, houseId, systemId)
