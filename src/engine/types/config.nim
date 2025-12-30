import ./config/[
  gameplay, ships, ground_units, facilities, combat, economy, prestige, espionage,
  tech, construction, game_setup, house_themes, guild,
  starmap, limits
]

export gameplay, ships, ground_units, facilities, combat, economy, prestige, espionage,
  tech, construction, game_setup, house_themes, guild,
  starmap, limits

type
  GameConfig* = object
    gameplay*: GameplayConfig
    themes*: ThemesConfig
    starmap*: StarmapConfig
    ships*: ShipsConfig
    groundUnits*: GroundUnitsConfig
    facilities*: FacilitiesConfig
    combat*: CombatConfig
    economy*: EconomyConfig
    espionage*: EspionageConfig
    tech*: TechConfig
    limits*: LimitsConfig
    construction*: ConstructionConfig
    guild*: GuildConfig
    prestige*: PrestigeConfig

  GameSetup* = object
    gameParameters*: GameParametersConfig
    mapGeneration*: MapGenerationConfig
    victoryConditions*: VictoryConditionsConfig
    startingResources*: StartingResourcesConfig
    startingTech*: StartingTechConfig
    startingFleets*: StartingFleetsConfig
    startingFacilities*: StartingFacilitiesConfig
    startingGroundForces*: StartingGroundForcesConfig
    homeworld*: HomeworldConfig

  ConfigError* = ref object of CatchableError
    ## Exception raised when configuration is invalid or missing

  KdlConfigContext* = object
    ## Context for error reporting during config parsing
    filepath*: string
    nodePath*: seq[string]  # Track nested node path for errors

