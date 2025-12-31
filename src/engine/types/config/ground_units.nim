type
  PlanetaryShieldConfig* = object
    minCST*: int32
    productionCost*: int32
    maintenanceCost*: int32
    defenseStrength*: int32
    buildTime*: int32
    maxPerPlanet*: int32
    replaceOnUpgrade*: bool
    sld1BlockChance*: float32
    sld2BlockChance*: float32
    sld3BlockChance*: float32
    sld4BlockChance*: float32
    sld5BlockChance*: float32
    sld6BlockChance*: float32
    shieldDamageReduction*: float32
    shieldInvasionDifficulty*: float32

  GroundBatteryConfig* = object
    minCST*: int32
    productionCost*: int32
    maintenanceCost*: int32
    attackStrength*: int32
    defenseStrength*: int32
    buildTime*: int32
    maxPerPlanet*: int32

  ArmyConfig* = object
    minCST*: int32
    productionCost*: int32
    maintenanceCost*: int32
    attackStrength*: int32
    defenseStrength*: int32
    buildTime*: int32
    maxPerPlanet*: int32
    populationCost*: int32 # Souls recruited per division

  MarineDivisionConfig* = object
    minCST*: int32
    productionCost*: int32
    maintenanceCost*: int32
    attackStrength*: int32
    defenseStrength*: int32
    buildTime*: int32
    maxPerPlanet*: int32
    populationCost*: int32 # Souls recruited per division
    requiresTransport*: bool

  GroundUnitsConfig* = object ## Complete ground units configuration loaded from KDL
    planetaryShield*: PlanetaryShieldConfig
    groundBattery*: GroundBatteryConfig
    army*: ArmyConfig
    marineDivision*: MarineDivisionConfig
