## EC4X Configuration Loading and Validation
## Central module for loading and validating all game configuration files
## Based on EC4X specifications

import std/[tables, parsecfg, strutils, os]
import ../common/types/units

export ShipClass, ShipStats, GroundUnitType, GroundUnitStats, FacilityType, FacilityStats

type
  ConfigError* = object of CatchableError

  # Combat configuration
  CombatConfig* = object
    criticalHitRoll*: int
    retreatAfterRound*: int
    starbaseCriticalReroll*: bool
    starbaseDieModifier*: int
    # CER tables would go here

  # Economy configuration
  EconomyConfig* = object
    startingTreasury*: int
    startingPopulation*: int
    startingInfrastructure*: int
    naturalGrowthRate*: float
    researchCostBase*: int
    researchCostExponent*: int
    ebpCostPerPoint*: int
    cipCostPerPoint*: int

  # Prestige configuration
  PrestigeConfig* = object
    startingPrestige*: int
    victoryThreshold*: int
    defeatThreshold*: int
    defeatConsecutiveTurns*: int
    # Prestige values would go here as tables

  # Master game configuration
  GameConfig* = object
    ships*: Table[ShipClass, ShipStats]
    groundUnits*: Table[GroundUnitType, GroundUnitStats]
    facilities*: Table[FacilityType, FacilityStats]
    combat*: CombatConfig
    economy*: EconomyConfig
    prestige*: PrestigeConfig

# Helper functions for config parsing

proc getSectionValueInt(config: Config, section, key: string, default: int = 0): int =
  ## Get integer value from config section, with default fallback
  try:
    result = config.getSectionValue(section, key, $default).parseInt()
  except ValueError:
    raise newException(ConfigError, "Invalid integer value for " & section & "." & key)

proc getSectionValueFloat(config: Config, section, key: string, default: float = 0.0): float =
  ## Get float value from config section, with default fallback
  try:
    result = config.getSectionValue(section, key, $default).parseFloat()
  except ValueError:
    raise newException(ConfigError, "Invalid float value for " & section & "." & key)

proc getSectionValueBool(config: Config, section, key: string, default: bool = false): bool =
  ## Get boolean value from config section, with default fallback
  let val = config.getSectionValue(section, key, $default).toLowerAscii()
  result = val in ["true", "yes", "1"]

# Ship config loading and validation

proc shipClassToConfigKey(shipClass: ShipClass): string =
  ## Convert ShipClass enum to config file section key
  case shipClass
  of Fighter: "fighter"
  of Scout: "scout"
  of Raider: "raider"
  of Destroyer: "destroyer"
  of Cruiser: "cruiser"
  of LightCruiser: "light_cruiser"
  of HeavyCruiser: "heavy_cruiser"
  of Battlecruiser: "battlecruiser"
  of Battleship: "battleship"
  of Dreadnought: "dreadnought"
  of SuperDreadnought: "super_dreadnought"
  of Carrier: "carrier"
  of SuperCarrier: "super_carrier"
  of Starbase: "starbase"
  of ETAC: "etac"
  of TroopTransport: "troop_transport"
  of PlanetBreaker: "planet_breaker"

proc loadShipStats(config: Config, shipClass: ShipClass): ShipStats =
  ## Load stats for a single ship class from config
  let key = shipClassToConfigKey(shipClass)

  result.name = config.getSectionValue(key, "name", $shipClass)
  result.class = config.getSectionValue(key, "class", key)
  result.attackStrength = config.getSectionValueInt(key, "attack_strength")
  result.defenseStrength = config.getSectionValueInt(key, "defense_strength")
  result.commandCost = config.getSectionValueInt(key, "command_cost")
  result.commandRating = config.getSectionValueInt(key, "command_rating")
  result.techLevel = config.getSectionValueInt(key, "tech_level")
  result.buildCost = config.getSectionValueInt(key, "build_cost")
  result.upkeepCost = config.getSectionValueInt(key, "upkeep_cost")
  result.specialCapability = config.getSectionValue(key, "special_capability", "")
  result.carryLimit = config.getSectionValueInt(key, "carry_limit", 0)

proc validateShipStats(shipClass: ShipClass, stats: ShipStats) =
  ## Validate ship stats are within acceptable ranges
  if stats.attackStrength < 0:
    raise newException(ConfigError, $shipClass & ": attack_strength cannot be negative")

  if stats.defenseStrength < 0:
    raise newException(ConfigError, $shipClass & ": defense_strength cannot be negative")

  if stats.buildCost <= 0:
    raise newException(ConfigError, $shipClass & ": build_cost must be > 0")

  if stats.upkeepCost < 0:
    raise newException(ConfigError, $shipClass & ": upkeep_cost cannot be negative")

  if stats.techLevel < 0 or stats.techLevel > 10:
    raise newException(ConfigError, $shipClass & ": tech_level must be 0-10")

  if stats.commandCost < 0:
    raise newException(ConfigError, $shipClass & ": command_cost cannot be negative")

  if stats.commandRating < 0:
    raise newException(ConfigError, $shipClass & ": command_rating cannot be negative")

proc loadShipConfig(configPath: string): Table[ShipClass, ShipStats] =
  ## Load and validate ship configuration from file
  if not fileExists(configPath):
    raise newException(ConfigError, "Ship config file not found: " & configPath)

  let config = loadConfig(configPath)
  result = initTable[ShipClass, ShipStats]()

  for shipClass in ShipClass:
    let stats = loadShipStats(config, shipClass)
    validateShipStats(shipClass, stats)
    result[shipClass] = stats

# Ground unit config loading and validation

proc groundUnitTypeToConfigKey(unitType: GroundUnitType): string =
  ## Convert GroundUnitType enum to config file section key
  case unitType
  of PlanetaryShield: "planetary_shield"
  of GroundBattery: "ground_battery"
  of Army: "army"
  of MarineDivision: "marine_division"

proc loadGroundUnitStats(config: Config, unitType: GroundUnitType): GroundUnitStats =
  ## Load stats for a single ground unit type from config
  let key = groundUnitTypeToConfigKey(unitType)

  result.name = config.getSectionValue(key, "name", $unitType)
  result.class = config.getSectionValue(key, "class", key)
  result.cstMin = config.getSectionValueInt(key, "cst_min")
  result.buildCost = config.getSectionValueInt(key, "build_cost")
  result.upkeepCost = config.getSectionValueInt(key, "upkeep_cost")
  result.attackStrength = config.getSectionValueInt(key, "attack_strength")
  result.defenseStrength = config.getSectionValueInt(key, "defense_strength")
  result.buildTime = config.getSectionValueInt(key, "build_time", 1)
  result.maxPerPlanet = config.getSectionValueInt(key, "max_per_planet", -1)

proc validateGroundUnitStats(unitType: GroundUnitType, stats: GroundUnitStats) =
  ## Validate ground unit stats are within acceptable ranges
  if stats.attackStrength < 0:
    raise newException(ConfigError, $unitType & ": attack_strength cannot be negative")

  if stats.defenseStrength < 0:
    raise newException(ConfigError, $unitType & ": defense_strength cannot be negative")

  if stats.buildCost <= 0:
    raise newException(ConfigError, $unitType & ": build_cost must be > 0")

  if stats.upkeepCost < 0:
    raise newException(ConfigError, $unitType & ": upkeep_cost cannot be negative")

  if stats.buildTime < 1:
    raise newException(ConfigError, $unitType & ": build_time must be >= 1")

proc loadGroundUnitConfig(configPath: string): Table[GroundUnitType, GroundUnitStats] =
  ## Load and validate ground unit configuration from file
  if not fileExists(configPath):
    raise newException(ConfigError, "Ground unit config file not found: " & configPath)

  let config = loadConfig(configPath)
  result = initTable[GroundUnitType, GroundUnitStats]()

  for unitType in GroundUnitType:
    let stats = loadGroundUnitStats(config, unitType)
    validateGroundUnitStats(unitType, stats)
    result[unitType] = stats

# Facility config loading and validation

proc facilityTypeToConfigKey(facilityType: FacilityType): string =
  ## Convert FacilityType enum to config file section key
  case facilityType
  of Spaceport: "spaceport"
  of Shipyard: "shipyard"

proc loadFacilityStats(config: Config, facilityType: FacilityType): FacilityStats =
  ## Load stats for a single facility type from config
  let key = facilityTypeToConfigKey(facilityType)

  result.name = config.getSectionValue(key, "name", $facilityType)
  result.class = config.getSectionValue(key, "class", key)
  result.cstMin = config.getSectionValueInt(key, "cst_min")
  result.buildCost = config.getSectionValueInt(key, "build_cost")
  result.upkeepCost = config.getSectionValueInt(key, "upkeep_cost")
  result.defenseStrength = config.getSectionValueInt(key, "defense_strength")
  result.carryLimit = config.getSectionValueInt(key, "carry_limit", 0)
  result.buildTime = config.getSectionValueInt(key, "build_time", 1)
  result.docks = config.getSectionValueInt(key, "docks", 0)
  result.maxPerPlanet = config.getSectionValueInt(key, "max_per_planet", -1)

proc validateFacilityStats(facilityType: FacilityType, stats: FacilityStats) =
  ## Validate facility stats are within acceptable ranges
  if stats.buildCost <= 0:
    raise newException(ConfigError, $facilityType & ": build_cost must be > 0")

  if stats.upkeepCost < 0:
    raise newException(ConfigError, $facilityType & ": upkeep_cost cannot be negative")

  if stats.buildTime < 1:
    raise newException(ConfigError, $facilityType & ": build_time must be >= 1")

  if stats.docks < 0:
    raise newException(ConfigError, $facilityType & ": docks cannot be negative")

proc loadFacilityConfig(configPath: string): Table[FacilityType, FacilityStats] =
  ## Load and validate facility configuration from file
  if not fileExists(configPath):
    raise newException(ConfigError, "Facility config file not found: " & configPath)

  let config = loadConfig(configPath)
  result = initTable[FacilityType, FacilityStats]()

  for facilityType in FacilityType:
    let stats = loadFacilityStats(config, facilityType)
    validateFacilityStats(facilityType, stats)
    result[facilityType] = stats

# Combat config loading

proc loadCombatConfig(configPath: string): CombatConfig =
  ## Load combat configuration from file
  if not fileExists(configPath):
    raise newException(ConfigError, "Combat config file not found: " & configPath)

  let config = loadConfig(configPath)

  result.criticalHitRoll = config.getSectionValueInt("combat", "critical_hit_roll", 9)
  result.retreatAfterRound = config.getSectionValueInt("combat", "retreat_after_round", 1)
  result.starbaseCriticalReroll = config.getSectionValueBool("combat", "starbase_critical_reroll", true)
  result.starbaseDieModifier = config.getSectionValueInt("combat", "starbase_die_modifier", 2)

# Economy config loading

proc loadEconomyConfig(configPath: string): EconomyConfig =
  ## Load economy configuration from file
  if not fileExists(configPath):
    raise newException(ConfigError, "Economy config file not found: " & configPath)

  let config = loadConfig(configPath)

  result.startingTreasury = config.getSectionValueInt("starting_resources", "treasury", 1000)
  result.startingPopulation = config.getSectionValueInt("starting_resources", "starting_population", 5)
  result.startingInfrastructure = config.getSectionValueInt("starting_resources", "starting_infrastructure", 3)
  result.naturalGrowthRate = config.getSectionValueFloat("population", "natural_growth_rate", 0.02)
  result.researchCostBase = config.getSectionValueInt("research", "research_cost_base", 1000)
  result.researchCostExponent = config.getSectionValueInt("research", "research_cost_exponent", 2)
  result.ebpCostPerPoint = config.getSectionValueInt("espionage", "ebp_cost_per_point", 40)
  result.cipCostPerPoint = config.getSectionValueInt("espionage", "cip_cost_per_point", 40)

# Prestige config loading

proc loadPrestigeConfig(configPath: string): PrestigeConfig =
  ## Load prestige configuration from file
  if not fileExists(configPath):
    raise newException(ConfigError, "Prestige config file not found: " & configPath)

  let config = loadConfig(configPath)

  result.startingPrestige = config.getSectionValueInt("game_rules", "starting_prestige", 50)
  result.victoryThreshold = config.getSectionValueInt("game_rules", "victory_prestige", 5000)
  result.defeatThreshold = config.getSectionValueInt("game_rules", "defeat_threshold", 0)
  result.defeatConsecutiveTurns = config.getSectionValueInt("game_rules", "defeat_consecutive_turns", 3)

# Master config loading function

proc loadGameConfig*(dataDir: string = "data"): GameConfig =
  ## Load and validate all game configuration files
  ## Raises ConfigError if any config file is missing or invalid

  result.ships = loadShipConfig(dataDir / "ships_default.toml")
  result.groundUnits = loadGroundUnitConfig(dataDir / "ground_units_default.toml")
  result.facilities = loadFacilityConfig(dataDir / "facilities_default.toml")
  result.combat = loadCombatConfig(dataDir / "combat_default.toml")
  result.economy = loadEconomyConfig(dataDir / "economy_default.toml")
  result.prestige = loadPrestigeConfig(dataDir / "prestige_default.toml")

# Convenience accessors

proc getShipStats*(config: GameConfig, shipClass: ShipClass): ShipStats =
  ## Get ship stats by class, raises KeyError if not found
  result = config.ships[shipClass]

proc getGroundUnitStats*(config: GameConfig, unitType: GroundUnitType): GroundUnitStats =
  ## Get ground unit stats by type, raises KeyError if not found
  result = config.groundUnits[unitType]

proc getFacilityStats*(config: GameConfig, facilityType: FacilityType): FacilityStats =
  ## Get facility stats by type, raises KeyError if not found
  result = config.facilities[facilityType]
