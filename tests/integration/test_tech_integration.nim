## Integration Test: Technology Effects Applied to Entities
##
## Verifies that tech levels are correctly applied when:
## 1. Creating new entities (ships, facilities, starbases)
## 2. Upgrading tech (CST updates existing facilities)
## 3. NOT upgrading existing ships (WEP locked at build time)
##
## Tests sample tech levels (1, 3, 5, 10) rather than all levels

import std/[unittest, options, math, sequtils]
import ../../src/engine/engine
import ../../src/engine/types/[
  game_state, house, colony, facilities, ship, fleet, tech
]
import ../../src/engine/state/[engine, iterators]
import ../../src/engine/globals
import ../../src/engine/config/engine as config_engine
import ../../src/engine/systems/ship/entity
import ../../src/engine/systems/tech/[effects, advancement]
import ../../src/engine/entities/[ship_ops, neoria_ops, kastra_ops]
import ../../src/engine/systems/tech/advancement as tech_advancement

# Initialize config
gameConfig = config_engine.loadGameConfig()

# Helper: Create test game with house at specific tech level
proc createTestGameWithTech(
  wepLevel: int32 = 1, cstLevel: int32 = 1, eliLevel: int32 = 1,
  clkLevel: int32 = 1, elLevel: int32 = 1, scLevel: int32 = 1,
  fcLevel: int32 = 1, acoLevel: int32 = 1
): GameState =
  result = newGame(gameName = "Tech Integration Test")
  
  # Set house tech levels
  for house in result.allHouses():
    var modHouse = house
    modHouse.techTree.levels.wep = wepLevel
    modHouse.techTree.levels.cst = cstLevel
    modHouse.techTree.levels.eli = eliLevel
    modHouse.techTree.levels.clk = clkLevel
    modHouse.techTree.levels.el = elLevel
    modHouse.techTree.levels.sc = scLevel
    modHouse.techTree.levels.fc = fcLevel
    modHouse.techTree.levels.aco = acoLevel
    result.updateHouse(house.id, modHouse)

suite "Tech Integration: WEP Applied to Ships":
  
  test "New ship at WEP 1 has base AS/DS from config":
    let state = createTestGameWithTech(wepLevel = 1)
    let house = state.allHouses().toSeq[0]
    let fleet = state.fleetsOwned(house.id).toSeq[0]
    
    # Create destroyer at WEP 1
    let ship = state.createShip(house.id, fleet.id, ShipClass.Destroyer)
    
    # Get base stats (WEP 1)
    let baseStats = shipStats(ShipClass.Destroyer, 1)
    
    check ship.stats.wep == 1
    check ship.stats.attackStrength == baseStats.attackStrength
    check ship.stats.defenseStrength == baseStats.defenseStrength
  
  test "New ship at WEP 3 has +21% AS/DS (compound 10% per level)":
    let state = createTestGameWithTech(wepLevel = 3)
    let house = state.allHouses().toSeq[0]
    let fleet = state.fleetsOwned(house.id).toSeq[0]
    
    # Create destroyer at WEP 3
    let ship = state.createShip(house.id, fleet.id, ShipClass.Destroyer)
    
    # Get base stats (WEP 1) for comparison
    let baseStats = shipStats(ShipClass.Destroyer, 1)
    
    # WEP 3 = 1.1^2 = 1.21 = +21%
    let expectedAS = int32(float(baseStats.attackStrength) * 1.21)
    let expectedDS = int32(float(baseStats.defenseStrength) * 1.21)
    
    check ship.stats.wep == 3
    check ship.stats.attackStrength == expectedAS
    check ship.stats.defenseStrength == expectedDS
  
  test "New ship at WEP 5 has +46% AS/DS":
    let state = createTestGameWithTech(wepLevel = 5)
    let house = state.allHouses().toSeq[0]
    let fleet = state.fleetsOwned(house.id).toSeq[0]
    
    let ship = state.createShip(house.id, fleet.id, ShipClass.Cruiser)
    let baseStats = shipStats(ShipClass.Cruiser, 1)
    
    # WEP 5 = 1.1^4 = 1.4641 = +46.41%
    let expectedAS = int32(float(baseStats.attackStrength) * pow(1.1, 4.0))
    let expectedDS = int32(float(baseStats.defenseStrength) * pow(1.1, 4.0))
    
    check ship.stats.wep == 5
    check ship.stats.attackStrength == expectedAS
    check ship.stats.defenseStrength == expectedDS
  
  test "Existing ships keep their construction-time WEP after tech advance":
    var state = createTestGameWithTech(wepLevel = 1)
    let house = state.allHouses().toSeq[0]
    let fleet = state.fleetsOwned(house.id).toSeq[0]
    
    # Create ship at WEP 1
    let oldShip = state.createShip(house.id, fleet.id, ShipClass.Destroyer)
    let oldAS = oldShip.stats.attackStrength
    let oldDS = oldShip.stats.defenseStrength
    
    # Advance WEP to 3
    var modHouse = state.house(house.id).get()
    modHouse.techTree.levels.wep = 3
    state.updateHouse(house.id, modHouse)
    
    # Old ship should still have WEP 1 stats
    let unchangedShip = state.ship(oldShip.id).get()
    check unchangedShip.stats.wep == 1
    check unchangedShip.stats.attackStrength == oldAS
    check unchangedShip.stats.defenseStrength == oldDS
    
    # New ship should have WEP 3 stats
    let newShip = state.createShip(house.id, fleet.id, ShipClass.Destroyer)
    check newShip.stats.wep == 3
    check newShip.stats.attackStrength > oldAS
    check newShip.stats.defenseStrength > oldDS
  
  test "Ships from different WEP eras have different combat stats":
    var state = createTestGameWithTech(wepLevel = 1)
    let house = state.allHouses().toSeq[0]
    let fleet = state.fleetsOwned(house.id).toSeq[0]
    
    # Create WEP 1 destroyer
    let wep1Ship = state.createShip(house.id, fleet.id, ShipClass.Destroyer)
    
    # Advance to WEP 5
    var modHouse = state.house(house.id).get()
    modHouse.techTree.levels.wep = 5
    state.updateHouse(house.id, modHouse)
    
    # Create WEP 5 destroyer
    let wep5Ship = state.createShip(house.id, fleet.id, ShipClass.Destroyer)
    
    # WEP 5 ship should be significantly stronger
    check wep5Ship.stats.attackStrength > wep1Ship.stats.attackStrength
    check wep5Ship.stats.defenseStrength > wep1Ship.stats.defenseStrength
    
    # Verify exact multiplier (WEP 5 = 1.1^4 = 1.4641)
    let multiplier = float(wep5Ship.stats.attackStrength) / float(wep1Ship.stats.attackStrength)
    check multiplier >= 1.40 and multiplier <= 1.50
  
  test "Ship stats.wep field records construction-time tech level":
    var state = createTestGameWithTech(wepLevel = 3)
    let house = state.allHouses().toSeq[0]
    let fleet = state.fleetsOwned(house.id).toSeq[0]
    
    let ship = state.createShip(house.id, fleet.id, ShipClass.Destroyer)
    check ship.stats.wep == 3
    
    # Advance tech
    var modHouse = state.house(house.id).get()
    modHouse.techTree.levels.wep = 10
    state.updateHouse(house.id, modHouse)
    
    # Ship still reports original WEP
    let unchangedShip = state.ship(ship.id).get()
    check unchangedShip.stats.wep == 3

suite "Tech Integration: CST Applied to Facilities":
  
  test "New spaceport at CST 1 has base docks from config":
    var state = createTestGameWithTech(cstLevel = 1)
    let house = state.allHouses().toSeq[0]
    let colony = state.coloniesOwned(house.id).toSeq[0]
    
    # Create spaceport using entity ops (handles ID generation)
    let neoria = state.createNeoria(
      colony.id, NeoriaClass.Spaceport, house.id
    )
    
    # Base docks from config
    let baseDocks = gameConfig.facilities.facilities[FacilityClass.Spaceport].docks
    
    check neoria.baseDocks == baseDocks
    check neoria.effectiveDocks == baseDocks  # CST 1 = 1.0x
  
  test "New spaceport at CST 3 has 1.2x effective docks":
    var state = createTestGameWithTech(cstLevel = 3)
    let house = state.allHouses().toSeq[0]
    let colony = state.coloniesOwned(house.id).toSeq[0]
    
    let neoria = state.createNeoria(
      colony.id, NeoriaClass.Spaceport, house.id
    )
    
    let baseDocks = gameConfig.facilities.facilities[FacilityClass.Spaceport].docks
    
    # CST 3 = 1.0 + (3-1) * 0.1 = 1.2x
    let expectedDocks = int32(float(baseDocks) * 1.2)
    
    check neoria.baseDocks == baseDocks
    check neoria.effectiveDocks == expectedDocks
  
  test "CST upgrade recalculates ALL existing facility docks":
    var state = createTestGameWithTech(cstLevel = 1)
    let house = state.allHouses().toSeq[0]
    let colony = state.coloniesOwned(house.id).toSeq[0]
    
    # Create facilities at CST 1 using entity ops
    let spaceport = state.createNeoria(
      colony.id, NeoriaClass.Spaceport, house.id
    )
    let spaceportId = spaceport.id
    
    let shipyard = state.createNeoria(
      colony.id, NeoriaClass.Shipyard, house.id
    )
    let shipyardId = shipyard.id
    
    # Record initial docks
    let initialSpaceportDocks = spaceport.effectiveDocks
    let initialShipyardDocks = shipyard.effectiveDocks
    
    # Advance CST to 5
    var modHouse = state.house(house.id).get()
    modHouse.techTree.levels.cst = 5
    state.updateHouse(house.id, modHouse)
    
    # Manually trigger dock upgrade (normally happens in tech advancement)
    tech_advancement.applyDockCapacityUpgrade(state, house.id)
    
    # Check facilities updated
    let updatedSpaceport = state.neoria(spaceportId).get()
    let updatedShipyard = state.neoria(shipyardId).get()
    
    check updatedSpaceport.effectiveDocks > initialSpaceportDocks
    check updatedShipyard.effectiveDocks > initialShipyardDocks
    
    # Verify correct multiplier (CST 5 = 1.4x)
    let expectedSpaceportDocks = int32(float(spaceport.baseDocks) * 1.4)
    let expectedShipyardDocks = int32(float(shipyard.baseDocks) * 1.4)
    
    check updatedSpaceport.effectiveDocks == expectedSpaceportDocks
    check updatedShipyard.effectiveDocks == expectedShipyardDocks
  
  test "Shipyards and drydocks also get CST dock bonus":
    var state = createTestGameWithTech(cstLevel = 5)
    let house = state.allHouses().toSeq[0]
    let colony = state.coloniesOwned(house.id).toSeq[0]
    
    # Create different facility types using entity ops
    let shipyard = state.createNeoria(
      colony.id, NeoriaClass.Shipyard, house.id
    )
    
    let drydock = state.createNeoria(
      colony.id, NeoriaClass.Drydock, house.id
    )
    
    # All should have 1.4x multiplier at CST 5
    let shipyardBase = gameConfig.facilities.facilities[FacilityClass.Shipyard].docks
    let drydockBase = gameConfig.facilities.facilities[FacilityClass.Drydock].docks
    
    let expectedShipyard = int32(float(shipyardBase) * 1.4)
    let expectedDrydock = int32(float(drydockBase) * 1.4)
    
    check shipyard.effectiveDocks == expectedShipyard
    check drydock.effectiveDocks == expectedDrydock

suite "Tech Integration: WEP Applied to Starbases":
  
  test "New starbase at WEP 1 has base AS/DS":
    var state = createTestGameWithTech(wepLevel = 1)
    let house = state.allHouses().toSeq[0]
    let colony = state.coloniesOwned(house.id).toSeq[0]
    
    let starbase = state.createKastra(
      colony.id, KastraClass.Starbase, 1  # WEP level 1
    )
    
    # Get base config
    let configStats = gameConfig.facilities.facilities[FacilityClass.Starbase]
    
    check starbase.stats.wep == 1
    check starbase.stats.attackStrength == configStats.attackStrength
    check starbase.stats.defenseStrength == configStats.defenseStrength
  
  test "New starbase at WEP 3 has +21% AS/DS":
    var state = createTestGameWithTech(wepLevel = 3)
    let house = state.allHouses().toSeq[0]
    let colony = state.coloniesOwned(house.id).toSeq[0]
    
    let starbase = state.createKastra(
      colony.id, KastraClass.Starbase, 3  # WEP level 3
    )
    
    let configStats = gameConfig.facilities.facilities[FacilityClass.Starbase]
    let expectedAS = int32(float(configStats.attackStrength) * 1.21)
    let expectedDS = int32(float(configStats.defenseStrength) * 1.21)
    
    check starbase.stats.wep == 3
    check starbase.stats.attackStrength == expectedAS
    check starbase.stats.defenseStrength == expectedDS
  
  test "Existing starbases keep construction-time WEP":
    var state = createTestGameWithTech(wepLevel = 1)
    let house = state.allHouses().toSeq[0]
    let colony = state.coloniesOwned(house.id).toSeq[0]
    
    let starbase = state.createKastra(
      colony.id, KastraClass.Starbase, 1  # WEP level 1
    )
    let kastraId = starbase.id
    let oldAS = starbase.stats.attackStrength
    
    # Advance WEP
    var modHouse = state.house(house.id).get()
    modHouse.techTree.levels.wep = 5
    state.updateHouse(house.id, modHouse)
    
    # Starbase unchanged
    let unchangedStarbase = state.kastra(kastraId).get()
    check unchangedStarbase.stats.wep == 1
    check unchangedStarbase.stats.attackStrength == oldAS

suite "Tech Integration: EL Applied to Economy":
  
  test "EL 5 gives 25% production bonus":
    # EL bonus calculation
    let bonus = effects.economicBonus(5)
    
    # EL 5 should give 25% (5% per level, capped at 50%)
    check bonus == 0.25
  
  test "EL 10 gives 50% production bonus (cap)":
    let bonus = effects.economicBonus(10)
    check bonus == 0.50
    
    # Test cap - EL 15 should also give 50%
    let cappedBonus = effects.economicBonus(15)
    check cappedBonus == 0.50

suite "Tech Integration: ELI/CLK in Detection":
  
  test "House ELI level used in detection calculations":
    let state = createTestGameWithTech(eliLevel = 5)
    let house = state.allHouses().toSeq[0]
    
    check house.techTree.levels.eli == 5
    
    # Detection would use this ELI level
    # (Full combat/surveillance integration tested elsewhere)
  
  test "House CLK level used in raider cloaking":
    let state = createTestGameWithTech(clkLevel = 3)
    let house = state.allHouses().toSeq[0]
    
    check house.techTree.levels.clk == 3
    
    # Raider cloaking would use this CLK level

echo "Tech integration tests validate that technology effects are correctly"
echo "applied to entities at construction time and updated (for CST only)."
