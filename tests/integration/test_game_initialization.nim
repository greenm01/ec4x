## Comprehensive Game Initialization Test
##
## Tests the complete game initialization flow from engine.nim::newGame()
## Validates all aspects of game state creation

import std/[unittest, options, tables]
import ../../src/engine/engine
import ../../src/engine/types/[core, game_state, house, colony, facilities, ground_unit, ship]
import ../../src/engine/state/[engine, iterators, player_state]
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
      # Check unified facilities (neorias = production, kastras = defensive)
      let expectedNeorias =
        gameSetup.startingFacilities.spaceports +
        gameSetup.startingFacilities.shipyards +
        gameSetup.startingFacilities.drydocks
      check colony.neoriaIds.len == expectedNeorias
      check colony.kastraIds.len == 0  # No starting starbases

  test "Homeworld systems use configured class and resources":
    let game = newGame()

    for systemId in game.starMap.houseSystemIds:
      let systemOpt = game.system(systemId)
      check systemOpt.isSome
      if systemOpt.isSome:
        let system = systemOpt.get()
        check $system.planetClass == gameSetup.homeworld.planetClass
        check $system.resourceRating == gameSetup.homeworld.rawQuality

  test "PlayerState keeps owned system class and resource data":
    let game = newGame()

    for house in game.allHouses():
      let ps = game.createPlayerState(house.id)
      for colony in ps.ownColonies:
        check ps.visibleSystems.hasKey(colony.systemId)
        if ps.visibleSystems.hasKey(colony.systemId):
          let visSys = ps.visibleSystems[colony.systemId]
          let systemOpt = game.system(colony.systemId)
          check systemOpt.isSome
          if systemOpt.isSome:
            let system = systemOpt.get()
            check visSys.planetClass == ord(system.planetClass).int32
            check visSys.resourceRating == ord(system.resourceRating).int32

  test "Facilities properly created":
    let game = newGame()

    var totalNeorias = 0

    for colony in game.allColonies():
      # Verify neorias (unified production facilities)
      for neoriaId in colony.neoriaIds:
        let neoriaOpt = game.neoria(neoriaId)
        check neoriaOpt.isSome
        if neoriaOpt.isSome:
          let neoria = neoriaOpt.get()
          check neoria.colonyId == colony.id
          check neoria.commissionedTurn == 1  # Game starts at turn 1
          check neoria.baseDocks > 0
          check neoria.effectiveDocks == neoria.baseDocks
          totalNeorias += 1

    let playerCount = gameSetup.gameParameters.playerCount
    let expectedTotal = playerCount * (
      gameSetup.startingFacilities.spaceports +
      gameSetup.startingFacilities.shipyards +
      gameSetup.startingFacilities.drydocks
    )
    check totalNeorias == expectedTotal

  test "Ground units created with correct stats":
    let game = newGame()

    var totalArmies = 0
    var totalMarines = 0
    var totalBatteries = 0

    for colony in game.allColonies():
      # Verify ground units (unified collection)
      for groundUnitId in colony.groundUnitIds:
        let unitOpt = game.groundUnit(groundUnitId)
        check unitOpt.isSome
        if unitOpt.isSome:
          let unit = unitOpt.get()
          check unit.stats.attackStrength > 0 or unit.stats.defenseStrength > 0
          check unit.garrison.locationType == GroundUnitLocation.OnColony
          check unit.garrison.colonyId == colony.id

          # Count by type
          case unit.stats.unitType
          of GroundClass.Army:
            totalArmies += 1
          of GroundClass.Marine:
            totalMarines += 1
          of GroundClass.GroundBattery:
            totalBatteries += 1
          else:
            discard

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
      check fleet.ships.len > 0  # Changed from squadrons to ships
      check fleet.location in game.starMap.houseSystemIds

  test "Ships properly created with stats":
    let game = newGame()

    var shipCount = 0
    for fleet in game.allFleets():
      for shipId in fleet.ships:  # Changed from squadrons to ships
        let shipOpt = game.ship(shipId)
        check shipOpt.isSome
        if shipOpt.isSome:
          let ship = shipOpt.get()
          check ship.stats.wep > 0
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
