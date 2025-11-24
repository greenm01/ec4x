## Technology Configuration Loader
##
## Loads technology research costs and effects from config/tech.toml
## Allows runtime configuration for all tech trees

import std/[os]
import toml_serialization

type
  StartingTechConfig* = object
    ## Starting tech levels per economy.md:4.0
    ## CRITICAL: ALL tech starts at level 1, not 0!
    economic_level*: int            # EL1
    science_level*: int             # SL1
    construction_tech*: int         # CST1
    weapons_tech*: int              # WEP1
    terraforming_tech*: int         # TER1
    electronic_intelligence*: int   # ELI1
    cloaking_tech*: int             # CLK1
    shield_tech*: int               # SLD1 (Planetary Shields)
    counter_intelligence*: int      # CIC1
    fighter_doctrine*: int          # FD I (starts at 1)
    advanced_carrier_ops*: int      # ACO I (starts at 1)

  TechConfig* = object
    ## Technology configuration from tech.toml
    starting_tech*: StartingTechConfig

proc loadTechConfig*(configPath: string = "config/tech.toml"): TechConfig =
  ## Load technology configuration from TOML file
  ## Uses toml_serialization for type-safe parsing

  if not fileExists(configPath):
    raise newException(IOError, "Tech config not found: " & configPath)

  let configContent = readFile(configPath)
  result = Toml.decode(configContent, TechConfig)

  echo "[Config] Loaded technology configuration from ", configPath

## Global configuration instance

var globalTechConfig* = loadTechConfig()

## Helper to reload configuration (for testing)

proc reloadTechConfig*() =
  ## Reload configuration from file
  globalTechConfig = loadTechConfig()
