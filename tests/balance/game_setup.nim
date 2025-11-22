## Game Setup Module for Balance Testing
##
## Creates balanced starting conditions for balance test scenarios

import std/[tables, options, random, strformat]
import ../../src/engine/[gamestate, starmap, fleet, squadron, ship]
import ../../src/common/types/[core, units, planets, tech]
import ../../src/common/[hex, system]
import ../../src/engine/config/[gameplay_config, tech_config, prestige_config]
import ../../src/engine/research/types as res_types
import ../../src/engine/espionage/types as esp_types
import ../../src/engine/diplomacy/types as dip_types

proc createBalancedStartingHouse*(houseId: HouseId): House =
  ## Create a house with standard starting conditions
  result = House(
    id: houseId,
    name: $houseId,
    color: "blue",
    eliminated: false,
    treasury: 1000,  # Starting funds
    prestige: globalPrestigeConfig.victory.starting_prestige,
    techTree: res_types.initTechTree(),
    negativePrestigeTurns: 0,
    diplomaticRelations: dip_types.DiplomaticRelations(
      relations: initTable[HouseId, dip_types.DiplomaticState]()
    ),
    violationHistory: dip_types.ViolationHistory(
      violations: initTable[HouseId, seq[dip_types.PactViolation]]()
    ),
    espionageBudget: esp_types.EspionageBudget(
      ebp: 0,
      cip: 0
    ),
    dishonoredStatus: dip_types.DishonoredStatus(
      active: false,
      turnsRemaining: 0
    ),
    diplomaticIsolation: dip_types.DiplomaticIsolation(
      active: false,
      turnsRemaining: 0
    ),
    planetBreakerCount: 0
  )

proc createStartingColony*(systemId: SystemId, owner: HouseId,
                          planetClass: PlanetClass): Colony =
  ## Create a starting colony with basic infrastructure
  result = Colony(
    systemId: systemId,
    owner: owner,
    populationUnits: 50,  # 50 million starting population
    industrial: IndustrialUnits(units: 25),  # 50% industrial capacity
    planetClass: planetClass,
    resources: ResourceRating.Average,
    production: 0,
    underConstruction: none(ConstructionProject),
    fighterSquadrons: @[],
    capacityViolation: CapacityViolation(
      active: false,
      violationType: "",
      turnsRemaining: 0,
      violationTurn: 0
    ),
    starbases: @[],
    spaceports: @[],
    shipyards: @[],
    planetaryShieldLevel: 0,
    groundBatteries: 0,
    armies: 5,  # Starting defense
    marines: 0,
    blockaded: false,
    blockadedBy: @[],
    blockadeTurns: 0
  )

proc createStartingFleet*(owner: HouseId, location: SystemId,
                         fleetId: FleetId): Fleet =
  ## Create a starting fleet with basic ships
  var squadrons: seq[Squadron] = @[]

  # Create starting squadron (3 Frigates)
  let frigate = Ship(
    class: ShipClass.Frigate,
    stats: ShipStats(
      attackStrength: 2,
      defensiveStrength: 1,
      hullPoints: 2,
      armor: 0,
      shields: 0,
      size: 1,
      cargo: 0,
      fighterCapacity: 0
    ),
    isCrippled: false
  )

  squadrons.add(Squadron(
    id: &"{fleetId}_sq1",
    flagship: frigate,
    escorts: @[frigate, frigate],  # 3 ships total
    combinedStats: CombinedStats(
      totalAS: 6,
      totalDS: 3,
      totalHP: 6
    )
  ))

  result = Fleet(
    id: fleetId,
    owner: owner,
    location: location,
    squadrons: squadrons
  )

proc generateStarMap*(numSystems: int, rng: var Rand): Table[SystemId, StarSystem] =
  ## Generate a simple star map for testing
  result = initTable[SystemId, StarSystem]()

  for i in 0..<numSystems:
    let systemId = (&"System{i+1}").SystemId
    let position = Hex(q: int32(i mod 8), r: int32(i div 8))

    # Vary planet classes
    let planetClass = case i mod 7
      of 0: PlanetClass.Ideal
      of 1: PlanetClass.Normal
      of 2: PlanetClass.Desert
      of 3: PlanetClass.Tundra
      of 4: PlanetClass.Oceanic
      of 5: PlanetClass.Hostile
      else: PlanetClass.Barren

    result[systemId] = StarSystem(
      id: systemId,
      position: position,
      planetClass: planetClass,
      resources: ResourceRating.Average,
      hasColony: false,
      controlledBy: none(HouseId)
    )

proc createBalancedGame*(numHouses: int, mapSize: int): GameState =
  ## Create a balanced game setup for testing
  var rng = initRand(42)  # Deterministic for reproducibility

  result = GameState(
    turn: 1,
    year: 2400,
    month: 1,
    houses: initTable[HouseId, House](),
    colonies: initTable[SystemId, Colony](),
    fleets: initTable[FleetId, Fleet](),
    systems: generateStarMap(mapSize, rng),
    ongoingEffects: initTable[HouseId, seq[OngoingEffect]](),
    diplomaticRelations: initTable[tuple[house1, house2: HouseId], DiplomaticRelation]()
  )

  # Create houses and assign starting positions
  for i in 0..<numHouses:
    let houseId = (&"House{i+1}").HouseId
    result.houses[houseId] = createBalancedStartingHouse(houseId)

    # Assign home system (evenly spaced)
    let homeSystemIdx = (i * (mapSize div numHouses))
    let homeSystemId = (&"System{homeSystemIdx+1}").SystemId

    # Create home colony
    let homeColony = createStartingColony(
      homeSystemId,
      houseId,
      PlanetClass.Normal
    )
    result.colonies[homeSystemId] = homeColony
    result.systems[homeSystemId].hasColony = true
    result.systems[homeSystemId].controlledBy = some(houseId)

    # Create starting fleet at home
    let fleetId = (&"{houseId}_Fleet1").FleetId
    result.fleets[fleetId] = createStartingFleet(
      houseId,
      homeSystemId,
      fleetId
    )

    # Initialize ongoing effects
    result.ongoingEffects[houseId] = @[]

  # Initialize diplomatic relations (all neutral)
  for i in 0..<numHouses:
    for j in (i+1)..<numHouses:
      let house1 = (&"House{i+1}").HouseId
      let house2 = (&"House{j+1}").HouseId
      result.diplomaticRelations[(house1, house2)] = DiplomaticRelation(
        house1: house1,
        house2: house2,
        state: DiplomaticState.Neutral,
        pactTurn: none(int),
        dishonorTurns: 0,
        isolationTurns: 0
      )

when isMainModule:
  echo "Testing game setup..."
  let game = createBalancedGame(4, 20)

  echo &"Created game with {game.houses.len} houses"
  echo &"Map size: {game.systems.len} systems"
  echo &"Colonies: {game.colonies.len}"
  echo &"Fleets: {game.fleets.len}"

  for houseId, house in game.houses:
    echo &"\n{houseId}:"
    echo &"  Prestige: {house.prestige}"
    echo &"  Treasury: {house.treasury}"
    echo &"  Tech EL: {house.techTree.levels.energyLevel}"

  echo "\nGame setup complete!"
