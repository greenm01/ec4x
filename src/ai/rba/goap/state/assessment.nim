## Threat and Opportunity Assessment
##
## Analyzes world state to identify strategic opportunities and threats.
## Used by GOAP planner to prioritize goals.

import std/[tables, options, algorithm, sequtils]
import ../core/types
import ../../../../common/types/[core, diplomacy]

# =============================================================================
# Threat Assessment
# =============================================================================

type
  ThreatLevel* {.pure.} = enum
    ## Threat urgency levels
    None = 0,
    Low = 1,
    Medium = 2,
    High = 3,
    Critical = 4

  ColonyThreat* = object
    ## Threat assessment for a specific colony
    systemId*: SystemId
    threatLevel*: ThreatLevel
    undefended*: bool
    vulnerable*: bool
    nearEnemyTerritory*: bool
    estimatedAttackStrength*: int

proc assessColonyThreat*(state: WorldStateSnapshot, systemId: SystemId): ColonyThreat =
  ## Assess threat level for a specific colony
  ##
  ## Factors:
  ## - Defense strength
  ## - Proximity to enemy colonies
  ## - Strategic value (production)

  result = ColonyThreat(
    systemId: systemId,
    threatLevel: ThreatLevel.None,
    undefended: systemId in state.undefendedColonies,
    vulnerable: systemId in state.vulnerableColonies,
    nearEnemyTerritory: false,  # TODO: Check proximity to enemy colonies
    estimatedAttackStrength: 0
  )

  # Undefended colonies are critical threat
  if result.undefended:
    result.threatLevel = ThreatLevel.Critical
  elif result.vulnerable:
    result.threatLevel = ThreatLevel.High
  else:
    result.threatLevel = ThreatLevel.Low

proc identifyThreatenedColonies*(state: WorldStateSnapshot): seq[ColonyThreat] =
  ## Identify all colonies under threat
  ##
  ## Returns sorted by threat level (highest first)

  result = @[]

  for systemId in state.ownedColonies:
    let threat = assessColonyThreat(state, systemId)
    if threat.threatLevel != ThreatLevel.None:
      result.add(threat)

  # Sort by threat level (descending)
  result.sort do (a, b: ColonyThreat) -> int:
    result = ord(b.threatLevel) - ord(a.threatLevel)

# =============================================================================
# Opportunity Assessment
# =============================================================================

type
  OpportunityType* {.pure.} = enum
    ## Types of strategic opportunities
    WeakEnemy,              ## Undefended/weak enemy colony
    TechAdvantage,          ## Tech gap we can exploit
    DiplomaticOpening,      ## Alliance/isolation opportunity
    ExpansionOpportunity,   ## Unclaimed high-value system
    EconomicGrowth          ## Infrastructure investment opportunity

  StrategicOpportunity* = object
    ## An identified strategic opportunity
    opportunityType*: OpportunityType
    priority*: float        ## 0.0-1.0, higher = more valuable
    target*: Option[SystemId]
    targetHouse*: Option[HouseId]
    estimatedCost*: int
    estimatedBenefit*: int
    description*: string

proc identifyInvasionOpportunities*(state: WorldStateSnapshot): seq[StrategicOpportunity] =
  ## Identify weak enemy colonies suitable for invasion
  ##
  ## Returns sorted by value (highest first)

  result = @[]

  for systemId in state.invasionOpportunities:
    # Phase 1: Simplified - all invasion opportunities are valid targets
    # TODO: Extract actual owner from knownEnemyColonies in Phase 2
    let opp = StrategicOpportunity(
        opportunityType: OpportunityType.WeakEnemy,
        priority: 0.7,  # High priority
        target: some(systemId),
        targetHouse: none(HouseId),  # Phase 1: owner unknown
        estimatedCost: 210,  # Transport + marines + escort
        estimatedBenefit: 100,  # Prestige + production
        description: "Invade weak colony at " & $systemId
      )
    result.add(opp)

  # Sort by priority (descending)
  result.sort do (a, b: StrategicOpportunity) -> int:
    result = cmp(b.priority, a.priority)

proc identifyTechOpportunities*(state: WorldStateSnapshot): seq[StrategicOpportunity] =
  ## Identify tech research opportunities
  ##
  ## Prioritizes critical tech gaps

  result = @[]

  for techField in state.criticalTechGaps:
    let opp = StrategicOpportunity(
      opportunityType: OpportunityType.TechAdvantage,
      priority: 0.6,
      estimatedCost: 50,  # RP cost estimate
      estimatedBenefit: 200,  # Unlocks capabilities
      description: "Close tech gap in " & $techField
    )
    result.add(opp)

proc identifyDiplomaticOpportunities*(state: WorldStateSnapshot): seq[StrategicOpportunity] =
  ## Identify diplomatic opportunities
  ##
  ## - Potential alliances
  ## - Houses to isolate

  result = @[]

  # Check for neutral houses (potential allies)
  for (houseId, dipState) in state.diplomaticRelations.pairs:
    if dipState == DiplomaticState.Neutral:
      let opp = StrategicOpportunity(
        opportunityType: OpportunityType.DiplomaticOpening,
        priority: 0.5,
        targetHouse: some(houseId),
        estimatedCost: 0,  # Free action
        estimatedBenefit: 50,  # Prestige + security
        description: "Form alliance with " & $houseId
      )
      result.add(opp)

proc identifyAllOpportunities*(state: WorldStateSnapshot): seq[StrategicOpportunity] =
  ## Identify all strategic opportunities
  ##
  ## Combines all opportunity types and sorts by priority

  result = @[]
  result.add(identifyInvasionOpportunities(state))
  result.add(identifyTechOpportunities(state))
  result.add(identifyDiplomaticOpportunities(state))

  # Sort by priority (descending)
  result.sort do (a, b: StrategicOpportunity) -> int:
    result = cmp(b.priority, a.priority)

# =============================================================================
# Strategic Situation Assessment
# =============================================================================

type
  StrategicSituation* {.pure.} = enum
    ## Overall strategic posture
    Dominating,      ## Strong position, can be aggressive
    Competitive,     ## Even match, balanced approach
    Defensive,       ## Under pressure, defensive priorities
    Critical         ## Survival mode, emergency measures

proc assessStrategicSituation*(state: WorldStateSnapshot): StrategicSituation =
  ## Assess overall strategic situation
  ##
  ## Based on:
  ## - Economic strength (treasury, production)
  ## - Military strength (fleet power)
  ## - Territory control (colonies)
  ## - Diplomatic position

  var score = 0.0

  # Economic health (30%)
  if state.netIncome > 0:
    score += 0.3
  elif state.treasury > state.maintenanceCost * 3:
    score += 0.2  # Can survive 3 turns
  elif state.treasury > 0:
    score += 0.1

  # Military strength (30%)
  if state.totalFleetStrength > 500:
    score += 0.3  # Strong fleet
  elif state.totalFleetStrength > 200:
    score += 0.2  # Adequate fleet
  elif state.totalFleetStrength > 50:
    score += 0.1  # Weak fleet

  # Territory control (20%)
  if state.ownedColonies.len >= 5:
    score += 0.2
  elif state.ownedColonies.len >= 3:
    score += 0.1

  # Defensive posture (20%)
  let defenseCoverage = 1.0 - (state.undefendedColonies.len.float / max(1.0, state.ownedColonies.len.float))
  score += defenseCoverage * 0.2

  # Classify situation
  if score >= 0.7:
    return StrategicSituation.Dominating
  elif score >= 0.5:
    return StrategicSituation.Competitive
  elif score >= 0.3:
    return StrategicSituation.Defensive
  else:
    return StrategicSituation.Critical
