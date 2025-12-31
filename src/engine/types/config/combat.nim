import std/tables

type
  CombatMechanicsConfig* = object
    criticalHitRoll*: int32
    retreatAfterRound*: int32
    maxCombatRounds*: int32
    desperationRoundTrigger*: int32
    starbaseCriticalReroll*: bool
    starbaseDieModifier*: int32

  CerModifiersConfig* = object
    scouts*: int32
    surprise*: int32
    ambush*: int32

  CerTableConfig* = object
    veryPoorMax*: int32
    poorMax*: int32
    averageMax*: int32
    goodMin*: int32

  BombardmentConfig* = object
    maxRoundsPerTurn*: int32
    veryPoorMax*: int32
    poorMax*: int32
    goodMin*: int32

  GroundCombatConfig* = object
    poorMax*: int32
    averageMax*: int32
    goodMax*: int32
    critical*: int32

  SldCombatLevelData* = object
    ## Shield level combat data (legacy - now in tech.kdl)
    chance*: int32  # Currently unused (all 0s in original config)
    roll*: int32
    blocked*: int32  # Renamed from 'block' (reserved keyword)

  PlanetaryShieldsConfig* = object
    ## Planetary shields configuration (moved to tech.kdl)
    ## Uses Table pattern for numbered levels (see data-guide.md)
    ## Parser returns empty default - shield data now in TechConfig.sld
    levels*: Table[int32, SldCombatLevelData]

  DamageRulesConfig* = object
    crippledAsMultiplier*: float32
    crippledMaintenanceMultiplier*: float32
    crippledTargetingWeight*: float32
    squadronFightsAsUnit*: bool
    destroyAfterAllCrippled*: bool

  RetreatRulesConfig* = object
    fightersNeverRetreat*: bool
    spaceliftDestroyedIfEscortLost*: bool
    retreatToNearestFriendly*: bool

  BlockadeConfig* = object
    blockadeProductionPenalty*: float32
    blockadePrestigePenalty*: int32

  InvasionConfig* = object
    invasionIuLoss*: float32
    blitzIuLoss*: float32
    blitzMarinePenalty*: float32

  TargetingConfig* = object
    raiderWeight*: float32
    capitalWeight*: float32
    escortWeight*: float32
    fighterWeight*: float32
    starbaseWeight*: float32

  CombatConfig* = object ## Complete combat configuration loaded from KDL
    combat*: CombatMechanicsConfig
    cerModifiers*: CerModifiersConfig
    cerTable*: CerTableConfig
    bombardment*: BombardmentConfig
    groundCombat*: GroundCombatConfig
    planetaryShields*: PlanetaryShieldsConfig
    damageRules*: DamageRulesConfig
    retreatRules*: RetreatRulesConfig
    blockade*: BlockadeConfig
    invasion*: InvasionConfig
    targeting*: TargetingConfig

