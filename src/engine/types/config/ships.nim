import ../ship  # For ShipClass enum
export ShipClass

type
  ShipStatsConfig* = object
    ## Configuration data for a ship class
    minCST*: int32
    productionCost*: int32
    maintenanceCost*: int32
    attackStrength*: int32
    defenseStrength*: int32
    commandCost*: int32
    commandRating*: int32
    carryLimit*: int32
    buildTime*: int32

  SalvageConfig* = object
    salvageValueMultiplier*: float32

  ShipsConfig* = object
    ## Ship configuration indexed by semantic ship class
    ## Uses array pattern for categorical data (see types-guide.md)
    ships*: array[ShipClass, ShipStatsConfig]
    salvage*: SalvageConfig

