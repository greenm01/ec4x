type
  ConstructionTimesConfig* = object
    spaceportTurns*: int32
    spaceportDocks*: int32
    shipyardTurns*: int32
    shipyardDocks*: int32
    shipyardRequiresSpaceport*: bool
    starbaseTurns*: int32
    starbaseRequiresShipyard*: bool
    starbaseMaxPerColony*: int32
    planetaryShieldTurns*: int32
    planetaryShieldMax*: int32
    planetaryShieldReplaceOnUpgrade*: bool
    groundBatteryTurns*: int32
    groundBatteryMax*: int32
    fighterSquadronPlanetBased*: bool

  RepairConfig* = object
    shipRepairTurns*: int32
    shipRepairCostMultiplier*: float32
    starbaseRepairCostMultiplier*: float32

  ModifiersConfig* = object
    planetsideConstructionCostMultiplier*: float32
    constructionCapacityIncreasePerLevel*: float32

  CostsConfig* = object
    spaceportCost*: int32
    shipyardCost*: int32
    starbaseCost*: int32
    groundBatteryCost*: int32
    fighterSquadronCost*: int32
    planetaryShieldSld1Cost*: int32
    planetaryShieldSld2Cost*: int32
    planetaryShieldSld3Cost*: int32
    planetaryShieldSld4Cost*: int32
    planetaryShieldSld5Cost*: int32
    planetaryShieldSld6Cost*: int32

  UpkeepConfig* = object
    spaceportUpkeep*: int32
    shipyardUpkeep*: int32
    starbaseUpkeep*: int32
    groundBatteryUpkeep*: int32
    planetaryShieldUpkeep*: int32

  ConstructionConfig* = object ## Complete construction configuration loaded from KDL
    construction*: ConstructionTimesConfig
    repair*: RepairConfig
    modifiers*: ModifiersConfig
    costs*: CostsConfig
    upkeep*: UpkeepConfig

