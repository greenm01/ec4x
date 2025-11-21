## System Unit Tests
##
## Tests for star system properties and control

import unittest
import std/options
import ../../src/common/[hex, system]

suite "System Tests":
  test "system creation":
    let coords = hex(1, 2)
    let system = newSystem(coords, 2, 4, some(1u))

    check system.coords == coords
    check system.ring == 2
    check system.player.isSome
    check system.player.get == 1

  test "system control":
    var system = newSystem(hex(0, 0), 1, 4)

    check not system.isControlled()
    check not system.controlledBy(1)

    system.setController(1)
    check system.isControlled()
    check system.controlledBy(1)
    check not system.controlledBy(2)

    system.clearController()
    check not system.isControlled()

  test "system properties":
    let hubSystem = newSystem(hex(0, 0), 0, 4)
    let homeSystem = newSystem(hex(1, 0), 1, 4, some(1u))
    let neutralSystem = newSystem(hex(2, 0), 2, 4)

    check hubSystem.isHub()
    check hubSystem.isHomeSystem()
    check not homeSystem.isHomeSystem()  # Ring 1 is not a home system
    check not neutralSystem.isHomeSystem()

when isMainModule:
  echo "Running System Tests..."
