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

  ConstructionConfig* = object ## Complete construction configuration loaded from KDL
    construction*: ConstructionTimesConfig
    repair*: RepairConfig
    modifiers*: ModifiersConfig

