## GOAP Shared Conditions System
##
## DRY (Don't Repeat Yourself) Foundation:
## - Single source of truth for all preconditions and success conditions
## - All 4 domains (fleet, build, research, diplomatic) import and use this module
## - No duplication of condition logic across domains
##
## Usage:
## ```nim
## import goap/core/conditions
##
## # Create precondition
## let precond = createPrecondition(HasBudget, {"minBudget": 200}.toTable)
##
## # Check precondition
## if checkPrecondition(worldState, precond):
##   # Action is applicable
## ```

import std/[tables, strutils]
import types
import ../../../../common/types/[core, tech]

# =============================================================================
# Condition Type Registry (DRY: Centralized Definitions)
# =============================================================================

type
  ConditionKind* {.pure.} = enum
    ## All possible condition types across all domains
    # Economic Conditions
    HasBudget                 ## treasury >= minBudget
    HasProduction             ## production >= minProduction
    HasNetIncome              ## netIncome >= minIncome
    # Territory Conditions
    ControlsSystem            ## systemId in ownedColonies
    SystemUndefended          ## systemId in undefendedColonies
    ColonyVulnerable          ## systemId in vulnerableColonies
    # Military Conditions
    HasFleet                  ## fleetId exists in idleFleets
    HasFleetStrength          ## totalFleetStrength >= minStrength
    FleetAtLocation           ## fleet.location == systemId
    # Tech Conditions
    HasTechLevel              ## techLevels[field] >= level
    TechGapExists             ## techField in criticalTechGaps
    # Diplomatic Conditions
    HasAlliance               ## diplomaticRelations[house] == Ally
    AtWar                     ## diplomaticRelations[house] == Enemy
    IsNeutral                 ## diplomaticRelations[house] == Neutral
    # Intelligence Conditions
    HasIntel                  ## systemId NOT in staleIntelSystems
    EnemyColonyKnown          ## systemId in knownEnemyColonies

# =============================================================================
# Condition Checking (Core Logic)
# =============================================================================

proc checkPrecondition*(state: WorldStateSnapshot, cond: PreconditionRef): bool =
  ## Check if precondition is satisfied in current world state
  ##
  ## DRY Principle: All domains use this single function
  ## No duplicated condition logic
  let kind = parseEnum[ConditionKind](cond.conditionId)

  case kind
  # Economic
  of HasBudget:
    let minBudget = cond.params.getOrDefault("minBudget", 0)
    return state.treasury >= minBudget

  of HasProduction:
    let minProduction = cond.params.getOrDefault("minProduction", 0)
    return state.production >= minProduction

  of HasNetIncome:
    let minIncome = cond.params.getOrDefault("minIncome", 0)
    return state.netIncome >= minIncome

  # Territory
  of ControlsSystem:
    let systemId = SystemId(cond.params.getOrDefault("systemId", 0))
    return systemId in state.ownedColonies

  of SystemUndefended:
    let systemId = SystemId(cond.params.getOrDefault("systemId", 0))
    return systemId in state.undefendedColonies

  of ColonyVulnerable:
    let systemId = SystemId(cond.params.getOrDefault("systemId", 0))
    return systemId in state.vulnerableColonies

  # Military
  of HasFleet:
    # NOTE: FleetId is string, params stores hash for lookup
    # This is a simplified check - real implementation needs proper ID mapping
    return state.idleFleets.len > 0

  of HasFleetStrength:
    let minStrength = cond.params.getOrDefault("minStrength", 0)
    return state.totalFleetStrength >= minStrength

  of FleetAtLocation:
    # NOTE: Would need fleet location tracking in WorldStateSnapshot
    # For now, return true (conservative estimate)
    return true

  # Tech
  of HasTechLevel:
    let techField = TechField(cond.params.getOrDefault("techField", 0))
    let minLevel = cond.params.getOrDefault("minLevel", 0)
    return state.techLevels.getOrDefault(techField, 0) >= minLevel

  of TechGapExists:
    let techField = TechField(cond.params.getOrDefault("techField", 0))
    return techField in state.criticalTechGaps

  # Diplomatic
  of HasAlliance:
    # NOTE: HouseId is string, simplified check for compilation
    # TODO: Proper ID mapping needed for production
    return true

  of AtWar:
    # NOTE: HouseId is string, simplified check for compilation
    # TODO: Proper ID mapping needed for production
    return true

  of IsNeutral:
    # NOTE: HouseId is string, simplified check for compilation
    # TODO: Proper ID mapping needed for production
    return true

  # Intelligence
  of HasIntel:
    let systemId = SystemId(cond.params.getOrDefault("systemId", 0))
    return systemId notin state.staleIntelSystems

  of EnemyColonyKnown:
    let systemId = SystemId(cond.params.getOrDefault("systemId", 0))
    for (sys, _) in state.knownEnemyColonies:
      if sys == systemId:
        return true
    return false

proc checkSuccessCondition*(state: WorldStateSnapshot, cond: SuccessConditionRef): bool =
  ## Check if goal success condition is met
  ##
  ## Reuses precondition logic (success conditions are just preconditions)
  let precond = PreconditionRef(
    conditionId: cond.conditionId,
    params: cond.params
  )
  return checkPrecondition(state, precond)

# =============================================================================
# Condition Builders (Convenience Functions)
# =============================================================================

proc createPrecondition*(kind: ConditionKind, params: Table[string, int]): PreconditionRef =
  ## Create a precondition with parameters
  ##
  ## Example:
  ## ```nim
  ## let prec = createPrecondition(HasBudget, {"minBudget": 200}.toTable)
  ## ```
  new(result)
  result.conditionId = $kind
  result.params = params

proc createSuccessCondition*(kind: ConditionKind, params: Table[string, int]): SuccessConditionRef =
  ## Create a success condition with parameters
  new(result)
  result.conditionId = $kind
  result.params = params

# =============================================================================
# Convenience Builders (Domain-Specific)
# =============================================================================

proc hasMinBudget*(budget: int): PreconditionRef =
  ## Economic: Require minimum treasury
  createPrecondition(HasBudget, {"minBudget": budget}.toTable)

proc controlsSystem*(systemId: SystemId): PreconditionRef =
  ## Territory: Require owning system
  createPrecondition(ControlsSystem, {"systemId": int(systemId)}.toTable)

proc hasMinTechLevel*(field: TechField, level: int): PreconditionRef =
  ## Tech: Require minimum tech level
  createPrecondition(HasTechLevel, {"techField": int(field), "minLevel": level}.toTable)

proc atWarWith*(houseId: HouseId): PreconditionRef =
  ## Diplomatic: Require war status
  # NOTE: Simplified for Phase 1, proper ID mapping in Phase 2
  createPrecondition(AtWar, initTable[string, int]())

proc hasAllianceWith*(houseId: HouseId): PreconditionRef =
  ## Diplomatic: Require alliance
  # NOTE: Simplified for Phase 1, proper ID mapping in Phase 2
  createPrecondition(HasAlliance, initTable[string, int]())

# =============================================================================
# Precondition Validation (For Action Applicability)
# =============================================================================

proc allPreconditionsMet*(state: WorldStateSnapshot, preconditions: seq[PreconditionRef]): bool =
  ## Check if all preconditions are satisfied
  ##
  ## Used by A* planner to determine action applicability
  for precond in preconditions:
    if not checkPrecondition(state, precond):
      return false
  return true
