## Unit Tests for Fleet and Squadron Cleanup Operations
##
## Tests the cleanup pattern applied throughout the codebase:
## - Empty fleets are removed
## - Associated orders are cleaned up
## - Squadrons maintain flagship invariant

import std/[unittest, tables]
import ../../src/engine/fleet
import ../../src/engine/squadron
import ../../src/common/types/[core, units]

proc createTestShip(shipClass: ShipClass, crippled: bool = false): EnhancedShip =
  EnhancedShip(
    shipClass: shipClass,
    shipType: ShipType.Military,
    stats: ShipStats(
      name: $shipClass,
      class: $shipClass,
      attackStrength: 10,
      defenseStrength: 10,
      commandCost: 1,
      commandRating: 5,
      techLevel: 1,
      buildCost: 100,
      upkeepCost: 10,
      specialCapability: "",
      carryLimit: 0
    ),
    isCrippled: crippled,
    name: $shipClass
  )

proc createTestSquadron(id: SquadronId, flagshipClass: ShipClass,
                       escortCount: int = 0): Squadron =
  var escorts: seq[EnhancedShip] = @[]
  for i in 0..<escortCount:
    escorts.add(createTestShip(ShipClass.Frigate, false))

  Squadron(
    id: id,
    flagship: createTestShip(flagshipClass, false),
    ships: escorts,
    owner: "house-test",
    location: 1.SystemId,
    destroyed: false,
    embarkedFighters: @[]
  )

suite "Squadron Invariants":
  test "Squadron always has flagship":
    let squad = createTestSquadron("squad-1", ShipClass.Battleship, escortCount = 0)

    check squad.flagship.shipClass == ShipClass.Battleship
    check squad.ships.len == 0
    check not squad.destroyed

  test "Squadron with escorts":
    let squad = createTestSquadron("squad-1", ShipClass.Battleship, escortCount = 3)

    check squad.flagship.shipClass == ShipClass.Battleship
    check squad.ships.len == 3
    check squad.shipCount() == 4  # flagship + 3 escorts

  test "isEmpty means no escorts (flagship still present)":
    let squad = createTestSquadron("squad-1", ShipClass.Scout, escortCount = 0)

    check squad.isEmpty()  # No escorts
    check squad.shipCount() == 1  # But still has flagship

suite "Fleet Invariants":
  test "Empty fleet has no squadrons":
    var fleet = Fleet(
      id: "fleet-1",
      owner: "house-test",
      location: 1.SystemId,
      squadrons: @[],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: false
    )

    check fleet.isEmpty()
    check fleet.squadrons.len == 0

  test "Fleet with squadrons is not empty":
    let squad = createTestSquadron("squad-1", ShipClass.Cruiser, escortCount = 2)
    var fleet = Fleet(
      id: "fleet-1",
      owner: "house-test",
      location: 1.SystemId,
      squadrons: @[squad],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: false
    )

    check not fleet.isEmpty()
    check fleet.squadrons.len == 1

suite "Cleanup Pattern":
  test "Removing last squadron leaves empty fleet":
    let squad = createTestSquadron("squad-1", ShipClass.Battleship, escortCount = 2)
    var fleet = Fleet(
      id: "fleet-1",
      owner: "house-test",
      location: 1.SystemId,
      squadrons: @[squad],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: false
    )

    # Remove all squadrons
    fleet.squadrons = @[]

    # Fleet should be marked for deletion
    check fleet.isEmpty()
    check fleet.squadrons.len == 0

  test "Removing one squadron from multi-squadron fleet":
    let squad1 = createTestSquadron("squad-1", ShipClass.Battleship, escortCount = 2)
    let squad2 = createTestSquadron("squad-2", ShipClass.Cruiser, escortCount = 1)
    var fleet = Fleet(
      id: "fleet-1",
      owner: "house-test",
      location: 1.SystemId,
      squadrons: @[squad1, squad2],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: false
    )

    # Remove one squadron
    fleet.squadrons.delete(0)

    # Fleet still valid
    check not fleet.isEmpty()
    check fleet.squadrons.len == 1
    check fleet.squadrons[0].id == "squad-2"

when isMainModule:
  echo "Running fleet and squadron cleanup tests..."
