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

proc applyThreatBoost*(allocation: var BudgetAllocation) =
  ## Emergency military boost when house is under threat
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
  isUnderThreat: bool = false,
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
  ## 3. **NEW**: Consult Domestikos requirements (dynamic adjustment)
  ## 4. Apply threat response if needed (emergency military boost)
  ## 5. Normalize to ensure sum = 1.0
  ##
  ## Backward Compatible:
  ## - If admiralRequirements is none, behaves exactly like old system
  ## - Falls back to static config percentages

  # 1. Baseline from config
  result = getBaselineAllocation(act)

  # 2. Personality modifiers
  applyPersonalityModifiers(result, personality, act)

  # 3. Domestikos consultation (NEW - Treasurer-Domestikos consultation system)
  if admiralRequirements.isSome and availableBudget > 0:
    consultDomestikosRequirements(result, admiralRequirements.get(), availableBudget)

  # 4. Threat response
  if isUnderThreat:
    applyThreatBoost(result)

  # 5. Normalize
  normalizeAllocation(result)
