import ./config/[
  gameplay, ships, ground_units, facilities, combat, economy, prestige, espionage,
  tech, military, standing_commands, construction, game_setup, house_themes, guild,
  starmap
]

export gameplay, ships, ground_units, facilities, combat, economy, prestige, espionage,
  tech, military, standing_commands, construction, game_setup, house_themes, guild,
  starmap

type
  GameConfig* = object
    gameSetup*: GameSetupConfig
    gameplay*: GameplayConfig
    houseThemes*: ThemeConfig
    starmap*: StarmapConfig
    ships*: ShipsConfig
    groundUnits*: GroundUnitsConfig
    facilities*: FacilitiesConfig
    combat*: CombatConfig
    economy*: EconomyConfig
    prestige*: PrestigeConfig
    espionage*: EspionageConfig
    tech*: TechConfig
    military*: MilitaryConfig
    standingCommands*: StandingCommandsConfig
    construction*: ConstructionConfig
    guild*: GuildConfig

    # Dynamic scaling multipliers
    prestigeMultiplier*: float64
    populationMultiplier*: float64

  ConfigError* = object of CatchableError
    ## Exception raised when configuration is invalid or missing

  KdlConfigContext* = object
    ## Context for error reporting during config parsing
    filepath*: string
    nodePath*: seq[string]  # Track nested node path for errors

