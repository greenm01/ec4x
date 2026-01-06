## Fleet Command (FC) - Ships Per Fleet Capacity System
##
## Implements reference.md Table 10.5 - Fleet Command ship count limits
##
## Ship Count Formula: Max ships per fleet = FC Tech Level capacity
##
## Where Fleet Command (FC) Tech Level provides (from config/tech.kdl):
## - FC I: 10 ships per fleet
## - FC II: 14 ships per fleet
## - FC III: 18 ships per fleet
## - FC IV: 22 ships per fleet
## - FC V: 26 ships per fleet
## - FC VI: 30 ships per fleet
##
## **IMPORTANT:** This is a hard capacity limit. Fleets cannot add ships beyond
## their FC-determined maximum. No grace period - enforcement at addition time.
##
## Data-oriented design: Calculate capacity (pure), check violations (pure),
## block at addition time (explicit mutations)

import std/[options, tables]
import ../../types/[capacity, core, game_state, fleet, house]
import ../../state/[engine, iterators]
import ../../globals
import ../../../common/logger

export capacity.CapacityViolation, capacity.ViolationSeverity

proc getFleetCommandMaxShips*(fcLevel: int32): int32 =
  ## Get max ships per fleet based on FC tech level
  ## Returns maximum ship count from config/tech.kdl fc levels
  let cfg = gameConfig.tech.fc
  if cfg.levels.hasKey(fcLevel):
    return cfg.levels[fcLevel].maxShipsPerFleet
  else:
    # Default to FC I if level not found
    return cfg.levels[1'i32].maxShipsPerFleet

proc getCurrentFleetSize*(state: GameState, fleetId: FleetId): int32 =
  ## Get current number of ships in fleet
  ## Pure function - just counts fleet.ships
  let fleetOpt = state.fleet(fleetId)
  if fleetOpt.isNone:
    return 0'i32

  let fleet = fleetOpt.get()
  return int32(fleet.ships.len)

proc analyzeFleetCapacity*(
    state: GameState, fleetId: FleetId
): Option[capacity.CapacityViolation] =
  ## Analyze single fleet's ship count capacity
  ## Returns violation if fleet exceeds capacity, none otherwise
  ##
  ## Args:
  ##   state: Game state
  ##   fleetId: Fleet ID to check
  ##
  ## Returns:
  ##   Some(violation) if over capacity, none otherwise

  let fleetOpt = state.fleet(fleetId)
  if fleetOpt.isNone:
    return none(capacity.CapacityViolation)

  let fleet = fleetOpt.get()

  # Get house's FC tech level
  let houseOpt = state.house(fleet.houseId)
  if houseOpt.isNone:
    return none(capacity.CapacityViolation)

  let fcLevel = houseOpt.get().techTree.levels.fc
  let maximum = getFleetCommandMaxShips(fcLevel)
  let current = getCurrentFleetSize(state, fleetId)
  let excess = max(0'i32, current - maximum)

  # FC has no grace period - immediate critical if over
  let severity =
    if excess == 0'i32:
      capacity.ViolationSeverity.None
    else:
      capacity.ViolationSeverity.Critical

  if severity == capacity.ViolationSeverity.None:
    return none(capacity.CapacityViolation)

  result = some(
    capacity.CapacityViolation(
      capacityType: capacity.CapacityType.FleetSize,
      entity: capacity.EntityIdUnion(
        kind: capacity.CapacityType.FleetSize, fleetId: fleetId
      ),
      current: current,
      maximum: maximum,
      excess: excess,
      severity: severity,
      graceTurnsRemaining: 0'i32, # No grace period
      violationTurn: int32(state.turn),
    )
  )

proc checkViolations*(state: GameState): seq[capacity.CapacityViolation] =
  ## Batch check all fleets for ship count violations
  ## Pure function - returns analysis without mutations
  result = @[]

  # Iterate through all fleets
  for house in state.activeHouses():
    for fleet in state.fleetsOwned(house.id):
      let violation = analyzeFleetCapacity(state, fleet.id)
      if violation.isSome:
        result.add(violation.get())

proc canAddShipsToFleet*(
    state: GameState, fleetId: FleetId, shipsToAdd: int32
): bool =
  ## Check if fleet has capacity to add ships
  ## Returns true if fleet can accommodate shipsToAdd additional ships
  ##
  ## Args:
  ##   state: Game state
  ##   fleetId: Fleet ID
  ##   shipsToAdd: Number of ships to add
  ##
  ## Returns:
  ##   true if fleet has enough capacity, false otherwise

  let fleetOpt = state.fleet(fleetId)
  if fleetOpt.isNone:
    return false

  let fleet = fleetOpt.get()

  # Get house's FC tech level
  let houseOpt = state.house(fleet.houseId)
  if houseOpt.isNone:
    return false

  let fcLevel = houseOpt.get().techTree.levels.fc
  let maximum = getFleetCommandMaxShips(fcLevel)
  let current = getCurrentFleetSize(state, fleetId)

  return current + shipsToAdd <= maximum

proc getAvailableFleetCapacity*(state: GameState, fleetId: FleetId): int32 =
  ## Get remaining ship capacity for fleet
  ## Returns: maximum - current
  ## Returns 0 if fleet doesn't exist
  ##
  ## Used to check how many more ships can be added to fleet

  let fleetOpt = state.fleet(fleetId)
  if fleetOpt.isNone:
    return 0'i32

  let fleet = fleetOpt.get()

  # Get house's FC tech level
  let houseOpt = state.house(fleet.houseId)
  if houseOpt.isNone:
    return 0'i32

  let fcLevel = houseOpt.get().techTree.levels.fc
  let maximum = getFleetCommandMaxShips(fcLevel)
  let current = getCurrentFleetSize(state, fleetId)

  return max(0'i32, maximum - current)

proc processCapacityEnforcement*(state: var GameState): seq[capacity.CapacityViolation] =
  ## Main entry point - check all fleets for ship count violations
  ## Called during Maintenance phase
  ##
  ## NOTE: Unlike fighter grace period or capital ship auto-scrap,
  ## fleet size violations should NEVER occur because adding ships is blocked
  ## at capacity. This function exists for consistency and debugging.
  ##
  ## If violations are found, they indicate a bug in the fleet management system.
  ##
  ## Returns: List of violations found (for logging/debugging)

  result = @[]

  logDebug("Military", "Checking fleet size capacity (FC limits)")

  # Check all fleets for violations (should find none)
  let violations = checkViolations(state)

  logDebug("Military", "Fleet size check complete", " violations=", $violations.len)

  if violations.len == 0:
    logDebug("Military", "All fleets within FC capacity limits")
    return

  # Violations should NEVER happen - ship additions are blocked at capacity
  # If we find violations, log as warnings for debugging
  logWarn(
    "Military", "Fleet size violations found (BUG!)", " count=", $violations.len
  )

  for violation in violations:
    logWarn(
      "Military",
      "Fleet over size capacity",
      " fleetId=",
      $violation.entity.fleetId,
      " current=",
      $violation.current,
      " max=",
      $violation.maximum,
      " excess=",
      $violation.excess,
    )

  result = violations

## Design Notes:
##
## **Data-Oriented Pattern:**
## 1. getFleetCommandMaxShips() - Pure calculation of max capacity by FC level
## 2. analyzeFleetCapacity() - Pure analysis of single fleet status
## 3. checkViolations() - Batch analyze all fleets (pure)
## 4. canAddShipsToFleet() - Pure check if adding is allowed
## 5. processCapacityEnforcement() - Check violations (should find none)
##
## **Key Differences from Other Capacity Systems:**
## - Per-fleet capacity (not per-house or per-colony)
## - Tech-based limit (FC level determines capacity)
## - Blocking enforcement (reject at add time, not auto-remove)
## - NO grace period (hard limit)
## - NO salvage (violations shouldn't occur)
##
## **Spec Compliance:**
## - reference.md Table 10.5 - Ships Per Fleet limits
## - research_development.md Section 4.10 - Fleet Command tech
## - FC I: 10 ships → FC VI: 30 ships
##
## **Integration Points:**
## - Call canAddShipsToFleet(state, fleetId, count) before allowing ship
##   assignments to fleets
## - Call processCapacityEnforcement() in Maintenance phase (debugging only)
## - Use getAvailableFleetCapacity(state, fleetId) to show available capacity
##   to players
##
## **Special Cases:**
## - FC tech upgrade: Immediately increases capacity for ALL fleets house-wide
## - FC tech downgrade: Already-assigned ships remain (grandfathered)
## - Fleet merges: Check combined size against FC limit before allowing
##
## **Strategic Implications:**
## - Higher FC tech allows larger, more powerful individual fleets
## - FC research immediately upgrades ALL fleet capacities house-wide
## - Players must balance between few large fleets vs many small fleets
