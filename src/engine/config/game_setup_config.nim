## Game Setup Configuration Loader
##
## Loads game setup parameters from game_setup/standard.kdl using nimkdl
## Defines starting conditions for players (homeworld, fleet, facilities, tech)

import std/[os, strutils, options, tables]
import kdl
import kdl_helpers
import ../../common/logger
import ../types/config

proc parseGameInfo(node: KdlNode, ctx: var KdlConfigContext): GameInfoConfig =
  result = GameInfoConfig(
    name: node.requireString("name", ctx),
    description: node.requireString("description", ctx),
    recommendedPlayers: node.requireInt32("recommendedPlayers", ctx),
    estimatedDuration: node.requireString("estimatedDuration", ctx)
  )

proc parseVictoryConditions(node: KdlNode, ctx: var KdlConfigContext): VictoryConditionsConfig =
  result = VictoryConditionsConfig(
    primaryCondition: node.requireString("primaryCondition", ctx),
    secondaryCondition: node.requireString("secondaryCondition", ctx),
    prestigeThreshold: node.requireInt32("prestigeThreshold", ctx),
    turnLimit: node.requireInt32("turnLimit", ctx)
  )

proc parseMap(node: KdlNode, ctx: var KdlConfigContext): MapConfig =
  result = MapConfig(
    size: node.requireString("size", ctx),
    systems: node.requireInt32("systems", ctx),
    jumpLaneDensity: node.requireString("jumpLaneDensity", ctx),
    startingDistance: node.requireString("startingDistance", ctx)
  )

proc parseStartingResources(node: KdlNode, ctx: var KdlConfigContext): StartingResourcesConfig =
  result = StartingResourcesConfig(
    treasury: node.requireInt32("treasury", ctx),
    startingPrestige: node.requireInt32("startingPrestige", ctx),
    defaultTaxRate: node.requireFloat32("defaultTaxRate", ctx)
  )

proc parseStartingTech(node: KdlNode, ctx: var KdlConfigContext): StartingTechConfig =
  result = StartingTechConfig(
    economicLevel: node.requireInt32("economicLevel", ctx),
    scienceLevel: node.requireInt32("scienceLevel", ctx),
    constructionTech: node.requireInt32("constructionTech", ctx),
    weaponsTech: node.requireInt32("weaponsTech", ctx),
    terraformingTech: node.requireInt32("terraformingTech", ctx),
    electronicIntelligence: node.requireInt32("electronicIntelligence", ctx),
    cloakingTech: node.requireInt32("cloakingTech", ctx),
    shieldTech: node.requireInt32("shieldTech", ctx),
    counterIntelligence: node.requireInt32("counterIntelligence", ctx),
    fighterDoctrine: node.requireInt32("fighterDoctrine", ctx),
    advancedCarrierOps: node.requireInt32("advancedCarrierOps", ctx)
  )

proc parseStartingFleet(node: KdlNode, ctx: var KdlConfigContext): StartingFleetConfig =
  result = StartingFleetConfig(
    fleetCount: node.requireInt32("fleetCount", ctx),
    etac: getInt32Opt(node, "etac", 0),
    lightCruiser: getInt32Opt(node, "lightCruiser", 0),
    destroyer: getInt32Opt(node, "destroyer", 0),
    scout: getInt32Opt(node, "scout", 0)
  )

proc parseStartingFacilities(node: KdlNode, ctx: var KdlConfigContext): StartingFacilitiesConfig =
  result = StartingFacilitiesConfig(
    spaceports: node.requireInt32("spaceports", ctx),
    shipyards: node.requireInt32("shipyards", ctx),
    starbases: node.requireInt32("starbases", ctx),
    groundBatteries: node.requireInt32("groundBatteries", ctx),
    planetaryShields: node.requireInt32("planetaryShields", ctx)
  )

proc parseStartingGroundForces(node: KdlNode, ctx: var KdlConfigContext): StartingGroundForcesConfig =
  result = StartingGroundForcesConfig(
    armies: node.requireInt32("armies", ctx),
    marines: node.requireInt32("marines", ctx)
  )

proc parseHomeworld(node: KdlNode, ctx: var KdlConfigContext): HomeworldConfig =
  result = HomeworldConfig(
    planetClass: node.requireString("planetClass", ctx),
    rawQuality: node.requireString("rawQuality", ctx),
    colonyLevel: node.requireInt32("colonyLevel", ctx),
    populationUnits: node.requireInt32("populationUnits", ctx),
    industrialUnits: node.requireInt32("industrialUnits", ctx)
  )

proc parseHouseNaming(node: KdlNode, ctx: var KdlConfigContext): HouseNamingConfig =
  result = HouseNamingConfig(
    namePattern: node.requireString("namePattern", ctx),
    useThemeNames: node.requireBool("useThemeNames", ctx)
  )

proc loadGameSetupConfig*(
    configPath: string = "game_setup/standard.kdl"
): GameSetupConfig =
  ## Load game setup configuration from KDL file
  ## Uses kdl_config_helpers for type-safe parsing
  let doc = loadKdlConfig(configPath)
  var ctx = newContext(configPath)

  ctx.withNode("gameInfo"):
    let node = doc.requireNode("gameInfo", ctx)
    result.gameInfo = parseGameInfo(node, ctx)

  ctx.withNode("victoryConditions"):
    let node = doc.requireNode("victoryConditions", ctx)
    result.victoryConditions = parseVictoryConditions(node, ctx)

  ctx.withNode("map"):
    let node = doc.requireNode("map", ctx)
    result.map = parseMap(node, ctx)

  ctx.withNode("startingResources"):
    let node = doc.requireNode("startingResources", ctx)
    result.startingResources = parseStartingResources(node, ctx)

  ctx.withNode("startingTech"):
    let node = doc.requireNode("startingTech", ctx)
    result.startingTech = parseStartingTech(node, ctx)

  ctx.withNode("startingFleet"):
    let node = doc.requireNode("startingFleet", ctx)
    result.startingFleet = parseStartingFleet(node, ctx)

  ctx.withNode("startingFacilities"):
    let node = doc.requireNode("startingFacilities", ctx)
    result.startingFacilities = parseStartingFacilities(node, ctx)

  ctx.withNode("startingGroundForces"):
    let node = doc.requireNode("startingGroundForces", ctx)
    result.startingGroundForces = parseStartingGroundForces(node, ctx)

  ctx.withNode("homeworld"):
    let node = doc.requireNode("homeworld", ctx)
    result.homeworld = parseHomeworld(node, ctx)

  # Optional house naming
  let houseNamingNode = doc.getNode("houseNaming")
  if houseNamingNode.isSome:
    ctx.withNode("houseNaming"):
      result.houseNaming = some(parseHouseNaming(houseNamingNode.get(), ctx))
  else:
    result.houseNaming = none(HouseNamingConfig)

  logInfo("Config", "Loaded game setup configuration", "path=", configPath)

proc parsePlanetClass*(className: string): PlanetClass =
  ## Parse planet class string from config
  case className.toLower()
  of "extreme":
    PlanetClass.Extreme
  of "desolate":
    PlanetClass.Desolate
  of "hostile":
    PlanetClass.Hostile
  of "harsh":
    PlanetClass.Harsh
  of "benign":
    PlanetClass.Benign
  of "lush":
    PlanetClass.Lush
  of "eden":
    PlanetClass.Eden
  else:
    raise newException(ValueError, "Invalid planet class: " & className)

proc parseResourceRating*(ratingName: string): ResourceRating =
  ## Parse resource rating string from config
  case ratingName.toLower()
  of "verypoor", "very_poor":
    ResourceRating.VeryPoor
  of "poor":
    ResourceRating.Poor
  of "abundant":
    ResourceRating.Abundant
  of "rich":
    ResourceRating.Rich
  of "veryrich", "very_rich":
    ResourceRating.VeryRich
  else:
    raise newException(ValueError, "Invalid resource rating: " & ratingName)

proc parseFleetConfig(node: KdlNode, ctx: var KdlConfigContext): FleetConfig =
  ## Parse a single fleet node from KDL
  var ships: seq[string] = @[]

  # Get ships - KDL stores these as arguments to the "ships" child
  let shipsOpt = node.getChild("ships")
  if shipsOpt.isSome:
    let shipsNode = shipsOpt.get()
    # Ships are stored as string arguments
    for arg in shipsNode.args:
      if arg.kind == KValKind.KString:
        ships.add(arg.getString())

  # Get optional cargoPtu
  var cargoPtu: Option[int32] = none(int32)
  let cargoPtuOpt = node.getChild("cargoPtu")
  if cargoPtuOpt.isSome:
    let cargoPtuNode = cargoPtuOpt.get()
    if cargoPtuNode.args.len > 0:
      cargoPtu = some(cargoPtuNode.args[0].getInt32())

  result = FleetConfig(ships: ships, cargoPtu: cargoPtu)

proc loadIndividualFleetConfigs*(
    configPath: string = "game_setup/fleets.kdl"
): Table[int, FleetConfig] =
  ## Load individual fleet configurations from KDL file
  ## Parses fleet1, fleet2, ... fleetN nodes
  ## Returns table mapping fleet index to FleetConfig
  ##
  ## Note: Uses separate fleets.kdl file

  result = initTable[int, FleetConfig]()

  if not fileExists(configPath):
    logWarn("Config", "Fleet config not found", "path=", configPath)
    return

  let doc = loadKdlConfig(configPath)
  var ctx = newContext(configPath)

  # Parse individual fleetN nodes (1-indexed)
  var fleetIdx = 1
  while true:
    let fleetName = "fleet" & $fleetIdx
    let fleetNodeOpt = doc.getNode(fleetName)

    if fleetNodeOpt.isNone:
      break

    ctx.withNode(fleetName):
      let fleetNode = fleetNodeOpt.get()
      result[fleetIdx] = parseFleetConfig(fleetNode, ctx)
      logDebug(
        "Config",
        "Loaded fleet config",
        "fleet=",
        $fleetIdx,
        "ships=",
        $result[fleetIdx].ships.len,
      )

    fleetIdx += 1

  logInfo("Config", "Loaded individual fleet configs", "count=", $(fleetIdx - 1))

proc getHouseNamePattern*(config: GameSetupConfig): string =
  ## Get house naming pattern from config, with fallback default
  if config.houseNaming.isSome:
    return config.houseNaming.get().namePattern
  else:
    return "House{index}" # Default pattern

proc useThemeNames*(config: GameSetupConfig): bool =
  ## Check if config specifies using theme names from house_themes.kdl
  if config.houseNaming.isSome:
    return config.houseNaming.get().useThemeNames
  else:
    return false # Default: don't use theme names
