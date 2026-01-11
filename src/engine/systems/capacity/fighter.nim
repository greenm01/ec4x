## Fighter Capacity Enforcement System
##
## Implements assets.md:2.4.1 - fighter capacity limits and violation enforcement.
##
## Capacity Formula: Max Fighters = floor(IU / 100) × FD Multiplier
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
## Enforcement: Disband oldest fighters first after grace period expires
##
## Data-oriented design: Calculate violations (pure), apply enforcement (explicit mutations)

import std/[sequtils, math, strutils, options, tables, algorithm]
import
  ../../types/
    [capacity, core, game_state, ship, production, event, colony, house]
import ../../state/[engine, iterators]
import ../../entities/ship_ops
import ../../event_factory/fleet_ops
import ../../globals
import ../../../common/logger

export
  capacity.CapacityViolation, capacity.EnforcementAction, capacity.ViolationSeverity

proc fighterDoctrineMultiplier(fdLevel: int32): float32 =
  ## Get Fighter Doctrine tech multiplier per assets.md:2.4.1
  ## Reads from gameConfig.tech.fd.levels
  let cfg = gameConfig.tech.fd
  if cfg.levels.hasKey(fdLevel):
    return cfg.levels[fdLevel].capacityMultiplier
  else:
    # Default to FD I (level 1) if not found
    return 1.0'f32

proc calculateMaxFighterCapacity*(industrialUnits: int32, fdLevel: int32): int32 =
  ## Pure calculation of maximum fighter capacity
  ## Formula: Max Fighters = floor(IU / divisor) × FD Tech Multiplier
  ## Per assets.md:2.4.1 and economy.md:3.10
  ## Reads divisor from gameConfig.limits.fighterCapacity
  let fdMult = fighterDoctrineMultiplier(fdLevel)
  let divisor = gameConfig.limits.fighterCapacity.iuDivisor
  return int32(floor(float32(industrialUnits) / float32(divisor)) * fdMult)

proc analyzeCapacity*(
    state: GameState, colony: Colony, houseId: HouseId
): capacity.CapacityViolation =
  ## Pure function - analyze colony's fighter capacity status
  ## Returns capacity analysis without mutating state

  # Get Fighter Doctrine level from house tech tree
  let houseOpt = state.house(houseId)
  let fdLevel =
    if houseOpt.isSome:
      houseOpt.get().techTree.levels.fd
    else:
      1'i32 # Default to base level

  # Count current fighters (only those actually commissioned, referenced by colony)
  var current = int32(colony.fighterIds.len)

  # Account for fighters already under construction at this colony
  var underConstruction = 0'i32
  for projectId in colony.constructionQueue:
    let projectOpt = state.constructionProject(projectId)
    if projectOpt.isSome:
      let project = projectOpt.get()
      if project.shipClass == some(ShipClass.Fighter):
        underConstruction += 1'i32

  # Check underConstruction field (single active project)
  if colony.underConstruction.isSome:
    let projectId = colony.underConstruction.get()
    let projectOpt = state.constructionProject(projectId)
    if projectOpt.isSome:
      let project = projectOpt.get()
      if project.shipClass == some(ShipClass.Fighter):
        underConstruction += 1'i32

  current += underConstruction

  let maximum = calculateMaxFighterCapacity(colony.industrial.units, fdLevel)
  let excess = max(0'i32, current - maximum)

  # Determine severity based on existing violation tracking
  # Use colony.capacityViolation for grace period tracking
  let severity =
    if excess == 0:
      capacity.ViolationSeverity.None
    elif colony.capacityViolation.severity != capacity.ViolationSeverity.None:
      # Existing violation - check grace period
      if colony.capacityViolation.graceTurnsRemaining <= 0:
        capacity.ViolationSeverity.Critical
      else:
        capacity.ViolationSeverity.Violation
    else:
      capacity.ViolationSeverity.Violation # New violation

  result = capacity.CapacityViolation(
    capacityType: capacity.CapacityType.FighterSquadron,
    entity: capacity.EntityIdUnion(
      kind: capacity.CapacityType.FighterSquadron, colonyId: colony.id
    ),
    current: current,
    maximum: maximum,
    excess: excess,
    severity: severity,
    graceTurnsRemaining:
      if colony.capacityViolation.severity != capacity.ViolationSeverity.None:
        colony.capacityViolation.graceTurnsRemaining
      else:
        gameConfig.limits.fighterCapacity.violationGracePeriodTurns,
    violationTurn:
      if colony.capacityViolation.severity != capacity.ViolationSeverity.None:
        colony.capacityViolation.violationTurn
      else:
        state.turn,
  )

proc checkViolations*(state: GameState): seq[capacity.CapacityViolation] =
  ## Batch check all colonies for fighter capacity violations
  ## Pure function - returns analysis without mutations
  result = @[]

  # Use iterator to efficiently check all colonies
  for house in state.activeHouses():
    for colony in state.coloniesOwned(house.id):
      let status = analyzeCapacity(state, colony, colony.owner)
      if status.severity != capacity.ViolationSeverity.None:
        result.add(status)

proc updateViolationTracking*(
    state: GameState, violation: capacity.CapacityViolation
) =
  ## Update violation tracking for a colony
  ## Explicit mutation - applies tracking state changes

  let colonyId = violation.entity.colonyId
  let colonyOpt = state.colony(colonyId)
  if colonyOpt.isNone:
    return

  var colony = colonyOpt.get()

  if violation.severity != capacity.ViolationSeverity.None:
    # Violation exists
    if colony.capacityViolation.severity == capacity.ViolationSeverity.None:
      # New violation - start grace period
      colony.capacityViolation = capacity.CapacityViolation(
        capacityType: capacity.CapacityType.FighterSquadron,
        entity: capacity.EntityIdUnion(
          kind: capacity.CapacityType.FighterSquadron, colonyId: colonyId
        ),
        current: violation.current,
        maximum: violation.maximum,
        excess: violation.excess,
        severity: capacity.ViolationSeverity.Violation,
        graceTurnsRemaining: gameConfig.limits.fighterCapacity.violationGracePeriodTurns,
        violationTurn: int32(state.turn),
      )

      logWarn(
        "Military",
        "Fighter capacity violation - new",
        " colony=",
        $colonyId,
        " type=industrial",
        " excess=",
        $violation.excess,
        " gracePeriod=2turns",
        " currentIU=",
        $colony.industrial.units,
      )
    else:
      # Existing violation - decrement grace period
      colony.capacityViolation.graceTurnsRemaining -= 1'i32
      colony.capacityViolation.current = violation.current
      colony.capacityViolation.maximum = violation.maximum
      colony.capacityViolation.excess = violation.excess

      logWarn(
        "Military",
        "Fighter capacity violation - continuing",
        " colony=",
        $colonyId,
        " type=industrial",
        " graceRemaining=",
        $colony.capacityViolation.graceTurnsRemaining,
      )
  else:
    # No violation - clear tracking
    if colony.capacityViolation.severity != capacity.ViolationSeverity.None:
      logDebug(
        "Military", "Fighter capacity violation resolved", " colony=", $colonyId
      )
      colony.capacityViolation = capacity.CapacityViolation(
        capacityType: capacity.CapacityType.FighterSquadron,
        entity: capacity.EntityIdUnion(
          kind: capacity.CapacityType.FighterSquadron, colonyId: colonyId
        ),
        current: 0,
        maximum: 0,
        excess: 0,
        severity: capacity.ViolationSeverity.None,
        graceTurnsRemaining: 0,
        violationTurn: 0,
      )

  # Update colony in state
  state.updateColony(colonyId, colony)

proc planEnforcement*(
    state: GameState, violation: capacity.CapacityViolation
): capacity.EnforcementAction =
  ## Plan enforcement actions for expired violations
  ## Pure function - returns enforcement plan without mutations

  result = capacity.EnforcementAction(
    capacityType: capacity.CapacityType.FighterSquadron,
    entity: violation.entity,
    actionType: "",
    affectedUnitIds: @[],
    description: "",
  )

  # Check if enforcement needed
  if violation.severity != capacity.ViolationSeverity.Critical:
    return

  let colonyId = violation.entity.colonyId
  let colonyOpt = state.colony(colonyId)
  if colonyOpt.isNone:
    return

  let colony = colonyOpt.get()

  # Get actual fighters from colony
  # Sort by ship ID (IDs are generated sequentially, oldest = lowest ID)
  var sortedFighters: seq[ShipId] = @[]

  for shipId in colony.fighterIds:
    let shipOpt = state.ship(shipId)
    if shipOpt.isSome:
      sortedFighters.add(shipId)

  # Sort by ID (oldest first - lowest IDs were created first)
  sortedFighters.sort do(a, b: ShipId) -> int:
    cmp(uint32(a), uint32(b))

  # Select excess fighters for disbanding
  let toDisbandCount = min(violation.excess, int32(sortedFighters.len))
  result.actionType = "disband"
  for i in 0 ..< toDisbandCount:
    result.affectedUnitIds.add($sortedFighters[i])

  result.description =
    $toDisbandCount & " fighter(s) auto-disbanded at colony-" &
    $violation.entity.colonyId & " (capacity violation)"

proc applyEnforcement*(
    state: GameState, action: capacity.EnforcementAction, events: var seq[GameEvent]
) =
  ## Apply enforcement actions
  ## Explicit mutation - disbands fighters and clears violation
  ## Emits SquadronDisbanded events for tracking

  if action.actionType != "disband" or action.affectedUnitIds.len == 0:
    return

  let colonyId = action.entity.colonyId
  let colonyOpt = state.colony(colonyId)
  if colonyOpt.isNone:
    return

  var colony = colonyOpt.get()

  # Disband fighters (oldest first)
  for fighterIdStr in action.affectedUnitIds:
    let fighterId = ShipId(parseUInt(fighterIdStr))

    # Get ship info before destroying
    let shipOpt = state.ship(fighterId)
    if shipOpt.isSome:

      # Emit shipDisbanded event
      events.add(
        fleet_ops.squadronDisbanded(
          houseId = colony.owner,
          squadronId = fighterIdStr,
          shipClass = ShipClass.Fighter,
          reason = "Fighter capacity exceeded (IU loss)",
          systemId = colony.systemId,
        )
      )

      logDebug(
        "Military", "Fighter disbanded - capacity violation", " shipId=",
        fighterIdStr, " salvage=none",
      )

    # Remove from colony's fighter list
    colony.fighterIds.keepIf(
      proc(id: ShipId): bool =
        id != fighterId
    )

    # Destroy ship from state.ships EntityManager
    state.destroyShip(fighterId)

  # Clear violation tracking
  colony.capacityViolation = capacity.CapacityViolation(
    capacityType: capacity.CapacityType.FighterSquadron,
    entity: capacity.EntityIdUnion(
      kind: capacity.CapacityType.FighterSquadron, colonyId: colonyId
    ),
    current: 0,
    maximum: 0,
    excess: 0,
    severity: capacity.ViolationSeverity.None,
    graceTurnsRemaining: 0,
    violationTurn: 0,
  )

  # Update colony in state
  state.updateColony(colonyId, colony)

  logDebug(
    "Military",
    "Capacity enforcement complete",
    " colony=",
    $colonyId,
    " disbanded=",
    $action.affectedUnitIds.len,
  )

proc processCapacityEnforcement*(
    state: GameState, events: var seq[GameEvent]
): seq[capacity.EnforcementAction] =
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
    # Clear any lingering violation tracking
    for house in state.activeHouses():
      for colony in state.coloniesOwned(house.id):
        if colony.capacityViolation.severity != capacity.ViolationSeverity.None:
          var mutColony = colony
          mutColony.capacityViolation = capacity.CapacityViolation(
            capacityType: capacity.CapacityType.FighterSquadron,
            entity: capacity.EntityIdUnion(
              kind: capacity.CapacityType.FighterSquadron, colonyId: colony.id
            ),
            current: 0'i32,
            maximum: 0'i32,
            excess: 0'i32,
            severity: capacity.ViolationSeverity.None,
            graceTurnsRemaining: 0'i32,
            violationTurn: 0'i32,
          )
          state.updateColony(colony.id, mutColony)
    return

  logDebug("Military", "Capacity violations found, count=", $violations.len)

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
    logDebug(
      "Military",
      "Enforcing expired capacity violations",
      " count=",
      $enforcementActions.len,
    )
    for action in enforcementActions:
      applyEnforcement(state, action, events)
      result.add(action) # Track which actions were applied
  else:
    logDebug("Military", "No violations requiring immediate enforcement")

proc canCommissionFighter*(state: GameState, colony: Colony): bool =
  ## Check if colony can commission a new fighter
  ## Returns false if colony is in capacity violation
  ## Pure function - no mutations

  if colony.capacityViolation.severity != capacity.ViolationSeverity.None:
    return false

  let violation = analyzeCapacity(state, colony, colony.owner)
  return
    violation.severity == capacity.ViolationSeverity.None and
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
## - economy.md:3.10: Fighter economics
## - Formula: Max FS = floor(IU / 100) × FD Tech Multiplier
## - NO infrastructure requirements (no starbases, shipyards, spaceports)
## - 2-turn grace period for violations
## - Disband oldest fighters first
## - No salvage value for forced disbanding
##
## **Integration Points:**
## - Call processCapacityEnforcement() in Maintenance phase
## - Call canCommissionFighter() before commissioning new fighters
## - Enforcement happens AFTER industrial capacity changes
