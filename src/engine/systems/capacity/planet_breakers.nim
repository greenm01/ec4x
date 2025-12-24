## Planet-Breaker Capacity Enforcement System
##
## Implements planet-breaker ownership limits per reference.md Table 10.5
##
## Capacity Formula: Max PB = Current colony count (homeworld counts as 1)
##
## **IMPORTANT:** Planet-breakers are limited by strategic expansion, not industrial capacity
## Rationale: These superweapons require massive support infrastructure distributed across
## multiple colonies. Only empires with sufficient territorial control can field them.
##
## Enforcement: Cannot build beyond limit, must auto-scrap if colonies lost
##
## Data-oriented design: Calculate violations (pure), apply enforcement (explicit mutations)

import std/[strutils, algorithm, options]
import ../../types/[
  capacity, core, game_state, squadron, ship, production, event, colony, house
]
import ../../state/[game_state as gs_helpers, iterators]
import ../../entities/squadron_ops
import ../../event_factory/fleet_ops
import ../../../common/logger

export capacity.CapacityViolation, capacity.EnforcementAction,
       capacity.ViolationSeverity

proc calculateMaxPlanetBreakers*(colonyCount: int): int =
  ## Pure calculation of maximum planet-breaker capacity
  ## Formula: Max PB = current colony count
  ## Homeworld counts as 1 colony
  return colonyCount

proc countPlanetBreakersInFleets*(state: GameState, houseId: HouseId): int =
  ## Count planet-breakers currently in fleets for a house
  ## (O(1) lookup via squadronsOwned iterator)
  result = 0
  for squadron in state.squadronsOwned(houseId):
    if squadron.flagship.shipClass == ShipClass.PlanetBreaker:
      result += 1

proc countPlanetBreakersUnderConstruction*(state: GameState, houseId: HouseId): int =
  ## Count planet-breakers currently under construction house-wide
  result = 0
  for colony in state.coloniesOwned(houseId):
    # Check underConstruction (single active project)
    if colony.underConstruction.isSome:
      let projectId = colony.underConstruction.get()
      let projectOpt = gs_helpers.getConstructionProject(state, projectId)
      if projectOpt.isSome:
        let project = projectOpt.get()
        if project.projectType == BuildType.Ship and project.itemId == "PlanetBreaker":
          result += 1

    # Check construction queue
    for projectId in colony.constructionQueue:
      let projectOpt = gs_helpers.getConstructionProject(state, projectId)
      if projectOpt.isSome:
        let project = projectOpt.get()
        if project.projectType == BuildType.Ship and project.itemId == "PlanetBreaker":
          result += 1

proc analyzeCapacity*(state: GameState, houseId: HouseId): capacity.CapacityViolation =
  ## Pure function - analyze house's planet-breaker capacity status
  ## Returns capacity analysis without mutating state

  # Count colonies owned by house
  var colonyCount = 0
  for colony in state.coloniesOwned(houseId):
    colonyCount += 1

  let current = countPlanetBreakersInFleets(state, houseId)
  let maximum = calculateMaxPlanetBreakers(colonyCount)
  let excess = max(0, current - maximum)

  # Planet-breakers have no grace period - immediate enforcement
  let severity = if excess == 0:
                   capacity.ViolationSeverity.None
                 else:
                   capacity.ViolationSeverity.Critical

  result = capacity.CapacityViolation(
    capacityType: capacity.CapacityType.PlanetBreaker,
    entity: capacity.EntityIdUnion(kind: capacity.CapacityType.PlanetBreaker, houseId: houseId),
    current: int32(current),
    maximum: int32(maximum),
    excess: int32(excess),
    severity: severity,
    graceTurnsRemaining: 0'i32,  # No grace period
    violationTurn: int32(state.turn)
  )

proc checkViolations*(state: GameState): seq[capacity.CapacityViolation] =
  ## Batch check all houses for planet-breaker capacity violations
  ## Pure function - returns analysis without mutations
  result = @[]

  for house in state.activeHouses():
    let status = analyzeCapacity(state, house.id)
    if status.severity != capacity.ViolationSeverity.None:
      result.add(status)

proc planEnforcement*(state: GameState, violation: capacity.CapacityViolation): capacity.EnforcementAction =
  ## Plan enforcement actions for violations
  ## Pure function - returns enforcement plan without mutations
  ## Planet-breakers: Auto-scrap oldest units immediately (no grace period)

  result = capacity.EnforcementAction(
    capacityType: capacity.CapacityType.PlanetBreaker,
    entity: violation.entity,
    actionType: "",
    affectedUnitIds: @[],
    description: ""
  )

  if violation.severity != capacity.ViolationSeverity.Critical:
    return

  let houseId = violation.entity.houseId

  # Find all planet-breakers for this house
  # Sort by squadron ID (deterministic order, oldest squadrons have lower IDs)
  var squadronIds: seq[string] = @[]

  for squadron in state.squadronsOwned(houseId):
    if squadron.flagship.shipClass == ShipClass.PlanetBreaker:
      squadronIds.add($squadron.id)

  # Sort by squadron ID (alphabetical/numerical order gives deterministic "oldest first" behavior)
  squadronIds.sort()

  # Select excess planet-breakers for scrapping
  let toScrapCount = min(violation.excess, int32(squadronIds.len))
  result.actionType = "auto_scrap"
  for i in 0 ..< toScrapCount:
    result.affectedUnitIds.add(squadronIds[i])

  result.description = $toScrapCount & " planet-breaker(s) auto-scrapped for house-" &
                      $violation.entity.houseId & " (colony loss, no salvage)"

proc applyEnforcement*(state: var GameState, action: capacity.EnforcementAction,
                       events: var seq[GameEvent]) =
  ## Apply enforcement actions
  ## Explicit mutation - scraps planet-breakers (no salvage value)
  ## Emits SquadronScrapped events for tracking

  if action.actionType != "auto_scrap" or action.affectedUnitIds.len == 0:
    return

  let houseId = action.entity.houseId

  # Remove planet-breakers using squadron_ops.destroySquadron
  for squadronIdStr in action.affectedUnitIds:
    let squadronId = SquadronId(parseUInt(squadronIdStr))

    # Get squadron info before destroying
    let squadronOpt = gs_helpers.getSquadrons(state, squadronId)
    if squadronOpt.isSome:
      let squadron = squadronOpt.get()

      # Emit SquadronScrapped event
      events.add(fleet_ops.squadronScrapped(
        houseId = houseId,
        squadronId = squadronIdStr,
        shipClass = ShipClass.PlanetBreaker,
        reason = "Planet-breaker capacity exceeded (colony loss)",
        salvageValue = 0,  # No salvage for planet-breakers
        systemId = squadron.location
      ))

      logger.logDebug("Military", "Planet-breaker auto-scrapped - colony loss",
                " squadronId=", squadronIdStr, " salvage=none")

    # Destroy squadron from state.squadrons EntityManager
    squadron_ops.destroySquadron(state, squadronId)

  logger.logDebug("Military", "Planet-breaker capacity enforcement complete",
            " house=", $houseId,
            " scrapped=", $action.affectedUnitIds.len)

proc processCapacityEnforcement*(state: var GameState,
                                events: var seq[GameEvent]): seq[capacity.EnforcementAction] =
  ## Main entry point - batch process all planet-breaker capacity violations
  ## Called during Maintenance phase
  ## Data-oriented: analyze all → plan enforcement → apply enforcement
  ## Returns: List of enforcement actions that were actually applied

  result = @[]

  logger.logDebug("Military", "Checking planet-breaker capacity")

  # Step 1: Check all houses for violations (pure)
  let violations = checkViolations(state)

  if violations.len == 0:
    logger.logDebug("Military", "All houses within planet-breaker capacity limits")
    return

  logger.logDebug("Military", "Planet-breaker violations found, count=", $violations.len)

  # Step 2: Plan enforcement (no tracking needed - immediate enforcement)
  var enforcementActions: seq[capacity.EnforcementAction] = @[]
  for violation in violations:
    let action = planEnforcement(state, violation)
    if action.actionType == "auto_scrap" and action.affectedUnitIds.len > 0:
      enforcementActions.add(action)

  # Step 3: Apply enforcement (mutations)
  if enforcementActions.len > 0:
    logger.logDebug("Military", "Enforcing planet-breaker capacity violations",
              " count=", $enforcementActions.len)
    for action in enforcementActions:
      applyEnforcement(state, action, events)
      result.add(action)  # Track which actions were applied
  else:
    logger.logDebug("Military", "No planet-breaker violations requiring enforcement")

proc canBuildPlanetBreaker*(state: GameState, houseId: HouseId): bool =
  ## Check if house can build a new planet-breaker
  ## Returns false if house is at or over capacity
  ## Pure function - no mutations

  let violation = analyzeCapacity(state, houseId)

  # Account for planet-breakers already under construction
  let underConstruction = countPlanetBreakersUnderConstruction(state, houseId)

  return violation.current + int32(underConstruction) < violation.maximum

## Design Notes:
##
## **Data-Oriented Pattern:**
## 1. analyzeCapacity() - Pure calculation of capacity status
## 2. checkViolations() - Batch analyze all houses (pure)
## 3. planEnforcement() - Pure function returns enforcement plan
## 4. applyEnforcement() - Explicit mutations apply the plan
## 5. processCapacityEnforcement() - Main batch processor
##
## **Differences from Fighter Capacity:**
## - NO grace period (immediate enforcement on colony loss)
## - Per-house limit (not per-colony)
## - Auto-scrap instead of disband
## - No salvage value (25% salvage would be too generous for such powerful units)
##
## **Spec Compliance:**
## - reference.md Table 10.5: 1 planet-breaker per colony owned
## - Immediate enforcement when colonies are lost
## - Cannot build beyond current colony count
## - Oldest units scrapped first
##
## **Integration Points:**
## - Call processCapacityEnforcement() in Maintenance phase
## - Call canBuildPlanetBreaker() before allowing construction orders
## - Enforcement happens AFTER colony ownership changes
