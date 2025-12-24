## Game Setup Configuration Loader
##
## Loads game setup parameters from game_setup/standard.toml using toml_serialization
## Defines starting conditions for players (homeworld, fleet, facilities, tech)

import std/[os, strutils, options, tables]
import toml_serialization
import ../../common/logger
import ../types/starmap

type
  GameInfoConfig* = object ## Game metadata
    name*: string
    description*: string
    recommended_players*: int32
    estimated_duration*: string

  VictoryConditionsConfig* = object ## Victory conditions
    primary_condition*: string
    secondary_condition*: string
    prestige_threshold*: int32
    turn_limit*: int32 # NEW: Turn limit for turn_limit victory mode

  MapConfig* = object ## Map generation settings
    size*: string
    systems*: int32
    jump_lane_density*: string
    starting_distance*: string

  StartingResourcesConfig* = object ## Starting economic resources
    treasury*: int32
    starting_prestige*: int32
    default_tax_rate*: float32

  StartingTechConfig* = object ## Initial technology levels per gameplay.md:1.2
    economic_level*: int32
    science_level*: int32
    construction_tech*: int32
    weapons_tech*: int32
    terraforming_tech*: int32
    electronic_intelligence*: int32
    cloaking_tech*: int32
    shield_tech*: int32
    counter_intelligence*: int32
    fighter_doctrine*: int32
    advanced_carrier_ops*: int32

  StartingFleetConfig* = object ## Initial fleet composition
    fleet_count*: int32 # Number of individual fleets to create
    # Fallback aggregated counts (used if individual fleet sections not available)
    etac*: int32
    light_cruiser*: int32
    destroyer*: int32
    scout*: int32

  FleetConfig* = object ## Individual fleet configuration (new per-fleet format)
    ships*: seq[string] # Ship class names (e.g., ["ETAC", "LightCruiser"])
    cargo_ptu*: Option[int32] # Optional PTU cargo override for ETACs

  HouseNamingConfig* = object ## House naming configuration
    name_pattern*: string # Pattern with {index} placeholder
    use_theme_names*: bool # Whether to use house_themes.toml

  StartingFacilitiesConfig* = object ## Homeworld starting facilities
    spaceports*: int32
    shipyards*: int32
    starbases*: int32
    ground_batteries*: int32
    planetary_shields*: int32

  StartingGroundForcesConfig* = object ## Homeworld starting ground forces
    armies*: int32
    marines*: int32

  HomeworldConfig* = object ## Homeworld characteristics
    planet_class*: string # "Eden"
    raw_quality*: string # "Abundant"
    colony_level*: int32 # Infrastructure level (5 = Level V)
    population_units*: int32 # Starting population in PU (840)
    industrial_units*: int32

  GameSetupConfig* = object ## Complete game setup configuration
    game_info*: GameInfoConfig
    victory_conditions*: VictoryConditionsConfig
    map*: MapConfig
    starting_resources*: StartingResourcesConfig
    starting_tech*: StartingTechConfig
    starting_fleet*: StartingFleetConfig
    starting_facilities*: StartingFacilitiesConfig
    starting_ground_forces*: StartingGroundForcesConfig
    homeworld*: HomeworldConfig
    house_naming*: Option[HouseNamingConfig] # Optional, defaults if not present

proc loadGameSetupConfig*(
    configPath: string = "game_setup/standard.toml"
): GameSetupConfig =
  ## Load game setup configuration from TOML file
  ## Uses toml_serialization for type-safe parsing

  if not fileExists(configPath):
    raise newException(IOError, "Game setup config not found: " & configPath)

  let configContent = readFile(configPath)
  result = Toml.decode(configContent, GameSetupConfig)

  logInfo("Config", "Loaded game setup configuration", "path=", configPath)

proc parsePlanetClass*(className: string): PlanetClass =
  ## Parse planet class string from config
  case className.toLower()
  of "extreme":
    PlanetClass.Extreme
  of "desolate":
    PlanetClass.Desolate
  of "hostile":
    PlanetClass.Hostile
  of "harsh":
    PlanetClass.Harsh
  of "benign":
    PlanetClass.Benign
  of "lush":
    PlanetClass.Lush
  of "eden":
    PlanetClass.Eden
  else:
    raise newException(ValueError, "Invalid planet class: " & className)

proc parseResourceRating*(ratingName: string): ResourceRating =
  ## Parse resource rating string from config
  case ratingName.toLower()
  of "verypoor", "very_poor":
    ResourceRating.VeryPoor
  of "poor":
    ResourceRating.Poor
  of "abundant":
    ResourceRating.Abundant
  of "rich":
    ResourceRating.Rich
  of "veryrich", "very_rich":
    ResourceRating.VeryRich
  else:
    raise newException(ValueError, "Invalid resource rating: " & ratingName)

proc parseFleetConfigSection*(
    configContent: string, fleetIdx: int
): Option[FleetConfig] =
  ## Parse a single [fleetN] section from TOML content
  ## Returns Some(FleetConfig) if section exists and is valid, None otherwise
  let sectionName = "[fleet" & $fleetIdx & "]"
  let sectionStart = configContent.find(sectionName)

  if sectionStart < 0:
    return none(FleetConfig)

  # Skip past the section header line to start of actual content
  var contentStart = sectionStart + sectionName.len
  while contentStart < configContent.len and configContent[contentStart] != '\n':
    contentStart += 1
  contentStart += 1 # Skip the newline

  # Find the end of this section (next [section] header at start of line, or end of file)
  var sectionEnd = configContent.len
  var i = contentStart
  while i < configContent.len:
    # Check if this is a new section header ([ at start of line)
    if configContent[i] == '[':
      # Check if this [ is at the start of a line (after newline or whitespace)
      var isLineStart = true
      if i > contentStart:
        var j = i - 1
        while j >= contentStart and configContent[j] != '\n':
          if configContent[j] notin {' ', '\t', '\r'}:
            isLineStart = false
            break
          j -= 1
      if isLineStart:
        sectionEnd = i
        break
    i += 1

  let sectionContent = configContent[contentStart ..< sectionEnd]

  # Parse ships array - look for: ships = ["Ship1", "Ship2"]
  var ships: seq[string] = @[]
  let shipsPattern = "ships"
  let shipsStart = sectionContent.find(shipsPattern)

  if shipsStart >= 0:
    # Find the array content between [ and ]
    let arrayStart = sectionContent.find("[", shipsStart)

    if arrayStart >= 0:
      let arrayEnd = sectionContent.find("]", arrayStart)

      if arrayEnd > arrayStart:
        let arrayContent = sectionContent[arrayStart + 1 ..< arrayEnd]

        # Split by comma and clean up quotes
        for shipStr in arrayContent.split(','):
          let cleaned = shipStr.strip().strip(chars = {'"', '\''})
          if cleaned.len > 0:
            ships.add(cleaned)

  # Parse optional cargo_ptu
  var cargoPtu: Option[int32] = none(int32)
  let cargoPattern = "cargo_ptu"
  let cargoStart = sectionContent.find(cargoPattern)
  if cargoStart >= 0:
    # Extract the number after cargo_ptu =
    let eqPos = sectionContent.find("=", cargoStart)
    if eqPos >= 0:
      var numStr = ""
      for i in (eqPos + 1) ..< sectionContent.len:
        let c = sectionContent[i]
        if c in '0' .. '9':
          numStr.add(c)
        elif numStr.len > 0:
          break
      if numStr.len > 0:
        try:
          cargoPtu = some(parseInt(numStr).int32)
        except ValueError:
          discard

  if ships.len > 0:
    return some(FleetConfig(ships: ships, cargoPtu: cargoPtu))
  else:
    return none(FleetConfig)

proc loadIndividualFleetConfigs*(
    configPath: string = "game_setup/fleets.toml"
): Table[int, FleetConfig] =
  ## Load individual fleet configurations from TOML file
  ## Parses [fleet1], [fleet2], ... [fleetN] sections
  ## Returns table mapping fleet index to FleetConfig
  ##
  ## Note: Uses separate fleets.toml file to avoid toml_serialization conflicts
  ## with indexed table sections in main standard.toml

  result = initTable[int, FleetConfig]()

  if not fileExists(configPath):
    logWarn("Config", "Game setup config not found", "path=", configPath)
    return

  let configContent = readFile(configPath)
  logDebug(
    "Config",
    "Loaded fleet config file",
    "path=",
    configPath,
    "size=",
    $configContent.len,
  )

  # Parse individual [fleetN] sections (1-indexed)
  var fleetIdx = 1
  while true:
    let fleetConfig = parseFleetConfigSection(configContent, fleetIdx)
    if fleetConfig.isNone:
      break

    result[fleetIdx] = fleetConfig.get()
    logDebug(
      "Config",
      "Loaded fleet config",
      "fleet=",
      $fleetIdx,
      "ships=",
      $fleetConfig.get().ships.len,
    )
    fleetIdx += 1

  logInfo("Config", "Loaded individual fleet configs", "count=", $(fleetIdx - 1))

proc getHouseNamePattern*(config: GameSetupConfig): string =
  ## Get house naming pattern from config, with fallback default
  if config.house_naming.isSome:
    return config.house_naming.get().name_pattern
  else:
    return "House{index}" # Default pattern

proc useThemeNames*(config: GameSetupConfig): bool =
  ## Check if config specifies using theme names from house_themes.toml
  if config.house_naming.isSome:
    return config.house_naming.get().use_theme_names
  else:
    return false # Default: don't use theme names

## Global configuration instance

var globalGameSetupConfig* = loadGameSetupConfig()

## Helper to reload configuration (for testing)

proc reloadGameSetupConfig*() =
  ## Reload configuration from file
  globalGameSetupConfig = loadGameSetupConfig()
