type
  ActivationConfig* = object
    globalEnabled*: bool
    defaultActivationDelayTurns*: int32
    enabledByDefault*: bool

  BehaviorConfig* = object
    autoHoldOnCompletion*: bool
    respectDiplomaticChanges*: bool

  UIHintsConfig* = object
    warnBeforeActivation*: bool
    warnTurnsBefore*: int32

  StandingCommandsConfig* = object
    ## Complete standing commands configuration loaded from KDL
    activation*: ActivationConfig
    behavior*: BehaviorConfig
    uiHints*: UIHintsConfig

