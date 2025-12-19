## Reverse Index Maintenance for GameState Optimization
##
## Provides safe, consistent updates to persistent reverse indices.
## ALL fleet/colony mutations MUST call these procs to maintain invariants.
##
## Design invariants:
## - fleetsByLocation[loc] contains EXACTLY the fleets at that location
## - fleetsByOwner[owner] contains EXACTLY the fleets owned by that owner
## - coloniesByOwner[owner] contains EXACTLY the colonies owned by that
##   owner
##
## Thread safety: Not required (turn resolution is sequential)
## Performance: O(1) index updates, O(k) where k = small fleet/colony
## counts

import std/[tables, sequtils, algorithm]
import gamestate
import ../common/types/core

# ===========================================================================
# Fleet Index Maintenance
# ===========================================================================

proc addFleetToIndices*(
  state: var GameState,
  fleetId: FleetId,
  owner: HouseId,
  location: SystemId
) =
  ## Register new fleet in all indices
  ## Called after: Fleet creation

  # Add to location index
  if location notin state.fleetsByLocation:
    state.fleetsByLocation[location] = @[]
  state.fleetsByLocation[location].add(fleetId)

  # Add to owner index
  if owner notin state.fleetsByOwner:
    state.fleetsByOwner[owner] = @[]
  state.fleetsByOwner[owner].add(fleetId)

proc removeFleetFromIndices*(
  state: var GameState,
  fleetId: FleetId,
  owner: HouseId,
  location: SystemId
) =
  ## Unregister fleet from all indices
  ## Called before: Fleet deletion

  # Remove from location index
  if location in state.fleetsByLocation:
    let idx = state.fleetsByLocation[location].find(fleetId)
    if idx >= 0:
      state.fleetsByLocation[location].delete(idx)
    # Clean up empty entries
    if state.fleetsByLocation[location].len == 0:
      state.fleetsByLocation.del(location)

  # Remove from owner index
  if owner in state.fleetsByOwner:
    let idx = state.fleetsByOwner[owner].find(fleetId)
    if idx >= 0:
      state.fleetsByOwner[owner].delete(idx)
    # Clean up empty entries
    if state.fleetsByOwner[owner].len == 0:
      state.fleetsByOwner.del(owner)

proc updateFleetLocation*(
  state: var GameState,
  fleetId: FleetId,
  oldLocation: SystemId,
  newLocation: SystemId
) =
  ## Update fleet location index after movement
  ## Called after: Fleet movement orders

  if oldLocation == newLocation:
    return  # No change needed

  # Remove from old location
  if oldLocation in state.fleetsByLocation:
    let idx = state.fleetsByLocation[oldLocation].find(fleetId)
    if idx >= 0:
      state.fleetsByLocation[oldLocation].delete(idx)
    if state.fleetsByLocation[oldLocation].len == 0:
      state.fleetsByLocation.del(oldLocation)

  # Add to new location
  if newLocation notin state.fleetsByLocation:
    state.fleetsByLocation[newLocation] = @[]
  state.fleetsByLocation[newLocation].add(fleetId)

# ===========================================================================
# Colony Index Maintenance
# ===========================================================================

proc addColonyToIndices*(
  state: var GameState,
  systemId: SystemId,
  owner: HouseId
) =
  ## Register new colony in indices
  ## Called after: ETAC colonization, game initialization

  if owner notin state.coloniesByOwner:
    state.coloniesByOwner[owner] = @[]
  state.coloniesByOwner[owner].add(systemId)

proc removeColonyFromIndices*(
  state: var GameState,
  systemId: SystemId,
  owner: HouseId
) =
  ## Unregister colony from indices
  ## Called before: Colony deletion (if implemented)

  if owner in state.coloniesByOwner:
    let idx = state.coloniesByOwner[owner].find(systemId)
    if idx >= 0:
      state.coloniesByOwner[owner].delete(idx)
    if state.coloniesByOwner[owner].len == 0:
      state.coloniesByOwner.del(owner)

proc updateColonyOwner*(
  state: var GameState,
  systemId: SystemId,
  oldOwner: HouseId,
  newOwner: HouseId
) =
  ## Update colony ownership index after conquest
  ## Called after: Successful invasion

  # Remove from old owner
  if oldOwner in state.coloniesByOwner:
    let idx = state.coloniesByOwner[oldOwner].find(systemId)
    if idx >= 0:
      state.coloniesByOwner[oldOwner].delete(idx)
    if state.coloniesByOwner[oldOwner].len == 0:
      state.coloniesByOwner.del(oldOwner)

  # Add to new owner
  if newOwner notin state.coloniesByOwner:
    state.coloniesByOwner[newOwner] = @[]
  state.coloniesByOwner[newOwner].add(systemId)

# ===========================================================================
# Index Initialization
# ===========================================================================

proc initializeGameIndices*(state: var GameState) =
  ## Initialize reverse indices from current game state
  ## Called during game initialization and after deserialization

  state.fleetsByLocation = initTable[SystemId, seq[FleetId]]()
  state.fleetsByOwner = initTable[HouseId, seq[FleetId]]()
  state.coloniesByOwner = initTable[HouseId, seq[SystemId]]()

  # Build fleet indices
  for fleetId, fleet in state.fleets:
    # Index by location
    if fleet.location notin state.fleetsByLocation:
      state.fleetsByLocation[fleet.location] = @[]
    state.fleetsByLocation[fleet.location].add(fleetId)

    # Index by owner
    if fleet.owner notin state.fleetsByOwner:
      state.fleetsByOwner[fleet.owner] = @[]
    state.fleetsByOwner[fleet.owner].add(fleetId)

  # Build colony index
  for systemId, colony in state.colonies:
    if colony.owner notin state.coloniesByOwner:
      state.coloniesByOwner[colony.owner] = @[]
    state.coloniesByOwner[colony.owner].add(systemId)

# ===========================================================================
# Validation (for testing/debugging)
# ===========================================================================

proc validateIndices*(state: GameState): seq[string] =
  ## Verify index consistency with actual game state
  ## Returns list of inconsistencies (empty = valid)
  ## Used in tests and debug assertions

  result = @[]

  # Validate fleetsByLocation
  var actualFleetsByLocation = initTable[SystemId, seq[FleetId]]()
  for fleetId, fleet in state.fleets:
    if fleet.location notin actualFleetsByLocation:
      actualFleetsByLocation[fleet.location] = @[]
    actualFleetsByLocation[fleet.location].add(fleetId)

  for loc, fleets in state.fleetsByLocation:
    if loc notin actualFleetsByLocation:
      result.add("fleetsByLocation has extra location: " & $loc)
    elif fleets.sorted != actualFleetsByLocation[loc].sorted:
      result.add("fleetsByLocation mismatch at " & $loc)

  for loc, fleets in actualFleetsByLocation:
    if loc notin state.fleetsByLocation:
      result.add("fleetsByLocation missing location: " & $loc)

  # Validate fleetsByOwner
  var actualFleetsByOwner = initTable[HouseId, seq[FleetId]]()
  for fleetId, fleet in state.fleets:
    if fleet.owner notin actualFleetsByOwner:
      actualFleetsByOwner[fleet.owner] = @[]
    actualFleetsByOwner[fleet.owner].add(fleetId)

  for owner, fleets in state.fleetsByOwner:
    if owner notin actualFleetsByOwner:
      result.add("fleetsByOwner has extra owner: " & owner)
    elif fleets.sorted != actualFleetsByOwner[owner].sorted:
      result.add("fleetsByOwner mismatch for " & owner)

  for owner, fleets in actualFleetsByOwner:
    if owner notin state.fleetsByOwner:
      result.add("fleetsByOwner missing owner: " & owner)

  # Validate coloniesByOwner
  var actualColoniesByOwner = initTable[HouseId, seq[SystemId]]()
  for systemId, colony in state.colonies:
    if colony.owner notin actualColoniesByOwner:
      actualColoniesByOwner[colony.owner] = @[]
    actualColoniesByOwner[colony.owner].add(systemId)

  for owner, systems in state.coloniesByOwner:
    if owner notin actualColoniesByOwner:
      result.add("coloniesByOwner has extra owner: " & owner)
    elif systems.sorted != actualColoniesByOwner[owner].sorted:
      result.add("coloniesByOwner mismatch for " & owner)

  for owner, systems in actualColoniesByOwner:
    if owner notin state.coloniesByOwner:
      result.add("coloniesByOwner missing owner: " & owner)
