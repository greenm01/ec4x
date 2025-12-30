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
  ## Parse morale { tier "Crisis" { maxPrestige 0 } ... }
  var crisisMax, lowMax, averageMax, goodMax, highMax: int32
  highMax = 999  # Elite is implicit (81+)

  for child in node.children:
    if child.name == "tier" and child.args.len > 0:
      let tierName = child.args[0].getString()
      let maxPrestige = child.requireInt32("maxPrestige", ctx)
      case tierName
      of "Crisis": crisisMax = maxPrestige
      of "Low": lowMax = maxPrestige
      of "Average": averageMax = maxPrestige
      of "Good": goodMax = maxPrestige
      else: discard

  result = MoraleConfig(
    crisisMax: crisisMax,
    lowMax: lowMax,
    averageMax: averageMax,
    goodMax: goodMax,
    highMax: highMax
  )

proc parsePrestigeEvents(node: KdlNode, ctx: var KdlConfigContext): tuple[
  economic: EconomicPrestigeConfig,
  military: MilitaryPrestigeConfig,
  espionage: EspionagePrestigeConfig,
  espionageVictim: EspionageVictimPrestigeConfig,
  scout: ScoutPrestigeConfig,
  diplomacy: DiplomacyPrestigeConfig,
  victoryAchievement: VictoryAchievementConfig,
  penalties: PenaltiesPrestigeConfig
] =
  ## Parse prestigeEvents { techAdvancement { value 2 } shipDestroyed { value 1 victimLoss -1 } ... }
  var economic: EconomicPrestigeConfig
  var military: MilitaryPrestigeConfig
  var espionage: EspionagePrestigeConfig
  var espionageVictim: EspionageVictimPrestigeConfig
  var scout: ScoutPrestigeConfig
  var diplomacy: DiplomacyPrestigeConfig
  var victoryAchievement: VictoryAchievementConfig
  var penalties: PenaltiesPrestigeConfig

  for child in node.children:
    case child.name
    # Economic events
    of "techAdvancement": economic.techAdvancement = child.requireInt32("value", ctx)
    of "colonyEstablishment": economic.establishColony = child.requireInt32("value", ctx)

    # Military events - attacker side
    of "systemCapture": military.systemCapture = child.requireInt32("value", ctx)
    of "shipDestroyed": military.destroySquadron = child.requireInt32("value", ctx)
    of "starbaseDestroyed": military.destroyStarbase = child.requireInt32("value", ctx)
    of "fleetVictory": military.fleetVictory = child.requireInt32("value", ctx)
    of "planetConquered": military.invadePlanet = child.requireInt32("value", ctx)
    of "houseEliminated": military.eliminateHouse = child.requireInt32("value", ctx)

    # Military events - defender side (penalties)
    of "planetLost": military.losePlanet = child.requireInt32("value", ctx)
    of "undefendedColonyMultiplier":
      military.undefendedColonyPenaltyMultiplier = child.args[0].getFloat()

    # Espionage events - attacker
    of "techTheft":
      espionage.techTheft = child.requireInt32("value", ctx)
      espionageVictim.techTheftVictim = child.requireInt32("victimLoss", ctx)
    of "sabotageLowImpact":
      espionage.lowImpactSabotage = child.requireInt32("value", ctx)
      espionageVictim.lowImpactSabotageVictim = child.requireInt32("victimLoss", ctx)
    of "sabotageHighImpact":
      espionage.highImpactSabotage = child.requireInt32("value", ctx)
      espionageVictim.highImpactSabotageVictim = child.requireInt32("victimLoss", ctx)
    of "assassination":
      espionage.assassination = child.requireInt32("value", ctx)
      espionageVictim.assassinationVictim = child.requireInt32("victimLoss", ctx)
    of "cyberAttack":
      espionage.cyberAttack = child.requireInt32("value", ctx)
      espionageVictim.cyberAttackVictim = child.requireInt32("victimLoss", ctx)
    of "economicManipulation":
      espionage.economicManipulation = child.requireInt32("value", ctx)
      espionageVictim.economicManipulationVictim = child.requireInt32("victimLoss", ctx)
    of "psyopsCampaign":
      espionage.psyopsCampaign = child.requireInt32("value", ctx)
      espionageVictim.psyopsCampaignVictim = child.requireInt32("victimLoss", ctx)
    of "counterIntelligenceSweep":
      espionage.counterIntelSweep = child.requireInt32("value", ctx)
      espionageVictim.counterIntelSweepVictim = child.requireInt32("victimLoss", ctx)
    of "intelligenceTheft":
      espionage.intelligenceTheft = child.requireInt32("value", ctx)
      espionageVictim.intelligenceTheftVictim = child.requireInt32("victimLoss", ctx)
    of "plantDisinformation":
      espionage.plantDisinformation = child.requireInt32("value", ctx)
      espionageVictim.plantDisinformationVictim = child.requireInt32("victimLoss", ctx)
    of "espionageFailure":
      espionage.failedEspionage = child.requireInt32("value", ctx)

    # Victory
    of "victoryAchieved": victoryAchievement.victoryAchieved = child.requireInt32("value", ctx)

    else: discard

  result = (economic, military, espionage, espionageVictim, scout, diplomacy, victoryAchievement, penalties)

proc parseTaxPenalties(node: KdlNode, ctx: var KdlConfigContext): TaxPenaltiesTier =
  ## Parse taxPenalties { tier 1 { minRate=0 maxRate=50 penalty=0 } ... }
  var tiers: array[6, tuple[min: int32, max: int32, penalty: int32]]

  for child in node.children:
    if child.name == "tier" and child.args.len > 0:
      let tierNum = child.args[0].getInt()
      if tierNum >= 1 and tierNum <= 6:
        tiers[tierNum - 1] = (
          child.requireInt32("minRate", ctx),
          child.requireInt32("maxRate", ctx),
          child.requireInt32("penalty", ctx)
        )

  result = TaxPenaltiesTier(
    tier1Min: tiers[0].min, tier1Max: tiers[0].max, tier1Penalty: tiers[0].penalty,
    tier2Min: tiers[1].min, tier2Max: tiers[1].max, tier2Penalty: tiers[1].penalty,
    tier3Min: tiers[2].min, tier3Max: tiers[2].max, tier3Penalty: tiers[2].penalty,
    tier4Min: tiers[3].min, tier4Max: tiers[3].max, tier4Penalty: tiers[3].penalty,
    tier5Min: tiers[4].min, tier5Max: tiers[4].max, tier5Penalty: tiers[4].penalty,
    tier6Min: tiers[5].min, tier6Max: tiers[5].max, tier6Penalty: tiers[5].penalty
  )

proc parseTaxIncentives(node: KdlNode, ctx: var KdlConfigContext): TaxIncentivesTier =
  ## Parse taxIncentives { tier 1 { minRate=21 maxRate=30 prestigeBonusPerColony=1 } ... }
  var tiers: array[5, tuple[min: int32, max: int32, prestige: int32]]

  for child in node.children:
    if child.name == "tier" and child.args.len > 0:
      let tierNum = child.args[0].getInt()
      if tierNum >= 1 and tierNum <= 5:
        tiers[tierNum - 1] = (
          child.requireInt32("minRate", ctx),
          child.requireInt32("maxRate", ctx),
          child.requireInt32("prestigeBonusPerColony", ctx)
        )

  result = TaxIncentivesTier(
    tier1Min: tiers[0].min, tier1Max: tiers[0].max, tier1Prestige: tiers[0].prestige,
    tier2Min: tiers[1].min, tier2Max: tiers[1].max, tier2Prestige: tiers[1].prestige,
    tier3Min: tiers[2].min, tier3Max: tiers[2].max, tier3Prestige: tiers[2].prestige,
    tier4Min: tiers[3].min, tier4Max: tiers[3].max, tier4Prestige: tiers[3].prestige,
    tier5Min: tiers[4].min, tier5Max: tiers[4].max, tier5Prestige: tiers[4].prestige
  )

proc loadPrestigeConfig*(configPath: string): PrestigeConfig =
  ## Load prestige configuration from KDL file
  ## Uses kdl_config_helpers for type-safe parsing
  let doc = loadKdlConfig(configPath)
  var ctx = newContext(configPath)

  ctx.withNode("victory"):
    result.victory = parseVictory(doc.requireNode("victory", ctx), ctx)

  ctx.withNode("dynamicScaling"):
    result.dynamicScaling = parseDynamicScaling(doc.requireNode("dynamicScaling", ctx), ctx)

  ctx.withNode("morale"):
    result.morale = parseMorale(doc.requireNode("morale", ctx), ctx)

  # Parse prestigeEvents (contains all event values)
  ctx.withNode("prestigeEvents"):
    let events = parsePrestigeEvents(doc.requireNode("prestigeEvents", ctx), ctx)
    result.economic = events.economic
    result.military = events.military
    result.espionage = events.espionage
    result.espionageVictim = events.espionageVictim
    result.scout = events.scout
    result.diplomacy = events.diplomacy
    result.victoryAchievement = events.victoryAchievement
    result.penalties = events.penalties

  ctx.withNode("taxPenalties"):
    result.taxPenalties = parseTaxPenalties(doc.requireNode("taxPenalties", ctx), ctx)

  ctx.withNode("taxIncentives"):
    result.taxIncentives = parseTaxIncentives(doc.requireNode("taxIncentives", ctx), ctx)

  logInfo("Config", "Loaded prestige configuration", "path=", configPath)
