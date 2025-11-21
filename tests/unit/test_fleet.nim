## Fleet Unit Tests
##
## Tests for fleet composition and operations

import unittest
import ../../src/engine/[ship, fleet]
import ../../src/common/types/combat

suite "Fleet Tests":
  test "fleet creation":
    let emptyFleet = newFleet()
    let ships = @[militaryShip(), spaceliftShip()]
    let fleet = newFleet(ships)

    check emptyFleet.isEmpty()
    check emptyFleet.len == 0
    check fleet.len == 2
    check not fleet.isEmpty()

  test "fleet operations":
    var fleet = newFleet()
    let military = militaryShip()
    let spacelift = spaceliftShip()

    fleet.add(military)
    fleet.add(spacelift)

    check fleet.len == 2
    check fleet.hasCombatShips()
    check fleet.hasTransportShips()
    check fleet.combatStrength() == 1
    check fleet.transportCapacity() == 1

  test "fleet lane traversal":
    let mixedFleet = fleet(militaryShip(), spaceliftShip())
    let militaryFleet = fleet(militaryShip(), militaryShip())
    let spaceliftFleet = fleet(spaceliftShip(), spaceliftShip())

    # Major and Minor lanes can be traversed by any fleet
    check mixedFleet.canTraverse(Major)
    check mixedFleet.canTraverse(Minor)
    check militaryFleet.canTraverse(Major)
    check militaryFleet.canTraverse(Minor)
    check spaceliftFleet.canTraverse(Major)
    check spaceliftFleet.canTraverse(Minor)

    # Only military fleets can traverse restricted lanes
    check not mixedFleet.canTraverse(Restricted)
    check militaryFleet.canTraverse(Restricted)
    check not spaceliftFleet.canTraverse(Restricted)

  test "fleet convenience constructors":
    let milFleet = militaryFleet(3)
    let spaceFleet = spaceliftFleet(2)
    let mixed = mixedFleet(2, 1)

    check milFleet.len == 3
    check milFleet.combatStrength() == 3
    check milFleet.transportCapacity() == 0

    check spaceFleet.len == 2
    check spaceFleet.combatStrength() == 0
    check spaceFleet.transportCapacity() == 2

    check mixed.len == 3
    check mixed.combatStrength() == 2
    check mixed.transportCapacity() == 1

when isMainModule:
  echo "Running Fleet Tests..."
