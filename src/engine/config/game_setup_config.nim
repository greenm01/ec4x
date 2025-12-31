## Game Setup Configuration Loader
##
## Loads game setup parameters from scenarios/*.kdl using nimkdl
## Defines starting conditions for players (homeworld, fleet, facilities, tech)

import std/[strutils, options]
import kdl
import kdl_helpers
import ../../common/logger
import ../types/config

proc parseGameParameters(node: KdlNode, ctx: var KdlConfigContext): GameParametersConfig =
  result = GameParametersConfig(
    scenarioName: node.requireString("scenarioName", ctx),
    scenarioDescription: node.getString("scenarioDescription", ""),
    playerCount: node.requireInt32("playerCount", ctx),
    gameSeed: node.getInt64Opt("gameSeed")
  )

proc parseVictoryConditions(node: KdlNode, ctx: var KdlConfigContext): VictoryConditionsConfig =
  result = VictoryConditionsConfig(
    turnLimit: node.requireInt32("turnLimit", ctx),
    finalConflictAutoEnemy: node.requireBool("finalConflictAutoEnemy", ctx)
  )

proc parseStartingResources(node: KdlNode, ctx: var KdlConfigContext): StartingResourcesConfig =
  result = StartingResourcesConfig(
    treasury: node.requireInt32("treasury", ctx),
    startingPrestige: node.requireInt32("startingPrestige", ctx),
    defaultTaxRate: node.requireFloat32("defaultTaxRate", ctx)
  )

proc parseStartingTech(node: KdlNode, ctx: var KdlConfigContext): StartingTechConfig =
  ## Parse starting tech using abbreviated field names
  result = StartingTechConfig(
    el: node.requireInt32("economicLevel", ctx),
    sl: node.requireInt32("scienceLevel", ctx),
    wep: node.requireInt32("weapons", ctx),
    cst: node.requireInt32("construction", ctx),
    sld: node.requireInt32("shields", ctx),
    ter: node.requireInt32("terraforming", ctx),
    eli: node.requireInt32("electronicIntelligence", ctx),
    clk: node.requireInt32("cloaking", ctx),
    stl: node.requireInt32("strategicLift", ctx),
    cic: node.requireInt32("counterIntelligence", ctx),
    fc: node.requireInt32("flagshipCommand", ctx),
    sc: node.requireInt32("strategicCommand", ctx),
    fd: node.requireInt32("fighterDoctrine", ctx),
    aco: node.requireInt32("advancedCarrierOperations", ctx)
  )

proc parseFleetConfig(node: KdlNode, ctx: var KdlConfigContext): FleetConfig =
  ## Parse a single fleet node from KDL
  var ships: seq[string] = @[]

  # Get ships - KDL stores these as arguments to the "ships" child
  let shipsOpt = node.findChildNode("ships")
  if shipsOpt.isSome:
    let shipsNode = shipsOpt.get()
    # Ships are stored as string arguments
    for arg in shipsNode.args:
      if arg.kind == KValKind.KString:
        ships.add(arg.getString())

  result = FleetConfig(ships: ships)

proc parseStartingFleets(node: KdlNode, ctx: var KdlConfigContext): StartingFleetsConfig =
  ## Parse startingFleet node with child fleet nodes
  var fleets: seq[FleetConfig] = @[]

  # Get all "fleet" child nodes
  for child in node.children:
    if child.name == "fleet":
      ctx.withNode("fleet"):
        fleets.add(parseFleetConfig(child, ctx))

  result = StartingFleetsConfig(fleets: fleets)

proc parseStartingFacilities(node: KdlNode, ctx: var KdlConfigContext): StartingFacilitiesConfig =
  result = StartingFacilitiesConfig(
    spaceports: node.requireInt32("spaceports", ctx),
    shipyards: node.requireInt32("shipyards", ctx),
    drydocks: node.requireInt32("drydocks", ctx)
  )

proc parseStartingGroundForces(node: KdlNode, ctx: var KdlConfigContext): StartingGroundForcesConfig =
  result = StartingGroundForcesConfig(
    armies: node.requireInt32("armies", ctx),
    marines: node.requireInt32("marines", ctx),
    groundBatteries: node.requireInt32("groundBatteries", ctx),
    planetaryShields: node.requireInt32("planetaryShields", ctx)
  )

proc parseMapGeneration(node: KdlNode, ctx: var KdlConfigContext): MapGenerationConfig =
  result = MapGenerationConfig(
    numRings: node.requireInt32("numRings", ctx)
  )

proc parseHomeworld(node: KdlNode, ctx: var KdlConfigContext): HomeworldConfig =
  result = HomeworldConfig(
    planetClass: node.requireString("planetClass", ctx),
    rawQuality: node.requireString("rawQuality", ctx),
    colonyLevel: node.requireInt32("colonyLevel", ctx),
    populationUnits: node.requireInt32("populationUnits", ctx),
    industrialUnits: node.requireInt32("industrialUnits", ctx)
  )

proc loadGameSetupConfig*(setupPath: string): GameSetup =
  ## Load game setup configuration from KDL file
  ## Uses kdl_config_helpers for type-safe parsing

  let doc = loadKdlConfig(setupPath)
  var ctx = newContext(setupPath)

  ctx.withNode("gameParameters"):
    let node = doc.requireNode("gameParameters", ctx)
    result.gameparameters = parseGameParameters(node, ctx)

  ctx.withNode("mapGeneration"):
    let node = doc.requireNode("mapGeneration", ctx)
    result.mapGeneration = parseMapGeneration(node, ctx)

  ctx.withNode("victoryConditions"):
    let node = doc.requireNode("victoryConditions", ctx)
    result.victoryConditions = parseVictoryConditions(node, ctx)

  ctx.withNode("startingResources"):
    let node = doc.requireNode("startingResources", ctx)
    result.startingResources = parseStartingResources(node, ctx)

  ctx.withNode("startingTech"):
    let node = doc.requireNode("startingTech", ctx)
    result.startingTech = parseStartingTech(node, ctx)

  ctx.withNode("startingFleets"):
    let node = doc.requireNode("startingFleets", ctx)
    result.startingFleets = parseStartingFleets(node, ctx)

  ctx.withNode("startingFacilities"):
    let node = doc.requireNode("startingFacilities", ctx)
    result.startingFacilities = parseStartingFacilities(node, ctx)

  ctx.withNode("startingGroundForces"):
    let node = doc.requireNode("startingGroundForces", ctx)
    result.startingGroundForces = parseStartingGroundForces(node, ctx)

  ctx.withNode("homeworld"):
    let node = doc.requireNode("homeworld", ctx)
    result.homeworld = parseHomeworld(node, ctx)

  logInfo("Game Setup", "Loaded game setup configuration", "path=", setupPath)
