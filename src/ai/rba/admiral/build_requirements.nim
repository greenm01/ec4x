## Build Requirements Module - Admiral Strategic Analysis
##
## Generates build requirements based on tactical gap analysis.
## Enables requirements-driven ship production instead of hardcoded thresholds.
##
## Key Features:
## - Defense gap detection with severity scoring
## - Reconnaissance gap analysis
## - Offensive readiness assessment
## - Priority-based requirement generation
## - Escalation for persistent gaps (adaptive AI)
##
## Integration: Called by Admiral module, consumed by build system

import std/[options, tables, sequtils, algorithm, strformat]
import ../../../common/system
import ../../../common/types/[core, units]
import ../../../engine/[gamestate, fog_of_war, logger]
import ../controller_types
import ../config
import ./fleet_analysis

# Import types from parent Admiral module
{.push used.}
from ../admiral import FleetAnalysis, FleetUtilization
{.pop.}

type
  RequirementPriority* {.pure.} = enum
    ## Priority levels for build requirements
    ## Drives budget allocation and fulfillment order
    Critical    # Immediate threat, homeworld defense (absolute priority)
    High        # Important colonies, active threats (high priority)
    Medium      # Standard gaps, preventive measures (normal priority)
    Low         # Nice-to-have, efficiency improvements (low priority)
    Deferred    # Future planning, low urgency (skip if budget limited)

  RequirementType* {.pure.} = enum
    ## Category of requirement (for analytics and explainability)
    DefenseGap          # Undefended/under-defended colony
    OffensivePrep       # Staging for offensive operations
    ReconnaissanceGap   # Insufficient intelligence coverage
    ExpansionSupport    # ETACs for colonization
    ThreatResponse      # Emergency fleet buildup

  BuildRequirement* = object
    ## Single build requirement from Admiral analysis
    ## Represents a specific tactical need with priority and cost
    requirementType*: RequirementType
    priority*: RequirementPriority
    shipClass*: Option[ShipClass]        # Recommended ship type
    quantity*: int                       # Ships needed
    buildObjective*: BuildObjective      # Which budget category to use
    targetSystem*: Option[SystemId]      # Deployment target (if specified)
    estimatedCost*: int                  # PP cost estimate
    reason*: string                      # Explainability/debug

  BuildRequirements* = object
    ## Complete set of requirements from Admiral analysis
    ## Passed to build system for execution
    requirements*: seq[BuildRequirement]
    totalEstimatedCost*: int
    criticalCount*: int
    highCount*: int
    generatedTurn*: int
    act*: GameAct

  DefenseGap* = object
    ## Detailed defense gap analysis for a single colony
    colonySystemId*: SystemId
    severity*: RequirementPriority
    currentDefenders*: int
    recommendedDefenders*: int
    nearestDefenderDistance*: int
    colonyPriority*: float               # Production-based priority
    estimatedThreat*: float              # 0.0-1.0
    deploymentUrgency*: int              # Turns until critical
    turnsUndefended*: int                # Escalation tracker (for adaptive AI)

  ColonyDefenseHistory* = object
    ## Tracks defense history for escalation logic
    systemId*: SystemId
    turnsUndefended*: int
    lastDefenderAssigned*: int           # Turn number

# =============================================================================
# Gap Severity and Escalation
# =============================================================================

proc escalateSeverity*(
  baseSeverity: RequirementPriority,
  turnsUndefended: int
): RequirementPriority =
  ## Escalate gap severity based on persistence
  ## Creates adaptive AI: Fresh analysis each turn, but urgency increases
  ## if problem persists (engaging gameplay - not predictable patterns)
  ##
  ## Escalation thresholds (configurable in rba.toml):
  ## - 3+ turns: Low → Medium
  ## - 5+ turns: Medium → High
  ## - 7+ turns: High → Critical

  result = baseSeverity

  let config = globalRBAConfig.admiral
  case baseSeverity
  of RequirementPriority.Low:
    if turnsUndefended >= config.escalation_low_to_medium_turns:
      result = RequirementPriority.Medium
      logDebug(LogCategory.lcAI,
               &"Escalated gap severity: Low → Medium (undefended {turnsUndefended} turns)")
  of RequirementPriority.Medium:
    if turnsUndefended >= config.escalation_medium_to_high_turns:
      result = RequirementPriority.High
      logDebug(LogCategory.lcAI,
               &"Escalated gap severity: Medium → High (undefended {turnsUndefended} turns)")
  of RequirementPriority.High:
    if turnsUndefended >= config.escalation_high_to_critical_turns:
      result = RequirementPriority.Critical
      logWarn(LogCategory.lcAI,
              &"Escalated gap severity: High → CRITICAL (undefended {turnsUndefended} turns)")
  else:
    discard  # Critical and Deferred don't escalate

# =============================================================================
# Placeholder Functions (Step 1: Types only, implementations in Step 2)
# =============================================================================

proc assessDefenseGaps*(
  filtered: FilteredGameState,
  analyses: seq[FleetAnalysis],
  defensiveAssignments: Table[FleetId, StandingOrder],
  controller: AIController
): seq[DefenseGap] =
  ## Identify defense gaps with severity scoring
  ## TODO: Implement in Step 2
  result = @[]

proc assessReconnaissanceGaps*(
  filtered: FilteredGameState,
  controller: AIController,
  currentAct: GameAct
): seq[DefenseGap] =
  ## Identify reconnaissance gaps (stale intel, unknown systems)
  ## TODO: Implement in Step 2
  result = @[]

proc assessOffensiveReadiness*(
  filtered: FilteredGameState,
  analyses: seq[FleetAnalysis],
  controller: AIController,
  currentAct: GameAct
): seq[DefenseGap] =
  ## Assess offensive capability and opportunities
  ## TODO: Implement in Step 2
  result = @[]

proc generateBuildRequirements*(
  filtered: FilteredGameState,
  analyses: seq[FleetAnalysis],
  defensiveAssignments: Table[FleetId, StandingOrder],
  controller: AIController,
  currentAct: GameAct
): BuildRequirements =
  ## Main entry point: Generate all build requirements from Admiral analysis
  ## TODO: Implement in Step 2
  result = BuildRequirements(
    requirements: @[],
    totalEstimatedCost: 0,
    criticalCount: 0,
    highCount: 0,
    generatedTurn: filtered.turn,
    act: currentAct
  )
