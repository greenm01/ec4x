## Game Setup Configuration Loader
##
## Loads game setup parameters from game_setup/standard.toml using toml_serialization
## Defines starting conditions for players (homeworld, fleet, facilities, tech)

import std/[os, strutils]
import toml_serialization
import ../../common/logger
import ../../common/types/planets

type
  GameInfoConfig* = object
    ## Game metadata
    name*: string
    description*: string
    recommended_players*: int
    estimated_duration*: string

  VictoryConditionsConfig* = object
    ## Victory conditions
    primary_condition*: string
    secondary_condition*: string
    prestige_threshold*: int
    turn_limit*: int  # NEW: Turn limit for turn_limit victory mode

  MapConfig* = object
    ## Map generation settings
    size*: string
    systems*: int
    jump_lane_density*: string
    starting_distance*: string

  StartingResourcesConfig* = object
    ## Starting economic resources
    treasury*: int
    starting_prestige*: int
    default_tax_rate*: float

  StartingTechConfig* = object
    ## Initial technology levels per gameplay.md:1.2
    economic_level*: int
    science_level*: int
    construction_tech*: int
    weapons_tech*: int
    terraforming_tech*: int
    electronic_intelligence*: int
    cloaking_tech*: int
    shield_tech*: int
    counter_intelligence*: int
    fighter_doctrine*: int
    advanced_carrier_ops*: int

  StartingFleetConfig* = object
    ## Initial fleet composition
    etac*: int
    light_cruiser*: int
    destroyer*: int
    scout*: int

  StartingFacilitiesConfig* = object
    ## Homeworld starting facilities
    spaceports*: int
    shipyards*: int
    starbases*: int
    ground_batteries*: int
    planetary_shields*: int

  StartingGroundForcesConfig* = object
    ## Homeworld starting ground forces
    armies*: int
    marines*: int

  HomeworldConfig* = object
    ## Homeworld characteristics
    planet_class*: string      # "Eden"
    raw_quality*: string        # "Abundant"
    colony_level*: int          # Infrastructure level (5 = Level V)
    population_units*: int      # Starting population in PU (840)
    industrial_units*: int

  GameSetupConfig* = object
    ## Complete game setup configuration
    game_info*: GameInfoConfig
    victory_conditions*: VictoryConditionsConfig
    map*: MapConfig
    starting_resources*: StartingResourcesConfig
    starting_tech*: StartingTechConfig
    starting_fleet*: StartingFleetConfig
    starting_facilities*: StartingFacilitiesConfig
    starting_ground_forces*: StartingGroundForcesConfig
    homeworld*: HomeworldConfig

proc loadGameSetupConfig*(configPath: string = "game_setup/standard.toml"): GameSetupConfig =
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
  of "extreme": PlanetClass.Extreme
  of "desolate": PlanetClass.Desolate
  of "hostile": PlanetClass.Hostile
  of "harsh": PlanetClass.Harsh
  of "benign": PlanetClass.Benign
  of "lush": PlanetClass.Lush
  of "eden": PlanetClass.Eden
  else:
    raise newException(ValueError, "Invalid planet class: " & className)

proc parseResourceRating*(ratingName: string): ResourceRating =
  ## Parse resource rating string from config
  case ratingName.toLower()
  of "verypoor", "very_poor": ResourceRating.VeryPoor
  of "poor": ResourceRating.Poor
  of "abundant": ResourceRating.Abundant
  of "rich": ResourceRating.Rich
  of "veryrich", "very_rich": ResourceRating.VeryRich
  else:
    raise newException(ValueError, "Invalid resource rating: " & ratingName)

## Global configuration instance

var globalGameSetupConfig* = loadGameSetupConfig()

## Helper to reload configuration (for testing)

proc reloadGameSetupConfig*() =
  ## Reload configuration from file
  globalGameSetupConfig = loadGameSetupConfig()
