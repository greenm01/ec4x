type
  ConstructionTimesConfig* = object
    shipTurns*: int32
    armyTurns*: int32
    marineTurns*: int32
    groundBatteryTurns*: int32
    planetaryShieldTurns*: int32
    spaceportTurns*: int32
    spaceportDocks*: int32
    shipyardTurns*: int32
    shipyardDocks*: int32
    shipyardRequiresSpaceport*: bool
    drydockTurns*: int32
    starbaseTurns*: int32
    starbaseRequiresShipyard*: bool
    starbaseMaxPerColony*: int32
    planetaryShieldMax*: int32
    planetaryShieldReplaceOnUpgrade*: bool
    groundBatteryMax*: int32
    fighterSquadronPlanetBased*: bool

  RepairConfig* = object
    shipRepairTurns*: int32
    shipRepairCostMultiplier*: float32
    starbaseRepairTurns*: int32
    starbaseRepairCostMultiplier*: float32
    starbaseRepairRequires*: string
    starbaseRepairUsesDockCapacity*: bool

  ModifiersConfig* = object
    planetsideConstructionCostMultiplier*: float32
    constructionCapacityIncreasePerLevel*: float32

  ConstructionConfig* = object ## Complete construction configuration loaded from KDL
    construction*: ConstructionTimesConfig
    repair*: RepairConfig
    modifiers*: ModifiersConfig

