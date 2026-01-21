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

  # Convert Table to seq by house index (0-11)
  result.houses = newSeqOfCap[(string, string)](12)
  for i in 0 ..< 12:
    if i.int32 in entry.houses:
      let houseData = entry.houses[i.int32]
      result.houses.add((houseData.name, houseData.color))
    else:
      # Fallback if house data missing
      result.houses.add(("House " & $i, "gray"))

proc parseThemeEntry(node: KdlNode, ctx: var KdlConfigContext): ThemeEntry =
  ## Parse a single theme entry from KDL node
  ## Per types-guide.md: Use Table[int32, T] for numbered sequences
  let nameAttr = node.stringAttribute("name", ctx)
  if nameAttr.isNone:
    let path = ctx.nodePath.join(".")
    raise newConfigError(
      "Theme node missing required 'name' attribute in " & path
    )

  result = ThemeEntry(
    name: nameAttr.get(),
    description: node.requireString("description", ctx),
    houses: initTable[int32, HouseThemeData]()
  )

  # Parse house data for each house index (0-11)
  for i in 0 ..< 12:
    let houseIdx = i.int32
    let nameProp = "house" & $i & "Name"
    let colorProp = "house" & $i & "Color"

    result.houses[houseIdx] = HouseThemeData(
      name: node.requireString(nameProp, ctx),
      color: node.requireString(colorProp, ctx)
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
        if result.activeTheme.len == 0:
          result.activeTheme = entry.name

  logInfo("Config", "Loaded themes configuration", "path=", configPath)
