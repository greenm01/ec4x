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

import std/[algorithm, options, strutils, tables]
import ../../../types/capacity as types
import ../../../gamestate
import ../../../types/economy as econ_types # For ConstructionType, ConstructionProject
import ../../../../common/types/core
import ../../../../common/types/units # For ShipClass
import ../../../../common/logger

export types.CapacityViolation, types.EnforcementAction, types.ViolationSeverity

proc calculateMaxPlanetBreakers*(colonyCount: int): int =
  ## Pure calculation of maximum planet-breaker capacity
  ## Formula: Max PB = current colony count
  ## Homeworld counts as 1 colony
  return colonyCount

proc countPlanetBreakersInFleets*(state: GameState, houseId: core.HouseId): int =
  ## Count planet-breakers currently in fleets for a house
  ## (O(1) lookup via fleetsByOwner index)
  result = 0
  if houseId in state.fleetsByOwner:
    for fleetId in state.fleetsByOwner[houseId]:
      if fleetId in state.fleets:
        let fleet = state.fleets[fleetId]
        for squadron in fleet.squadrons:
          if squadron.flagship.shipClass == ShipClass.PlanetBreaker:
            result += 1

proc countPlanetBreakersUnderConstruction*(state: GameState, houseId: core.HouseId): int =
  ## Count planet-breakers currently under construction house-wide
  result = 0
  for systemId, colony in state.colonies:
    if colony.owner == houseId:
      # Check underConstruction (legacy single project)
      if colony.underConstruction.isSome:
        let project = colony.underConstruction.get()
        if project.projectType == econ_types.ConstructionType.Ship and
           project.itemId == "PlanetBreaker":
          result += 1

      # Check construction queue
      for project in colony.constructionQueue:
        if project.projectType == econ_types.ConstructionType.Ship and
           project.itemId == "PlanetBreaker":
          result += 1

proc analyzeCapacity*(state: GameState, houseId: core.HouseId): types.CapacityViolation =
  ## Pure function - analyze house's planet-breaker capacity status
  ## Returns capacity analysis without mutating state

  # Count colonies owned by house
  var colonyCount = 0
  for systemId, colony in state.colonies:
    if colony.owner == houseId:
      colonyCount += 1

  let current = countPlanetBreakersInFleets(state, houseId)
  let maximum = calculateMaxPlanetBreakers(colonyCount)
  let excess = max(0, current - maximum)

  # Planet-breakers have no grace period - immediate enforcement
  let severity = if excess == 0:
                   ViolationSeverity.None
                 else:
                   ViolationSeverity.Critical

  result = types.CapacityViolation(
    capacityType: CapacityType.PlanetBreaker,
    entityId: $houseId,
    current: current,
    maximum: maximum,
    excess: excess,
    severity: severity,
    graceTurnsRemaining: 0,  # No grace period
    violationTurn: state.turn
  )

proc checkViolations*(state: GameState): seq[types.CapacityViolation] =
  ## Batch check all houses for planet-breaker capacity violations
  ## Pure function - returns analysis without mutations
  result = @[]

  for houseId, house in state.houses:
    if not house.eliminated:
      let status = analyzeCapacity(state, houseId)
      if status.severity != ViolationSeverity.None:
        result.add(status)

proc planEnforcement*(state: GameState, violation: types.CapacityViolation): types.EnforcementAction =
  ## Plan enforcement actions for violations
  ## Pure function - returns enforcement plan without mutations
  ## Planet-breakers: Auto-scrap oldest units immediately (no grace period)

  result = types.EnforcementAction(
    capacityType: CapacityType.PlanetBreaker,
    entityId: violation.entityId,
    actionType: "",
    affectedUnits: @[],
    description: ""
  )

  if violation.severity != ViolationSeverity.Critical:
    return

  let houseId = core.HouseId(violation.entityId)

  # Find all planet-breakers for this house
  # Sort by squadron ID (deterministic order, oldest squadrons tend to have lower IDs)
  var squadronIds: seq[string] = @[]

  for fleetId, fleet in state.fleets:
    if fleet.owner == houseId:
      for squadron in fleet.squadrons:
        if squadron.flagship.shipClass == ShipClass.PlanetBreaker:
          squadronIds.add(squadron.id)

  # Sort by squadron ID (alphabetical/numerical order gives deterministic "oldest first" behavior)
  squadronIds.sort()

  # Select excess planet-breakers for scrapping
  let toScrapCount = min(violation.excess, squadronIds.len)
  result.actionType = "auto_scrap"
  for i in 0 ..< toScrapCount:
    result.affectedUnits.add(squadronIds[i])

  result.description = $toScrapCount & " planet-breaker(s) auto-scrapped for house-" &
                      violation.entityId & " (colony loss, no salvage)"

proc applyEnforcement*(state: var GameState, action: types.EnforcementAction) =
  ## Apply enforcement actions
  ## Explicit mutation - scraps planet-breakers (no salvage value)

  if action.actionType != "auto_scrap" or action.affectedUnits.len == 0:
    return

  let houseId = core.HouseId(action.entityId)

  # Remove planet-breakers from fleets
  for fleetId, fleet in state.fleets.mpairs:
    if fleet.owner == houseId:
      var toRemove: seq[int] = @[]
      for idx, squadron in fleet.squadrons:
        if squadron.id in action.affectedUnits:
          toRemove.add(idx)
          logEconomy("Planet-breaker auto-scrapped - colony loss",
                    "squadronId=", squadron.id, " salvage=none")

      # Remove squadrons (reverse order to maintain indices)
      for idx in toRemove.reversed:
        fleet.squadrons.delete(idx)

  logEconomy("Planet-breaker capacity enforcement complete",
            "house=", $houseId,
            " scrapped=", $action.affectedUnits.len)

proc processCapacityEnforcement*(state: var GameState): seq[types.EnforcementAction] =
  ## Main entry point - batch process all planet-breaker capacity violations
  ## Called during Maintenance phase
  ## Data-oriented: analyze all → plan enforcement → apply enforcement
  ## Returns: List of enforcement actions that were actually applied

  result = @[]

  logDebug("Military", "Checking planet-breaker capacity")

  # Step 1: Check all houses for violations (pure)
  let violations = checkViolations(state)

  if violations.len == 0:
    logDebug("Military", "All houses within planet-breaker capacity limits")
    return

  logDebug("Military", "Planet-breaker violations found", "count=", $violations.len)

  # Step 2: Plan enforcement (no tracking needed - immediate enforcement)
  var enforcementActions: seq[types.EnforcementAction] = @[]
  for violation in violations:
    let action = planEnforcement(state, violation)
    if action.actionType == "auto_scrap" and action.affectedUnits.len > 0:
      enforcementActions.add(action)

  # Step 3: Apply enforcement (mutations)
  if enforcementActions.len > 0:
    logEconomy("Enforcing planet-breaker capacity violations",
              "count=", $enforcementActions.len)
    for action in enforcementActions:
      applyEnforcement(state, action)
      result.add(action)  # Track which actions were applied
  else:
    logDebug("Military", "No planet-breaker violations requiring enforcement")

proc canBuildPlanetBreaker*(state: GameState, houseId: core.HouseId): bool =
  ## Check if house can build a new planet-breaker
  ## Returns false if house is at or over capacity
  ## Pure function - no mutations

  let violation = analyzeCapacity(state, houseId)

  # Account for planet-breakers already under construction
  let underConstruction = countPlanetBreakersUnderConstruction(state, houseId)

  return violation.current + underConstruction < violation.maximum

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
