type
  SpaceportConfig* = object
    minCST*: int32
    buildCost*: int32
    maintenancePercent*: float32
    defenseStrength*: int32
    docks*: int32

  ShipyardConfig* = object
    minCST*: int32
    buildCost*: int32
    maintenancePercent*: float32
    defenseStrength*: int32
    prerequisite*: string
    docks*: int32

  DrydockConfig* = object
    minCST*: int32
    buildCost*: int32
    maintenancePercent*: float32
    defenseStrength*: int32
    prerequisite*: string
    docks*: int32

  StarbaseConfig* = object
    minCST*: int32
    buildCost*: int32
    maintenancePercent*: float32
    attackStrength*: int32
    defenseStrength*: int32
    prerequisite*: string

  FacilitiesConfig* = object ## Complete facilities configuration loaded from KDL
    spaceport*: SpaceportConfig
    shipyard*: ShipyardConfig
    drydock*: DrydockConfig
    starbase*: StarbaseConfig

