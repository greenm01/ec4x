## Basileus Personality Module
##
## Byzantine Basileus - Personality-driven advisor weighting
##
## Calculates advisor importance weights based on AI personality traits.
## Narrow range (0.85-1.15) ensures all advisors are heard while reducing extreme bias.

import std/tables
import ../controller_types
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
  ## Returns weights in range 0.85-1.15 (base) with Act and war-time modifiers up to 2.2x
  ## Higher weight = higher priority in resource allocation conflicts
  ##
  ## Formula: baseWeight = 1.0 ± (personalityTrait - 0.5) * 0.3
  ## This maps personality [0.0-1.0] to weight [0.85-1.15]
  ##
  ## War-time modifiers (user preference: aggressive 45%/55% budget floors):
  ## - Act 3 at war: Domestikos 1.8x (up from 1.15x)
  ## - Act 4 at war: Domestikos 1.8x (up from 1.15x)

  result = initTable[AdvisorType, float]()

  # Domestikos: influenced by aggression
  result[AdvisorType.Domestikos] = 1.0 + (personality.aggression - 0.5) * 0.3

  # Logothete: influenced by tech priority
  result[AdvisorType.Logothete] = 1.0 + (personality.techPriority - 0.5) * 0.3

  # Drungarius: influenced by aggression (espionage supports military)
  result[AdvisorType.Drungarius] = 1.0 + (personality.aggression - 0.5) * 0.15

  # Protostrator: influenced by diplomacy value
  result[AdvisorType.Protostrator] = 1.0 + (personality.diplomacyValue - 0.5) * 0.3

  # Eparch: influenced by economic focus
  result[AdvisorType.Eparch] = 1.0 + (personality.economicFocus - 0.5) * 0.3

  # Treasurer: always 1.0 (no personality weighting, handles budget allocation)
  result[AdvisorType.Treasurer] = 1.0

  # Act modifiers with war-time escalation
  case act
  of ai_types.GameAct.Act1_LandGrab:
    # Act 1: Classic 4X expansion economy - construction over research
    result[AdvisorType.Domestikos] *= 1.6  # +60% construction priority
    result[AdvisorType.Logothete] *= 0.7   # -30% research priority (defer to later Acts)
    result[AdvisorType.Eparch] *= 1.2      # +20% economy priority (infrastructure investment)
  of ai_types.GameAct.Act2_RisingTensions:
    if isAtWar:
      # Early war: Aggressive military boost + research reduction
      result[AdvisorType.Domestikos] *= 1.5   # Increased from 1.4
      result[AdvisorType.Logothete] *= 0.85   # Reduce research during war
    else:
      # Peacetime buildup: Balanced growth
      result[AdvisorType.Domestikos] *= 1.3
      result[AdvisorType.Logothete] *= 0.9
  of ai_types.GameAct.Act3_TotalWar, ai_types.GameAct.Act4_Endgame:
    let warMultiplier = if act == ai_types.GameAct.Act4_Endgame: 2.5 else: 2.0  # Act 4: Aggressive military focus
    let researchMultiplier = if act == ai_types.GameAct.Act4_Endgame: 0.5 else: 0.7  # Reduced research in Act 4

    if isAtWar:
      # War-time: Maximum military prioritization
      result[AdvisorType.Domestikos] *= warMultiplier
      result[AdvisorType.Logothete] *= researchMultiplier  # Minimum research during war
      result[AdvisorType.Drungarius] *= 1.20  # Intelligence more valuable in late-game war
      result[AdvisorType.Protostrator] *= 0.60  # Further reduced (focus on war, not diplomacy)
    else:
      # Peace-time: Moderate military boost + research investment
      result[AdvisorType.Domestikos] *= (if act == ai_types.GameAct.Act4_Endgame: 2.0 else: 1.3)  # Act 4: Strong peacetime military
      result[AdvisorType.Logothete] *= (if act == ai_types.GameAct.Act4_Endgame: 1.0 else: 0.8)  # Maintain some tech in Act 4
      result[AdvisorType.Drungarius] *= 1.15  # Increased peacetime intelligence
      result[AdvisorType.Protostrator] *= 0.75  # Reduced peacetime diplomacy

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
