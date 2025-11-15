## Game creation module for EC4X moderator
##
## This module handles the creation of new EC4X games, including
## star map generation, system setup, and initial game state.

import std/[os, strutils, sequtils, tables, options]
import ../../core
import config

type
  GameCreationError* = object of CatchableError

proc ensureGameDirectory*(path: string): bool =
  ## Ensure the game directory exists and is writable
  try:
    if not dirExists(path):
      createDir(path)

    # Test write permissions
    let testFile = path / "test_write.tmp"
    writeFile(testFile, "test")
    removeFile(testFile)

    return true
  except OSError:
    return false

proc generateStarMap*(playerCount: int): StarMap =
  ## Generate a complete star map for the given number of players
  echo "Generating star map for ", playerCount, " players..."

  result = starMap(playerCount)

  echo "Generated ", result.systems.len, " star systems"
  echo "Generated ", result.lanes.len, " jump lanes"

  # Verify connectivity
  let playerSystems = toSeq(result.systems.values).filterIt(it.player.isSome)
  echo "Player home systems: ", playerSystems.len

  for system in playerSystems:
    let playerId = system.player.get
    echo "Player ", playerId, " home system: ", system.id, " at ", system.coords

proc saveGameState*(gamePath: string, starMap: StarMap, config: Config) =
  ## Save the initial game state to files
  let gameDataPath = gamePath / "game_data"
  if not dirExists(gameDataPath):
    createDir(gameDataPath)

  # Save star map data (simplified - in a real implementation you'd use proper serialization)
  let systemsFile = gameDataPath / "systems.txt"
  var systemsData = ""
  for system in starMap.systems.values:
    let playerStr = if system.player.isSome: $system.player.get else: "none"
    systemsData.add($system.id & "," & $system.coords.q & "," & $system.coords.r & "," &
                    $system.ring & "," & playerStr & "\n")
  writeFile(systemsFile, systemsData)

  # Save lanes data
  let lanesFile = gameDataPath / "lanes.txt"
  var lanesData = ""
  for lane in starMap.lanes:
    lanesData.add($lane.source & "," & $lane.destination & "," & $lane.laneType & "\n")
  writeFile(lanesFile, lanesData)

  echo "Game state saved to: ", gameDataPath

proc createInitialFleets*(starMap: StarMap): Table[uint, seq[Fleet]] =
  ## Create initial fleets for each player
  result = initTable[uint, seq[Fleet]]()

  for system in starMap.systems.values:
    if system.player.isSome:
      let playerId = system.player.get
      let homeFleet = mixedFleet(2, 1)  # 2 military, 1 spacelift

      if playerId notin result:
        result[playerId] = @[]
      result[playerId].add(homeFleet)

      echo "Created initial fleet for Player ", playerId, ": ", homeFleet

proc printGameSummary*(starMap: StarMap, config: Config) =
  ## Print a summary of the created game
  echo "\n" & "=".repeat(50)
  echo "EC4X GAME CREATION SUMMARY"
  echo "=".repeat(50)
  echo "Game Name: ", config.gameName
  echo "Host: ", config.hostName
  echo "Players: ", config.numEmpires
  echo "Systems: ", starMap.systems.len
  echo "Jump Lanes: ", starMap.lanes.len
  echo "Map Rings: ", starMap.numRings
  echo "Hub System ID: ", starMap.hubId

  # Show ring distribution
  var ringCounts = initTable[uint32, int]()
  for system in starMap.systems.values:
    if system.ring in ringCounts:
      ringCounts[system.ring].inc
    else:
      ringCounts[system.ring] = 1

  echo "\nSystems by Ring:"
  for ring in 0..starMap.numRings:
    let count = if ring in ringCounts: ringCounts[ring] else: 0
    echo "  Ring ", ring, ": ", count, " systems"

  echo "\nPlayer Home Systems:"
  for system in starMap.systems.values:
    if system.player.isSome:
      echo "  Player ", system.player.get, ": System ", system.id, " at ", system.coords

  echo "=".repeat(50)

proc testConnectivity*(starMap: StarMap): bool =
  ## Test if all player systems are connected
  let playerSystems = toSeq(starMap.systems.values).filterIt(it.player.isSome)
  if playerSystems.len < 2:
    return true

  # Simple connectivity test - check if we can find paths between first two players
  let system1 = playerSystems[0]
  let system2 = playerSystems[1]

  # For now, just check if they have adjacent systems (simplified)
  let adjacent1 = starMap.getAdjacentSystems(system1.id)
  let adjacent2 = starMap.getAdjacentSystems(system2.id)

  echo "Connectivity test: Player 0 has ", adjacent1.len, " adjacent systems"
  echo "Connectivity test: Player 1 has ", adjacent2.len, " adjacent systems"

  return adjacent1.len > 0 and adjacent2.len > 0

proc newGame*(gamePath: string): bool =
  ## Create a new EC4X game in the specified directory
  try:
    echo "\n" & "#".repeat(50)
    echo "##### Creating New EC4X Game #####"
    echo "#".repeat(50)

    # Ensure game directory exists
    if not ensureGameDirectory(gamePath):
      raise newException(GameCreationError, "Cannot create or access game directory: " & gamePath)

    # Load or create configuration
    var config: Config
    let configPath = gamePath / CONFIG_FILE

    if fileExists(configPath):
      config = loadConfig(gamePath)
    else:
      echo "No configuration file found, creating default..."
      config = createDefaultConfig(gamePath)

    if not validateConfig(config):
      raise newException(GameCreationError, "Invalid configuration")

    # Generate star map
    let starMap = generateStarMap(config.numEmpires.int)

    # Test connectivity
    if not testConnectivity(starMap):
      echo "Warning: Connectivity test failed"

    # Create initial fleets
    let initialFleets = createInitialFleets(starMap)
    echo "Created initial fleets for ", initialFleets.len, " players"

    # Save game state
    saveGameState(gamePath, starMap, config)

    # Print summary
    printGameSummary(starMap, config)

    echo "\nGame creation completed successfully!"
    echo "Game directory: ", gamePath

    return true

  except Exception as e:
    echo "Error creating game: ", e.msg
    return false

proc genStarMap*(): bool =
  ## Generate a test star map (for development/testing)
  try:
    echo "Generating test star map..."
    let playerCount = 3
    let starMap = starMap(playerCount)

    # Create a test fleet
    let fleet = fleet(militaryShip(), spaceliftShip())
    echo "Created test fleet: ", fleet

    # Find player home systems
    let player0HomeSystems = starMap.playerSystems(0)
    if player0HomeSystems.len > 0:
      echo "Player 0 home system: ", player0HomeSystems[0]

    let player1HomeSystems = starMap.playerSystems(1)
    if player1HomeSystems.len > 0:
      echo "Player 1 home system: ", player1HomeSystems[0]

    # Print all systems for verification
    echo "\nAll Systems:"
    for system in starMap.systems.values:
      let adjacentIds = starMap.getAdjacentSystems(system.id)
      echo "ID: ", system.id, ", Coords: ", system.coords, ", Ring: ", system.ring,
           ", Player: ", system.player, ", Adjacent: ", adjacentIds.len

    # Test pathfinding
    echo "\nTesting pathfinding..."
    let player0PathSystems = starMap.playerSystems(0)
    let player1PathSystems = starMap.playerSystems(1)

    if player0PathSystems.len > 0 and player1PathSystems.len > 0:
      let start = player0PathSystems[0]
      let goal = player1PathSystems[0]
      let testFleet = fleet(militaryShip(), spaceliftShip())

      echo "Testing path from Player 0 to Player 1..."
      let pathResult = findPath(starMap, start.id, goal.id, testFleet)

      if pathResult.found:
        echo "Path found! Length: ", pathResult.path.len, " systems"
        echo "Total cost: ", pathResult.totalCost
        echo "Path: ", pathResult.path.mapIt($it).join(" -> ")
      else:
        echo "No path found between players"

      # Test reachability
      echo "Testing reachability..."
      let reachable = isReachable(starMap, start.id, goal.id, testFleet)
      echo "Systems reachable: ", reachable

      # Test movement range
      echo "Testing movement range from Player 0 home..."
      let range = findPathsInRange(starMap, start.id, 3, testFleet)
      echo "Systems within range 3: ", range.len

    echo "\nStar map generation test completed successfully!"
    return true

  except Exception as e:
    echo "Error in star map generation: ", e.msg
    return false
