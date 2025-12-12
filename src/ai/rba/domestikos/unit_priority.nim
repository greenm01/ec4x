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

import std/[tables, options]
import ../../../common/types/units
import ../../../engine/economy/config_accessors
import ../../common/types as ai_common_types

# ============================================================================
# ACT APPROPRIATENESS SCORING TABLES
# ============================================================================

const ActAppropriatenessScores = {
  # Act 1: Land Grab - Expansion and colony defense
  GameAct.Act1_LandGrab: {
    ShipClass.ETAC: 4.0,
    ShipClass.Destroyer: 3.0,
    ShipClass.Frigate: 3.0,
    ShipClass.Corvette: 3.0,
    ShipClass.Scout: 2.5,
    ShipClass.LightCruiser: 2.0,
    ShipClass.TroopTransport: 0.0,  # HARD GATE - Act 2+ only
    ShipClass.Cruiser: 1.0,
    ShipClass.Raider: 1.0,
    ShipClass.Battlecruiser: 0.5,
    ShipClass.HeavyCruiser: 0.5,
    ShipClass.Battleship: 0.5,
    ShipClass.Dreadnought: 0.5,
    ShipClass.SuperDreadnought: 0.5,
    ShipClass.Carrier: 0.5,
    ShipClass.SuperCarrier: 0.5,
    ShipClass.PlanetBreaker: 0.5,
    ShipClass.Fighter: 2.0
  }.toTable,

  # Act 2: Rising Tensions - Military buildup with medium capitals
  GameAct.Act2_RisingTensions: {
    ShipClass.Cruiser: 4.0,
    ShipClass.LightCruiser: 4.0,
    ShipClass.Battlecruiser: 4.0,
    ShipClass.Carrier: 3.5,
    ShipClass.HeavyCruiser: 3.0,
    ShipClass.Destroyer: 2.0,
    ShipClass.Frigate: 2.0,
    ShipClass.ETAC: 2.0,
    ShipClass.Raider: 2.5,
    ShipClass.Scout: 2.0,
    ShipClass.TroopTransport: 2.0,
    ShipClass.Corvette: 1.5,
    ShipClass.Battleship: 1.5,
    ShipClass.Dreadnought: 1.0,
    ShipClass.SuperDreadnought: 1.0,
    ShipClass.SuperCarrier: 1.5,
    ShipClass.PlanetBreaker: 1.0,
    ShipClass.Fighter: 2.5
  }.toTable,

  # Act 3: Total War - Heavy capitals and decisive battles
  GameAct.Act3_TotalWar: {
    ShipClass.Battleship: 4.0,
    ShipClass.Dreadnought: 4.0,
    ShipClass.SuperCarrier: 3.5,
    ShipClass.HeavyCruiser: 3.0,
    ShipClass.Cruiser: 2.5,
    ShipClass.Battlecruiser: 2.5,
    ShipClass.Carrier: 2.5,
    ShipClass.SuperDreadnought: 2.0,
    ShipClass.Raider: 2.0,
    ShipClass.PlanetBreaker: 2.0,
    ShipClass.LightCruiser: 2.0,
    ShipClass.Destroyer: 1.5,
    ShipClass.TroopTransport: 1.5,
    ShipClass.Frigate: 1.0,
    ShipClass.Corvette: 1.0,
    ShipClass.ETAC: 0.5,
    ShipClass.Scout: 1.0,
    ShipClass.Fighter: 2.0
  }.toTable,

  # Act 4: Endgame - Ultimate capitals and siege warfare
  GameAct.Act4_Endgame: {
    ShipClass.SuperDreadnought: 4.0,
    ShipClass.Dreadnought: 4.0,
    ShipClass.PlanetBreaker: 3.5,
    ShipClass.Battleship: 3.0,
    ShipClass.SuperCarrier: 3.0,
    ShipClass.HeavyCruiser: 2.5,
    ShipClass.Battlecruiser: 2.0,
    ShipClass.Carrier: 2.0,
    ShipClass.Cruiser: 1.5,
    ShipClass.Raider: 1.5,
    ShipClass.LightCruiser: 1.0,
    ShipClass.TroopTransport: 1.0,
    ShipClass.Destroyer: 0.5,
    ShipClass.Frigate: 0.5,
    ShipClass.Corvette: 0.5,
    ShipClass.ETAC: 0.5,
    ShipClass.Scout: 0.5,
    ShipClass.Fighter: 1.5
  }.toTable
}.toTable

# ============================================================================
# STRATEGIC VALUE SCORING
# ============================================================================

const StrategicValueScores = {
  # Capital Ships (2.0 points) - Ultimate firepower
  ShipClass.SuperDreadnought: 2.0,
  ShipClass.Dreadnought: 2.0,
  ShipClass.Battleship: 2.0,
  ShipClass.SuperCarrier: 2.0,

  # Medium Capitals (1.5 points) - Force projection
  ShipClass.Battlecruiser: 1.5,
  ShipClass.HeavyCruiser: 1.5,
  ShipClass.Cruiser: 1.5,
  ShipClass.Carrier: 1.5,

  # Escorts & Specialized (1.0 points) - Core fleet
  ShipClass.Destroyer: 1.0,
  ShipClass.LightCruiser: 1.0,
  ShipClass.Frigate: 1.0,
  ShipClass.ETAC: 1.0,
  ShipClass.Raider: 1.0,
  ShipClass.PlanetBreaker: 1.0,

  # Light Units (0.5 points) - Support roles
  ShipClass.Corvette: 0.5,
  ShipClass.Scout: 0.5,
  ShipClass.TroopTransport: 0.5,
  ShipClass.Fighter: 0.5
}.toTable

# ============================================================================
# SCORING FUNCTIONS
# ============================================================================

proc getActAppropriatenessScore(
  unit: ShipClass,
  currentAct: ai_common_types.GameAct
): float =
  ## Get Act appropriateness score for unit (0.0 - 4.0 points)
  ## Units appropriate for current Act score higher
  if ActAppropriatenessScores.hasKey(currentAct) and
     ActAppropriatenessScores[currentAct].hasKey(unit):
    return ActAppropriatenessScores[currentAct][unit]
  else:
    return 0.0

proc getStrategicValueScore(unit: ShipClass): float =
  ## Get strategic value score for unit (0.0 - 2.0 points)
  ## Capital > Medium > Escort > Light
  if StrategicValueScores.hasKey(unit):
    return StrategicValueScores[unit]
  else:
    return 0.0

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
