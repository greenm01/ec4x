import ./config/[
  gameplay, ships, ground_units, facilities, combat, economy, prestige, espionage,
  tech, military
]

export gameplay, ships, ground_units, facilities, combat, economy, prestige, espionage, tech, military

type
  GameConfig* = object
    gameplay*: GameplayConfig
    ships*: ShipsConfig
    groundUnits*: GroundUnitsConfig
    facilities*: FacilitiesConfig
    combat*: CombatConfig
    economy*: EconomyConfig
    prestige*: PrestigeConfig
    espionage*: EspionageConfig
    tech*: TechConfig

  ConfigError* = object of CatchableError
    ## Exception raised when configuration is invalid or missing

  KdlConfigContext* = object
    ## Context for error reporting during config parsing
    filepath*: string
    nodePath*: seq[string]  # Track nested node path for errors

