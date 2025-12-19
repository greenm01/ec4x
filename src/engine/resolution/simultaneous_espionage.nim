## Simultaneous Espionage Resolution
##
## Handles simultaneous resolution of SpyPlanet, SpySystem, and HackStarbase orders
## to prevent first-mover advantages in intelligence operations.

import std/[tables, options, random, strformat, algorithm]
import ../intelligence/spy_resolution
import simultaneous_types
import simultaneous_resolver
import ../gamestate
import ../index_maintenance
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
import ../intelligence/generator as intel_generator
import ../intelligence/types as intel_types

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

      # Get target from order
      if order.targetSystem.isNone:
        continue

      let targetSystem = order.targetSystem.get()

      # Log if fleet not at target (will attempt movement in Maintenance Phase)
      let fleet = state.fleets[order.fleetId]
      if fleet.location != targetSystem:
        logDebug(LogCategory.lcOrders, &"Espionage order queued: {order.fleetId} will move from {fleet.location} to {targetSystem}")

      result.add(EspionageIntent(
        houseId: houseId,
        fleetId: order.fleetId,
        targetSystem: targetSystem,
        orderType: $order.orderType,
        espionageStrength: espionageStrength
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
  rng: var Rand,
  events: var seq[res_types.GameEvent]
): seq[simultaneous_types.EspionageResult] =
  ## Resolve espionage conflict. On arrival, missions always succeed in starting.
  ## Detection happens each turn in conflict_phase, not on arrival.
  result = @[]

  if conflict.intents.len == 0:
    return

  for intent in conflict.intents:
    # Per docs, no detection on arrival. All espionage missions succeed in starting.
    let outcome = ResolutionOutcome.Success

    result.add(simultaneous_types.EspionageResult(
      houseId: intent.houseId,
      fleetId: intent.fleetId,
      originalTarget: intent.targetSystem,
      outcome: outcome,
      actualTarget: some(intent.targetSystem),
      prestigeAwarded: 0
    ))

proc resolveEspionage*(
  state: var GameState,
  orders: Table[HouseId, OrderPacket],
  rng: var Rand,
  events: var seq[res_types.GameEvent]
): seq[simultaneous_types.EspionageResult] =
  ## Main entry point: Resolve all espionage orders simultaneously
  result = @[]

  let intents = collectEspionageIntents(state, orders)
  if intents.len == 0:
    return

  let conflicts = detectEspionageConflicts(intents)

  for conflict in conflicts:
    let conflictResults = resolveEspionageConflict(state, conflict, rng, events)
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

proc processScoutIntelligence*(
  state: var GameState,
  results: seq[simultaneous_types.EspionageResult],
  orders: Table[HouseId, OrderPacket],
  rng: var Rand,
  events: var seq[res_types.GameEvent]
) =
  ## Process successful scout-based espionage results to start persistent missions.
  ## Per canonical turn cycle, on arrival the mission is registered.
  ## The fleet is locked, and detection/intel gathering happens each subsequent turn.

  for result in results:
    # Only process successful espionage arrivals
    if result.outcome != ResolutionOutcome.Success:
      continue

    if result.fleetId notin state.fleets:
      continue
    var fleet = state.fleets[result.fleetId]
    if fleet.owner != result.houseId:
      continue

    let targetSystem = result.originalTarget

    # Find order
    if result.houseId notin orders:
      continue
    let packet = orders[result.houseId]
    var orderOpt: Option[FleetOrder]
    for order in packet.fleetOrders:
      if order.fleetId == result.fleetId and order.targetSystem.isSome and
         order.targetSystem.get() == targetSystem and
         order.orderType in [FleetOrderType.SpyPlanet, FleetOrderType.SpySystem,
                              FleetOrderType.HackStarbase]:
        orderOpt = some(order)
        break
    if orderOpt.isNone:
      continue
    let order = orderOpt.get

    # Transition to OnSpyMission state
    fleet.missionState = FleetMissionState.OnSpyMission
    fleet.missionStartTurn = state.turn
    fleet.missionType = some(ord(order.orderType))
    fleet.missionTarget = some(targetSystem)

    # Register active mission
    let scoutCount = fleet.squadrons.len
    let missionType = case order.orderType
      of FleetOrderType.SpyPlanet: SpyMissionType.SpyOnPlanet
      of FleetOrderType.HackStarbase: SpyMissionType.HackStarbase
      of FleetOrderType.SpySystem: SpyMissionType.SpyOnSystem
      else: continue

    state.activeSpyMissions[result.fleetId] = ActiveSpyMission(
      fleetId: result.fleetId,
      missionType: missionType,
      targetSystem: targetSystem,
      scoutCount: scoutCount,
      startTurn: state.turn,
      ownerHouse: fleet.owner
    )

    state.fleets[result.fleetId] = fleet
    logInfo(LogCategory.lcOrders, &"Spy mission started for fleet {result.fleetId} at {targetSystem}")

    events.add(event_factory.orderCompleted(
      fleet.owner,
      result.fleetId,
      "SpyMissionStarted",
      details = &"spy mission started at {targetSystem} ({scoutCount} scouts)",
      systemId = some(targetSystem)
    ))
