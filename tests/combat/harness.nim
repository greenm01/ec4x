## Combat Test Harness
##
## Runs bulk combat scenarios and collects statistics
## Detects edge cases, spec violations, and balance issues

import std/[times, sequtils, tables, strformat, options]
import ../../src/engine/combat/[types, engine]
import ../../src/engine/squadron
import ../../src/common/types/[core, units, combat]
import generator

export BattleScenario, CombatResult

## Test Result Tracking

type
  TestResult* = object
    ## Result from running a test scenario
    scenario*: BattleScenario
    result*: CombatResult
    duration*: float          # Seconds to resolve
    edgeCases*: seq[EdgeCase]
    violations*: seq[SpecViolation]

  EdgeCase* = object
    ## Unusual or interesting combat outcome
    caseType*: string
    description*: string
    severity*: EdgeCaseSeverity

  EdgeCaseSeverity* {.pure.} = enum
    Info,      # Interesting but normal
    Warning,   # Unusual but legal
    Critical   # Should not happen

  SpecViolation* = object
    ## Rule violation detected
    rule*: string
    description*: string
    roundNumber*: int

  TestSuiteResults* = object
    ## Aggregate results from multiple tests
    totalTests*: int
    totalDuration*: float
    results*: seq[TestResult]
    edgeCaseCounts*: Table[string, int]
    violationCounts*: Table[string, int]

## Edge Case Detection

proc detectEdgeCases*(scenario: BattleScenario, combatResult: CombatResult): seq[EdgeCase] =
  ## Analyze combat result for edge cases
  result = @[]

  # Check for stalemate
  if combatResult.wasStalemate:
    result.add(EdgeCase(
      caseType: "stalemate",
      description: fmt"Combat stalemated after {combatResult.totalRounds} rounds",
      severity: EdgeCaseSeverity.Warning
    ))

  # Check for one-round victories
  if combatResult.totalRounds == 1 and combatResult.victor.isSome:
    result.add(EdgeCase(
      caseType: "instant_victory",
      description: "Combat resolved in single round",
      severity: EdgeCaseSeverity.Info
    ))

  # Check for mutual destruction
  if combatResult.victor.isNone and combatResult.survivors.len == 0:
    result.add(EdgeCase(
      caseType: "mutual_destruction",
      description: "All Task Forces destroyed",
      severity: EdgeCaseSeverity.Warning
    ))

  # Check for immediate retreat
  if combatResult.totalRounds == 2 and combatResult.retreated.len > 0:
    result.add(EdgeCase(
      caseType: "immediate_retreat",
      description: fmt"Retreat after first round: {combatResult.retreated}",
      severity: EdgeCaseSeverity.Info
    ))

  # Check for very long combat
  if combatResult.totalRounds >= 15:
    result.add(EdgeCase(
      caseType: "long_combat",
      description: fmt"Combat lasted {combatResult.totalRounds} rounds",
      severity: EdgeCaseSeverity.Warning
    ))

  # Check for no damage rounds (potential infinite loop)
  var consecutiveNoDamageRounds = 0
  for roundResults in combatResult.rounds:
    var hadDamage = false
    for phaseResult in roundResults:
      if phaseResult.stateChanges.len > 0:
        hadDamage = true
        break

    if hadDamage:
      consecutiveNoDamageRounds = 0
    else:
      consecutiveNoDamageRounds += 1

    if consecutiveNoDamageRounds >= 5:
      result.add(EdgeCase(
        caseType: "no_damage_loop",
        description: fmt"{consecutiveNoDamageRounds} consecutive rounds without damage",
        severity: EdgeCaseSeverity.Critical
      ))
      break

proc detectViolations*(scenario: BattleScenario, combatResult: CombatResult): seq[SpecViolation] =
  ## Check for spec violations
  result = @[]

  # Check: Can't retreat on first round (Section 7.3.5)
  if combatResult.totalRounds == 1 and combatResult.retreated.len > 0:
    result.add(SpecViolation(
      rule: "7.3.5 - No Retreat First Round",
      description: "Task Force retreated on first round",
      roundNumber: 1
    ))

  # Check: Combat must end eventually (max 20 rounds)
  if combatResult.totalRounds > 20:
    result.add(SpecViolation(
      rule: "7.3.4 - Stalemate at 20 rounds",
      description: fmt"Combat exceeded 20 rounds: {combatResult.totalRounds}",
      roundNumber: combatResult.totalRounds
    ))

  # Check: Victor must be alive or none
  if combatResult.victor.isSome:
    let victorId = combatResult.victor.get()
    var victorAlive = false
    for tf in combatResult.survivors:
      if tf.house == victorId:
        victorAlive = true
        break

    if not victorAlive:
      result.add(SpecViolation(
        rule: "Combat Victory",
        description: fmt"Victor {victorId} not in survivors list",
        roundNumber: combatResult.totalRounds
      ))

## Test Execution

proc runTest*(scenario: BattleScenario): TestResult =
  ## Run single combat test scenario
  let startTime = cpuTime()

  # Build battle context
  let context = BattleContext(
    systemId: scenario.systemId,
    taskForces: scenario.taskForces,
    seed: scenario.seed,
    maxRounds: 20
  )

  # Resolve combat
  let combatResult = resolveCombat(context)

  let endTime = cpuTime()
  let duration = endTime - startTime

  # Analyze results
  let edgeCases = detectEdgeCases(scenario, combatResult)
  let violations = detectViolations(scenario, combatResult)

  result = TestResult(
    scenario: scenario,
    result: combatResult,
    duration: duration,
    edgeCases: edgeCases,
    violations: violations
  )

proc runTestSuite*(scenarios: seq[BattleScenario], verbose: bool = false): TestSuiteResults =
  ## Run multiple test scenarios
  result = TestSuiteResults(
    totalTests: scenarios.len,
    totalDuration: 0.0,
    results: @[],
    edgeCaseCounts: initTable[string, int](),
    violationCounts: initTable[string, int]()
  )

  for i, scenario in scenarios:
    if verbose:
      echo fmt"Running test {i+1}/{scenarios.len}: {scenario.name}"

    let testResult = runTest(scenario)
    result.results.add(testResult)
    result.totalDuration += testResult.duration

    # Aggregate edge cases
    for edgeCase in testResult.edgeCases:
      let count = result.edgeCaseCounts.getOrDefault(edgeCase.caseType, 0)
      result.edgeCaseCounts[edgeCase.caseType] = count + 1

    # Aggregate violations
    for violation in testResult.violations:
      let count = result.violationCounts.getOrDefault(violation.rule, 0)
      result.violationCounts[violation.rule] = count + 1

    if verbose and (testResult.edgeCases.len > 0 or testResult.violations.len > 0):
      echo fmt"  - Edge cases: {testResult.edgeCases.len}, Violations: {testResult.violations.len}"

## Statistics

proc calculateWinRates*(results: seq[TestResult]): Table[string, tuple[wins: int, total: int]] =
  ## Calculate win rates by house
  result = initTable[string, tuple[wins: int, total: int]]()

  for testResult in results:
    for tf in testResult.scenario.taskForces:
      let house = tf.house
      var entry = result.getOrDefault(house, (0, 0))
      entry.total += 1
      if testResult.result.victor.isSome and testResult.result.victor.get() == house:
        entry.wins += 1
      result[house] = entry

proc calculateAverageRounds*(results: seq[TestResult]): float =
  ## Calculate average combat length
  if results.len == 0:
    return 0.0

  var total = 0
  for r in results:
    total += r.result.totalRounds

  return float(total) / float(results.len)

proc countCriticalHits*(results: seq[TestResult]): int =
  ## Count total critical hits across all tests
  result = 0
  for testResult in results:
    for roundResults in testResult.result.rounds:
      for phaseResult in roundResults:
        for attack in phaseResult.attacks:
          if attack.cerRoll.isCriticalHit:
            result += 1

## Output Formatting

proc formatSummary*(suiteResults: TestSuiteResults): string =
  ## Generate human-readable summary
  result = fmt"""
=== Combat Test Suite Results ===

Total Tests: {suiteResults.totalTests}
Total Duration: {suiteResults.totalDuration:.3f}s
Avg Per Test: {suiteResults.totalDuration / float(suiteResults.totalTests):.4f}s

Edge Cases Detected:
"""

  if suiteResults.edgeCaseCounts.len == 0:
    result.add("  (none)\n")
  else:
    for caseType, count in suiteResults.edgeCaseCounts:
      result.add(fmt"  {caseType}: {count}" & "\n")

  result.add("\nSpec Violations:\n")
  if suiteResults.violationCounts.len == 0:
    result.add("  (none)\n")
  else:
    for rule, count in suiteResults.violationCounts:
      result.add(fmt"  {rule}: {count}" & "\n")

  # Calculate stats
  let avgRounds = calculateAverageRounds(suiteResults.results)
  let criticalHits = countCriticalHits(suiteResults.results)

  result.add(fmt"""
Combat Statistics:
  Average Rounds: {avgRounds:.2f}
  Critical Hits: {criticalHits}
  Critical Hit Rate: {float(criticalHits) / float(suiteResults.totalTests * 10):.3f} per round
""")

## Quick Test Runner

proc quickTest*(numTests: int = 100, seed: int64 = 12345, verbose: bool = false): TestSuiteResults =
  ## Run quick test suite with random scenarios
  echo fmt"Generating {numTests} random battle scenarios..."
  let scenarios = generateTestSuite(seed, numTests)

  echo fmt"Running {numTests} combat tests..."
  result = runTestSuite(scenarios, verbose)

  echo "\n" & formatSummary(result)
