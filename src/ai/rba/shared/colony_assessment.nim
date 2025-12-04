## Shared Colony Assessment Utilities
##
## Consolidated defense and strategic assessment logic used across all RBA modules.
## Eliminates inconsistencies between strategic, tactical, and logistics calculations.

import std/options
import ../../../common/types/[core, planets]
import ../../../engine/[gamestate, fog_of_war]
import ../intelligence  # For getColony helper

# =============================================================================
# Defense Assessment Types
# =============================================================================

type
  DefenseAssessment* = object
    ## Comprehensive defense assessment for a colony
    ## Used by strategic, tactical, and logistics modules for consistent decisions
    hasStarbase*: bool
    hasGroundDefense*: bool
    defensiveStrength*: int       # Numerical strength (0-500+)
    needsReinforcement*: bool     # Needs immediate defense buildup
    isVulnerable*: bool           # High-value target with weak defenses
    isHighValue*: bool            # Strategic importance (production/resources)

# =============================================================================
# Defense Strength Calculation
# =============================================================================

proc calculateDefensiveStrength*(colony: Colony): int =
  ## Calculate total defensive strength of a colony
  ## Consolidated from strategic.nim:28-45
  ##
  ## Scoring:
  ## - Starbase (operational): 100 points each
  ## - Ground battery: 20 points each
  ## - Planetary shield: 15 points per level
  ## - Ground forces: 10 points each (armies + marines)
  ##
  ## Thresholds:
  ## - 0-50: Undefended (vulnerable to raids)
  ## - 50-100: Minimal defense (ground only)
  ## - 100-200: Basic defense (1 starbase)
  ## - 200-300: Strong defense (2 starbases or 1 + ground)
  ## - 300+: Fortress (multiple starbases + ground)

  result = 0

  # Orbital defenses (starbases)
  for starbase in colony.starbases:
    if not starbase.isCrippled:
      result += 100

  # Ground defenses
  result += colony.groundBatteries * 20
  result += colony.planetaryShieldLevel * 15
  result += (colony.armies + colony.marines) * 10

# =============================================================================
# Strategic Value Assessment
# =============================================================================

proc assessStrategicValue*(colony: Colony): int =
  ## Calculate strategic value of a colony
  ## Consolidated from strategic.nim:54-77
  ##
  ## Value factors:
  ## - Production: 10 points per PP
  ## - Infrastructure: 20 points per level
  ## - Resources: 70 (Very Rich) to 0 (Very Poor)

  result = colony.production * 10
  result += colony.infrastructure * 20

  case colony.resources
  of ResourceRating.VeryRich:
    result += 70
  of ResourceRating.Rich:
    result += 50
  of ResourceRating.Abundant:
    result += 30
  of ResourceRating.Poor:
    result += 10
  of ResourceRating.VeryPoor:
    result += 0

proc isHighValueColony*(colony: Colony): bool =
  ## Check if colony is high-value target
  ## Consolidated from tactical.nim:90-92
  ##
  ## High value if:
  ## - Production >= 30 PP (major industrial center)
  ## - OR resources Rich/Very Rich (strategic materials)

  result = colony.production >= 30 or
           colony.resources in [ResourceRating.Rich,
                               ResourceRating.VeryRich,
                               ResourceRating.Abundant]

# =============================================================================
# Comprehensive Defense Assessment
# =============================================================================

proc assessColonyDefenseNeeds*(
  colony: Colony,
  filtered: FilteredGameState
): DefenseAssessment =
  ## Canonical defense assessment used by all modules
  ## Consolidates logic from strategic, tactical, and logistics modules
  ##
  ## Returns comprehensive assessment including:
  ## - Binary flags (hasStarbase, hasGroundDefense)
  ## - Numerical strength for detailed comparisons
  ## - Strategic flags (needsReinforcement, isVulnerable)

  # Basic defense presence (from logistics.nim:168-169)
  result.hasStarbase = colony.starbases.len > 0
  result.hasGroundDefense = colony.groundBatteries > 0 or
                            colony.armies > 0 or
                            colony.marines > 0

  # Numerical strength calculation (from strategic.nim:28-45)
  result.defensiveStrength = calculateDefensiveStrength(colony)

  # Strategic value assessment (from tactical.nim:90-92)
  result.isHighValue = isHighValueColony(colony)

  # Reinforcement needs assessment
  # Minimum viable defense: 100 points (1 starbase OR equivalent ground)
  result.needsReinforcement = not result.hasStarbase and
                               result.defensiveStrength < 100

  # Vulnerability assessment
  # High-value colonies with weak defenses are vulnerable
  # Threshold: 200 points (2 starbases or 1 starbase + significant ground)
  result.isVulnerable = result.isHighValue and
                        result.defensiveStrength < 200

# =============================================================================
# Helper Functions
# =============================================================================

proc assessColonyDefenseNeedsBySystem*(
  filtered: FilteredGameState,
  systemId: SystemId
): Option[DefenseAssessment] =
  ## Assess defense needs for a colony by system ID
  ## Returns None if system is not colonized or not owned by viewing house

  let colonyOpt = getColony(filtered, systemId)
  if colonyOpt.isNone:
    return none(DefenseAssessment)

  let colony = colonyOpt.get()
  if colony.owner != filtered.viewingHouse:
    return none(DefenseAssessment)

  return some(assessColonyDefenseNeeds(colony, filtered))

proc getUndefendedColonies*(
  filtered: FilteredGameState
): seq[Colony] =
  ## Get list of undefended colonies (for logistics prioritization)
  ## Undefended = no starbase AND defensiveStrength < 100

  result = @[]
  for colony in filtered.ownColonies:
    let assessment = assessColonyDefenseNeeds(colony, filtered)
    if assessment.needsReinforcement:
      result.add(colony)

proc getVulnerableColonies*(
  filtered: FilteredGameState
): seq[Colony] =
  ## Get list of vulnerable high-value colonies (for defense prioritization)
  ## Vulnerable = high value AND defensiveStrength < 200

  result = @[]
  for colony in filtered.ownColonies:
    let assessment = assessColonyDefenseNeeds(colony, filtered)
    if assessment.isVulnerable:
      result.add(colony)
