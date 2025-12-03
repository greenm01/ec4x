## Colony Management Phase - Auto-repair, tax rates, colony-level settings
##
## Byzantine Imperial Government: Eparch's domain (economic administration)
##
## Responsibilities:
## - Auto-repair toggle management (enable/disable per colony)
## - Tax rate optimization (future: dock capacity allocation)
## - Colony-level economic settings
##
## Auto-repair strategy (User Requirements):
## - Enable at all colonies by default for convenience
## - AI can override if economic stress detected or conflicts with logistics
## - Manual repairs preferred when:
##   1. Treasury is critical (< threshold PP)
##   2. Dock capacity needed for urgent builds
##   3. Fleet redeployment planned (don't repair ships about to transfer)

import std/[tables, sequtils, options]
import std/logging
import ../../../engine/[gamestate, fog_of_war, order_types, logger]
import ../../../common/types/core
import ../../common/types as ai_types
import ../controller_types
import ../intelligence  # For colony analysis
import ../config  # For RBA configuration

proc generateColonyManagementOrders*(
  controller: AIController,
  filtered: FilteredGameState,
  currentAct: ai_types.GameAct
): seq[ColonyManagementOrder] =
  ## Generate colony management orders
  ##
  ## Auto-repair decision logic:
  ## - Enable by default (convenience for AI)
  ## - Disable if treasury < threshold (economic stress)
  ## - Future: Consider dock capacity constraints

  # Get auto-repair threshold from config (default 100 PP)
  let autoRepairThreshold = globalRBAConfig.eparch.auto_repair_threshold

  # Determine if we should enable auto-repair based on treasury
  let treasuryHealthy = controller.house.treasury >= autoRepairThreshold
  let enableAutoRepair = treasuryHealthy

  # Log decision
  if not treasuryHealthy:
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Disabling auto-repair (treasury {controller.house.treasury} < {autoRepairThreshold} PP)")
  else:
    logDebug(LogCategory.lcAI,
             &"{controller.houseId} Enabling auto-repair at all colonies (treasury healthy: {controller.house.treasury} PP)")

  # Generate orders for all owned colonies
  for colony in filtered.ownColonies:
    # Only generate order if setting needs to change
    if colony.autoRepairEnabled != enableAutoRepair:
      result.add(ColonyManagementOrder(
        colonyId: colony.id,
        action: ColonyManagementAction.SetAutoRepair,
        enabled: some(enableAutoRepair)
      ))

      logDebug(LogCategory.lcAI,
               &"{controller.houseId} Setting auto-repair at {colony.id}: {enableAutoRepair}")

  if result.len > 0:
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Generated {result.len} colony management orders (auto-repair toggles)")
