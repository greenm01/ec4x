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

import std/[tables, strutils, options, math]
import ./types
import ../../gamestate
import ../../squadron
import ../types as econ_types
import ../../../common/types/core
import ../../../common/types/units
import ../../../common/logger

export types.CapacityViolation, types.EnforcementAction, types.ViolationSeverity

proc isCarrier*(shipClass: ShipClass): bool =
  ## Check if ship class is a carrier
  ## Carriers: CV (Carrier), CX (Super Carrier)
  shipClass == ShipClass.Carrier or shipClass == ShipClass.SuperCarrier

proc getCarrierMaxCapacity*(shipClass: ShipClass, acoLevel: int): int =
  ## Get max hangar capacity for carrier based on ACO tech level
  ## Returns 0 for non-carrier ships
  ##
  ## Capacity Table (from economy.md:4.13 and assets.md:2.4.1):
  ## - CV at ACO I: 3 FS
  ## - CV at ACO II: 4 FS
  ## - CV at ACO III: 5 FS
  ## - CX at ACO I: 5 FS
  ## - CX at ACO II: 6 FS
  ## - CX at ACO III: 8 FS
  case shipClass
  of ShipClass.Carrier:
    case acoLevel
    of 1: return 3
    of 2: return 4
    of 3: return 5
    else: return 3  # Default to ACO I if invalid level
  of ShipClass.SuperCarrier:
    case acoLevel
    of 1: return 5
    of 2: return 6
    of 3: return 8
    else: return 5  # Default to ACO I if invalid level
  else:
    return 0  # Non-carriers have no hangar capacity

proc getCurrentHangarLoad*(squadron: Squadron): int =
  ## Get current number of fighters embarked on carrier
  ## Pure function - just counts embarkedFighters
  return squadron.embarkedFighters.len

proc analyzeCarrierCapacity*(state: GameState, fleetId: core.FleetId,
                              squadronIdx: int): Option[types.CapacityViolation] =
  ## Analyze single carrier's hangar capacity
  ## Returns violation if carrier exceeds capacity, none otherwise
  ##
  ## Args:
  ##   state: Game state
  ##   fleetId: Fleet containing the carrier
  ##   squadronIdx: Index of squadron in fleet.squadrons
  ##
  ## Returns:
  ##   Some(violation) if over capacity, none otherwise

  if not state.fleets.hasKey(fleetId):
    return none(types.CapacityViolation)

  let fleet = state.fleets[fleetId]
  if squadronIdx < 0 or squadronIdx >= fleet.squadrons.len:
    return none(types.CapacityViolation)

  let squadron = fleet.squadrons[squadronIdx]

  # Only check carriers
  if not isCarrier(squadron.flagship.shipClass):
    return none(types.CapacityViolation)

  # Get house's ACO tech level
  if not state.houses.hasKey(fleet.owner):
    return none(types.CapacityViolation)

  let acoLevel = state.houses[fleet.owner].techTree.levels.advancedCarrierOps
  let maximum = getCarrierMaxCapacity(squadron.flagship.shipClass, acoLevel)
  let current = getCurrentHangarLoad(squadron)
  let excess = max(0, current - maximum)

  # Carrier hangar has no grace period - immediate critical if over
  let severity = if excess == 0:
                   ViolationSeverity.None
                 else:
                   ViolationSeverity.Critical

  if severity == ViolationSeverity.None:
    return none(types.CapacityViolation)

  result = some(types.CapacityViolation(
    capacityType: CapacityType.CarrierHangar,
    entityId: squadron.id,  # Violation is per-carrier
    current: current,
    maximum: maximum,
    excess: excess,
    severity: severity,
    graceTurnsRemaining: 0,  # No grace period
    violationTurn: state.turn
  ))

proc checkViolations*(state: GameState): seq[types.CapacityViolation] =
  ## Batch check all carriers across all fleets for hangar capacity violations
  ## Pure function - returns analysis without mutations
  result = @[]

  for fleetId, fleet in state.fleets:
    for idx, squadron in fleet.squadrons:
      if isCarrier(squadron.flagship.shipClass):
        let violation = analyzeCarrierCapacity(state, fleetId, idx)
        if violation.isSome:
          result.add(violation.get())

proc getAvailableHangarSpace*(state: GameState, fleetId: core.FleetId,
                               squadronIdx: int): int =
  ## Get remaining hangar capacity for carrier
  ## Returns: maximum - current
  ## Returns 0 if carrier doesn't exist or is not a carrier
  ##
  ## Used to check if carrier can load additional fighters

  if not state.fleets.hasKey(fleetId):
    return 0

  let fleet = state.fleets[fleetId]
  if squadronIdx < 0 or squadronIdx >= fleet.squadrons.len:
    return 0

  let squadron = fleet.squadrons[squadronIdx]

  # Only carriers have hangar space
  if not isCarrier(squadron.flagship.shipClass):
    return 0

  # Get house's ACO tech level
  if not state.houses.hasKey(fleet.owner):
    return 0

  let acoLevel = state.houses[fleet.owner].techTree.levels.advancedCarrierOps
  let maximum = getCarrierMaxCapacity(squadron.flagship.shipClass, acoLevel)
  let current = getCurrentHangarLoad(squadron)

  return max(0, maximum - current)

proc canLoadFighters*(state: GameState, fleetId: core.FleetId,
                      squadronIdx: int, fightersToLoad: int): bool =
  ## Check if carrier has hangar space available to load fighters
  ## Returns true if carrier can accommodate fightersToLoad additional fighters
  ##
  ## Args:
  ##   state: Game state
  ##   fleetId: Fleet containing the carrier
  ##   squadronIdx: Index of squadron in fleet.squadrons
  ##   fightersToLoad: Number of fighter squadrons to load
  ##
  ## Returns:
  ##   true if carrier has enough hangar space, false otherwise

  let availableSpace = getAvailableHangarSpace(state, fleetId, squadronIdx)
  return availableSpace >= fightersToLoad

proc findCarrierBySquadronId*(state: GameState, squadronId: string): Option[tuple[fleetId: core.FleetId, squadronIdx: int]] =
  ## Find fleet and squadron index for a carrier by squadron ID
  ## Helper function for operations that reference carriers by ID
  ##
  ## Returns: Some((fleetId, squadronIdx)) if found, none otherwise

  for fleetId, fleet in state.fleets:
    for idx, squadron in fleet.squadrons:
      if squadron.id == squadronId:
        return some((fleetId, idx))

  return none(tuple[fleetId: core.FleetId, squadronIdx: int])

proc getAvailableHangarSpaceById*(state: GameState, squadronId: string): int =
  ## Get available hangar space for carrier by squadron ID
  ## Convenience wrapper around getAvailableHangarSpace
  ##
  ## Returns: Available hangar space, or 0 if carrier not found

  let carrierLocation = findCarrierBySquadronId(state, squadronId)
  if carrierLocation.isNone:
    return 0

  let (fleetId, squadronIdx) = carrierLocation.get()
  return getAvailableHangarSpace(state, fleetId, squadronIdx)

proc canLoadFightersById*(state: GameState, squadronId: string,
                          fightersToLoad: int): bool =
  ## Check if carrier can load fighters by squadron ID
  ## Convenience wrapper around canLoadFighters
  ##
  ## Returns: true if carrier has space, false otherwise

  let carrierLocation = findCarrierBySquadronId(state, squadronId)
  if carrierLocation.isNone:
    return false

  let (fleetId, squadronIdx) = carrierLocation.get()
  return canLoadFighters(state, fleetId, squadronIdx, fightersToLoad)

proc processCapacityEnforcement*(state: var GameState): seq[types.EnforcementAction] =
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

  logDebug("Military", "Checking carrier hangar capacity",
           " fleets=", $state.fleets.len)

  # Check all carriers for violations (should find none)
  let violations = checkViolations(state)

  logDebug("Military", "Carrier check complete", " violations=", $violations.len)

  if violations.len == 0:
    logDebug("Military", "All carriers within hangar capacity limits")
    return

  # Violations should NEVER happen - loading is blocked at capacity
  # If we find violations, log as warnings for debugging
  logWarn("Military", "Carrier hangar violations found (BUG!)", "count=", $violations.len)

  for violation in violations:
    logWarn("Military",
           "Carrier over hangar capacity",
           " carrier=", violation.entityId,
           " current=", $violation.current,
           " max=", $violation.maximum,
           " excess=", $violation.excess)

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
## - Call canLoadFighters() before allowing fighter loading operations
## - Call processCapacityEnforcement() in Maintenance phase (debugging only)
## - Use getAvailableHangarSpace() to show available capacity to players
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
