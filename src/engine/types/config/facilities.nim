import ../facilities

type
  FacilityStatsConfig* = object
    ## Unified facility configuration (used with array indexing)
    ## Per types-guide.md: Use array[Enum, T] for categorical systems
    minCST*: int32
    buildCost*: int32
    maintenancePercent*: float32
    defenseStrength*: int32
    attackStrength*: int32 # Only used by Starbase
    docks*: int32 # Used by Spaceport, Shipyard, Drydock (0 for Starbase)
    prerequisite*: string # Empty for Spaceport

  FacilitiesConfig* = object ## Complete facilities configuration loaded from KDL
    ## Array-indexed by FacilityType for O(1) access
    facilities*: array[FacilityType, FacilityStatsConfig]

