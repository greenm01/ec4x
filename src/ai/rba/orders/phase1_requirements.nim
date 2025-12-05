## Phase 1: Multi-Advisor Requirement Generation
##
## All 6 advisors generate requirements with intelligence context

import std/[strformat, tables, options]
import ../../../common/types/core
import ../../../engine/[gamestate, fog_of_war, logger, order_types]
import ../../../engine/fleet
import ../controller_types
import ../shared/intelligence_types  # For IntelligenceSnapshot
import ../../common/types as ai_types
import ../domestikos
import ../domestikos/build_requirements
import ../domestikos/fleet_analysis
import ../logothete/requirements as logothete_req
import ../drungarius/requirements as drungarius_req
import ../eparch/requirements as eparch_req
import ../protostrator/requirements as protostrator_req

proc generateAllAdvisorRequirements*(
  controller: var AIController,
  filtered: FilteredGameState,
  intelSnapshot: IntelligenceSnapshot,
  currentAct: ai_types.GameAct
) =
  ## Phase 1: Generate requirements from all advisors
  ## Each advisor analyzes game state and generates prioritized requirements

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} === Phase 1: Requirement Generation ===")

  # === DOMESTIKOS: Military build requirements ===
  logInfo(LogCategory.lcAI, &"{controller.houseId} Domestikos: Generating build requirements")

  # Generate Domestikos orders first (for fleet analysis and standing orders)
  var emptyTacticalOrders = initTable[FleetId, FleetOrder]()
  let domestikosOrders = generateDomestikosOrders(
    controller,
    filtered,
    currentAct,
    emptyTacticalOrders,
    some(intelSnapshot)  # Phase F: Pass intelligence for offensive/defensive operations
  )

  # Update standing orders with Domestikos changes
  updateStandingOrdersWithDomestikosChanges(controller, domestikosOrders)

  # Now generate build requirements (needs intelSnapshot)
  # We need fleet analyses - get them from Domestikos module
  # For now, create empty structures until we refactor generateDomestikosOrders
  let emptyAnalyses: seq[fleet_analysis.FleetAnalysis] = @[]
  let emptyDefensiveAssignments = initTable[FleetId, StandingOrder]()

  controller.domestikosRequirements = some(generateBuildRequirements(
    filtered,
    emptyAnalyses,  # TODO: Extract from generateDomestikosOrders
    emptyDefensiveAssignments,  # TODO: Extract from generateDomestikosOrders
    controller,
    currentAct,
    intelSnapshot
  ))

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Domestikos: Generated " &
          &"{controller.domestikosRequirements.get().requirements.len} build requirements")

  # === LOGOTHETE: Research requirements ===
  logInfo(LogCategory.lcAI, &"{controller.houseId} Logothete: Generating research requirements")

  controller.logotheteRequirements = some(logothete_req.generateResearchRequirements(
    controller,
    filtered,
    intelSnapshot,
    currentAct
  ))

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Logothete: Generated " &
          &"{controller.logotheteRequirements.get().requirements.len} research requirements")

  # === DRUNGARIUS: Espionage requirements ===
  logInfo(LogCategory.lcAI, &"{controller.houseId} Drungarius: Generating espionage requirements")

  controller.drungariusRequirements = some(drungarius_req.generateEspionageRequirements(
    controller,
    filtered,
    intelSnapshot,
    currentAct
  ))

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Drungarius: Generated " &
          &"{controller.drungariusRequirements.get().requirements.len} espionage requirements")

  # === EPARCH: Economic/infrastructure requirements ===
  logInfo(LogCategory.lcAI, &"{controller.houseId} Eparch: Generating economic requirements")

  controller.eparchRequirements = some(eparch_req.generateEconomicRequirements(
    controller,
    filtered,
    intelSnapshot
  ))

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Eparch: Generated " &
          &"{controller.eparchRequirements.get().requirements.len} economic requirements")

  # === PROTOSTRATOR: Diplomatic requirements ===
  logInfo(LogCategory.lcAI, &"{controller.houseId} Protostrator: Generating diplomatic requirements")

  controller.protostratorRequirements = some(protostrator_req.generateDiplomaticRequirements(
    controller,
    filtered,
    intelSnapshot
  ))

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Protostrator: Generated " &
          &"{controller.protostratorRequirements.get().requirements.len} diplomatic requirements")

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Phase 1 complete: All advisor requirements generated")
