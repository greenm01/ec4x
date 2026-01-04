## Victory Condition Engine
##
## Evaluate victory conditions and determine game winner

import std/[tables, algorithm, options]
import ../types/[victory, game_state, core, house]
import ../state/[engine, iterators]

export victory

## Victory Checking

proc checkMilitaryVictory*(
    houses: Table[HouseId, House], currentTurn: int32
): VictoryCheck =
  ## Check if only one house remains
  result = VictoryCheck(victoryOccurred: false)

  var remainingHouses: seq[(HouseId, House)] = @[]
  for houseId, house in houses.pairs:
    if not house.isEliminated:
      remainingHouses.add((houseId, house))

  if remainingHouses.len == 1:
    let (victorId, victorHouse) = remainingHouses[0]
    result.victoryOccurred = true
    result.status = VictoryStatus(
      victoryAchieved: true,
      houseId: victorId,
      victoryType: VictoryType.MilitaryVictory,
      achievedOnTurn: currentTurn,
      description: victorHouse.name & " is the last house standing!",
    )

proc checkTurnLimitVictory*(
    houses: Table[HouseId, House], condition: VictoryCondition, currentTurn: int32
): VictoryCheck =
  ## Check if turn limit reached, award victory to highest prestige
  result = VictoryCheck(victoryOccurred: false)

  if condition.turnLimit > 0 and currentTurn >= condition.turnLimit:
    # Find house with highest prestige
    var bestHouse: Option[(HouseId, House, int32)] = none((HouseId, House, int32))

    for houseId, house in houses.pairs:
      if not house.isEliminated:
        if bestHouse.isNone or house.prestige > bestHouse.get()[2]:
          bestHouse = some((houseId, house, house.prestige))

    if bestHouse.isSome:
      let (victorId, victorHouse, prestige) = bestHouse.get()
      result.victoryOccurred = true
      result.status = VictoryStatus(
        victoryAchieved: true,
        houseId: victorId,
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
  ## Per docs/specs/01-gameplay.md Section 1.4.4:
  ## 1. Military Victory: Last house standing (highest priority)
  ## 2. Turn Limit Victory: Highest prestige when turn limit reached

  # Build houses table from entity manager
  var houses: Table[HouseId, House]
  for (id, house) in state.allHousesWithId():
    houses[id] = house

  # 1. Military victory - last house standing (highest priority)
  let militaryCheck = checkMilitaryVictory(houses, state.turn)
  if militaryCheck.victoryOccurred:
    return militaryCheck

  # 2. Turn limit victory - highest prestige at turn limit
  let turnLimitCheck = checkTurnLimitVictory(houses, condition, state.turn)
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

  for (houseId, house) in state.allHousesWithId():
    # Count colonies using iterator
    var colonyCount: int32 = 0
    for colony in state.coloniesOwned(houseId):
      colonyCount += 1

    rankings.add(
      HouseRanking(
        houseId: houseId,
        houseName: house.name,
        prestige: house.prestige,
        colonies: colonyCount,
        eliminated: house.isEliminated,
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
    totalSystems: state.systemsCount(),
    totalColonized: totalColonized,
  )
