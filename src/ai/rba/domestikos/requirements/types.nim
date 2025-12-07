## Domestikos Requirements Types Module
##
## Type definitions for build requirement generation and defense gap analysis.
## Following DoD (Data-Oriented Design): Pure data structures, no behavior.
##
## Extracted from build_requirements.nim (lines 129-147)

import ../../../../common/types/core  # For SystemId
import ../../controller_types  # For RequirementPriority

type
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
