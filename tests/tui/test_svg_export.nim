## Integration test: SVG starmap export
##
## Generates an SVG from a real game state to verify the export works.

import std/[unittest, strutils, os]
import ../../src/engine/init/game_state
import ../../src/engine/types/core
import ../../src/player/svg/svg_pkg

suite "SVG Starmap Export":

  test "generates valid SVG from game state":
    # Create a game
    let state = initGameState(
      setupPath = "scenarios/standard-4-player.kdl",
      gameName = "SVG Test Game",
      configDir = "config",
      dataDir = "data"
    )
    
    # Generate SVG for house 1
    let svg = generateStarmap(state, HouseId(1))
    
    # Basic structure checks
    check "<?xml" in svg
    check "<svg" in svg
    check "</svg>" in svg
    
    # Background rect
    check "<rect id=\"background\"" in svg
    check "fill=\"#000000\"" in svg
    
    # Nodes group
    check "<g id=\"nodes\">" in svg
    check "<circle" in svg
    
    # Labels group  
    check "<g id=\"labels\">" in svg
    check "<text" in svg
    
    # Lanes group
    check "<g id=\"lanes\">" in svg
    check "<line" in svg
    
    # Legend
    check "<g id=\"legend\"" in svg
    check "LEGEND" in svg

  test "SVG contains planet-resource codes inside nodes":
    let state = initGameState(
      setupPath = "scenarios/standard-4-player.kdl",
      gameName = "SVG Code Test",
      configDir = "config",
      dataDir = "data"
    )
    
    let svg = generateStarmap(state, HouseId(1))
    
    # Should have label-inside class for text in circles
    check "label-inside" in svg
    
    # Should have planet-resource codes like "HO-A", "BE-R", etc.
    # Check for at least one code pattern (2 letters, dash, 1-2 letters)
    var foundCode = false
    for code in ["EX-", "DE-", "HO-", "HA-", "BE-", "LU-", "ED-"]:
      if code in svg:
        foundCode = true
        break
    check foundCode

  test "SVG export size is reasonable":
    let state = initGameState(
      setupPath = "scenarios/standard-4-player.kdl",
      gameName = "SVG Size Test",
      configDir = "config",
      dataDir = "data"
    )
    
    let svg = generateStarmap(state, HouseId(1))
    
    # Should be between 20KB and 200KB for a 61-system map
    check svg.len > 20_000
    check svg.len < 200_000

  test "SVG can be written to file":
    let state = initGameState(
      setupPath = "scenarios/standard-4-player.kdl",
      gameName = "SVG File Test",
      configDir = "config",
      dataDir = "data"
    )
    
    let svg = generateStarmap(state, HouseId(1))
    let testPath = "/tmp/ec4x_test_starmap.svg"
    
    writeFile(testPath, svg)
    check fileExists(testPath)
    
    let readBack = readFile(testPath)
    check readBack == svg
    
    # Cleanup
    removeFile(testPath)
