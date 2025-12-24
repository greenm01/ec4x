## Victory Condition Engine
##
## Evaluate victory conditions and determine game winner

import std/[tables, algorithm, options]
import types
import ../gamestate
import ../../common/types/core

export types

## Victory Checking

proc checkPrestigeVictory*(
    houses: Table[HouseId, House], condition: VictoryCondition, currentTurn: int
): VictoryCheck =
  ## Check if any house has reached prestige threshold
  ## If threshold is 0, prestige victory is disabled
  result = VictoryCheck(victoryOccurred: false)

  # Prestige victory disabled if threshold is 0
  if condition.prestigeThreshold <= 0:
    return

  for houseId, house in houses:
    if not house.eliminated and house.prestige >= condition.prestigeThreshold:
      result.victoryOccurred = true
      result.status = VictoryStatus(
        victoryAchieved: true,
        victor: houseId,
        victoryType: VictoryType.PrestigeVictory,
        achievedOnTurn: currentTurn,
        description:
          house.name & " achieved " & $house.prestige & " prestige (threshold: " &
          $condition.prestigeThreshold & ")",
      )
      return

proc checkLastHouseStanding*(
    houses: Table[HouseId, House], currentTurn: int
): VictoryCheck =
  ## Check if only one house remains
  result = VictoryCheck(victoryOccurred: false)

  var remainingHouses: seq[(HouseId, House)] = @[]
  for houseId, house in houses:
    if not house.eliminated:
      remainingHouses.add((houseId, house))

  if remainingHouses.len == 1:
    let (victorId, victorHouse) = remainingHouses[0]
    result.victoryOccurred = true
    result.status = VictoryStatus(
      victoryAchieved: true,
      victor: victorId,
      victoryType: VictoryType.LastHouseStanding,
      achievedOnTurn: currentTurn,
      description: victorHouse.name & " is the last house standing!",
    )

proc checkTurnLimitVictory*(
    houses: Table[HouseId, House], condition: VictoryCondition, currentTurn: int
): VictoryCheck =
  ## Check if turn limit reached, award victory to highest prestige
  result = VictoryCheck(victoryOccurred: false)

  if condition.turnLimit > 0 and currentTurn >= condition.turnLimit:
    # Find house with highest prestige
    var bestHouse: Option[(HouseId, House, int)] = none((HouseId, House, int))

    for houseId, house in houses:
      if not house.eliminated:
        if bestHouse.isNone or house.prestige > bestHouse.get()[2]:
          bestHouse = some((houseId, house, house.prestige))

    if bestHouse.isSome:
      let (victorId, victorHouse, prestige) = bestHouse.get()
      result.victoryOccurred = true
      result.status = VictoryStatus(
        victoryAchieved: true,
        victor: victorId,
        victoryType: VictoryType.TurnLimit,
        achievedOnTurn: currentTurn,
        description:
          victorHouse.name & " wins with highest prestige (" & $prestige &
          ") at turn limit",
      )

proc checkVictoryConditions*(
    state: GameState, condition: VictoryCondition
): VictoryCheck =
  ## Check all victory conditions and return result
  ## Checks in priority command: Prestige → Last Standing → Turn Limit

  # 1. Prestige victory (highest priority)
  let prestigeCheck = checkPrestigeVictory(state.houses, condition, state.turn)
  if prestigeCheck.victoryOccurred:
    return prestigeCheck

  # 2. Last house standing
  let lastStandingCheck = checkLastHouseStanding(state.houses, state.turn)
  if lastStandingCheck.victoryOccurred:
    return lastStandingCheck

  # 3. Turn limit victory (lowest priority)
  let turnLimitCheck = checkTurnLimitVictory(state.houses, condition, state.turn)
  if turnLimitCheck.victoryOccurred:
    return turnLimitCheck

  # No victory yet
  return VictoryCheck(victoryOccurred: false)

## Leaderboard

type
  HouseRanking* = object
    houseId*: HouseId
    houseName*: string
    prestige*: int
    colonies*: int
    eliminated*: bool
    rank*: int

  Leaderboard* = object ## Public leaderboard showing house rankings and game state
    rankings*: seq[HouseRanking]
    totalSystems*: int # Total colonizable systems in the game
    totalColonized*: int # Total systems currently colonized

proc generateLeaderboard*(state: GameState): Leaderboard =
  ## Generate ranked leaderboard of all houses with game metadata
  var rankings: seq[HouseRanking] = @[]

  for houseId, house in state.houses:
    let colonyCount = state.getHouseColonies(houseId).len

    rankings.add(
      HouseRanking(
        houseId: houseId,
        houseName: house.name,
        prestige: house.prestige,
        colonies: colonyCount,
        eliminated: house.eliminated,
        rank: 0, # Will be set after sorting
      )
    )

  # Sort by prestige (descending), then by colonies
  rankings.sort do(a, b: HouseRanking) -> int:
    if a.eliminated != b.eliminated:
      return if a.eliminated: 1 else: -1
    if a.prestige != b.prestige:
      return cmp(b.prestige, a.prestige) # Higher is better
    return cmp(b.colonies, a.colonies)

  # Assign ranks
  for i, ranking in rankings.mpairs:
    ranking.rank = i + 1

  # Calculate total colonized systems
  var totalColonized = 0
  for ranking in rankings:
    totalColonized += ranking.colonies

  return Leaderboard(
    rankings: rankings,
    totalSystems: state.starMap.systems.len,
    totalColonized: totalColonized,
  )
