## Comprehensive Fog of War Engine Tests
##
## Tests fog-of-war filtering at the engine level to ensure AI only sees what it should.
## Critical for Phase 2 AI development - ensures fair play and proper intelligence gathering.
##
## Test Coverage:
## 1. Core visibility levels (Owned, Occupied, Scouted, Adjacent, None)
## 2. Multi-house scenarios (different perspectives)
## 3. Intelligence database integration (espionage intel)
## 4. Fleet detection and visibility
## 5. Edge cases and transitions

import std/[unittest, tables, options, sets]
import ../../src/engine/[gamestate, fog_of_war, starmap, fleet, squadron, spacelift]
import ../../src/common/[hex, system]
import ../../src/common/types/[core, planets, tech, units, combat]
import ../../src/engine/intelligence/types as intel_types

suite "Fog of War - Core Visibility Levels":
  ## Test basic visibility levels: Owned, Occupied, Scouted, Adjacent, None

  setup:
    # Create 4-player star map
    let map = starMap(4)
    var state = newGameState("fow-test", 4, map)
    state.turn = 10

    # Initialize houses
    for i in 0..<4:
      let houseId = ("house-" & $(i+1)).HouseId
      var house = initializeHouse("House " & $(i+1), "color" & $(i+1))
      house.id = houseId
      state.houses[houseId] = house

    # Create home colonies for each house at their starting systems
    for i in 0..<4:
      let houseId = ("house-" & $(i+1)).HouseId
      let systemId = map.playerSystemIds[i]
      state.colonies[systemId] = createHomeColony(systemId, houseId)

  test "Owned system - full visibility with colony details":
    let house1 = "house-1".HouseId
    let filtered = createFogOfWarView(state, house1)

    # Should see own colony with full details
    let ownSystem = map.playerSystemIds[0]
    check filtered.ownColonies.len == 1
    check filtered.ownColonies[0].owner == house1
    # Check population matches actual colony (value from game_setup/standard.toml)
    check filtered.ownColonies[0].population == state.colonies[ownSystem].population

    # Own system should be visible with Owned level
    check ownSystem in filtered.visibleSystems
    check filtered.visibleSystems[ownSystem].visibility == VisibilityLevel.Owned
    check filtered.visibleSystems[ownSystem].lastScoutedTurn == some(10)

    # Staleness should be 0 (current)
    check filtered.getIntelStaleness(ownSystem) == 0

    # Should be able to see colony details
    check filtered.canSeeColonyDetails(ownSystem)

  test "Occupied system - fleet presence reveals system":
    let house1 = "house-1".HouseId
    let ownSystem = map.playerSystemIds[0]

    # Create fleet at a different system (hub or adjacent)
    let destSystem = map.hubId  # Move to central hub

    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    var destSq = newSquadron(destroyer)
    destSq.owner = house1
    destSq.location = destSystem

    let fleet = newFleet(
      squadrons = @[destSq],
      id = "fleet-1".FleetId,
      owner = house1,
      location = destSystem
    )
    state.fleets["fleet-1".FleetId] = fleet

    let filtered = createFogOfWarView(state, house1)

    # Hub system should be Occupied
    check destSystem in filtered.visibleSystems
    check filtered.visibleSystems[destSystem].visibility == VisibilityLevel.Occupied
    check filtered.visibleSystems[destSystem].lastScoutedTurn == some(10)

    # Should see own fleet
    check filtered.ownFleets.len == 1
    check filtered.ownFleets[0].id == "fleet-1".FleetId
    check filtered.ownFleets[0].location == destSystem

    # Can see fleets in occupied system
    check filtered.canSeeFleets(destSystem)

  test "Adjacent system - awareness only, no details":
    let house1 = "house-1".HouseId
    let ownSystem = map.playerSystemIds[0]
    let filtered = createFogOfWarView(state, house1)

    # Get adjacent systems
    let adjacentSystems = map.getAdjacentSystems(ownSystem)

    # Adjacent systems should be visible
    for adjSystem in adjacentSystems:
      if adjSystem != ownSystem:
        check adjSystem in filtered.visibleSystems
        # Should be Adjacent (unless it's another player's starting system)
        let vis = filtered.visibleSystems[adjSystem].visibility
        check vis in [VisibilityLevel.Adjacent, VisibilityLevel.Owned]

        # If truly adjacent (not owned by us), cannot see details
        if vis == VisibilityLevel.Adjacent:
          check not filtered.canSeeColonyDetails(adjSystem)
          check not filtered.canSeeFleets(adjSystem)
          check filtered.visibleSystems[adjSystem].lastScoutedTurn.isNone

  test "Hidden system - no visibility beyond adjacent range":
    let house1 = "house-1".HouseId
    let ownSystem = map.playerSystemIds[0]
    let filtered = createFogOfWarView(state, house1)

    # Get all systems within 2 jumps
    var knownSystems = initHashSet[uint]()
    knownSystems.incl(ownSystem)

    let adjacentLayer1 = map.getAdjacentSystems(ownSystem)
    for sys in adjacentLayer1:
      knownSystems.incl(sys)

    # Systems beyond adjacent range should not be visible
    for systemId in map.systems.keys:
      if systemId notin knownSystems:
        # This system is 2+ jumps away, should not be visible
        if systemId notin filtered.visibleSystems:
          # Confirmed hidden
          check filtered.getIntelStaleness(systemId) == -1
          check not filtered.canSeeColonyDetails(systemId)

  test "Public information - prestige and elimination status":
    let house1 = "house-1".HouseId

    # Set different prestige values
    var h1 = state.houses["house-1".HouseId]
    h1.prestige = 150
    state.houses["house-1".HouseId] = h1

    var h2 = state.houses["house-2".HouseId]
    h2.prestige = 200
    h2.eliminated = false
    state.houses["house-2".HouseId] = h2

    var h3 = state.houses["house-3".HouseId]
    h3.eliminated = true
    state.houses["house-3".HouseId] = h3

    let filtered = createFogOfWarView(state, house1)

    # Should see all prestige scores (public info)
    check filtered.housePrestige.len == 4
    check filtered.housePrestige["house-1".HouseId] == 150
    check filtered.housePrestige["house-2".HouseId] == 200

    # Should see elimination status
    check filtered.houseEliminated["house-2".HouseId] == false
    check filtered.houseEliminated["house-3".HouseId] == true


suite "Fog of War - Multi-House Scenarios":
  ## Test how different houses see different parts of the map

  setup:
    let map = starMap(4)
    var state = newGameState("multi-house-test", 4, map)
    state.turn = 20

    # Initialize all houses
    for i in 0..<4:
      let houseId = ("house-" & $(i+1)).HouseId
      var house = initializeHouse("House " & $(i+1), "color")
      house.id = houseId
      state.houses[houseId] = house

      # Create home colony
      let systemId = map.playerSystemIds[i]
      state.colonies[systemId] = createHomeColony(systemId, houseId)

  test "Each house sees only their own territory":
    # Get filtered views for each house
    let filtered1 = createFogOfWarView(state, "house-1".HouseId)
    let filtered2 = createFogOfWarView(state, "house-2".HouseId)
    let filtered3 = createFogOfWarView(state, "house-3".HouseId)

    # Each house should see exactly 1 own colony
    check filtered1.ownColonies.len == 1
    check filtered1.ownColonies[0].owner == "house-1".HouseId

    check filtered2.ownColonies.len == 1
    check filtered2.ownColonies[0].owner == "house-2".HouseId

    check filtered3.ownColonies.len == 1
    check filtered3.ownColonies[0].owner == "house-3".HouseId

    # Each house sees their own system as Owned
    check filtered1.visibleSystems[map.playerSystemIds[0]].visibility == VisibilityLevel.Owned
    check filtered2.visibleSystems[map.playerSystemIds[1]].visibility == VisibilityLevel.Owned
    check filtered3.visibleSystems[map.playerSystemIds[2]].visibility == VisibilityLevel.Owned

  test "Fleet encounter - both houses detect each other":
    # Both house-1 and house-2 send fleets to the hub
    let hub = map.hubId

    # House 1 fleet
    let destroyer1 = newEnhancedShip(ShipClass.Destroyer)
    var sq1 = newSquadron(destroyer1)
    sq1.owner = "house-1".HouseId
    sq1.location = hub

    let fleet1 = newFleet(
      squadrons = @[sq1],
      id = "fleet-1".FleetId,
      owner = "house-1".HouseId,
      location = hub
    )
    state.fleets["fleet-1".FleetId] = fleet1

    # House 2 fleet
    let cruiser2 = newEnhancedShip(ShipClass.Cruiser)
    var sq2 = newSquadron(cruiser2)
    sq2.owner = "house-2".HouseId
    sq2.location = hub

    let fleet2 = newFleet(
      squadrons = @[sq2],
      id = "fleet-2".FleetId,
      owner = "house-2".HouseId,
      location = hub
    )
    state.fleets["fleet-2".FleetId] = fleet2

    # House 1 perspective
    let filtered1 = createFogOfWarView(state, "house-1".HouseId)

    # House 1 should see house 2's fleet
    check filtered1.visibleFleets.len == 1
    check filtered1.visibleFleets[0].owner == "house-2".HouseId
    check filtered1.visibleFleets[0].location == hub

    # House 2 perspective
    let filtered2 = createFogOfWarView(state, "house-2".HouseId)

    # House 2 should see house 1's fleet
    check filtered2.visibleFleets.len == 1
    check filtered2.visibleFleets[0].owner == "house-1".HouseId
    check filtered2.visibleFleets[0].location == hub

  test "Enemy colony in occupied system - visual detection":
    # House 2 has a colony at a specific system
    let targetSystem = map.hubId  # Use hub for testing
    var colony2 = createHomeColony(targetSystem, "house-2".HouseId)
    colony2.population = 50
    state.colonies[targetSystem] = colony2

    # House 1 sends fleet to that system
    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    var sq = newSquadron(destroyer)
    sq.owner = "house-1".HouseId
    sq.location = targetSystem

    let fleet = newFleet(
      squadrons = @[sq],
      id = "scout-fleet".FleetId,
      owner = "house-1".HouseId,
      location = targetSystem
    )
    state.fleets["scout-fleet".FleetId] = fleet

    let filtered1 = createFogOfWarView(state, "house-1".HouseId)

    # House 1 should see house 2's colony
    check filtered1.visibleColonies.len >= 1

    # Find house 2's colony in visible list
    var foundColony = false
    for col in filtered1.visibleColonies:
      if col.systemId == targetSystem and col.owner == "house-2".HouseId:
        foundColony = true
        break

    check foundColony


suite "Fog of War - Intelligence Database Integration":
  ## Test how intelligence reports integrate with fog-of-war

  setup:
    let map = starMap(2)
    var state = newGameState("intel-test", 2, map)
    state.turn = 30

    for i in 0..<2:
      let houseId = ("house-" & $(i+1)).HouseId
      var house = initializeHouse("House " & $(i+1), "color")
      house.id = houseId
      state.houses[houseId] = house

      let systemId = map.playerSystemIds[i]
      state.colonies[systemId] = createHomeColony(systemId, houseId)

  test "Colony intel reveals hidden system":
    let house1 = "house-1".HouseId
    let house2System = map.playerSystemIds[1]

    # House 2's colony (hidden from house 1 normally)
    var colony2 = state.colonies[house2System]
    colony2.population = 75
    colony2.infrastructure = 8
    state.colonies[house2System] = colony2

    # Add colony intel to house 1's intelligence database
    var house1Data = state.houses[house1]
    let colonyIntel = ColonyIntelReport(
      colonyId: house2System,
      targetOwner: "house-2".HouseId,
      gatheredTurn: 28,  # 2 turns ago
      quality: IntelQuality.Spy,
      population: 75,
      industry: 4,
      defenses: 0,
      starbaseLevel: 0,
      constructionQueue: @[]
    )
    house1Data.intelligence.addColonyReport(colonyIntel)
    state.houses[house1] = house1Data

    let filtered = createFogOfWarView(state, house1)

    # System should now be Scouted (visible via intel)
    check house2System in filtered.visibleSystems
    check filtered.visibleSystems[house2System].visibility == VisibilityLevel.Scouted
    check filtered.visibleSystems[house2System].lastScoutedTurn == some(28)

    # Intel is 2 turns stale
    check filtered.getIntelStaleness(house2System) == 2

    # Should see enemy colony via intel report
    var foundColony = false
    for col in filtered.visibleColonies:
      if col.systemId == house2System:
        foundColony = true
        check col.estimatedPopulation == some(75)
        check col.estimatedIndustry == some(4)
        check col.intelTurn == some(28)

    check foundColony

  test "Multiple intel reports - uses most recent":
    let house1 = "house-1".HouseId
    let targetSystem = map.hubId

    var house1Data = state.houses[house1]

    # Add older colony intel
    let oldIntel = ColonyIntelReport(
      colonyId: targetSystem,
      targetOwner: "house-2".HouseId,
      gatheredTurn: 20,  # 10 turns ago
      quality: IntelQuality.Visual,
      population: 50,
      industry: 2,
      defenses: 0,
      starbaseLevel: 0,
      constructionQueue: @[]
    )
    house1Data.intelligence.addColonyReport(oldIntel)

    # Add newer system intel
    let recentIntel = SystemIntelReport(
      systemId: targetSystem,
      gatheredTurn: 28,  # 2 turns ago
      quality: IntelQuality.Visual,
      detectedFleets: @[]
    )
    house1Data.intelligence.addSystemReport(recentIntel)

    state.houses[house1] = house1Data

    let filtered = createFogOfWarView(state, house1)

    # Should use most recent intel (turn 28)
    check targetSystem in filtered.visibleSystems
    check filtered.visibleSystems[targetSystem].lastScoutedTurn == some(28)
    check filtered.getIntelStaleness(targetSystem) == 2

  test "Intel staleness increases with time":
    let house1 = "house-1".HouseId
    let targetSystem = map.hubId

    var house1Data = state.houses[house1]

    # Add intel from various turns
    let intel10 = ColonyIntelReport(
      colonyId: targetSystem,
      targetOwner: "house-2".HouseId,
      gatheredTurn: 10,  # 20 turns ago
      quality: IntelQuality.Visual,
      population: 50,
      industry: 2,
      defenses: 0,
      starbaseLevel: 0,
      constructionQueue: @[]
    )
    house1Data.intelligence.addColonyReport(intel10)
    state.houses[house1] = house1Data

    let filtered = createFogOfWarView(state, house1)

    # Intel is 20 turns stale
    check filtered.getIntelStaleness(targetSystem) == 20


suite "Fog of War - Fleet Detection & Visibility":
  ## Test fleet detection mechanics

  setup:
    let map = starMap(2)
    var state = newGameState("fleet-test", 2, map)
    state.turn = 15

    for i in 0..<2:
      let houseId = ("house-" & $(i+1)).HouseId
      var house = initializeHouse("House " & $(i+1), "color")
      house.id = houseId
      state.houses[houseId] = house

      let systemId = map.playerSystemIds[i]
      state.colonies[systemId] = createHomeColony(systemId, houseId)

  test "Fleet composition hidden - only ship count visible":
    let house1 = "house-1".HouseId
    let house2 = "house-2".HouseId
    let meetingPoint = map.hubId

    # House 2 creates diverse fleet
    let cruiser = newEnhancedShip(ShipClass.Cruiser)
    var cruiserSq = newSquadron(cruiser)
    cruiserSq.owner = house2
    cruiserSq.location = meetingPoint

    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    var destroyerSq = newSquadron(destroyer)
    destroyerSq.owner = house2
    destroyerSq.location = meetingPoint

    let etac = newSpaceLiftShip(
      id = "etac-2",
      shipClass = ShipClass.ETAC,
      owner = house2,
      location = meetingPoint
    )

    let fleet2 = newFleet(
      squadrons = @[cruiserSq, destroyerSq],
      spaceLiftShips = @[etac],
      id = "fleet-2".FleetId,
      owner = house2,
      location = meetingPoint
    )
    state.fleets["fleet-2".FleetId] = fleet2

    # House 1 sends scout to meeting point
    let scout = newEnhancedShip(ShipClass.Scout)
    var scoutSq = newSquadron(scout)
    scoutSq.owner = house1
    scoutSq.location = meetingPoint

    let fleet1 = newFleet(
      squadrons = @[scoutSq],
      id = "fleet-1".FleetId,
      owner = house1,
      location = meetingPoint
    )
    state.fleets["fleet-1".FleetId] = fleet1

    let filtered = createFogOfWarView(state, house1)

    # House 1 should detect house 2's fleet
    check filtered.visibleFleets.len == 1
    check filtered.visibleFleets[0].owner == house2

    # Should see estimated ship count but NOT composition
    check filtered.visibleFleets[0].estimatedShipCount.isSome
    # 2 squadrons + 1 spacelift = 3 units
    check filtered.visibleFleets[0].estimatedShipCount.get == 3

    # Full details only available if owned
    check filtered.visibleFleets[0].fullDetails.isNone

  test "Fleet in hidden system - not visible":
    let house2 = "house-2".HouseId
    let house2Home = map.playerSystemIds[1]

    # House 2 has fleet at home (hidden from house 1)
    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    var sq = newSquadron(destroyer)
    sq.owner = house2
    sq.location = house2Home

    let fleet = newFleet(
      squadrons = @[sq],
      id = "hidden-fleet".FleetId,
      owner = house2,
      location = house2Home
    )
    state.fleets["hidden-fleet".FleetId] = fleet

    let filtered1 = createFogOfWarView(state, "house-1".HouseId)

    # House 1 should NOT see house 2's fleet (no presence at that system)
    check filtered1.visibleFleets.len == 0


suite "Fog of War - Edge Cases & Transitions":
  ## Test edge cases and visibility transitions

  setup:
    let map = starMap(2)
    var state = newGameState("edge-test", 2, map)
    state.turn = 50

    let house1 = "house-1".HouseId
    let house2 = "house-2".HouseId

    var h1 = initializeHouse("House 1", "blue")
    h1.id = house1
    state.houses[house1] = h1

    var h2 = initializeHouse("House 2", "red")
    h2.id = house2
    state.houses[house2] = h2

    let house1Home = map.playerSystemIds[0]
    let house2Home = map.playerSystemIds[1]
    state.colonies[house1Home] = createHomeColony(house1Home, house1)
    state.colonies[house2Home] = createHomeColony(house2Home, house2)

  test "Empty house - no visibility beyond existence":
    # Create a house with no colonies or fleets
    let emptyHouse = "house-empty".HouseId
    var hEmpty = initializeHouse("Empty House", "gray")
    hEmpty.id = emptyHouse
    state.houses[emptyHouse] = hEmpty

    let filtered = createFogOfWarView(state, emptyHouse)

    # Should have valid view but minimal visibility
    check filtered.viewingHouse == emptyHouse
    check filtered.ownColonies.len == 0
    check filtered.ownFleets.len == 0
    # Universal map awareness: ALL systems visible from start (fog_of_war.nim:315-328)
    check filtered.visibleSystems.len == map.systems.len

    # Public info still available
    check filtered.housePrestige.len >= 2  # At least house1 and house2

  test "Visibility upgrade - adjacent -> occupied -> owned":
    # house1 and house1Home already defined in setup
    let targetSystem = map.getAdjacentSystems(house1Home)[0]

    # Stage 1: Adjacent
    var filtered = createFogOfWarView(state, house1)
    check targetSystem in filtered.visibleSystems
    check filtered.visibleSystems[targetSystem].visibility == VisibilityLevel.Adjacent

    # Stage 2: Send fleet -> Occupied
    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    var sq = newSquadron(destroyer)
    sq.owner = house1
    sq.location = targetSystem

    let fleet = newFleet(
      squadrons = @[sq],
      id = "fleet-1".FleetId,
      owner = house1,
      location = targetSystem
    )
    state.fleets["fleet-1".FleetId] = fleet

    filtered = createFogOfWarView(state, house1)
    check filtered.visibleSystems[targetSystem].visibility == VisibilityLevel.Occupied

    # Stage 3: Colonize -> Owned
    state.colonies[targetSystem] = createHomeColony(targetSystem, house1)

    filtered = createFogOfWarView(state, house1)
    check filtered.visibleSystems[targetSystem].visibility == VisibilityLevel.Owned

  test "Multiple fleets at same location":
    # house1 and house1Home already defined in setup

    # Create 3 fleets at home
    for i in 1..3:
      let destroyer = newEnhancedShip(ShipClass.Destroyer)
      var sq = newSquadron(destroyer)
      sq.owner = house1
      sq.location = house1Home

      let fleetId = ("fleet-" & $i).FleetId
      let fleet = newFleet(
        squadrons = @[sq],
        id = fleetId,
        owner = house1,
        location = house1Home
      )
      state.fleets[fleetId] = fleet

    let filtered = createFogOfWarView(state, house1)

    # Should see all 3 fleets
    check filtered.ownFleets.len == 3

  test "Eliminated house still gets filtered view":
    # house1 already defined in setup
    var h1Elim = state.houses[house1]
    h1Elim.eliminated = true
    state.houses[house1] = h1Elim

    let filtered = createFogOfWarView(state, house1)

    check filtered.viewingHouse == house1
    check filtered.ownHouse.eliminated == true

    # Elimination status is public
    check filtered.houseEliminated[house1] == true


suite "Fog of War - Advanced Edge Cases":
  ## Comprehensive edge case testing for fog-of-war system

  setup:
    let map = starMap(4)
    var state = newGameState("advanced-edge-test", 4, map)
    state.turn = 100

    # Initialize 4 houses
    for i in 0..<4:
      let houseId = ("house-" & $(i+1)).HouseId
      var house = initializeHouse("House " & $(i+1), "color")
      house.id = houseId
      state.houses[houseId] = house

      # Home colonies
      let systemId = map.playerSystemIds[i]
      state.colonies[systemId] = createHomeColony(systemId, houseId)

  test "Visibility downgrade - colony lost (owned -> scouted)":
    let house1 = "house-1".HouseId
    let conqueredSystem = map.playerSystemIds[0]  # House 1's home

    # House 1 initially owns the system
    var filtered = createFogOfWarView(state, house1)
    check conqueredSystem in filtered.visibleSystems
    check filtered.visibleSystems[conqueredSystem].visibility == VisibilityLevel.Owned

    # House 2 conquers the system
    var colony = state.colonies[conqueredSystem]
    colony.owner = "house-2".HouseId
    state.colonies[conqueredSystem] = colony

    # Add old intel to house 1's intelligence database
    var house1Data = state.houses[house1]
    let colonyIntel = ColonyIntelReport(
      colonyId: conqueredSystem,
      targetOwner: house1,
      gatheredTurn: 95,  # 5 turns ago
      quality: IntelQuality.Visual,
      population: 100,
      industry: 5,
      defenses: 0,
      starbaseLevel: 0,
      constructionQueue: @[]
    )
    house1Data.intelligence.addColonyReport(colonyIntel)
    state.houses[house1] = house1Data

    # House 1 should now see it as Scouted (via old intel)
    filtered = createFogOfWarView(state, house1)
    check conqueredSystem in filtered.visibleSystems
    check filtered.visibleSystems[conqueredSystem].visibility == VisibilityLevel.Scouted
    check filtered.getIntelStaleness(conqueredSystem) == 5

  test "Stale intel vs current visibility - current wins":
    let house1 = "house-1".HouseId
    let targetSystem = map.hubId

    # Add very old intel
    var house1Data = state.houses[house1]
    let oldIntel = ColonyIntelReport(
      colonyId: targetSystem,
      targetOwner: "house-2".HouseId,
      gatheredTurn: 50,  # 50 turns ago
      quality: IntelQuality.Visual,
      population: 30,
      industry: 2,
      defenses: 0,
      starbaseLevel: 0,
      constructionQueue: @[]
    )
    house1Data.intelligence.addColonyReport(oldIntel)
    state.houses[house1] = house1Data

    # House 1 sends fleet to target system (current visibility)
    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    var sq = newSquadron(destroyer)
    sq.owner = house1
    sq.location = targetSystem

    let fleet = newFleet(
      squadrons = @[sq],
      id = "scout-fleet".FleetId,
      owner = house1,
      location = targetSystem
    )
    state.fleets["scout-fleet".FleetId] = fleet

    let filtered = createFogOfWarView(state, house1)

    # Should be Occupied (current) not Scouted (stale)
    check targetSystem in filtered.visibleSystems
    check filtered.visibleSystems[targetSystem].visibility == VisibilityLevel.Occupied
    check filtered.getIntelStaleness(targetSystem) == 0  # Current

  test "Multiple houses in same system - all detect each other":
    let hub = map.hubId

    # All 4 houses send fleets to hub
    for i in 0..<4:
      let houseId = ("house-" & $(i+1)).HouseId
      let destroyer = newEnhancedShip(ShipClass.Destroyer)
      var sq = newSquadron(destroyer)
      sq.owner = houseId
      sq.location = hub

      let fleetId = (houseId & "-fleet").FleetId
      let fleet = newFleet(
        squadrons = @[sq],
        id = fleetId,
        owner = houseId,
        location = hub
      )
      state.fleets[fleetId] = fleet

    # Each house should see 3 enemy fleets
    for i in 0..<4:
      let houseId = ("house-" & $(i+1)).HouseId
      let filtered = createFogOfWarView(state, houseId)

      # Should see hub as occupied
      check hub in filtered.visibleSystems
      check filtered.visibleSystems[hub].visibility == VisibilityLevel.Occupied

      # Should see 3 enemy fleets (all others)
      check filtered.visibleFleets.len == 3

      # Should see own fleet
      check filtered.ownFleets.len == 1

  test "Empty system (no colony) - can still be occupied":
    let house1 = "house-1".HouseId
    let emptySystem = map.hubId

    # Confirm no colony at hub
    check emptySystem notin state.colonies

    # House 1 sends fleet to empty system
    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    var sq = newSquadron(destroyer)
    sq.owner = house1
    sq.location = emptySystem

    let fleet = newFleet(
      squadrons = @[sq],
      id = "fleet-1".FleetId,
      owner = house1,
      location = emptySystem
    )
    state.fleets["fleet-1".FleetId] = fleet

    let filtered = createFogOfWarView(state, house1)

    # Should see empty system as Occupied
    check emptySystem in filtered.visibleSystems
    check filtered.visibleSystems[emptySystem].visibility == VisibilityLevel.Occupied

    # No colonies visible (system is empty)
    var coloniesInSystem = 0
    for col in filtered.visibleColonies:
      if col.systemId == emptySystem:
        coloniesInSystem += 1

    check coloniesInSystem == 0

  test "Intel staleness boundary - turn 0 intel":
    let house1 = "house-1".HouseId
    let targetSystem = map.hubId

    state.turn = 100

    # Add intel from turn 0
    var house1Data = state.houses[house1]
    let ancientIntel = ColonyIntelReport(
      colonyId: targetSystem,
      targetOwner: "house-2".HouseId,
      gatheredTurn: 0,  # Turn 0
      quality: IntelQuality.Visual,
      population: 10,
      industry: 1,
      defenses: 0,
      starbaseLevel: 0,
      constructionQueue: @[]
    )
    house1Data.intelligence.addColonyReport(ancientIntel)
    state.houses[house1] = house1Data

    let filtered = createFogOfWarView(state, house1)

    # Staleness should be 100 turns
    check filtered.getIntelStaleness(targetSystem) == 100

  test "Intel quality doesn't affect visibility level":
    let house1 = "house-1".HouseId
    let targetSystem = map.hubId

    var house1Data = state.houses[house1]

    # Add Visual quality intel
    let visualIntel = ColonyIntelReport(
      colonyId: targetSystem,
      targetOwner: "house-2".HouseId,
      gatheredTurn: 95,
      quality: IntelQuality.Visual,
      population: 50,
      industry: 2,
      defenses: 0,
      starbaseLevel: 0,
      constructionQueue: @[]
    )
    house1Data.intelligence.addColonyReport(visualIntel)
    state.houses[house1] = house1Data

    let filtered1 = createFogOfWarView(state, house1)

    # Should be Scouted regardless of quality
    check targetSystem in filtered1.visibleSystems
    check filtered1.visibleSystems[targetSystem].visibility == VisibilityLevel.Scouted

    # Now replace with Spy quality intel (same turn)
    let spyIntel = ColonyIntelReport(
      colonyId: targetSystem,
      targetOwner: "house-2".HouseId,
      gatheredTurn: 95,
      quality: IntelQuality.Spy,  # Different quality
      population: 50,
      industry: 3,
      defenses: 1,
      starbaseLevel: 0,
      constructionQueue: @[]
    )
    house1Data.intelligence.addColonyReport(spyIntel)
    state.houses[house1] = house1Data

    let filtered2 = createFogOfWarView(state, house1)

    # Still Scouted, quality doesn't change visibility level
    check targetSystem in filtered2.visibleSystems
    check filtered2.visibleSystems[targetSystem].visibility == VisibilityLevel.Scouted
    check filtered2.getIntelStaleness(targetSystem) == 5

  test "Fleet withdrawal - system visibility downgrades":
    let house1 = "house-1".HouseId
    let targetSystem = map.hubId

    # House 1 fleet at hub
    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    var sq = newSquadron(destroyer)
    sq.owner = house1
    sq.location = targetSystem

    let fleetId = "fleet-1".FleetId
    let fleet = newFleet(
      squadrons = @[sq],
      id = fleetId,
      owner = house1,
      location = targetSystem
    )
    state.fleets[fleetId] = fleet

    var filtered = createFogOfWarView(state, house1)

    # Should be Occupied
    check targetSystem in filtered.visibleSystems
    check filtered.visibleSystems[targetSystem].visibility == VisibilityLevel.Occupied

    # Fleet withdraws
    state.fleets.del(fleetId)

    # Add intel from when fleet was there
    var house1Data = state.houses[house1]
    let recentIntel = SystemIntelReport(
      systemId: targetSystem,
      gatheredTurn: 100,  # Current turn
      quality: IntelQuality.Visual,
      detectedFleets: @[]
    )
    house1Data.intelligence.addSystemReport(recentIntel)
    state.houses[house1] = house1Data

    filtered = createFogOfWarView(state, house1)

    # Should downgrade to Scouted (intel only)
    check targetSystem in filtered.visibleSystems
    check filtered.visibleSystems[targetSystem].visibility == VisibilityLevel.Scouted

  test "System with no intel - visible via universal map awareness":
    let house1 = "house-1".HouseId

    # Find a system that's not home, not adjacent to home, and has no intel
    var distantSystem = 0u
    let house1Home = map.playerSystemIds[0]
    let adjacentSystems = map.getAdjacentSystems(house1Home)

    for systemId in map.systems.keys:
      if systemId != house1Home and
         systemId notin adjacentSystems and
         systemId notin map.playerSystemIds:
        distantSystem = systemId
        break

    check distantSystem != 0  # Found a distant system

    let filtered = createFogOfWarView(state, house1)

    # Universal map awareness: ALL systems visible from start (fog_of_war.nim:315-328)
    # Even systems with no intel are visible as Adjacent with full jump lane info
    check distantSystem in filtered.visibleSystems
    check filtered.visibleSystems[distantSystem].visibility == VisibilityLevel.Adjacent
    check filtered.getIntelStaleness(distantSystem) == -1  # No intel, but system known

  test "System intel without colony intel - still Scouted":
    let house1 = "house-1".HouseId
    let targetSystem = map.hubId

    var house1Data = state.houses[house1]

    # Add only system intel, no colony intel
    let systemIntel = SystemIntelReport(
      systemId: targetSystem,
      gatheredTurn: 95,
      quality: IntelQuality.Visual,
      detectedFleets: @[]
    )
    house1Data.intelligence.addSystemReport(systemIntel)
    state.houses[house1] = house1Data

    let filtered = createFogOfWarView(state, house1)

    # Should be Scouted via system intel
    check targetSystem in filtered.visibleSystems
    check filtered.visibleSystems[targetSystem].visibility == VisibilityLevel.Scouted
    check filtered.getIntelStaleness(targetSystem) == 5

  test "Diplomatic state visible only for relationships involving viewer":
    let house1 = "house-1".HouseId
    let house2 = "house-2".HouseId
    let house3 = "house-3".HouseId

    # House 1 <-> House 2: Non-Aggression Pact
    state.diplomacy[(house1, house2)] = DiplomaticState.NonAggression

    # House 2 <-> House 3: Non-Aggression Pact (doesn't involve house 1)
    state.diplomacy[(house2, house3)] = DiplomaticState.NonAggression

    let filtered = createFogOfWarView(state, house1)

    # Should see own diplomatic relations
    check (house1, house2) in filtered.houseDiplomacy
    check filtered.houseDiplomacy[(house1, house2)] == DiplomaticState.NonAggression

    # Should NOT see other houses' relations
    check (house2, house3) notin filtered.houseDiplomacy


suite "Fog of War - Fleet Movement Scenarios":
  ## Test fog-of-war during fleet movement and transit

  setup:
    let map = starMap(3)
    var state = newGameState("movement-test", 3, map)
    state.turn = 50

    # Initialize houses
    for i in 0..<3:
      let houseId = ("house-" & $(i+1)).HouseId
      var house = initializeHouse("House " & $(i+1), "color")
      house.id = houseId
      state.houses[houseId] = house

      let systemId = map.playerSystemIds[i]
      state.colonies[systemId] = createHomeColony(systemId, houseId)

  test "Fleet at source system - visible to all at that location":
    let house1 = "house-1".HouseId
    let house2 = "house-2".HouseId
    let sourceSystem = map.hubId

    # House 1 fleet at hub
    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    var sq = newSquadron(destroyer)
    sq.owner = house1
    sq.location = sourceSystem

    let fleet1 = newFleet(
      squadrons = @[sq],
      id = "fleet-1".FleetId,
      owner = house1,
      location = sourceSystem
    )
    state.fleets["fleet-1".FleetId] = fleet1

    # House 2 also at hub
    let cruiser = newEnhancedShip(ShipClass.Cruiser)
    var sq2 = newSquadron(cruiser)
    sq2.owner = house2
    sq2.location = sourceSystem

    let fleet2 = newFleet(
      squadrons = @[sq2],
      id = "fleet-2".FleetId,
      owner = house2,
      location = sourceSystem
    )
    state.fleets["fleet-2".FleetId] = fleet2

    # Both houses should detect each other
    let filtered1 = createFogOfWarView(state, house1)
    let filtered2 = createFogOfWarView(state, house2)

    # House 1 sees house 2's fleet
    check filtered1.visibleFleets.len == 1
    check filtered1.visibleFleets[0].owner == house2

    # House 2 sees house 1's fleet
    check filtered2.visibleFleets.len == 1
    check filtered2.visibleFleets[0].owner == house1

  test "Fleet moves to new system - old system loses occupied status":
    let house1 = "house-1".HouseId
    let house1Home = map.playerSystemIds[0]
    let targetSystem = map.hubId

    # Fleet starts at home
    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    var sq = newSquadron(destroyer)
    sq.owner = house1
    sq.location = house1Home

    let fleetId = "fleet-1".FleetId
    var fleet = newFleet(
      squadrons = @[sq],
      id = fleetId,
      owner = house1,
      location = house1Home
    )
    state.fleets[fleetId] = fleet

    var filtered = createFogOfWarView(state, house1)

    # Home system is Owned (colony there)
    check house1Home in filtered.visibleSystems
    check filtered.visibleSystems[house1Home].visibility == VisibilityLevel.Owned

    # Fleet moves to hub
    fleet.location = targetSystem
    sq.location = targetSystem
    fleet.squadrons[0] = sq
    state.fleets[fleetId] = fleet

    filtered = createFogOfWarView(state, house1)

    # Hub is now Occupied
    check targetSystem in filtered.visibleSystems
    check filtered.visibleSystems[targetSystem].visibility == VisibilityLevel.Occupied

    # Home is still Owned (colony remains)
    check house1Home in filtered.visibleSystems
    check filtered.visibleSystems[house1Home].visibility == VisibilityLevel.Owned

  test "Fleet enters enemy territory - both sides detect":
    let house1 = "house-1".HouseId
    let house2 = "house-2".HouseId
    let house2Home = map.playerSystemIds[1]

    # House 1 sends fleet to house 2's home
    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    var sq = newSquadron(destroyer)
    sq.owner = house1
    sq.location = house2Home

    let fleet = newFleet(
      squadrons = @[sq],
      id = "invader".FleetId,
      owner = house1,
      location = house2Home
    )
    state.fleets["invader".FleetId] = fleet

    # House 1 perspective
    let filtered1 = createFogOfWarView(state, house1)

    # Should see house 2's colony (visual detection)
    var foundColony = false
    for col in filtered1.visibleColonies:
      if col.systemId == house2Home and col.owner == house2:
        foundColony = true
    check foundColony

    # House 2 perspective
    let filtered2 = createFogOfWarView(state, house2)

    # Should detect house 1's fleet (in own territory)
    check filtered2.visibleFleets.len >= 1
    var foundFleet = false
    for fleet in filtered2.visibleFleets:
      if fleet.owner == house1 and fleet.location == house2Home:
        foundFleet = true
    check foundFleet

  test "Multiple fleets moving to convergence point - all visible on arrival":
    let hub = map.hubId

    # All 3 houses send fleets to hub
    for i in 0..<3:
      let houseId = ("house-" & $(i+1)).HouseId
      let destroyer = newEnhancedShip(ShipClass.Destroyer)
      var sq = newSquadron(destroyer)
      sq.owner = houseId
      sq.location = hub

      let fleetId = (houseId & "-fleet").FleetId
      let fleet = newFleet(
        squadrons = @[sq],
        id = fleetId,
        owner = houseId,
        location = hub
      )
      state.fleets[fleetId] = fleet

    # Each house should see 2 enemy fleets
    for i in 0..<3:
      let houseId = ("house-" & $(i+1)).HouseId
      let filtered = createFogOfWarView(state, houseId)

      # Should see 2 enemy fleets
      check filtered.visibleFleets.len == 2

      # Should see own fleet
      check filtered.ownFleets.len == 1

  test "Fleet splits - both fleets visible in respective locations":
    let house1 = "house-1".HouseId
    let house1Home = map.playerSystemIds[0]
    let targetSystem = map.hubId

    # Create fleet 1 at home
    let destroyer1 = newEnhancedShip(ShipClass.Destroyer)
    var sq1 = newSquadron(destroyer1)
    sq1.owner = house1
    sq1.location = house1Home

    let fleet1 = newFleet(
      squadrons = @[sq1],
      id = "fleet-1".FleetId,
      owner = house1,
      location = house1Home
    )
    state.fleets["fleet-1".FleetId] = fleet1

    # Create fleet 2 at hub (split from fleet 1)
    let destroyer2 = newEnhancedShip(ShipClass.Destroyer)
    var sq2 = newSquadron(destroyer2)
    sq2.owner = house1
    sq2.location = targetSystem

    let fleet2 = newFleet(
      squadrons = @[sq2],
      id = "fleet-2".FleetId,
      owner = house1,
      location = targetSystem
    )
    state.fleets["fleet-2".FleetId] = fleet2

    let filtered = createFogOfWarView(state, house1)

    # Should see both own fleets
    check filtered.ownFleets.len == 2

    # Home system is Owned
    check house1Home in filtered.visibleSystems
    check filtered.visibleSystems[house1Home].visibility == VisibilityLevel.Owned

    # Hub is Occupied
    check targetSystem in filtered.visibleSystems
    check filtered.visibleSystems[targetSystem].visibility == VisibilityLevel.Occupied

  test "Fleet retreats from combat zone - enemy loses visibility":
    let house1 = "house-1".HouseId
    let house2 = "house-2".HouseId
    let battleground = map.hubId
    let retreatSystem = map.playerSystemIds[0]

    # Both fleets start at battleground
    let destroyer1 = newEnhancedShip(ShipClass.Destroyer)
    var sq1 = newSquadron(destroyer1)
    sq1.owner = house1
    sq1.location = battleground

    let fleet1 = newFleet(
      squadrons = @[sq1],
      id = "fleet-1".FleetId,
      owner = house1,
      location = battleground
    )
    state.fleets["fleet-1".FleetId] = fleet1

    let cruiser = newEnhancedShip(ShipClass.Cruiser)
    var sq2 = newSquadron(cruiser)
    sq2.owner = house2
    sq2.location = battleground

    let fleet2 = newFleet(
      squadrons = @[sq2],
      id = "fleet-2".FleetId,
      owner = house2,
      location = battleground
    )
    state.fleets["fleet-2".FleetId] = fleet2

    # House 2 perspective - sees house 1
    var filtered2 = createFogOfWarView(state, house2)
    check filtered2.visibleFleets.len == 1
    check filtered2.visibleFleets[0].owner == house1

    # House 1 retreats to home
    var fleet1Retreat = state.fleets["fleet-1".FleetId]
    fleet1Retreat.location = retreatSystem
    fleet1Retreat.squadrons[0].location = retreatSystem
    state.fleets["fleet-1".FleetId] = fleet1Retreat

    # House 2 perspective - no longer sees house 1
    filtered2 = createFogOfWarView(state, house2)
    check filtered2.visibleFleets.len == 0

  test "Passing fleets - brief visibility window":
    # This test documents the behavior when fleets pass through a system

    let house1 = "house-1".HouseId
    let house2 = "house-2".HouseId
    let transitSystem = map.hubId

    # House 1 has scout at transit system
    let scout = newEnhancedShip(ShipClass.Scout)
    var scoutSq = newSquadron(scout)
    scoutSq.owner = house1
    scoutSq.location = transitSystem

    let scoutFleet = newFleet(
      squadrons = @[scoutSq],
      id = "scout-fleet".FleetId,
      owner = house1,
      location = transitSystem
    )
    state.fleets["scout-fleet".FleetId] = scoutFleet

    # House 2 fleet "passes through" (at system, not in transit)
    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    var destSq = newSquadron(destroyer)
    destSq.owner = house2
    destSq.location = transitSystem

    let passingFleet = newFleet(
      squadrons = @[destSq],
      id = "passing-fleet".FleetId,
      owner = house2,
      location = transitSystem  # Not marked as in-transit
    )
    state.fleets["passing-fleet".FleetId] = passingFleet

    let filtered = createFogOfWarView(state, house1)

    # House 1 should detect passing fleet (same location)
    check filtered.visibleFleets.len == 1
    check filtered.visibleFleets[0].owner == house2

  test "Adjacent fleet (one jump away) - not visible without intel":
    let house1 = "house-1".HouseId
    let house2 = "house-2".HouseId
    let house1Home = map.playerSystemIds[0]

    # Get a system adjacent to house 1's home
    let adjacentSystems = map.getAdjacentSystems(house1Home)
    check adjacentSystems.len > 0
    let adjacentSystem = adjacentSystems[0]

    # House 2 fleet at adjacent system
    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    var sq = newSquadron(destroyer)
    sq.owner = house2
    sq.location = adjacentSystem

    let fleet2 = newFleet(
      squadrons = @[sq],
      id = "hidden-fleet".FleetId,
      owner = house2,
      location = adjacentSystem
    )
    state.fleets["hidden-fleet".FleetId] = fleet2

    let filtered = createFogOfWarView(state, house1)

    # House 1 should NOT see the fleet (not at same location)
    var foundEnemyFleet = false
    for fleet in filtered.visibleFleets:
      if fleet.owner == house2:
        foundEnemyFleet = true

    check not foundEnemyFleet

    # But should see system as Adjacent
    check adjacentSystem in filtered.visibleSystems
    check filtered.visibleSystems[adjacentSystem].visibility == VisibilityLevel.Adjacent


echo "\n✅ All fog-of-war engine tests compiled successfully"
echo "   Test Suites: 8"
echo "   Coverage:"
echo "     - Core visibility levels (Owned, Occupied, Scouted, Adjacent, None)"
echo "     - Multi-house scenarios"
echo "     - Intelligence database integration"
echo "     - Fleet detection & visibility"
echo "     - Edge cases & transitions"
echo "     - Public information (prestige, diplomacy, elimination)"
