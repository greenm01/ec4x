type
  SpaceportConfig* = object
    cstMin*: int32
    buildCost*: int32
    upkeepCost*: int32
    defenseStrength*: int32
    carryLimit*: int32
    description*: string
    buildTime*: int32
    docks*: int32
    maxPerPlanet*: int32
    requiredForShipyard*: bool

  ShipyardConfig* = object
    cstMin*: int32
    buildCost*: int32
    upkeepCost*: int32
    defenseStrength*: int32
    carryLimit*: int32
    description*: string
    buildTime*: int32
    docks*: int32
    maxPerPlanet*: int32
    requiresSpaceport*: bool
    fixedOrbit*: bool

  DrydockConfig* = object
    cstMin*: int32
    buildCost*: int32
    upkeepCost*: int32
    defenseStrength*: int32
    carryLimit*: int32
    description*: string
    buildTime*: int32
    docks*: int32
    maxPerPlanet*: int32
    requiresSpaceport*: bool
    fixedOrbit*: bool
    repairOnly*: bool

  StarbaseConfig* = object
    cstMin*: int32
    buildCost*: int32
    upkeepCost*: int32
    defenseStrength*: int32
    attackStrength*: int32
    description*: string
    buildTime*: int32
    maxPerPlanet*: int32
    requiresSpaceport*: bool
    fixedOrbit*: bool
    economicLiftBonus*: int32
    growthBonus*: float32

  ConstructionConfig* = object
    repairRatePerTurn*: float32
    multipleDocksAllowed*: bool

  FacilitiesConfig* = object ## Complete facilities configuration loaded from KDL
    spaceport*: SpaceportConfig
    shipyard*: ShipyardConfig
    drydock*: DrydockConfig
    starbase*: StarbaseConfig
    construction*: ConstructionConfig

