import ./[core, tech, espionage, income]

type
  HouseStatus* {.pure.} = enum
    Active
    Autopilot
    DefensiveCollapse

  House* = object
    id*: HouseId
    name*: string
    prestige*: int32
    treasury*: int32
    techTree*: TechTree
    espionageBudget*: EspionageBudget
    taxPolicy*: TaxPolicy
    isEliminated*: bool
    eliminatedTurn*: int32
    # House status tracking
    status*: HouseStatus
    turnsWithoutOrders*: int32
    consecutiveShortfallTurns*: int32
    negativePrestigeTurns*: int32
    # Special assets
    planetBreakerCount*: int32

  Houses* = object
    entities*: EntityManager[HouseId, House] # Core storage
