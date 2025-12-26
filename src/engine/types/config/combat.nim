type
  CombatMechanicsConfig* = object
    criticalHitRoll*: int32
    retreatAfterRound*: int32
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

  PlanetaryShieldsConfig* = object
    sld1Chance*: int32
    sld1Roll*: int32
    sld1Block*: int32
    sld2Chance*: int32
    sld2Roll*: int32
    sld2Block*: int32
    sld3Chance*: int32
    sld3Roll*: int32
    sld3Block*: int32
    sld4Chance*: int32
    sld4Roll*: int32
    sld4Block*: int32
    sld5Chance*: int32
    sld5Roll*: int32
    sld5Block*: int32
    sld6Chance*: int32
    sld6Roll*: int32
    sld6Block*: int32

  DamageRulesConfig* = object
    crippledAsMultiplier*: float32
    crippledMaintenanceMultiplier*: float32
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

