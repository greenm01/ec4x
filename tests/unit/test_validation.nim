## Unit Tests for Validation System
##
## Tests all validation utilities and game setup validation

import unittest
import std/strutils
import ../../src/engine/config/validators
import ../../src/engine/[setup, starmap]

suite "Validator Utilities":
  test "validateRange - valid integer":
    # Should not raise
    validateRange(5, 1, 10, "test_value")

  test "validateRange - too low":
    expect ValidationError:
      validateRange(0, 1, 10, "test_value")

  test "validateRange - too high":
    expect ValidationError:
      validateRange(11, 1, 10, "test_value")

  test "validateRange - valid float":
    validateRange(0.5, 0.0, 1.0, "test_ratio")
    # Should not raise

  test "validateRange - float out of bounds":
    expect ValidationError:
      validateRange(1.5, 0.0, 1.0, "test_ratio")

  test "validatePositive - valid":
    validatePositive(10, "test_value")
    validatePositive(1, "test_value")
    # Should not raise

  test "validatePositive - zero fails":
    expect ValidationError:
      validatePositive(0, "test_value")

  test "validatePositive - negative fails":
    expect ValidationError:
      validatePositive(-5, "test_value")

  test "validateNonNegative - valid":
    validateNonNegative(0, "test_value")
    validateNonNegative(10, "test_value")
    # Should not raise

  test "validateNonNegative - negative fails":
    expect ValidationError:
      validateNonNegative(-1, "test_value")

  test "validateRatio - valid values":
    validateRatio(0.0, "ratio")
    validateRatio(0.5, "ratio")
    validateRatio(1.0, "ratio")
    # Should not raise

  test "validateRatio - below zero fails":
    expect ValidationError:
      validateRatio(-0.1, "ratio")

  test "validateRatio - above one fails":
    expect ValidationError:
      validateRatio(1.1, "ratio")

  test "validateSumToOne - exact sum":
    validateSumToOne([0.25, 0.25, 0.25, 0.25], context="test_splits")
    # Should not raise

  test "validateSumToOne - within tolerance":
    validateSumToOne([0.33, 0.33, 0.34], tolerance=0.01, context="test_splits")
    # Should not raise

  test "validateSumToOne - outside tolerance":
    expect ValidationError:
      validateSumToOne([0.5, 0.5, 0.5], context="test_splits")

  test "validateSumToOne - way off":
    expect ValidationError:
      validateSumToOne([0.1, 0.1, 0.1], context="test_splits")

  test "validateMinLessThanMax - valid":
    validateMinLessThanMax(1, 10, "range")
    # Should not raise

  test "validateMinLessThanMax - min equals max fails":
    expect ValidationError:
      validateMinLessThanMax(5, 5, "range")

  test "validateMinLessThanMax - min greater than max fails":
    expect ValidationError:
      validateMinLessThanMax(10, 5, "range")

suite "Game Setup Validation":
  test "validateGameSetup - all valid":
    let params = GameSetupParams(
      numPlayers: 4,
      numTurns: 30,
      mapRings: 3,
      seed: 42
    )
    let errors = validateGameSetup(params)
    check errors.len == 0

  test "validateGameSetup - zero rings fails":
    let params = GameSetupParams(
      numPlayers: 4,
      numTurns: 30,
      mapRings: 0,
      seed: 42
    )
    let errors = validateGameSetup(params)
    check errors.len > 0
    check "zero rings" in errors[0].toLower()

  test "validateGameSetup - zero turns fails":
    let params = GameSetupParams(
      numPlayers: 4,
      numTurns: 0,
      mapRings: 3,
      seed: 42
    )
    let errors = validateGameSetup(params)
    check errors.len > 0
    check "turn" in errors[0].toLower()

  test "validateGameSetup - too many turns fails":
    let params = GameSetupParams(
      numPlayers: 4,
      numTurns: 99999,
      mapRings: 3,
      seed: 42
    )
    let errors = validateGameSetup(params)
    check errors.len > 0

  test "validateGameSetup - too few players fails":
    let params = GameSetupParams(
      numPlayers: 1,
      numTurns: 30,
      mapRings: 3,
      seed: 42
    )
    let errors = validateGameSetup(params)
    check errors.len > 0
    check "player" in errors[0].toLower()

  test "validateGameSetup - too many players fails":
    let params = GameSetupParams(
      numPlayers: 13,
      numTurns: 30,
      mapRings: 3,
      seed: 42
    )
    let errors = validateGameSetup(params)
    check errors.len > 0
    check "player" in errors[0].toLower()

  test "validateGameSetup - negative rings fails":
    let params = GameSetupParams(
      numPlayers: 4,
      numTurns: 30,
      mapRings: -1,
      seed: 42
    )
    let errors = validateGameSetup(params)
    check errors.len > 0

  test "validateGameSetup - too many rings fails":
    let params = GameSetupParams(
      numPlayers: 4,
      numTurns: 30,
      mapRings: 99,
      seed: 42
    )
    let errors = validateGameSetup(params)
    check errors.len > 0

  test "validateGameSetup - minimum valid values":
    let params = GameSetupParams(
      numPlayers: MIN_PLAYERS,
      numTurns: MIN_TURNS,
      mapRings: MIN_MAP_RINGS,
      seed: 1
    )
    let errors = validateGameSetup(params)
    check errors.len == 0

  test "validateGameSetup - maximum valid values":
    let params = GameSetupParams(
      numPlayers: MAX_PLAYERS,
      numTurns: MAX_TURNS,
      mapRings: MAX_MAP_RINGS,
      seed: 999999
    )
    let errors = validateGameSetup(params)
    check errors.len == 0

  test "validateGameSetup - flexible map/player combinations":
    # User requirement: Allow 2 players on large map
    let params = GameSetupParams(
      numPlayers: 2,
      numTurns: 30,
      mapRings: 12,
      seed: 42
    )
    let errors = validateGameSetup(params)
    check errors.len == 0

  test "validateGameSetup - multiple errors reported":
    let params = GameSetupParams(
      numPlayers: 0,
      numTurns: 0,
      mapRings: 0,
      seed: 42
    )
    let errors = validateGameSetup(params)
    check errors.len >= 3  # Should report all three errors

suite "Map Rings Domain Validation":
  test "validateMapRings - valid values":
    let errors = validateMapRings(3, 4)
    check errors.len == 0

  test "validateMapRings - zero fails":
    let errors = validateMapRings(0, 4)
    check errors.len > 0
    check "zero" in errors[0].toLower()

  test "validateMapRings - negative fails":
    let errors = validateMapRings(-1, 4)
    check errors.len > 0

  test "validateMapRings - too many fails":
    let errors = validateMapRings(99, 4)
    check errors.len > 0

  test "validateMapRings - minimum valid":
    let errors = validateMapRings(1, 2)
    check errors.len == 0

  test "validateMapRings - maximum valid":
    let errors = validateMapRings(20, 4)
    check errors.len == 0

  test "validateMapRings - no player count requirement":
    # User requirement: Allow flexible combinations
    let errors = validateMapRings(2, 10)
    check errors.len == 0  # Small map, many players - should be OK

when isMainModule:
  echo "Running validation tests..."
