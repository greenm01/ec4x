## Planet Names Configuration Tests
##
## Tests for loading and assigning planet names from config/planets.kdl

import unittest
import std/strutils
import ../../src/engine/config/[starmap_config, engine]
import ../../src/engine/starmap
import ../../src/engine/init/game_state

let playerCount: int32 = 4
let seed: int64 = 99999

gameConfig = loadGameConfig("config")
gameSetup = loadGameSetup("scenarios/standard.kdl")

suite "Planet Names Config Tests":
  test "load planet names from config":
    # Load starmap config which includes planet names
    let config = gameConfig.starmap

    # Verify planet names were loaded
    check config.planetNames.names.len > 0
    check config.planetNames.names.len == 509

  test "planet names contain expected entries":
    let config = gameConfig.starmap

    # Check for some known names from the config
    check "Basil" in config.planetNames.names
    check "Athanasius" in config.planetNames.names
    check "Constantinople" in config.planetNames.names
    check "Nicaea" in config.planetNames.names

  test "assign names to starmap systems":
    # Generate a small starmap
    var map = initStarMap(playerCount, seed)

    # Load config with planet names
    let config = gameConfig.starmap

    # Assign names
    map.assignSystemNames(config.planetNames.names)

    # Verify all systems have names
    for system in map.systems.entities.data:
      check system.name.len > 0
      check system.name != ""

    # First system should have first name from pool
    check map.systems.entities.data[0].name == "Basil"

  test "assign names with empty pool falls back to System-ID":
    var map = initStarMap(playerCount, seed)

    # Assign with empty name pool
    let emptyPool: seq[string] = @[]
    map.assignSystemNames(emptyPool)

    # All systems should have fallback names
    for system in map.systems.entities.data:
      check system.name.len > 0
      check system.name.startsWith("System-")

  test "assign names when pool is exhausted":
    var map = initStarMap(playerCount, seed)
    let systemCount = map.systems.entities.data.len

    # Create a small name pool (smaller than system count)
    let smallPool = @["Alpha", "Beta", "Gamma"]
    map.assignSystemNames(smallPool)

    # First 3 should use pool names
    check map.systems.entities.data[0].name == "Alpha"
    check map.systems.entities.data[1].name == "Beta"
    check map.systems.entities.data[2].name == "Gamma"

    # Remaining should use fallback
    if systemCount > 3:
      check map.systems.entities.data[3].name.startsWith("System-")

when isMainModule:
  echo "Running Planet Names Config Tests..."
