## Unit Tests for Construction and Squadron Management
##
## Tests the core functionality of:
## - Ship construction mechanics
## - Squadron formation
## - Fleet organization
## - Auto-assignment

import std/[unittest, options]
import ../../src/engine/[squadron, fleet]
import ../../src/engine/economy/construction
import ../../src/common/types/[units, planets]

suite "Ship Construction Mechanics":

  test "Get ship construction costs":
    # Verify construction costs are defined for all ship types
    let fighterCost = getShipConstructionCost(ShipClass.Fighter)
    let scoutCost = getShipConstructionCost(ShipClass.Scout)
    let destroyerCost = getShipConstructionCost(ShipClass.Destroyer)
    let cruiserCost = getShipConstructionCost(ShipClass.Cruiser)
    let battleshipCost = getShipConstructionCost(ShipClass.Battleship)
    let dreadnoughtCost = getShipConstructionCost(ShipClass.Dreadnought)

    # All costs should be positive
    check fighterCost > 0
    check scoutCost > 0
    check destroyerCost > 0
    check cruiserCost > 0
    check battleshipCost > 0
    check dreadnoughtCost > 0

    # Generally larger ships cost more (but not strictly linear)
    check fighterCost < battleshipCost
    check cruiserCost < dreadnoughtCost

  test "Get ship build times with CST levels":
    # Test CST reduces build time
    let scoutBase = getShipBuildTime(ShipClass.Scout, cstLevel = 1)
    let scoutCST5 = getShipBuildTime(ShipClass.Scout, cstLevel = 5)

    check scoutCST5 <= scoutBase  # Higher CST = faster or same build time

    # All ship types should have positive build times
    let destroyerTime = getShipBuildTime(ShipClass.Destroyer, cstLevel = 1)
    let battleshipTime = getShipBuildTime(ShipClass.Battleship, cstLevel = 1)

    check destroyerTime > 0
    check battleshipTime > 0

  test "Create ship construction project":
    let project = createShipProject(ShipClass.Cruiser)

    check project.projectType == ConstructionType.Ship
    check project.itemId.len > 0  # Should have ship identifier
    check project.turnsRemaining > 0
    check project.costTotal > 0

  test "Create facility construction projects":
    let spaceportProject = createBuildingProject("Spaceport")
    let shipyardProject = createBuildingProject("Shipyard")
    let starbaseProject = createBuildingProject("Starbase")

    check spaceportProject.projectType == ConstructionType.Building
    check shipyardProject.projectType == ConstructionType.Building
    check starbaseProject.projectType == ConstructionType.Building

    # Verify different build times
    check spaceportProject.turnsRemaining >= 1
    check shipyardProject.turnsRemaining >= 1

suite "Squadron Formation":

  test "Create squadron with flagship":
    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    let sq = newSquadron(destroyer, id = "sq1", owner = "house1", location = 1)

    check sq.id == "sq1"
    check sq.owner == "house1"
    check sq.location == 1
    check sq.flagship.shipClass == ShipClass.Destroyer
    check sq.ships.len == 0  # No additional ships yet

  test "Add ship to squadron":
    let cruiser = newEnhancedShip(ShipClass.Cruiser)
    var sq = newSquadron(cruiser, id = "sq1", owner = "house1", location = 1)

    # Add a destroyer to the squadron
    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    let success = sq.addShip(destroyer)

    check success == true
    check sq.ships.len == 1
    check sq.ships[0].shipClass == ShipClass.Destroyer

  test "Remove ship from squadron":
    let cruiser = newEnhancedShip(ShipClass.Cruiser)
    var sq = newSquadron(cruiser, id = "sq1", owner = "house1", location = 1)

    # Add and then remove a ship
    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    discard sq.addShip(destroyer)
    check sq.ships.len == 1

    let removed = sq.removeShip(0)
    check removed.isSome
    check removed.get().shipClass == ShipClass.Destroyer
    check sq.ships.len == 0

  test "Squadron total AS calculation":
    let cruiser = newEnhancedShip(ShipClass.Cruiser)
    var sq = newSquadron(cruiser, id = "sq1", owner = "house1", location = 1)

    let flagshipAS = sq.flagship.stats.attackStrength

    # Add another ship
    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    let destroyerAS = destroyer.stats.attackStrength
    discard sq.addShip(destroyer)

    # Total AS should be sum of flagship + ships
    let totalAS = sq.combatStrength()
    check totalAS == (flagshipAS + destroyerAS)

  test "Squadron total DS calculation":
    let cruiser = newEnhancedShip(ShipClass.Cruiser)
    var sq = newSquadron(cruiser, id = "sq1", owner = "house1", location = 1)

    let flagshipDS = sq.flagship.stats.defenseStrength

    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    let destroyerDS = destroyer.stats.defenseStrength
    discard sq.addShip(destroyer)

    let totalDS = sq.defenseStrength()
    check totalDS == (flagshipDS + destroyerDS)

suite "Fleet Organization":

  test "Create empty fleet":
    let fleet = newFleet(
      squadrons = @[],
      spaceLiftShips = @[],
      id = "fleet1",
      owner = "house1",
      location = 1
    )

    check fleet.id == "fleet1"
    check fleet.owner == "house1"
    check fleet.location == 1
    check fleet.squadrons.len == 0
    check fleet.spaceLiftShips.len == 0
    check fleet.status == FleetStatus.Active

  test "Create fleet with squadrons":
    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    var sq1 = newSquadron(destroyer, id = "sq1", owner = "house1", location = 1)

    let cruiser = newEnhancedShip(ShipClass.Cruiser)
    var sq2 = newSquadron(cruiser, id = "sq2", owner = "house1", location = 1)

    let fleet = newFleet(
      squadrons = @[sq1, sq2],
      spaceLiftShips = @[],
      id = "fleet1",
      owner = "house1",
      location = 1
    )

    check fleet.squadrons.len == 2
    check fleet.squadrons[0].id == "sq1"
    check fleet.squadrons[1].id == "sq2"

  test "Fleet status types":
    # Verify fleet status enum values exist
    let activeFleet = newFleet(
      id = "f1",
      owner = "h1",
      location = 1,
      status = FleetStatus.Active
    )

    let reserveFleet = newFleet(
      id = "f2",
      owner = "h1",
      location = 1,
      status = FleetStatus.Reserve
    )

    let mothballedFleet = newFleet(
      id = "f3",
      owner = "h1",
      location = 1,
      status = FleetStatus.Mothballed
    )

    check activeFleet.status == FleetStatus.Active
    check reserveFleet.status == FleetStatus.Reserve
    check mothballedFleet.status == FleetStatus.Mothballed

  test "Multiple squadrons of different types in fleet":
    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    var sq1 = newSquadron(destroyer, id = "dd1", owner = "house1", location = 1)

    let cruiser = newEnhancedShip(ShipClass.Cruiser)
    var sq2 = newSquadron(cruiser, id = "ca1", owner = "house1", location = 1)

    let battleship = newEnhancedShip(ShipClass.Battleship)
    var sq3 = newSquadron(battleship, id = "bb1", owner = "house1", location = 1)

    let fleet = newFleet(
      squadrons = @[sq1, sq2, sq3],
      id = "fleet1",
      owner = "house1",
      location = 1
    )

    check fleet.squadrons.len == 3
    # Verify each squadron maintains its type
    check fleet.squadrons[0].flagship.shipClass == ShipClass.Destroyer
    check fleet.squadrons[1].flagship.shipClass == ShipClass.Cruiser
    check fleet.squadrons[2].flagship.shipClass == ShipClass.Battleship

when isMainModule:
  echo "╔════════════════════════════════════════════════╗"
  echo "║  Construction & Squadron Management Tests      ║"
  echo "╚════════════════════════════════════════════════╝"
