type
  FighterMechanicsConfig* = object
    fighterCapacityIuDivisor*: int32
    capacityViolationGracePeriod*: int32

  SquadronLimitsConfig* = object
    squadronLimitIuDivisor*: int32 # IU divisor for capital squadron limit calculation
    squadronLimitMinimum*: int32
    totalSquadronIuDivisor*: int32 # IU divisor for total squadron limit calculation
    totalSquadronMinimum*: int32
    capitalShipCrThreshold*: int32

  SpaceLiftCapacityConfig* = object
    etacCapacity*: int32 # Population Transfer Units per ETAC

  MilitaryConfig* = object ## Complete military configuration loaded from KDL
    fighterMechanics*: FighterMechanicsConfig
    squadronLimits*: SquadronLimitsConfig
    spaceliftCapacity*: SpaceLiftCapacityConfig

