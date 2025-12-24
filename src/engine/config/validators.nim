## Validation Utilities
##
## Reusable validation functions for configuration and parameter validation
## Provides consistent error handling and reporting across the engine
##
## Design:
## - All validators raise ValidationError on failure
## - Configurable severity (warning vs error) where appropriate
## - Clear error messages with actual vs expected values

import std/[math, strformat, logging]

type
  ValidationError* = object of CatchableError ## Exception raised when validation fails

  ValidationSeverity* {.pure.} = enum
    ## Severity level for validation failures
    vWarning ## Log warning but continue execution
    vError ## Raise exception and halt

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
