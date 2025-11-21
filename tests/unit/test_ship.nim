## Ship Unit Tests
##
## Tests for ship types and capabilities

import unittest
import ../../src/engine/[ship, fleet]

suite "Ship Tests":
  test "ship creation":
    let military = newShip(Military)
    let spacelift = newShip(Spacelift)
    let crippledMil = newShip(Military, true)

    check military.shipType == Military
    check not military.isCrippled
    check spacelift.shipType == Spacelift
    check not spacelift.isCrippled
    check crippledMil.isCrippled

  test "ship capabilities":
    let military = militaryShip()
    let spacelift = spaceliftShip()
    let crippledMil = militaryShip(true)
    let crippledSpace = spaceliftShip(true)

    # Combat capability
    check military.isCombatCapable()
    check not spacelift.isCombatCapable()
    check not crippledMil.isCombatCapable()
    check not crippledSpace.isCombatCapable()

    # Transport capability
    check not military.canCarryTroops()
    check spacelift.canCarryTroops()
    check not crippledMil.canCarryTroops()
    check not crippledSpace.canCarryTroops()

    # Restricted lane traversal
    check military.canCrossRestrictedLane()
    check not spacelift.canCrossRestrictedLane()
    check not crippledMil.canCrossRestrictedLane()
    check not crippledSpace.canCrossRestrictedLane()

when isMainModule:
  echo "Running Ship Tests..."
