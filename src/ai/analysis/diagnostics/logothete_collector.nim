## Logothete Collector - Research & Technology Domain
##
## Tracks technology levels, research point investment, breakthroughs,
## and research waste (investing in maxed tech).
##
## REFACTORED: 2025-12-06 - Extracted from diagnostics.nim (lines 406-456)

import std/tables
import ./types
import ../../../engine/gamestate
import ../../../engine/diagnostics_data
import ../../../common/types/core

proc collectLogotheteMetrics*(state: GameState, houseId: HouseId,
                              prevMetrics: DiagnosticMetrics,
                              report: TurnResolutionReport): DiagnosticMetrics =
  ## Collect research & technology metrics
  result = initDiagnosticMetrics(state.turn, houseId)

  let house = state.houses.getOrDefault(houseId)

  # ================================================================
  # TECHNOLOGY LEVELS (All 11 technology types)
  # ================================================================

  result.techCST = house.techTree.levels.constructionTech
  result.techWEP = house.techTree.levels.weaponsTech
  result.techEL = house.techTree.levels.economicLevel
  result.techSL = house.techTree.levels.scienceLevel
  result.techTER = house.techTree.levels.terraformingTech
  result.techELI = house.techTree.levels.electronicIntelligence
  result.techCLK = house.techTree.levels.cloakingTech
  result.techSLD = house.techTree.levels.shieldTech
  result.techCIC = house.techTree.levels.counterIntelligence
  result.techFD = house.techTree.levels.fighterDoctrine
  result.techACO = house.techTree.levels.advancedCarrierOps

  # ================================================================
  # RESEARCH POINTS (tracked from turn resolution)
  # ================================================================

  result.researchERP = report.researchERP
  result.researchSRP = report.researchSRP
  result.researchTRP = report.researchTRP

  result.researchBreakthroughs = prevMetrics.researchBreakthroughs + report.researchBreakthroughs

  # ================================================================
  # RESEARCH WASTE TRACKING (Tech Level Caps)
  # ================================================================

  # Detect wasted RP when investing in maxed tech levels
  const maxEconomicLevel = 11
  const maxScienceLevel = 8

  # Track ERP waste if EL at max
  if result.techEL >= maxEconomicLevel and result.researchERP > 0:
    result.researchWastedERP = result.researchERP
  else:
    result.researchWastedERP = 0

  # Track SRP waste if SL at max
  if result.techSL >= maxScienceLevel and result.researchSRP > 0:
    result.researchWastedSRP = result.researchSRP
  else:
    result.researchWastedSRP = 0

  # Track consecutive turns at max levels (similar to prestigeVictoryProgress)
  # This detects persistent waste over multiple turns
  if result.techEL >= maxEconomicLevel:
    result.turnsAtMaxEL = prevMetrics.turnsAtMaxEL + 1
  else:
    result.turnsAtMaxEL = 0

  if result.techSL >= maxScienceLevel:
    result.turnsAtMaxSL = prevMetrics.turnsAtMaxSL + 1
  else:
    result.turnsAtMaxSL = 0
