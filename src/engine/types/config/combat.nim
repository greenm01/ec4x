import ../combat

type
  CombatMechanicsConfig* = object
    criticalHitRoll*: int32
    retreatAfterRound*: int32
    maxCombatRounds*: int32
    desperationRoundTrigger*: int32

  CerModifiersConfig* = object
    ambush*: int32
    moraleDRM*: MoraleDrmConfig

  CerTableConfig* = object
    veryPoorMax*: int32
    veryPoorMultiplier*: float32
    poorMax*: int32
    poorMultiplier*: float32
    averageMax*: int32
    averageMultiplier*: float32
    goodMin*: int32
    goodMultiplier*: float32

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

  MoraleTierThreshold* = object
    ## Single morale tier configuration
    maxPercent*: int32      # Max % of leader's prestige (0-100), omit for highest tier
    drm*: int32     # ROE adjustment for this tier

  MoraleDrmConfig* = object
    ## ROE modifiers based on morale tier relative to leading house (per spec 7.2.3)
    ## Each tier defines percentage threshold and ROE modifier
    crisis*: MoraleTierThreshold
    veryLow*: MoraleTierThreshold
    low*: MoraleTierThreshold
    average*: MoraleTierThreshold
    good*: MoraleTierThreshold
    high*: MoraleTierThreshold
    veryHigh*: MoraleTierThreshold  # No maxPercent, applies to >high threshold

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
    starbaseDetectionBonus*: int32

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

  MoraleTierConfig* = object
    threshold*: int32 # 1d20 roll required to succeed
    cerBonus*: int32 # CER bonus on success (or penalty if negative)
    appliesTo*: MoraleEffectTarget # Who gets the bonus
    criticalAutoSuccess*: bool # Critical hits auto-succeed

  MoraleChecksConfig* = array[MoraleTier, MoraleTierConfig]

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
    moraleChecks*: MoraleChecksConfig

