## Prestige Configuration Loader
##
## Loads prestige values from config/prestige.kdl using nimkdl
## Allows runtime configuration for balance testing

import kdl
import kdl_config_helpers
import ../../common/logger

type
  VictoryConfig* = object
    ## Victory config (prestige_victory removed - now in game_setup/*.kdl)
    startingPrestige*: int32
    defeatThreshold*: int32
    defeatConsecutiveTurns*: int32

  DynamicScalingConfig* = object
    enabled*: bool
    baseMultiplier*: float32
    baselineTurns*: int32
    baselineSystemsPerPlayer*: int32
    turnScalingFactor*: float32
    minMultiplier*: float32
    maxMultiplier*: float32

  MoraleConfig* = object
    crisisMax*: int32
    lowMax*: int32
    averageMax*: int32
    goodMax*: int32
    highMax*: int32

  EconomicPrestigeConfig* = object
    techAdvancement*: int32
    establishColony*: int32
    maxPopulation*: int32
    iuMilestone50*: int32
    iuMilestone75*: int32
    iuMilestone100*: int32
    iuMilestone150*: int32
    terraformPlanet*: int32

  MilitaryPrestigeConfig* = object
    destroySquadron*: int32
    destroyStarbase*: int32
    fleetVictory*: int32
    invadePlanet*: int32
    eliminateHouse*: int32
    systemCapture*: int32
    losePlanet*: int32
    loseStarbase*: int32
    ambushedByCloak*: int32
    forceRetreat*: int32
    forcedToRetreat*: int32
    scoutDestroyed*: int32
    undefendedColonyPenaltyMultiplier*: float32

  EspionagePrestigeConfig* = object
    techTheft*: int32
    lowImpactSabotage*: int32
    highImpactSabotage*: int32
    assassination*: int32
    cyberAttack*: int32
    economicManipulation*: int32
    psyopsCampaign*: int32
    counterIntelSweep*: int32
    intelligenceTheft*: int32
    plantDisinformation*: int32
    failedEspionage*: int32

  EspionageVictimPrestigeConfig* = object
    techTheftVictim*: int32
    lowImpactSabotageVictim*: int32
    highImpactSabotageVictim*: int32
    assassinationVictim*: int32
    cyberAttackVictim*: int32
    economicManipulationVictim*: int32
    psyopsCampaignVictim*: int32
    counterIntelSweepVictim*: int32
    intelligenceTheftVictim*: int32
    plantDisinformationVictim*: int32

  ScoutPrestigeConfig* = object
    spyOnPlanet*: int32
    hackStarbase*: int32
    spyOnSystem*: int32

  DiplomacyPrestigeConfig* = object
    declareWar*: int32
    makePeace*: int32

  VictoryAchievementConfig* = object
    victoryAchieved*: int32

  PenaltiesPrestigeConfig* = object
    highTaxThreshold*: int32
    highTaxPenalty*: int32
    highTaxFrequency*: int32
    veryHighTaxThreshold*: int32
    veryHighTaxPenalty*: int32
    veryHighTaxFrequency*: int32
    maintenanceShortfallBase*: int32
    maintenanceShortfallIncrement*: int32
    blockadePenalty*: int32
    overInvestEspionage*: int32
    overInvestCounterIntel*: int32

  TaxPenaltiesTier* = object
    tier1Min*: int32
    tier1Max*: int32
    tier1Penalty*: int32
    tier2Min*: int32
    tier2Max*: int32
    tier2Penalty*: int32
    tier3Min*: int32
    tier3Max*: int32
    tier3Penalty*: int32
    tier4Min*: int32
    tier4Max*: int32
    tier4Penalty*: int32
    tier5Min*: int32
    tier5Max*: int32
    tier5Penalty*: int32
    tier6Min*: int32
    tier6Max*: int32
    tier6Penalty*: int32

  TaxIncentivesTier* = object
    tier1Min*: int32
    tier1Max*: int32
    tier1Prestige*: int32
    tier2Min*: int32
    tier2Max*: int32
    tier2Prestige*: int32
    tier3Min*: int32
    tier3Max*: int32
    tier3Prestige*: int32
    tier4Min*: int32
    tier4Max*: int32
    tier4Prestige*: int32
    tier5Min*: int32
    tier5Max*: int32
    tier5Prestige*: int32

  PrestigeConfig* = object ## Complete prestige configuration loaded from KDL
    victory*: VictoryConfig
    dynamicScaling*: DynamicScalingConfig
    morale*: MoraleConfig
    economic*: EconomicPrestigeConfig
    military*: MilitaryPrestigeConfig
    espionage*: EspionagePrestigeConfig
    espionageVictim*: EspionageVictimPrestigeConfig
    scout*: ScoutPrestigeConfig
    diplomacy*: DiplomacyPrestigeConfig
    victoryAchievement*: VictoryAchievementConfig
    penalties*: PenaltiesPrestigeConfig
    taxPenalties*: TaxPenaltiesTier
    taxIncentives*: TaxIncentivesTier

proc parseVictory(node: KdlNode, ctx: var KdlConfigContext): VictoryConfig =
  result = VictoryConfig(
    startingPrestige: node.requireInt("startingPrestige", ctx).int32,
    defeatThreshold: node.requireInt("defeatThreshold", ctx).int32,
    defeatConsecutiveTurns: node.requireInt("defeatConsecutiveTurns", ctx).int32
  )

proc parseDynamicScaling(node: KdlNode, ctx: var KdlConfigContext): DynamicScalingConfig =
  result = DynamicScalingConfig(
    enabled: node.requireBool("enabled", ctx),
    baseMultiplier: node.requireFloat("baseMultiplier", ctx).float32,
    baselineTurns: node.requireInt("baselineTurns", ctx).int32,
    baselineSystemsPerPlayer: node.requireInt("baselineSystemsPerPlayer", ctx).int32,
    turnScalingFactor: node.requireFloat("turnScalingFactor", ctx).float32,
    minMultiplier: node.requireFloat("minMultiplier", ctx).float32,
    maxMultiplier: node.requireFloat("maxMultiplier", ctx).float32
  )

proc parseMorale(node: KdlNode, ctx: var KdlConfigContext): MoraleConfig =
  result = MoraleConfig(
    crisisMax: node.requireInt("crisisMax", ctx).int32,
    lowMax: node.requireInt("lowMax", ctx).int32,
    averageMax: node.requireInt("averageMax", ctx).int32,
    goodMax: node.requireInt("goodMax", ctx).int32,
    highMax: node.requireInt("highMax", ctx).int32
  )

proc parseEconomic(node: KdlNode, ctx: var KdlConfigContext): EconomicPrestigeConfig =
  result = EconomicPrestigeConfig(
    techAdvancement: node.requireInt("techAdvancement", ctx).int32,
    establishColony: node.requireInt("establishColony", ctx).int32,
    maxPopulation: node.requireInt("maxPopulation", ctx).int32,
    iuMilestone50: node.requireInt("iuMilestone50", ctx).int32,
    iuMilestone75: node.requireInt("iuMilestone75", ctx).int32,
    iuMilestone100: node.requireInt("iuMilestone100", ctx).int32,
    iuMilestone150: node.requireInt("iuMilestone150", ctx).int32,
    terraformPlanet: node.requireInt("terraformPlanet", ctx).int32
  )

proc parseMilitary(node: KdlNode, ctx: var KdlConfigContext): MilitaryPrestigeConfig =
  result = MilitaryPrestigeConfig(
    destroySquadron: node.requireInt("destroySquadron", ctx).int32,
    destroyStarbase: node.requireInt("destroyStarbase", ctx).int32,
    fleetVictory: node.requireInt("fleetVictory", ctx).int32,
    invadePlanet: node.requireInt("invadePlanet", ctx).int32,
    eliminateHouse: node.requireInt("eliminateHouse", ctx).int32,
    systemCapture: node.requireInt("systemCapture", ctx).int32,
    losePlanet: node.requireInt("losePlanet", ctx).int32,
    loseStarbase: node.requireInt("loseStarbase", ctx).int32,
    ambushedByCloak: node.requireInt("ambushedByCloak", ctx).int32,
    forceRetreat: node.requireInt("forceRetreat", ctx).int32,
    forcedToRetreat: node.requireInt("forcedToRetreat", ctx).int32,
    scoutDestroyed: node.requireInt("scoutDestroyed", ctx).int32,
    undefendedColonyPenaltyMultiplier: node.requireFloat("undefendedColonyPenaltyMultiplier", ctx).float32
  )

proc parseEspionage(node: KdlNode, ctx: var KdlConfigContext): EspionagePrestigeConfig =
  result = EspionagePrestigeConfig(
    techTheft: node.requireInt("techTheft", ctx).int32,
    lowImpactSabotage: node.requireInt("lowImpactSabotage", ctx).int32,
    highImpactSabotage: node.requireInt("highImpactSabotage", ctx).int32,
    assassination: node.requireInt("assassination", ctx).int32,
    cyberAttack: node.requireInt("cyberAttack", ctx).int32,
    economicManipulation: node.requireInt("economicManipulation", ctx).int32,
    psyopsCampaign: node.requireInt("psyopsCampaign", ctx).int32,
    counterIntelSweep: node.requireInt("counterIntelSweep", ctx).int32,
    intelligenceTheft: node.requireInt("intelligenceTheft", ctx).int32,
    plantDisinformation: node.requireInt("plantDisinformation", ctx).int32,
    failedEspionage: node.requireInt("failedEspionage", ctx).int32
  )

proc parseEspionageVictim(node: KdlNode, ctx: var KdlConfigContext): EspionageVictimPrestigeConfig =
  result = EspionageVictimPrestigeConfig(
    techTheftVictim: node.requireInt("techTheftVictim", ctx).int32,
    lowImpactSabotageVictim: node.requireInt("lowImpactSabotageVictim", ctx).int32,
    highImpactSabotageVictim: node.requireInt("highImpactSabotageVictim", ctx).int32,
    assassinationVictim: node.requireInt("assassinationVictim", ctx).int32,
    cyberAttackVictim: node.requireInt("cyberAttackVictim", ctx).int32,
    economicManipulationVictim: node.requireInt("economicManipulationVictim", ctx).int32,
    psyopsCampaignVictim: node.requireInt("psyopsCampaignVictim", ctx).int32,
    counterIntelSweepVictim: node.requireInt("counterIntelSweepVictim", ctx).int32,
    intelligenceTheftVictim: node.requireInt("intelligenceTheftVictim", ctx).int32,
    plantDisinformationVictim: node.requireInt("plantDisinformationVictim", ctx).int32
  )

proc parseScout(node: KdlNode, ctx: var KdlConfigContext): ScoutPrestigeConfig =
  result = ScoutPrestigeConfig(
    spyOnPlanet: node.requireInt("spyOnPlanet", ctx).int32,
    hackStarbase: node.requireInt("hackStarbase", ctx).int32,
    spyOnSystem: node.requireInt("spyOnSystem", ctx).int32
  )

proc parseDiplomacy(node: KdlNode, ctx: var KdlConfigContext): DiplomacyPrestigeConfig =
  result = DiplomacyPrestigeConfig(
    declareWar: node.requireInt("declareWar", ctx).int32,
    makePeace: node.requireInt("makePeace", ctx).int32
  )

proc parseVictoryAchievement(node: KdlNode, ctx: var KdlConfigContext): VictoryAchievementConfig =
  result = VictoryAchievementConfig(
    victoryAchieved: node.requireInt("victoryAchieved", ctx).int32
  )

proc parsePenalties(node: KdlNode, ctx: var KdlConfigContext): PenaltiesPrestigeConfig =
  result = PenaltiesPrestigeConfig(
    highTaxThreshold: node.requireInt("highTaxThreshold", ctx).int32,
    highTaxPenalty: node.requireInt("highTaxPenalty", ctx).int32,
    highTaxFrequency: node.requireInt("highTaxFrequency", ctx).int32,
    veryHighTaxThreshold: node.requireInt("veryHighTaxThreshold", ctx).int32,
    veryHighTaxPenalty: node.requireInt("veryHighTaxPenalty", ctx).int32,
    veryHighTaxFrequency: node.requireInt("veryHighTaxFrequency", ctx).int32,
    maintenanceShortfallBase: node.requireInt("maintenanceShortfallBase", ctx).int32,
    maintenanceShortfallIncrement: node.requireInt("maintenanceShortfallIncrement", ctx).int32,
    blockadePenalty: node.requireInt("blockadePenalty", ctx).int32,
    overInvestEspionage: node.requireInt("overInvestEspionage", ctx).int32,
    overInvestCounterIntel: node.requireInt("overInvestCounterIntel", ctx).int32
  )

proc parseTaxPenalties(node: KdlNode, ctx: var KdlConfigContext): TaxPenaltiesTier =
  result = TaxPenaltiesTier(
    tier1Min: node.requireInt("tier1Min", ctx).int32,
    tier1Max: node.requireInt("tier1Max", ctx).int32,
    tier1Penalty: node.requireInt("tier1Penalty", ctx).int32,
    tier2Min: node.requireInt("tier2Min", ctx).int32,
    tier2Max: node.requireInt("tier2Max", ctx).int32,
    tier2Penalty: node.requireInt("tier2Penalty", ctx).int32,
    tier3Min: node.requireInt("tier3Min", ctx).int32,
    tier3Max: node.requireInt("tier3Max", ctx).int32,
    tier3Penalty: node.requireInt("tier3Penalty", ctx).int32,
    tier4Min: node.requireInt("tier4Min", ctx).int32,
    tier4Max: node.requireInt("tier4Max", ctx).int32,
    tier4Penalty: node.requireInt("tier4Penalty", ctx).int32,
    tier5Min: node.requireInt("tier5Min", ctx).int32,
    tier5Max: node.requireInt("tier5Max", ctx).int32,
    tier5Penalty: node.requireInt("tier5Penalty", ctx).int32,
    tier6Min: node.requireInt("tier6Min", ctx).int32,
    tier6Max: node.requireInt("tier6Max", ctx).int32,
    tier6Penalty: node.requireInt("tier6Penalty", ctx).int32
  )

proc parseTaxIncentives(node: KdlNode, ctx: var KdlConfigContext): TaxIncentivesTier =
  result = TaxIncentivesTier(
    tier1Min: node.requireInt("tier1Min", ctx).int32,
    tier1Max: node.requireInt("tier1Max", ctx).int32,
    tier1Prestige: node.requireInt("tier1Prestige", ctx).int32,
    tier2Min: node.requireInt("tier2Min", ctx).int32,
    tier2Max: node.requireInt("tier2Max", ctx).int32,
    tier2Prestige: node.requireInt("tier2Prestige", ctx).int32,
    tier3Min: node.requireInt("tier3Min", ctx).int32,
    tier3Max: node.requireInt("tier3Max", ctx).int32,
    tier3Prestige: node.requireInt("tier3Prestige", ctx).int32,
    tier4Min: node.requireInt("tier4Min", ctx).int32,
    tier4Max: node.requireInt("tier4Max", ctx).int32,
    tier4Prestige: node.requireInt("tier4Prestige", ctx).int32,
    tier5Min: node.requireInt("tier5Min", ctx).int32,
    tier5Max: node.requireInt("tier5Max", ctx).int32,
    tier5Prestige: node.requireInt("tier5Prestige", ctx).int32
  )

proc loadPrestigeConfig*(configPath: string = "config/prestige.kdl"): PrestigeConfig =
  ## Load prestige configuration from KDL file
  ## Uses kdl_config_helpers for type-safe parsing
  let doc = loadKdlConfig(configPath)
  var ctx = newContext(configPath)

  ctx.withNode("victory"):
    let node = doc.requireNode("victory", ctx)
    result.victory = parseVictory(node, ctx)

  ctx.withNode("dynamicScaling"):
    let node = doc.requireNode("dynamicScaling", ctx)
    result.dynamicScaling = parseDynamicScaling(node, ctx)

  ctx.withNode("morale"):
    let node = doc.requireNode("morale", ctx)
    result.morale = parseMorale(node, ctx)

  ctx.withNode("economic"):
    let node = doc.requireNode("economic", ctx)
    result.economic = parseEconomic(node, ctx)

  ctx.withNode("military"):
    let node = doc.requireNode("military", ctx)
    result.military = parseMilitary(node, ctx)

  ctx.withNode("espionage"):
    let node = doc.requireNode("espionage", ctx)
    result.espionage = parseEspionage(node, ctx)

  ctx.withNode("espionageVictim"):
    let node = doc.requireNode("espionageVictim", ctx)
    result.espionageVictim = parseEspionageVictim(node, ctx)

  ctx.withNode("scout"):
    let node = doc.requireNode("scout", ctx)
    result.scout = parseScout(node, ctx)

  ctx.withNode("diplomacy"):
    let node = doc.requireNode("diplomacy", ctx)
    result.diplomacy = parseDiplomacy(node, ctx)

  ctx.withNode("victoryAchievement"):
    let node = doc.requireNode("victoryAchievement", ctx)
    result.victoryAchievement = parseVictoryAchievement(node, ctx)

  ctx.withNode("penalties"):
    let node = doc.requireNode("penalties", ctx)
    result.penalties = parsePenalties(node, ctx)

  ctx.withNode("taxPenalties"):
    let node = doc.requireNode("taxPenalties", ctx)
    result.taxPenalties = parseTaxPenalties(node, ctx)

  ctx.withNode("taxIncentives"):
    let node = doc.requireNode("taxIncentives", ctx)
    result.taxIncentives = parseTaxIncentives(node, ctx)

  logInfo("Config", "Loaded prestige configuration", "path=", configPath)

## Global configuration instance

var globalPrestigeConfig* = loadPrestigeConfig()

## Helper to reload configuration (for testing)

proc reloadPrestigeConfig*() =
  ## Reload configuration from file
  globalPrestigeConfig = loadPrestigeConfig()

## Dynamic Prestige Multiplier Calculation

proc calculateDynamicMultiplier*(numSystems: int32, numPlayers: int32): float32 =
  ## Calculate dynamic prestige multiplier based on map size and player count
  ##
  ## Formula:
  ##   systems_per_player = numSystems / numPlayers
  ##   target_turns = baseline_turns + (systems_per_player - baseline_ratio) * turn_scaling_factor
  ##   multiplier = base_multiplier * (baseline_turns / target_turns)
  ##   multiplier = clamp(multiplier, min_multiplier, max_multiplier)
  ##
  ## This ensures:
  ## - Small maps (few systems per player): Higher multiplier = faster games
  ## - Large maps (many systems per player): Lower multiplier = longer games
  ## - Victory threshold (5000 prestige) stays constant regardless of map size

  let config = globalPrestigeConfig.dynamicScaling

  # If dynamic scaling is disabled, return base multiplier
  if not config.enabled:
    return config.baseMultiplier

  # Calculate systems per player
  let systemsPerPlayer = float32(numSystems) / float32(numPlayers)

  # Calculate target turns based on map density
  let systemDiff = systemsPerPlayer - float32(config.baselineSystemsPerPlayer)
  let targetTurns =
    float32(config.baselineTurns) + (systemDiff * config.turnScalingFactor)

  # Calculate multiplier (inverse relationship: more turns = lower multiplier)
  let multiplier =
    config.baseMultiplier * (float32(config.baselineTurns) / targetTurns)

  # Clamp to reasonable bounds
  result = max(config.minMultiplier, min(config.maxMultiplier, multiplier))
