type
  ThemeConfig* = object
    activeTheme*: string

  EliminationConfig* = object
    defensiveCollapseTurns*: int32
    defensiveCollapseThreshold*: int32

  AutopilotConfig* = object
    miaTurnsThreshold*: int32

  AutopilotBehaviorConfig* = object
    continueStandingOrders*: bool
    patrolHomeSystems*: bool
    maintainEconomy*: bool
    defensiveConstruction*: bool
    noOffensiveOps*: bool
    maintainDiplomacy*: bool

  DefensiveCollapseBehaviorConfig* = object
    retreatToHome*: bool
    defendOnly*: bool
    noConstruction*: bool
    noDiplomacyChanges*: bool
    economyCeases*: bool
    permanentElimination*: bool

  VictoryConfig* = object
    prestigeVictoryEnabled*: bool
    lastPlayerVictoryEnabled*: bool
    autopilotCanWin*: bool
    finalConflictAutoEnemy*: bool

  GameplayConfig* = object ## Complete gameplay configuration loaded from KDL
    theme*: ThemeConfig
    elimination*: EliminationConfig
    autopilot*: AutopilotConfig
    autopilotBehavior*: AutopilotBehaviorConfig
    defensiveCollapseBehavior*: DefensiveCollapseBehaviorConfig
    victory*: VictoryConfig

