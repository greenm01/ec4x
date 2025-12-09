## EC4X Diplomatic Types
## Diplomatic relations and prestige tracking

import core

# =============================================================================
# Diplomatic and Prestige Types
# =============================================================================

type
  DiplomaticState * = enum
    ## Relations between houses - 3-level system
    ## Neutral: Default state, safe passage
    ## Hostile: Tense relations, potential for combat
    ## Enemy: Active warfare, combat on sight
    Neutral          # Default state
    Hostile          # Escalated tensions from deep space combat
    Enemy            # Open war from planetary attacks

  PrestigeChange* = object
    ## Record of prestige gain/loss
    house*: HouseId
    amount*: int
    reason*: string
    turn*: int
