## Fighter Squadron Capacity Enforcement System
##
## Implements assets.md:2.4.1 - fighter squadron capacity limits and violation enforcement.
##
## Capacity Formula: Max FS = floor(IU / 100) × FD Multiplier
##
## Where Fighter Doctrine (FD) Tech Level Multiplier is:
## - FD I (base): 1.0x
## - FD II: 1.5x
## - FD III: 2.0x
##
## **IMPORTANT:** Capacity is based on Industrial Units (IU), NOT Population Units (PU)
## Rationale: With populations in millions, pilot availability isn't the constraint;
## industrial capacity (factories, supply chains, manufacturing) limits fighter production.
##
## **NO infrastructure required:** Per assets.md:2.4.1 and economy.md:3.10,
## fighters are built planet-side via distributed manufacturing. No starport, shipyard,
## or starbase infrastructure is required for colony-based fighters.
##
## Grace Period: 2 turns to resolve violation
## Enforcement: Disband oldest squadrons first after grace period expires
##
## Data-oriented design: Calculate violations (pure), apply enforcement (explicit mutations)

import std/[sequtils, algorithm, math, tables, strutils]
import ./types
import ../types as econ_types  # For ConstructionType
import ../../gamestate
import ../../squadron  # For Squadron type
import ../../state_helpers
import ../../iterators
import ../../../common/types/core
import ../../../common/logger
import ../../resolution/types as resolution_types  # For GameEvent
import ../../resolution/event_factory/fleet_ops  # For squadronDisbanded

export types.CapacityViolation, types.EnforcementAction, types.ViolationSeverity

proc getFighterDoctrineMultiplier(fdLevel: int): float =
  ## Get Fighter Doctrine tech multiplier per assets.md:2.4.1
  # TODO Load these multiplier from toml config files
  case fdLevel
  of 1: return 1.0   # FD I (base)
  of 2: return 1.5   # FD II
  of 3: return 2.0   # FD III
  else: return 1.0   # Default to base

proc calculateMaxFighterCapacity*(industrialUnits: int, fdLevel: int): int =
  ## Pure calculation of maximum fighter squadron capacity
  ## Formula: Max FS = floor(IU / 100) × FD Tech Multiplier
  ## Per assets.md:2.4.1 and economy.md:3.10
  # TODO load fighter_capacity_iu_divisor from toml config. no hard coded variables
  let fdMult = getFighterDoctrineMultiplier(fdLevel)
  return int(floor(float(industrialUnits) / 100.0) * fdMult)

proc analyzeCapacity*(state: GameState, colony: Colony, houseId: core.HouseId): types.CapacityViolation =
  ## Pure function - analyze colony's fighter capacity status
  ## Returns capacity analysis without mutating state

  # Get Fighter Doctrine level from house tech tree
  let fdLevel = if houseId in state.houses:
                  state.houses[houseId].techTree.levels.fighterDoctrine
                else:
                  1  # Default to base level

  var current = colony.fighterSquadrons.len

  # Account for fighters already under construction at this colony
  let underConstruction = colony.constructionQueue.filterIt(
    it.projectType == ConstructionType.Ship and it.itemId == "Fighter"
  ).len

  current += underConstruction

  let maximum = calculateMaxFighterCapacity(colony.industrial.units, fdLevel)
  let excess = max(0, current - maximum)

  # Determine severity
  let severity = if excess == 0:
                   ViolationSeverity.None
                 elif colony.capacityViolation.active:
                   if colony.capacityViolation.turnsRemaining <= 0:
                     ViolationSeverity.Critical
                   else:
                     ViolationSeverity.Violation
                 else:
                   ViolationSeverity.Violation  # New violation

  result = types.CapacityViolation(
    capacityType: CapacityType.FighterSquadron,
    entityId: $colony.systemId,
    current: current,
    maximum: maximum,
    excess: excess,
    severity: severity,
    graceTurnsRemaining: if colony.capacityViolation.active: colony.capacityViolation.turnsRemaining else: 2,
    violationTurn: if colony.capacityViolation.active: colony.capacityViolation.violationTurn else: state.turn
  )

proc checkViolations*(state: GameState): seq[types.CapacityViolation] =
  ## Batch check all colonies for fighter capacity violations
  ## Pure function - returns analysis without mutations
  result = @[]

  for (systemId, colony) in state.allColoniesWithId():
    let status = analyzeCapacity(state, colony, colony.owner)
    if status.severity != ViolationSeverity.None:
      result.add(status)

proc updateViolationTracking*(state: var GameState, violation: types.CapacityViolation) =
  ## Update violation tracking for a colony
  ## Explicit mutation - applies tracking state changes

  let colonyId = SystemId(parseInt(violation.entityId))
  state.withColony(colonyId):
    if violation.severity != ViolationSeverity.None:
      # Violation exists
      if not colony.capacityViolation.active:
        # New violation - start grace period
        colony.capacityViolation.active = true
        colony.capacityViolation.violationType = "industrial"
        colony.capacityViolation.turnsRemaining = 2  # 2-turn grace period
        colony.capacityViolation.violationTurn = state.turn

        logWarn("Military", "Fighter capacity violation - new",
                "colony=", $colonyId, " type=industrial",
                " excess=", $violation.excess, " gracePeriod=2turns",
                " currentIU=", $colony.industrial.units)
      else:
        # Existing violation - decrement grace period
        colony.capacityViolation.turnsRemaining -= 1
        logWarn("Military", "Fighter capacity violation - continuing",
                "colony=", $colonyId, " type=industrial",
                " graceRemaining=", $colony.capacityViolation.turnsRemaining)
    else:
      # No violation - clear tracking
      if colony.capacityViolation.active:
        logDebug("Military", "Fighter capacity violation resolved",
                "colony=", $colonyId)
        colony.capacityViolation.active = false

proc planEnforcement*(state: GameState, violation: types.CapacityViolation): types.EnforcementAction =
  ## Plan enforcement actions for expired violations
  ## Pure function - returns enforcement plan without mutations

  result = types.EnforcementAction(
    capacityType: CapacityType.FighterSquadron,
    entityId: violation.entityId,
    actionType: "",
    affectedUnits: @[],
    description: ""
  )

  # Check if enforcement needed
  if violation.severity != ViolationSeverity.Critical:
    return

  let colonyId = SystemId(parseInt(violation.entityId))
  if colonyId notin state.colonies:
    return

  let colony = state.colonies[colonyId]

  # Disband oldest squadrons first (per spec)
  # Sort by squadron ID (IDs contain encoded turn: systemId-FS-[turn*100+index])
  var sortedFighters = colony.fighterSquadrons
  sortedFighters.sort do (a, b: Squadron) -> int:
    cmp(a.id, b.id)  # Lexicographic sort by ID (encodes commissioning order)

  # Select excess fighters for disbanding
  let toDisbandCount = min(violation.excess, sortedFighters.len)
  result.actionType = "disband"
  for i in 0 ..< toDisbandCount:
    result.affectedUnits.add(sortedFighters[i].id)

  result.description = $toDisbandCount & " fighter squadron(s) auto-disbanded at colony-" &
                      violation.entityId & " (capacity violation)"

proc applyEnforcement*(state: var GameState, action: types.EnforcementAction,
                       events: var seq[resolution_types.GameEvent]) =
  ## Apply enforcement actions
  ## Explicit mutation - disbands fighters and clears violation
  ## Emits SquadronDisbanded events for tracking

  if action.actionType != "disband" or action.affectedUnits.len == 0:
    return

  let colonyId = SystemId(parseInt(action.entityId))
  state.withColony(colonyId):
    # Disband fighters (oldest first)
    for fighterId in action.affectedUnits:
      # Find the fighter squadron before removing it (for event metadata)
      let fighterOpt = colony.fighterSquadrons.filterIt(it.id == fighterId)
      if fighterOpt.len > 0:
        let fighter = fighterOpt[0]

        # Emit SquadronDisbanded event (fighters use ShipClass.Fighter)
        events.add(fleet_ops.squadronDisbanded(
          houseId = colony.owner,
          squadronId = fighterId,
          shipClass = ShipClass.Fighter,  # Fighter squadron
          reason = "Fighter squadron capacity exceeded (IU loss)",
          systemId = colonyId
        ))

      let fid = fighterId  # Copy to avoid lent capture issue
      colony.fighterSquadrons.keepIf(proc(f: Squadron): bool = f.id != fid)

      logEconomy("Fighter squadron disbanded - capacity violation",
                "squadronId=", fighterId, " salvage=none")

    # Clear violation tracking
    colony.capacityViolation.active = false

    logEconomy("Capacity enforcement complete",
              "colony=", $colonyId,
              " disbanded=", $action.affectedUnits.len)

proc processCapacityEnforcement*(state: var GameState,
                                events: var seq[resolution_types.GameEvent]): seq[types.EnforcementAction] =
  ## Main entry point - batch process all capacity violations
  ## Called during Maintenance phase
  ## Data-oriented: analyze all → plan enforcement → apply enforcement
  ## Returns: List of enforcement actions that were actually applied

  result = @[]

  logDebug("Military", "Checking fighter capacity")

  # Step 1: Check all colonies for violations (pure)
  let violations = checkViolations(state)

  if violations.len == 0:
    logDebug("Military", "All colonies within fighter capacity limits")
    return

  logDebug("Military", "Capacity violations found", "count=", $violations.len)

  # Step 2: Update violation tracking (mutations)
  for violation in violations:
    updateViolationTracking(state, violation)

  # Step 3: Plan enforcement for expired violations (pure)
  var enforcementActions: seq[types.EnforcementAction] = @[]
  for violation in violations:
    let action = planEnforcement(state, violation)
    if action.actionType == "disband" and action.affectedUnits.len > 0:
      enforcementActions.add(action)

  # Step 4: Apply enforcement (mutations)
  if enforcementActions.len > 0:
    logEconomy("Enforcing expired capacity violations",
              "count=", $enforcementActions.len)
    for action in enforcementActions:
      applyEnforcement(state, action, events)
      result.add(action)  # Track which actions were applied
  else:
    logDebug("Military", "No violations requiring immediate enforcement")

proc canCommissionFighter*(state: GameState, colony: Colony): bool =
  ## Check if colony can commission a new fighter squadron
  ## Returns false if colony is in capacity violation
  ## Pure function - no mutations

  if colony.capacityViolation.active:
    return false

  let violation = analyzeCapacity(state, colony, colony.owner)
  return violation.severity == ViolationSeverity.None and
         violation.current < violation.maximum

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
## - economy.md:3.10: Fighter squadron economics
## - Formula: Max FS = floor(IU / 100) × FD Tech Multiplier
## - NO infrastructure requirements (no starbases, shipyards, spaceports)
## - 2-turn grace period for violations
## - Disband oldest squadrons first
## - No salvage value for forced disbanding
##
## **Integration Points:**
## - Call processCapacityEnforcement() in Maintenance phase
## - Call canCommissionFighter() before commissioning new fighters
## - Enforcement happens AFTER industrial capacity changes
