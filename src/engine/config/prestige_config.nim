## Prestige Configuration Loader
##
## Loads prestige values from config/kdl using nimkdl
## Allows runtime configuration for balance testing

import std/tables
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
  ## Parse morale section (now a placeholder, thresholds moved to combat.kdl)
  ## Morale tiers are calculated relative to leading house
  result = MoraleConfig(
    placeholder: true
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
  var economic = EconomicPrestigeConfig(
    iuMilestones: initTable[int32, IuMilestoneData]()
  )
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
  ## Returns Table indexed by tier number
  var tiers = initTable[int32, TaxPenaltyTierData]()

  for child in node.children:
    if child.name == "tier" and child.args.len > 0:
      let tierNum = int32(child.args[0].getInt())
      if tierNum >= 1 and tierNum <= 6:
        tiers[tierNum] = TaxPenaltyTierData(
          minRate: child.requireInt32("minRate", ctx),
          maxRate: child.requireInt32("maxRate", ctx),
          penalty: child.requireInt32("penalty", ctx)
        )

  result = TaxPenaltiesTier(tiers: tiers)

proc parseTaxIncentives(node: KdlNode, ctx: var KdlConfigContext): TaxIncentivesTier =
  ## Parse taxIncentives { tier 1 { minRate=21 maxRate=30 prestigeBonusPerColony=1 } ... }
  ## Returns Table indexed by tier number
  var tiers = initTable[int32, TaxIncentiveTierData]()

  for child in node.children:
    if child.name == "tier" and child.args.len > 0:
      let tierNum = int32(child.args[0].getInt())
      if tierNum >= 1 and tierNum <= 5:
        tiers[tierNum] = TaxIncentiveTierData(
          minRate: child.requireInt32("minRate", ctx),
          maxRate: child.requireInt32("maxRate", ctx),
          prestige: child.requireInt32("prestigeBonusPerColony", ctx)
        )

  result = TaxIncentivesTier(tiers: tiers)

proc parseMaintenanceShortfall(node: KdlNode, ctx: var KdlConfigContext,
                                penalties: var PenaltiesPrestigeConfig) =
  ## Parse maintenanceShortfall { basePenalty -5; escalationPerTurn -2 }
  ## Updates the penalties config with maintenance shortfall values
  penalties.maintenanceShortfallBase = node.requireInt32("basePenalty", ctx)
  penalties.maintenanceShortfallIncrement = node.requireInt32("escalationPerTurn", ctx)

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

  ctx.withNode("maintenanceShortfall"):
    parseMaintenanceShortfall(doc.requireNode("maintenanceShortfall", ctx), ctx,
                              result.penalties)

  logInfo("Config", "Loaded prestige configuration", "path=", configPath)
