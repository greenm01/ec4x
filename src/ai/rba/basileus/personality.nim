## Basileus Personality Module
##
## Byzantine Basileus - Personality-driven advisor weighting
##
## Calculates advisor importance weights based on AI personality traits.
## Narrow range (0.85-1.15) ensures all advisors are heard while reducing extreme bias.

import std/tables
import ../controller_types
import ../../common/types as ai_types
import ../config  # For globalRBAConfig

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

  # Personality influence multipliers from config/rba.toml [basileus]
  # Domestikos: influenced by aggression
  result[AdvisorType.Domestikos] = 1.0 + (personality.aggression - 0.5) *
    globalRBAConfig.basileus.personality_domestikos_multiplier

  # Logothete: influenced by tech priority
  result[AdvisorType.Logothete] = 1.0 + (personality.techPriority - 0.5) *
    globalRBAConfig.basileus.personality_logothete_multiplier

  # Drungarius: influenced by aggression (espionage supports military)
  result[AdvisorType.Drungarius] = 1.0 + (personality.aggression - 0.5) *
    globalRBAConfig.basileus.personality_drungarius_multiplier

  # Protostrator: influenced by diplomacy value
  result[AdvisorType.Protostrator] = 1.0 + (personality.diplomacyValue - 0.5) *
    globalRBAConfig.basileus.personality_protostrator_multiplier

  # Eparch: influenced by economic focus
  result[AdvisorType.Eparch] = 1.0 + (personality.economicFocus - 0.5) *
    globalRBAConfig.basileus.personality_eparch_multiplier

  # Treasurer: always 1.0 (no personality weighting, handles budget allocation)
  result[AdvisorType.Treasurer] = 1.0

  # Act-specific advisor priority multipliers (from config/rba.toml [act_priorities])
  # These multipliers encode the 4-Act Strategic Progression from architecture docs
  # Baseline multipliers from config, with war-time escalation from [basileus]
  case act
  of ai_types.GameAct.Act1_LandGrab:
    # Act 1: Land Grab - Expansion & Reconnaissance
    # Architecture priorities: Eparch CRITICAL, Domestikos HIGH, others MEDIUM/LOW
    let priorities = globalRBAConfig.act_priorities.act1_land_grab
    result[AdvisorType.Eparch] *= priorities.eparch_multiplier
    result[AdvisorType.Domestikos] *= priorities.domestikos_multiplier
    result[AdvisorType.Drungarius] *= priorities.drungarius_multiplier
    result[AdvisorType.Logothete] *= priorities.logothete_multiplier
    result[AdvisorType.Protostrator] *= priorities.protostrator_multiplier

  of ai_types.GameAct.Act2_RisingTensions:
    # Act 2: Rising Tensions - Consolidation & Military Buildup
    # Architecture priorities: Domestikos CRITICAL, Eparch/Logothete HIGH
    let priorities = globalRBAConfig.act_priorities.act2_rising_tensions
    result[AdvisorType.Domestikos] *= priorities.domestikos_multiplier
    result[AdvisorType.Eparch] *= priorities.eparch_multiplier
    result[AdvisorType.Logothete] *= priorities.logothete_multiplier
    result[AdvisorType.Drungarius] *= priorities.drungarius_multiplier
    result[AdvisorType.Protostrator] *= priorities.protostrator_multiplier
    # War-time boost (from [basileus] config for backwards compatibility)
    if isAtWar:
      result[AdvisorType.Logothete] *= globalRBAConfig.basileus.act2_war_research_multiplier
    else:
      result[AdvisorType.Logothete] *= globalRBAConfig.basileus.act2_hostile_research_multiplier

  of ai_types.GameAct.Act3_TotalWar:
    # Act 3: Total War - Conquest
    # Architecture priorities: Domestikos CRITICAL, Drungarius/Protostrator HIGH
    let priorities = globalRBAConfig.act_priorities.act3_total_war
    result[AdvisorType.Domestikos] *= priorities.domestikos_multiplier
    result[AdvisorType.Drungarius] *= priorities.drungarius_multiplier
    result[AdvisorType.Protostrator] *= priorities.protostrator_multiplier
    result[AdvisorType.Eparch] *= priorities.eparch_multiplier
    result[AdvisorType.Logothete] *= priorities.logothete_multiplier
    # War-time escalation (from [basileus] config)
    if isAtWar:
      result[AdvisorType.Domestikos] *= globalRBAConfig.basileus.act3_war_military_multiplier
      result[AdvisorType.Logothete] *= globalRBAConfig.basileus.act3_war_research_multiplier
      result[AdvisorType.Protostrator] *= globalRBAConfig.basileus.act3_war_diplomacy_multiplier
    else:
      result[AdvisorType.Logothete] *= globalRBAConfig.basileus.act3_peace_research_multiplier
      result[AdvisorType.Protostrator] *= globalRBAConfig.basileus.act3_peace_diplomacy_multiplier

  of ai_types.GameAct.Act4_Endgame:
    # Act 4: Endgame - Securing Victory
    # Architecture priorities: Domestikos CRITICAL, Eparch/Protostrator HIGH
    let priorities = globalRBAConfig.act_priorities.act4_endgame
    result[AdvisorType.Domestikos] *= priorities.domestikos_multiplier
    result[AdvisorType.Eparch] *= priorities.eparch_multiplier
    result[AdvisorType.Protostrator] *= priorities.protostrator_multiplier
    result[AdvisorType.Logothete] *= priorities.logothete_multiplier
    result[AdvisorType.Drungarius] *= priorities.drungarius_multiplier
    # War-time escalation (from [basileus] config)
    if isAtWar:
      result[AdvisorType.Domestikos] *= globalRBAConfig.basileus.act4_war_military_multiplier
      result[AdvisorType.Logothete] *= globalRBAConfig.basileus.act4_war_research_multiplier
    else:
      result[AdvisorType.Logothete] *= globalRBAConfig.basileus.act4_peace_research_multiplier

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
