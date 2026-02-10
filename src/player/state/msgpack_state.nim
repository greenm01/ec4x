## Msgpack state deserialization for TUI
##
## Deserializes PlayerState and PlayerStateDelta from msgpack binary
## received via Nostr transport.

import std/[options, tables]
import msgpack4nim
import ../../engine/types/[core, player_state]
import ../../common/msgpack_types
import ../../daemon/transport/nostr/delta_msgpack

export msgpack_types
export delta_msgpack

# =============================================================================
# Full State Deserialization
# =============================================================================

proc parseFullStateMsgpack*(payload: string): Option[PlayerState] =
  ## Deserialize msgpack binary to PlayerState
  try:
    some(unpack(payload, PlayerState))
  except CatchableError:
    none(PlayerState)

# =============================================================================
# Delta Application
# =============================================================================

proc applyDeltaToPlayerState*(
  state: var PlayerState,
  delta: PlayerStateDelta
) =
  ## Apply a PlayerStateDelta to update the PlayerState in place
  
  # Update metadata
  state.turn = delta.turn
  state.viewingHouse = delta.viewingHouse
  if delta.homeworldSystemIdChanged:
    state.homeworldSystemId = delta.homeworldSystemId
  if delta.treasuryBalanceChanged:
    state.treasuryBalance = delta.treasuryBalance
  if delta.netIncomeChanged:
    state.netIncome = delta.netIncome
  if delta.techLevelsChanged:
    state.techLevels = delta.techLevels
  if delta.researchPointsChanged:
    state.researchPoints = delta.researchPoints
  
  # Apply ownColonies delta
  for colony in delta.ownColonies.added:
    # Find existing or add
    var found = false
    for i, existing in state.ownColonies:
      if existing.id == colony.id:
        state.ownColonies[i] = colony
        found = true
        break
    if not found:
      state.ownColonies.add(colony)
  
  for colony in delta.ownColonies.updated:
    for i, existing in state.ownColonies:
      if existing.id == colony.id:
        state.ownColonies[i] = colony
        break
  
  for removedId in delta.ownColonies.removed:
    let colonyId = ColonyId(removedId)
    var idx = -1
    for i, existing in state.ownColonies:
      if existing.id == colonyId:
        idx = i
        break
    if idx >= 0:
      state.ownColonies.delete(idx)
  
  # Apply ownFleets delta
  for fleet in delta.ownFleets.added:
    var found = false
    for i, existing in state.ownFleets:
      if existing.id == fleet.id:
        state.ownFleets[i] = fleet
        found = true
        break
    if not found:
      state.ownFleets.add(fleet)
  
  for fleet in delta.ownFleets.updated:
    for i, existing in state.ownFleets:
      if existing.id == fleet.id:
        state.ownFleets[i] = fleet
        break
  
  for removedId in delta.ownFleets.removed:
    let fleetId = FleetId(removedId)
    var idx = -1
    for i, existing in state.ownFleets:
      if existing.id == fleetId:
        idx = i
        break
    if idx >= 0:
      state.ownFleets.delete(idx)
  
  # Apply ownShips delta
  for ship in delta.ownShips.added:
    var found = false
    for i, existing in state.ownShips:
      if existing.id == ship.id:
        state.ownShips[i] = ship
        found = true
        break
    if not found:
      state.ownShips.add(ship)
  
  for ship in delta.ownShips.updated:
    for i, existing in state.ownShips:
      if existing.id == ship.id:
        state.ownShips[i] = ship
        break
  
  for removedId in delta.ownShips.removed:
    let shipId = ShipId(removedId)
    var idx = -1
    for i, existing in state.ownShips:
      if existing.id == shipId:
        idx = i
        break
    if idx >= 0:
      state.ownShips.delete(idx)
  
  # Apply ownGroundUnits delta
  for unit in delta.ownGroundUnits.added:
    var found = false
    for i, existing in state.ownGroundUnits:
      if existing.id == unit.id:
        state.ownGroundUnits[i] = unit
        found = true
        break
    if not found:
      state.ownGroundUnits.add(unit)
  
  for unit in delta.ownGroundUnits.updated:
    for i, existing in state.ownGroundUnits:
      if existing.id == unit.id:
        state.ownGroundUnits[i] = unit
        break
  
  for removedId in delta.ownGroundUnits.removed:
    let unitId = GroundUnitId(removedId)
    var idx = -1
    for i, existing in state.ownGroundUnits:
      if existing.id == unitId:
        idx = i
        break
    if idx >= 0:
      state.ownGroundUnits.delete(idx)
  
  # Apply visibleSystems delta
  for system in delta.visibleSystems.added:
    state.visibleSystems[system.systemId] = system
  
  for system in delta.visibleSystems.updated:
    state.visibleSystems[system.systemId] = system
  
  for removedId in delta.visibleSystems.removed:
    state.visibleSystems.del(SystemId(removedId))
  
  # Apply visibleColonies delta
  for colony in delta.visibleColonies.added:
    var found = false
    for i, existing in state.visibleColonies:
      if existing.colonyId == colony.colonyId:
        state.visibleColonies[i] = colony
        found = true
        break
    if not found:
      state.visibleColonies.add(colony)
  
  for colony in delta.visibleColonies.updated:
    for i, existing in state.visibleColonies:
      if existing.colonyId == colony.colonyId:
        state.visibleColonies[i] = colony
        break
  
  for removedId in delta.visibleColonies.removed:
    let colonyId = ColonyId(removedId)
    var idx = -1
    for i, existing in state.visibleColonies:
      if existing.colonyId == colonyId:
        idx = i
        break
    if idx >= 0:
      state.visibleColonies.delete(idx)
  
  # Apply visibleFleets delta
  for fleet in delta.visibleFleets.added:
    var found = false
    for i, existing in state.visibleFleets:
      if existing.fleetId == fleet.fleetId:
        state.visibleFleets[i] = fleet
        found = true
        break
    if not found:
      state.visibleFleets.add(fleet)
  
  for fleet in delta.visibleFleets.updated:
    for i, existing in state.visibleFleets:
      if existing.fleetId == fleet.fleetId:
        state.visibleFleets[i] = fleet
        break
  
  for removedId in delta.visibleFleets.removed:
    let fleetId = FleetId(removedId)
    var idx = -1
    for i, existing in state.visibleFleets:
      if existing.fleetId == fleetId:
        idx = i
        break
    if idx >= 0:
      state.visibleFleets.delete(idx)

  # Apply ltuSystems delta
  if state.ltuSystems.len == 0 and
      (delta.ltuSystems.added.len > 0 or
       delta.ltuSystems.updated.len > 0 or
       delta.ltuSystems.removed.len > 0):
    state.ltuSystems = initTable[SystemId, int32]()
  for entry in delta.ltuSystems.added:
    state.ltuSystems[entry.systemId] = entry.turn

  for entry in delta.ltuSystems.updated:
    state.ltuSystems[entry.systemId] = entry.turn

  for removedId in delta.ltuSystems.removed:
    state.ltuSystems.del(SystemId(removedId))

  # Apply ltuColonies delta
  if state.ltuColonies.len == 0 and
      (delta.ltuColonies.added.len > 0 or
       delta.ltuColonies.updated.len > 0 or
       delta.ltuColonies.removed.len > 0):
    state.ltuColonies = initTable[ColonyId, int32]()
  for entry in delta.ltuColonies.added:
    state.ltuColonies[entry.colonyId] = entry.turn

  for entry in delta.ltuColonies.updated:
    state.ltuColonies[entry.colonyId] = entry.turn

  for removedId in delta.ltuColonies.removed:
    state.ltuColonies.del(ColonyId(removedId))

  # Apply ltuFleets delta
  if state.ltuFleets.len == 0 and
      (delta.ltuFleets.added.len > 0 or
       delta.ltuFleets.updated.len > 0 or
       delta.ltuFleets.removed.len > 0):
    state.ltuFleets = initTable[FleetId, int32]()
  for entry in delta.ltuFleets.added:
    state.ltuFleets[entry.fleetId] = entry.turn

  for entry in delta.ltuFleets.updated:
    state.ltuFleets[entry.fleetId] = entry.turn

  for removedId in delta.ltuFleets.removed:
    state.ltuFleets.del(FleetId(removedId))
  
  # Apply housePrestige delta
  for entry in delta.housePrestige.added:
    state.housePrestige[entry.houseId] = entry.value
  
  for entry in delta.housePrestige.updated:
    state.housePrestige[entry.houseId] = entry.value
  
  for removedId in delta.housePrestige.removed:
    state.housePrestige.del(HouseId(removedId))
  
  # Apply houseColonyCounts delta
  for entry in delta.houseColonyCounts.added:
    state.houseColonyCounts[entry.houseId] = entry.count

  for entry in delta.houseColonyCounts.updated:
    state.houseColonyCounts[entry.houseId] = entry.count

  for removedId in delta.houseColonyCounts.removed:
    state.houseColonyCounts.del(HouseId(removedId))

  # Apply houseNames delta
  for entry in delta.houseNames.added:
    state.houseNames[entry.houseId] = entry.name

  for entry in delta.houseNames.updated:
    state.houseNames[entry.houseId] = entry.name

  for removedId in delta.houseNames.removed:
    state.houseNames.del(HouseId(removedId))

  # Apply diplomaticRelations delta
  for entry in delta.diplomaticRelations.added:
    state.diplomaticRelations[(entry.sourceHouse, entry.targetHouse)] = entry.state
  
  for entry in delta.diplomaticRelations.updated:
    state.diplomaticRelations[(entry.sourceHouse, entry.targetHouse)] = entry.state
  
  for removedId in delta.diplomaticRelations.removed:
    let sourceId = HouseId(removedId shr 16)
    let targetId = HouseId(removedId and 0xFFFF'u32)
    state.diplomaticRelations.del((sourceId, targetId))
  
  # Apply eliminatedHouses delta
  for houseId in delta.eliminatedHouses.added:
    if houseId notin state.eliminatedHouses:
      state.eliminatedHouses.add(houseId)
  
  for removedId in delta.eliminatedHouses.removed:
    let houseId = HouseId(removedId)
    var idx = -1
    for i, existing in state.eliminatedHouses:
      if existing == houseId:
        idx = i
        break
    if idx >= 0:
      state.eliminatedHouses.delete(idx)
  
  # Apply actProgression if changed
  if delta.actProgressionChanged and delta.actProgression.isSome:
    state.actProgression = delta.actProgression.get()

proc parseDeltaMsgpack*(payload: string): Option[PlayerStateDelta] =
  ## Deserialize msgpack binary to PlayerStateDelta
  try:
    some(unpack(payload, PlayerStateDelta))
  except CatchableError:
    none(PlayerStateDelta)

proc applyDeltaMsgpack*(
  state: var PlayerState,
  payload: string
): Option[int32] =
  ## Apply a msgpack-encoded delta to a PlayerState
  ## Returns the new turn number if successful
  let deltaOpt = parseDeltaMsgpack(payload)
  if deltaOpt.isNone:
    return none(int32)
  
  let delta = deltaOpt.get()
  applyDeltaToPlayerState(state, delta)
  some(delta.turn)
