type
  PlanetaryShieldConfig* = object
    ## Planetary shield facility configuration
    ## Shield mechanics (block chance, damage reduction) calculated algorithmically
    ## See: src/engine/systems/production/commissioning.nim:getShieldBlockChance()
    minCST*: int32
    productionCost*: int32
    maintenanceCost*: int32
    defenseStrength*: int32
    buildTime*: int32
    maxPerPlanet*: int32
    replaceOnUpgrade*: bool

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
