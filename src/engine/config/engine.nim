import ../types/[config, ship]
import ./[
  ships_config, ground_units_config, facilities_config,
  combat_config, economy_config, prestige_config
]

# Master config loading function
proc loadGameConfig(dataDir: string = "config"): GameConfig =
  ## Load and validate all game configuration files
  ## Raises ConfigError if any config file is missing or invalid

  let gameSetupConfig = loadGameSetupConfig()
  let gameplayConfig = loadGameplayConfig()
  let houseThemesConfig = loadHouseThemesConfig()
  let starmapConfig = loadStarmapConfig()
  let shipsConfig = loadShipsConfig(dataDir / "ships.kdl")
  let groundUnitsConfig = loadGroundUnitsConfig(dataDir / "ground_units.kdl")
  let facilitiesConfig = loadFacilitiesConfig(dataDir / "facilities.kdl")
  let combatConfig = loadCombatConfig(dataDir / "combat.kdl")
  let economyConfig = loadEconomyConfig(dataDir / "economy.kdl")
  let prestigeConfig = loadPrestigeConfig(dataDir / "prestige.kdl")
  let espionageConfig = loadEspionageConfig()
  let techConfig = loadTechConfig()
  let militaryConfig = loadMilitaryConfig()
  let standingCommandConfig = loadStandingCommandConfig()
  let constructionConfig = loadConstructionConfig()
  let populationConfig = loadPopulationCondfig()

  result.prestigeMultiplier = prestigeMultiplier
