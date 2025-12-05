## Budget Allocation Logic - Strategic Resource Distribution
##
## This module converts game state + Domestikos requirements → Budget percentages
##
## Responsibilities:
## - Extract baseline allocation from config (Act-specific percentages)
## - Apply personality modifiers (aggressive → more military, etc.)
## - Consult Domestikos requirements for dynamic adjustment
## - Apply threat response (emergency military boost)
## - Normalize to ensure sum = 1.0

import std/[tables, options]
import ../../common/types
import ../[config, controller_types]
import ../shared/intelligence_types
import ../drungarius/threat_assessment
import ./consultation

proc getBaselineAllocation*(act: GameAct): BudgetAllocation =
  ## Extract baseline allocation percentages from config based on game act
  ##
  ## These percentages represent strategic intent for each act:
  ## - Act 1: Maximum expansion (land grab)
  ## - Act 2: Build intelligence + defenses (rising tensions)
  ## - Act 3: Focus on military (total war)
  ## - Act 4: All-in military push (endgame)

  let cfg = case act
    of GameAct.Act1_LandGrab:
      globalRBAConfig.budget_act1_land_grab
    of GameAct.Act2_RisingTensions:
      globalRBAConfig.budget_act2_rising_tensions
    of GameAct.Act3_TotalWar:
      globalRBAConfig.budget_act3_total_war
    of GameAct.Act4_Endgame:
      globalRBAConfig.budget_act4_endgame

  result = {
    Expansion: cfg.expansion,
    Defense: cfg.defense,
    Military: cfg.military,
    Reconnaissance: cfg.reconnaissance,
    SpecialUnits: cfg.special_units,
    Technology: cfg.technology
  }.toTable()

proc applyPersonalityModifiers*(
  allocation: var BudgetAllocation,
  personality: AIPersonality,
  act: GameAct
) =
  ## Apply personality-based adjustments to allocation percentages
  ##
  ## Max adjustment: ±15% shift to maintain strategic diversity
  ##
  ## Personality traits:
  ## - Aggression: More military, less expansion
  ## - Economic focus: More expansion, less military (Act 1-2 only)

  let aggressionMod = (personality.aggression - 0.5) * 0.30  # -0.15 to +0.15
  let economicMod = (personality.economicFocus - 0.5) * 0.20  # -0.10 to +0.10

  # Aggressive personalities: More military, less expansion
  if aggressionMod > 0.0:
    allocation[Military] = min(0.80, allocation[Military] + aggressionMod)
    allocation[Expansion] = max(0.0, allocation[Expansion] - aggressionMod * 0.7)

  # Economic personalities: More expansion, less military (Act 1-2 only)
  # In war (Act 3-4), even economic AIs need military
  if economicMod > 0.0 and act in {GameAct.Act1_LandGrab, GameAct.Act2_RisingTensions}:
    allocation[Expansion] = min(0.75, allocation[Expansion] + economicMod)
    allocation[Military] = max(0.10, allocation[Military] - economicMod * 0.5)

proc applyThreatAwareAllocation*(
  allocation: var BudgetAllocation,
  intelSnapshot: IntelligenceSnapshot
) =
  ## Graduated threat-aware budget adjustment based on intelligence (Phase D)
  ## Replaces binary isUnderThreat flag with nuanced threat response

  let config = globalRBAConfig.intelligence.threat_response
  let threats = intelSnapshot.military.threatsByColony

  if threats.len == 0:
    return  # No threats, no adjustment

  # Calculate maximum threat level and threat count
  let maxThreat = calculateMaxThreatLevel(threats)  # Returns 0.0-1.0
  let threatCount = threats.len

  # Determine base boost percentage from threat level
  var boostPct: float
  var threatLevelName: string
  if maxThreat >= 0.85:
    boostPct = config.critical_threat_boost  # 1.00 (100%)
    threatLevelName = "Critical"
  elif maxThreat >= 0.6:
    boostPct = config.high_threat_boost  # 0.50 (50%)
    threatLevelName = "High"
  elif maxThreat >= 0.4:
    boostPct = config.moderate_threat_boost  # 0.30 (30%)
    threatLevelName = "Moderate"
  elif maxThreat >= 0.2:
    boostPct = config.low_threat_boost  # 0.10 (10%)
    threatLevelName = "Low"
  else:
    boostPct = 0.0  # None threat
    threatLevelName = "None"

  # Apply multi-threat multiplier if facing 3+ simultaneous threats
  var multiplierApplied = false
  if threatCount >= 3:
    boostPct *= config.multi_threat_multiplier  # 1.5x
    multiplierApplied = true

  # Log threat-aware allocation (Phase D)
  if boostPct > 0.0:
    import ../../../engine/logger
    import std/strformat
    logInfo(LogCategory.lcAI,
            &"Treasurer: Threat level {maxThreat:.2f} ({threatLevelName}) detected, " &
            &"applying {boostPct * 100:.0f}% budget boost" &
            (if multiplierApplied: &" (multi-threat {threatCount} colonies)" else: ""))

  # Calculate boost amounts
  let defenseBoost = boostPct * config.defense_boost_ratio  # 60%
  let militaryBoost = boostPct * config.military_boost_ratio  # 40%

  # Apply boosts (with caps to prevent exceeding 100%)
  allocation[Defense] = min(0.50, allocation[Defense] + defenseBoost)
  allocation[Military] = min(0.60, allocation[Military] + militaryBoost)

  # Reduce other categories proportionally to make room
  let totalBoost = defenseBoost + militaryBoost
  allocation[Expansion] = max(0.05, allocation[Expansion] - totalBoost * 0.5)
  allocation[SpecialUnits] = max(0.02, allocation[SpecialUnits] - totalBoost * 0.3)
  allocation[Reconnaissance] = max(0.03, allocation[Reconnaissance] - totalBoost * 0.2)

proc applyThreatBoost*(allocation: var BudgetAllocation) =
  ## Emergency military boost when house is under threat
  ## DEPRECATED: Replaced by applyThreatAwareAllocation() in Phase D
  ## Kept for backward compatibility
  ##
  ## Shifts 20% of budget to Military from Expansion and SpecialUnits

  let emergencyBoost = 0.20
  allocation[Military] = min(0.85, allocation[Military] + emergencyBoost)
  allocation[Expansion] = max(0.0, allocation[Expansion] - emergencyBoost * 0.7)
  allocation[SpecialUnits] = max(0.0, allocation[SpecialUnits] - emergencyBoost * 0.3)

proc normalizeAllocation*(allocation: var BudgetAllocation) =
  ## Ensure allocation percentages sum to exactly 1.0
  ##
  ## After all adjustments (personality, Domestikos consultation, threat response),
  ## the percentages may not sum to 1.0. This normalizes them.

  var total = 0.0
  for val in allocation.values:
    total += val

  if total != 1.0 and total > 0.0:
    for key in allocation.keys:
      allocation[key] = allocation[key] / total

proc allocateBudget*(
  act: GameAct,
  personality: AIPersonality,
  intelSnapshot: Option[IntelligenceSnapshot] = none(IntelligenceSnapshot),
  admiralRequirements: Option[BuildRequirements] = none(BuildRequirements),
  availableBudget: int = 0
): BudgetAllocation =
  ## Main budget allocation function - Treasurer's primary responsibility
  ##
  ## Returns percentage allocation across objectives (sums to 1.0)
  ##
  ## Process:
  ## 1. Start with baseline from config (strategic intent)
  ## 2. Apply personality modifiers (AI behavior diversity)
  ## 3. Consult Domestikos requirements (dynamic adjustment)
  ## 4. Apply threat-aware allocation (Phase D - graduated response)
  ## 5. Normalize to ensure sum = 1.0
  ##
  ## Backward Compatible:
  ## - If intelSnapshot is none, no threat-aware adjustment
  ## - If admiralRequirements is none, behaves exactly like old system
  ## - Falls back to static config percentages

  # 1. Baseline from config
  result = getBaselineAllocation(act)

  # 2. Personality modifiers
  applyPersonalityModifiers(result, personality, act)

  # 3. Domestikos consultation (Treasurer-Domestikos consultation system)
  if admiralRequirements.isSome and availableBudget > 0:
    consultDomestikosRequirements(result, admiralRequirements.get(), availableBudget)

  # 4. Threat-aware allocation (Phase D - NEW)
  if intelSnapshot.isSome:
    applyThreatAwareAllocation(result, intelSnapshot.get())

  # 5. Normalize
  normalizeAllocation(result)
