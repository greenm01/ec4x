## RBA Espionage Module
##
## Strategic espionage and counter-intelligence decision-making

import std/[tables, options, random, sequtils, algorithm]
import ../../common/types/[core, diplomacy]
import ../../engine/[gamestate, fog_of_war]
import ../../engine/espionage/types as esp_types
import ../../engine/diplomacy/types as dip_types
import ../common/types as ai_types  # For OperationType
import ./controller_types

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
      priority += prestigeGap.float * 0.01  # +1 priority per 100 prestige gap

    # Target diplomatic enemies (high priority)
    let relation = dip_types.getDiplomaticState(house.diplomaticRelations, houseId)
    if relation == dip_types.DiplomaticState.Enemy:
      priority += 200.0  # Major priority boost for enemies

    # Random factor (prevent predictability)
    priority += rng.rand(50.0)

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
                              target: HouseId, rng: var Rand): esp_types.EspionageAction =
  ## Choose espionage operation based on strategic context and available EBP
  let p = controller.personality
  let house = filtered.ownHouse
  let ebp = house.espionageBudget.ebpPoints

  # Get target's relative strength
  let targetPrestige = filtered.housePrestige.getOrDefault(target, 0)
  let myPrestige = house.prestige
  let prestigeGap = targetPrestige - myPrestige

  # Intelligence Theft - Steal enemy's entire intelligence database (high-value intel warfare)
  # Very valuable when we lack intel on the galaxy or before major operations
  if ebp >= 8 and rng.rand(1.0) < 0.15:  # 15% chance when available
    # Prioritize stealing intel from leaders (they have best intel) or enemies
    let relation = dip_types.getDiplomaticState(house.diplomaticRelations, target)
    if prestigeGap > 100 or relation == dip_types.DiplomaticState.Enemy:
      return esp_types.EspionageAction.IntelligenceTheft  # Steal complete intel database

  # High-value operations when significantly behind (disruption strategy)
  if prestigeGap > 300 and ebp >= 10 and rng.rand(1.0) < 0.3:
    return esp_types.EspionageAction.Assassination  # Slow down leader's tech

  if prestigeGap > 200 and ebp >= 7 and rng.rand(1.0) < 0.4:
    return esp_types.EspionageAction.SabotageHigh  # Cripple production

  # Plant Disinformation - Corrupt enemy intelligence (advanced psychological warfare)
  # Very effective against aggressive enemies who rely on intel for invasions
  if ebp >= 6 and rng.rand(1.0) < 0.2:  # 20% chance when available
    # Target aggressive enemies (declared Enemy or significantly ahead in prestige)
    let relation = dip_types.getDiplomaticState(house.diplomaticRelations, target)
    if relation == dip_types.DiplomaticState.Enemy or targetPrestige > myPrestige + 200:
      return esp_types.EspionageAction.PlantDisinformation  # Corrupt their intel for 2 turns

  # Economic warfare for economic-focused AIs
  if p.economicFocus > 0.6 and ebp >= 6 and rng.rand(1.0) < 0.5:
    return esp_types.EspionageAction.EconomicManipulation  # Disrupt economy

  # Cyber attacks before invasions (if we have operations targeting this system)
  for op in controller.operations:
    if op.operationType == ai_types.OperationType.Invasion and ebp >= 6:
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
  if ebp >= 5:
    return esp_types.EspionageAction.TechTheft

  # Cheap harassment options
  if ebp >= 3 and rng.rand(1.0) < 0.5:
    return esp_types.EspionageAction.PsyopsCampaign  # Economic harassment

  if ebp >= 2:
    return esp_types.EspionageAction.SabotageLow  # Better than nothing

  # Fallback (won't execute if insufficient EBP)
  return esp_types.EspionageAction.TechTheft

proc shouldUseCounterIntel*(controller: AIController, filtered: FilteredGameState): bool =
  ## Decide if we should use Counter-Intelligence Sweep this turn (defensive)
  let house = filtered.ownHouse

  # Need at least 4 CIP for counter-intel
  if house.espionageBudget.cipPoints < 4:
    return false

  # Protect during active invasion operations
  for op in controller.operations:
    if op.operationType == ai_types.OperationType.Invasion:
      return true  # Protect invasion plans from enemy intelligence

  # Protect when prestige is very high (we're winning, thus a target)
  if house.prestige > 900:
    return true

  # Protect periodically (every 5 turns) if low aggression (defensive personality)
  if filtered.turn mod 5 == 0 and controller.personality.aggression < 0.5:
    return true

  return false

proc generateEspionageAction*(controller: AIController, filtered: FilteredGameState, rng: var Rand): Option[esp_types.EspionageAttempt] =
  ## Generate espionage action with strategic targeting and operation selection
  let p = controller.personality
  let house = filtered.ownHouse

  # Check for counter-intelligence need first (defensive)
  if shouldUseCounterIntel(controller, filtered):
    # Counter-intel doesn't need a target
    return some(esp_types.EspionageAttempt(
      attacker: controller.houseId,
      target: controller.houseId,  # Self-target for counter-intel
      action: esp_types.EspionageAction.CounterIntelSweep,
      targetSystem: none(SystemId)
    ))

  # Check if we have EBP for offensive operations (min 2 for low-impact sabotage)
  if house.espionageBudget.ebpPoints < 2:
    return none(esp_types.EspionageAttempt)

  # CRITICAL: Don't do espionage if prestige is critically low (collapsing)
  # Detection costs -2 prestige. Only block if truly desperate (< 0 = collapse)
  if house.prestige < 50:
    return none(esp_types.EspionageAttempt)

  # Frequency control: AI strategy determines espionage investment
  # Economic/Turtle: 2-3% EBP budget (infrequent)
  # Balanced: 3-4% EBP budget (moderate)
  # Aggressive: 1-2% EBP budget (minimal, focus on military)
  # Espionage strategy: 4-5% EBP budget (frequent)
  let espionageChance = if p.riskTolerance > 0.6 and p.economicFocus < 0.5:
    0.5  # Espionage-focused AI (50% chance per turn)
  elif p.economicFocus > 0.7:
    0.2  # Economic AI (20% chance, minimal espionage)
  elif p.aggression > 0.7:
    0.15  # Aggressive AI (15% chance, focus on military instead)
  else:
    0.3  # Balanced AI (30% chance)

  if rng.rand(1.0) > espionageChance:
    return none(esp_types.EspionageAttempt)

  # Select target strategically
  let target = selectEspionageTarget(controller, filtered, rng)

  # Select operation based on strategic context
  let operation = selectEspionageOperation(controller, filtered, target, rng)

  return some(esp_types.EspionageAttempt(
    attacker: controller.houseId,
    target: target,
    action: operation,
    targetSystem: none(SystemId)
  ))
