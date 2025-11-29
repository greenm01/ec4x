## Stress Test Framework
##
## Core infrastructure for stress testing the EC4X engine
## Provides:
## - Anomaly detection and invariant checking
## - Long-running simulation infrastructure
## - Statistical analysis for unknown-unknowns
## - Performance monitoring and regression detection

import std/[tables, times, strformat, options, math, sequtils, strutils, sets]
import ../../src/engine/[gamestate, resolve, orders, setup, fleet, squadron]
import ../../src/common/types/[core, units]
import ../../src/engine/config/[ships_config, military_config]

type
  InvariantViolation* = object
    ## Detected violation of a game state invariant
    turn*: int
    severity*: ViolationSeverity
    category*: string
    description*: string
    details*: Table[string, string]

  ViolationSeverity* {.pure.} = enum
    Warning,   # Suspicious but maybe valid
    Error,     # Clear bug - invalid state
    Critical   # Game-breaking corruption

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
    checkFighterCapacity*: bool    # Fighters must fit carrier capacity
    checkSquadronLimits*: bool     # Squadron counts must respect PU limits
    checkFleetLocations*: bool     # Fleets must be at valid system IDs
    checkOwnership*: bool          # All entities owned by valid houses
    checkUniqueIds*: bool          # All IDs must be unique
    checkOrphanedSquadrons*: bool  # Squadrons must be in exactly one fleet
    checkPrestigeRange*: bool      # Prestige should be bounded
    checkTechLevelRange*: bool     # Tech levels in valid range

proc newInvariantViolation*(turn: int, severity: ViolationSeverity,
                           category, description: string,
                           details: Table[string, string] = initTable[string, string]()): InvariantViolation =
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
    checkFighterCapacity: true,
    checkSquadronLimits: true,
    checkFleetLocations: true,
    checkOwnership: true,
    checkUniqueIds: true,
    checkOrphanedSquadrons: true,
    checkPrestigeRange: true,
    checkTechLevelRange: true
  )

proc checkStateInvariants*(state: GameState, turn: int, invariants: StateInvariants = defaultInvariants()): seq[InvariantViolation] =
  ## Check all game state invariants and return violations
  var violations: seq[InvariantViolation] = @[]

  # Build valid house IDs set
  let validHouses = toSeq(state.houses.keys).toHashSet

  # Build valid system IDs set
  let validSystems = toSeq(state.starMap.systems.keys).toHashSet

  # Track all fleet IDs to check for duplicates
  var allFleetIds: seq[FleetId] = @[]
  var allSquadronIds: seq[string] = @[]

  # Check each house
  for houseId, house in state.houses:

    # Treasury checks
    if invariants.checkTreasury:
      # Allow controlled negative treasury for maintenance shortfall scenarios
      # But extremely negative values (< -10000 PP) are suspicious
      if house.treasury < -10_000:
        var details = initTable[string, string]()
        details["house"] = houseId
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
        details["house"] = houseId
        details["prestige"] = $house.prestige
        violations.add(newInvariantViolation(
          turn, ViolationSeverity.Warning,
          "Prestige",
          &"House {houseId} has extremely high prestige: {house.prestige}",
          details
        ))
      elif house.prestige < -1000:
        var details = initTable[string, string]()
        details["house"] = houseId
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
        ("CST", house.techTree.levels.constructionTech),
        ("WEP", house.techTree.levels.weaponsTech),
        ("EL", house.techTree.levels.economicLevel),
        ("SL", house.techTree.levels.scienceLevel),
        ("TER", house.techTree.levels.terraformingTech),
        ("ELI", house.techTree.levels.electronicIntelligence),
        ("CLK", house.techTree.levels.cloakingTech),
        ("SLD", house.techTree.levels.shieldTech),
        ("CIC", house.techTree.levels.counterIntelligence),
        ("FD", house.techTree.levels.fighterDoctrine),
        ("ACO", house.techTree.levels.advancedCarrierOps)
      ]

      for (fieldName, level) in allTechLevels:
        if level < 0 or level > 20:
          var details = initTable[string, string]()
          details["house"] = houseId
          details["field"] = fieldName
          details["level"] = $level
          violations.add(newInvariantViolation(
            turn, ViolationSeverity.Error,
            "TechLevel",
            &"House {houseId} has invalid {fieldName} tech level: {level}",
            details
          ))

  # Check colonies
  for systemId, colony in state.colonies:

    # System ID validity
    if invariants.checkFleetLocations:
      if systemId notin validSystems:
        var details = initTable[string, string]()
        details["systemId"] = $systemId
        details["owner"] = colony.owner
        violations.add(newInvariantViolation(
          turn, ViolationSeverity.Critical,
          "InvalidLocation",
          &"Colony at invalid system ID: {systemId}",
          details
        ))

    # Owner validity
    if invariants.checkOwnership:
      if colony.owner notin validHouses:
        var details = initTable[string, string]()
        details["systemId"] = $systemId
        details["owner"] = colony.owner
        violations.add(newInvariantViolation(
          turn, ViolationSeverity.Critical,
          "InvalidOwner",
          &"Colony at {systemId} owned by non-existent house: {colony.owner}",
          details
        ))

    # Population consistency
    if colony.populationUnits < 0:
      var details = initTable[string, string]()
      details["systemId"] = $systemId
      details["owner"] = colony.owner
      details["PU"] = $colony.populationUnits
      violations.add(newInvariantViolation(
        turn, ViolationSeverity.Error,
        "Population",
        &"Colony at {systemId} has negative PU: {colony.populationUnits}",
        details
      ))

    # Infrastructure bounds
    if colony.infrastructure < 0 or colony.infrastructure > 10:
      var details = initTable[string, string]()
      details["systemId"] = $systemId
      details["infrastructure"] = $colony.infrastructure
      violations.add(newInvariantViolation(
        turn, ViolationSeverity.Error,
        "Infrastructure",
        &"Colony at {systemId} has invalid infrastructure: {colony.infrastructure} (should be 0-10)",
        details
      ))

    # Fighter capacity checks
    if invariants.checkFighterCapacity:
      let fighterCount = colony.fighterSquadrons.len
      # Calculate allowed fighters based on military_config rules
      # This is simplified - real check requires carrier capacity calculation
      if fighterCount > 1000:  # Sanity check - no colony should have 1000+ fighter squadrons
        var details = initTable[string, string]()
        details["systemId"] = $systemId
        details["fighterCount"] = $fighterCount
        violations.add(newInvariantViolation(
          turn, ViolationSeverity.Warning,
          "FighterCapacity",
          &"Colony at {systemId} has suspiciously high fighter count: {fighterCount}",
          details
        ))

    # Check unassigned squadron IDs for duplicates
    for sq in colony.unassignedSquadrons:
      allSquadronIds.add(sq.id)

  # Check fleets
  for fleetId, fleet in state.fleets:
    allFleetIds.add(fleetId)

    # Fleet location validity
    if invariants.checkFleetLocations:
      if fleet.location notin validSystems:
        var details = initTable[string, string]()
        details["fleetId"] = fleetId
        details["location"] = $fleet.location
        details["owner"] = fleet.owner
        violations.add(newInvariantViolation(
          turn, ViolationSeverity.Critical,
          "InvalidLocation",
          &"Fleet {fleetId} at invalid system ID: {fleet.location}",
          details
        ))

    # Fleet owner validity
    if invariants.checkOwnership:
      if fleet.owner notin validHouses:
        var details = initTable[string, string]()
        details["fleetId"] = fleetId
        details["owner"] = fleet.owner
        violations.add(newInvariantViolation(
          turn, ViolationSeverity.Critical,
          "InvalidOwner",
          &"Fleet {fleetId} owned by non-existent house: {fleet.owner}",
          details
        ))

    # Squadron ownership consistency
    for sq in fleet.squadrons:
      allSquadronIds.add(sq.id)
      if sq.owner != fleet.owner:
        var details = initTable[string, string]()
        details["fleetId"] = fleetId
        details["fleetOwner"] = fleet.owner
        details["squadronId"] = sq.id
        details["squadronOwner"] = sq.owner
        violations.add(newInvariantViolation(
          turn, ViolationSeverity.Error,
          "OwnershipMismatch",
          &"Fleet {fleetId} (owner: {fleet.owner}) contains squadron {sq.id} (owner: {sq.owner})",
          details
        ))

  # Check for duplicate IDs
  if invariants.checkUniqueIds:
    # Check fleet ID uniqueness
    let fleetIdCounts = allFleetIds.toCountTable()
    for fleetId, count in fleetIdCounts:
      if count > 1:
        var details = initTable[string, string]()
        details["fleetId"] = fleetId
        details["count"] = $count
        violations.add(newInvariantViolation(
          turn, ViolationSeverity.Critical,
          "DuplicateId",
          &"Fleet ID {fleetId} appears {count} times",
          details
        ))

    # Check squadron ID uniqueness
    let squadronIdCounts = allSquadronIds.toCountTable()
    for sqId, count in squadronIdCounts:
      if count > 1:
        var details = initTable[string, string]()
        details["squadronId"] = sqId
        details["count"] = $count
        violations.add(newInvariantViolation(
          turn, ViolationSeverity.Critical,
          "DuplicateId",
          &"Squadron ID {sqId} appears {count} times (squadron in multiple fleets!)",
          details
        ))

  return violations

proc reportViolations*(violations: seq[InvariantViolation]) =
  ## Print violation report to console
  if violations.len == 0:
    echo "✅ No invariant violations detected"
    return

  echo &"\n⚠️  Found {violations.len} invariant violations:"
  echo "=" .repeat(80)

  # Group by severity
  let critical = violations.filterIt(it.severity == ViolationSeverity.Critical)
  let errors = violations.filterIt(it.severity == ViolationSeverity.Error)
  let warnings = violations.filterIt(it.severity == ViolationSeverity.Warning)

  if critical.len > 0:
    echo &"\n🔴 CRITICAL ({critical.len}):"
    for v in critical:
      echo &"  Turn {v.turn} [{v.category}] {v.description}"
      for key, val in v.details:
        echo &"    {key}: {val}"

  if errors.len > 0:
    echo &"\n🟡 ERRORS ({errors.len}):"
    for v in errors:
      echo &"  Turn {v.turn} [{v.category}] {v.description}"
      for key, val in v.details:
        echo &"    {key}: {val}"

  if warnings.len > 0:
    echo &"\n🟠 WARNINGS ({warnings.len}):"
    for v in warnings:
      echo &"  Turn {v.turn} [{v.category}] {v.description}"
      for key, val in v.details:
        echo &"    {key}: {val}"

  echo "=" .repeat(80)
