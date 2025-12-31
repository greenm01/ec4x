## Comprehensive Game Initialization Test
##
## Tests the complete game initialization flow from engine.nim::newGame()
## Validates all aspects of game state creation

import std/[unittest, options, tables]
import ../../src/engine/engine
import ../../src/engine/types/[core, game_state, house, colony, facilities, ground_unit, ship]
import ../../src/engine/state/[engine as state_helpers, entity_manager, iterators]
import ../../src/engine/globals

suite "Game Initialization - Complete Flow":

  test "newGame creates valid GameState":
    let game = newGame()

    check game.turn == 1
    let playerCount = gameSetup.gameParameters.playerCount
    check game.houses.entities.data.len == playerCount

  test "Houses initialized with correct resources":
    let game = newGame()

    for house in game.allHouses():
      check house.treasury == gameSetup.startingResources.treasury
      check house.prestige == gameSetup.startingResources.startingPrestige
      check house.status == HouseStatus.Active

  test "Houses have correct starting tech":
    let game = newGame()

    for house in game.allHouses():
      let tech = house.techTree.levels
      # Verify all tech levels from config
      check tech.el == gameSetup.startingTech.el
      check tech.sl == gameSetup.startingTech.sl
      check tech.cst == gameSetup.startingTech.cst
      check tech.wep == gameSetup.startingTech.wep
      check tech.ter == gameSetup.startingTech.ter
      check tech.eli == gameSetup.startingTech.eli
      check tech.clk == gameSetup.startingTech.clk
      check tech.sld == gameSetup.startingTech.sld
      check tech.cic == gameSetup.startingTech.cic
      check tech.stl == gameSetup.startingTech.stl
      check tech.fc == gameSetup.startingTech.fc
      check tech.sc == gameSetup.startingTech.sc
      check tech.fd == gameSetup.startingTech.fd
      check tech.aco == gameSetup.startingTech.aco

  test "Homeworld colonies created with facilities":
    let game = newGame()
    let playerCount = gameSetup.gameParameters.playerCount

    check game.colonies.entities.data.len == playerCount

    for colony in game.allColonies():
      check colony.populationUnits == gameSetup.homeworld.populationUnits
      check colony.infrastructure == gameSetup.homeworld.colonyLevel
      check colony.spaceportIds.len == gameSetup.startingFacilities.spaceports
      check colony.shipyardIds.len == gameSetup.startingFacilities.shipyards
      check colony.drydockIds.len == gameSetup.startingFacilities.drydocks
      check colony.starbaseIds.len == 0  # No starting starbases

  test "Facilities properly created":
    let game = newGame()

    var totalSpaceports = 0
    var totalShipyards = 0
    var totalDrydocks = 0

    for colony in game.allColonies():
      # Verify spaceports
      for spaceportId in colony.spaceportIds:
        let spaceportOpt = game.spaceports.entities.entity(spaceportId)
        check spaceportOpt.isSome
        if spaceportOpt.isSome:
          let spaceport = spaceportOpt.get()
          check spaceport.colonyId == colony.id
          check spaceport.commissionedTurn == 0
          check spaceport.baseDocks > 0
          check spaceport.effectiveDocks == spaceport.baseDocks
          totalSpaceports += 1

      # Verify shipyards
      for shipyardId in colony.shipyardIds:
        let shipyardOpt = game.shipyards.entities.entity(shipyardId)
        check shipyardOpt.isSome
        if shipyardOpt.isSome:
          let shipyard = shipyardOpt.get()
          check shipyard.colonyId == colony.id
          check shipyard.commissionedTurn == 0
          check shipyard.baseDocks > 0
          check shipyard.effectiveDocks == shipyard.baseDocks
          check shipyard.isCrippled == false
          totalShipyards += 1

      # Verify drydocks
      for drydockId in colony.drydockIds:
        let drydockOpt = game.drydocks.entities.entity(drydockId)
        check drydockOpt.isSome
        if drydockOpt.isSome:
          let drydock = drydockOpt.get()
          check drydock.colonyId == colony.id
          check drydock.commissionedTurn == 0
          check drydock.baseDocks > 0
          check drydock.effectiveDocks == drydock.baseDocks
          check drydock.isCrippled == false
          totalDrydocks += 1

    let playerCount = gameSetup.gameParameters.playerCount
    check totalSpaceports == playerCount * gameSetup.startingFacilities.spaceports
    check totalShipyards == playerCount * gameSetup.startingFacilities.shipyards
    check totalDrydocks == playerCount * gameSetup.startingFacilities.drydocks

  test "Ground units created with correct stats":
    let game = newGame()

    var totalArmies = 0
    var totalMarines = 0
    var totalBatteries = 0

    for colony in game.allColonies():
      # Verify armies
      for armyId in colony.armyIds:
        let armyOpt = game.groundUnits.entities.entity(armyId)
        check armyOpt.isSome
        if armyOpt.isSome:
          let army = armyOpt.get()
          check army.stats.unitType == GroundClass.Army
          check army.stats.attackStrength > 0
          check army.stats.defenseStrength > 0
          check army.garrison.locationType == GroundUnitLocation.OnColony
          check army.garrison.colonyId == colony.id
          totalArmies += 1

      # Verify marines
      for marineId in colony.marineIds:
        let marineOpt = game.groundUnits.entities.entity(marineId)
        check marineOpt.isSome
        if marineOpt.isSome:
          let marine = marineOpt.get()
          check marine.stats.unitType == GroundClass.Marine
          check marine.stats.attackStrength > 0
          check marine.stats.defenseStrength > 0
          check marine.garrison.locationType == GroundUnitLocation.OnColony
          check marine.garrison.colonyId == colony.id
          totalMarines += 1

      # Verify ground batteries
      for batteryId in colony.groundBatteryIds:
        let batteryOpt = game.groundUnits.entities.entity(batteryId)
        check batteryOpt.isSome
        if batteryOpt.isSome:
          let battery = batteryOpt.get()
          check battery.stats.unitType == GroundClass.GroundBattery
          check battery.stats.attackStrength > 0
          check battery.stats.defenseStrength > 0
          check battery.garrison.locationType == GroundUnitLocation.OnColony
          check battery.garrison.colonyId == colony.id
          totalBatteries += 1

    let playerCount = gameSetup.gameParameters.playerCount
    check totalArmies == playerCount * gameSetup.startingGroundForces.armies
    check totalMarines == playerCount * gameSetup.startingGroundForces.marines
    check totalBatteries == playerCount * gameSetup.startingGroundForces.groundBatteries

  test "Starting fleets created":
    let game = newGame()
    let playerCount = gameSetup.gameParameters.playerCount
    let fleetsPerPlayer = gameSetup.startingFleets.fleets.len

    check game.fleets.entities.data.len == playerCount * fleetsPerPlayer

    for fleet in game.allFleets():
      check fleet.squadrons.len > 0
      check fleet.location in game.starMap.houseSystemIds

  test "Ships properly created with stats":
    let game = newGame()

    var shipCount = 0
    for fleet in game.allFleets():
      for squadronId in fleet.squadrons:
        let squadronOpt = state_helpers.squadrons(game, squadronId)
        check squadronOpt.isSome
        if squadronOpt.isSome:
          let squadron = squadronOpt.get()
          let shipOpt = state_helpers.ship(game, squadron.flagshipId)
          check shipOpt.isSome
          if shipOpt.isSome:
            let ship = shipOpt.get()
            check ship.stats.weaponsTech > 0
            shipCount += 1

            # ETACs should have cargo
            if ship.shipClass == ShipClass.ETAC:
              check ship.cargo.isSome
              if ship.cargo.isSome:
                check ship.cargo.get().quantity > 0

    check shipCount > 0

  test "Diplomatic relations initialized":
    let game = newGame()
    let playerCount = gameSetup.gameParameters.playerCount

    check game.diplomaticRelation.len == playerCount * (playerCount - 1)

  test "Entity manager indices consistent":
    let game = newGame()

    for house in game.allHouses():
      check game.houses.entities.index.hasKey(house.id)

    for colony in game.allColonies():
      check game.colonies.entities.index.hasKey(colony.id)
      check game.colonies.bySystem.hasKey(colony.systemId)

    for fleet in game.allFleets():
      check game.fleets.entities.index.hasKey(fleet.id)
