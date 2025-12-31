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
    node: KdlNode, facilityType: FacilityType, ctx: var KdlConfigContext
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
  of FacilityType.Spaceport:
    result.docks = node.requireInt32("docks", ctx)
    result.attackStrength = 0
    result.prerequisite = ""
  of FacilityType.Shipyard:
    result.docks = node.requireInt32("docks", ctx)
    result.prerequisite = node.requireString("prerequisite", ctx)
    result.attackStrength = 0
  of FacilityType.Drydock:
    result.docks = node.requireInt32("docks", ctx)
    result.prerequisite = node.requireString("prerequisite", ctx)
    result.attackStrength = 0
  of FacilityType.Starbase:
    result.attackStrength = node.requireInt32("attackStrength", ctx)
    result.prerequisite = node.requireString("prerequisite", ctx)
    result.docks = 0

proc loadFacilitiesConfig*(configPath: string): FacilitiesConfig =
  ## Load facilities configuration from KDL file
  ## Uses kdl_config_helpers for type-safe parsing
  ## Builds array indexed by FacilityType for O(1) access
  let doc = loadKdlConfig(configPath)
  var ctx = newContext(configPath)

  # Parse facilities parent node
  ctx.withNode("facilities"):
    let facilitiesNode = doc.requireNode("facilities", ctx)
    for child in facilitiesNode.children:
      case child.name
      of "spaceport":
        ctx.withNode("spaceport"):
          result.facilities[FacilityType.Spaceport] =
            parseFacilityStats(child, FacilityType.Spaceport, ctx)
      of "shipyard":
        ctx.withNode("shipyard"):
          result.facilities[FacilityType.Shipyard] =
            parseFacilityStats(child, FacilityType.Shipyard, ctx)
      of "drydock":
        ctx.withNode("drydock"):
          result.facilities[FacilityType.Drydock] =
            parseFacilityStats(child, FacilityType.Drydock, ctx)
      else:
        discard

  # Parse orbitalDefenses parent node
  ctx.withNode("orbitalDefenses"):
    let orbitalNode = doc.requireNode("orbitalDefenses", ctx)
    for child in orbitalNode.children:
      if child.name == "starbase":
        ctx.withNode("starbase"):
          result.facilities[FacilityType.Starbase] =
            parseFacilityStats(child, FacilityType.Starbase, ctx)

  logInfo("Config", "Loaded facilities configuration", "path=", configPath)
