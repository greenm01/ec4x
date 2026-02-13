type
  C2LimitsConfig* = object
    c2ConversionRatio*: float32
    c2OverdraftRatio*: float32

  QuantityLimitsConfig* = object
    maxStarbasesPerColony*: int32
    maxPlanetaryShieldsPerColony*: int32
    maxPlanetBreakersPerColony*: int32
    maxSpaceportsPerColony*: int32

  FighterCapacityConfig* = object
    iuDivisor*: int32
    violationGracePeriodTurns*: int32

  PopulationLimitsConfig* = object
    ## Cross-system population constraints
    ## Used by: cargo loading, population transfers, colonization
    minColonyPopulation*: int32        # Minimum viable colony (5000 souls)
    maxConcurrentTransfers*: int32     # Max simultaneous population transfers per house

  EspionageLimitsConfig* = object
    ## Target cooldown: prevents espionage spam against single house
    maxOpsPerTargetPerTurn*: int32     # Max ops vs any single rival house per turn

  MessagingLimitsConfig* = object
    ## Player-to-player message limits
    maxMessageLength*: int32           # Max characters per message
    maxMessagesPerMinute*: int32       # Rate limit per sender

  PlanetCapacityConfig* = object
    planetClass*: string
    puMax*: int32

  CapacitiesConfig* = object
    planetCapacities*: seq[PlanetCapacityConfig]

  ScScalingConfig* = object
    ## Strategic Command logarithmic fleet scaling
    ## Formula: maxFleets = base × (1 + log₂(systems_per_player ÷ divisor) × scaleFactor)
    systemsPerPlayerDivisor*: float32  # Threshold where scaling begins (default: 8.0)
    scaleFactor*: float32               # Scaling aggressiveness (default: 0.4)

  LimitsConfig* = object
    c2Limits*: C2LimitsConfig
    quantityLimits*: QuantityLimitsConfig
    fighterCapacity*: FighterCapacityConfig
    populationLimits*: PopulationLimitsConfig
    espionageLimits*: EspionageLimitsConfig
    messagingLimits*: MessagingLimitsConfig
    capacities*: CapacitiesConfig
    scScaling*: ScScalingConfig
