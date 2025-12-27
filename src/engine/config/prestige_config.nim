## Prestige Configuration Loader
##
## Loads prestige values from config/prestige.kdl using nimkdl
## Allows runtime configuration for balance testing

import kdl
import kdl_helpers
import ../../common/logger
import ../types/config

proc parseVictory(node: KdlNode, ctx: var KdlConfigContext): VictoryConfig =
  result = VictoryConfig(
    startingPrestige: node.requireInt32("startingPrestige", ctx),
    defeatThreshold: node.requireInt32("defeatThreshold", ctx),
    defeatConsecutiveTurns: node.requireInt32("defeatConsecutiveTurns", ctx)
  )

proc parseDynamicScaling(node: KdlNode, ctx: var KdlConfigContext): DynamicPrestigeConfig =
  result = DynamicPrestigeConfig(
    enabled: node.requireBool("enabled", ctx),
    baseMultiplier: node.requireFloat32("baseMultiplier", ctx),
    baselineTurns: node.requireInt32("baselineTurns", ctx),
    baselineSystemsPerPlayer: node.requireInt32("baselineSystemsPerPlayer", ctx),
    turnScalingFactor: node.requireFloat32("turnScalingFactor", ctx),
    minMultiplier: node.requireFloat32("minMultiplier", ctx),
    maxMultiplier: node.requireFloat32("maxMultiplier", ctx)
  )

proc parseMorale(node: KdlNode, ctx: var KdlConfigContext): MoraleConfig =
  result = MoraleConfig(
    crisisMax: node.requireInt32("crisisMax", ctx),
    lowMax: node.requireInt32("lowMax", ctx),
    averageMax: node.requireInt32("averageMax", ctx),
    goodMax: node.requireInt32("goodMax", ctx),
    highMax: node.requireInt32("highMax", ctx)
  )

proc parseEconomic(node: KdlNode, ctx: var KdlConfigContext): EconomicPrestigeConfig =
  result = EconomicPrestigeConfig(
    techAdvancement: node.requireInt32("techAdvancement", ctx),
    establishColony: node.requireInt32("establishColony", ctx),
    maxPopulation: node.requireInt32("maxPopulation", ctx),
    iuMilestone50: node.requireInt32("iuMilestone50", ctx),
    iuMilestone75: node.requireInt32("iuMilestone75", ctx),
    iuMilestone100: node.requireInt32("iuMilestone100", ctx),
    iuMilestone150: node.requireInt32("iuMilestone150", ctx),
    terraformPlanet: node.requireInt32("terraformPlanet", ctx)
  )

proc parseMilitary(node: KdlNode, ctx: var KdlConfigContext): MilitaryPrestigeConfig =
  result = MilitaryPrestigeConfig(
    destroySquadron: node.requireInt32("destroySquadron", ctx),
    destroyStarbase: node.requireInt32("destroyStarbase", ctx),
    fleetVictory: node.requireInt32("fleetVictory", ctx),
    invadePlanet: node.requireInt32("invadePlanet", ctx),
    eliminateHouse: node.requireInt32("eliminateHouse", ctx),
    systemCapture: node.requireInt32("systemCapture", ctx),
    losePlanet: node.requireInt32("losePlanet", ctx),
    loseStarbase: node.requireInt32("loseStarbase", ctx),
    ambushedByCloak: node.requireInt32("ambushedByCloak", ctx),
    forceRetreat: node.requireInt32("forceRetreat", ctx),
    forcedToRetreat: node.requireInt32("forcedToRetreat", ctx),
    scoutDestroyed: node.requireInt32("scoutDestroyed", ctx),
    undefendedColonyPenaltyMultiplier: node.requireFloat32("undefendedColonyPenaltyMultiplier", ctx)
  )

proc parseEspionage(node: KdlNode, ctx: var KdlConfigContext): EspionagePrestigeConfig =
  result = EspionagePrestigeConfig(
    techTheft: node.requireInt32("techTheft", ctx),
    lowImpactSabotage: node.requireInt32("lowImpactSabotage", ctx),
    highImpactSabotage: node.requireInt32("highImpactSabotage", ctx),
    assassination: node.requireInt32("assassination", ctx),
    cyberAttack: node.requireInt32("cyberAttack", ctx),
    economicManipulation: node.requireInt32("economicManipulation", ctx),
    psyopsCampaign: node.requireInt32("psyopsCampaign", ctx),
    counterIntelSweep: node.requireInt32("counterIntelSweep", ctx),
    intelligenceTheft: node.requireInt32("intelligenceTheft", ctx),
    plantDisinformation: node.requireInt32("plantDisinformation", ctx),
    failedEspionage: node.requireInt32("failedEspionage", ctx)
  )

proc parseEspionageVictim(node: KdlNode, ctx: var KdlConfigContext): EspionageVictimPrestigeConfig =
  result = EspionageVictimPrestigeConfig(
    techTheftVictim: node.requireInt32("techTheftVictim", ctx),
    lowImpactSabotageVictim: node.requireInt32("lowImpactSabotageVictim", ctx),
    highImpactSabotageVictim: node.requireInt32("highImpactSabotageVictim", ctx),
    assassinationVictim: node.requireInt32("assassinationVictim", ctx),
    cyberAttackVictim: node.requireInt32("cyberAttackVictim", ctx),
    economicManipulationVictim: node.requireInt32("economicManipulationVictim", ctx),
    psyopsCampaignVictim: node.requireInt32("psyopsCampaignVictim", ctx),
    counterIntelSweepVictim: node.requireInt32("counterIntelSweepVictim", ctx),
    intelligenceTheftVictim: node.requireInt32("intelligenceTheftVictim", ctx),
    plantDisinformationVictim: node.requireInt32("plantDisinformationVictim", ctx)
  )

proc parseScout(node: KdlNode, ctx: var KdlConfigContext): ScoutPrestigeConfig =
  result = ScoutPrestigeConfig(
    spyOnPlanet: node.requireInt32("spyOnPlanet", ctx),
    hackStarbase: node.requireInt32("hackStarbase", ctx),
    spyOnSystem: node.requireInt32("spyOnSystem", ctx)
  )

proc parseDiplomacy(node: KdlNode, ctx: var KdlConfigContext): DiplomacyPrestigeConfig =
  result = DiplomacyPrestigeConfig(
    declareWar: node.requireInt32("declareWar", ctx),
    makePeace: node.requireInt32("makePeace", ctx)
  )

proc parseVictoryAchievement(node: KdlNode, ctx: var KdlConfigContext): VictoryAchievementConfig =
  result = VictoryAchievementConfig(
    victoryAchieved: node.requireInt32("victoryAchieved", ctx)
  )

proc parsePenalties(node: KdlNode, ctx: var KdlConfigContext): PenaltiesPrestigeConfig =
  result = PenaltiesPrestigeConfig(
    highTaxThreshold: node.requireInt32("highTaxThreshold", ctx),
    highTaxPenalty: node.requireInt32("highTaxPenalty", ctx),
    highTaxFrequency: node.requireInt32("highTaxFrequency", ctx),
    veryHighTaxThreshold: node.requireInt32("veryHighTaxThreshold", ctx),
    veryHighTaxPenalty: node.requireInt32("veryHighTaxPenalty", ctx),
    veryHighTaxFrequency: node.requireInt32("veryHighTaxFrequency", ctx),
    maintenanceShortfallBase: node.requireInt32("maintenanceShortfallBase", ctx),
    maintenanceShortfallIncrement: node.requireInt32("maintenanceShortfallIncrement", ctx),
    blockadePenalty: node.requireInt32("blockadePenalty", ctx),
    overInvestEspionage: node.requireInt32("overInvestEspionage", ctx),
    overInvestCounterIntel: node.requireInt32("overInvestCounterIntel", ctx)
  )

proc parseTaxPenalties(node: KdlNode, ctx: var KdlConfigContext): TaxPenaltiesTier =
  result = TaxPenaltiesTier(
    tier1Min: node.requireInt32("tier1Min", ctx),
    tier1Max: node.requireInt32("tier1Max", ctx),
    tier1Penalty: node.requireInt32("tier1Penalty", ctx),
    tier2Min: node.requireInt32("tier2Min", ctx),
    tier2Max: node.requireInt32("tier2Max", ctx),
    tier2Penalty: node.requireInt32("tier2Penalty", ctx),
    tier3Min: node.requireInt32("tier3Min", ctx),
    tier3Max: node.requireInt32("tier3Max", ctx),
    tier3Penalty: node.requireInt32("tier3Penalty", ctx),
    tier4Min: node.requireInt32("tier4Min", ctx),
    tier4Max: node.requireInt32("tier4Max", ctx),
    tier4Penalty: node.requireInt32("tier4Penalty", ctx),
    tier5Min: node.requireInt32("tier5Min", ctx),
    tier5Max: node.requireInt32("tier5Max", ctx),
    tier5Penalty: node.requireInt32("tier5Penalty", ctx),
    tier6Min: node.requireInt32("tier6Min", ctx),
    tier6Max: node.requireInt32("tier6Max", ctx),
    tier6Penalty: node.requireInt32("tier6Penalty", ctx)
  )

proc parseTaxIncentives(node: KdlNode, ctx: var KdlConfigContext): TaxIncentivesTier =
  result = TaxIncentivesTier(
    tier1Min: node.requireInt32("tier1Min", ctx),
    tier1Max: node.requireInt32("tier1Max", ctx),
    tier1Prestige: node.requireInt32("tier1Prestige", ctx),
    tier2Min: node.requireInt32("tier2Min", ctx),
    tier2Max: node.requireInt32("tier2Max", ctx),
    tier2Prestige: node.requireInt32("tier2Prestige", ctx),
    tier3Min: node.requireInt32("tier3Min", ctx),
    tier3Max: node.requireInt32("tier3Max", ctx),
    tier3Prestige: node.requireInt32("tier3Prestige", ctx),
    tier4Min: node.requireInt32("tier4Min", ctx),
    tier4Max: node.requireInt32("tier4Max", ctx),
    tier4Prestige: node.requireInt32("tier4Prestige", ctx),
    tier5Min: node.requireInt32("tier5Min", ctx),
    tier5Max: node.requireInt32("tier5Max", ctx),
    tier5Prestige: node.requireInt32("tier5Prestige", ctx)
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
