## @engine/telemetry/collectors/tech.nim
##
## Collect technology metrics from GameState.
## Covers: tech levels, research points, breakthroughs.

import std/options
import ../../types/[telemetry, core, game_state, event, house]

proc collectTechMetrics*(
  state: GameState,
  houseId: HouseId,
  prevMetrics: DiagnosticMetrics
): DiagnosticMetrics =
  ## Collect technology metrics from GameState
  result = prevMetrics  # Start with previous metrics

  let house = state.houses.entities.getOrDefault(houseId)

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
  # RESEARCH POINTS (tracked from events)
  # ================================================================

  var researchERP: int32 = 0
  var researchSRP: int32 = 0
  var researchTRP: int32 = 0
  var researchBreakthroughs: int32 = 0

  for event in state.lastTurnEvents:
    if event.houseId != some(houseId): continue

    case event.eventType:
    of Research, TechAdvance:
      # TODO: Extract research points from event details
      # researchERP += extractERP(event)
      # researchSRP += extractSRP(event)
      # researchTRP += extractTRP(event)
      researchBreakthroughs += 1
    else:
      discard

  result.researchERP = researchERP
  result.researchSRP = researchSRP
  result.researchTRP = researchTRP
  result.researchBreakthroughs = prevMetrics.researchBreakthroughs +
    researchBreakthroughs

  # ================================================================
  # RESEARCH WASTE TRACKING (Tech Level Caps)
  # ================================================================

  const maxEconomicLevel: int32 = 11
  const maxScienceLevel: int32 = 8

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

  # Track consecutive turns at max levels
  if result.techEL >= maxEconomicLevel:
    result.turnsAtMaxEL = prevMetrics.turnsAtMaxEL + 1
  else:
    result.turnsAtMaxEL = 0

  if result.techSL >= maxScienceLevel:
    result.turnsAtMaxSL = prevMetrics.turnsAtMaxSL + 1
  else:
    result.turnsAtMaxSL = 0
