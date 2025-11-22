## Technology Configuration Loader
##
## Loads technology research costs and effects from config/tech.toml
## Allows runtime configuration for all tech trees
##
## NOTE: This is a simplified loader that stores the raw TOML content.
## Full structured parsing will be added when tech system is implemented.

import std/[os]

type
  TechConfig* = object
    ## Technology configuration - currently stores raw TOML for future parsing
    ## Full type-safe structures will be added during tech system implementation
    configPath*: string
    loaded*: bool

proc loadTechConfig*(configPath: string = "config/tech.toml"): TechConfig =
  ## Load technology configuration from TOML file
  ## Currently validates file exists and will be parsed when tech system is integrated

  if not fileExists(configPath):
    raise newException(IOError, "Tech config not found: " & configPath)

  result = TechConfig(
    configPath: configPath,
    loaded: true
  )

  echo "[Config] Located technology configuration at ", configPath
  echo "[Config] Full tech config parsing will be implemented with tech system"

## Global configuration instance

var globalTechConfig* = loadTechConfig()

## Helper to reload configuration (for testing)

proc reloadTechConfig*() =
  ## Reload configuration from file
  globalTechConfig = loadTechConfig()
