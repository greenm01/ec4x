type
  SpaceportConfig* = object
    description*: string
    minCST*: int32
    productionCost*: int32
    maintenanceCost*: int32
    defenseStrength*: int32
    buildTime*: int32
    docks*: int32
    maxPerPlanet*: int32
    requiredForShipyard*: bool

  ShipyardConfig* = object
    description*: string
    minCST*: int32
    productionCost*: int32
    maintenanceCost*: int32
    defenseStrength*: int32
    buildTime*: int32
    docks*: int32
    maxPerPlanet*: int32
    requiresSpaceport*: bool

  DrydockConfig* = object
    description*: string
    minCST*: int32
    productionCost*: int32
    maintenanceCost*: int32
    defenseStrength*: int32
    buildTime*: int32
    docks*: int32
    maxPerPlanet*: int32
    requiresSpaceport*: bool

  StarbaseConfig* = object
    description*: string
    minCST*: int32
    productionCost*: int32
    maintenanceCost*: int32
    attachStrength*: int32
    defenseStrength*: int32
    buildTime*: int32
    maxPerPlanet*: int32
    requiresSpaceport*: bool
    economicLiftBonus*: int32
    growthBonus*: float32

  FacilitiesConfig* = object ## Complete facilities configuration loaded from KDL
    spaceport*: SpaceportConfig
    shipyard*: ShipyardConfig
    drydock*: DrydockConfig
    starbase*: StarbaseConfig

