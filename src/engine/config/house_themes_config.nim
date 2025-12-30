## House Theme Configuration Loader
##
## Loads house themes from config/house_themes.kdl
## Allows switching between different naming schemes (Dune, Generic, Classical)

import std/[tables, strutils]
import kdl
import kdl_helpers
import ../../common/logger
import ../types/config

proc toHouseTheme(entry: ThemeEntry): HouseTheme =
  ## Convert KDL structure to internal HouseTheme representation
  result.name = entry.name
  result.description = entry.description

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
    let path = ctx.nodePath.join(".")
    raise newConfigError(
      "Theme node missing required 'name' attribute in " & path
    )

  result = ThemeEntry(
    name: nameAttr.get(),
    description: node.requireString("description", ctx),
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

proc loadThemesConfig*(configPath: string): ThemesConfig =
  ## Load theme configuration from KDL file
  result.themes = initTable[string, HouseTheme]()

  let doc = loadKdlConfig(configPath)
  var ctx = newContext(configPath)

  # Find all theme nodes
  for node in doc:
    if node.name == "theme":
      ctx.withNode("theme"):
        let entry = parseThemeEntry(node, ctx)
        result.themes[entry.name] = toHouseTheme(entry)

  logInfo("Config", "Loaded themes configuration", "path=", configPath)
