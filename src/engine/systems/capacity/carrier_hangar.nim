## Carrier Hangar Capacity Enforcement System
##
## Implements per-carrier hangar capacity limits for fighters embarked on carriers.
##
## Capacity Formula: Based on carrier type and ACO (Advanced Carrier Operations) tech
##
## **Carrier Types and Capacity:**
## - Carrier (CV): 3/4/5 fighter ships at ACO I/II/III
## - Super Carrier (CX): 5/6/8 fighter ships at ACO I/II/III
##
## **IMPORTANT:** Carrier hangar capacity is a hard physical constraint.
## Cannot load fighters beyond available hangar space. No grace period.
##
## Enforcement: Block loading at capacity, check violations during maintenance
## Ownership: Embarked fighters are carrier-owned, don't count against colony limits
##
## Data-oriented design: Calculate capacity (pure), check violations (pure),
## enforce at load time (explicit mutations)

import std/[options, math, tables]
import ../../types/[capacity, core, game_state, ship]
import ../../state/[engine, iterators]
import ../../globals
import ../../../common/logger

export
  capacity.CapacityViolation, capacity.EnforcementAction, capacity.ViolationSeverity

proc isCarrier*(shipClass: ShipClass): bool =
  ## Check if ship class is a carrier
  ## Carriers: CV (Carrier), CX (Super Carrier)
  shipClass == ShipClass.Carrier or shipClass == ShipClass.SuperCarrier

proc getCarrierMaxCapacity*(shipClass: ShipClass, acoLevel: int): int =
  ## Get max hangar capacity for carrier based on ACO tech level
  ## Returns 0 for non-carrier ships
  ##
  ## Reads capacity from gameConfig.tech.aco.levels
  let levelKey = int32(acoLevel)
  let defaultKey = int32(1)

  case shipClass
  of ShipClass.Carrier:
    if gameConfig.tech.aco.levels.hasKey(levelKey):
      return gameConfig.tech.aco.levels[levelKey].cvCapacity.int
    else:
      return gameConfig.tech.aco.levels[defaultKey].cvCapacity.int # Default to ACO I
  of ShipClass.SuperCarrier:
    if gameConfig.tech.aco.levels.hasKey(levelKey):
      return gameConfig.tech.aco.levels[levelKey].cxCapacity.int
    else:
      return gameConfig.tech.aco.levels[defaultKey].cxCapacity.int # Default to ACO I
  else:
    return 0 # Non-carriers have no hangar capacity

proc getCurrentHangarLoad*(ship: Ship): int =
  ## Get current number of fighters embarked on carrier
  ## Pure function - just counts embarkedFighters
  return ship.embarkedFighters.len

proc analyzeCarrierCapacity*(
    state: GameState, shipId: ShipId
): Option[capacity.CapacityViolation] =
  ## Analyze single carrier's hangar capacity
  ## Returns violation if carrier exceeds capacity, none otherwise
  ##
  ## Args:
  ##   state: Game state
  ##   shipId: Ship ID of the carrier
  ##
  ## Returns:
  ##   Some(violation) if over capacity, none otherwise

  let shipOpt = state.ship(shipId)
  if shipOpt.isNone:
    return none(capacity.CapacityViolation)

  let ship = shipOpt.get()

  # Only check carriers
  if not isCarrier(ship.shipClass):
    return none(capacity.CapacityViolation)

  # Get house's ACO tech level
  let houseOpt = state.house(ship.houseId)
  if houseOpt.isNone:
    return none(capacity.CapacityViolation)

  let acoLevel = houseOpt.get().techTree.levels.aco
  let maximum = getCarrierMaxCapacity(ship.shipClass, acoLevel)
  let current = getCurrentHangarLoad(ship)
  let excess = max(0, current - maximum)

  # Carrier hangar has no grace period - immediate critical if over
  let severity =
    if excess == 0:
      capacity.ViolationSeverity.None
    else:
      capacity.ViolationSeverity.Critical

  if severity == capacity.ViolationSeverity.None:
    return none(capacity.CapacityViolation)

  result = some(
    capacity.CapacityViolation(
      capacityType: capacity.CapacityType.CarrierHangar,
      entity: capacity.EntityIdUnion(
        kind: capacity.CapacityType.CarrierHangar, shipId: ship.id
      ),
      current: int32(current),
      maximum: int32(maximum),
      excess: int32(excess),
      severity: severity,
      graceTurnsRemaining: 0, # No grace period
      violationTurn: int32(state.turn),
    )
  )

proc checkViolations*(state: GameState): seq[capacity.CapacityViolation] =
  ## Batch check all carriers across all fleets for hangar capacity violations
  ## Pure function - returns analysis without mutations
  result = @[]

  # Iterate through all ships to find carriers
  for house in state.activeHouses():
    for fleet in state.fleetsOwned(house.id):
      for shipId in fleet.ships:
        let shipOpt = state.ship(shipId)
        if shipOpt.isSome:
          let ship = shipOpt.get()
          if isCarrier(ship.shipClass):
            let violation = analyzeCarrierCapacity(state, shipId)
            if violation.isSome:
              result.add(violation.get())

proc getAvailableHangarSpace*(state: GameState, shipId: ShipId): int =
  ## Get remaining hangar capacity for carrier
  ## Returns: maximum - current
  ## Returns 0 if carrier doesn't exist or is not a carrier
  ##
  ## Used to check if carrier can load additional fighters

  let shipOpt = state.ship(shipId)
  if shipOpt.isNone:
    return 0

  let ship = shipOpt.get()

  # Only carriers have hangar space
  if not isCarrier(ship.shipClass):
    return 0

  # Get house's ACO tech level
  let houseOpt = state.house(ship.houseId)
  if houseOpt.isNone:
    return 0

  let acoLevel = houseOpt.get().techTree.levels.aco
  let maximum = getCarrierMaxCapacity(ship.shipClass, acoLevel)
  let current = getCurrentHangarLoad(ship)

  return max(0, maximum - current)

proc canLoadFighters*(
    state: GameState, shipId: ShipId, fightersToLoad: int
): bool =
  ## Check if carrier has hangar space available to load fighters
  ## Returns true if carrier can accommodate fightersToLoad additional fighters
  ##
  ## Args:
  ##   state: Game state
  ##   shipId: Ship ID of the carrier
  ##   fightersToLoad: Number of fighter ships to load
  ##
  ## Returns:
  ##   true if carrier has enough hangar space, false otherwise

  let availableSpace = getAvailableHangarSpace(state, shipId)
  return availableSpace >= fightersToLoad

proc processCapacityEnforcement*(
    state: var GameState
): seq[capacity.EnforcementAction] =
  ## Main entry point - check all carriers for hangar capacity violations
  ## Called during Maintenance phase
  ##
  ## NOTE: Unlike fighter grace period or capital ship auto-scrap,
  ## carrier hangar violations should NEVER occur because loading is blocked at
  ## capacity. This function exists for consistency and debugging.
  ##
  ## If violations are found, they indicate a bug in the loading system.
  ##
  ## Returns: Empty list (no enforcement actions - violations shouldn't happen)

  result = @[]

  logger.logDebug("Military", "Checking carrier hangar capacity")

  # Check all carriers for violations (should find none)
  let violations = checkViolations(state)

  logger.logDebug("Military", "Carrier check complete", " violations=", $violations.len)

  if violations.len == 0:
    logger.logDebug("Military", "All carriers within hangar capacity limits")
    return

  # Violations should NEVER happen - loading is blocked at capacity
  # If we find violations, log as warnings for debugging
  logger.logWarn(
    "Military", "Carrier hangar violations found (BUG!)", " count=", $violations.len
  )

  for violation in violations:
    logger.logWarn(
      "Military",
      "Carrier over hangar capacity",
      " current=",
      $violation.current,
      " max=",
      $violation.maximum,
      " excess=",
      $violation.excess,
    )

  # No enforcement actions - violations should be prevented at load time
  # We just log them for debugging purposes

## Design Notes:
##
## **Data-Oriented Pattern:**
## 1. getCarrierMaxCapacity() - Pure calculation of max capacity by ACO level
## 2. analyzeCarrierCapacity() - Pure analysis of single carrier status
## 3. checkViolations() - Batch analyze all carriers (pure)
## 4. canLoadFighters() - Pure check if loading is allowed
## 5. processCapacityEnforcement() - Check violations (should find none)
##
## **Key Differences from Other Capacity Systems:**
## - Per-carrier capacity (not per-house or per-colony)
## - Tech-based limit (ACO level determines capacity)
## - Blocking enforcement (reject at load time, not auto-disband)
## - NO grace period (hard physical limit)
## - NO salvage (violations shouldn't occur)
##
## **Spec Compliance:**
## - economy.md:4.13 - ACO tech progression and carrier capacity
## - assets.md:2.4.1 - Carrier mechanics and fighter loading
## - reference.md Table 10.5 - Capacity limits per ACO level
##
## **Integration Points:**
## - Call canLoadFighters(state, shipId, count) before allowing fighter
##   loading operations
## - Call processCapacityEnforcement() in Maintenance phase (debugging only)
## - Use getAvailableHangarSpace(state, shipId) to show available capacity
##   to players
##
## **Special Cases:**
## - ACO tech downgrade: Already-loaded fighters remain (grandfathered)
## - Crippled carriers: Still have full hangar capacity (fighters survive)
## - Carrier destruction: Embarked fighters are lost with the carrier
##
## **Strategic Implications:**
## - Super Carriers (CX) have significantly more capacity than Carriers (CV)
## - ACO tech research immediately upgrades ALL carrier capacities house-wide
## - Players must carefully manage fighter distribution across carriers
## - Embarked fighters don't count against colony capacity (ownership transfer)
