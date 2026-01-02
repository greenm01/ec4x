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

  PopulationLimitsConfig* = object
    ## Cross-system population constraints
    ## Used by: cargo loading, population transfers, colonization
    minColonyPopulation*: int32        # Minimum viable colony (5000 souls)
    maxConcurrentTransfers*: int32     # Max simultaneous population transfers per house

  PlanetCapacityConfig* = object
    planetClass*: string
    puMax*: int32

  CapacitiesConfig* = object
    planetCapacities*: seq[PlanetCapacityConfig]

  LimitsConfig* = object
    c2Limits*: C2LimitsConfig
    quantityLimits*: QuantityLimitsConfig
    fighterCapacity*: FighterCapacityConfig
    populationLimits*: PopulationLimitsConfig
    capacities*: CapacitiesConfig
