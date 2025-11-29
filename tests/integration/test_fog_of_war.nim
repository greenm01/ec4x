## Fog of War System Tests
##
## Tests fog-of-war filtering to ensure AI only sees what it should

import std/[unittest, tables, options, sets]
import ../../src/engine/[gamestate, fog_of_war, starmap, fleet, squadron]
import ../../src/engine/research/types as res_types
import ../../src/common/system
import ../../src/common/types/[core, planets, tech, units]
import ../../src/engine/intelligence/types as intel_types

suite "Fog of War System":

  setup:
    # Create a simple 2-player starmap
    var starMap = newStarMap(2)
    starMap.populate()

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

    # Alpha colony at system 1
    state.colonies[1] = createHomeColony(1.SystemId, "house-alpha")

    # Beta colony at system 2
    state.colonies[2] = createHomeColony(2.SystemId, "house-beta")

  test "Owned system visibility - full details":
    # Alpha should see system 1 with full details
    let filtered = createFogOfWarView(state, "house-alpha")

    check filtered.viewingHouse == "house-alpha"
    check filtered.turn == 10
    check filtered.ownColonies.len == 1
    check filtered.ownColonies[0].systemId == 1.uint

    # Check system 1 is in visible systems
    check 1.uint in filtered.visibleSystems
    check filtered.visibleSystems[1.uint].visibility == VisibilityLevel.Owned
    check filtered.visibleSystems[1.uint].lastScoutedTurn == some(10)

    # Check staleness
    check filtered.getIntelStaleness(1.uint) == 0  # Current

  test "Occupied system visibility - fleet presence":
    # Place Alpha fleet at system 3
    var alphaFleet = Fleet(
      id: "fleet-alpha-1",
      owner: "house-alpha",
      location: 3.uint,
      squadrons: @[],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: true
    )
    state.fleets["fleet-alpha-1"] = alphaFleet

    let filtered = createFogOfWarView(state, "house-alpha")

    # Alpha should see system 3 as occupied
    check 3.uint in filtered.visibleSystems
    check filtered.visibleSystems[3.uint].visibility == VisibilityLevel.Occupied
    check filtered.visibleSystems[3.uint].lastScoutedTurn == some(10)

    # Check fleet is visible
    check filtered.ownFleets.len == 1
    check filtered.ownFleets[0].id == "fleet-alpha-1"

  test "Adjacent system visibility - awareness only":
    # Alpha should see sys-2 and sys-3 as adjacent (connected to owned sys-1)
    let filtered = createFogOfWarView(state, "house-alpha")

    # sys-2 should be adjacent
    check 2.uint in filtered.visibleSystems
    check filtered.visibleSystems[2.uint].visibility == VisibilityLevel.Adjacent
    check filtered.visibleSystems[2.uint].lastScoutedTurn.isNone

    # sys-3 should be adjacent
    check 3.uint in filtered.visibleSystems
    check filtered.visibleSystems[3.uint].visibility == VisibilityLevel.Adjacent

  test "Hidden system - no visibility":
    # Alpha should NOT see sys-5 (not connected to known systems)
    let filtered = createFogOfWarView(state, "house-alpha")

    # sys-5 should not be visible
    check 5.uint notin filtered.visibleSystems

    # Beta colony at sys-5 should not be visible
    check filtered.visibleColonies.len == 0

  test "Enemy colony in occupied system - visible":
    # Place Alpha fleet at sys-2 (Beta's colony)
    var alphaFleet = Fleet(
      id: "fleet-alpha-1",
      owner: "house-alpha",
      location: 2.uint,
      squadrons: @[],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: true
    )
    state.fleets["fleet-alpha-1"] = alphaFleet

    let filtered = createFogOfWarView(state, "house-alpha")

    # sys-2 should be occupied
    check 2.uint in filtered.visibleSystems
    check filtered.visibleSystems[2.uint].visibility == VisibilityLevel.Occupied

    # Beta colony at sys-2 should be visible
    check filtered.visibleColonies.len == 1
    check filtered.visibleColonies[0].systemId == 2.uint
    check filtered.visibleColonies[0].owner == "house-beta"

  test "Enemy fleet detection - same system":
    # Place both Alpha and Beta fleets at sys-4
    var alphaFleet = Fleet(
      id: "fleet-alpha-1",
      owner: "house-alpha",
      location: 4.uint,
      squadrons: @[],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: true
    )
    state.fleets["fleet-alpha-1"] = alphaFleet

    var betaFleet = Fleet(
      id: "fleet-beta-1",
      owner: "house-beta",
      location: 4.uint,
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
    check filtered.visibleFleets[0].location == 4.uint
    check filtered.visibleFleets[0].intelTurn == some(10)

  test "Enemy fleet in hidden system - not visible":
    # Place Beta fleet at sys-5 (hidden from Alpha)
    var betaFleet = Fleet(
      id: "fleet-beta-1",
      owner: "house-beta",
      location: 5.uint,
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
    # Add stale colony intel for sys-2 to Alpha's intelligence
    var alphaHouse = state.houses["house-alpha"]

    let colonyIntel = ColonyIntelReport(
      colonyId: 2.uint,
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
    check 2.uint in filtered.visibleSystems
    check filtered.visibleSystems[2.uint].visibility == VisibilityLevel.Scouted
    check filtered.visibleSystems[2.uint].lastScoutedTurn == some(5)

    # Check staleness
    check filtered.getIntelStaleness(2.uint) == 5  # 5 turns stale

  test "Public information - prestige visible":
    let filtered = createFogOfWarView(state, "house-alpha")

    # Alpha should see Beta's prestige
    check filtered.housePrestige.len == 2
    check "house-alpha" in filtered.housePrestige
    check "house-beta" in filtered.housePrestige

  test "Own assets - full details":
    # Add multiple colonies and fleets for Alpha
    var alphaColony2 = createHomeColony(3.SystemId, "house-alpha")
    alphaColony2.population = 30
    state.colonies[3] = alphaColony2

    var alphaFleet = Fleet(
      id: "fleet-alpha-1",
      owner: "house-alpha",
      location: 1.uint,
      squadrons: @[],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: true
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
      owner: "house-alpha",
      location: 2.uint,
      squadrons: @[],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: true
    )
    state.fleets["fleet-alpha-1"] = alphaFleet

    let filtered = createFogOfWarView(state, "house-alpha")

    # Can see details at owned sys-1
    check filtered.canSeeColonyDetails(1.uint)

    # Can see details at occupied sys-2
    check filtered.canSeeColonyDetails(2.uint)

    # Cannot see details at adjacent sys-3
    check not filtered.canSeeColonyDetails(3.uint)

    # Cannot see details at hidden sys-5
    check not filtered.canSeeColonyDetails(5.uint)

  test "Helper procs - canSeeFleets":
    # Place Alpha fleet at sys-4
    var alphaFleet = Fleet(
      id: "fleet-alpha-1",
      owner: "house-alpha",
      location: 4.uint,
      squadrons: @[],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: true
    )
    state.fleets["fleet-alpha-1"] = alphaFleet

    let filtered = createFogOfWarView(state, "house-alpha")

    # Can see fleets at owned sys-1
    check filtered.canSeeFleets(1.uint)

    # Can see fleets at occupied sys-4
    check filtered.canSeeFleets(4.uint)

    # Cannot see fleets at adjacent sys-2
    check not filtered.canSeeFleets(2.uint)

    # Cannot see fleets at hidden sys-5
    check not filtered.canSeeFleets(5.uint)

  test "Intelligence database integration":
    # Add various intel reports to Alpha
    var alphaHouse = state.houses["house-alpha"]

    # Colony intel for sys-2
    let colonyIntel = ColonyIntelReport(
      colonyId: 2.uint,
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
      systemId: 4.uint,
      gatheredTurn: 9,
      quality: IntelQuality.Visual,
      detectedFleets: @[]
    )
    alphaHouse.intelligence.addSystemReport(systemIntel)

    state.houses["house-alpha"] = alphaHouse

    let filtered = createFogOfWarView(state, "house-alpha")

    # sys-2 should be scouted
    check 2.uint in filtered.visibleSystems
    check filtered.visibleSystems[2.uint].visibility == VisibilityLevel.Scouted
    check filtered.getIntelStaleness(2.uint) == 2  # Turn 10 - turn 8

    # sys-4 should be scouted
    check 4.uint in filtered.visibleSystems
    check filtered.visibleSystems[4.uint].visibility == VisibilityLevel.Scouted
    check filtered.getIntelStaleness(4.uint) == 1  # Turn 10 - turn 9

echo "✓ All fog of war tests compiled successfully"
