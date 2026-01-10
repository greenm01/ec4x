import std/os
import ../types/config
import ./[
  game_setup_config, gameplay_config, house_themes_config, starmap_config,
  ships_config, ground_units_config, facilities_config, combat_config,
  economy_config, prestige_config, espionage_config, tech_config,
  limits_config, construction_config, guild_config
]

proc loadGameConfig*(configDir: string = "config"): GameConfig =
  ## Load and validate all game configuration files
  ## Raises ConfigError if any config file is missing or invalid
  result.gameplay = loadGameplayConfig(configDir / "gameplay.kdl")
  result.themes = loadThemesConfig(configDir / "dynatoi.kdl")
  result.starmap = loadStarmapConfig(configDir / "starmap.kdl")
  result.ships = loadShipsConfig(configDir / "ships.kdl")
  result.groundUnits = loadGroundUnitsConfig(configDir / "ground_units.kdl")
  result.facilities = loadFacilitiesConfig(configDir / "facilities.kdl")
  result.combat = loadCombatConfig(configDir / "combat.kdl")
  result.economy = loadEconomyConfig(configDir / "economy.kdl")
  result.prestige = loadPrestigeConfig(configDir / "kdl")
  result.espionage = loadEspionageConfig(configDir / "espionage.kdl")
  result.tech = loadTechConfig(configDir / "tech.kdl")
  result.limits = loadLimitsConfig(configDir / "limits.kdl")
  result.construction = loadConstructionConfig(configDir / "construction.kdl")
  result.guild = loadGuildConfig(configDir / "guild.kdl")

proc loadGameSetup*(setupPath: string): GameSetup =
  result = loadGameSetupConfig(setupPath)
  
