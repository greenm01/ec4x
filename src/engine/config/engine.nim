import ../types/[config, ship]
import ./[
  ships_config, ground_units_config, facilities_config,
  combat_config, economy_config, prestige_config
]

# Master config loading function

let gameConfig* {.threadvar.}: GameConfig = loadGameConfig()

proc loadGameConfig(dataDir: string = "config"): GameConfig =
  ## Load and validate all game configuration files
  ## Raises ConfigError if any config file is missing or invalid

  result.ships = loadShipsConfig(dataDir / "ships.kdl")
  result.groundUnits = loadGroundUnitsConfig(dataDir / "ground_units.kdl")
  result.facilities = loadFacilitiesConfig(dataDir / "facilities.kdl")
  result.combat = loadCombatConfig(dataDir / "combat.kdl")
  result.economy = loadEconomyConfig(dataDir / "economy.kdl")
  result.prestige = loadPrestigeConfig(dataDir / "prestige.kdl")
