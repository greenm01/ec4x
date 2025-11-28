## Fighter Squadron Capacity Enforcement System
##
## Implements assets.md:2.4.1 - fighter squadron capacity limits and violation enforcement.
##
## Capacity Formula: Max FS = floor(PU / 100) × FD Tech Multiplier
## Infrastructure Requirement: ceil(Current FS / 5) operational starbases
##
## Violation Types:
## - Infrastructure: Not enough operational starbases for current fighter count
## - Population: Too many fighters for current population (PU)
##
## Grace Period: 2 turns to resolve violation
## Enforcement: Disband oldest squadrons first after grace period expires
##
## Data-oriented design: Calculate violations (pure), apply enforcement (explicit mutations)

import std/[tables, sequtils, algorithm, math]
import ../gamestate
import ../state_helpers
import ../iterators
import ../../common/types/core
import ../../common/logger

type
  ViolationType* {.pure.} = enum
    ## Type of capacity violation
    None,            # No violation
    Infrastructure,  # Not enough operational starbases
    Population       # Too many fighters for population

  CapacityStatus* = object
    ## Capacity analysis for a colony
    colonyId*: SystemId
    currentFighters*: int
    maxCapacity*: int
    requiredStarbases*: int
    operationalStarbases*: int
    violationType*: ViolationType
    excessFighters*: int

  EnforcementAction* = object
    ## Action to take for capacity enforcement
    colonyId*: SystemId
    fightersToDisband*: seq[string]  # Fighter squadron IDs
    violationType*: ViolationType
    gracePeriodExpired*: bool

proc getFighterDoctrineMultiplier(fdLevel: int): float =
  ## Get Fighter Doctrine tech multiplier per assets.md:2.4.1
  case fdLevel
  of 1: return 1.0   # FD I (base)
  of 2: return 1.5   # FD II
  of 3: return 2.0   # FD III
  else: return 1.0   # Default to base

proc getOperationalStarbaseCount(colony: Colony): int =
  ## Count operational (non-crippled) starbases at colony
  result = 0
  for starbase in colony.starbases:
    if not starbase.isCrippled:
      result += 1

proc calculateMaxFighterCapacity*(populationUnits: int, fdLevel: int): int =
  ## Pure calculation of maximum fighter squadron capacity
  ## Formula: Max FS = floor(PU / 100) × FD Tech Multiplier
  let fdMult = getFighterDoctrineMultiplier(fdLevel)
  return int(floor(float(populationUnits) / 100.0) * fdMult)

proc calculateRequiredStarbases*(fighterCount: int): int =
  ## Pure calculation of required operational starbases
  ## Formula: ceil(Current FS / 5) per assets.md:2.4.1
  if fighterCount <= 0:
    return 0
  return int(ceil(float(fighterCount) / 5.0))

proc analyzeCapacity*(state: GameState, colony: Colony, houseId: HouseId): CapacityStatus =
  ## Pure function - analyze colony's fighter capacity status
  ## Returns capacity analysis without mutating state

  result = CapacityStatus(
    colonyId: colony.systemId,
    currentFighters: colony.fighterSquadrons.len,
    violationType: ViolationType.None,
    excessFighters: 0
  )

  # Get Fighter Doctrine level from house tech tree
  let fdLevel = if houseId in state.houses:
                  state.houses[houseId].techTree.levels.fighterDoctrine
                else:
                  1  # Default to base level

  # Calculate maximum capacity
  result.maxCapacity = calculateMaxFighterCapacity(colony.populationUnits, fdLevel)

  # Calculate infrastructure requirements
  result.requiredStarbases = calculateRequiredStarbases(result.currentFighters)
  result.operationalStarbases = getOperationalStarbaseCount(colony)

  # Check for violations
  # Priority: Infrastructure violation first (more critical)
  if result.operationalStarbases < result.requiredStarbases:
    result.violationType = ViolationType.Infrastructure
    # Excess fighters = current - (operational starbases × 5)
    result.excessFighters = result.currentFighters - (result.operationalStarbases * 5)
  elif result.currentFighters > result.maxCapacity:
    result.violationType = ViolationType.Population
    result.excessFighters = result.currentFighters - result.maxCapacity

proc checkViolations*(state: GameState): seq[CapacityStatus] =
  ## Batch check all colonies for fighter capacity violations
  ## Pure function - returns analysis without mutations
  result = @[]

  for (systemId, colony) in state.allColoniesWithId():
    let status = analyzeCapacity(state, colony, colony.owner)
    if status.violationType != ViolationType.None:
      result.add(status)

proc updateViolationTracking*(state: var GameState, status: CapacityStatus) =
  ## Update violation tracking for a colony
  ## Explicit mutation - applies tracking state changes

  state.withColony(status.colonyId):
    if status.violationType != ViolationType.None:
      # Violation exists
      if not colony.capacityViolation.active:
        # New violation - start grace period
        colony.capacityViolation.active = true
        colony.capacityViolation.violationType = case status.violationType
          of ViolationType.Infrastructure: "infrastructure"
          of ViolationType.Population: "population"
          else: ""
        colony.capacityViolation.turnsRemaining = 2  # 2-turn grace period
        colony.capacityViolation.violationTurn = state.turn

        logWarn("Military", "Fighter capacity violation - new",
                "colony=", $status.colonyId, " type=", status.violationType,
                " excess=", $status.excessFighters, " gracePeriod=2turns")
      else:
        # Existing violation - decrement grace period
        colony.capacityViolation.turnsRemaining -= 1
        logWarn("Military", "Fighter capacity violation - continuing",
                "colony=", $status.colonyId, " type=", status.violationType,
                " graceRemaining=", $colony.capacityViolation.turnsRemaining)
    else:
      # No violation - clear tracking
      if colony.capacityViolation.active:
        logDebug("Military", "Fighter capacity violation resolved",
                "colony=", $status.colonyId)
        colony.capacityViolation.active = false

proc planEnforcement*(state: GameState, status: CapacityStatus): EnforcementAction =
  ## Plan enforcement actions for expired violations
  ## Pure function - returns enforcement plan without mutations

  result = EnforcementAction(
    colonyId: status.colonyId,
    violationType: status.violationType,
    gracePeriodExpired: false,
    fightersToDisband: @[]
  )

  # Check if grace period has expired
  if status.colonyId in state.colonies:
    let colony = state.colonies[status.colonyId]
    if colony.capacityViolation.active and colony.capacityViolation.turnsRemaining <= 0:
      result.gracePeriodExpired = true

      # Disband oldest squadrons first (per spec)
      # Sort by commissioned turn (oldest first)
      var sortedFighters = colony.fighterSquadrons
      sortedFighters.sort do (a, b: FighterSquadron) -> int:
        cmp(a.commissionedTurn, b.commissionedTurn)

      # Select excess fighters for disbanding
      let toDisbandCount = min(status.excessFighters, sortedFighters.len)
      for i in 0 ..< toDisbandCount:
        result.fightersToDisband.add(sortedFighters[i].id)

proc applyEnforcement*(state: var GameState, action: EnforcementAction) =
  ## Apply enforcement actions
  ## Explicit mutation - disbands fighters and clears violation

  if not action.gracePeriodExpired or action.fightersToDisband.len == 0:
    return

  state.withColony(action.colonyId):
    # Disband fighters (oldest first)
    for fighterId in action.fightersToDisband:
      let fid = fighterId  # Copy to avoid lent capture issue
      colony.fighterSquadrons.keepIf(proc(f: FighterSquadron): bool = f.id != fid)

      logEconomy("Fighter squadron disbanded - capacity violation",
                "squadronId=", fighterId, " salvage=none")

    # Clear violation tracking
    colony.capacityViolation.active = false

    logEconomy("Capacity enforcement complete",
              "colony=", $action.colonyId,
              " disbanded=", $action.fightersToDisband.len)

proc processCapacityEnforcement*(state: var GameState) =
  ## Main entry point - batch process all capacity violations
  ## Called during Maintenance phase
  ## Data-oriented: analyze all → plan enforcement → apply enforcement

  logDebug("Military", "Checking fighter capacity")

  # Step 1: Check all colonies for violations (pure)
  let violations = checkViolations(state)

  if violations.len == 0:
    logDebug("Military", "All colonies within fighter capacity limits")
    return

  logDebug("Military", "Capacity violations found", "count=", $violations.len)

  # Step 2: Update violation tracking (mutations)
  for status in violations:
    updateViolationTracking(state, status)

  # Step 3: Plan enforcement for expired violations (pure)
  var enforcementActions: seq[EnforcementAction] = @[]
  for status in violations:
    let action = planEnforcement(state, status)
    if action.gracePeriodExpired:
      enforcementActions.add(action)

  # Step 4: Apply enforcement (mutations)
  if enforcementActions.len > 0:
    logEconomy("Enforcing expired capacity violations",
              "count=", $enforcementActions.len)
    for action in enforcementActions:
      applyEnforcement(state, action)
  else:
    logDebug("Military", "No violations requiring immediate enforcement")

proc canCommissionFighter*(state: GameState, colony: Colony): bool =
  ## Check if colony can commission a new fighter squadron
  ## Returns false if colony is in capacity violation
  ## Pure function - no mutations

  if colony.capacityViolation.active:
    return false

  let status = analyzeCapacity(state, colony, colony.owner)
  return status.violationType == ViolationType.None and
         status.currentFighters < status.maxCapacity

## Design Notes:
##
## **Data-Oriented Pattern:**
## 1. analyzeCapacity() - Pure calculation of capacity status
## 2. checkViolations() - Batch analyze all colonies (pure)
## 3. updateViolationTracking() - Explicit mutations for tracking
## 4. planEnforcement() - Pure function returns enforcement plan
## 5. applyEnforcement() - Explicit mutations apply the plan
## 6. processCapacityEnforcement() - Main batch processor
##
## **Benefits:**
## - Testable: All calculations are pure functions
## - Explicit: All state changes visible
## - Batch-friendly: Process all colonies together
## - Loggable: Can inspect plans before application
##
## **Spec Compliance:**
## - assets.md:2.4.1: Complete capacity system
## - Formula: Max FS = floor(PU / 100) × FD Tech Multiplier
## - Infrastructure: ceil(Current FS / 5) operational starbases
## - 2-turn grace period for violations
## - Disband oldest squadrons first
## - No salvage value for forced disbanding
##
## **Integration Points:**
## - Call processCapacityEnforcement() in Maintenance phase
## - Call canCommissionFighter() before commissioning new fighters
## - Enforcement happens AFTER population/infrastructure changes
