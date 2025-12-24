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

import std/[sequtils, algorithm, math, tables, strutils, options]
import ../../types/[
  capacity, core, game_state, squadron, ship, production, event, colony, house
]
import ../../state/[entity_manager, game_state as gs_helpers, iterators]
import ../../entities/squadron_ops
import ../../event_factory/fleet_ops
import ../../config/[military_config, tech_config]
import ../../../common/logger

export capacity.CapacityViolation, capacity.EnforcementAction,
       capacity.ViolationSeverity

proc getFighterDoctrineMultiplier(fdLevel: int): float =
  ## Get Fighter Doctrine tech multiplier per assets.md:2.4.1
  ## Reads from globalTechConfig.fighter_doctrine
  let cfg = globalTechConfig.fighter_doctrine
  case fdLevel
  of 1: return cfg.level_1_capacity_multiplier.float
  of 2: return cfg.level_2_capacity_multiplier.float
  of 3: return cfg.level_3_capacity_multiplier.float
  else: return cfg.level_1_capacity_multiplier.float  # Default to base

proc calculateMaxFighterCapacity*(industrialUnits: int, fdLevel: int): int =
  ## Pure calculation of maximum fighter squadron capacity
  ## Formula: Max FS = floor(IU / divisor) × FD Tech Multiplier
  ## Per assets.md:2.4.1 and economy.md:3.10
  ## Reads divisor from globalMilitaryConfig.fighter_mechanics
  let fdMult = getFighterDoctrineMultiplier(fdLevel)
  let divisor = globalMilitaryConfig.fighter_mechanics.fighter_capacity_iu_divisor.float
  return int(floor(float(industrialUnits) / divisor) * fdMult)

proc analyzeCapacity*(state: GameState, colony: Colony, houseId: HouseId): capacity.CapacityViolation =
  ## Pure function - analyze colony's fighter capacity status
  ## Returns capacity analysis without mutating state

  # Get Fighter Doctrine level from house tech tree
  let houseOpt = gs_helpers.getHouse(state, houseId)
  let fdLevel = if houseOpt.isSome:
                  houseOpt.get().techTree.levels.fighterDoctrine
                else:
                  1  # Default to base level

  # Count current fighters (only those actually commissioned, referenced by colony)
  var current = colony.fighterSquadronIds.len

  # Account for fighters already under construction at this colony
  var underConstruction = 0
  for projectId in colony.constructionQueue:
    let projectOpt = gs_helpers.getConstructionProject(state, projectId)
    if projectOpt.isSome:
      let project = projectOpt.get()
      if project.projectType == BuildType.Ship and project.itemId == "Fighter":
        underConstruction += 1

  # Check underConstruction field (single active project)
  if colony.underConstruction.isSome:
    let projectId = colony.underConstruction.get()
    let projectOpt = gs_helpers.getConstructionProject(state, projectId)
    if projectOpt.isSome:
      let project = projectOpt.get()
      if project.projectType == BuildType.Ship and project.itemId == "Fighter":
        underConstruction += 1

  current += underConstruction

  let maximum = calculateMaxFighterCapacity(int(colony.industrial.units), fdLevel)
  let excess = max(0, current - maximum)

  # Determine severity based on existing violation tracking
  # Use colony.capacityViolation for grace period tracking
  let severity = if excess == 0:
                   capacity.ViolationSeverity.None
                 elif colony.capacityViolation.severity != capacity.ViolationSeverity.None:
                   # Existing violation - check grace period
                   if colony.capacityViolation.graceTurnsRemaining <= 0:
                     capacity.ViolationSeverity.Critical
                   else:
                     capacity.ViolationSeverity.Violation
                 else:
                   capacity.ViolationSeverity.Violation  # New violation

  result = capacity.CapacityViolation(
    capacityType: capacity.CapacityType.FighterSquadron,
    entity: capacity.EntityIdUnion(kind: capacity.CapacityType.FighterSquadron, colonyId: colony.id),
    current: int32(current),
    maximum: int32(maximum),
    excess: int32(excess),
    severity: severity,
    graceTurnsRemaining: if colony.capacityViolation.severity != capacity.ViolationSeverity.None:
                           colony.capacityViolation.graceTurnsRemaining
                         else:
                           2'i32,
    violationTurn: if colony.capacityViolation.severity != capacity.ViolationSeverity.None:
                     colony.capacityViolation.violationTurn
                   else:
                     int32(state.turn)
  )

proc checkViolations*(state: GameState): seq[capacity.CapacityViolation] =
  ## Batch check all colonies for fighter capacity violations
  ## Pure function - returns analysis without mutations
  result = @[]

  # Use iterator to efficiently check all colonies
  for houseId in state.houses.entities.index.keys:
    let houseOpt = gs_helpers.getHouse(state, houseId)
    if houseOpt.isNone or houseOpt.get().isEliminated:
      continue

    for colony in state.coloniesOwned(houseId):
      let status = analyzeCapacity(state, colony, colony.owner)
      if status.severity != capacity.ViolationSeverity.None:
        result.add(status)

proc updateViolationTracking*(state: var GameState, violation: capacity.CapacityViolation) =
  ## Update violation tracking for a colony
  ## Explicit mutation - applies tracking state changes

  let colonyId = violation.entity.colonyId
  let colonyOpt = gs_helpers.getColony(state, colonyId)
  if colonyOpt.isNone:
    return

  var colony = colonyOpt.get()

  if violation.severity != capacity.ViolationSeverity.None:
    # Violation exists
    if colony.capacityViolation.severity == capacity.ViolationSeverity.None:
      # New violation - start grace period
      colony.capacityViolation = capacity.CapacityViolation(
        capacityType: capacity.CapacityType.FighterSquadron,
        entity: capacity.EntityIdUnion(kind: capacity.CapacityType.FighterSquadron, colonyId: colonyId),
        current: violation.current,
        maximum: violation.maximum,
        excess: violation.excess,
        severity: capacity.ViolationSeverity.Violation,
        graceTurnsRemaining: 2'i32,
        violationTurn: int32(state.turn)
      )

      logger.logWarn("Military", "Fighter capacity violation - new",
              " colony=", $colonyId, " type=industrial",
              " excess=", $violation.excess, " gracePeriod=2turns",
              " currentIU=", $colony.industrial.units)
    else:
      # Existing violation - decrement grace period
      colony.capacityViolation.graceTurnsRemaining -= 1
      colony.capacityViolation.current = violation.current
      colony.capacityViolation.maximum = violation.maximum
      colony.capacityViolation.excess = violation.excess

      logger.logWarn("Military", "Fighter capacity violation - continuing",
              " colony=", $colonyId, " type=industrial",
              " graceRemaining=", $colony.capacityViolation.graceTurnsRemaining)
  else:
    # No violation - clear tracking
    if colony.capacityViolation.severity != capacity.ViolationSeverity.None:
      logger.logDebug("Military", "Fighter capacity violation resolved",
              " colony=", $colonyId)
      colony.capacityViolation = capacity.CapacityViolation(
        capacityType: capacity.CapacityType.FighterSquadron,
        entity: capacity.EntityIdUnion(kind: capacity.CapacityType.FighterSquadron, colonyId: colonyId),
        current: 0,
        maximum: 0,
        excess: 0,
        severity: capacity.ViolationSeverity.None,
        graceTurnsRemaining: 0,
        violationTurn: 0
      )

  # Update colony in state
  state.colonies.entities.updateEntity(colonyId, colony)

proc planEnforcement*(state: GameState, violation: capacity.CapacityViolation): capacity.EnforcementAction =
  ## Plan enforcement actions for expired violations
  ## Pure function - returns enforcement plan without mutations

  result = capacity.EnforcementAction(
    capacityType: capacity.CapacityType.FighterSquadron,
    entity: violation.entity,
    actionType: "",
    affectedUnitIds: @[],
    description: ""
  )

  # Check if enforcement needed
  if violation.severity != capacity.ViolationSeverity.Critical:
    return

  let colonyId = violation.entity.colonyId
  let colonyOpt = gs_helpers.getColony(state, colonyId)
  if colonyOpt.isNone:
    return

  let colony = colonyOpt.get()

  # Get actual fighter squadrons from state.squadrons
  # Sort by squadron ID (IDs are generated sequentially, oldest = lowest ID)
  var sortedFighters: seq[SquadronId] = @[]

  for squadronId in colony.fighterSquadronIds:
    let squadronOpt = gs_helpers.getSquadrons(state, squadronId)
    if squadronOpt.isSome:
      sortedFighters.add(squadronId)

  # Sort by ID (oldest first - lowest IDs were created first)
  sortedFighters.sort do (a, b: SquadronId) -> int:
    cmp(uint32(a), uint32(b))

  # Select excess fighters for disbanding
  let toDisbandCount = min(violation.excess, int32(sortedFighters.len))
  result.actionType = "disband"
  for i in 0 ..< toDisbandCount:
    result.affectedUnitIds.add($sortedFighters[i])

  result.description = $toDisbandCount & " fighter squadron(s) auto-disbanded at colony-" &
                      $violation.entity.colonyId & " (capacity violation)"

proc applyEnforcement*(state: var GameState, action: capacity.EnforcementAction,
                       events: var seq[GameEvent]) =
  ## Apply enforcement actions
  ## Explicit mutation - disbands fighters and clears violation
  ## Emits SquadronDisbanded events for tracking

  if action.actionType != "disband" or action.affectedUnitIds.len == 0:
    return

  let colonyId = action.entity.colonyId
  let colonyOpt = gs_helpers.getColony(state, colonyId)
  if colonyOpt.isNone:
    return

  var colony = colonyOpt.get()

  # Disband fighters (oldest first)
  for fighterIdStr in action.affectedUnitIds:
    let fighterId = SquadronId(parseUInt(fighterIdStr))

    # Get squadron info before destroying
    let squadronOpt = gs_helpers.getSquadrons(state, fighterId)
    if squadronOpt.isSome:
      let squadron = squadronOpt.get()

      # Emit SquadronDisbanded event (fighters use ShipClass.Fighter)
      events.add(fleet_ops.squadronDisbanded(
        houseId = colony.owner,
        squadronId = fighterIdStr,
        shipClass = ShipClass.Fighter,
        reason = "Fighter squadron capacity exceeded (IU loss)",
        systemId = colony.systemId
      ))

      logger.logDebug("Military", "Fighter squadron disbanded - capacity violation",
                " squadronId=", fighterIdStr, " salvage=none")

    # Remove from colony's fighter squadron list
    colony.fighterSquadronIds.keepIf(proc(id: SquadronId): bool = id != fighterId)

    # Destroy squadron from state.squadrons EntityManager
    squadron_ops.destroySquadron(state, fighterId)

  # Clear violation tracking
  colony.capacityViolation = capacity.CapacityViolation(
    capacityType: capacity.CapacityType.FighterSquadron,
    entity: capacity.EntityIdUnion(kind: capacity.CapacityType.FighterSquadron, colonyId: colonyId),
    current: 0,
    maximum: 0,
    excess: 0,
    severity: capacity.ViolationSeverity.None,
    graceTurnsRemaining: 0,
    violationTurn: 0
  )

  # Update colony in state
  state.colonies.entities.updateEntity(colonyId, colony)

  logger.logDebug("Military", "Capacity enforcement complete",
            " colony=", $colonyId,
            " disbanded=", $action.affectedUnitIds.len)

proc processCapacityEnforcement*(state: var GameState,
                                events: var seq[GameEvent]): seq[capacity.EnforcementAction] =
  ## Main entry point - batch process all capacity violations
  ## Called during Maintenance phase
  ## Data-oriented: analyze all → plan enforcement → apply enforcement
  ## Returns: List of enforcement actions that were actually applied

  result = @[]

  logger.logDebug("Military", "Checking fighter capacity")

  # Step 1: Check all colonies for violations (pure)
  let violations = checkViolations(state)

  if violations.len == 0:
    logger.logDebug("Military", "All colonies within fighter capacity limits")
    # Clear any lingering violation tracking
    for houseId in state.houses.entities.index.keys:
      let houseOpt = gs_helpers.getHouse(state, houseId)
      if houseOpt.isNone or houseOpt.get().isEliminated:
        continue

      for colony in state.coloniesOwned(houseId):
        if colony.capacityViolation.severity != capacity.ViolationSeverity.None:
          var mutColony = colony
          mutColony.capacityViolation = capacity.CapacityViolation(
            capacityType: capacity.CapacityType.FighterSquadron,
            entity: capacity.EntityIdUnion(kind: capacity.CapacityType.FighterSquadron, colonyId: colony.id),
            current: 0,
            maximum: 0,
            excess: 0,
            severity: capacity.ViolationSeverity.None,
            graceTurnsRemaining: 0,
            violationTurn: 0
          )
          state.colonies.entities.updateEntity(colony.id, mutColony)
    return

  logger.logDebug("Military", "Capacity violations found, count=", $violations.len)

  # Step 2: Update violation tracking (mutations)
  for violation in violations:
    updateViolationTracking(state, violation)

  # Re-check violations after tracking updates to get current severity
  let updatedViolations = checkViolations(state)

  # Step 3: Plan enforcement for expired violations (pure)
  var enforcementActions: seq[capacity.EnforcementAction] = @[]
  for violation in updatedViolations:
    let action = planEnforcement(state, violation)
    if action.actionType == "disband" and action.affectedUnitIds.len > 0:
      enforcementActions.add(action)

  # Step 4: Apply enforcement (mutations)
  if enforcementActions.len > 0:
    logger.logDebug("Military", "Enforcing expired capacity violations",
              " count=", $enforcementActions.len)
    for action in enforcementActions:
      applyEnforcement(state, action, events)
      result.add(action)  # Track which actions were applied
  else:
    logger.logDebug("Military", "No violations requiring immediate enforcement")

proc canCommissionFighter*(state: GameState, colony: Colony): bool =
  ## Check if colony can commission a new fighter squadron
  ## Returns false if colony is in capacity violation
  ## Pure function - no mutations

  if colony.capacityViolation.severity != capacity.ViolationSeverity.None:
    return false

  let violation = analyzeCapacity(state, colony, colony.owner)
  return violation.severity == capacity.ViolationSeverity.None and
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
