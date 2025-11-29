## Fog of War System Tests
##
## Tests fog-of-war filtering to ensure AI only sees what it should

import std/[unittest, tables, options, sets]
import ../../src/engine/[gamestate, fog_of_war, starmap, fleet, squadron]
import ../../src/common/[system, types/[core, planets, tech, units]]
import ../../src/engine/intelligence/types as intel_types

suite "Fog of War System":

  setup:
    # Create a simple 5-system map
    var starMap = StarMap(
      systems: initTable[SystemId, System](),
      starMapWidth: 100,
      starMapHeight: 100,
      numSystems: 5
    )

    # System 1: House Alpha homeworld
    starMap.systems["sys-1"] = System(
      id: "sys-1",
      name: "Alpha Prime",
      x: 10,
      y: 10,
      connections: @["sys-2", "sys-3"]
    )

    # System 2: House Beta homeworld
    starMap.systems["sys-2"] = System(
      id: "sys-2",
      name: "Beta Station",
      x: 20,
      y: 10,
      connections: @["sys-1", "sys-4"]
    )

    # System 3: Adjacent to Alpha, uncolonized
    starMap.systems["sys-3"] = System(
      id: "sys-3",
      name: "Gamma Outpost",
      x: 10,
      y: 20,
      connections: @["sys-1", "sys-4"]
    )

    # System 4: Neutral, visible to both
    starMap.systems["sys-4"] = System(
      id: "sys-4",
      name: "Delta Hub",
      x: 20,
      y: 20,
      connections: @["sys-2", "sys-3", "sys-5"]
    )

    # System 5: Hidden from Alpha
    starMap.systems["sys-5"] = System(
      id: "sys-5",
      name: "Epsilon Unknown",
      x: 30,
      y: 20,
      connections: @["sys-4"]
    )

    # Create game state
    var state = newGameState("test-fow-game", 2, starMap)
    state.turn = 10

    # House Alpha
    var alphaHouse = initializeHouse("Alpha", "blue")
    alphaHouse.id = "house-alpha"
    state.houses["house-alpha"] = alphaHouse

    # House Beta
    var betaHouse = initializeHouse("Beta", "red")
    betaHouse.id = "house-beta"
    state.houses["house-beta"] = betaHouse

    # Alpha colony at sys-1
    state.colonies["sys-1"] = createHomeColony("sys-1", "house-alpha")

    # Beta colony at sys-2
    state.colonies["sys-2"] = createHomeColony("sys-2", "house-beta")

    # Beta colony at sys-5 (hidden from Alpha)
    var betaHiddenColony = createHomeColony("sys-5", "house-beta")
    betaHiddenColony.population = 50
    betaHiddenColony.infrastructure = 5
    state.colonies["sys-5"] = betaHiddenColony

  test "Owned system visibility - full details":
    # Alpha should see sys-1 with full details
    let filtered = createFogOfWarView(state, "house-alpha")

    check filtered.viewingHouse == "house-alpha"
    check filtered.turn == 10
    check filtered.ownColonies.len == 1
    check filtered.ownColonies[0].systemId == "sys-1"

    # Check sys-1 is in visible systems
    check "sys-1" in filtered.visibleSystems
    check filtered.visibleSystems["sys-1"].visibility == VisibilityLevel.Owned
    check filtered.visibleSystems["sys-1"].lastScoutedTurn == some(10)

    # Check staleness
    check filtered.getIntelStaleness("sys-1") == 0  # Current

  test "Occupied system visibility - fleet presence":
    # Place Alpha fleet at sys-3
    var alphaFleet = Fleet(
      id: "fleet-alpha-1",
      name: "Alpha Expeditionary",
      owner: "house-alpha",
      location: "sys-3",
      squadrons: @[],
      spaceLiftShips: @[]
    )
    state.fleets["fleet-alpha-1"] = alphaFleet

    let filtered = createFogOfWarView(state, "house-alpha")

    # Alpha should see sys-3 as occupied
    check "sys-3" in filtered.visibleSystems
    check filtered.visibleSystems["sys-3"].visibility == VisibilityLevel.Occupied
    check filtered.visibleSystems["sys-3"].lastScoutedTurn == some(10)

    # Check fleet is visible
    check filtered.ownFleets.len == 1
    check filtered.ownFleets[0].id == "fleet-alpha-1"

  test "Adjacent system visibility - awareness only":
    # Alpha should see sys-2 and sys-3 as adjacent (connected to owned sys-1)
    let filtered = createFogOfWarView(state, "house-alpha")

    # sys-2 should be adjacent
    check "sys-2" in filtered.visibleSystems
    check filtered.visibleSystems["sys-2"].visibility == VisibilityLevel.Adjacent
    check filtered.visibleSystems["sys-2"].lastScoutedTurn.isNone

    # sys-3 should be adjacent
    check "sys-3" in filtered.visibleSystems
    check filtered.visibleSystems["sys-3"].visibility == VisibilityLevel.Adjacent

  test "Hidden system - no visibility":
    # Alpha should NOT see sys-5 (not connected to known systems)
    let filtered = createFogOfWarView(state, "house-alpha")

    # sys-5 should not be visible
    check "sys-5" notin filtered.visibleSystems

    # Beta colony at sys-5 should not be visible
    check filtered.visibleColonies.len == 0

  test "Enemy colony in occupied system - visible":
    # Place Alpha fleet at sys-2 (Beta's colony)
    var alphaFleet = Fleet(
      id: "fleet-alpha-1",
      name: "Alpha Scouts",
      owner: "house-alpha",
      location: "sys-2",
      squadrons: @[],
      spaceLiftShips: @[]
    )
    state.fleets["fleet-alpha-1"] = alphaFleet

    let filtered = createFogOfWarView(state, "house-alpha")

    # sys-2 should be occupied
    check "sys-2" in filtered.visibleSystems
    check filtered.visibleSystems["sys-2"].visibility == VisibilityLevel.Occupied

    # Beta colony at sys-2 should be visible
    check filtered.visibleColonies.len == 1
    check filtered.visibleColonies[0].systemId == "sys-2"
    check filtered.visibleColonies[0].owner == "house-beta"

  test "Enemy fleet detection - same system":
    # Place both Alpha and Beta fleets at sys-4
    var alphaFleet = Fleet(
      id: "fleet-alpha-1",
      name: "Alpha Patrol",
      owner: "house-alpha",
      location: "sys-4",
      squadrons: @[],
      spaceLiftShips: @[]
    )
    state.fleets["fleet-alpha-1"] = alphaFleet

    var betaFleet = Fleet(
      id: "fleet-beta-1",
      name: "Beta Interceptors",
      owner: "house-beta",
      location: "sys-4",
      squadrons: @[],
      spaceLiftShips: @[]
    )
    state.fleets["fleet-beta-1"] = betaFleet

    let filtered = createFogOfWarView(state, "house-alpha")

    # Alpha should detect Beta fleet
    check filtered.visibleFleets.len == 1
    check filtered.visibleFleets[0].fleetId == "fleet-beta-1"
    check filtered.visibleFleets[0].owner == "house-beta"
    check filtered.visibleFleets[0].location == "sys-4"
    check filtered.visibleFleets[0].intelTurn == some(10)

  test "Enemy fleet in hidden system - not visible":
    # Place Beta fleet at sys-5 (hidden from Alpha)
    var betaFleet = Fleet(
      id: "fleet-beta-1",
      name: "Beta Hidden Fleet",
      owner: "house-beta",
      location: "sys-5",
      squadrons: @[],
      spaceLiftShips: @[]
    )
    state.fleets["fleet-beta-1"] = betaFleet

    let filtered = createFogOfWarView(state, "house-alpha")

    # Alpha should NOT see Beta fleet
    check filtered.visibleFleets.len == 0

  test "Stale intel from intelligence database":
    # Add stale colony intel for sys-2 to Alpha's intelligence
    var alphaHouse = state.houses["house-alpha"]

    let colonyIntel = ColonyIntelReport(
      colonyId: "sys-2",
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

    # sys-2 should be scouted (stale intel)
    check "sys-2" in filtered.visibleSystems
    check filtered.visibleSystems["sys-2"].visibility == VisibilityLevel.Scouted
    check filtered.visibleSystems["sys-2"].lastScoutedTurn == some(5)

    # Check staleness
    check filtered.getIntelStaleness("sys-2") == 5  # 5 turns stale

  test "Public information - prestige visible":
    let filtered = createFogOfWarView(state, "house-alpha")

    # Alpha should see Beta's prestige
    check filtered.housePrestige.len == 2
    check "house-alpha" in filtered.housePrestige
    check "house-beta" in filtered.housePrestige

  test "Own assets - full details":
    # Add multiple colonies and fleets for Alpha
    var alphaColony2 = createHomeColony("sys-3", "house-alpha")
    alphaColony2.population = 30
    state.colonies["sys-3"] = alphaColony2

    var alphaFleet = Fleet(
      id: "fleet-alpha-1",
      name: "Alpha Fleet",
      owner: "house-alpha",
      location: "sys-1",
      squadrons: @[],
      spaceLiftShips: @[]
    )
    state.fleets["fleet-alpha-1"] = alphaFleet

    let filtered = createFogOfWarView(state, "house-alpha")

    # Check own colonies
    check filtered.ownColonies.len == 2
    check filtered.ownColonies[0].population in [100, 30]  # Either colony
    check filtered.ownColonies[1].population in [100, 30]

    # Check own fleets
    check filtered.ownFleets.len == 1
    check filtered.ownFleets[0].id == "fleet-alpha-1"

  test "Helper procs - canSeeColonyDetails":
    # Place Alpha fleet at sys-2
    var alphaFleet = Fleet(
      id: "fleet-alpha-1",
      name: "Alpha Scouts",
      owner: "house-alpha",
      location: "sys-2",
      squadrons: @[],
      spaceLiftShips: @[]
    )
    state.fleets["fleet-alpha-1"] = alphaFleet

    let filtered = createFogOfWarView(state, "house-alpha")

    # Can see details at owned sys-1
    check filtered.canSeeColonyDetails("sys-1")

    # Can see details at occupied sys-2
    check filtered.canSeeColonyDetails("sys-2")

    # Cannot see details at adjacent sys-3
    check not filtered.canSeeColonyDetails("sys-3")

    # Cannot see details at hidden sys-5
    check not filtered.canSeeColonyDetails("sys-5")

  test "Helper procs - canSeeFleets":
    # Place Alpha fleet at sys-4
    var alphaFleet = Fleet(
      id: "fleet-alpha-1",
      name: "Alpha Patrol",
      owner: "house-alpha",
      location: "sys-4",
      squadrons: @[],
      spaceLiftShips: @[]
    )
    state.fleets["fleet-alpha-1"] = alphaFleet

    let filtered = createFogOfWarView(state, "house-alpha")

    # Can see fleets at owned sys-1
    check filtered.canSeeFleets("sys-1")

    # Can see fleets at occupied sys-4
    check filtered.canSeeFleets("sys-4")

    # Cannot see fleets at adjacent sys-2
    check not filtered.canSeeFleets("sys-2")

    # Cannot see fleets at hidden sys-5
    check not filtered.canSeeFleets("sys-5")

  test "Intelligence database integration":
    # Add various intel reports to Alpha
    var alphaHouse = state.houses["house-alpha"]

    # Colony intel for sys-2
    let colonyIntel = ColonyIntelReport(
      colonyId: "sys-2",
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

    # System intel for sys-4
    let systemIntel = SystemIntelReport(
      systemId: "sys-4",
      gatheredTurn: 9,
      quality: IntelQuality.Visual,
      detectedFleets: @[]
    )
    alphaHouse.intelligence.addSystemReport(systemIntel)

    state.houses["house-alpha"] = alphaHouse

    let filtered = createFogOfWarView(state, "house-alpha")

    # sys-2 should be scouted
    check "sys-2" in filtered.visibleSystems
    check filtered.visibleSystems["sys-2"].visibility == VisibilityLevel.Scouted
    check filtered.getIntelStaleness("sys-2") == 2  # Turn 10 - turn 8

    # sys-4 should be scouted
    check "sys-4" in filtered.visibleSystems
    check filtered.visibleSystems["sys-4"].visibility == VisibilityLevel.Scouted
    check filtered.getIntelStaleness("sys-4") == 1  # Turn 10 - turn 9

echo "✓ All fog of war tests compiled successfully"
