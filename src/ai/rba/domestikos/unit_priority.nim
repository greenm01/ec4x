## Unit Priority Scoring Module
##
## Implements Act-aware priority scoring for unit construction.
## Replaces "first matching CST" algorithm with "best matching" scoring.
##
## Key Features:
## - Act appropriateness scoring (4.0 points max)
## - Strategic value scoring (2.0 points max)
## - Budget efficiency scoring (1.0 points max)
## - CST availability filtering (binary gate)
##
## Integration: Called by build_requirements.nim capacity filler

import std/options
import ../../../common/types/units
import ../../../engine/economy/config_accessors
import ../../common/types as ai_common_types
import ../config  # For globalRBAConfig

# ============================================================================
# CONFIG-DRIVEN SCORING FUNCTIONS
# ============================================================================
# All unit priority scores are now loaded from config/rba.toml
# This enables balance tuning without recompilation

proc getScoreFromConfig(scores: ShipClassScores, unit: ShipClass): float =
  ## Helper to extract score for a ship class from config ShipClassScores
  case unit
  of ShipClass.ETAC: scores.etac
  of ShipClass.Destroyer: scores.destroyer
  of ShipClass.Frigate: scores.frigate
  of ShipClass.Corvette: scores.corvette
  of ShipClass.Scout: scores.scout
  of ShipClass.LightCruiser: scores.light_cruiser
  of ShipClass.Cruiser: scores.cruiser
  of ShipClass.Raider: scores.raider
  of ShipClass.Battlecruiser: scores.battlecruiser
  of ShipClass.HeavyCruiser: scores.heavy_cruiser
  of ShipClass.Battleship: scores.battleship
  of ShipClass.Dreadnought: scores.dreadnought
  of ShipClass.SuperDreadnought: scores.super_dreadnought
  of ShipClass.Carrier: scores.carrier
  of ShipClass.SuperCarrier: scores.super_carrier
  of ShipClass.PlanetBreaker: scores.planet_breaker
  of ShipClass.TroopTransport: scores.troop_transport
  of ShipClass.Fighter: scores.fighter

# ============================================================================
# SCORING FUNCTIONS
# ============================================================================

proc getActAppropriatenessScore(
  unit: ShipClass,
  currentAct: ai_common_types.GameAct
): float =
  ## Get Act appropriateness score for unit (0.0 - 4.0 points)
  ## Units appropriate for current Act score higher
  ## Scores loaded from config/rba.toml [domestikos.unit_priorities.act*]
  let scores = case currentAct
    of ai_common_types.GameAct.Act1_LandGrab:
      globalRBAConfig.domestikos_unit_priorities_act1_land_grab
    of ai_common_types.GameAct.Act2_RisingTensions:
      globalRBAConfig.domestikos_unit_priorities_act2_rising_tensions
    of ai_common_types.GameAct.Act3_TotalWar:
      globalRBAConfig.domestikos_unit_priorities_act3_total_war
    of ai_common_types.GameAct.Act4_Endgame:
      globalRBAConfig.domestikos_unit_priorities_act4_endgame

  return getScoreFromConfig(scores, unit)

proc getStrategicValueScore(unit: ShipClass): float =
  ## Get strategic value score for unit (0.0 - 2.0 points)
  ## Capital > Medium > Escort > Light
  ## Scores loaded from config/rba.toml [domestikos.unit_priorities.strategic_values]
  return getScoreFromConfig(globalRBAConfig.domestikos_unit_priorities_strategic_values, unit)

proc getBudgetEfficiencyScore(unit: ShipClass, budget: int): float =
  ## Get budget efficiency score (0.0 - 1.0 points)
  ## Rewards filling the budget slot (higher cost ratio is better)
  let unitCost = getShipConstructionCost(unit)

  if unitCost > budget:
    return 0.0  # Unaffordable

  let costRatio = unitCost.float / budget.float

  # Score is directly proportional to budget utilization
  # This incentivizes building the most expensive (and powerful) ship
  # that fits within the per-slot budget for capacity fillers.
  return costRatio

proc calculateUnitPriority*(
  unit: ShipClass,
  currentAct: ai_common_types.GameAct,
  cstLevel: int,
  budget: int
): float =
  ## Calculate priority score for unit (0.0 - 7.0 points max)
  ## Returns -1.0 if unit not buildable (CST requirement not met)
  ##
  ## Scoring breakdown:
  ## - Act appropriateness: 0.0 - 4.0 points
  ## - Strategic value: 0.0 - 2.0 points
  ## - Budget efficiency: 0.0 - 1.0 points
  ##
  ## Example scores:
  ##   Act 2, Cruiser, CST IV, 200PP budget:
  ##     Act appropriateness: 4.0 (perfect for Act 2)
  ##     Strategic value: 1.5 (medium capital)
  ##     Budget efficiency: 1.0 (120PP cost, 60% of budget)
  ##     Total: 6.5 points
  ##
  ##   Act 2, Destroyer, CST I, 200PP budget:
  ##     Act appropriateness: 2.0 (not priority in Act 2)
  ##     Strategic value: 1.0 (escort)
  ##     Budget efficiency: 1.0 (40PP cost, 20% of budget)
  ##     Total: 4.0 points

  # CST availability check (binary gate)
  let requiredCST = getShipCSTRequirement(unit)
  if cstLevel < requiredCST:
    return -1.0  # Not buildable, filter out

  var score = 0.0

  # 1. Act appropriateness (0.0 - 4.0 points)
  score += getActAppropriatenessScore(unit, currentAct)

  # 2. Strategic value (0.0 - 2.0 points)
  score += getStrategicValueScore(unit)

  # 3. Budget efficiency (0.0 - 1.0 points)
  score += getBudgetEfficiencyScore(unit, budget)

  return score

# ============================================================================
# UNIT SELECTION
# ============================================================================

proc selectBestUnit*(
  candidates: seq[ShipClass],
  currentAct: ai_common_types.GameAct,
  cstLevel: int,
  budget: int
): Option[ShipClass] =
  ## Select best unit from candidates based on priority scoring
  ## Returns None if no affordable buildable unit exists
  ##
  ## Algorithm:
  ## 1. Score all candidates
  ## 2. Filter out unbuildable (CST requirement not met)
  ## 3. Filter out unaffordable (cost > budget)
  ## 4. Return highest scoring unit
  ## 5. If no valid unit, return None
  ##
  ## Example:
  ##   Candidates: [Destroyer, Cruiser, Battlecruiser, Battleship]
  ##   Act 2, CST IV, 200PP budget
  ##
  ##   Scores:
  ##     Destroyer (CST I, 40PP): 4.0 (buildable, affordable)
  ##     Cruiser (CST IV, 120PP): 6.5 (buildable, affordable) ← SELECTED
  ##     Battlecruiser (CST V, 180PP): 5.5 (NOT buildable, CST V > CST IV)
  ##     Battleship (CST VI, 250PP): -1.0 (NOT buildable, CST VI > CST IV)

  var bestUnit: Option[ShipClass] = none(ShipClass)
  var bestScore = -1.0

  for candidate in candidates:
    let score = calculateUnitPriority(candidate, currentAct, cstLevel, budget)

    # Skip unbuildable units (score = -1.0)
    if score < 0.0:
      continue

    # Update best if higher score
    if score > bestScore:
      bestScore = score
      bestUnit = some(candidate)

  return bestUnit
