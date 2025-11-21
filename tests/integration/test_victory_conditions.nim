## Integration tests for Victory Conditions system

import std/[unittest, tables, options]
import ../../src/engine/victory/[types, engine]
import ../../src/engine/gamestate
import ../../src/engine/starmap
import ../../src/common/types/core

suite "Victory Conditions":

  test "Prestige victory at 5000 threshold":
    # Create minimal game state
    let starMap = newStarMap(3)
    var state = newGameState("test", 3, starMap)

    # Add houses
    state.houses["house1".HouseId] = initializeHouse("House Alpha", "blue")
    state.houses["house2".HouseId] = initializeHouse("House Beta", "red")
    state.houses["house3".HouseId] = initializeHouse("House Gamma", "green")

    # House 1 reaches 5000 prestige
    state.houses["house1".HouseId].prestige = 5000
    state.houses["house2".HouseId].prestige = 3000
    state.houses["house3".HouseId].prestige = 2000

    state.turn = 50

    let condition = initVictoryCondition()
    let result = checkVictoryConditions(state, condition)

    check result.victoryOccurred == true
    check result.status.victor == "house1".HouseId
    check result.status.victoryType == VictoryType.PrestigeVictory
    check result.status.achievedOnTurn == 50

  test "No victory when below threshold":
    let starMap = newStarMap(2)
    var state = newGameState("test", 2, starMap)

    state.houses["house1".HouseId] = initializeHouse("House Alpha", "blue")
    state.houses["house2".HouseId] = initializeHouse("House Beta", "red")

    state.houses["house1".HouseId].prestige = 4999
    state.houses["house2".HouseId].prestige = 3000

    let condition = initVictoryCondition()
    let result = checkVictoryConditions(state, condition)

    check result.victoryOccurred == false

  test "Last house standing victory":
    let starMap = newStarMap(3)
    var state = newGameState("test", 3, starMap)

    state.houses["house1".HouseId] = initializeHouse("House Alpha", "blue")
    state.houses["house2".HouseId] = initializeHouse("House Beta", "red")
    state.houses["house3".HouseId] = initializeHouse("House Gamma", "green")

    # Eliminate all but one
    state.houses["house2".HouseId].eliminated = true
    state.houses["house3".HouseId].eliminated = true

    state.turn = 75

    let condition = initVictoryCondition()
    let result = checkVictoryConditions(state, condition)

    check result.victoryOccurred == true
    check result.status.victor == "house1".HouseId
    check result.status.victoryType == VictoryType.LastHouseStanding

  test "Turn limit victory to highest prestige":
    let starMap = newStarMap(3)
    var state = newGameState("test", 3, starMap)

    state.houses["house1".HouseId] = initializeHouse("House Alpha", "blue")
    state.houses["house2".HouseId] = initializeHouse("House Beta", "red")
    state.houses["house3".HouseId] = initializeHouse("House Gamma", "green")

    state.houses["house1".HouseId].prestige = 3500
    state.houses["house2".HouseId].prestige = 4000  # Highest
    state.houses["house3".HouseId].prestige = 2800

    state.turn = 100

    var condition = initVictoryCondition()
    condition.turnLimit = 100

    let result = checkVictoryConditions(state, condition)

    check result.victoryOccurred == true
    check result.status.victor == "house2".HouseId
    check result.status.victoryType == VictoryType.TurnLimit

  test "Turn limit not reached yet":
    let starMap = newStarMap(3)
    var state = newGameState("test", 2, starMap)

    state.houses["house1".HouseId] = initializeHouse("House Alpha", "blue")
    state.houses["house2".HouseId] = initializeHouse("House Beta", "red")

    state.turn = 99

    var condition = initVictoryCondition()
    condition.turnLimit = 100

    let result = checkVictoryConditions(state, condition)

    check result.victoryOccurred == false

  test "Prestige victory takes priority over last standing":
    let starMap = newStarMap(3)
    var state = newGameState("test", 2, starMap)

    state.houses["house1".HouseId] = initializeHouse("House Alpha", "blue")
    state.houses["house2".HouseId] = initializeHouse("House Beta", "red")

    # House 1 has prestige victory AND house 2 is eliminated
    state.houses["house1".HouseId].prestige = 5100
    state.houses["house2".HouseId].eliminated = true

    let condition = initVictoryCondition()
    let result = checkVictoryConditions(state, condition)

    check result.victoryOccurred == true
    check result.status.victoryType == VictoryType.PrestigeVictory  # Higher priority

  test "Leaderboard ranking by prestige":
    let starMap = newStarMap(3)
    var state = newGameState("test", 4, starMap)

    state.houses["house1".HouseId] = initializeHouse("House Alpha", "blue")
    state.houses["house2".HouseId] = initializeHouse("House Beta", "red")
    state.houses["house3".HouseId] = initializeHouse("House Gamma", "green")
    state.houses["house4".HouseId] = initializeHouse("House Delta", "yellow")

    state.houses["house1".HouseId].prestige = 3500
    state.houses["house2".HouseId].prestige = 4200
    state.houses["house3".HouseId].prestige = 2800
    state.houses["house4".HouseId].prestige = 1500

    let leaderboard = generateLeaderboard(state)

    check leaderboard.len == 4
    check leaderboard[0].rank == 1
    check leaderboard[0].houseId == "house2".HouseId  # Highest prestige
    check leaderboard[1].houseId == "house1".HouseId
    check leaderboard[2].houseId == "house3".HouseId
    check leaderboard[3].houseId == "house4".HouseId

  test "Leaderboard places eliminated houses last":
    let starMap = newStarMap(3)
    var state = newGameState("test", 3, starMap)

    state.houses["house1".HouseId] = initializeHouse("House Alpha", "blue")
    state.houses["house2".HouseId] = initializeHouse("House Beta", "red")
    state.houses["house3".HouseId] = initializeHouse("House Gamma", "green")

    state.houses["house1".HouseId].prestige = 2000
    state.houses["house2".HouseId].prestige = 4000  # Highest but eliminated
    state.houses["house2".HouseId].eliminated = true
    state.houses["house3".HouseId].prestige = 1500

    let leaderboard = generateLeaderboard(state)

    check leaderboard[0].houseId == "house1".HouseId  # Active with 2000
    check leaderboard[1].houseId == "house3".HouseId  # Active with 1500
    check leaderboard[2].houseId == "house2".HouseId  # Eliminated (last)
    check leaderboard[2].eliminated == true
