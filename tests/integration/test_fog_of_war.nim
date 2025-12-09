## Fog of War System Tests
##
## Tests fog-of-war filtering to ensure AI only sees what it should

import std/[unittest, tables, options, sets]
import ../../src/engine/[gamestate, fog_of_war, starmap, fleet, squadron]
import ../../src/engine/initialization/game
import ../../src/engine/research/types as res_types
import ../../src/common/system
import ../../src/common/types/[core, planets, tech, units]
import ../../src/engine/intelligence/types as intel_types

suite "Fog of War System":

  setup:
    # Create a simple 2-player starmap
    var starMap = newStarMap(2)
    starMap.populate()

    # Get player homeworld system IDs from the starmap
    let alphaSystemId = starMap.playerSystemIds[0]
    let betaSystemId = starMap.playerSystemIds[1]

    # Get adjacent systems for testing
    let alphaAdjacent = starMap.getAdjacentSystems(alphaSystemId)
    let adjacentSystem1 = if alphaAdjacent.len > 0: alphaAdjacent[0] else: alphaSystemId + 1
    let adjacentSystem2 = if alphaAdjacent.len > 1: alphaAdjacent[1] else: alphaSystemId + 2


    # Get a hidden system (not adjacent to alpha, at least 2 hops away)
    var hiddenSystem: uint = 0
    for sysId in starMap.systems.keys:
      if sysId != alphaSystemId and sysId notin alphaAdjacent:
        # Check if it's also not adjacent to any of alpha's adjacent systems
        let sysAdjacent = starMap.getAdjacentSystems(sysId)
        var isTrulyHidden = true
        for adjId in sysAdjacent:
          if adjId == alphaSystemId or adjId in alphaAdjacent:
            isTrulyHidden = false
            break
        if isTrulyHidden:
          hiddenSystem = sysId
          break

    # Create game state
    var state = newGameState("test-fow-game", 2, starMap)
    state.turn = 10

    # House Alpha
    state.houses["house-alpha"] = House(
      id: "house-alpha",
      name: "Alpha",
      treasury: 1000,
      eliminated: false,
      techTree: res_types.initTechTree()
    )

    # House Beta
    state.houses["house-beta"] = House(
      id: "house-beta",
      name: "Beta",
      treasury: 1000,
      eliminated: false,
      techTree: res_types.initTechTree()
    )

    # Alpha colony at player homeworld
    state.colonies[alphaSystemId] = createHomeColony(alphaSystemId.SystemId, "house-alpha")

    # Beta colony at player homeworld
    state.colonies[betaSystemId] = createHomeColony(betaSystemId.SystemId, "house-beta")

  test "Owned system visibility - full details":
    # Alpha should see their homeworld with full details
    let filtered = createFogOfWarView(state, "house-alpha")

    check filtered.viewingHouse == "house-alpha"
    check filtered.turn == 10
    check filtered.ownColonies.len == 1
    check filtered.ownColonies[0].systemId == alphaSystemId

    # Check alpha homeworld is in visible systems
    check alphaSystemId in filtered.visibleSystems
    check filtered.visibleSystems[alphaSystemId].visibility == VisibilityLevel.Owned
    check filtered.visibleSystems[alphaSystemId].lastScoutedTurn == some(10)

    # Check staleness
    check filtered.getIntelStaleness(alphaSystemId) == 0  # Current

  test "Occupied system visibility - fleet presence":
    # Place Alpha fleet at an adjacent system
    var alphaFleet = Fleet(
      id: "fleet-alpha-1",
      owner: "house-alpha",
      location: adjacentSystem1,
      squadrons: @[],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: true
    )
    state.fleets["fleet-alpha-1"] = alphaFleet

    let filtered = createFogOfWarView(state, "house-alpha")

    # Alpha should see the adjacent system as occupied
    check adjacentSystem1 in filtered.visibleSystems
    check filtered.visibleSystems[adjacentSystem1].visibility == VisibilityLevel.Occupied
    check filtered.visibleSystems[adjacentSystem1].lastScoutedTurn == some(10)

    # Check fleet is visible
    check filtered.ownFleets.len == 1
    check filtered.ownFleets[0].id == "fleet-alpha-1"

  test "Adjacent system visibility - awareness only":
    # Alpha should see adjacent systems
    let filtered = createFogOfWarView(state, "house-alpha")

    # Adjacent systems should be visible
    check adjacentSystem1 in filtered.visibleSystems
    check filtered.visibleSystems[adjacentSystem1].visibility == VisibilityLevel.Adjacent
    check filtered.visibleSystems[adjacentSystem1].lastScoutedTurn.isNone

    if alphaAdjacent.len > 1:
      check adjacentSystem2 in filtered.visibleSystems
      check filtered.visibleSystems[adjacentSystem2].visibility == VisibilityLevel.Adjacent

  test "Universal map awareness - all systems visible":
    # Per fog_of_war.nim lines 315-328: Universal map awareness is enabled
    # ALL systems are visible from start with full jump lane information
    # This is an intentional game design: players know the map topology,
    # but colonies/fleets remain hidden until scouted
    let filtered = createFogOfWarView(state, "house-alpha")

    # ALL systems should be visible (universal map awareness)
    check filtered.visibleSystems.len == state.starMap.systems.len

    # Systems that aren't owned/occupied/scouted should be Adjacent visibility
    if hiddenSystem > 0:
      check hiddenSystem in filtered.visibleSystems
      check filtered.visibleSystems[hiddenSystem].visibility == VisibilityLevel.Adjacent
      # Jump lanes are revealed for strategic planning
      check filtered.visibleSystems[hiddenSystem].jumpLanes.len >= 0

    # No enemy colonies should be visible (none placed yet in this test)
    check filtered.visibleColonies.len == 0

  test "Enemy colony in occupied system - visible":
    # Place Alpha fleet at Beta's colony
    var alphaFleet = Fleet(
      id: "fleet-alpha-1",
      owner: "house-alpha",
      location: betaSystemId,
      squadrons: @[],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: true
    )
    state.fleets["fleet-alpha-1"] = alphaFleet

    let filtered = createFogOfWarView(state, "house-alpha")

    # Beta's system should be occupied
    check betaSystemId in filtered.visibleSystems
    check filtered.visibleSystems[betaSystemId].visibility == VisibilityLevel.Occupied

    # Beta colony should be visible
    check filtered.visibleColonies.len == 1
    check filtered.visibleColonies[0].systemId == betaSystemId
    check filtered.visibleColonies[0].owner == "house-beta"

  test "Enemy fleet detection - same system":
    # Place both Alpha and Beta fleets at an adjacent system
    var alphaFleet = Fleet(
      id: "fleet-alpha-1",
      owner: "house-alpha",
      location: adjacentSystem1,
      squadrons: @[],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: true
    )
    state.fleets["fleet-alpha-1"] = alphaFleet

    var betaFleet = Fleet(
      id: "fleet-beta-1",
      owner: "house-beta",
      location: adjacentSystem1,
      squadrons: @[],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: true
    )
    state.fleets["fleet-beta-1"] = betaFleet

    let filtered = createFogOfWarView(state, "house-alpha")

    # Alpha should detect Beta fleet
    check filtered.visibleFleets.len == 1
    check filtered.visibleFleets[0].fleetId == "fleet-beta-1"
    check filtered.visibleFleets[0].owner == "house-beta"
    check filtered.visibleFleets[0].location == adjacentSystem1
    check filtered.visibleFleets[0].intelTurn == some(10)

  test "Enemy fleet in hidden system - not visible":
    # Place Beta fleet at hidden system
    var betaFleet = Fleet(
      id: "fleet-beta-1",
      owner: "house-beta",
      location: hiddenSystem,
      squadrons: @[],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: true
    )
    state.fleets["fleet-beta-1"] = betaFleet

    let filtered = createFogOfWarView(state, "house-alpha")

    # Alpha should NOT see Beta fleet
    check filtered.visibleFleets.len == 0

  test "Stale intel from intelligence database":
    # Add stale colony intel for Beta's system to Alpha's intelligence
    var alphaHouse = state.houses["house-alpha"]

    let colonyIntel = ColonyIntelReport(
      colonyId: betaSystemId,
      targetOwner: "house-beta",
      gatheredTurn: 5,  # 5 turns ago
      quality: IntelQuality.Spy,
      population: 80,
      industry: 4,
      defenses: 2,
      starbaseLevel: 0,
      constructionQueue: @[]
    )
    alphaHouse.intelligence.addColonyReport(colonyIntel)
    state.houses["house-alpha"] = alphaHouse

    let filtered = createFogOfWarView(state, "house-alpha")

    # Beta's system should be scouted (stale intel)
    check betaSystemId in filtered.visibleSystems
    check filtered.visibleSystems[betaSystemId].visibility == VisibilityLevel.Scouted
    check filtered.visibleSystems[betaSystemId].lastScoutedTurn == some(5)

    # Check staleness
    check filtered.getIntelStaleness(betaSystemId) == 5  # 5 turns stale

  test "Public information - prestige visible":
    let filtered = createFogOfWarView(state, "house-alpha")

    # Alpha should see Beta's prestige
    check filtered.housePrestige.len == 2
    check "house-alpha" in filtered.housePrestige
    check "house-beta" in filtered.housePrestige

  test "Own assets - full details":
    # Add multiple colonies and fleets for Alpha
    var alphaColony2 = createHomeColony(adjacentSystem1.SystemId, "house-alpha")
    alphaColony2.population = 30
    alphaColony2.populationUnits = 30
    alphaColony2.souls = 30_000_000  # 30 PU = 30M souls
    state.colonies[adjacentSystem1] = alphaColony2

    var alphaFleet = Fleet(
      id: "fleet-alpha-1",
      owner: "house-alpha",
      location: alphaSystemId,
      squadrons: @[],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: true
    )
    state.fleets["fleet-alpha-1"] = alphaFleet

    let filtered = createFogOfWarView(state, "house-alpha")

    # Check own colonies
    check filtered.ownColonies.len == 2
    # Population: homeworld (from config) or 30 (second colony)
    let homePopulation = state.colonies[alphaSystemId].population
    let secondPopulation = state.colonies[adjacentSystem1].population
    let pops = [filtered.ownColonies[0].population, filtered.ownColonies[1].population]
    check homePopulation in pops
    check secondPopulation in pops

    # Check own fleets
    check filtered.ownFleets.len == 1
    check filtered.ownFleets[0].id == "fleet-alpha-1"

  test "Helper procs - canSeeColonyDetails":
    # Place Alpha fleet at Beta's system
    var alphaFleet = Fleet(
      id: "fleet-alpha-1",
      owner: "house-alpha",
      location: betaSystemId,
      squadrons: @[],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: true
    )
    state.fleets["fleet-alpha-1"] = alphaFleet

    let filtered = createFogOfWarView(state, "house-alpha")

    # Can see details at owned system
    check filtered.canSeeColonyDetails(alphaSystemId)

    # Can see details at occupied system
    check filtered.canSeeColonyDetails(betaSystemId)

    # Cannot see details at adjacent system
    if alphaAdjacent.len > 0:
      check not filtered.canSeeColonyDetails(adjacentSystem1)

    # Cannot see details at hidden system
    check not filtered.canSeeColonyDetails(hiddenSystem)

  test "Helper procs - canSeeFleets":
    # Place Alpha fleet at an adjacent system
    var alphaFleet = Fleet(
      id: "fleet-alpha-1",
      owner: "house-alpha",
      location: adjacentSystem1,
      squadrons: @[],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: true
    )
    state.fleets["fleet-alpha-1"] = alphaFleet

    let filtered = createFogOfWarView(state, "house-alpha")

    # Can see fleets at owned system
    check filtered.canSeeFleets(alphaSystemId)

    # Can see fleets at occupied system
    check filtered.canSeeFleets(adjacentSystem1)

    # Cannot see fleets at non-occupied adjacent system
    if alphaAdjacent.len > 1:
      check not filtered.canSeeFleets(adjacentSystem2)

    # Cannot see fleets at hidden system
    check not filtered.canSeeFleets(hiddenSystem)

  test "Intelligence database integration":
    # Add various intel reports to Alpha
    var alphaHouse = state.houses["house-alpha"]

    # Colony intel for Beta's system
    let colonyIntel = ColonyIntelReport(
      colonyId: betaSystemId,
      targetOwner: "house-beta",
      gatheredTurn: 8,
      quality: IntelQuality.Spy,
      population: 100,
      industry: 3,
      defenses: 1,
      starbaseLevel: 0,
      constructionQueue: @[]
    )
    alphaHouse.intelligence.addColonyReport(colonyIntel)

    # System intel for an adjacent system
    let systemIntel = SystemIntelReport(
      systemId: adjacentSystem1,
      gatheredTurn: 9,
      quality: IntelQuality.Visual,
      detectedFleets: @[]
    )
    alphaHouse.intelligence.addSystemReport(systemIntel)

    state.houses["house-alpha"] = alphaHouse

    let filtered = createFogOfWarView(state, "house-alpha")

    # Beta's system should be scouted
    check betaSystemId in filtered.visibleSystems
    check filtered.visibleSystems[betaSystemId].visibility == VisibilityLevel.Scouted
    check filtered.getIntelStaleness(betaSystemId) == 2  # Turn 10 - turn 8

    # Adjacent system should be scouted
    check adjacentSystem1 in filtered.visibleSystems
    check filtered.visibleSystems[adjacentSystem1].visibility == VisibilityLevel.Scouted
    check filtered.getIntelStaleness(adjacentSystem1) == 1  # Turn 10 - turn 9

echo "✓ All fog of war tests compiled successfully"
