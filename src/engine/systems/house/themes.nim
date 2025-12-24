## House Theme Configuration Loader
##
## Loads house themes from config/house_themes.toml
## Allows switching between different naming schemes (Dune, Generic, Classical)

import std/[tables, strutils, os]
import toml_serialization
import ../../../common/logger

type
  ThemeEntry* = object
    name*: string
    description*: string
    legal_warning*: string
    # All 12 houses inline
    house_0_name*, house_0_color*: string
    house_1_name*, house_1_color*: string
    house_2_name*, house_2_color*: string
    house_3_name*, house_3_color*: string
    house_4_name*, house_4_color*: string
    house_5_name*, house_5_color*: string
    house_6_name*, house_6_color*: string
    house_7_name*, house_7_color*: string
    house_8_name*, house_8_color*: string
    house_9_name*, house_9_color*: string
    house_10_name*, house_10_color*: string
    house_11_name*, house_11_color*: string

  ThemeFile* = object
    theme*: seq[ThemeEntry]

  HouseTheme* = object
    name*: string
    description*: string
    legalWarning*: string
    houses*: seq[tuple[name: string, color: string]]  # Indexed by position 0-11

  ThemeConfig* = object
    themes*: Table[string, HouseTheme]
    activeTheme*: string

proc toHouseTheme(entry: ThemeEntry): HouseTheme =
  ## Convert TOML structure to internal HouseTheme representation
  result.name = entry.name
  result.description = entry.description
  result.legalWarning = entry.legal_warning

  # Extract house names and colors (positions 0-11)
  result.houses = @[
    (entry.house_0_name, entry.house_0_color),
    (entry.house_1_name, entry.house_1_color),
    (entry.house_2_name, entry.house_2_color),
    (entry.house_3_name, entry.house_3_color),
    (entry.house_4_name, entry.house_4_color),
    (entry.house_5_name, entry.house_5_color),
    (entry.house_6_name, entry.house_6_color),
    (entry.house_7_name, entry.house_7_color),
    (entry.house_8_name, entry.house_8_color),
    (entry.house_9_name, entry.house_9_color),
    (entry.house_10_name, entry.house_10_color),
    (entry.house_11_name, entry.house_11_color)
  ]

proc loadThemeConfig*(themeFile: string = "config/house_themes.toml",
                       activeThemeName: string = "dune"): ThemeConfig =
  ## Load theme configuration from TOML file
  result.themes = initTable[string, HouseTheme]()

  # Load house_themes.toml
  if not fileExists(themeFile):
    raise newException(IOError, "House themes config not found: " & themeFile)

  let themeContent = readFile(themeFile)
  let themeData = Toml.decode(themeContent, ThemeFile)

  # Convert all themes to internal representation
  for entry in themeData.theme:
    result.themes[entry.name] = toHouseTheme(entry)

  # Set active theme
  result.activeTheme = activeThemeName

proc getActiveTheme*(config: ThemeConfig): HouseTheme =
  ## Get the currently active theme
  if config.activeTheme in config.themes:
    return config.themes[config.activeTheme]
  else:
    # Fallback to "generic" theme if active theme not found
    if "generic" in config.themes:
      return config.themes["generic"]
    else:
      # Ultimate fallback - return first available theme
      for theme in config.themes.values:
        return theme
      raise newException(ValueError, "No themes available in configuration")

proc getHouseName*(theme: HouseTheme, position: int): string =
  ## Get house name for given position (0-11)
  if position < 0 or position >= theme.houses.len:
    return "House" & $(position + 1)  # Fallback naming
  return theme.houses[position].name

proc getHouseColor*(theme: HouseTheme, position: int): string =
  ## Get house color for given position (0-11)
  if position < 0 or position >= theme.houses.len:
    return "white"  # Fallback color
  return theme.houses[position].color

# Module initialization - load theme config at compile time or runtime
var globalThemeConfig*: ThemeConfig

proc initializeThemes*() =
  ## Initialize global theme configuration
  globalThemeConfig = loadThemeConfig()

  # Log active theme
  let theme = getActiveTheme(globalThemeConfig)
  logInfo("Config", "House theme loaded",
          "name=", theme.name, " description=", theme.description)
  if theme.legalWarning != "none":
    logWarn("Config", "Theme legal warning", "warning=", theme.legalWarning)

when isMainModule:
  # Test theme loading
  logDebug("Test", "Testing House Theme Loader")
  logDebug("Test", "==========================")

  let config = loadThemeConfig()
  logDebug("Test", "Available themes", "count=", $config.themes.len)
  for themeName, theme in config.themes:
    logDebug("Test", "Theme details",
            "name=", theme.name, " description=", theme.description,
            " legalWarning=", theme.legalWarning)
    logDebug("Test", "Theme houses:")
    for i, house in theme.houses:
      logDebug("Test", "House",
              "index=", $i, " name=", house.name, " color=", house.color)

  logDebug("Test", "Active theme", "name=", config.activeTheme)
  let activeTheme = getActiveTheme(config)
  logDebug("Test", "Active theme details",
          "name=", activeTheme.name, " description=", activeTheme.description)
  logDebug("Test", "First 4 houses:")
  for i in 0..3:
    logDebug("Test", "House",
            "index=", $i, " name=", getHouseName(activeTheme, i),
            " color=", getHouseColor(activeTheme, i))
