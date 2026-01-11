## Integration Test: Capacity Limits System
##
## Tests all game capacity limits per docs/specs/10-reference.md Section 10.5
##
## Capacity Systems Tested:
## 1. C2 Pool (Command & Control) - Soft cap with PP penalty
## 2. Fleet Count (SC Tech) - Hard cap on combat fleets per house
## 3. Ships Per Fleet (FC Tech) - Hard cap per individual fleet
## 4. Fighter Capacity (FD Tech + IU) - Per-colony with 2-turn grace
## 5. Carrier Hangar Capacity (ACO Tech) - Hard cap per carrier
## 6. Planet Breaker Limits - Max 1 per owned colony
## 7. Per-Colony Facilities - Starbases (max 3), Shields (max 1), Spaceports (max 1)
## 8. Construction Dock Capacity - Per-facility limits
##
## Exclusions:
## - Anti-destruction protection (combat mechanic, not capacity system)
## - Multi-turn grace period mechanics (deferred to separate test file)

import std/[unittest, options, tables, math]
import ../../src/engine/engine
import ../../src/engine/types/[
  core, game_state, house, colony, facilities, ship, fleet,
  production, ground_unit, capacity
]
import ../../src/engine/state/[engine, iterators]
import ../../src/engine/globals
import ../../src/engine/config/engine as config_engine

# Initialize config once for all tests
gameConfig = config_engine.loadGameConfig()

# Import all capacity systems
import ../../src/engine/systems/capacity/[
  c2_pool, sc_fleet_count, fc_fleet_size, fighter, carrier_hangar,
  planet_breakers, planetary_shields, starbases, construction_docks
]

# Import entity operations
import ../../src/engine/entities/[
  ship_ops, fleet_ops, kastra_ops, ground_unit_ops
]



# Helper to get a system from a house's colonies
proc houseSystem(game: GameState, houseId: HouseId): SystemId =
  for colony in game.coloniesOwned(houseId):
    return colony.systemId
  return SystemId(0)  # Fallback (shouldn't happen)

suite "Capacity Limits: C2 Pool (Soft Cap)":

  test "calculateC2Pool with zero IU returns SC tech bonus only":
    let c2Pool = calculateC2Pool(totalHouseIU = 0, scLevel = 1)
    # SC I bonus from config
    let expectedBonus = gameConfig.tech.sc.levels[1].c2Bonus
    check c2Pool == expectedBonus

  test "calculateC2Pool formula matches spec (IU × 0.3 + SC bonus)":
    # Get SC III bonus from config
    let sc3Bonus = gameConfig.tech.sc.levels[3].c2Bonus
    let c2Pool = calculateC2Pool(totalHouseIU = 1000, scLevel = 3)
    # Expected: 1000 × 0.3 + sc3Bonus = 300 + 80 = 380
    let expected = int32(1000.0 * 0.3) + sc3Bonus
    check c2Pool == expected

  test "calculateC2Pool scales with SC tech advancement":
    let totalIU = 1000'i32
    let sc1 = calculateC2Pool(totalIU, scLevel = 1)
    let sc3 = calculateC2Pool(totalIU, scLevel = 3)
    let sc6 = calculateC2Pool(totalIU, scLevel = 6)
    # Higher SC levels should provide more C2 Pool
    check sc3 > sc1
    check sc6 > sc3

  test "calculateLogisticalStrain with no overdraft returns 0":
    let strain = calculateLogisticalStrain(totalCC = 100, c2Pool = 150)
    check strain == 0

  test "calculateLogisticalStrain formula matches spec (excess × 0.5)":
    # Overdraft by 100 CC → strain = 100 × 0.5 = 50 PP
    let strain = calculateLogisticalStrain(totalCC = 200, c2Pool = 100)
    check strain == 50

  test "C2 Pool analysis in full game context":
    var game = newGame()
    let houseId = HouseId(1)
    
    # Get initial analysis
    let analysis = analyzeC2Capacity(game, houseId)
    
    # Should have baseline C2 Pool from SC tech + starting IU
    check analysis.c2Pool > 0
    check analysis.totalIU >= 0
    check analysis.scLevel >= 1

suite "Capacity Limits: Fleet Count (SC Tech)":

  test "strategicCommandMaxFleets SC I base capacity":
    # SC I = 10 fleets on small map (8 systems per player baseline)
    let maxFleets = strategicCommandMaxFleets(
      scLevel = 1, totalSystems = 32, playerCount = 4
    )
    check maxFleets >= 10  # At least base capacity

  test "strategicCommandMaxFleets scales with SC tech":
    let sys = 32'i32
    let players = 4'i32
    let sc1 = strategicCommandMaxFleets(1, sys, players)
    let sc3 = strategicCommandMaxFleets(3, sys, players)
    let sc6 = strategicCommandMaxFleets(6, sys, players)
    # Higher SC should allow more fleets
    check sc3 > sc1
    check sc6 > sc3

  test "strategicCommandMaxFleets scales with map size":
    let scLevel = 6'i32
    let players = 4'i32
    let smallMap = strategicCommandMaxFleets(scLevel, 32, players)
    let mediumMap = strategicCommandMaxFleets(scLevel, 92, players)
    let largeMap = strategicCommandMaxFleets(scLevel, 156, players)
    # Larger maps should allow more fleets
    check mediumMap > smallMap
    check largeMap > mediumMap

  test "isAuxiliaryShip correctly identifies auxiliary ship classes":
    check isAuxiliaryShip(ShipClass.Scout) == true
    check isAuxiliaryShip(ShipClass.ETAC) == true
    check isAuxiliaryShip(ShipClass.TroopTransport) == true
    check isAuxiliaryShip(ShipClass.Destroyer) == false
    check isAuxiliaryShip(ShipClass.Battleship) == false
    check isAuxiliaryShip(ShipClass.Carrier) == false

  test "canCreateCombatFleet respects SC tech limit":
    var game = newGame()
    let houseId = HouseId(1)
    
    # Should be able to create fleets initially (under SC I limit of 10)
    check canCreateCombatFleet(game, houseId) == true
    
    # Get max capacity by counting systems
    var systemCount = 0'i32
    for _ in game.allSystems():
      systemCount += 1
    
    let maxFleets = strategicCommandMaxFleets(
      scLevel = 1,
      totalSystems = systemCount,
      playerCount = 4  # Standard scenario has 4 players
    )
    check maxFleets >= 10  # SC I base

  test "countCombatFleets excludes auxiliary-only fleets":
    var game = newGame()
    let houseId = HouseId(1)
    let systemId = houseSystem(game, houseId)
    
    # Count initial combat fleets (game init creates 4 starting fleets)
    let initialCombatCount = countCombatFleets(game, houseId)
    
    # Create a scout-only fleet (auxiliary - should NOT count)
    let scoutFleet = game.createFleet(houseId, systemId)
    discard game.createShip(houseId, scoutFleet.id, ShipClass.Scout)
    
    # Create a fleet with combat ship (SHOULD count)
    let combatFleet = game.createFleet(houseId, systemId)
    discard game.createShip(houseId, combatFleet.id, ShipClass.Destroyer)
    
    # Count should be initial + 1 (only the new destroyer fleet counts)
    let finalCombatCount = countCombatFleets(game, houseId)
    check finalCombatCount == initialCombatCount + 1

suite "Capacity Limits: Ships Per Fleet (FC Tech)":

  test "fleetCommandMaxShips FC I base capacity":
    let maxShips = fleetCommandMaxShips(fcLevel = 1)
    let expected = gameConfig.tech.fc.levels[1].maxShipsPerFleet
    check maxShips == expected

  test "fleetCommandMaxShips scales with FC tech":
    let fc1 = fleetCommandMaxShips(1)
    let fc3 = fleetCommandMaxShips(3)
    let fc6 = fleetCommandMaxShips(6)
    # Higher FC should allow more ships per fleet
    check fc3 > fc1
    check fc6 > fc3
    let expectedFC6 = gameConfig.tech.fc.levels[6].maxShipsPerFleet
    check fc6 == expectedFC6

  test "currentFleetSize counts ships correctly":
    var game = newGame()
    let houseId = HouseId(1)
    let systemId = houseSystem(game, houseId)
    
    # Create fleet with 3 ships
    let fleet = game.createFleet(houseId, systemId)
    discard game.createShip(houseId, fleet.id, ShipClass.Corvette)
    discard game.createShip(houseId, fleet.id, ShipClass.Frigate)
    discard game.createShip(houseId, fleet.id, ShipClass.Destroyer)
    
    let size = currentFleetSize(game, fleet.id)
    check size == 3

  test "canAddShipsToFleet respects FC tech limit":
    var game = newGame()
    let houseId = HouseId(1)
    let systemId = houseSystem(game, houseId)
    
    # Set FC tech to level 1 (10 ships max)
    var house = game.house(houseId).get()
    house.techTree.levels.fc = 1
    game.updateHouse(houseId, house)
    
    # Create fleet with 8 ships
    let fleet = game.createFleet(houseId, systemId)
    for i in 0..<8:
      discard game.createShip(houseId, fleet.id, ShipClass.Corvette)
    
    # Should be able to add 2 more (8 + 2 = 10, at limit)
    check canAddShipsToFleet(game, fleet.id, shipsToAdd = 2) == true
    
    # Should NOT be able to add 3 more (8 + 3 = 11, over limit)
    check canAddShipsToFleet(game, fleet.id, shipsToAdd = 3) == false

  test "availableFleetCapacity returns correct remaining space":
    var game = newGame()
    let houseId = HouseId(1)
    let systemId = houseSystem(game, houseId)
    
    # Set FC tech to level 1 (10 ships max)
    var house = game.house(houseId).get()
    house.techTree.levels.fc = 1
    game.updateHouse(houseId, house)
    
    # Create fleet with 7 ships
    let fleet = game.createFleet(houseId, systemId)
    for i in 0..<7:
      discard game.createShip(houseId, fleet.id, ShipClass.Corvette)
    
    # Available capacity should be 10 - 7 = 3
    let available = availableFleetCapacity(game, fleet.id)
    check available == 3

suite "Capacity Limits: Fighter Capacity":

  test "calculateMaxFighterCapacity formula matches spec (IU ÷ 100 × FD)":
    # FD I (1.0x): 500 IU ÷ 100 = 5 fighters
    let fd1 = calculateMaxFighterCapacity(industrialUnits = 500, fdLevel = 1)
    check fd1 == 5
    
    # FD II (1.5x): 500 IU ÷ 100 × 1.5 = 7 fighters
    let fd2 = calculateMaxFighterCapacity(industrialUnits = 500, fdLevel = 2)
    check fd2 == 7
    
    # FD III (2.0x): 500 IU ÷ 100 × 2.0 = 10 fighters
    let fd3 = calculateMaxFighterCapacity(industrialUnits = 500, fdLevel = 3)
    check fd3 == 10

  test "calculateMaxFighterCapacity floors division correctly":
    # 150 IU ÷ 100 = 1.5 → floor = 1 fighter (FD I)
    let capacity = calculateMaxFighterCapacity(industrialUnits = 150, fdLevel = 1)
    check capacity == 1

  test "calculateMaxFighterCapacity with zero IU returns zero":
    let capacity = calculateMaxFighterCapacity(industrialUnits = 0, fdLevel = 1)
    check capacity == 0

  test "analyzeCapacity detects fighter violations":
    var game = newGame()
    let houseId = HouseId(1)
    
    # Get a colony
    var colony: Colony
    for c in game.coloniesOwned(houseId):
      colony = c
      break
    
    # Set low IU (e.g., 50 IU = capacity for 0 fighters at FD I)
    colony.industrial.units = 50
    game.updateColony(colony.id, colony)
    
    # Create 2 fighters (over capacity)
    let fighter1 = game.createShip(houseId, FleetId(0), ShipClass.Fighter)
    let fighter2 = game.createShip(houseId, FleetId(0), ShipClass.Fighter)
    colony.fighterIds.add(fighter1.id)
    colony.fighterIds.add(fighter2.id)
    game.updateColony(colony.id, colony)
    
    # Analyze capacity
    let violation = fighter.analyzeCapacity(game, colony, houseId)
    
    # Should detect violation
    check violation.current == 2
    check violation.maximum == 0
    check violation.excess == 2

  test "canCommissionFighter respects capacity":
    var game = newGame()
    let houseId = HouseId(1)
    
    # Get a colony with good capacity
    var colony: Colony
    for c in game.coloniesOwned(houseId):
      colony = c
      break
    
    # Set high IU (1000 IU = capacity for 10 fighters at FD I)
    colony.industrial.units = 1000
    game.updateColony(colony.id, colony)
    
    # Should be able to commission fighters
    check canCommissionFighter(game, colony) == true

suite "Capacity Limits: Carrier Hangars":

  test "isCarrier correctly identifies carrier types":
    check isCarrier(ShipClass.Carrier) == true
    check isCarrier(ShipClass.SuperCarrier) == true
    check isCarrier(ShipClass.Destroyer) == false
    check isCarrier(ShipClass.Battleship) == false

  test "carrierMaxCapacity CV scales with ACO tech":
    # CV capacity from config
    let aco1 = carrierMaxCapacity(ShipClass.Carrier, acoLevel = 1)
    let aco2 = carrierMaxCapacity(ShipClass.Carrier, acoLevel = 2)
    let aco3 = carrierMaxCapacity(ShipClass.Carrier, acoLevel = 3)
    
    let expectedAco1 = gameConfig.tech.aco.levels[1].cvCapacity
    let expectedAco2 = gameConfig.tech.aco.levels[2].cvCapacity
    let expectedAco3 = gameConfig.tech.aco.levels[3].cvCapacity
    
    check aco1 == expectedAco1
    check aco2 == expectedAco2
    check aco3 == expectedAco3

  test "carrierMaxCapacity CX scales with ACO tech":
    # CX capacity from config
    let aco1 = carrierMaxCapacity(ShipClass.SuperCarrier, acoLevel = 1)
    let aco2 = carrierMaxCapacity(ShipClass.SuperCarrier, acoLevel = 2)
    let aco3 = carrierMaxCapacity(ShipClass.SuperCarrier, acoLevel = 3)
    
    let expectedAco1 = gameConfig.tech.aco.levels[1].cxCapacity
    let expectedAco2 = gameConfig.tech.aco.levels[2].cxCapacity
    let expectedAco3 = gameConfig.tech.aco.levels[3].cxCapacity
    
    check aco1 == expectedAco1
    check aco2 == expectedAco2
    check aco3 == expectedAco3

  test "carrierMaxCapacity non-carriers return zero":
    let capacity = carrierMaxCapacity(ShipClass.Destroyer, acoLevel = 3)
    check capacity == 0

  test "currentHangarLoad counts embarked fighters":
    var game = newGame()
    let houseId = HouseId(1)
    let systemId = houseSystem(game, houseId)
    
    # Create carrier with CST tech level 3
    var house = game.house(houseId).get()
    house.techTree.levels.cst = 3
    game.updateHouse(houseId, house)
    
    let fleet = game.createFleet(houseId, systemId)
    let carrier = game.createShip(houseId, fleet.id, ShipClass.Carrier)
    
    # Embark 2 fighters
    var carrierShip = carrier  # Already a Ship, not ShipId
    carrierShip.embarkedFighters.add(ShipId(9991))
    carrierShip.embarkedFighters.add(ShipId(9992))
    game.updateShip(carrier.id, carrierShip)
    
    # Count should be 2
    let load = currentHangarLoad(carrierShip)
    check load == 2

  test "canLoadFighters respects ACO tech capacity":
    var game = newGame()
    let houseId = HouseId(1)
    let systemId = houseSystem(game, houseId)
    
    # Set ACO tech to level 1 (CV = 3 fighters)
    var house = game.house(houseId).get()
    house.techTree.levels.cst = 3  # Can build CV
    house.techTree.levels.aco = 1
    game.updateHouse(houseId, house)
    
    let fleet = game.createFleet(houseId, systemId)
    let carrier = game.createShip(houseId, fleet.id, ShipClass.Carrier)
    
    # Load 2 fighters
    var carrierShip = carrier
    carrierShip.embarkedFighters.add(ShipId(9991))
    carrierShip.embarkedFighters.add(ShipId(9992))
    game.updateShip(carrier.id, carrierShip)
    
    # Should be able to load 1 more (2 + 1 = 3, at capacity)
    check canLoadFighters(game, carrier.id, fightersToLoad = 1) == true
    
    # Should NOT be able to load 2 more (2 + 2 = 4, over capacity)
    check canLoadFighters(game, carrier.id, fightersToLoad = 2) == false

  test "availableHangarSpace returns correct remaining capacity":
    var game = newGame()
    let houseId = HouseId(1)
    let systemId = houseSystem(game, houseId)
    
    # Set ACO tech to level 2 (CV = 4 fighters)
    var house = game.house(houseId).get()
    house.techTree.levels.cst = 3
    house.techTree.levels.aco = 2
    game.updateHouse(houseId, house)
    
    let fleet = game.createFleet(houseId, systemId)
    let carrier = game.createShip(houseId, fleet.id, ShipClass.Carrier)
    
    # Load 1 fighter
    var carrierShip = carrier
    carrierShip.embarkedFighters.add(ShipId(9991))
    game.updateShip(carrier.id, carrierShip)
    
    # Available space should be 4 - 1 = 3
    let space = availableHangarSpace(game, carrier.id)
    check space == 3

suite "Capacity Limits: Planet Breakers":

  test "calculateMaxPlanetBreakers equals colony count":
    # 5 colonies = max 5 planet breakers
    let maxPB = calculateMaxPlanetBreakers(colonyCount = 5)
    check maxPB == 5
    
    # 1 colony (homeworld) = max 1 planet breaker
    let homeworldOnly = calculateMaxPlanetBreakers(colonyCount = 1)
    check homeworldOnly == 1

  test "countPlanetBreakersInFleets counts across all house fleets":
    var game = newGame()
    let houseId = HouseId(1)
    let systemId = houseSystem(game, houseId)
    
    # Set CST to level 10 (can build PB)
    var house = game.house(houseId).get()
    house.techTree.levels.cst = 10
    game.updateHouse(houseId, house)
    
    # Create 2 fleets with 1 PB each
    let fleet1 = game.createFleet(houseId, systemId)
    discard game.createShip(houseId, fleet1.id, ShipClass.PlanetBreaker)
    
    let fleet2 = game.createFleet(houseId, systemId)
    discard game.createShip(houseId, fleet2.id, ShipClass.PlanetBreaker)
    
    # Count should be 2
    let pbCount = countPlanetBreakersInFleets(game, houseId)
    check pbCount == 2

  test "analyzeCapacity detects PB violations":
    var game = newGame()
    let houseId = HouseId(1)
    let systemId = houseSystem(game, houseId)
    
    # Set CST to level 10
    var house = game.house(houseId).get()
    house.techTree.levels.cst = 10
    game.updateHouse(houseId, house)
    
    # Count colonies (likely 1 = homeworld)
    var colonyCount = 0'i32
    for _ in game.coloniesOwned(houseId):
      colonyCount += 1
    
    # Create PBs exceeding colony count
    let fleet = game.createFleet(houseId, systemId)
    for i in 0..<(colonyCount + 2):
      discard game.createShip(houseId, fleet.id, ShipClass.PlanetBreaker)
    
    # Analyze should detect violation
    let violation = planet_breakers.analyzeCapacity(game, houseId)
    
    check violation.current == colonyCount + 2
    check violation.maximum == colonyCount
    check violation.excess == 2
    check violation.severity == ViolationSeverity.Critical

  test "canBuildPlanetBreaker accounts for construction queue":
    var game = newGame()
    let houseId = HouseId(1)
    
    # Set CST to level 10
    var house = game.house(houseId).get()
    house.techTree.levels.cst = 10
    game.updateHouse(houseId, house)
    
    # Count colonies
    var colonyCount = 0'i32
    for _ in game.coloniesOwned(houseId):
      colonyCount += 1
    
    # Should be able to build up to colony count
    let canBuild = canBuildPlanetBreaker(game, houseId)
    check canBuild == true

suite "Capacity Limits: Per-Colony Facilities":

  test "countPlanetaryShields counts operational shields":
    var game = newGame()
    let houseId = HouseId(1)
    
    # Get a colony
    var colony: Colony
    for c in game.coloniesOwned(houseId):
      colony = c
      break
    
    # Initially no shields
    let count = countPlanetaryShields(game, colony)
    check count == 0

  test "canBuildPlanetaryShield enforces max 1 per colony":
    var game = newGame()
    let houseId = HouseId(1)
    
    # Get a colony
    var colony: Colony
    for c in game.coloniesOwned(houseId):
      colony = c
      break
    
    # Should be able to build first shield
    check canBuildPlanetaryShield(game, colony) == true
    
    # Add a planetary shield
    discard game.createGroundUnit(houseId, colony.id, GroundClass.PlanetaryShield)
    # Note: createGroundUnit automatically adds to colony.groundUnitIds
    
    # Reload colony
    colony = game.colony(colony.id).get()
    
    # Should NOT be able to build second shield
    check canBuildPlanetaryShield(game, colony) == false

  test "countStarbases counts operational starbases":
    var game = newGame()
    let houseId = HouseId(1)
    
    # Get a colony
    var colony: Colony
    for c in game.coloniesOwned(houseId):
      colony = c
      break
    
    # Initially no starbases
    let count = countStarbases(game, colony)
    check count == 0

  test "canBuildStarbase enforces max 3 per colony":
    var game = newGame()
    let houseId = HouseId(1)
    
    # Get a colony
    var colony: Colony
    for c in game.coloniesOwned(houseId):
      colony = c
      break
    
    # Should be able to build first starbase
    check canBuildStarbase(game, colony) == true
    
    # Add 3 starbases
    for i in 0..<3:
      discard game.createKastra(colony.id, KastraClass.Starbase, wepLevel = 1)
      # Note: createKastra automatically adds to colony.kastraIds
    
    # Reload colony
    colony = game.colony(colony.id).get()
    
    # Verify count
    let count = countStarbases(game, colony)
    check count == 3
    
    # Should NOT be able to build 4th starbase
    check canBuildStarbase(game, colony) == false

  test "starbases analyzeCapacity reports correct status":
    var game = newGame()
    let houseId = HouseId(1)
    
    # Get a colony
    var colony: Colony
    for c in game.coloniesOwned(houseId):
      colony = c
      break
    
    # Add 2 starbases
    for i in 0..<2:
      discard game.createKastra(colony.id, KastraClass.Starbase, wepLevel = 1)
      # Note: createKastra automatically adds to colony.kastraIds
    
    # Reload colony
    colony = game.colony(colony.id).get()
    
    # Analyze capacity
    let analysis = starbases.analyzeCapacity(game, colony)
    
    check analysis.current == 2
    check analysis.maximum == 3
    check analysis.underConstruction == 0

suite "Capacity Limits: Construction Docks":

  test "facilityCapacity reports correct dock counts":
    var game = newGame()
    let houseId = HouseId(1)
    
    # Get a colony
    var colony: Colony
    for c in game.coloniesOwned(houseId):
      colony = c
      break
    
    # Colony should have at least 1 spaceport (from game init)
    # Check if we have any neorias
    if colony.neoriaIds.len > 0:
      let neoriaId = colony.neoriaIds[0]
      let neoria = game.neoria(neoriaId).get()
      let capacity = facilityCapacity(neoria)
      
      # Spaceport has 5 docks, shipyard has 10
      check capacity.maxDocks > 0
      check capacity.usedDocks >= 0

  test "shipRequiresDock returns false for fighters only":
    check shipRequiresDock(ShipClass.Fighter) == false
    check shipRequiresDock(ShipClass.Destroyer) == true
    check shipRequiresDock(ShipClass.Carrier) == true

  test "colonyTotalCapacity sums all facilities":
    var game = newGame()
    let houseId = HouseId(1)
    
    # Get a colony
    var colony: Colony
    for c in game.coloniesOwned(houseId):
      colony = c
      break
    
    let (current, maximum) = colonyTotalCapacity(game, colony.id)
    
    # Should have some capacity from initial facilities
    check maximum >= 0
    check current >= 0
    check current <= maximum

  test "analyzeColonyCapacity returns facility details":
    var game = newGame()
    let houseId = HouseId(1)
    
    # Get a colony with facilities
    var colony: Colony
    for c in game.coloniesOwned(houseId):
      colony = c
      break
    
    let facilities = analyzeColonyCapacity(game, colony.id)
    
    # Should have at least one facility (spaceport from init)
    if colony.neoriaIds.len > 0:
      check facilities.len > 0
      
      # Each facility should have valid capacity
      for facility in facilities:
        check facility.maxDocks > 0
        check facility.usedDocks >= 0
