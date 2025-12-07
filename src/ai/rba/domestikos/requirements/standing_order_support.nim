## Domestikos Standing Order Support (Gap 5)
##
## Integrates standing orders with build requirements system.
## Ensures defense-aware capacity filling and persistent defense assignments.
##
## Key Features:
## - Track defense history (turnsUndefended counter for escalation)
## - Generate requirements for systems with active defense orders
## - Bias capacity fillers toward defender ship types
## - Update ColonyDefenseHistory persistence tracking
##
## Following DoD (Data-Oriented Design): Pure functions for defense tracking.

import std/[tables, options, strformat, sets]
import ../../../../common/types/[core, units]
import ../../../../engine/[gamestate, logger, fog_of_war]
import ../../../../engine/economy/config_accessors
import ../../controller_types
import ../../config
import ../../common/types as ai_common_types
import ../../standing_orders_manager
import ../unit_priority

# =============================================================================
# Defense History Tracking (Gap 5 Persistence)
# =============================================================================

proc updateDefenseHistory*(
  controller: var AIController,
  filtered: FilteredGameState,
  currentTurn: int
) =
  ## Update defense history for all colonies
  ## Tracks turnsUndefended counter for escalation logic
  ##
  ## Escalation logic (from config):
  ## - 0-3 turns: Priority unchanged
  ## - 3-5 turns: Escalate Low → Medium
  ## - 5-7 turns: Escalate Medium → High
  ## - 7+ turns: Escalate High → Critical

  # Build set of systems with defenders (fleet or starbase)
  var systemsWithDefenders = initHashSet[SystemId]()

  for fleet in filtered.ownFleets:
    systemsWithDefenders.incl(fleet.location)

  for colony in filtered.ownColonies:
    if colony.starbases.len > 0:
      systemsWithDefenders.incl(colony.systemId)

  # Update defense history for all colonies
  for colony in filtered.ownColonies:
    let systemId = colony.systemId

    if systemId in systemsWithDefenders:
      # Colony is defended - reset counter
      if controller.defenseHistory.hasKey(systemId):
        var history = controller.defenseHistory[systemId]
        history.turnsUndefended = 0
        history.lastDefenderAssigned = currentTurn
        history.lastCheckedTurn = currentTurn
        controller.defenseHistory[systemId] = history

        logDebug(LogCategory.lcAI,
                 &"DefenseHistory: {systemId} now defended, reset counter")
      else:
        # Initialize history for defended colony
        controller.defenseHistory[systemId] = ColonyDefenseHistory(
          systemId: systemId,
          turnsUndefended: 0,
          lastDefenderAssigned: currentTurn,
          lastCheckedTurn: currentTurn
        )
    else:
      # Colony is undefended - increment counter
      if controller.defenseHistory.hasKey(systemId):
        var history = controller.defenseHistory[systemId]
        history.turnsUndefended += 1
        history.lastCheckedTurn = currentTurn
        controller.defenseHistory[systemId] = history

        logDebug(LogCategory.lcAI,
                 &"DefenseHistory: {systemId} undefended for " &
                 &"{history.turnsUndefended} turns")
      else:
        # Initialize history for undefended colony
        controller.defenseHistory[systemId] = ColonyDefenseHistory(
          systemId: systemId,
          turnsUndefended: 1,
          lastDefenderAssigned: 0,
          lastCheckedTurn: currentTurn
        )

  # Clean up stale entries (colonies no longer owned)
  var ownedSystems = initHashSet[SystemId]()
  for colony in filtered.ownColonies:
    ownedSystems.incl(colony.systemId)

  var staleSystems: seq[SystemId] = @[]
  for systemId in controller.defenseHistory.keys:
    if systemId notin ownedSystems:
      staleSystems.add(systemId)

  for systemId in staleSystems:
    controller.defenseHistory.del(systemId)
    logDebug(LogCategory.lcAI,
             &"DefenseHistory: Removed stale entry for {systemId}")

# =============================================================================
# Standing Order Support Requirements
# =============================================================================

proc generateStandingOrderSupportRequirements*(
  controller: var AIController,
  filtered: FilteredGameState,
  act: ai_common_types.GameAct,
  cstLevel: int,
  currentTurn: int
): seq[BuildRequirement] =
  ## Generate build requirements for systems with active defense orders
  ## but no actual defenders present (orders assigned but fleet not arrived)
  ##
  ## Called AFTER defense gap requirements to avoid duplication
  ## Only generates requirements for systems with standing orders that need
  ## support (fleet en route but not yet arrived)

  result = @[]

  if not globalRBAConfig.standing_orders_integration
      .generate_support_requirements:
    return result

  # Get systems with defense orders but no fleet present
  let undefendedWithOrders = getUndefendedSystemsWithOrders(
    controller, filtered)

  if undefendedWithOrders.len == 0:
    return result

  logInfo(LogCategory.lcAI,
          &"Standing order support: {undefendedWithOrders.len} systems " &
          &"have defense orders but no defenders present")

  # Get appropriate defender class for current act
  let defenderClass = case act
    of ai_common_types.GameAct.Act1_LandGrab:
      ShipClass.Corvette  # Cheap early defense
    of ai_common_types.GameAct.Act2_RisingTensions:
      ShipClass.LightCruiser  # Balanced mid-game defense
    of ai_common_types.GameAct.Act3_TotalWar:
      ShipClass.Cruiser  # Strong late-game defense
    of ai_common_types.GameAct.Act4_Endgame:
      ShipClass.Battlecruiser  # Maximum defense

  # Check if tech available
  if getShipCSTRequirement(defenderClass) > cstLevel:
    logWarn(LogCategory.lcAI,
            &"Standing order support: {defenderClass} requires CST " &
            &"{getShipCSTRequirement(defenderClass)}, have {cstLevel}")
    return result

  # Generate requirements for each undefended system with standing order
  for systemId in undefendedWithOrders:
    # Check if we have history for this system
    let turnsUndefended = if controller.defenseHistory.hasKey(systemId):
                            controller.defenseHistory[systemId].turnsUndefended
                          else:
                            0

    # Escalate priority based on how long system has been undefended
    let priority = if turnsUndefended >= globalRBAConfig.domestikos
                      .escalation_high_to_critical_turns:
                     RequirementPriority.Critical
                   elif turnsUndefended >= globalRBAConfig.domestikos
                      .escalation_medium_to_high_turns:
                     RequirementPriority.High
                   elif turnsUndefended >= globalRBAConfig.domestikos
                      .escalation_low_to_medium_turns:
                     RequirementPriority.High
                   else:
                     RequirementPriority.Medium

    let cost = getShipConstructionCost(defenderClass)

    let req = BuildRequirement(
      requirementType: RequirementType.DefenseGap,
      priority: priority,
      shipClass: some(defenderClass),
      itemId: none(string),
      quantity: 1,
      buildObjective: ai_common_types.BuildObjective.Defense,
      targetSystem: some(systemId),
      estimatedCost: cost,
      reason: &"Standing order support: {systemId} has DefendSystem " &
              &"order but no fleet present ({turnsUndefended} turns)"
    )

    result.add(req)

    logInfo(LogCategory.lcAI,
            &"Standing order support requirement: {defenderClass} for " &
            &"{systemId} (priority {priority}, {turnsUndefended} turns " &
            &"undefended)")

# =============================================================================
# Capacity Filler Biasing (Defense-Aware Filling)
# =============================================================================

proc biasFillerTowardsDefenders*(
  baseFillerCandidates: seq[ShipClass],
  controller: AIController,
  filtered: FilteredGameState,
  act: ai_common_types.GameAct
): seq[ShipClass] =
  ## Bias capacity filler candidates toward defender ship types
  ## when systems have unmet defense orders
  ##
  ## Strategy: If N systems need defenders, add N defender ships to
  ## the filler rotation (based on config filler_standing_order_bias)

  result = baseFillerCandidates

  if not globalRBAConfig.standing_orders_integration
      .generate_support_requirements:
    return result

  # Get systems with unmet defense needs
  let undefendedWithOrders = getUndefendedSystemsWithOrders(
    controller, filtered)

  if undefendedWithOrders.len == 0:
    return result

  # Calculate how many defender ships to add to rotation
  let biasFactor = globalRBAConfig.standing_orders_integration
                    .filler_standing_order_bias
  let defenderBonus = int(float(undefendedWithOrders.len) * biasFactor)

  if defenderBonus == 0:
    return result

  # Get appropriate defender class for current act
  let defenderClass = case act
    of ai_common_types.GameAct.Act1_LandGrab:
      ShipClass.Corvette
    of ai_common_types.GameAct.Act2_RisingTensions:
      ShipClass.LightCruiser
    of ai_common_types.GameAct.Act3_TotalWar:
      ShipClass.Cruiser
    of ai_common_types.GameAct.Act4_Endgame:
      ShipClass.Battlecruiser

  # Add defender ships to filler rotation
  for i in 0..<defenderBonus:
    result.add(defenderClass)

  logInfo(LogCategory.lcAI,
          &"Capacity filler bias: Added {defenderBonus}× {defenderClass} " &
          &"to rotation ({undefendedWithOrders.len} undefended systems " &
          &"with standing orders)")
