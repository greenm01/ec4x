## EC4X Diplomatic Types
## Diplomatic relations and prestige tracking

import core

# =============================================================================
# Diplomatic and Prestige Types
# =============================================================================

type
  DiplomaticState* {.pure.} = enum
    ## Relations between houses - 4-level system
    ## Neutral: Default state, no formal relations
    ## Ally: Formal pact, mutual defense in combat
    ## Hostile: Tensions escalated, combat in deep space
    ## Enemy: Open war, planetary attacks
    Neutral          # Default state
    Ally             # Formal alliance pact, mutual defense
    Hostile          # Escalated tensions from deep space combat
    Enemy            # Open war from planetary attacks

  PrestigeChange* = object
    ## Record of prestige gain/loss
    house*: HouseId
    amount*: int
    reason*: string
    turn*: int
