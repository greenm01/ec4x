## Basileus Personality Module
##
## Byzantine Basileus - Personality-driven advisor weighting
##
## Calculates advisor importance weights based on AI personality traits.
## Conservative range (0.7-1.3) ensures all advisors are always heard.

import std/tables
import ../../../common/types/core
import ../controller_types
import ../../../engine/gamestate
import ../../common/types as ai_types

# AdvisorType is now defined in controller_types.nim and imported
# type
#   AdvisorType* {.pure.} = enum
#     Domestikos, Logothete, Drungarius, Eparch, Protostrator, Treasurer

proc calculateAdvisorWeights*(
  personality: AIPersonality,
  act: ai_types.GameAct,
  isAtWar: bool = false  # NEW: War condition parameter
): Table[AdvisorType, float] =
  ## Calculate advisor weight multipliers based on personality, game act, and war status
  ##
  ## Returns weights in range 0.7-1.3 (base) with war-time boosts up to 1.8x
  ## Higher weight = higher priority in resource allocation conflicts
  ##
  ## Formula: baseWeight = 1.0 ± (personalityTrait - 0.5) * 0.6
  ## This maps personality [0.0-1.0] to weight [0.7-1.3]
  ##
  ## War-time modifiers (user preference: aggressive 45%/55% budget floors):
  ## - Act 3 at war: Domestikos 1.8x (up from 1.15x)
  ## - Act 4 at war: Domestikos 1.8x (up from 1.15x)

  result = initTable[AdvisorType, float]()

  # Domestikos: influenced by aggression
  result[AdvisorType.Domestikos] = 1.0 + (personality.aggression - 0.5) * 0.6

  # Logothete: influenced by tech priority
  result[AdvisorType.Logothete] = 1.0 + (personality.techPriority - 0.5) * 0.6

  # Drungarius: influenced by aggression (espionage supports military)
  result[AdvisorType.Drungarius] = 1.0 + (personality.aggression - 0.5) * 0.3

  # Protostrator: influenced by diplomacy value
  result[AdvisorType.Protostrator] = 1.0 + (personality.diplomacyValue - 0.5) * 0.6

  # Eparch: influenced by economic focus
  result[AdvisorType.Eparch] = 1.0 + (personality.economicFocus - 0.5) * 0.6

  # Treasurer: always 1.0 (no personality weighting, handles budget allocation)
  result[AdvisorType.Treasurer] = 1.0

  # Act modifiers with war-time escalation
  case act
  of ai_types.GameAct.Act3_TotalWar, ai_types.GameAct.Act4_Endgame:
    if isAtWar:
      # War-time: Aggressive military prioritization
      result[AdvisorType.Domestikos] *= 1.8   # UP from 1.15 (user preference)
      result[AdvisorType.Drungarius] *= 1.15  # Intelligence valuable in war
      result[AdvisorType.Protostrator] *= 0.70  # DOWN (focus on war, not diplomacy)
    else:
      # Peace-time: Moderate military boost
      result[AdvisorType.Domestikos] *= 1.3
      result[AdvisorType.Drungarius] *= 1.10
      result[AdvisorType.Protostrator] *= 0.85
  of ai_types.GameAct.Act2_RisingTensions:
    if isAtWar:
      # Early war: Moderate military boost
      result[AdvisorType.Domestikos] *= 1.4
  else:
    discard  # No act modifiers in Act 1 (peaceful expansion)

proc describeWeightRationale*(
  advisorType: AdvisorType,
  weight: float,
  personality: AIPersonality,
  act: ai_types.GameAct
): string =
  ## Generate human-readable explanation of why an advisor has a given weight
  ## Useful for diagnostics and debugging

  case advisorType
  of AdvisorType.Domestikos:
    result = "Aggression=" & $personality.aggression & " → weight=" & $weight
  of AdvisorType.Logothete:
    result = "TechPriority=" & $personality.techPriority & " → weight=" & $weight
  of AdvisorType.Drungarius:
    result = "Aggression=" & $personality.aggression & " (30%) → weight=" & $weight
  of AdvisorType.Protostrator:
    result = "DiplomacyValue=" & $personality.diplomacyValue & " → weight=" & $weight
  of AdvisorType.Eparch:
    result = "EconomicFocus=" & $personality.economicFocus & " → weight=" & $weight
  of AdvisorType.Treasurer:
    result = "Fixed at 1.0 (budget allocator)"

  if act in {ai_types.GameAct.Act3_TotalWar, ai_types.GameAct.Act4_Endgame}:
    result &= " [Act " & $act & " modifier applied]"
