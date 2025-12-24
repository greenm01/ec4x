## Carrier Hangar Capacity Enforcement System
##
## Implements per-carrier hangar capacity limits for fighters embarked on carriers.
##
## Capacity Formula: Based on carrier type and ACO (Advanced Carrier Operations) tech
##
## **Carrier Types and Capacity:**
## - Carrier (CV): 3/4/5 fighter squadrons at ACO I/II/III
## - Super Carrier (CX): 5/6/8 fighter squadrons at ACO I/II/III
##
## **IMPORTANT:** Carrier hangar capacity is a hard physical constraint.
## Cannot load fighters beyond available hangar space. No grace period.
##
## Enforcement: Block loading at capacity, check violations during maintenance
## Ownership: Embarked fighters are carrier-owned, don't count against colony limits
##
## Data-oriented design: Calculate capacity (pure), check violations (pure),
## enforce at load time (explicit mutations)

import std/[options, math]
import ../../types/[capacity, core, game_state, squadron, ship]
import ../../state/[game_state as gs_helpers, iterators]
import ../../config/tech_config
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
  ## Reads capacity from globalTechConfig.advanced_carrier_operations
  let cfg = globalTechConfig.advanced_carrier_operations

  case shipClass
  of ShipClass.Carrier:
    case acoLevel
    of 1:
      return cfg.level_1_cv_capacity.int
    of 2:
      return cfg.level_2_cv_capacity.int
    of 3:
      return cfg.level_3_cv_capacity.int
    else:
      return cfg.level_1_cv_capacity.int # Default to ACO I
  of ShipClass.SuperCarrier:
    case acoLevel
    of 1:
      return cfg.level_1_cx_capacity.int
    of 2:
      return cfg.level_2_cx_capacity.int
    of 3:
      return cfg.level_3_cx_capacity.int
    else:
      return cfg.level_1_cx_capacity.int # Default to ACO I
  else:
    return 0 # Non-carriers have no hangar capacity

proc getCurrentHangarLoad*(squadron: Squadron): int =
  ## Get current number of fighters embarked on carrier
  ## Pure function - just counts embarkedFighters
  return squadron.embarkedFighters.len

proc analyzeCarrierCapacity*(
    state: GameState, squadronId: SquadronId
): Option[capacity.CapacityViolation] =
  ## Analyze single carrier's hangar capacity
  ## Returns violation if carrier exceeds capacity, none otherwise
  ##
  ## Args:
  ##   state: Game state
  ##   squadronId: Squadron ID of the carrier
  ##
  ## Returns:
  ##   Some(violation) if over capacity, none otherwise

  let squadronOpt = gs_helpers.getSquadrons(state, squadronId)
  if squadronOpt.isNone:
    return none(capacity.CapacityViolation)

  let squadron = squadronOpt.get()

  # Get flagship ship to check if carrier
  let flagshipOpt = gs_helpers.getShip(state, squadron.flagshipId)
  if flagshipOpt.isNone:
    return none(capacity.CapacityViolation)

  let flagship = flagshipOpt.get()

  # Only check carriers
  if not isCarrier(flagship.shipClass):
    return none(capacity.CapacityViolation)

  # Get house's ACO tech level
  let houseOpt = gs_helpers.getHouse(state, squadron.houseId)
  if houseOpt.isNone:
    return none(capacity.CapacityViolation)

  let acoLevel = houseOpt.get().techTree.levels.advancedCarrierOps
  let maximum = getCarrierMaxCapacity(flagship.shipClass, acoLevel)
  let current = getCurrentHangarLoad(squadron)
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
        kind: capacity.CapacityType.CarrierHangar, shipId: flagship.id
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

  # Iterate through all active houses and their squadrons
  for house in state.activeHouses():
    for squadron in state.squadronsOwned(house.id):
      # Get flagship to check if carrier
      let flagshipOpt = gs_helpers.getShip(state, squadron.flagshipId)
      if flagshipOpt.isSome:
        let flagship = flagshipOpt.get()
        if isCarrier(flagship.shipClass):
          let violation = analyzeCarrierCapacity(state, squadron.id)
          if violation.isSome:
            result.add(violation.get())

proc getAvailableHangarSpace*(state: GameState, squadronId: SquadronId): int =
  ## Get remaining hangar capacity for carrier
  ## Returns: maximum - current
  ## Returns 0 if carrier doesn't exist or is not a carrier
  ##
  ## Used to check if carrier can load additional fighters

  let squadronOpt = gs_helpers.getSquadrons(state, squadronId)
  if squadronOpt.isNone:
    return 0

  let squadron = squadronOpt.get()

  # Get flagship ship to check if carrier
  let flagshipOpt = gs_helpers.getShip(state, squadron.flagshipId)
  if flagshipOpt.isNone:
    return 0

  let flagship = flagshipOpt.get()

  # Only carriers have hangar space
  if not isCarrier(flagship.shipClass):
    return 0

  # Get house's ACO tech level
  let houseOpt = gs_helpers.getHouse(state, squadron.houseId)
  if houseOpt.isNone:
    return 0

  let acoLevel = houseOpt.get().techTree.levels.advancedCarrierOps
  let maximum = getCarrierMaxCapacity(flagship.shipClass, acoLevel)
  let current = getCurrentHangarLoad(squadron)

  return max(0, maximum - current)

proc canLoadFighters*(
    state: GameState, squadronId: SquadronId, fightersToLoad: int
): bool =
  ## Check if carrier has hangar space available to load fighters
  ## Returns true if carrier can accommodate fightersToLoad additional fighters
  ##
  ## Args:
  ##   state: Game state
  ##   squadronId: Squadron ID of the carrier
  ##   fightersToLoad: Number of fighter squadrons to load
  ##
  ## Returns:
  ##   true if carrier has enough hangar space, false otherwise

  let availableSpace = getAvailableHangarSpace(state, squadronId)
  return availableSpace >= fightersToLoad

proc processCapacityEnforcement*(
    state: var GameState
): seq[capacity.EnforcementAction] =
  ## Main entry point - check all carriers for hangar capacity violations
  ## Called during Maintenance phase
  ##
  ## NOTE: Unlike fighter squadron grace period or capital squadron auto-scrap,
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
## - Call canLoadFighters(state, squadronId, count) before allowing fighter
##   loading operations
## - Call processCapacityEnforcement() in Maintenance phase (debugging only)
## - Use getAvailableHangarSpace(state, squadronId) to show available capacity
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
