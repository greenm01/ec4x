import ../ground_unit

type
  GroundUnitStatsConfig* = object
    ## Unified ground unit configuration (used with array indexing)
    ## Per types-guide.md: Use array[Enum, T] for categorical systems
    minCST*: int32
    productionCost*: int32
    maintenanceCost*: int32
    attackStrength*: int32 # 0 for PlanetaryShield
    defenseStrength*: int32
    buildTime*: int32
    maxPerPlanet*: int32
    populationCost*: int32 # Only used by Army/Marine
    requiresTransport*: bool # Only true for Marine
    replaceOnUpgrade*: bool # Only true for PlanetaryShield

  GroundUnitsConfig* = object ## Complete ground units configuration loaded from KDL
    ## Array-indexed by GroundUnitType for O(1) access
    units*: array[GroundUnitType, GroundUnitStatsConfig]
