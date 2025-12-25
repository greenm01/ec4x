## Test for KDL Ship Config Loader
##
## Tests loading the actual config/ships.kdl using the real engine config system

import std/[os, options, strutils]

# Import your actual engine config modules
import ../../src/engine/config/ships_config

proc main() =
  echo "Testing KDL Ship Config Loader with actual config file..."
  echo "Config path: config/ships.kdl"
  
  # Test 1: Load actual config file using the engine's loader
  echo "\n[1] Loading via engine config system..."
  try:
    let config = loadShipsConfig("config/ships.kdl")
    echo "✓ Loaded successfully"

    # Test 2: Verify escort ships
    echo "\n[2] Checking escort ships..."
    assert config.corvette.attackStrength == 2
    assert config.corvette.defenseStrength == 3
    assert config.corvette.productionCost == 20
    echo "✓ Corvette: AS=2, DS=3, Cost=20"

    assert config.frigate.attackStrength == 3
    assert config.frigate.productionCost == 30
    echo "✓ Frigate: AS=3, Cost=30"

    assert config.destroyer.attackStrength == 5
    assert config.destroyer.productionCost == 40
    echo "✓ Destroyer: AS=5, Cost=40"

    assert config.lightCruiser.attackStrength == 8
    assert config.lightCruiser.productionCost == 60
    echo "✓ Light Cruiser: AS=8, Cost=60"

    assert config.heavyCruiser.attackStrength == 12
    assert config.heavyCruiser.minCST == 2
    echo "✓ Heavy Cruiser: AS=12, Tech=2"
    
    # Test 3: Verify capital ships
    echo "\n[3] Checking capital ships..."
    assert config.battlecruiser.attackStrength == 16
    assert config.battlecruiser.minCST == 3
    echo "✓ Battlecruiser: AS=16, Tech=3"

    assert config.battleship.attackStrength == 20
    assert config.battleship.defenseStrength == 25
    assert config.battleship.productionCost == 150
    assert config.battleship.minCST == 4
    echo "✓ Battleship: AS=20, DS=25, Cost=150, Tech=4"

    assert config.dreadnought.attackStrength == 28
    assert config.dreadnought.productionCost == 200
    assert config.dreadnought.minCST == 5
    echo "✓ Dreadnought: AS=28, Cost=200, Tech=5"

    assert config.superDreadnought.attackStrength == 35
    assert config.superDreadnought.productionCost == 250
    assert config.superDreadnought.minCST == 6
    echo "✓ Super Dreadnought: AS=35, Cost=250, Tech=6"
    
    # Test 4: Verify carriers with carryLimit
    echo "\n[4] Checking carriers..."
    assert config.carrier.attackStrength == 5
    assert config.carrier.defenseStrength == 18
    assert config.carrier.carryLimit == 3
    assert config.carrier.productionCost == 120
    assert config.carrier.minCST == 3
    echo "✓ Carrier: AS=5, DS=18, Carry=3, Cost=120, Tech=3"

    assert config.supercarrier.attackStrength == 8
    assert config.supercarrier.carryLimit == 5
    assert config.supercarrier.minCST == 6
    echo "✓ Supercarrier: AS=8, Carry=5, Tech=6"
    
    # Test 5: Verify raiders
    echo "\n[5] Checking raiders..."
    assert config.raider.attackStrength == 20
    assert config.raider.defenseStrength == 25
    assert config.raider.productionCost == 200
    assert config.raider.minCST == 5
    echo "✓ Raider: AS=20, DS=25, Cost=200, Tech=5"
    
    # Test 6: Verify scouts
    echo "\n[6] Checking scouts..."
    assert config.scout.attackStrength == 0
    assert config.scout.defenseStrength == 2
    assert config.scout.productionCost == 50
    assert config.scout.commandRating == 0
    echo "✓ Scout: AS=0, DS=2, Cost=50, CR=0"
    
    # Test 7: Verify fighters
    echo "\n[7] Checking fighters..."
    assert config.fighter.attackStrength == 5
    assert config.fighter.defenseStrength == 2
    assert config.fighter.productionCost == 25
    assert config.fighter.commandCost == 1
    assert config.fighter.minCST == 1
    echo "✓ Fighter: AS=5, DS=2, Cost=25, CC=1, Tech=1"
    
    # Test 8: Verify auxiliary ships
    echo "\n[8] Checking auxiliary ships..."
    assert config.etac.attackStrength == 0
    assert config.etac.defenseStrength == 0
    assert config.etac.carryLimit == 0
    assert config.etac.productionCost == 50
    echo "✓ ETAC: AS=0, DS=0, Carry=0, Cost=50"

    assert config.troopTransport.attackStrength == 0
    assert config.troopTransport.defenseStrength == 0
    assert config.troopTransport.carryLimit == 0
    assert config.troopTransport.productionCost == 30
    echo "✓ Troop Transport: AS=0, DS=0, Carry=0, Cost=30"
    
    # Test 9: Verify special weapons
    echo "\n[9] Checking special weapons..."
    assert config.planetbreaker.attackStrength == 50
    assert config.planetbreaker.defenseStrength == 20
    assert config.planetbreaker.productionCost == 400
    assert config.planetbreaker.minCST == 10
    echo "✓ Planetbreaker: AS=50, DS=20, Cost=400, Tech=10"

    # Test 10: Verify maintenanceCost
    echo "\n[10] Checking maintenanceCost..."
    assert config.corvette.maintenanceCost == 3
    assert config.etac.maintenanceCost == 5
    echo "✓ maintenanceCost handled correctly"
    
    # Test 11: Test getShipConfig accessor
    echo "\n[11] Testing getShipConfig accessor..."
    let corvetteStats = getShipConfig(ShipClass.Corvette)
    assert corvetteStats.attackStrength == 2

    let battleshipStats = getShipConfig(ShipClass.Battleship)
    assert battleshipStats.attackStrength == 20

    let fighterStats = getShipConfig(ShipClass.Fighter)
    assert fighterStats.attackStrength == 5

    let carrierStats = getShipConfig(ShipClass.Carrier)
    assert carrierStats.carryLimit == 3
    echo "✓ Accessor function works for all ship classes"
    
    echo "\n" & "=".repeat(60)
    echo "✓ ALL TESTS PASSED - KDL config loader working correctly!"
    echo "=".repeat(60)
    
  except Exception as e:
    echo "\n✗ TEST FAILED:"
    echo "  Error: ", e.msg
    echo "  Type: ", $e.name
    quit(1)

when isMainModule:
  main()
