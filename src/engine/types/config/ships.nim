type
  ShipStatsConfig* = object
    description*: string
    minCST*: int32
    productionCost*: int32
    maintenanceCost*: int32
    attackStrength*: int32
    defenseStrength*: int32
    commandCost*: int32
    commandRating*: int32
    carryLimit*: int32
    buildTime*: int32

  ShipsConfig* = object
    corvette*: ShipStatsConfig
    frigate*: ShipStatsConfig
    destroyer*: ShipStatsConfig
    lightCruiser*: ShipStatsConfig
    heavyCruiser*: ShipStatsConfig
    battlecruiser*: ShipStatsConfig
    battleship*: ShipStatsConfig
    dreadnought*: ShipStatsConfig
    superDreadnought*: ShipStatsConfig
    planetbreaker*: ShipStatsConfig
    carrier*: ShipStatsConfig
    supercarrier*: ShipStatsConfig
    fighter*: ShipStatsConfig
    raider*: ShipStatsConfig
    scout*: ShipStatsConfig
    etac*: ShipStatsConfig
    troopTransport*: ShipStatsConfig

