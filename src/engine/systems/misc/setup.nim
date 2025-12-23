## Game Setup Validation
##
## SINGLE SOURCE OF TRUTH for game setup parameter validation
## All entry points (test harness, moderator, clients) should use validateGameSetup()
##
## Architecture:
## - Orchestrates validation across multiple domain modules
## - Returns structured error list (empty = valid)
## - Delegates domain-specific validation to respective modules
##
## Design Philosophy:
## - Fail fast: Validate before game creation
## - Clear errors: Descriptive messages with context
## - Complete validation: Check all parameters, return all errors
## - Reusable: Works for any entry point

import std/[strformat]
import starmap  # For validateMapRings domain validation

type
  GameSetupParams* = object
    ## Complete set of parameters required to create a game
    numPlayers*: int    ## Number of players (2-12)
    numTurns*: int      ## Number of turns to simulate (1-10000)
    mapRings*: int      ## Map size in rings (1-20, 0 not allowed)
    seed*: int64        ## Random seed for game generation

  SetupValidationError* = object of CatchableError
    ## Exception type for setup validation failures
    ## Use validateGameSetup() instead of raising directly

# Constants for parameter bounds
const
  MIN_PLAYERS* = 2
  MAX_PLAYERS* = 12
  MIN_TURNS* = 1
  MAX_TURNS* = 10000
  MIN_MAP_RINGS* = 1    # Zero rings explicitly not allowed
  MAX_MAP_RINGS* = 20

proc validateGameSetup*(params: GameSetupParams): seq[string] =
  ## Validates all game setup parameters
  ##
  ## Returns:
  ##   Empty seq = all valid
  ##   Non-empty seq = list of validation errors
  ##
  ## Example:
  ##   ```nim
  ##   let params = GameSetupParams(numPlayers: 4, numTurns: 30, mapRings: 3, seed: 42)
  ##   let errors = validateGameSetup(params)
  ##   if errors.len > 0:
  ##     for err in errors:
  ##       echo "Error: ", err
  ##     quit(1)
  ##   ```
  ##
  ## This is the DEFINITIVE validation - all entry points must use this
  var errors: seq[string] = @[]

  # Validate player count
  if params.numPlayers < MIN_PLAYERS or params.numPlayers > MAX_PLAYERS:
    errors.add(&"Invalid player count: {params.numPlayers} (must be {MIN_PLAYERS}-{MAX_PLAYERS})")

  # Validate turn count
  if params.numTurns < MIN_TURNS:
    errors.add(&"Invalid turn count: {params.numTurns} (must be >= {MIN_TURNS})")
  elif params.numTurns > MAX_TURNS:
    errors.add(&"Invalid turn count: {params.numTurns} (must be <= {MAX_TURNS})")

  # Validate map rings - delegate to starmap module (domain owner)
  let mapRingErrors = validateMapRings(params.mapRings, params.numPlayers)
  errors.add(mapRingErrors)

  # Future: Add cross-parameter validation here
  # Example: if params.mapRings < params.numPlayers * minSystemsPerPlayer: ...

  return errors

proc validateGameSetupOrQuit*(params: GameSetupParams, programName: string = "game") =
  ## Convenience function that validates and exits on error
  ## Useful for CLI tools that should fail fast
  ##
  ## Example:
  ##   ```nim
  ##   let params = GameSetupParams(...)
  ##   validateGameSetupOrQuit(params, "run_simulation")
  ##   # Continues only if valid
  ##   ```
  let errors = validateGameSetup(params)
  if errors.len > 0:
    # Keep echo for user-facing CLI error messages
    echo "Invalid game setup parameters:"
    for err in errors:
      echo "  - ", err
    echo ""
    echo "Usage: ", programName, " <turns> <seed> <map_rings> <num_players>"
    echo "  turns:       ", MIN_TURNS, "-", MAX_TURNS
    echo "  map_rings:   ", MIN_MAP_RINGS, "-", MAX_MAP_RINGS, " (0 not allowed)"
    echo "  num_players: ", MIN_PLAYERS, "-", MAX_PLAYERS
    quit(1)
