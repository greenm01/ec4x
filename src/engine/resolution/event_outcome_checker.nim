import std/[tables, options, sequtils, algorithm, sugar]
import ../../../common/types/core # For HouseId, SystemId, FleetId
import ../../../engine/[gamestate, logger]
import ../../../engine/order_types # For FleetOrderType
import ../../ai/rba/goap/core/types # For Action, ActionType, GoalType, TechField
import ../../ai/rba/controller_types # For IntelligenceSnapshot, AdvisorRequirement, EconomicRequirementType
import ../../../common/types/diplomacy # For DiplomaticActionType, DiplomaticProposalType, DiplomaticState
import ../../../engine/espionage/types # For EspionageAction
import types as event_types # Use the event_types alias from resolution/types.nim


# Helper functions for checking actual outcomes of actions
proc getFleetCount*(gs: GameState, houseId: HouseId, systemId: SystemId, shipClass: string): int =
  ## Returns the total number of ships of a given class for a house in a system from GameState.
  if systemId not in gs.systems: return 0
  let sys = gs.systems[systemId]
  if houseId not in sys.fleets: return 0
  for _, fleet in sys.fleets[houseId]:
    if $fleet.shipClass == shipClass: # Assuming shipClass can be compared as string
      result += fleet.numShips

proc getFleetCount*(intel: controller_types.IntelligenceSnapshot, houseId: HouseId, systemId: SystemId, shipClass: string): int =
  ## Returns the total number of ships of a given class for a house in a system from IntelligenceSnapshot.
  if systemId not in intel.knownSystems: return 0
  let sysIntel = intel.knownSystems[systemId]
  if houseId not in sysIntel.fleets: return 0
  for _, fleetIntel in sysIntel.fleets[houseId]:
    if fleetIntel.shipClass == shipClass: # Assuming FleetIntel has a string field `shipClass`
      result += fleetIntel.numShips # Assuming FleetIntel has `numShips: int`

proc getFacilityOrGroundUnitCount*(gs: GameState, houseId: HouseId, systemId: SystemId, itemId: string, isFacility: bool): int =
  ## Returns the count of a facility or ground unit for a house in a system from GameState.
  if systemId not in gs.systems: return 0
  let sys = gs.systems[systemId]
  if houseId not in sys.facilities and isFacility: return 0
  if houseId not in sys.groundForces and not isFacility: return 0

  if isFacility:
    if sys.facilities[houseId].contains(itemId):
      return sys.facilities[houseId][itemId]
  else: # Ground units
    if sys.groundForces[houseId].contains(itemId):
      return sys.groundForces[houseId][itemId]
  return 0

proc getFacilityOrGroundUnitCount*(intel: controller_types.IntelligenceSnapshot, houseId: HouseId, systemId: SystemId, itemId: string, isFacility: bool): int =
  ## Returns the count of a facility or ground unit for a house in a system from IntelligenceSnapshot.
  if systemId not in intel.knownSystems: return 0
  let sysIntel = intel.knownSystems[systemId]
  if houseId not in sysIntel.facilities and isFacility: return 0
  if houseId not in sysIntel.groundForces and not isFacility: return 0
  
  if isFacility:
    if sysIntel.facilities[houseId].contains(itemId):
      return sysIntel.facilities[houseId][itemId]
  else: # Ground units
    if sysIntel.groundForces[houseId].contains(itemId):
      return sysIntel.groundForces[houseId][itemId]
  return 0


proc checkActualOutcome*(
  houseId: HouseId,
  action: goap_types.Action,
  initialGameState: GameState,
  intelSnapshot: controller_types.IntelligenceSnapshot,
  currentTechLevels: Table[goap_types.TechField, int], # AI's current tech levels from controller
  events: seq[event_types.GameEvent] # Events from the current turn, filtered for AI visibility
): bool =
  ## Checks if a GOAP action had its intended effect by comparing initial game state
  ## with the intelligence snapshot after orders have been processed, and by analyzing events.
  case action.actionType
  of goap_types.ActionType.BuildFleet:
    let initialCount = getFleetCount(initialGameState, houseId, action.target, action.shipClass)
    let currentCount = getFleetCount(intelSnapshot, houseId, action.target, action.shipClass)
    return currentCount > initialCount
  of goap_types.ActionType.BuildFacility:
    let initialCount = getFacilityOrGroundUnitCount(initialGameState, houseId, action.target, action.itemId, true)
    let currentCount = getFacilityOrGroundUnitCount(intelSnapshot, houseId, action.target, action.itemId, true)
    return currentCount > initialCount
  of goap_types.ActionType.BuildGroundForces:
    let initialCount = getFacilityOrGroundUnitCount(initialGameState, houseId, action.target, action.itemId, false)
    let currentCount = getFacilityOrGroundUnitCount(intelSnapshot, houseId, action.target, action.itemId, false)
    return currentCount > initialCount
  of goap_types.ActionType.AllocateResearch:
    let initialTechLevel = initialGameState.techLevels[houseId].getOrDefault(action.techField, 0) # Use getOrDefault for safety
    let currentTechLevel = currentTechLevels.getOrDefault(action.techField, 0)
    return currentTechLevel > initialTechLevel
  of goap_types.ActionType.MoveFleet, goap_types.ActionType.AttackColony, goap_types.ActionType.AssembleInvasionForce,
     goap_types.ActionType.EstablishDefense, goap_types.ActionType.ConductScoutMission:
    # Check for specific FleetOrder events (OrderIssued, OrderCompleted, OrderFailed, OrderRejected, OrderAborted)
    var eventFound = false
    for event in events:
      if event.houseId.isSome and event.houseId.get() == houseId and event.fleetId.isSome:
        # Check if the event is for *this specific GOAP action's order*
        let orderTypeStr = event.orderType.getOrDefault("") # OrderType is an Option[string]
        if $action.actionType == orderTypeStr:
          eventFound = true
          case event.eventType
          of event_types.GameEventType.OrderCompleted, event_types.GameEventType.OrderIssued:
            # OrderIssued also counts as success for multi-turn orders, means it started.
            # Further validate targetSystem if applicable.
            if action.target.isSome and event.systemId.isSome and action.target.get() != event.systemId.get():
              logger.logDebug(logger.LogCategory.lcAI, &"Fleet action '{action.actionType}' outcome: Target mismatch for event {event.eventType}.")
              continue # Target mismatch, not this action's event
            logger.logInfo(logger.LogCategory.lcAI, &"Fleet action '{action.actionType}' outcome: Completed/Issued (via event {event.eventType}).")
            return true
          of event_types.GameEventType.OrderFailed, event_types.GameEventType.OrderRejected, event_types.GameEventType.OrderAborted:
            logger.logWarn(logger.LogCategory.lcAI, &"Fleet action '{action.actionType}' outcome: FAILED (via event {event.eventType}: {event.reason.getOrDefault("No reason provided")}).")
            return false
          else:
            discard # Not a relevant event kind for this check

    # If no explicit event found, assume pending for this turn.
    # The stalled plan logic will catch long-running/unresponsive orders.
    if not eventFound:
      logger.logDebug(logger.LogCategory.lcAI, &"Fleet action '{action.actionType}' outcome: No explicit event found. Assuming pending.")
    return true
  of goap_types.ActionType.ConductEspionage:
    # Check for EspionageEvent indicating success or failure
    for event in events:
      if event.eventType == event_types.GameEventType.Espionage:
        if event.sourceHouseId.isSome and event.sourceHouseId.get() == houseId and
           event.targetHouseId.isSome and event.targetHouseId.get() == action.targetHouse.get() and # targetHouseId is Option[HouseId] for event
           event.operationType.isSome and event.operationType.get() == action.espionageAction:
          if event.success.getOrDefault(false):
            logger.logInfo(logger.LogCategory.lcAI, &"ConductEspionage outcome: Operation '{action.espionageAction}' against {action.targetHouse.get()} succeeded (via EspionageEvent).")
            return true
          else:
            logger.logWarn(logger.LogCategory.lcAI, &"ConductEspionage outcome: Operation '{action.espionageAction}' against {action.targetHouse.get()} FAILED (via EspionageEvent).")
            return false # Explicit failure from event
    logger.logDebug(logger.LogCategory.lcAI, &"ConductEspionage outcome: No explicit event for operation '{action.espionageAction}'. Assuming pending/ongoing.")
    return true # Default to true, rely on stalled plan for actual failure
  of goap_types.ActionType.ProposeAlliance:
    if action.targetHouse.isSome:
      for event in events:
        if event.eventType == event_types.GameEventType.Diplomacy:
          if event.sourceHouseId.isSome and event.sourceHouseId.get() == houseId and
             event.targetHouseId.isSome and event.targetHouseId.get() == action.targetHouse.get() and
             event.action == DiplomaticActionType.ProposeAlliance and event.success.getOrDefault(false):
            logger.logInfo(logger.LogCategory.lcAI, &"ProposeAlliance outcome: Alliance with {action.targetHouse.get()} successfully established (via DiplomacyEvent).")
            return true
    return false # No successful alliance event found
  of goap_types.ActionType.DeclareWar:
    if action.targetHouse.isSome:
      for event in events:
        if event.eventType == event_types.GameEventType.Diplomacy:
          if event.sourceHouseId.isSome and event.sourceHouseId.get() == houseId and
             event.targetHouseId.isSome and event.targetHouseId.get() == action.targetHouse.get() and
             event.action == DiplomaticActionType.DeclareWar and event.success.getOrDefault(false):
            logger.logInfo(logger.LogCategory.lcAI, &"DeclareWar outcome: War successfully declared on {action.targetHouse.get()} (via DiplomacyEvent).")
            return true
    return false # No successful war declaration event found
  of goap_types.ActionType.GainTreasury, goap_types.ActionType.SpendTreasury, goap_types.ActionType.TerraformPlanet:
    # These are internal GOAP actions or have their outcomes checked by other mechanisms/future events
    return true # Assume success if GOAP generated them
  else:
    # For any other actions, assume success for now.
    return true
