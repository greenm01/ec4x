import std/[tables, options]
import ../../common/types/core # HouseId, SystemId, FleetId
import ../types/core        # GameState, House, Colony, Fleet

# Core state accessors

proc getHouse*(state: GameState, houseId: HouseId): Option[House] =
  ## Get house by ID
  if houseId in state.houses:
    return some(state.houses[houseId])
  return none(House)

proc getColony*(state: GameState, systemId: SystemId): Option[Colony] =
  ## Get colony by system ID
  if systemId in state.colonies:
    return some(state.colonies[systemId])
  return none(Colony)

proc getFleet*(state: GameState, fleetId: FleetId): Option[Fleet] =
  ## Get fleet by ID
  if fleetId in state.fleets:
    return some(state.fleets[fleetId])
  return none(Fleet)

proc getActiveHouses*(state: GameState): seq[House] =
  ## Get all non-eliminated houses
  result = @[]
  for house in state.houses.values:
    if not house.eliminated:
      result.add(house)

proc getHouseColonies*(state: GameState, houseId: HouseId): seq[Colony] =
  ## Get all colonies owned by a house (O(1) lookup via coloniesByOwner index)
  result = @[]
  if houseId in state.coloniesByOwner:
    for systemId in state.coloniesByOwner[houseId]:
      if systemId in state.colonies:
        result.add(state.colonies[systemId])

proc getHouseFleets*(state: GameState, houseId: HouseId): seq[Fleet] =
  ## Get all fleets owned by a house (O(1) lookup via fleetsByOwner index)
  result = @[]
  if houseId in state.fleetsByOwner:
    for fleetId in state.fleetsByOwner[houseId]:
      if fleetId in state.fleets:
        result.add(state.fleets[fleetId])
