## Morale System Types
##
## Morale affects tax efficiency, combat effectiveness, and production
## Based on prestige and recent events

import ../../common/types/core

export core.HouseId

type
  MoraleLevel* {.pure.} = enum
    ## Morale state categories
    Collapsing,   # < -100 prestige: -50% tax, -20% combat
    VeryLow,      # -100 to 0: -25% tax, -10% combat
    Low,          # 0 to 500: -10% tax, -5% combat
    Normal,       # 500 to 1500: No modifiers
    High,         # 1500 to 3000: +10% tax, +5% combat
    VeryHigh,     # 3000 to 5000: +20% tax, +10% combat
    Exceptional   # 5000+: +30% tax, +15% combat

  MoraleModifiers* = object
    ## Morale effects on game mechanics
    taxEfficiency*: float      # Multiplier for tax collection (0.5 to 1.3)
    combatBonus*: float        # Combat effectiveness modifier (-0.2 to +0.15)
    productionBonus*: float    # IU production modifier (currently always 1.0)

  HouseMorale* = object
    ## Morale tracking for a house
    houseId*: HouseId
    currentLevel*: MoraleLevel
    prestige*: int             # Current prestige
    modifiers*: MoraleModifiers

## Constants

const
  # Prestige thresholds for morale levels
  COLLAPSING_THRESHOLD* = -100
  VERY_LOW_THRESHOLD* = 0
  LOW_THRESHOLD* = 500
  NORMAL_THRESHOLD* = 1500
  HIGH_THRESHOLD* = 3000
  VERY_HIGH_THRESHOLD* = 5000

## Helper Procs

proc getMoraleLevel*(prestige: int): MoraleLevel =
  ## Determine morale level from prestige
  if prestige < COLLAPSING_THRESHOLD:
    return MoraleLevel.Collapsing
  elif prestige < VERY_LOW_THRESHOLD:
    return MoraleLevel.VeryLow
  elif prestige < LOW_THRESHOLD:
    return MoraleLevel.Low
  elif prestige < NORMAL_THRESHOLD:
    return MoraleLevel.Normal
  elif prestige < HIGH_THRESHOLD:
    return MoraleLevel.High
  elif prestige < VERY_HIGH_THRESHOLD:
    return MoraleLevel.VeryHigh
  else:
    return MoraleLevel.Exceptional

proc getMoraleModifiers*(level: MoraleLevel): MoraleModifiers =
  ## Get morale modifiers for a given level
  case level
  of MoraleLevel.Collapsing:
    return MoraleModifiers(
      taxEfficiency: 0.5,
      combatBonus: -0.2,
      productionBonus: 1.0
    )
  of MoraleLevel.VeryLow:
    return MoraleModifiers(
      taxEfficiency: 0.75,
      combatBonus: -0.1,
      productionBonus: 1.0
    )
  of MoraleLevel.Low:
    return MoraleModifiers(
      taxEfficiency: 0.9,
      combatBonus: -0.05,
      productionBonus: 1.0
    )
  of MoraleLevel.Normal:
    return MoraleModifiers(
      taxEfficiency: 1.0,
      combatBonus: 0.0,
      productionBonus: 1.0
    )
  of MoraleLevel.High:
    return MoraleModifiers(
      taxEfficiency: 1.1,
      combatBonus: 0.05,
      productionBonus: 1.0
    )
  of MoraleLevel.VeryHigh:
    return MoraleModifiers(
      taxEfficiency: 1.2,
      combatBonus: 0.1,
      productionBonus: 1.0
    )
  of MoraleLevel.Exceptional:
    return MoraleModifiers(
      taxEfficiency: 1.3,
      combatBonus: 0.15,
      productionBonus: 1.0
    )

proc initHouseMorale*(houseId: HouseId, prestige: int): HouseMorale =
  ## Initialize morale for a house
  let level = getMoraleLevel(prestige)
  let modifiers = getMoraleModifiers(level)

  result = HouseMorale(
    houseId: houseId,
    currentLevel: level,
    prestige: prestige,
    modifiers: modifiers
  )

proc updateMorale*(morale: var HouseMorale, newPrestige: int) =
  ## Update morale based on new prestige value
  morale.prestige = newPrestige
  morale.currentLevel = getMoraleLevel(newPrestige)
  morale.modifiers = getMoraleModifiers(morale.currentLevel)
