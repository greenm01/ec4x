## Phase 0: Intelligence Distribution
##
## Drungarius generates unified intelligence snapshot for all advisors

import std/[strformat, options]
import ../../../engine/[gamestate, fog_of_war, logger]
import ../controller_types
import ../drungarius/intelligence_distribution

proc generateIntelligenceSnapshot*(
  filtered: FilteredGameState,
  controller: AIController
): IntelligenceSnapshot =
  ## Phase 0: Intelligence distribution
  ## Drungarius consolidates fog-of-war + reconnaissance + espionage data

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} === Phase 0: Intelligence Distribution ===")

  result = generateIntelligenceReport(filtered, controller)

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Intelligence snapshot: " &
          &"{result.knownEnemyColonies.len} enemy colonies, " &
          &"{result.highValueTargets.len} high-value targets")

  return result
