## House Theme Configuration Loader
##
## Loads house themes from config/house_themes.kdl
## Allows switching between different naming schemes (Dune, Generic, Classical)

import std/[tables, strutils]
import kdl
import kdl_config_helpers
import ../../../common/logger

type
  ThemeEntry* = object
    name*: string
    description*: string
    legalWarning*: string
    # All 12 houses inline
    house0Name*, house0Color*: string
    house1Name*, house1Color*: string
    house2Name*, house2Color*: string
    house3Name*, house3Color*: string
    house4Name*, house4Color*: string
    house5Name*, house5Color*: string
    house6Name*, house6Color*: string
    house7Name*, house7Color*: string
    house8Name*, house8Color*: string
    house9Name*, house9Color*: string
    house10Name*, house10Color*: string
    house11Name*, house11Color*: string

  HouseTheme* = object
    name*: string
    description*: string
    legalWarning*: string
    houses*: seq[tuple[name: string, color: string]] # Indexed by position 0-11

  ThemeConfig* = object
    themes*: Table[string, HouseTheme]
    activeTheme*: string

proc toHouseTheme(entry: ThemeEntry): HouseTheme =
  ## Convert KDL structure to internal HouseTheme representation
  result.name = entry.name
  result.description = entry.description
  result.legalWarning = entry.legalWarning

  # Extract house names and colors (positions 0-11)
  result.houses =
    @[
      (entry.house0Name, entry.house0Color),
      (entry.house1Name, entry.house1Color),
      (entry.house2Name, entry.house2Color),
      (entry.house3Name, entry.house3Color),
      (entry.house4Name, entry.house4Color),
      (entry.house5Name, entry.house5Color),
      (entry.house6Name, entry.house6Color),
      (entry.house7Name, entry.house7Color),
      (entry.house8Name, entry.house8Color),
      (entry.house9Name, entry.house9Color),
      (entry.house10Name, entry.house10Color),
      (entry.house11Name, entry.house11Color),
    ]

proc parseThemeEntry(node: KdlNode, ctx: var KdlConfigContext): ThemeEntry =
  ## Parse a single theme entry from KDL node
  let nameAttr = node.getStringAttribute("name", ctx)
  if nameAttr.isNone:
    raise newException(
      ConfigError,
      "Theme node missing required 'name' attribute: " & ctx.nodePath,
    )

  result = ThemeEntry(
    name: nameAttr.get(),
    description: node.requireString("description", ctx),
    legalWarning: node.requireString("legalWarning", ctx),
    house0Name: node.requireString("house0Name", ctx),
    house0Color: node.requireString("house0Color", ctx),
    house1Name: node.requireString("house1Name", ctx),
    house1Color: node.requireString("house1Color", ctx),
    house2Name: node.requireString("house2Name", ctx),
    house2Color: node.requireString("house2Color", ctx),
    house3Name: node.requireString("house3Name", ctx),
    house3Color: node.requireString("house3Color", ctx),
    house4Name: node.requireString("house4Name", ctx),
    house4Color: node.requireString("house4Color", ctx),
    house5Name: node.requireString("house5Name", ctx),
    house5Color: node.requireString("house5Color", ctx),
    house6Name: node.requireString("house6Name", ctx),
    house6Color: node.requireString("house6Color", ctx),
    house7Name: node.requireString("house7Name", ctx),
    house7Color: node.requireString("house7Color", ctx),
    house8Name: node.requireString("house8Name", ctx),
    house8Color: node.requireString("house8Color", ctx),
    house9Name: node.requireString("house9Name", ctx),
    house9Color: node.requireString("house9Color", ctx),
    house10Name: node.requireString("house10Name", ctx),
    house10Color: node.requireString("house10Color", ctx),
    house11Name: node.requireString("house11Name", ctx),
    house11Color: node.requireString("house11Color", ctx)
  )

proc loadThemeConfig*(
    themeFile: string = "config/house_themes.kdl", activeThemeName: string = "dune"
): ThemeConfig =
  ## Load theme configuration from KDL file
  result.themes = initTable[string, HouseTheme]()

  let doc = loadKdlConfig(themeFile)
  var ctx = newContext(themeFile)

  # Find all theme nodes
  for node in doc:
    if node.name == "theme":
      ctx.withNode("theme"):
        let entry = parseThemeEntry(node, ctx)
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
    return "House" & $(position + 1) # Fallback naming
  return theme.houses[position].name

proc getHouseColor*(theme: HouseTheme, position: int): string =
  ## Get house color for given position (0-11)
  if position < 0 or position >= theme.houses.len:
    return "white" # Fallback color
  return theme.houses[position].color

# Module initialization - load theme config at compile time or runtime
var globalThemeConfig*: ThemeConfig

proc initializeThemes*() =
  ## Initialize global theme configuration
  globalThemeConfig = loadThemeConfig()

  # Log active theme
  let theme = getActiveTheme(globalThemeConfig)
  logInfo(
    "Config", "House theme loaded", "name=", theme.name, " description=",
    theme.description,
  )
  if theme.legalWarning != "none":
    logWarn("Config", "Theme legal warning", "warning=", theme.legalWarning)

when isMainModule:
  # Test theme loading
  logDebug("Test", "Testing House Theme Loader")
  logDebug("Test", "==========================")

  let config = loadThemeConfig()
  logDebug("Test", "Available themes", "count=", $config.themes.len)
  for themeName, theme in config.themes:
    logDebug(
      "Test", "Theme details", "name=", theme.name, " description=", theme.description,
      " legalWarning=", theme.legalWarning,
    )
    logDebug("Test", "Theme houses:")
    for i, house in theme.houses:
      logDebug(
        "Test", "House", "index=", $i, " name=", house.name, " color=", house.color
      )

  logDebug("Test", "Active theme", "name=", config.activeTheme)
  let activeTheme = getActiveTheme(config)
  logDebug(
    "Test", "Active theme details", "name=", activeTheme.name, " description=",
    activeTheme.description,
  )
  logDebug("Test", "First 4 houses:")
  for i in 0 .. 3:
    logDebug(
      "Test",
      "House",
      "index=",
      $i,
      " name=",
      getHouseName(activeTheme, i),
      " color=",
      getHouseColor(activeTheme, i),
    )
