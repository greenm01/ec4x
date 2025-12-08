## Simultaneous Espionage Resolution
##
## Handles simultaneous resolution of SpyPlanet, SpySystem, and HackStarbase orders
## to prevent first-mover advantages in intelligence operations.

import std/[tables, options, random, strformat, algorithm]
import simultaneous_types
import simultaneous_resolver
import ../gamestate
import ../orders
import ../order_types
import ../logger
import ../squadron
import ../espionage/engine as esp_engine
import ../espionage/executor as esp_executor
import ../espionage/types as esp_types
import ../config/espionage_config
import ../../common/types/core
import ../prestige
import ./event_factory/intelligence as intelligence_events
import ./types as res_types

proc collectEspionageIntents*(
  state: GameState,
  orders: Table[HouseId, OrderPacket]
): seq[EspionageIntent] =
  ## Collect all espionage attempts
  result = @[]

  for houseId in state.houses.keys:
    if houseId notin orders:
      continue

    for order in orders[houseId].fleetOrders:
      if order.orderType notin [FleetOrderType.SpyPlanet, FleetOrderType.SpySystem, FleetOrderType.HackStarbase]:
        continue

      # Validate: fleet exists
      if order.fleetId notin state.fleets:
        continue

      # Calculate espionage strength using house prestige
      # Higher prestige = better intelligence operations
      let espionageStrength = state.houses[houseId].prestige

      # Check if house is dishonored
      let isDishonored = state.houses[houseId].dishonoredStatus.active

      # Get target from order
      if order.targetSystem.isNone:
        continue

      let targetSystem = order.targetSystem.get()

      result.add(EspionageIntent(
        houseId: houseId,
        fleetId: order.fleetId,
        targetSystem: targetSystem,
        orderType: $order.orderType,
        espionageStrength: espionageStrength,
        isDishonored: isDishonored
      ))

proc detectEspionageConflicts*(
  intents: seq[EspionageIntent]
): seq[EspionageConflict] =
  ## Group espionage intents by target system
  var targetSystems = initTable[SystemId, seq[EspionageIntent]]()

  for intent in intents:
    if intent.targetSystem notin targetSystems:
      targetSystems[intent.targetSystem] = @[]
    targetSystems[intent.targetSystem].add(intent)

  result = @[]
  for systemId, conflictingIntents in targetSystems:
    result.add(EspionageConflict(
      targetSystem: systemId,
      intents: conflictingIntents
    ))

proc resolveEspionageConflict*(
  state: var GameState,
  conflict: EspionageConflict,
  rng: var Rand
): seq[simultaneous_types.EspionageResult] =
  ## Resolve espionage conflict using prestige-based priority
  ## Dishonored houses go to end of list, if both dishonored then random
  result = @[]

  if conflict.intents.len == 0:
    return

  # Sort by: 1) honored status (honored first), 2) prestige (highest first), 3) random tiebreaker
  var sorted = conflict.intents

  # Separate honored and dishonored houses
  var honored: seq[EspionageIntent] = @[]
  var dishonored: seq[EspionageIntent] = @[]

  for intent in sorted:
    if intent.isDishonored:
      dishonored.add(intent)
    else:
      honored.add(intent)

  # Sort honored houses by prestige (descending)
  if honored.len > 0:
    let seed = tiebreakerSeed(state.turn, conflict.targetSystem)
    var honoredRng = initRand(seed)

    honored.sort do (a, b: EspionageIntent) -> int:
      if a.espionageStrength != b.espionageStrength:
        return cmp(b.espionageStrength, a.espionageStrength)  # Descending
      else:
        return honoredRng.rand(1) * 2 - 1  # Random: -1 or 1

  # Sort dishonored houses randomly
  if dishonored.len > 0:
    let seed = tiebreakerSeed(state.turn, conflict.targetSystem) + 1000  # Different seed
    var dishonoredRng = initRand(seed)

    dishonored.sort do (a, b: EspionageIntent) -> int:
      return dishonoredRng.rand(1) * 2 - 1  # Pure random

  # Combine: honored first, then dishonored
  sorted = honored & dishonored

  let first = sorted[0]
  logDebug(LogCategory.lcCombat,
           &"{conflict.intents.len} houses conducting espionage at {conflict.targetSystem}, priority: {first.houseId} (prestige: {first.espionageStrength}, dishonored: {first.isDishonored})")

  # All espionage attempts succeed, but in priority order
  # (Actual espionage resolution happens in main loop with proper detection rolls)
  for intent in sorted:
    result.add(simultaneous_types.EspionageResult(
      houseId: intent.houseId,
      fleetId: intent.fleetId,
      originalTarget: intent.targetSystem,
      outcome: ResolutionOutcome.Success,
      actualTarget: some(intent.targetSystem),
      prestigeAwarded: 0  # Prestige handled by espionage engine
    ))

proc resolveEspionage*(
  state: var GameState,
  orders: Table[HouseId, OrderPacket],
  rng: var Rand
): seq[simultaneous_types.EspionageResult] =
  ## Main entry point: Resolve all espionage orders simultaneously
  result = @[]

  let intents = collectEspionageIntents(state, orders)
  if intents.len == 0:
    return

  let conflicts = detectEspionageConflicts(intents)

  for conflict in conflicts:
    let conflictResults = resolveEspionageConflict(state, conflict, rng)
    result.add(conflictResults)

proc wasEspionageHandled*(
  results: seq[simultaneous_types.EspionageResult],
  houseId: HouseId,
  fleetId: FleetId
): bool =
  ## Check if an espionage order was already handled
  for result in results:
    if result.houseId == houseId and result.fleetId == fleetId:
      return true
  return false

proc processEspionageActions*(
  state: var GameState,
  orders: Table[HouseId, OrderPacket],
  rng: var Rand,
  events: var seq[res_types.GameEvent]
) =
  ## Process OrderPacket.espionageAction for all houses
  ## This handles EBP-based espionage actions (TechTheft, Assassination, etc.)
  ## separate from fleet-based espionage orders

  # Initialize espionage tracking for all houses this turn
  for houseId in state.houses.keys:
    state.houses[houseId].lastTurnEspionageAttempts = 0
    state.houses[houseId].lastTurnEspionageSuccess = 0
    state.houses[houseId].lastTurnEspionageDetected = 0
    state.houses[houseId].lastTurnTechThefts = 0
    state.houses[houseId].lastTurnSabotage = 0
    state.houses[houseId].lastTurnAssassinations = 0
    state.houses[houseId].lastTurnCyberAttacks = 0
    state.houses[houseId].lastTurnEBPSpent = 0
    state.houses[houseId].lastTurnCIPSpent = 0

  for houseId in state.houses.keys:
    if houseId notin orders:
      continue

    let packet = orders[houseId]

    # Step 1: Process EBP/CIP investments (purchase points with PP)
    if packet.ebpInvestment > 0:
      let ebpPurchased = esp_engine.purchaseEBP(state.houses[houseId].espionageBudget, packet.ebpInvestment)
      # Deduct PP from treasury (already projected in AI, but need to deduct actual cost)
      state.houses[houseId].treasury -= packet.ebpInvestment
      logInfo(LogCategory.lcEconomy, &"{houseId} purchased {ebpPurchased} EBP for {packet.ebpInvestment} PP")

    if packet.cipInvestment > 0:
      let cipPurchased = esp_engine.purchaseCIP(state.houses[houseId].espionageBudget, packet.cipInvestment)
      state.houses[houseId].treasury -= packet.cipInvestment
      # Track CIP spending for diagnostics
      state.houses[houseId].lastTurnCIPSpent += packet.cipInvestment
      logInfo(LogCategory.lcEconomy, &"{houseId} purchased {cipPurchased} CIP for {packet.cipInvestment} PP")

    # Step 2: Execute espionage action if present
    if packet.espionageAction.isNone:
      continue

    let attempt = packet.espionageAction.get()

    # Validate target house is not eliminated (leaderboard is public info)
    if attempt.target in state.houses:
      if state.houses[attempt.target].eliminated:
        logDebug(LogCategory.lcAI, &"{houseId} cannot target eliminated house {attempt.target}")
        continue

    # Check if attacker has sufficient EBP
    let actionCost = esp_engine.getActionCost(attempt.action)
    if not esp_engine.canAffordAction(state.houses[houseId].espionageBudget, attempt.action):
      logDebug(LogCategory.lcAI, &"{houseId} cannot afford {attempt.action} (cost: {actionCost} EBP, has: {state.houses[houseId].espionageBudget.ebpPoints})")
      continue

    # Spend EBP
    if not esp_engine.spendEBP(state.houses[houseId].espionageBudget, attempt.action):
      logDebug(LogCategory.lcAI, &"{houseId} failed to spend EBP for {attempt.action}")
      continue

    # Track espionage attempt and EBP spent
    state.houses[houseId].lastTurnEspionageAttempts += 1
    state.houses[houseId].lastTurnEBPSpent += actionCost

    # Track operation type
    case attempt.action
    of esp_types.EspionageAction.TechTheft:
      state.houses[houseId].lastTurnTechThefts += 1
    of esp_types.EspionageAction.SabotageLow, esp_types.EspionageAction.SabotageHigh:
      state.houses[houseId].lastTurnSabotage += 1
    of esp_types.EspionageAction.Assassination:
      state.houses[houseId].lastTurnAssassinations += 1
    of esp_types.EspionageAction.CyberAttack:
      state.houses[houseId].lastTurnCyberAttacks += 1
    else:
      discard  # Other operations not tracked separately

    logInfo(LogCategory.lcAI, &"{houseId} executing {attempt.action} against {attempt.target} (cost: {actionCost} EBP)")

    # Get target's CIC level from tech tree
    let targetCICLevel = case state.houses[attempt.target].techTree.levels.counterIntelligence
      of 1: esp_types.CICLevel.CIC1
      of 2: esp_types.CICLevel.CIC2
      of 3: esp_types.CICLevel.CIC3
      of 4: esp_types.CICLevel.CIC4
      of 5: esp_types.CICLevel.CIC5
      else: esp_types.CICLevel.CIC1

    let targetCIP = if attempt.target in state.houses:
                      state.houses[attempt.target].espionageBudget.cipPoints
                    else:
                      0

    # Execute espionage action with detection roll
    let result = esp_executor.executeEspionage(
      attempt,
      targetCICLevel,
      targetCIP,
      rng
    )

    # Apply results
    if result.success:
      # Track success for diagnostics
      state.houses[houseId].lastTurnEspionageSuccess += 1
      logInfo(LogCategory.lcAI, &"  SUCCESS: {result.description}")

      # Apply prestige changes
      for prestigeEvent in result.attackerPrestigeEvents:
        applyPrestigeEvent(state, attempt.attacker, prestigeEvent)
      for prestigeEvent in result.targetPrestigeEvents:
        applyPrestigeEvent(state, attempt.target, prestigeEvent)

      # Create espionage event based on action type
      case attempt.action
      of esp_types.EspionageAction.SabotageLow:
        if attempt.targetSystem.isSome:
          events.add(intelligence_events.sabotageConducted(
            attempt.attacker,
            attempt.target,
            attempt.targetSystem.get(),
            result.iuDamage,
            "Low"
          ))
      of esp_types.EspionageAction.SabotageHigh:
        if attempt.targetSystem.isSome:
          events.add(intelligence_events.sabotageConducted(
            attempt.attacker,
            attempt.target,
            attempt.targetSystem.get(),
            result.iuDamage,
            "High"
          ))
      of esp_types.EspionageAction.TechTheft:
        events.add(intelligence_events.techTheftExecuted(
          attempt.attacker,
          attempt.target,
          result.srpStolen
        ))
      of esp_types.EspionageAction.Assassination:
        events.add(intelligence_events.assassinationAttempted(
          attempt.attacker,
          attempt.target,
          globalEspionageConfig.effects.assassination_srp_reduction
        ))
      of esp_types.EspionageAction.EconomicManipulation:
        events.add(intelligence_events.economicManipulationExecuted(
          attempt.attacker,
          attempt.target,
          globalEspionageConfig.effects.economic_ncv_reduction
        ))
      of esp_types.EspionageAction.CyberAttack:
        if attempt.targetSystem.isSome:
          events.add(intelligence_events.cyberAttackConducted(
            attempt.attacker,
            attempt.target,
            attempt.targetSystem.get()
          ))
      of esp_types.EspionageAction.PsyopsCampaign:
        events.add(intelligence_events.psyopsCampaignLaunched(
          attempt.attacker,
          attempt.target,
          globalEspionageConfig.effects.psyops_tax_reduction
        ))
      of esp_types.EspionageAction.IntelligenceTheft:
        events.add(intelligence_events.intelligenceTheftExecuted(
          attempt.attacker,
          attempt.target
        ))
      of esp_types.EspionageAction.PlantDisinformation:
        events.add(intelligence_events.disinformationPlanted(
          attempt.attacker,
          attempt.target
        ))
      of esp_types.EspionageAction.CounterIntelSweep:
        if attempt.targetSystem.isSome:
          events.add(intelligence_events.counterIntelSweepExecuted(
            attempt.attacker,
            attempt.targetSystem.get()
          ))

      # Apply ongoing effects
      if result.effect.isSome:
        state.ongoingEffects.add(result.effect.get())

      # Apply immediate effects (SRP theft, IU damage, etc.)
      if result.srpStolen > 0:
        if attempt.target in state.houses:
          state.houses[attempt.target].techTree.accumulated.science =
            max(0, state.houses[attempt.target].techTree.accumulated.science - result.srpStolen)
          state.houses[attempt.attacker].techTree.accumulated.science += result.srpStolen
          logInfo(LogCategory.lcAI, &"    Stole {result.srpStolen} SRP from {attempt.target}")
    else:
      # Track detection for diagnostics
      state.houses[houseId].lastTurnEspionageDetected += 1
      logInfo(LogCategory.lcAI, &"  DETECTED by {attempt.target}")
      # Apply detection prestige penalties
      for prestigeEvent in result.attackerPrestigeEvents:
        applyPrestigeEvent(state, attempt.attacker, prestigeEvent)

      # Create detection event
      if attempt.targetSystem.isSome:
        events.add(intelligence_events.spyMissionDetected(
          attempt.attacker,
          attempt.target,
          attempt.targetSystem.get(),
          $attempt.action
        ))
