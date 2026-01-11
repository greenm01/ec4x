## Stress Test Framework
##
## Core infrastructure for stress testing the EC4X engine
## Provides:
## - Anomaly detection and invariant checking
## - Long-running simulation infrastructure
## - Statistical analysis for unknown-unknowns
## - Performance monitoring and regression detection
##
## Updated for new engine architecture (2026-01)

import std/[tables, strformat, sequtils, strutils, sets]
import ../../src/engine/types/[core, game_state, house, colony, fleet]
import ../../src/engine/state/[engine, iterators]

type
  InvariantViolation* = object
    ## Detected violation of a game state invariant
    turn*: int
    severity*: ViolationSeverity
    category*: string
    description*: string
    details*: Table[string, string]

  ViolationSeverity* {.pure.} = enum
    Warning   # Suspicious but maybe valid
    Error     # Clear bug - invalid state
    Critical  # Game-breaking corruption

  StressTestResult* = object
    ## Results from a stress test run
    testName*: string
    turnsCompleted*: int
    violations*: seq[InvariantViolation]
    crashed*: bool
    crashReason*: string
    metrics*: Table[string, float]

  StateInvariants* = object
    ## Tracks invariants that must always hold
    checkTreasury*: bool           # Treasury should never be negative (except controlled debt)
    checkFleetLocations*: bool     # Fleets must be at valid system IDs
    checkOwnership*: bool          # All entities owned by valid houses
    checkPrestigeRange*: bool      # Prestige should be bounded
    checkTechLevelRange*: bool     # Tech levels in valid range
    checkColonyPopulation*: bool   # Population should be non-negative

proc newInvariantViolation*(
    turn: int,
    severity: ViolationSeverity,
    category, description: string,
    details: Table[string, string] = initTable[string, string]()
): InvariantViolation =
  ## Create a new invariant violation
  InvariantViolation(
    turn: turn,
    severity: severity,
    category: category,
    description: description,
    details: details
  )

proc defaultInvariants*(): StateInvariants =
  ## Get default invariant checks (all enabled)
  StateInvariants(
    checkTreasury: true,
    checkFleetLocations: true,
    checkOwnership: true,
    checkPrestigeRange: true,
    checkTechLevelRange: true,
    checkColonyPopulation: true
  )

proc checkStateInvariants*(
    state: GameState,
    turn: int,
    invariants: StateInvariants = defaultInvariants()
): seq[InvariantViolation] =
  ## Check all game state invariants and return violations
  ## Updated for new entity manager architecture
  var violations: seq[InvariantViolation] = @[]

  # Build valid house IDs set (includes eliminated houses - they still exist)
  var validHouses: HashSet[HouseId]
  for (houseId, _) in state.allHousesWithId():
    validHouses.incl(houseId)

  # Build valid system IDs set
  var validSystems: HashSet[SystemId]
  for (systemId, _) in state.allSystemsWithId():
    validSystems.incl(systemId)

  # Check each house
  for (houseId, house) in state.activeHousesWithId():
    # Treasury checks
    if invariants.checkTreasury:
      # Allow controlled negative treasury for maintenance shortfall scenarios
      # But extremely negative values (< -10000 PP) are suspicious
      if house.treasury < -10_000:
        var details = initTable[string, string]()
        details["house"] = $houseId
        details["treasury"] = $house.treasury
        violations.add(newInvariantViolation(
          turn, ViolationSeverity.Error,
          "Treasury",
          &"House {houseId} has extremely negative treasury: {house.treasury} PP",
          details
        ))

    # Prestige checks
    if invariants.checkPrestigeRange:
      # Prestige can go negative (defensive collapse) but should have reasonable bounds
      # Suspect if prestige > 10000 or < -1000
      if house.prestige > 10_000:
        var details = initTable[string, string]()
        details["house"] = $houseId
        details["prestige"] = $house.prestige
        violations.add(newInvariantViolation(
          turn, ViolationSeverity.Warning,
          "Prestige",
          &"House {houseId} has extremely high prestige: {house.prestige}",
          details
        ))
      elif house.prestige < -1000:
        var details = initTable[string, string]()
        details["house"] = $houseId
        details["prestige"] = $house.prestige
        violations.add(newInvariantViolation(
          turn, ViolationSeverity.Warning,
          "Prestige",
          &"House {houseId} has extremely negative prestige: {house.prestige}",
          details
        ))

    # Tech level checks
    if invariants.checkTechLevelRange:
      # Tech levels should be in range 0-15 (some can go above 10 per spec)
      let allTechLevels = [
        ("CST", house.techTree.levels.cst),
        ("WEP", house.techTree.levels.wep),
        ("EL", house.techTree.levels.el),
        ("SL", house.techTree.levels.sl),
        ("TER", house.techTree.levels.ter),
        ("ELI", house.techTree.levels.eli),
        ("CLK", house.techTree.levels.clk),
        ("SLD", house.techTree.levels.sld),
        ("CIC", house.techTree.levels.cic),
        ("FD", house.techTree.levels.fd),
        ("ACO", house.techTree.levels.aco)
      ]

      for (fieldName, level) in allTechLevels:
        if level < 0 or level > 20:
          var details = initTable[string, string]()
          details["house"] = $houseId
          details["field"] = fieldName
          details["level"] = $level
          violations.add(newInvariantViolation(
            turn, ViolationSeverity.Error,
            "TechLevel",
            &"House {houseId} has invalid {fieldName} tech level: {level}",
            details
          ))

  # Check colonies
  for (colonyId, colony) in state.allColoniesWithId():
    # System ID validity
    if invariants.checkFleetLocations:
      if colony.systemId notin validSystems:
        var details = initTable[string, string]()
        details["colonyId"] = $colonyId
        details["systemId"] = $colony.systemId
        details["owner"] = $colony.owner
        violations.add(newInvariantViolation(
          turn, ViolationSeverity.Critical,
          "InvalidLocation",
          &"Colony {colonyId} at invalid system ID: {colony.systemId}",
          details
        ))

    # Owner validity
    if invariants.checkOwnership:
      if colony.owner notin validHouses:
        var details = initTable[string, string]()
        details["colonyId"] = $colonyId
        details["owner"] = $colony.owner
        violations.add(newInvariantViolation(
          turn, ViolationSeverity.Critical,
          "InvalidOwner",
          &"Colony {colonyId} owned by non-existent house: {colony.owner}",
          details
        ))

    # Population consistency
    if invariants.checkColonyPopulation:
      if colony.populationUnits < 0:
        var details = initTable[string, string]()
        details["colonyId"] = $colonyId
        details["owner"] = $colony.owner
        details["PU"] = $colony.populationUnits
        violations.add(newInvariantViolation(
          turn, ViolationSeverity.Error,
          "Population",
          &"Colony {colonyId} has negative PU: {colony.populationUnits}",
          details
        ))

      # Infrastructure bounds
      if colony.infrastructure < 0 or colony.infrastructure > 10:
        var details = initTable[string, string]()
        details["colonyId"] = $colonyId
        details["infrastructure"] = $colony.infrastructure
        violations.add(newInvariantViolation(
          turn, ViolationSeverity.Error,
          "Infrastructure",
          &"Colony {colonyId} has invalid infrastructure: {colony.infrastructure} (should be 0-10)",
          details
        ))

  # Check fleets
  for (fleetId, fleet) in state.allFleetsWithId():
    # Fleet location validity
    if invariants.checkFleetLocations:
      if fleet.location notin validSystems:
        var details = initTable[string, string]()
        details["fleetId"] = $fleetId
        details["location"] = $fleet.location
        details["owner"] = $fleet.houseId
        violations.add(newInvariantViolation(
          turn, ViolationSeverity.Critical,
          "InvalidLocation",
          &"Fleet {fleetId} at invalid system ID: {fleet.location}",
          details
        ))

    # Fleet owner validity
    if invariants.checkOwnership:
      if fleet.houseId notin validHouses:
        var details = initTable[string, string]()
        details["fleetId"] = $fleetId
        details["owner"] = $fleet.houseId
        violations.add(newInvariantViolation(
          turn, ViolationSeverity.Critical,
          "InvalidOwner",
          &"Fleet {fleetId} owned by non-existent house: {fleet.houseId}",
          details
        ))

  return violations

proc reportViolations*(violations: seq[InvariantViolation]) =
  ## Print violation report to console
  if violations.len == 0:
    echo "No invariant violations detected"
    return

  echo &"\nFound {violations.len} invariant violations:"
  echo "=" .repeat(80)

  # Group by severity
  let critical = violations.filterIt(it.severity == ViolationSeverity.Critical)
  let errors = violations.filterIt(it.severity == ViolationSeverity.Error)
  let warnings = violations.filterIt(it.severity == ViolationSeverity.Warning)

  if critical.len > 0:
    echo &"\nCRITICAL ({critical.len}):"
    for v in critical:
      echo &"  Turn {v.turn} [{v.category}] {v.description}"
      for key, val in v.details:
        echo &"    {key}: {val}"

  if errors.len > 0:
    echo &"\nERRORS ({errors.len}):"
    for v in errors:
      echo &"  Turn {v.turn} [{v.category}] {v.description}"
      for key, val in v.details:
        echo &"    {key}: {val}"

  if warnings.len > 0:
    echo &"\nWARNINGS ({warnings.len}):"
    for v in warnings:
      echo &"  Turn {v.turn} [{v.category}] {v.description}"
      for key, val in v.details:
        echo &"    {key}: {val}"

  echo "=" .repeat(80)
