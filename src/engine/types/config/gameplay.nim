type
  EliminationConfig* = object
    defensiveCollapseTurns*: int32
    defensiveCollapseThreshold*: int32

  AutopilotConfig* = object
    miaTurnsThreshold*: int32

  AutopilotBehaviorConfig* = object
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

  ColonizationConfig* = object
    strengthWeight*: int32

  GameplayConfig* = object ## Complete gameplay configuration loaded from KDL
    elimination*: EliminationConfig
    autopilot*: AutopilotConfig
    autopilotBehavior*: AutopilotBehaviorConfig
    defensiveCollapseBehavior*: DefensiveCollapseBehaviorConfig
    colonization*: ColonizationConfig
