## Victory Conditions Types
##
## Victory condition tracking and evaluation per specifications

import ./core

export HouseId

type
  VictoryType* {.pure.} = enum
    ## Ways to win the game per docs/specs/01-gameplay.md Section 1.4.4
    MilitaryVictory # Last house standing (all rivals eliminated)
    TurnLimit # Highest prestige when turn limit reached

  VictoryCondition* = object ## Victory condition configuration
    turnLimit*: int32 # Optional turn limit (0 = no limit)
    enableDefensiveCollapse*: bool # Allow elimination via negative prestige

  VictoryStatus* = object ## Current victory status
    victoryAchieved*: bool
    houseId*: HouseId
    victoryType*: VictoryType
    achievedOnTurn*: int32
    description*: string

  VictoryCheck* = object ## Result of checking victory conditions
    victoryOccurred*: bool
    status*: VictoryStatus

  ## Leaderboard
  HouseRanking* = object
    houseId*: HouseId
    houseName*: string
    prestige*: int32
    colonies*: int32
    eliminated*: bool
    rank*: int32

  Leaderboard* = object ## Public leaderboard showing house rankings and game state
    rankings*: seq[HouseRanking]
    totalSystems*: int32 # Total colonizable systems in the game
    totalColonized*: int32 # Total systems currently colonized
