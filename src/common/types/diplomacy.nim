## EC4X Diplomatic Types
## Diplomatic relations and prestige tracking

import core

# =============================================================================
# Diplomatic and Prestige Types
# =============================================================================

type
  DiplomaticState* {.pure.} = enum
    ## Relations between houses (hardcoded)
    Neutral          # Default state
    NonAggression    # Formal non-aggression pact
    Enemy            # At war

  PrestigeChange* = object
    ## Record of prestige gain/loss
    house*: HouseId
    amount*: int
    reason*: string
    turn*: int
