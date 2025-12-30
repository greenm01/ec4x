## Facilities Configuration Loader
##
## Loads facility stats from config/facilities.kdl using nimkdl
## Allows runtime configuration for spaceports and shipyards

import kdl
import kdl_helpers
import ../../common/logger
import ../types/config

proc parseSpaceport(node: KdlNode, ctx: var KdlConfigContext): SpaceportConfig =
  result = SpaceportConfig(
    minCST: node.requireInt32("minCST", ctx),
    buildCost: node.requireInt32("buildCost", ctx),
    maintenancePercent: node.requireFloat32("maintenancePercent", ctx),
    defenseStrength: node.requireInt32("defenseStrength", ctx),
    docks: node.requireInt32("docks", ctx)
  )

proc parseShipyard(node: KdlNode, ctx: var KdlConfigContext): ShipyardConfig =
  result = ShipyardConfig(
    minCST: node.requireInt32("minCST", ctx),
    buildCost: node.requireInt32("buildCost", ctx),
    maintenancePercent: node.requireFloat32("maintenancePercent", ctx),
    defenseStrength: node.requireInt32("defenseStrength", ctx),
    prerequisite: node.requireString("prerequisite", ctx),
    docks: node.requireInt32("docks", ctx)
  )

proc parseDrydock(node: KdlNode, ctx: var KdlConfigContext): DrydockConfig =
  result = DrydockConfig(
    minCST: node.requireInt32("minCST", ctx),
    buildCost: node.requireInt32("buildCost", ctx),
    maintenancePercent: node.requireFloat32("maintenancePercent", ctx),
    defenseStrength: node.requireInt32("defenseStrength", ctx),
    prerequisite: node.requireString("prerequisite", ctx),
    docks: node.requireInt32("docks", ctx)
  )

proc parseStarbase(node: KdlNode, ctx: var KdlConfigContext): StarbaseConfig =
  result = StarbaseConfig(
    minCST: node.requireInt32("minCST", ctx),
    buildCost: node.requireInt32("buildCost", ctx),
    maintenancePercent: node.requireFloat32("maintenancePercent", ctx),
    attackStrength: node.requireInt32("attackStrength", ctx),
    defenseStrength: node.requireInt32("defenseStrength", ctx),
    prerequisite: node.requireString("prerequisite", ctx)
  )

proc loadFacilitiesConfig*(configPath: string): FacilitiesConfig =
  ## Load facilities configuration from KDL file
  ## Uses kdl_config_helpers for type-safe parsing
  let doc = loadKdlConfig(configPath)
  var ctx = newContext(configPath)

  # Parse facilities parent node
  ctx.withNode("facilities"):
    let facilitiesNode = doc.requireNode("facilities", ctx)
    for child in facilitiesNode.children:
      case child.name
      of "spaceport":
        ctx.withNode("spaceport"):
          result.spaceport = parseSpaceport(child, ctx)
      of "shipyard":
        ctx.withNode("shipyard"):
          result.shipyard = parseShipyard(child, ctx)
      of "drydock":
        ctx.withNode("drydock"):
          result.drydock = parseDrydock(child, ctx)
      else:
        discard

  # Parse orbitalDefenses parent node
  ctx.withNode("orbitalDefenses"):
    let orbitalNode = doc.requireNode("orbitalDefenses", ctx)
    for child in orbitalNode.children:
      if child.name == "starbase":
        ctx.withNode("starbase"):
          result.starbase = parseStarbase(child, ctx)

  logInfo("Config", "Loaded facilities configuration", "path=", configPath)
