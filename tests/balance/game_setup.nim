## Game Setup Module for Balance Testing
##
## Creates balanced starting conditions for balance test scenarios
## Uses existing engine initialization functions

import std/[tables, options, random, strformat, sequtils, strutils, algorithm]
import ../../src/engine/[gamestate, starmap, fleet, squadron]
import ../../src/common/types/[core, units, planets, tech]
import ../../src/common/[hex, system]

export gamestate.initializeHouse, gamestate.createHomeColony
export squadron.createSquadron

proc generateBalancedStarMap*(numPlayers: int): StarMap =
  ## Generate a balanced star map for testing using the engine's StarMap
  result = newStarMap(numPlayers)

proc createStartingFleet*(owner: HouseId, location: SystemId): Fleet =
  ## Create a starting fleet with basic composition
  ## 1 squadron with 1 destroyer (per standard starting conditions)

  let squadron = createSquadron(
    shipClass = ShipClass.Destroyer,
    techLevel = 1,
    id = (&"{owner}_sq1").SquadronId,
    owner = owner,
    location = location,
    isCrippled = false
  )

  result = Fleet(
    id: (&"{owner}_fleet1").FleetId,
    owner: owner,
    location: location,
    squadrons: @[squadron]
  )

proc createBalancedGame*(numHouses: int, mapSize: int, seed: int64 = 42): GameState =
  ## Create a balanced game setup for testing
  ## All houses start with equal conditions at different map positions

  var rng = initRand(seed)

  # Generate star map with player starting positions
  var starMap = newStarMap(numHouses)
  starMap.populate()

  # Initialize empty game state
  result = GameState(
    gameId: "balance_test",
    turn: 1,
    year: 2400,
    month: 1,
    phase: GamePhase.Active,
    houses: initTable[HouseId, House](),
    colonies: initTable[SystemId, Colony](),
    fleets: initTable[FleetId, Fleet](),
    starMap: starMap,
    diplomacy: initTable[(HouseId, HouseId), DiplomaticState](),
    turnDeadline: 0,
    ongoingEffects: @[],
    spyScouts: initTable[string, SpyScout]()
  )

  # House names and colors
  const houseNames = ["Atreides", "Harkonnen", "Ordos", "Corrino",
                      "Vernius", "Moritani", "Richese"]
  const houseColors = ["blue", "red", "green", "gold",
                       "purple", "orange", "cyan"]

  # Create houses at player system positions
  for i in 0..<numHouses:
    let houseName = if i < houseNames.len: houseNames[i] else: &"House{i+1}"
    let houseColor = if i < houseColors.len: houseColors[i] else: "white"
    let houseId = (&"house-{houseName.toLower()}").HouseId

    # Initialize house with standard starting conditions
    result.houses[houseId] = initializeHouse(houseName, houseColor)

    # Get player's starting system from star map
    let homeSystemId = result.starMap.playerSystemIds[i]

    # Create home colony
    result.colonies[homeSystemId] = createHomeColony(homeSystemId, houseId)
    # BALANCE FIX: Enable auto-assign so new ships join fleets automatically
    result.colonies[homeSystemId].autoAssignFleets = true

    # Create starting fleet at homeworld
    result.fleets[(&"{houseId}_fleet1").FleetId] = createStartingFleet(
      houseId,
      homeSystemId
    )

  # Initialize diplomatic relations between all houses (all start neutral)
  let houseIds = toSeq(result.houses.keys)
  for i in 0..<houseIds.len:
    for j in (i+1)..<houseIds.len:
      let house1 = houseIds[i]
      let house2 = houseIds[j]
      result.diplomacy[(house1, house2)] = DiplomaticState.Neutral

proc printGameSetup*(game: GameState) =
  ## Print game setup summary for debugging
  echo &"\n{repeat(\"=\", 70)}"
  echo "Game Setup Summary"
  echo &"{repeat(\"=\", 70)}"
  echo &"Turn: {game.turn}, Year: {game.year}, Month: {game.month}"
  echo &"Houses: {game.houses.len}"
  echo &"Systems: {game.starMap.systems.len}"
  echo &"Colonies: {game.colonies.len}"
  echo &"Fleets: {game.fleets.len}"
  echo &"Diplomatic Relations: {game.diplomacy.len}"

  echo &"\n{repeat(\"=\", 70)}"
  echo "House Details"
  echo &"{repeat(\"=\", 70)}"

  for houseId in sorted(toSeq(game.houses.keys)):
    let house = game.houses[houseId]
    echo &"\n{house.name} ({houseId}):"
    echo &"  Color: {house.color}"
    echo &"  Prestige: {house.prestige}"
    echo &"  Treasury: {house.treasury} IU"
    echo &"  Tech Levels:"
    echo &"    EL: {house.techTree.levels.energyLevel}"
    echo &"    SL: {house.techTree.levels.shieldLevel}"
    echo &"    CST: {house.techTree.levels.constructionTech}"
    echo &"    WEP: {house.techTree.levels.weaponsTech}"

    # Find their colony
    for systemId, colony in game.colonies:
      if colony.owner == houseId:
        echo &"  Homeworld: {systemId}"
        echo &"    Population: {colony.population}M"
        echo &"    Infrastructure: {colony.infrastructure}"
        echo &"    Planet: {colony.planetClass}"
        echo &"    Resources: {colony.resources}"

    # Find their fleet
    for fleetId, fleet in game.fleets:
      if fleet.owner == houseId:
        let totalAS = fleet.squadrons.mapIt(it.combatStrength()).foldl(a + b, 0)
        echo &"  Fleet: {fleetId}"
        echo &"    Location: {fleet.location}"
        echo &"    Squadrons: {fleet.squadrons.len}"
        echo &"    Total AS: {totalAS}"

  echo &"\n{repeat(\"=\", 70)}"

when isMainModule:
  echo "Testing Game Setup Module"
  echo repeat("=", 70)
  echo ""

  # Test with 4 houses
  echo "Creating balanced game (4 houses)..."
  let game = createBalancedGame(4, 4)

  printGameSetup(game)

  echo "\n✓ Game setup complete!"
  echo "\nValidation:"
  echo &"  ✓ {game.houses.len} houses initialized"
  echo &"  ✓ {game.colonies.len} home colonies created"
  echo &"  ✓ {game.fleets.len} starting fleets created"
  echo &"  ✓ {game.diplomacy.len} diplomatic relations initialized"
  echo &"  ✓ {game.starMap.systems.len} star systems generated"

  # Verify each house has a homeworld and fleet
  for houseId in game.houses.keys:
    let hasColony = toSeq(game.colonies.values).anyIt(it.owner == houseId)
    let hasFleet = toSeq(game.fleets.values).anyIt(it.owner == houseId)
    if hasColony and hasFleet:
      echo &"  ✓ {houseId}: homeworld and fleet confirmed"
    else:
      echo &"  ✗ {houseId}: MISSING homeworld or fleet!"
