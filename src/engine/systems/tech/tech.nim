proc initDefaultTechLevel*(): TechLevel =
  ## Initialize TechLevel with all fields at starting level 1
  ## Per economy.md:4.0: "ALL technology levels start at level 1, never 0"
  result = TechLevel(
    economicLevel: 1,
    scienceLevel: 1,
    constructionTech: 1,
    weaponsTech: 1,
    terraformingTech: 1,
    electronicIntelligence: 1,
    cloakingTech: 1,
    shieldTech: 1,
    counterIntelligence: 1,
    fighterDoctrine: 1,
    advancedCarrierOps: 1
  )

proc initTechTree*(startingLevels: TechLevel): TechTree =
  ## Initialize tech tree with starting levels
  ## Per economy.md:4.0: "ALL technology levels start at level 1, never 0"
  ## Validates that all tech levels are >= 1

  # Validate EL and SL
  if startingLevels.economicLevel < 1:
    raise newException(ValueError, "Invalid EL: " & $startingLevels.economicLevel & ". All tech levels must be >= 1. Use initDefaultTechLevel() for proper initialization.")
  if startingLevels.scienceLevel < 1:
    raise newException(ValueError, "Invalid SL: " & $startingLevels.scienceLevel & ". All tech levels must be >= 1. Use initDefaultTechLevel() for proper initialization.")

  # Validate all technology fields
  if startingLevels.constructionTech < 1:
    raise newException(ValueError, "Invalid CON level: " & $startingLevels.constructionTech & ". All tech levels must be >= 1. Use initDefaultTechLevel() for proper initialization.")
  if startingLevels.weaponsTech < 1:
    raise newException(ValueError, "Invalid WEP level: " & $startingLevels.weaponsTech & ". All tech levels must be >= 1. Use initDefaultTechLevel() for proper initialization.")
  if startingLevels.terraformingTech < 1:
    raise newException(ValueError, "Invalid TER level: " & $startingLevels.terraformingTech & ". All tech levels must be >= 1. Use initDefaultTechLevel() for proper initialization.")
  if startingLevels.electronicIntelligence < 1:
    raise newException(ValueError, "Invalid ELI level: " & $startingLevels.electronicIntelligence & ". All tech levels must be >= 1. Use initDefaultTechLevel() for proper initialization.")
  if startingLevels.cloakingTech < 1:
    raise newException(ValueError, "Invalid CLO level: " & $startingLevels.cloakingTech & ". All tech levels must be >= 1. Use initDefaultTechLevel() for proper initialization.")
  if startingLevels.shieldTech < 1:
    raise newException(ValueError, "Invalid SHI level: " & $startingLevels.shieldTech & ". All tech levels must be >= 1. Use initDefaultTechLevel() for proper initialization.")
  if startingLevels.counterIntelligence < 1:
    raise newException(ValueError, "Invalid COU level: " & $startingLevels.counterIntelligence & ". All tech levels must be >= 1. Use initDefaultTechLevel() for proper initialization.")
  if startingLevels.fighterDoctrine < 1:
    raise newException(ValueError, "Invalid FIG level: " & $startingLevels.fighterDoctrine & ". All tech levels must be >= 1. Use initDefaultTechLevel() for proper initialization.")
  if startingLevels.advancedCarrierOps < 1:
    raise newException(ValueError, "Invalid CAR level: " & $startingLevels.advancedCarrierOps & ". All tech levels must be >= 1. Use initDefaultTechLevel() for proper initialization.")

  result = TechTree(
    levels: startingLevels,
    accumulated: ResearchPoints(
      economic: 0,
      science: 0,
      technology: initTable[TechField, int]()
    ),
    breakthroughBonus: initTable[TechField, float]()
  )

proc initTechTree*(): TechTree =
  ## Initialize tech tree with default starting levels (all at 1)
  ## Convenience function for tests and scenarios
  result = initTechTree(initDefaultTechLevel())

proc initResearchAllocation*(): ResearchAllocation =
  ## Initialize empty research allocation
  result = ResearchAllocation(
    economic: 0,
    science: 0,
    technology: initTable[TechField, int]()
  )
