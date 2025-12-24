## Morale System Types
##
## Morale affects tax efficiency, combat effectiveness, and production
## Based on prestige and recent events

import ./core

type
  MoraleLevel* {.pure.} = enum
    ## Morale state categories
    Collapsing # < -100 prestige: -50% tax, -20% combat
    VeryLow # -100 to 0: -25% tax, -10% combat
    Low # 0 to 500: -10% tax, -5% combat
    Normal # 500 to 1500: No modifiers
    High # 1500 to 3000: +10% tax, +5% combat
    VeryHigh # 3000 to 5000: +20% tax, +10% combat
    Exceptional # 5000+: +30% tax, +15% combat

  MoraleModifiers* = object ## Morale effects on game mechanics
    taxEfficiency*: float32 # Multiplier for tax collection (0.5 to 1.3)
    combatBonus*: float32 # Combat effectiveness modifier (-0.2 to +0.15)
    productionBonus*: float32 # IU production modifier (currently always 1.0)

  HouseMorale* = object ## Morale tracking for a house
    houseId*: HouseId
    currentLevel*: MoraleLevel
    prestige*: int32 # Current prestige
    modifiers*: MoraleModifiers
