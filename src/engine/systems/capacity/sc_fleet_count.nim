## Strategic Command (SC) - Combat Fleet Count Capacity System
##
## Implements reference.md Table 10.5 - Strategic Command fleet count limits
##
## Fleet Count Formula: Max combat fleets = SC Tech Base × Map Scale Factor
##
## Where Strategic Command (SC) Tech Level provides base (from config/tech.kdl):
## - SC I: 10 combat fleets (base)
## - SC II: 12 combat fleets (base)
## - SC III: 14 combat fleets (base)
## - SC IV: 16 combat fleets (base)
## - SC V: 18 combat fleets (base)
## - SC VI: 20 combat fleets (base)
##
## Map Scale Factor (from config/limits.kdl strategicCommandScaling):
## Formula: scale = 1 + log₂(systems_per_player ÷ divisor) × scaleFactor
## Where:
##   - systems_per_player = total_map_systems ÷ player_count
##   - divisor = 8.0 (threshold where scaling begins)
##   - scaleFactor = 0.4 (scaling aggressiveness)
##
## **IMPORTANT:** Only "combat fleets" count toward this limit. Fleets containing
## ONLY auxiliary ships (SC/ETAC/TT) are exempt and do not count.
##
## **IMPORTANT:** This is a hard capacity limit. Houses cannot create new combat
## fleets beyond their SC-determined maximum. No grace period - enforcement at
## creation time.
##
## Data-oriented design: Calculate capacity (pure), check violations (pure),
## block at creation time (explicit mutations)

import std/[options, tables, math]
import ../../types/[capacity, core, game_state, fleet, house, ship]
import ../../state/[engine, iterators]
import ../../globals
import ../../../common/logger

export capacity.CapacityViolation, capacity.ViolationSeverity

proc isAuxiliaryShip*(shipClass: ShipClass): bool =
  ## Check if ship class is auxiliary (non-combat)
  ## Auxiliary: SC (Scout), ET (ETAC), TT (Troop Transport)
  shipClass == ShipClass.Scout or shipClass == ShipClass.ETAC or
    shipClass == ShipClass.TroopTransport

proc isCombatFleet*(state: GameState, fleetId: FleetId): bool =
  ## Check if fleet is a combat fleet (contains any non-auxiliary ships)
  ## Returns true if fleet has at least one combat ship
  ## Pure function
  let fleetOpt = state.fleet(fleetId)
  if fleetOpt.isNone:
    return false

  let fleet = fleetOpt.get()

  # If fleet has any non-auxiliary ship, it's a combat fleet
  for shipId in fleet.ships:
    let shipOpt = state.ship(shipId)
    if shipOpt.isSome:
      let ship = shipOpt.get()
      if not isAuxiliaryShip(ship.shipClass):
        return true # Found a combat ship

  return false # Only auxiliary ships (or empty)

proc calculateMapScaleFactor*(
    totalSystems: int32, playerCount: int32
): float32 =
  ## Calculate logarithmic map scale factor for fleet count
  ## Formula: 1 + log₂(systems_per_player ÷ divisor) × scaleFactor
  ## Per config/limits.kdl strategicCommandScaling
  if playerCount <= 0'i32:
    return 1.0'f32

  let systemsPerPlayer = float32(totalSystems) / float32(playerCount)
  let divisor = gameConfig.limits.scScaling.systemsPerPlayerDivisor
  let scaleFactor = gameConfig.limits.scScaling.scaleFactor

  # If below divisor threshold, no scaling (return 1.0)
  if systemsPerPlayer <= divisor:
    return 1.0'f32

  # Apply logarithmic scaling
  let logComponent = log2(systemsPerPlayer / divisor)
  return 1.0'f32 + (logComponent * scaleFactor)

proc getStrategicCommandMaxFleets*(
    scLevel: int32, totalSystems: int32, playerCount: int32
): int32 =
  ## Get max combat fleets for house based on SC tech level and map size
  ## Returns maximum from config/tech.kdl sc levels with map scaling
  let cfg = gameConfig.tech.sc
  let baseFleets =
    if cfg.levels.hasKey(scLevel):
      cfg.levels[scLevel].maxCombatFleetsBase
    else:
      # Default to SC I if level not found
      cfg.levels[1'i32].maxCombatFleetsBase

  # Apply map scale factor
  let scaleFactor = calculateMapScaleFactor(totalSystems, playerCount)
  return int32(floor(float32(baseFleets) * scaleFactor))

proc countCombatFleets*(state: GameState, houseId: HouseId): int32 =
  ## Count combat fleets owned by house
  ## Pure function - counts fleets containing combat ships
  var count = 0'i32

  for fleet in state.fleetsOwned(houseId):
    if isCombatFleet(state, fleet.id):
      count += 1

  return count

proc analyzeFleetCountCapacity*(
    state: GameState, houseId: HouseId
): Option[capacity.CapacityViolation] =
  ## Analyze house's combat fleet count capacity
  ## Returns violation if house exceeds capacity, none otherwise
  ##
  ## Args:
  ##   state: Game state
  ##   houseId: House ID to check
  ##
  ## Returns:
  ##   Some(violation) if over capacity, none otherwise

  let houseOpt = state.house(houseId)
  if houseOpt.isNone:
    return none(capacity.CapacityViolation)

  let house = houseOpt.get()
  let scLevel = house.techTree.levels.sc

  # Get map parameters for scaling
  let totalSystems = int32(state.systems.entities.data.len)
  let playerCount = int32(state.houses.entities.data.len)

  let maximum = getStrategicCommandMaxFleets(scLevel, totalSystems, playerCount)
  let current = countCombatFleets(state, houseId)
  let excess = max(0'i32, current - maximum)

  # SC has no grace period - immediate critical if over
  let severity =
    if excess == 0'i32:
      capacity.ViolationSeverity.None
    else:
      capacity.ViolationSeverity.Critical

  if severity == capacity.ViolationSeverity.None:
    return none(capacity.CapacityViolation)

  result = some(
    capacity.CapacityViolation(
      capacityType: capacity.CapacityType.FleetCount,
      entity: capacity.EntityIdUnion(
        kind: capacity.CapacityType.FleetCount, houseId: houseId
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
  ## Batch check all houses for combat fleet count violations
  ## Pure function - returns analysis without mutations
  result = @[]

  # Iterate through all houses
  for house in state.activeHouses():
    let violation = analyzeFleetCountCapacity(state, house.id)
    if violation.isSome:
      result.add(violation.get())

proc canCreateCombatFleet*(
    state: GameState, houseId: HouseId
): bool =
  ## Check if house can create a new combat fleet
  ## Returns true if house has capacity for additional combat fleets
  ##
  ## Args:
  ##   state: Game state
  ##   houseId: House ID
  ##
  ## Returns:
  ##   true if house has capacity, false otherwise

  let houseOpt = state.house(houseId)
  if houseOpt.isNone:
    return false

  let house = houseOpt.get()
  let scLevel = house.techTree.levels.sc

  # Get map parameters
  let totalSystems = int32(state.systems.entities.data.len)
  let playerCount = int32(state.houses.entities.data.len)

  let maximum = getStrategicCommandMaxFleets(scLevel, totalSystems, playerCount)
  let current = countCombatFleets(state, houseId)

  return current < maximum

proc getAvailableFleetCapacity*(
    state: GameState, houseId: HouseId
): int32 =
  ## Get remaining combat fleet capacity for house
  ## Returns: maximum - current
  ## Returns 0 if house doesn't exist
  ##
  ## Used to check how many more combat fleets can be created

  let houseOpt = state.house(houseId)
  if houseOpt.isNone:
    return 0'i32

  let house = houseOpt.get()
  let scLevel = house.techTree.levels.sc

  # Get map parameters
  let totalSystems = 100'i32 # Placeholder
  let playerCount = 4'i32 # Placeholder

  let maximum = getStrategicCommandMaxFleets(scLevel, totalSystems, playerCount)
  let current = countCombatFleets(state, houseId)

  return max(0'i32, maximum - current)

proc processCapacityEnforcement*(
    state: GameState
): seq[capacity.CapacityViolation] =
  ## Main entry point - check all houses for combat fleet count violations
  ## Called during Maintenance phase
  ##
  ## NOTE: Unlike fighter grace period or capital ship auto-scrap,
  ## fleet count violations should NEVER occur because fleet creation is blocked
  ## at capacity. This function exists for consistency and debugging.
  ##
  ## If violations are found, they indicate a bug in the fleet management system.
  ##
  ## Returns: List of violations found (for logging/debugging)

  result = @[]

  logDebug("Military", "Checking combat fleet count capacity (SC limits)")

  # Check all houses for violations (should find none)
  let violations = checkViolations(state)

  logDebug("Military", "Fleet count check complete", " violations=", $violations.len)

  if violations.len == 0:
    logDebug("Military", "All houses within SC fleet count limits")
    return

  # Violations should NEVER happen - fleet creation is blocked at capacity
  # If we find violations, log as warnings for debugging
  logWarn(
    "Military",
    "Fleet count violations found (BUG!)",
    " count=",
    $violations.len,
  )

  for violation in violations:
    logWarn(
      "Military",
      "House over fleet count capacity",
      " houseId=",
      $violation.entity.houseId,
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
## 1. isCombatFleet() - Pure check if fleet contains combat ships
## 2. calculateMapScaleFactor() - Pure calculation of logarithmic scale
## 3. getStrategicCommandMaxFleets() - Pure calculation by SC level + map
## 4. countCombatFleets() - Pure count of combat fleets for house
## 5. analyzeFleetCountCapacity() - Pure analysis of house status
## 6. checkViolations() - Batch analyze all houses (pure)
## 7. canCreateCombatFleet() - Pure check if creation is allowed
## 8. processCapacityEnforcement() - Check violations (should find none)
##
## **Key Differences from Other Capacity Systems:**
## - Per-house capacity (not per-fleet or per-colony)
## - Tech-based limit with logarithmic map scaling
## - Distinguishes combat vs auxiliary fleets
## - Blocking enforcement (reject at creation time, not auto-remove)
## - NO grace period (hard limit)
## - NO salvage (violations shouldn't occur)
##
## **Spec Compliance:**
## - reference.md Table 10.5 - Fleet Count limits
## - research_development.md Section 4.11 - Strategic Command tech
## - limits.kdl strategicCommandScaling - Logarithmic scaling formula
## - SC I: 10 fleets → SC VI: 20 fleets (base, before map scaling)
##
## **Integration Points:**
## - Call canCreateCombatFleet(state, houseId) before allowing fleet creation
##   (only for fleets that will contain combat ships)
## - Call processCapacityEnforcement() in Maintenance phase (debugging only)
## - Use getAvailableFleetCapacity(state, houseId) to show capacity to players
## - When converting auxiliary fleet to combat (adding combat ships), check
##   capacity first
##
## **Special Cases:**
## - SC tech upgrade: Immediately increases capacity for house
## - SC tech downgrade: Already-created fleets remain (grandfathered)
## - Auxiliary→Combat conversion: Must check capacity before adding combat ship
## - Map size: Larger maps allow proportionally more fleets via log scaling
##
## **Strategic Implications:**
## - Higher SC tech + larger maps = more fleets allowed
## - SC research immediately upgrades fleet count capacity house-wide
## - Auxiliary fleets (scouts, ETACs, transports) don't count - unlimited
## - Players must balance between fleet quality (FC) and quantity (SC)
##
## **TODO:**
## - Integrate with starmap to get actual totalSystems and playerCount
## - Consider caching map scale factor (calculated once at game start)
