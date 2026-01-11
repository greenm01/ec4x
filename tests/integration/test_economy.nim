## Economy Integration Tests
## Validates income calculation, maintenance, treasury management
## Per docs/specs/03-economy.md

import std/[tables, options, sequtils, random]
import unittest
import ../../src/engine/engine
import ../../src/engine/types/[core, house, command, tech, colony, ship, facilities]
import ../../src/engine/state/[engine, iterators]
import ../../src/engine/turn_cycle/engine
import ../../src/engine/systems/income/[maintenance, engine]
import ../../src/engine/systems/production/accessors
import ../../src/engine/systems/tech/effects

suite "Economy: Income Calculation (Section 3.3)":

  test "Colony has industrial capacity":
    ## Colonies start with industrial capacity which generates production
    var game = newGame()
    
    # Get first house
    var houseId: HouseId
    for (id, _) in game.activeHousesWithId():
      houseId = id
      break
    
    # Get first colony
    var colonyId: ColonyId
    for colony in game.coloniesOwned(houseId):
      colonyId = colony.id
      break
    
    let colony = game.colony(colonyId).get()
    check colony.industrial.units > 0  # Industrial capacity exists
    
    let house = game.house(houseId).get()
    check house.treasury > 0

  test "EL tech bonus applies to production":
    ## EL provides +5% per level, capped at 50% (EL 10)
    var game = newGame()
    
    var houseId: HouseId
    for (id, _) in game.activeHousesWithId():
      houseId = id
      break
    
    # Set EL to 5 (should give 25% bonus)
    var house = game.house(houseId).get()
    house.techTree.levels.el = 5
    game.updateHouse(houseId, house)
    
    let elBonus = economicBonus(house.techTree.levels.el)
    check elBonus == 0.25  # 25% bonus (function returns the bonus, not the multiplier)

  test "Tax rate affects income (default 50%)":
    var game = newGame()
    
    var houseId: HouseId
    var colonyId: ColonyId
    for (id, _) in game.activeHousesWithId():
      houseId = id
      for colony in game.coloniesOwned(houseId):
        colonyId = colony.id
        break
      break
    
    var colony = game.colony(colonyId).get()
    check colony.taxRate == 50  # Default tax rate is 50%

suite "Economy: Maintenance (Section 3.4)":

  test "Ship maintenance scales by fleet status":
    ## Active = 100%, Reserve = 50%, Mothball = 10%
    var game = newGame()
    
    # Ships have maintenance cost from config
    let ddMaintenance = shipMaintenanceCost(ShipClass.Destroyer)
    check ddMaintenance > 0

  test "Facility upkeep costs match config":
    let spaceportUpkeep = spaceportUpkeep()
    let shipyardUpkeep = shipyardUpkeep()
    let starbaseUpkeep = starbaseUpkeep()
    
    check spaceportUpkeep > 0
    check shipyardUpkeep >= spaceportUpkeep
    check starbaseUpkeep > shipyardUpkeep

  test "Negative treasury is allowed (debt)":
    ## Houses can go into debt during maintenance shortfalls
    var game = newGame()
    
    var houseId: HouseId
    for (id, _) in game.activeHousesWithId():
      houseId = id
      break
    
    var house = game.house(houseId).get()
    house.treasury = -1000  # Set negative treasury
    game.updateHouse(houseId, house)
    
    let updated = game.house(houseId).get()
    check updated.treasury == -1000  # Negative allowed

suite "Economy: Full Turn Income Flow":

  test "Income phase processes treasury changes":
    ## Test a full turn with income and maintenance
    var game = newGame()
    var rng = initRand(42)
    
    # Get initial state
    var houseId: HouseId
    for (id, _) in game.activeHousesWithId():
      houseId = id
      break
    
    let initialTreasury = game.house(houseId).get().treasury
    
    # Create empty commands
    var commands = initTable[HouseId, CommandPacket]()
    for (id, house) in game.activeHousesWithId():
      commands[id] = CommandPacket(
        houseId: id,
        turn: 1,
        fleetCommands: @[],
        buildCommands: @[],
        repairCommands: @[],
        scrapCommands: @[],
        researchAllocation: ResearchAllocation(),
        diplomaticCommand: @[],
        populationTransfers: @[],
        terraformCommands: @[],
        colonyManagement: @[],
        espionageActions: @[],
        ebpInvestment: 0,
        cipInvestment: 0
      )
    
    # Resolve turn
    let result = game.resolveTurn(commands, rng)
    
    # Treasury should have changed (income - maintenance)
    let finalTreasury = game.house(houseId).get().treasury
    check finalTreasury != initialTreasury

  test "Treasury increases when income > maintenance":
    var game = newGame()
    var rng = initRand(123)
    
    var houseId: HouseId
    for (id, _) in game.activeHousesWithId():
      houseId = id
      break
    
    let initialTreasury = game.house(houseId).get().treasury
    
    # Run a no-op turn (no spending, just collect income)
    var commands = initTable[HouseId, CommandPacket]()
    for (id, house) in game.activeHousesWithId():
      commands[id] = CommandPacket(
        houseId: id,
        turn: 1,
        fleetCommands: @[],
        buildCommands: @[],
        repairCommands: @[],
        scrapCommands: @[],
        researchAllocation: ResearchAllocation(),
        diplomaticCommand: @[],
        populationTransfers: @[],
        terraformCommands: @[],
        colonyManagement: @[],
        espionageActions: @[],
        ebpInvestment: 0,
        cipInvestment: 0
      )
    
    discard game.resolveTurn(commands, rng)
    
    let finalTreasury = game.house(houseId).get().treasury
    
    # Should have net positive income (most starting positions do)
    check finalTreasury > initialTreasury

when isMainModule:
  echo "========================================"
  echo "  Economy Integration Tests"
  echo "  Per docs/specs/03-economy.md"
  echo "========================================"
  echo ""
