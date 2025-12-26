type
  PlanetaryShieldConfig* = object
    cstMin*: int32
    buildCost*: int32
    upkeepCost*: int32
    attackStrength*: int32
    defenseStrength*: int32
    description*: string
    buildTime*: int32
    maxPerPlanet*: int32
    salvageRequired*: bool

  GroundBatteryConfig* = object
    cstMin*: int32
    buildCost*: int32
    upkeepCost*: int32
    maintenancePercent*: int32
    attackStrength*: int32
    defenseStrength*: int32
    description*: string
    buildTime*: int32
    maxPerPlanet*: int32

  ArmyConfig* = object
    cstMin*: int32
    buildCost*: int32
    upkeepCost*: int32
    maintenancePercent*: int32
    attackStrength*: int32
    defenseStrength*: int32
    description*: string
    buildTime*: int32
    maxPerPlanet*: int32
    populationCost*: int32 # Souls recruited per division

  MarineDivisionConfig* = object
    cstMin*: int32
    buildCost*: int32
    upkeepCost*: int32
    maintenancePercent*: int32
    attackStrength*: int32
    defenseStrength*: int32
    description*: string
    buildTime*: int32
    maxPerPlanet*: int32
    requiresTransport*: bool
    populationCost*: int32 # Souls recruited per division

  GroundUnitsConfig* = object ## Complete ground units configuration loaded from KDL
    planetaryShield*: PlanetaryShieldConfig
    groundBattery*: GroundBatteryConfig
    army*: ArmyConfig
    marineDivision*: MarineDivisionConfig

