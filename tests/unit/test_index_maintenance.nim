## Index Maintenance Unit Tests
##
## Tests for reverse index operations and consistency validation
## Ensures O(1) lookup indices remain synchronized with game state

import std/[unittest, tables]
import ../../src/engine/gamestate
import ../../src/engine/index_maintenance
import ../../src/engine/ship
import ../../src/engine/squadron
import ../../src/engine/fleet
import ../../src/common/types/[core, units]

proc createTestGameState(): GameState =
  ## Create minimal GameState for testing index operations
  result = GameState()
  result.fleets = initTable[FleetId, Fleet]()
  result.colonies = initTable[SystemId, Colony]()
  result.fleetsByLocation = initTable[SystemId, seq[FleetId]]()
  result.fleetsByOwner = initTable[HouseId, seq[FleetId]]()
  result.coloniesByOwner = initTable[HouseId, seq[SystemId]]()

proc createTestFleet(id: FleetId, owner: HouseId,
                    location: SystemId): Fleet =
  ## Create minimal fleet for testing
  let destroyer = newShip(ShipClass.Destroyer)
  var squad = newSquadron(destroyer)
  result = newFleet(
    squadrons = @[squad],
    id = id,
    owner = owner,
    location = location
  )

suite "Fleet Index Maintenance":
  test "addFleetToIndices - single fleet":
    var state = createTestGameState()
    let fleetId: FleetId = "fleet-1"
    let owner: HouseId = "house-alpha"
    let location: SystemId = 42

    state.addFleetToIndices(fleetId, owner, location)

    check location in state.fleetsByLocation
    check state.fleetsByLocation[location] == @[fleetId]
    check owner in state.fleetsByOwner
    check state.fleetsByOwner[owner] == @[fleetId]

  test "addFleetToIndices - multiple fleets same location":
    var state = createTestGameState()
    let location: SystemId = 42
    let owner1: HouseId = "house-alpha"
    let owner2: HouseId = "house-beta"

    state.addFleetToIndices("fleet-1", owner1, location)
    state.addFleetToIndices("fleet-2", owner2, location)

    check state.fleetsByLocation[location].len == 2
    check "fleet-1" in state.fleetsByLocation[location]
    check "fleet-2" in state.fleetsByLocation[location]

  test "addFleetToIndices - multiple fleets same owner":
    var state = createTestGameState()
    let owner: HouseId = "house-alpha"

    state.addFleetToIndices("fleet-1", owner, 10.SystemId)
    state.addFleetToIndices("fleet-2", owner, 20.SystemId)
    state.addFleetToIndices("fleet-3", owner, 10.SystemId)

    check state.fleetsByOwner[owner].len == 3
    check "fleet-1" in state.fleetsByOwner[owner]
    check "fleet-2" in state.fleetsByOwner[owner]
    check "fleet-3" in state.fleetsByOwner[owner]

  test "removeFleetFromIndices - cleans up empty entries":
    var state = createTestGameState()
    let fleetId: FleetId = "fleet-1"
    let owner: HouseId = "house-alpha"
    let location: SystemId = 42

    # Add then remove
    state.addFleetToIndices(fleetId, owner, location)
    state.removeFleetFromIndices(fleetId, owner, location)

    # Tables should not contain empty entries
    check location notin state.fleetsByLocation
    check owner notin state.fleetsByOwner

  test "removeFleetFromIndices - preserves other fleets":
    var state = createTestGameState()
    let location: SystemId = 42
    let owner: HouseId = "house-alpha"

    state.addFleetToIndices("fleet-1", owner, location)
    state.addFleetToIndices("fleet-2", owner, location)

    # Remove only one
    state.removeFleetFromIndices("fleet-1", owner, location)

    check location in state.fleetsByLocation
    check state.fleetsByLocation[location] == @["fleet-2"]
    check owner in state.fleetsByOwner
    check state.fleetsByOwner[owner] == @["fleet-2"]

  test "removeFleetFromIndices - handles missing fleet gracefully":
    var state = createTestGameState()
    let fleetId: FleetId = "nonexistent-fleet"
    let owner: HouseId = "house-alpha"
    let location: SystemId = 42

    # Should not crash when removing non-existent fleet
    state.removeFleetFromIndices(fleetId, owner, location)

    # No entries should exist
    check location notin state.fleetsByLocation
    check owner notin state.fleetsByOwner

  test "updateFleetLocation - moves fleet between systems":
    var state = createTestGameState()
    let fleetId: FleetId = "fleet-1"
    let owner: HouseId = "house-alpha"
    let oldLoc: SystemId = 10
    let newLoc: SystemId = 20

    # Setup initial state
    state.addFleetToIndices(fleetId, owner, oldLoc)

    # Move fleet
    state.updateFleetLocation(fleetId, oldLoc, newLoc)

    # Should be at new location only
    check oldLoc notin state.fleetsByLocation
    check newLoc in state.fleetsByLocation
    check state.fleetsByLocation[newLoc] == @[fleetId]

  test "updateFleetLocation - no-op when locations identical":
    var state = createTestGameState()
    let fleetId: FleetId = "fleet-1"
    let owner: HouseId = "house-alpha"
    let location: SystemId = 42

    state.addFleetToIndices(fleetId, owner, location)

    # Move to same location
    state.updateFleetLocation(fleetId, location, location)

    # Should remain unchanged
    check state.fleetsByLocation[location] == @[fleetId]

  test "updateFleetLocation - preserves other fleets at old location":
    var state = createTestGameState()
    let owner: HouseId = "house-alpha"
    let oldLoc: SystemId = 10
    let newLoc: SystemId = 20

    state.addFleetToIndices("fleet-1", owner, oldLoc)
    state.addFleetToIndices("fleet-2", owner, oldLoc)

    # Move only fleet-1
    state.updateFleetLocation("fleet-1", oldLoc, newLoc)

    # fleet-2 should still be at old location
    check oldLoc in state.fleetsByLocation
    check state.fleetsByLocation[oldLoc] == @["fleet-2"]
    check state.fleetsByLocation[newLoc] == @["fleet-1"]

suite "Colony Index Maintenance":
  test "addColonyToIndices - single colony":
    var state = createTestGameState()
    let systemId: SystemId = 42
    let owner: HouseId = "house-alpha"

    state.addColonyToIndices(systemId, owner)

    check owner in state.coloniesByOwner
    check state.coloniesByOwner[owner] == @[systemId]

  test "addColonyToIndices - multiple colonies same owner":
    var state = createTestGameState()
    let owner: HouseId = "house-alpha"

    state.addColonyToIndices(10.SystemId, owner)
    state.addColonyToIndices(20.SystemId, owner)
    state.addColonyToIndices(30.SystemId, owner)

    check state.coloniesByOwner[owner].len == 3
    check 10.SystemId in state.coloniesByOwner[owner]
    check 20.SystemId in state.coloniesByOwner[owner]
    check 30.SystemId in state.coloniesByOwner[owner]

  test "removeColonyFromIndices - cleans up empty entries":
    var state = createTestGameState()
    let systemId: SystemId = 42
    let owner: HouseId = "house-alpha"

    # Add then remove
    state.addColonyToIndices(systemId, owner)
    state.removeColonyFromIndices(systemId, owner)

    # Table should not contain empty entry
    check owner notin state.coloniesByOwner

  test "removeColonyFromIndices - preserves other colonies":
    var state = createTestGameState()
    let owner: HouseId = "house-alpha"

    state.addColonyToIndices(10.SystemId, owner)
    state.addColonyToIndices(20.SystemId, owner)

    # Remove only one
    state.removeColonyFromIndices(10.SystemId, owner)

    check owner in state.coloniesByOwner
    check state.coloniesByOwner[owner] == @[20.SystemId]

  test "updateColonyOwner - transfers ownership":
    var state = createTestGameState()
    let systemId: SystemId = 42
    let oldOwner: HouseId = "house-alpha"
    let newOwner: HouseId = "house-beta"

    # Setup initial ownership
    state.addColonyToIndices(systemId, oldOwner)

    # Transfer ownership (conquest)
    state.updateColonyOwner(systemId, oldOwner, newOwner)

    # Should be owned by new owner only
    check oldOwner notin state.coloniesByOwner
    check newOwner in state.coloniesByOwner
    check state.coloniesByOwner[newOwner] == @[systemId]

  test "updateColonyOwner - preserves other colonies for old owner":
    var state = createTestGameState()
    let oldOwner: HouseId = "house-alpha"
    let newOwner: HouseId = "house-beta"

    state.addColonyToIndices(10.SystemId, oldOwner)
    state.addColonyToIndices(20.SystemId, oldOwner)

    # Transfer only one colony
    state.updateColonyOwner(10.SystemId, oldOwner, newOwner)

    # Old owner should still have other colony
    check oldOwner in state.coloniesByOwner
    check state.coloniesByOwner[oldOwner] == @[20.SystemId]
    check state.coloniesByOwner[newOwner] == @[10.SystemId]

suite "Index Initialization":
  test "initializeGameIndices - builds from empty state":
    var state = createTestGameState()

    state.initializeGameIndices()

    # Should have empty but initialized tables
    check state.fleetsByLocation.len == 0
    check state.fleetsByOwner.len == 0
    check state.coloniesByOwner.len == 0

  test "initializeGameIndices - builds from existing fleets":
    var state = createTestGameState()

    # Add fleets to state (not indices)
    let fleet1 = createTestFleet("fleet-1", "house-alpha", 10.SystemId)
    let fleet2 = createTestFleet("fleet-2", "house-alpha", 20.SystemId)
    let fleet3 = createTestFleet("fleet-3", "house-beta", 10.SystemId)

    state.fleets["fleet-1"] = fleet1
    state.fleets["fleet-2"] = fleet2
    state.fleets["fleet-3"] = fleet3

    # Build indices
    state.initializeGameIndices()

    # Verify location index
    check state.fleetsByLocation[10.SystemId].len == 2
    check "fleet-1" in state.fleetsByLocation[10.SystemId]
    check "fleet-3" in state.fleetsByLocation[10.SystemId]
    check state.fleetsByLocation[20.SystemId] == @["fleet-2"]

    # Verify owner index
    check state.fleetsByOwner["house-alpha"].len == 2
    check state.fleetsByOwner["house-beta"].len == 1

  test "initializeGameIndices - builds from existing colonies":
    var state = createTestGameState()

    # Add colonies to state (not indices)
    state.colonies[10.SystemId] = Colony(
      systemId: 10.SystemId,
      owner: "house-alpha",
      population: 100,
      infrastructure: 50
    )
    state.colonies[20.SystemId] = Colony(
      systemId: 20.SystemId,
      owner: "house-alpha",
      population: 100,
      infrastructure: 50
    )
    state.colonies[30.SystemId] = Colony(
      systemId: 30.SystemId,
      owner: "house-beta",
      population: 100,
      infrastructure: 50
    )

    # Build indices
    state.initializeGameIndices()

    # Verify colony index
    check state.coloniesByOwner["house-alpha"].len == 2
    check 10.SystemId in state.coloniesByOwner["house-alpha"]
    check 20.SystemId in state.coloniesByOwner["house-alpha"]
    check state.coloniesByOwner["house-beta"] == @[30.SystemId]

  test "initializeGameIndices - rebuilds stale indices":
    var state = createTestGameState()

    # Add fleets and manually create wrong indices
    let fleet1 = createTestFleet("fleet-1", "house-alpha", 10.SystemId)
    state.fleets["fleet-1"] = fleet1
    state.fleetsByLocation[99.SystemId] = @["nonexistent-fleet"]
    state.fleetsByOwner["house-wrong"] = @["fleet-1"]

    # Rebuild from scratch
    state.initializeGameIndices()

    # Should have correct indices now
    check 99.SystemId notin state.fleetsByLocation
    check "house-wrong" notin state.fleetsByOwner
    check state.fleetsByLocation[10.SystemId] == @["fleet-1"]
    check state.fleetsByOwner["house-alpha"] == @["fleet-1"]

suite "Index Validation":
  test "validateIndices - empty state is valid":
    var state = createTestGameState()
    state.initializeGameIndices()

    let errors = state.validateIndices()

    check errors.len == 0

  test "validateIndices - correctly indexed state is valid":
    var state = createTestGameState()

    # Add fleet with proper indexing
    let fleet = createTestFleet("fleet-1", "house-alpha", 42.SystemId)
    state.fleets["fleet-1"] = fleet
    state.addFleetToIndices("fleet-1", "house-alpha", 42.SystemId)

    let errors = state.validateIndices()

    check errors.len == 0

  test "validateIndices - detects missing location index":
    var state = createTestGameState()

    # Add fleet but skip location index
    let fleet = createTestFleet("fleet-1", "house-alpha", 42.SystemId)
    state.fleets["fleet-1"] = fleet
    state.fleetsByOwner["house-alpha"] = @["fleet-1"]
    # Intentionally skip: state.fleetsByLocation[42.SystemId] = @["fleet-1"]

    let errors = state.validateIndices()

    check errors.len > 0
    check "fleetsByLocation missing location: 42" in errors

  test "validateIndices - detects missing owner index":
    var state = createTestGameState()

    # Add fleet but skip owner index
    let fleet = createTestFleet("fleet-1", "house-alpha", 42.SystemId)
    state.fleets["fleet-1"] = fleet
    state.fleetsByLocation[42.SystemId] = @["fleet-1"]
    # Intentionally skip: state.fleetsByOwner["house-alpha"] = @["fleet-1"]

    let errors = state.validateIndices()

    check errors.len > 0
    check "fleetsByOwner missing owner: house-alpha" in errors

  test "validateIndices - detects extra location index":
    var state = createTestGameState()
    state.initializeGameIndices()

    # Add orphaned index entry
    state.fleetsByLocation[99.SystemId] = @["nonexistent-fleet"]

    let errors = state.validateIndices()

    check errors.len > 0
    check "fleetsByLocation has extra location: 99" in errors

  test "validateIndices - detects mismatched colony ownership":
    var state = createTestGameState()

    # Add colony with wrong index
    state.colonies[42.SystemId] = Colony(
      systemId: 42.SystemId,
      owner: "house-alpha",
      population: 100,
      infrastructure: 50
    )
    state.coloniesByOwner["house-beta"] = @[42.SystemId]  # Wrong owner!

    let errors = state.validateIndices()

    check errors.len > 0
    # Should report both missing correct owner and extra wrong owner
    check errors.len >= 2

when isMainModule:
  echo "Running index maintenance tests..."
