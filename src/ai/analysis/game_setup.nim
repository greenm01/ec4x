## Game Setup Module for Balance Testing
##
## Creates balanced starting conditions for balance test scenarios
## Uses existing engine initialization functions

import std/[tables, strformat, sequtils, strutils, algorithm]
import ../../engine/[gamestate, starmap, fleet, squadron, spacelift]
import ../../engine/config/[prestige_multiplier, house_themes, gameplay_config]
import ../../common/types/[core, units, planets, tech]
import ../../common/[system]

export gamestate.initializeHouse, gamestate.createHomeColony
export squadron.createSquadron

proc generateBalancedStarMap*(numPlayers: int): StarMap =
  ## Generate a balanced star map for testing using the engine's StarMap
  result = newStarMap(numPlayers)

proc createStartingFleets*(owner: HouseId, location: SystemId): seq[Fleet] =
  ## Create starting fleets matching original EC
  ## Original EC: 2 fleets (ETAC+Cruiser), 2 fleets (Destroyer)
  result = @[]

  # Fleet 1: ETAC + Light Cruiser
  let cruiser1 = createSquadron(
    shipClass = ShipClass.LightCruiser,
    techLevel = 1,
    id = (&"{owner}_cruiser_sq1").SquadronId,
    owner = owner,
    location = location,
    isCrippled = false
  )
  var etac1 = newSpaceLiftShip(
    id = &"{owner}_ETAC_1",
    shipClass = ShipClass.ETAC,
    owner = owner,
    location = location
  )
  # Load starting PTU for colonization
  etac1.cargo.cargoType = CargoType.Colonists
  etac1.cargo.quantity = 1
  result.add(Fleet(
    id: (&"{owner}_fleet1").FleetId,
    owner: owner,
    location: location,
    squadrons: @[cruiser1],
    spaceLiftShips: @[etac1]
  ))

  # Fleet 2: ETAC + Light Cruiser
  let cruiser2 = createSquadron(
    shipClass = ShipClass.LightCruiser,
    techLevel = 1,
    id = (&"{owner}_cruiser_sq2").SquadronId,
    owner = owner,
    location = location,
    isCrippled = false
  )
  var etac2 = newSpaceLiftShip(
    id = &"{owner}_ETAC_2",
    shipClass = ShipClass.ETAC,
    owner = owner,
    location = location
  )
  # Load starting PTU for colonization
  etac2.cargo.cargoType = CargoType.Colonists
  etac2.cargo.quantity = 1
  result.add(Fleet(
    id: (&"{owner}_fleet2").FleetId,
    owner: owner,
    location: location,
    squadrons: @[cruiser2],
    spaceLiftShips: @[etac2]
  ))

  # Fleet 3: Destroyer
  let destroyer1 = createSquadron(
    shipClass = ShipClass.Destroyer,
    techLevel = 1,
    id = (&"{owner}_destroyer_sq1").SquadronId,
    owner = owner,
    location = location,
    isCrippled = false
  )
  result.add(Fleet(
    id: (&"{owner}_fleet3").FleetId,
    owner: owner,
    location: location,
    squadrons: @[destroyer1],
    spaceLiftShips: @[]
  ))

  # Fleet 4: Destroyer
  let destroyer2 = createSquadron(
    shipClass = ShipClass.Destroyer,
    techLevel = 1,
    id = (&"{owner}_destroyer_sq2").SquadronId,
    owner = owner,
    location = location,
    isCrippled = false
  )
  result.add(Fleet(
    id: (&"{owner}_fleet4").FleetId,
    owner: owner,
    location: location,
    squadrons: @[destroyer2],
    spaceLiftShips: @[]
  ))

proc createBalancedGame*(numHouses: int, mapSize: int, seed: int64 = 42): GameState =
  ## Create a balanced game setup for testing
  ## All houses start with equal conditions at different map positions
  ## mapSize parameter controls number of rings (systems = roughly 3 × rings²)

  # Generate star map with player starting positions
  var starMap = newStarMap(numHouses, seed)
  # Override numRings based on mapSize parameter
  starMap.numRings = mapSize.uint32
  starMap.populate()

  # Initialize dynamic prestige multiplier based on map size
  initializePrestigeMultiplier(starMap.systems.len, numHouses)

  # Load house theme configuration from global gameplay config
  let activeThemeName = globalGameplayConfig.theme.active_theme
  let themeConfig = loadThemeConfig(activeThemeName = activeThemeName)
  let activeTheme = getActiveTheme(themeConfig)

  # DIAGNOSTIC: Test if specific map positions are inherently advantageous
  # Rotate house-to-position mapping by seed to test all position combinations
  # This will reveal if corrino's dominance is position-based or something else
  let positionRotation = int(seed mod numHouses.int64)
  var houseOrder = toSeq(0..<numHouses)
  # Rotate the array by positionRotation positions
  houseOrder = houseOrder[positionRotation..^1] & houseOrder[0..<positionRotation]

  # Initialize empty game state
  result = GameState(
    gameId: "balance_test",
    turn: 1,
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

  # Create houses at player system positions using active theme
  for i in 0..<numHouses:
    let houseName = getHouseName(activeTheme, i)
    let houseColor = getHouseColor(activeTheme, i)
    let houseId = (&"house-{houseName.toLower()}").HouseId

    # Initialize house with standard starting conditions
    result.houses[houseId] = initializeHouse(houseName, houseColor)

    # BALANCE FIX: Use randomized mapping instead of direct index
    # houseOrder[i] gives this house's randomized position in the player system list
    let positionIndex = houseOrder[i]
    let homeSystemId = result.starMap.playerSystemIds[positionIndex]

    # Create home colony
    result.colonies[homeSystemId] = createHomeColony(homeSystemId, houseId)

    # BALANCE FIX: Normalize starting system quality to ensure fairness
    # Override procedural generation to give all players identical starting conditions
    result.starMap.systems[homeSystemId].planetClass = PlanetClass.Eden
    result.starMap.systems[homeSystemId].resourceRating = ResourceRating.Abundant

    # NOTE: Auto-assignment is ALWAYS enabled (no field needed per gamestate.nim:100)

    # Add starting facilities (spaceport for ETACs, shipyard for military)
    result.colonies[homeSystemId].spaceports.add(Spaceport(
      id: $homeSystemId & "_spaceport1",
      commissionedTurn: 1,
      docks: 5
    ))
    result.colonies[homeSystemId].shipyards.add(Shipyard(
      id: $homeSystemId & "_shipyard1",
      commissionedTurn: 1,
      docks: 10,
      isCrippled: false
    ))

    # Create starting fleets at homeworld (4 fleets matching original EC)
    let startingFleets = createStartingFleets(houseId, homeSystemId)
    for fleet in startingFleets:
      result.fleets[fleet.id] = fleet

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
  echo &"Strategic Cycle: {game.turn}"
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
    echo &"    EL: {house.techTree.levels.economicLevel}"
    echo &"    SL: {house.techTree.levels.scienceLevel}"
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
