## Victory Conditions Types
##
## Victory condition tracking and evaluation per specifications

import ../../common/types/core

export core.HouseId

type
  VictoryType* {.pure.} = enum
    ## Ways to win the game
    PrestigeVictory,     # Reach 5000 prestige
    LastHouseStanding,   # All other houses eliminated
    TurnLimit            # Highest prestige when turn limit reached

  VictoryCondition* = object
    ## Victory condition configuration
    prestigeThreshold*: int     # Default: 5000
    turnLimit*: int             # Optional turn limit (0 = no limit)
    enableDefensiveCollapse*: bool  # Allow elimination via negative prestige

  VictoryStatus* = object
    ## Current victory status
    victoryAchieved*: bool
    victor*: HouseId
    victoryType*: VictoryType
    achievedOnTurn*: int
    description*: string

  VictoryCheck* = object
    ## Result of checking victory conditions
    victoryOccurred*: bool
    status*: VictoryStatus

## Constants

const
  DEFAULT_PRESTIGE_THRESHOLD* = 5000
  DEFAULT_COLLAPSE_TURNS* = 3  # Consecutive turns with negative prestige

## Initialization

proc initVictoryCondition*(): VictoryCondition =
  ## Create default victory conditions
  result = VictoryCondition(
    prestigeThreshold: DEFAULT_PRESTIGE_THRESHOLD,
    turnLimit: 0,  # No turn limit by default
    enableDefensiveCollapse: true
  )
