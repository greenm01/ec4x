## Drungarius Operations Module
##
## Byzantine Drungarius - Fleet/Intelligence Commander
##
## Strategic espionage and counter-intelligence decision-making

import std/[tables, options, random, sequtils, algorithm, strformat]
import ../../../common/types/[core, diplomacy]
import ../../../engine/[gamestate, fog_of_war, logger]
import ../../../engine/espionage/types as esp_types
import ../../../engine/diplomacy/types as dip_types
import ../../common/types as ai_types  # For OperationType
import ../controller_types # For AIController
import ../config  # For globalRBAConfig

export esp_types, core

proc selectEspionageTarget*(controller: AIController, filtered: FilteredGameState, rng: var Rand): HouseId =
  ## Choose espionage target strategically
  ## Prioritize: prestige leaders, diplomatic enemies, economic powerhouses
  let house = filtered.ownHouse
  let myPrestige = house.prestige

  var targets: seq[tuple[houseId: HouseId, priority: float]] = @[]

  for houseId, prestige in filtered.housePrestige:
    if houseId == controller.houseId:
      continue

    var priority = 0.0

    # Target prestige leaders (disrupt them)
    let prestigeGap = prestige - myPrestige
    if prestigeGap > 0:
      priority += prestigeGap.float * globalRBAConfig.drungarius.operations.target_prestige_gap_multiplier

    # Target diplomatic enemies (high priority)
    let relation = dip_types.getDiplomaticState(house.diplomaticRelations, houseId)
    if relation == dip_types.DiplomaticState.Enemy:
      priority += globalRBAConfig.drungarius.operations.target_enemy_priority_boost

    # Random factor (prevent predictability)
    priority += rng.rand(globalRBAConfig.drungarius.operations.target_random_factor_max)

    targets.add((houseId, priority))

  # Sort by priority (highest first)
  targets.sort(proc(a, b: auto): int = cmp(b.priority, a.priority))

  if targets.len > 0:
    return targets[0].houseId

  # Fallback: random (shouldn't happen)
  let allHouses = toSeq(filtered.housePrestige.keys)
  for houseId in allHouses:
    if houseId != controller.houseId:
      return houseId

  return controller.houseId  # Emergency fallback

proc selectEspionageOperation*(controller: AIController, filtered: FilteredGameState,
                              target: HouseId, projectedEBP: int, rng: var Rand): esp_types.EspionageAction =
  ## Choose espionage operation based on strategic context and available EBP
  ## projectedEBP = current points + this turn's investment (available immediately)
  let p = controller.personality
  let house = filtered.ownHouse
  let ebp = projectedEBP  # Use projected EBP, not current

  # Get target's relative strength
  let targetPrestige = filtered.housePrestige.getOrDefault(target, 0)
  let myPrestige = house.prestige
  let prestigeGap = targetPrestige - myPrestige

  # Load config for shorter references
  let cfg = globalRBAConfig.drungarius.operations

  # Intelligence Theft - Steal enemy's entire intelligence database (high-value intel warfare)
  # Very valuable when we lack intel on the galaxy or before major operations
  if ebp >= cfg.ebp_intelligence_theft and rng.rand(1.0) < cfg.chance_intelligence_theft:
    # Prioritize stealing intel from leaders (they have best intel) or enemies
    let relation = dip_types.getDiplomaticState(house.diplomaticRelations, target)
    if prestigeGap > cfg.prestige_gap_intelligence_theft or relation == dip_types.DiplomaticState.Enemy:
      return esp_types.EspionageAction.IntelligenceTheft  # Steal complete intel database

  # High-value operations when significantly behind (disruption strategy)
  if prestigeGap > cfg.prestige_gap_assassination and ebp >= cfg.ebp_assassination and rng.rand(1.0) < cfg.chance_assassination:
    return esp_types.EspionageAction.Assassination  # Slow down leader's tech

  if prestigeGap > cfg.prestige_gap_sabotage_high and ebp >= cfg.ebp_sabotage_high and rng.rand(1.0) < cfg.chance_sabotage_high:
    return esp_types.EspionageAction.SabotageHigh  # Cripple production

  # Plant Disinformation - Corrupt enemy intelligence (advanced psychological warfare)
  # Very effective against aggressive enemies who rely on intel for invasions
  if ebp >= cfg.ebp_plant_disinformation and rng.rand(1.0) < cfg.chance_plant_disinformation:
    # Target aggressive enemies (declared Enemy or significantly ahead in prestige)
    let relation = dip_types.getDiplomaticState(house.diplomaticRelations, target)
    if relation == dip_types.DiplomaticState.Enemy or targetPrestige > myPrestige + cfg.prestige_gap_disinformation:
      return esp_types.EspionageAction.PlantDisinformation  # Corrupt their intel for 2 turns

  # Economic warfare for economic-focused AIs
  if p.economicFocus > globalRBAConfig.drungarius.requirements.economic_focus_manipulation and ebp >= cfg.ebp_economic_manipulation and rng.rand(1.0) < cfg.chance_economic_manipulation:
    return esp_types.EspionageAction.EconomicManipulation  # Disrupt economy

  # Cyber attacks before invasions (if we have operations targeting this system)
  for op in controller.operations:
    if op.operationType == ai_types.OperationType.Invasion and ebp >= cfg.ebp_cyber_attack:
      # Check if target house owns the invasion target system
      # Check own colonies first
      for colony in filtered.ownColonies:
        if colony.systemId == op.targetSystem and colony.owner == target:
          return esp_types.EspionageAction.CyberAttack  # Soften defenses before invasion
      # Check visible colonies
      for colony in filtered.visibleColonies:
        if colony.systemId == op.targetSystem and colony.owner == target:
          return esp_types.EspionageAction.CyberAttack  # Soften defenses before invasion

  # Tech theft (default, safe, always useful)
  if ebp >= cfg.ebp_tech_theft:
    return esp_types.EspionageAction.TechTheft

  # Cheap harassment options
  if ebp >= cfg.ebp_psyops_campaign and rng.rand(1.0) < cfg.chance_psyops_campaign:
    return esp_types.EspionageAction.PsyopsCampaign  # Economic harassment

  if ebp >= cfg.ebp_sabotage_low:
    return esp_types.EspionageAction.SabotageLow  # Better than nothing

  # Fallback (won't execute if insufficient EBP)
  return esp_types.EspionageAction.TechTheft

proc shouldUseCounterIntel*(controller: AIController, filtered: FilteredGameState): bool =
  ## Decide if we should use Counter-Intelligence Sweep this turn (defensive)
  let house = filtered.ownHouse
  let cfg = globalRBAConfig.drungarius.operations

  # Need at least minimum CIP for counter-intel
  if house.espionageBudget.cipPoints < cfg.cip_minimum_counter_intel:
    return false

  # Protect during active invasion operations
  for op in controller.operations:
    if op.operationType == ai_types.OperationType.Invasion:
      return true  # Protect invasion plans from enemy intelligence

  # Protect when prestige is very high (we're winning, thus a target)
  if house.prestige > cfg.prestige_high_target_threshold:
    return true

  # Protect periodically if low aggression (defensive personality)
  if filtered.turn mod cfg.counter_intel_periodic_frequency == 0 and controller.personality.aggression < cfg.counter_intel_aggression_threshold:
    return true

  return false

proc generateEspionageAction*(controller: AIController, filtered: FilteredGameState,
                              projectedEBP: int, projectedCIP: int, rng: var Rand): Option[esp_types.EspionageAttempt] =
  ## Generate espionage action with strategic targeting and operation selection
  ## projectedEBP/CIP = current points + this turn's investment (available immediately)
  let p = controller.personality
  let house = filtered.ownHouse
  let cfg = globalRBAConfig.drungarius.operations

  logDebug(LogCategory.lcAI,
           &"{controller.houseId} Espionage check: prestige={house.prestige}, " &
           &"EBP={house.espionageBudget.ebpPoints}+{projectedEBP - house.espionageBudget.ebpPoints}={projectedEBP}, " &
           &"CIP={house.espionageBudget.cipPoints}+{projectedCIP - house.espionageBudget.cipPoints}={projectedCIP}")

  # Check for counter-intelligence need first (defensive)
  # Use projected CIP (includes this turn's investment)
  if projectedCIP >= cfg.cip_activation_threshold and shouldUseCounterIntel(controller, filtered):
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Espionage: Counter-Intelligence Sweep (defensive, CIP={projectedCIP})")
    # Counter-intel doesn't need a target
    return some(esp_types.EspionageAttempt(
      attacker: controller.houseId,
      target: controller.houseId,  # Self-target for counter-intel
      action: esp_types.EspionageAction.CounterIntelSweep,
      targetSystem: none(SystemId)
    ))

  # CRITICAL FIX: Don't gate espionage on EBP - let the operation selection handle costs
  # The old check (< 2 EBP) prevented ANY espionage from happening
  # Now: Always try espionage if we have scouts, let selectEspionageOperation pick affordable ops

  # CRITICAL: Don't do espionage if prestige is critically low (collapsing)
  # Detection costs -2 prestige. Only block if truly desperate (< 0 = collapse)
  if house.prestige < cfg.prestige_safety_threshold:
    logDebug(LogCategory.lcAI,
             &"{controller.houseId} Espionage: Skipped (prestige {house.prestige} < {cfg.prestige_safety_threshold}, too risky)")
    return none(esp_types.EspionageAttempt)

  # Frequency control: AI strategy determines espionage frequency
  # Rates from config - allow tuning espionage activity per AI archetype
  let espionageChance = if p.riskTolerance > cfg.frequency_risk_tolerance_threshold and p.economicFocus < cfg.frequency_economic_focus_cap:
    cfg.frequency_espionage_focused  # Espionage-focused AI
  elif p.economicFocus > cfg.frequency_economic_focus_threshold:
    cfg.frequency_economic_focused  # Economic AI
  elif p.aggression > cfg.frequency_aggression_threshold:
    cfg.frequency_aggressive  # Aggressive AI (focus on military instead)
  else:
    cfg.frequency_balanced  # Balanced AI

  let roll = rng.rand(1.0)
  logDebug(LogCategory.lcAI,
           &"{controller.houseId} Espionage: Frequency check - " &
           &"chance={espionageChance:.2f}, roll={roll:.2f}, " &
           &"personality=(risk={p.riskTolerance:.2f}, econ={p.economicFocus:.2f}, aggro={p.aggression:.2f})")

  if roll > espionageChance:
    logDebug(LogCategory.lcAI,
             &"{controller.houseId} Espionage: Skipped (roll {roll:.2f} > chance {espionageChance:.2f})")
    return none(esp_types.EspionageAttempt)

  # Select target strategically
  let target = selectEspionageTarget(controller, filtered, rng)
  logDebug(LogCategory.lcAI,
           &"{controller.houseId} Espionage: Selected target {target}")

  # Select operation based on strategic context (using projected EBP)
  let operation = selectEspionageOperation(controller, filtered, target, projectedEBP, rng)
  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Espionage: {operation} against {target} " &
          &"(projected EBP={projectedEBP})")

  return some(esp_types.EspionageAttempt(
    attacker: controller.houseId,
    target: target,
    action: operation,
    targetSystem: none(SystemId)
  ))
