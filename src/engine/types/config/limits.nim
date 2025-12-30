type
  C2LimitsConfig* = object
    c2ConversionRatio*: float32
    c2OverdraftRatio*: float32
    capitalShipCrThreshold*: int32

  QuantityLimitsConfig* = object
    maxStarbasesPerColony*: int32
    maxPlanetaryShieldsPerColony*: int32
    maxPlanetBreakersPerColony*: int32

  FighterCapacityConfig* = object
    iuDivisor*: int32
    violationGracePeriodTurns*: int32

  PlanetCapacityConfig* = object
    planetClass*: string
    puMax*: int32

  CapacitiesConfig* = object
    planetCapacities*: seq[PlanetCapacityConfig]

  LimitsConfig* = object
    c2Limits*: C2LimitsConfig
    quantityLimits*: QuantityLimitsConfig
    fighterCapacity*: FighterCapacityConfig
    capacities*: CapacitiesConfig
