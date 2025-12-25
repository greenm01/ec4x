## Game Setup Configuration Loader
##
## Loads game setup parameters from game_setup/standard.kdl using nimkdl
## Defines starting conditions for players (homeworld, fleet, facilities, tech)

import std/[os, strutils, options, tables]
import kdl
import kdl_config_helpers
import ../../common/logger
import ../types/starmap

type
  GameInfoConfig* = object ## Game metadata
    name*: string
    description*: string
    recommendedPlayers*: int32
    estimatedDuration*: string

  VictoryConditionsConfig* = object ## Victory conditions
    primaryCondition*: string
    secondaryCondition*: string
    prestigeThreshold*: int32
    turnLimit*: int32 # NEW: Turn limit for turn_limit victory mode

  MapConfig* = object ## Map generation settings
    size*: string
    systems*: int32
    jumpLaneDensity*: string
    startingDistance*: string

  StartingResourcesConfig* = object ## Starting economic resources
    treasury*: int32
    startingPrestige*: int32
    defaultTaxRate*: float32

  StartingTechConfig* = object ## Initial technology levels per gameplay.md:1.2
    economicLevel*: int32
    scienceLevel*: int32
    constructionTech*: int32
    weaponsTech*: int32
    terraformingTech*: int32
    electronicIntelligence*: int32
    cloakingTech*: int32
    shieldTech*: int32
    counterIntelligence*: int32
    fighterDoctrine*: int32
    advancedCarrierOps*: int32

  StartingFleetConfig* = object ## Initial fleet composition
    fleetCount*: int32 # Number of individual fleets to create
    # Fallback aggregated counts (used if individual fleet sections not available)
    etac*: int32
    lightCruiser*: int32
    destroyer*: int32
    scout*: int32

  FleetConfig* = object ## Individual fleet configuration (new per-fleet format)
    ships*: seq[string] # Ship class names (e.g., ["ETAC", "LightCruiser"])
    cargoPtu*: Option[int32] # Optional PTU cargo override for ETACs

  HouseNamingConfig* = object ## House naming configuration
    namePattern*: string # Pattern with {index} placeholder
    useThemeNames*: bool # Whether to use house_themes.kdl

  StartingFacilitiesConfig* = object ## Homeworld starting facilities
    spaceports*: int32
    shipyards*: int32
    starbases*: int32
    groundBatteries*: int32
    planetaryShields*: int32

  StartingGroundForcesConfig* = object ## Homeworld starting ground forces
    armies*: int32
    marines*: int32

  HomeworldConfig* = object ## Homeworld characteristics
    planetClass*: string # "Eden"
    rawQuality*: string # "Abundant"
    colonyLevel*: int32 # Infrastructure level (5 = Level V)
    populationUnits*: int32 # Starting population in PU (840)
    industrialUnits*: int32

  GameSetupConfig* = object ## Complete game setup configuration
    gameInfo*: GameInfoConfig
    victoryConditions*: VictoryConditionsConfig
    map*: MapConfig
    startingResources*: StartingResourcesConfig
    startingTech*: StartingTechConfig
    startingFleet*: StartingFleetConfig
    startingFacilities*: StartingFacilitiesConfig
    startingGroundForces*: StartingGroundForcesConfig
    homeworld*: HomeworldConfig
    houseNaming*: Option[HouseNamingConfig] # Optional, defaults if not present

proc parseGameInfo(node: KdlNode, ctx: var KdlConfigContext): GameInfoConfig =
  result = GameInfoConfig(
    name: node.requireString("name", ctx),
    description: node.requireString("description", ctx),
    recommendedPlayers: node.requireInt("recommendedPlayers", ctx).int32,
    estimatedDuration: node.requireString("estimatedDuration", ctx)
  )

proc parseVictoryConditions(node: KdlNode, ctx: var KdlConfigContext): VictoryConditionsConfig =
  result = VictoryConditionsConfig(
    primaryCondition: node.requireString("primaryCondition", ctx),
    secondaryCondition: node.requireString("secondaryCondition", ctx),
    prestigeThreshold: node.requireInt("prestigeThreshold", ctx).int32,
    turnLimit: node.requireInt("turnLimit", ctx).int32
  )

proc parseMap(node: KdlNode, ctx: var KdlConfigContext): MapConfig =
  result = MapConfig(
    size: node.requireString("size", ctx),
    systems: node.requireInt("systems", ctx).int32,
    jumpLaneDensity: node.requireString("jumpLaneDensity", ctx),
    startingDistance: node.requireString("startingDistance", ctx)
  )

proc parseStartingResources(node: KdlNode, ctx: var KdlConfigContext): StartingResourcesConfig =
  result = StartingResourcesConfig(
    treasury: node.requireInt("treasury", ctx).int32,
    startingPrestige: node.requireInt("startingPrestige", ctx).int32,
    defaultTaxRate: node.requireFloat("defaultTaxRate", ctx).float32
  )

proc parseStartingTech(node: KdlNode, ctx: var KdlConfigContext): StartingTechConfig =
  result = StartingTechConfig(
    economicLevel: node.requireInt("economicLevel", ctx).int32,
    scienceLevel: node.requireInt("scienceLevel", ctx).int32,
    constructionTech: node.requireInt("constructionTech", ctx).int32,
    weaponsTech: node.requireInt("weaponsTech", ctx).int32,
    terraformingTech: node.requireInt("terraformingTech", ctx).int32,
    electronicIntelligence: node.requireInt("electronicIntelligence", ctx).int32,
    cloakingTech: node.requireInt("cloakingTech", ctx).int32,
    shieldTech: node.requireInt("shieldTech", ctx).int32,
    counterIntelligence: node.requireInt("counterIntelligence", ctx).int32,
    fighterDoctrine: node.requireInt("fighterDoctrine", ctx).int32,
    advancedCarrierOps: node.requireInt("advancedCarrierOps", ctx).int32
  )

proc parseStartingFleet(node: KdlNode, ctx: var KdlConfigContext): StartingFleetConfig =
  result = StartingFleetConfig(
    fleetCount: node.requireInt("fleetCount", ctx).int32,
    etac: getIntOpt(node, "etac", 0).int32,
    lightCruiser: getIntOpt(node, "lightCruiser", 0).int32,
    destroyer: getIntOpt(node, "destroyer", 0).int32,
    scout: getIntOpt(node, "scout", 0).int32
  )

proc parseStartingFacilities(node: KdlNode, ctx: var KdlConfigContext): StartingFacilitiesConfig =
  result = StartingFacilitiesConfig(
    spaceports: node.requireInt("spaceports", ctx).int32,
    shipyards: node.requireInt("shipyards", ctx).int32,
    starbases: node.requireInt("starbases", ctx).int32,
    groundBatteries: node.requireInt("groundBatteries", ctx).int32,
    planetaryShields: node.requireInt("planetaryShields", ctx).int32
  )

proc parseStartingGroundForces(node: KdlNode, ctx: var KdlConfigContext): StartingGroundForcesConfig =
  result = StartingGroundForcesConfig(
    armies: node.requireInt("armies", ctx).int32,
    marines: node.requireInt("marines", ctx).int32
  )

proc parseHomeworld(node: KdlNode, ctx: var KdlConfigContext): HomeworldConfig =
  result = HomeworldConfig(
    planetClass: node.requireString("planetClass", ctx),
    rawQuality: node.requireString("rawQuality", ctx),
    colonyLevel: node.requireInt("colonyLevel", ctx).int32,
    populationUnits: node.requireInt("populationUnits", ctx).int32,
    industrialUnits: node.requireInt("industrialUnits", ctx).int32
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
      cargoPtu = some(cargoPtuNode.args[0].getInt().int32)

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

## Global configuration instance

var globalGameSetupConfig* = loadGameSetupConfig()

## Helper to reload configuration (for testing)

proc reloadGameSetupConfig*() =
  ## Reload configuration from file
  globalGameSetupConfig = loadGameSetupConfig()
