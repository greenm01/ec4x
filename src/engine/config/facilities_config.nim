## Facilities Configuration Loader
##
## Loads facility stats from config/facilities.kdl using nimkdl
## Allows runtime configuration for spaceports and shipyards

import kdl
import kdl_helpers
import ../../common/logger
import ../types/config
import ../types/facilities

proc parseFacilityStats(
    node: KdlNode, facilityType: FacilityClass, ctx: var KdlConfigContext
): FacilityStatsConfig =
  ## Parse facility stats from KDL node
  ## Unified parser for all facility types
  result = FacilityStatsConfig(
    minCST: node.requireInt32("minCST", ctx),
    buildCost: node.requireInt32("buildCost", ctx),
    maintenancePercent: node.requireFloat32("maintenancePercent", ctx),
    defenseStrength: node.requireInt32("defenseStrength", ctx),
  )

  # Type-specific fields
  case facilityType
  of FacilityClass.Spaceport:
    result.docks = node.requireInt32("docks", ctx)
    result.attackStrength = 0
    result.prerequisite = ""
  of FacilityClass.Shipyard:
    result.docks = node.requireInt32("docks", ctx)
    result.prerequisite = node.requireString("prerequisite", ctx)
    result.attackStrength = 0
  of FacilityClass.Drydock:
    result.docks = node.requireInt32("docks", ctx)
    result.prerequisite = node.requireString("prerequisite", ctx)
    result.attackStrength = 0
  of FacilityClass.Starbase:
    result.attackStrength = node.requireInt32("attackStrength", ctx)
    result.prerequisite = node.requireString("prerequisite", ctx)
    result.docks = 0

proc loadFacilitiesConfig*(configPath: string): FacilitiesConfig =
  ## Load facilities configuration from KDL file
  ## Uses kdl_config_helpers for type-safe parsing
  ## Builds array indexed by FacilityClass for O(1) access
  let doc = loadKdlConfig(configPath)
  var ctx = newContext(configPath)

  # Parse facilities parent node
  ctx.withNode("facilities"):
    let facilitiesNode = doc.requireNode("facilities", ctx)
    for child in facilitiesNode.children:
      case child.name
      of "spaceport":
        ctx.withNode("spaceport"):
          result.facilities[FacilityClass.Spaceport] =
            parseFacilityStats(child, FacilityClass.Spaceport, ctx)
      of "shipyard":
        ctx.withNode("shipyard"):
          result.facilities[FacilityClass.Shipyard] =
            parseFacilityStats(child, FacilityClass.Shipyard, ctx)
      of "drydock":
        ctx.withNode("drydock"):
          result.facilities[FacilityClass.Drydock] =
            parseFacilityStats(child, FacilityClass.Drydock, ctx)
      else:
        discard

  # Parse orbitalDefenses parent node
  ctx.withNode("orbitalDefenses"):
    let orbitalNode = doc.requireNode("orbitalDefenses", ctx)
    for child in orbitalNode.children:
      if child.name == "starbase":
        ctx.withNode("starbase"):
          result.facilities[FacilityClass.Starbase] =
            parseFacilityStats(child, FacilityClass.Starbase, ctx)

  logInfo("Config", "Loaded facilities configuration", "path=", configPath)
