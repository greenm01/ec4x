import ../[ship, fleet]  # For ShipClass and FleetStatus enums
export ShipClass, FleetStatus

type
  ShipStatsConfig* = object
    ## Configuration data for a ship class
    minCST*: int32
    productionCost*: int32
    maintenanceCost*: int32
    attackStrength*: int32
    defenseStrength*: int32
    commandCost*: int32
    carryLimit*: int32
    buildTime*: int32

  SalvageConfig* = object
    salvageValueMultiplier*: float32

  FleetStatusModifiers* = object
    ## Maintenance and C2 cost modifiers for fleet status
    ## Per 02-assets.md section 2.3.3.5
    c2CostMultiplier*: float32
    maintenanceMultiplier*: float32
    reactivationTurns*: int32

  ShipsConfig* = object
    ## Ship configuration indexed by semantic ship class
    ## Uses array pattern for categorical data (see types-guide.md)
    ships*: array[ShipClass, ShipStatsConfig]
    salvage*: SalvageConfig
    reserve*: FleetStatusModifiers
    mothballed*: FleetStatusModifiers

