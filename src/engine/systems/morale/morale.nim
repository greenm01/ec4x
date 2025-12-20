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
