## Combat Doctrine Adapter
##
## Tactical adaptation based on observed enemy behavior patterns
## Uses combat doctrine intelligence (Phase 2.2) to recommend ROE settings
##
## Architecture: Pure tactical analysis, no state mutation

import std/[tables, options]
import ../../../common/types/core
import ../shared/intelligence_types
import ../controller_types

# =============================================================================
# ROE Recommendation Types
# =============================================================================

type
  ROERecommendation* = object
    ## Recommended Rules of Engagement vs specific enemy
    aggressiveness*: int  # 1-10 scale (1=defensive, 10=all-out)
    retreatThreshold*: int  # % health to retreat (100=never, 1=always)
    pursuitDistance*: int  # Max jumps to chase fleeing enemies
    formationSpread*: FormationSpread
    reasoning*: string  # Why these settings recommended

  FormationSpread* {.pure.} = enum
    ## Fleet formation density
    Tight      # Concentrated firepower, vulnerable to area attacks
    Standard   # Balanced formation
    Dispersed  # Spread out, harder to hit but less coordinated

# =============================================================================
# Doctrine-Based Adaptation
# =============================================================================

proc adaptTacticsToEnemyDoctrine*(
  enemyHouse: HouseId,
  intelSnapshot: IntelligenceSnapshot
): ROERecommendation =
  ## Adapt tactics based on observed enemy combat doctrine
  ## Phase 4.4: Uses combat doctrine from intelligence (Phase 2.2)

  # Check if we have doctrine intelligence on this enemy
  if not intelSnapshot.military.combatDoctrine.hasKey(enemyHouse):
    # No doctrine data - use balanced default
    return ROERecommendation(
      aggressiveness: 5,
      retreatThreshold: 30,
      pursuitDistance: 2,
      formationSpread: FormationSpread.Standard,
      reasoning: "No doctrine intelligence available - using balanced approach"
    )

  let doctrine = intelSnapshot.military.combatDoctrine[enemyHouse]

  # Adapt tactics based on enemy behavior patterns
  case doctrine
  of CombatDoctrine.Aggressive:
    # Enemy is aggressive - use defensive counter-tactics
    # Key: Survive initial assault, then counter-attack when they overextend
    return ROERecommendation(
      aggressiveness: 4,  # Defensive posture
      retreatThreshold: 40,  # Retreat early to preserve forces
      pursuitDistance: 1,  # Don't chase (likely a trap)
      formationSpread: FormationSpread.Dispersed,  # Spread out to reduce damage
      reasoning: "Enemy doctrine: Aggressive - using defensive counter (early retreat, " &
                 "dispersed formation, no pursuit)"
    )

  of CombatDoctrine.Defensive:
    # Enemy is defensive - use aggressive tactics to force engagement
    # Key: Press the attack, don't let them dictate terms
    return ROERecommendation(
      aggressiveness: 8,  # Aggressive stance
      retreatThreshold: 20,  # Stay in fight longer
      pursuitDistance: 3,  # Chase fleeing enemies
      formationSpread: FormationSpread.Tight,  # Concentrated firepower
      reasoning: "Enemy doctrine: Defensive - using aggressive counter (press attack, " &
                 "chase fleeing enemies, tight formation)"
    )

  of CombatDoctrine.Raiding:
    # Enemy uses hit-and-run tactics - counter with pursuit and area denial
    # Key: Don't let them disengage easily
    return ROERecommendation(
      aggressiveness: 6,  # Moderately aggressive
      retreatThreshold: 35,  # Moderate retreat threshold
      pursuitDistance: 4,  # Long pursuit to catch raiders
      formationSpread: FormationSpread.Standard,  # Balanced for flexibility
      reasoning: "Enemy doctrine: Raiding - using pursuit counter (long chase distance, " &
                 "prevent hit-and-run)"
    )

  of CombatDoctrine.Balanced:
    # Enemy uses balanced tactics - mirror with standard approach
    return ROERecommendation(
      aggressiveness: 5,  # Balanced
      retreatThreshold: 30,  # Standard retreat
      pursuitDistance: 2,  # Standard pursuit
      formationSpread: FormationSpread.Standard,  # Standard formation
      reasoning: "Enemy doctrine: Balanced - using standard approach"
    )

  of CombatDoctrine.Unknown:
    # Not enough data to classify - use cautious default
    return ROERecommendation(
      aggressiveness: 4,  # Slightly defensive
      retreatThreshold: 35,  # Conservative retreat
      pursuitDistance: 1,  # Minimal pursuit (unknown threat)
      formationSpread: FormationSpread.Standard,  # Standard formation
      reasoning: "Enemy doctrine: Unknown - using cautious approach until more data available"
    )

# =============================================================================
# Helper Functions
# =============================================================================

proc recommendedROEAgainst*(
  enemyHouse: HouseId,
  intelSnapshot: Option[IntelligenceSnapshot],
  defaultROE: int = 5
): int =
  ## Get recommended ROE aggressiveness level vs specific enemy
  ## Returns 1-10 scale (fallback to default if no intelligence)

  if intelSnapshot.isNone:
    return defaultROE

  let recommendation = adaptTacticsToEnemyDoctrine(enemyHouse, intelSnapshot.get())
  return recommendation.aggressiveness

proc shouldPursue*(
  enemyHouse: HouseId,
  distance: int,
  intelSnapshot: Option[IntelligenceSnapshot]
): bool =
  ## Determine if we should pursue fleeing enemy based on doctrine
  ## Returns true if pursuit recommended at given distance

  if intelSnapshot.isNone:
    return distance <= 2  # Default: pursue up to 2 jumps

  let recommendation = adaptTacticsToEnemyDoctrine(enemyHouse, intelSnapshot.get())
  return distance <= recommendation.pursuitDistance
