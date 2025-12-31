type
  CombatMechanicsConfig* = object
    criticalHitRoll*: int32
    retreatAfterRound*: int32
    maxCombatRounds*: int32
    desperationRoundTrigger*: int32

  CerModifiersConfig* = object
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
    blockadePrestigePenalty*: int32
    blockadeProductionPenalty*: float32

  StarbaseConfig* = object
    starbaseCriticalReroll*: bool
    starbaseDieModifier*: int32

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
    damageRules*: DamageRulesConfig
    retreatRules*: RetreatRulesConfig
    blockade*: BlockadeConfig
    starbase*: StarbaseConfig
    invasion*: InvasionConfig
    targeting*: TargetingConfig

