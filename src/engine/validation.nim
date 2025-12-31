## Centralized Validation Functions
##
## Provides common validation patterns used across the engine.
## Consolidates validation logic to ensure consistency and reduce duplication.
##
## Design Philosophy:
## - Pure functions that return validation results
## - Consistent error message formatting
## - Easy to test and maintain
## - Single source of truth for validation rules

import std/[tables, options, math, strformat]
import ./types/[core, game_state, validation]
import ./state/iterators

####################################################
# Move most of these to applicable systems modules #
####################################################

## Tech Level Validation

proc techLevel*[T](
  levels: Table[int32, T],
  level: int32,
  techName: string,
  minLevel: int32 = 1,
  maxLevel: int32 = 15
): T =
  ## Retrieve tech level data with validation
  ## Raises ValidationError if level is out of bounds or doesn't exist
  ##
  ## Example:
  ##   let data = techLevel(cfg.levels, 5, "EL", 2, 10)
  ##   return data.erpCost
  if level < minLevel or level > maxLevel:
    raise newException(
      ValidationError,
      &"{techName} level must be between {minLevel} and {maxLevel}, got {level}"
    )

  if not levels.hasKey(level):
    raise newException(
      ValidationError,
      &"{techName} level {level} does not exist in configuration"
    )

  return levels[level]

proc success*(): ValidationResult =
  ## Create a successful validation result
  ValidationResult(valid: true, errorMessage: "")

proc failure*(message: string): ValidationResult =
  ## Create a failed validation result with error message
  ValidationResult(valid: false, errorMessage: message)

## House Validation

proc validateHouseExists*(state: GameState, houseId: HouseId): ValidationResult =
  ## Validate that a house exists in the game state
  if houseId notin state.houses:
    return failure("House " & $houseId & " does not exist")
  return success()

proc validateHouseActive*(state: GameState, houseId: HouseId): ValidationResult =
  ## Validate that a house exists and is not eliminated
  let existsCheck = validateHouseExists(state, houseId)
  if not existsCheck.valid:
    return existsCheck

  if state.houses[houseId].eliminated:
    return failure("House " & $houseId & " has been eliminated")
  return success()

proc validateHouseTreasury*(
    state: GameState, houseId: HouseId, requiredAmount: int
): ValidationResult =
  ## Validate that a house has sufficient treasury funds
  let activeCheck = validateHouseActive(state, houseId)
  if not activeCheck.valid:
    return activeCheck

  if state.houses[houseId].treasury < requiredAmount:
    return failure(
      "Insufficient funds: " & $requiredAmount & " PP required, " &
        $state.houses[houseId].treasury & " PP available"
    )
  return success()

## Colony Validation

proc validateColonyExists*(state: GameState, systemId: SystemId): ValidationResult =
  ## Validate that a colony exists at the given system
  if systemId notin state.colonies:
    return failure("No colony exists at system " & $systemId)
  return success()

proc validateColonyOwnership*(
    state: GameState, systemId: SystemId, houseId: HouseId
): ValidationResult =
  ## Validate that a colony exists and is owned by the specified house
  let existsCheck = validateColonyExists(state, systemId)
  if not existsCheck.valid:
    return existsCheck

  if state.colonies[systemId].owner != houseId:
    return failure("Colony at " & $systemId & " is not owned by " & $houseId)
  return success()

proc validateColonyNotBlockaded*(
    state: GameState, systemId: SystemId
): ValidationResult =
  ## Validate that a colony is not currently blockaded
  let existsCheck = validateColonyExists(state, systemId)
  if not existsCheck.valid:
    return existsCheck

  if state.colonies[systemId].blockaded:
    return failure("Colony at " & $systemId & " is blockaded")
  return success()

proc validateColonyPopulation*(
    state: GameState, systemId: SystemId, minPopulation: int
): ValidationResult =
  ## Validate that a colony has sufficient population
  let existsCheck = validateColonyExists(state, systemId)
  if not existsCheck.valid:
    return existsCheck

  let colony = state.colonies[systemId]
  if colony.populationUnits < minPopulation:
    return failure(
      "Insufficient population at " & $systemId & ": " & $minPopulation &
        " PU required, " & $colony.populationUnits & " PU available"
    )
  return success()

## Fleet Validation

proc validateFleetExists*(state: GameState, fleetId: FleetId): ValidationResult =
  ## Validate that a fleet exists in the game state
  if fleetId notin state.fleets:
    return failure("Fleet " & $fleetId & " does not exist")
  return success()

proc validateFleetOwnership*(
    state: GameState, fleetId: FleetId, houseId: HouseId
): ValidationResult =
  ## Validate that a fleet exists and is owned by the specified house
  let existsCheck = validateFleetExists(state, fleetId)
  if not existsCheck.valid:
    return existsCheck

  if state.fleets[fleetId].owner != houseId:
    return failure("Fleet " & $fleetId & " is not owned by " & $houseId)
  return success()

proc validateFleetAtSystem*(
    state: GameState, fleetId: FleetId, systemId: SystemId
): ValidationResult =
  ## Validate that a fleet is at the specified system
  let existsCheck = validateFleetExists(state, fleetId)
  if not existsCheck.valid:
    return existsCheck

  if state.fleets[fleetId].location != systemId:
    return failure("Fleet " & $fleetId & " is not at system " & $systemId)
  return success()

## System Validation

proc validateSystemExists*(state: GameState, systemId: SystemId): ValidationResult =
  ## Validate that a system exists in the star map
  if systemId notin state.starMap.systems:
    return failure("System " & $systemId & " does not exist")
  return success()

proc validatePathExists*(
    state: GameState, fromSystem: SystemId, toSystem: SystemId
): ValidationResult =
  ## Validate that a path exists between two systems
  ## Note: Requires a dummy fleet for pathfinding
  let fromCheck = validateSystemExists(state, fromSystem)
  if not fromCheck.valid:
    return fromCheck

  let toCheck = validateSystemExists(state, toSystem)
  if not toCheck.valid:
    return toCheck

  # Create dummy fleet for pathfinding
  # In real usage, caller should provide actual fleet or use findPath directly
  # This is a simplified check
  if fromSystem == toSystem:
    return success() # Same system is always reachable

  # For general validation, assume path exists if both systems exist
  # Actual pathfinding validation should be done with real fleet data
  return success()

## Resource Validation

proc validateConstructionQueue*(
    state: GameState, systemId: SystemId, maxQueueSize: int
): ValidationResult =
  ## Validate that a colony's construction queue is not full
  let existsCheck = validateColonyExists(state, systemId)
  if not existsCheck.valid:
    return existsCheck

  let colony = state.colonies[systemId]
  if colony.constructionQueue.len >= maxQueueSize:
    return failure(
      "Construction queue at " & $systemId & " is full (" & $maxQueueSize &
        " projects maximum)"
    )
  return success()

proc validateIndustrialCapacity*(
    state: GameState, systemId: SystemId, requiredIU: int
): ValidationResult =
  ## Validate that a colony has sufficient industrial units
  let existsCheck = validateColonyExists(state, systemId)
  if not existsCheck.valid:
    return existsCheck

  let colony = state.colonies[systemId]
  if colony.industrial.units < requiredIU:
    return failure(
      "Insufficient industrial capacity at " & $systemId & ": " & $requiredIU &
        " IU required, " & $colony.industrial.units & " IU available"
    )
  return success()

## Composite Validations
## These combine multiple checks for common scenarios

proc validateCanBuildAtColony*(
    state: GameState, houseId: HouseId, systemId: SystemId, cost: int
): ValidationResult =
  ## Validate that a house can build at a colony
  ## Checks: house active, colony ownership, sufficient funds

  let houseCheck = validateHouseActive(state, houseId)
  if not houseCheck.valid:
    return houseCheck

  let ownershipCheck = validateColonyOwnership(state, systemId, houseId)
  if not ownershipCheck.valid:
    return ownershipCheck

  let treasuryCheck = validateHouseTreasury(state, houseId, cost)
  if not treasuryCheck.valid:
    return treasuryCheck

  return success()

proc validateCanTransferPopulation*(
    state: GameState,
    houseId: HouseId,
    sourceSystem: SystemId,
    destSystem: SystemId,
    ptuAmount: int,
    minRetainedPU: int = 1,
): ValidationResult =
  ## Validate that a house can transfer population between systems
  ## Checks: house active, source ownership, destination exists, sufficient population

  let houseCheck = validateHouseActive(state, houseId)
  if not houseCheck.valid:
    return houseCheck

  let sourceCheck = validateColonyOwnership(state, sourceSystem, houseId)
  if not sourceCheck.valid:
    return sourceCheck

  let destCheck = validateSystemExists(state, destSystem)
  if not destCheck.valid:
    return destCheck

  # Check source has sufficient population (must retain minimum)
  let sourceColony = state.colonies[sourceSystem]
  if sourceColony.populationUnits - ptuAmount < minRetainedPU:
    return failure("Source colony must retain at least " & $minRetainedPU & " PU")

  return success()

proc validateCanMoveFleet*(
    state: GameState, houseId: HouseId, fleetId: FleetId, targetSystem: SystemId
): ValidationResult =
  ## Validate that a fleet can be moved to a target system
  ## Checks: house active, fleet ownership, target system exists

  let houseCheck = validateHouseActive(state, houseId)
  if not houseCheck.valid:
    return houseCheck

  let fleetCheck = validateFleetOwnership(state, fleetId, houseId)
  if not fleetCheck.valid:
    return fleetCheck

  let systemCheck = validateSystemExists(state, targetSystem)
  if not systemCheck.valid:
    return systemCheck

  return success()

## Helper Functions

proc isValid*(vr: ValidationResult): bool =
  ## Check if a validation result is valid (convenience function)
  return vr.valid

proc getError*(vr: ValidationResult): string =
  ## Get error message from validation result (convenience function)
  return vr.errorMessage

proc validateAll*(checks: seq[ValidationResult]): ValidationResult =
  ## Validate multiple checks - fails on first failure
  ## Returns first error encountered or success if all pass
  for check in checks:
    if not check.valid:
      return check
  return success()

proc validateRange*(
    value: int, min, max: int, fieldName: string, severity = ValidationSeverity.vError
) =
  ## Validates that a value is within the specified range [min, max]
  ##
  ## Example:
  ##   validateRange(5, 1, 10, "player_count")  # OK
  ##   validateRange(0, 1, 10, "player_count")  # Raises ValidationError
  if value < min or value > max:
    let msg = &"{fieldName} must be between {min} and {max}, got {value}"
    case severity
    of ValidationSeverity.vWarning:
      warn msg
    of ValidationSeverity.vError:
      raise newException(ValidationError, msg)

proc validateRange*(
    value: float,
    min, max: float,
    fieldName: string,
    severity = ValidationSeverity.vError,
) =
  ## Validates that a float value is within the specified range [min, max]
  if value < min or value > max:
    let msg = &"{fieldName} must be between {min} and {max}, got {value}"
    case severity
    of ValidationSeverity.vWarning:
      warn msg
    of ValidationSeverity.vError:
      raise newException(ValidationError, msg)

proc validatePositive*(value: int, fieldName: string) =
  ## Validates that a value is strictly positive (> 0)
  ##
  ## Example:
  ##   validatePositive(10, "build_cost")     # OK
  ##   validatePositive(0, "build_cost")      # Raises ValidationError
  if value <= 0:
    raise newException(ValidationError, &"{fieldName} must be positive, got {value}")

proc validatePositive*(value: float, fieldName: string) =
  ## Validates that a float value is strictly positive (> 0)
  if value <= 0.0:
    raise newException(ValidationError, &"{fieldName} must be positive, got {value}")

proc validateNonNegative*(value: int, fieldName: string) =
  ## Validates that a value is non-negative (>= 0)
  ##
  ## Example:
  ##   validateNonNegative(0, "upkeep_cost")   # OK
  ##   validateNonNegative(-5, "upkeep_cost")  # Raises ValidationError
  if value < 0:
    raise
      newException(ValidationError, &"{fieldName} must be non-negative, got {value}")

proc validateNonNegative*(value: float, fieldName: string) =
  ## Validates that a float value is non-negative (>= 0)
  if value < 0.0:
    raise
      newException(ValidationError, &"{fieldName} must be non-negative, got {value}")

proc validateRatio*(
    value: float, fieldName: string, severity = ValidationSeverity.vError
) =
  ## Validates that a value is a valid ratio between 0.0 and 1.0
  ##
  ## Example:
  ##   validateRatio(0.5, "aggression")      # OK
  ##   validateRatio(1.5, "aggression")      # Raises ValidationError
  if value < 0.0 or value > 1.0:
    let msg = &"{fieldName} must be between 0.0 and 1.0, got {value}"
    case severity
    of ValidationSeverity.vWarning:
      warn msg
    of ValidationSeverity.vError:
      raise newException(ValidationError, msg)

proc validateSumToOne*(
    values: openArray[float],
    tolerance = 0.01,
    context: string,
    severity = ValidationSeverity.vError,
) =
  ## Validates that a set of values sum to approximately 1.0
  ## Allows for small floating-point rounding errors via tolerance
  ##
  ## Example:
  ##   validateSumToOne([0.33, 0.33, 0.34], context="splits")  # OK
  ##   validateSumToOne([0.5, 0.5, 0.5], context="splits")     # Raises ValidationError
  var total = 0.0
  for v in values:
    total += v

  if abs(total - 1.0) > tolerance:
    let msg = &"{context} must sum to 1.0 (got {total}, tolerance {tolerance})"
    case severity
    of ValidationSeverity.vWarning:
      warn msg
    of ValidationSeverity.vError:
      raise newException(ValidationError, msg)

proc validateMinLessThanMax*(min, max: int, fieldName: string) =
  ## Validates that min < max for a range definition
  ##
  ## Example:
  ##   validateMinLessThanMax(1, 10, "pu_range")    # OK
  ##   validateMinLessThanMax(10, 5, "pu_range")    # Raises ValidationError
  if min >= max:
    raise newException(
      ValidationError, &"{fieldName}: min ({min}) must be less than max ({max})"
    )

proc validateMinLessThanMax*(min, max: float, fieldName: string) =
  ## Validates that min < max for a float range definition
  if min >= max:
    raise newException(
      ValidationError, &"{fieldName}: min ({min}) must be less than max ({max})"
    )

proc validatePercentage*(value: float, fieldName: string) =
  ## Validates that a value is a valid percentage (0.0 to 100.0)
  ## Note: For ratios (0.0 to 1.0), use validateRatio instead
  if value < 0.0 or value > 100.0:
    raise newException(
      ValidationError, &"{fieldName} must be between 0.0 and 100.0, got {value}"
    )

## Design Notes:
##
## **Usage Pattern:**
## ```nim
## let validation = validateCanBuildAtColony(state, houseId, systemId, cost)
## if not validation.valid:
##   echo "Error: ", validation.errorMessage
##   return
## ```
##
## **Benefits:**
## - Consistent validation across engine
## - Clear error messages
## - Easy to test (pure functions)
## - Composable (validateAll for multiple checks)
## - Single source of truth for validation rules
##
## **Design Philosophy:**
## - Pure functions (no side effects)
## - Return structured results (not bool + out param)
## - Consistent error message formatting
## - Composite functions for common scenarios
