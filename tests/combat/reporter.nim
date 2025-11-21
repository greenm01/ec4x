## JSON Export for Combat Results
##
## Converts typed combat results to JSON for AI analysis
## This is the ONLY place JSON touches the combat system

import std/[json, options, strformat, tables]
import ../src/engine/combat/[types, engine]
import ../src/engine/squadron
import ../src/common/types/[core, units, combat]
import combat_test_harness

## Core Type Conversions

proc toJson*(state: CombatState): JsonNode =
  case state
  of CombatState.Undamaged: return %"undamaged"
  of CombatState.Crippled: return %"crippled"
  of CombatState.Destroyed: return %"destroyed"

proc toJson*(phase: CombatPhase): JsonNode =
  case phase
  of CombatPhase.PreCombat: return %"pre_combat"
  of CombatPhase.Ambush: return %"ambush"
  of CombatPhase.Intercept: return %"intercept"
  of CombatPhase.MainEngagement: return %"main_engagement"
  of CombatPhase.PostCombat: return %"post_combat"

proc toJson*(bucket: TargetBucket): JsonNode =
  case bucket
  of TargetBucket.Raider: return %"raider"
  of TargetBucket.Capital: return %"capital"
  of TargetBucket.Destroyer: return %"destroyer"
  of TargetBucket.Fighter: return %"fighter"
  of TargetBucket.Starbase: return %"starbase"

proc toJson*(cer: CERRoll): JsonNode =
  %*{
    "natural_roll": cer.naturalRoll,
    "modifiers": cer.modifiers,
    "final_roll": cer.finalRoll,
    "effectiveness": cer.effectiveness,
    "is_critical_hit": cer.isCriticalHit
  }

proc toJson*(attack: AttackResult): JsonNode =
  %*{
    "attacker_id": attack.attackerId,
    "target_id": attack.targetId,
    "cer_roll": attack.cerRoll.toJson(),
    "damage_dealt": attack.damageDealt,
    "target_state_before": attack.targetStateBefore.toJson(),
    "target_state_after": attack.targetStateAfter.toJson()
  }

proc toJson*(change: StateChange): JsonNode =
  %*{
    "squadron_id": change.squadronId,
    "from_state": change.fromState.toJson(),
    "to_state": change.toState.toJson(),
    "destruction_protection_applied": change.destructionProtectionApplied
  }

proc toJson*(roundResult: RoundResult): JsonNode =
  var attacksJson = newJArray()
  for attack in roundResult.attacks:
    attacksJson.add(attack.toJson())

  var changesJson = newJArray()
  for change in roundResult.stateChanges:
    changesJson.add(change.toJson())

  %*{
    "phase": roundResult.phase.toJson(),
    "round_number": roundResult.roundNumber,
    "attacks": attacksJson,
    "state_changes": changesJson
  }

proc toJson*(squadron: CombatSquadron): JsonNode =
  %*{
    "id": squadron.squadron.id,
    "flagship_class": $squadron.squadron.flagship.shipClass,
    "ship_count": squadron.squadron.shipCount(),
    "state": squadron.state.toJson(),
    "bucket": squadron.bucket.toJson(),
    "attack_strength": squadron.getCurrentAS(),
    "defense_strength": squadron.getCurrentDS()
  }

proc toJson*(taskForce: TaskForce): JsonNode =
  var squadronsJson = newJArray()
  for sq in taskForce.squadrons:
    squadronsJson.add(sq.toJson())

  %*{
    "house": taskForce.house,
    "squadrons": squadronsJson,
    "roe": taskForce.roe,
    "is_cloaked": taskForce.isCloaked,
    "scout_bonus": taskForce.scoutBonus,
    "morale_modifier": taskForce.moraleModifier,
    "total_attack_strength": taskForce.totalAS(),
    "is_defending_homeworld": taskForce.isDefendingHomeworld
  }

proc toJson*(combatResult: CombatResult): JsonNode =
  var roundsJson = newJArray()
  for roundResults in combatResult.rounds:
    var phaseResultsJson = newJArray()
    for phaseResult in roundResults:
      phaseResultsJson.add(phaseResult.toJson())
    roundsJson.add(phaseResultsJson)

  var survivorsJson = newJArray()
  for tf in combatResult.survivors:
    survivorsJson.add(tf.toJson())

  var retreatedJson = newJArray()
  for house in combatResult.retreated:
    retreatedJson.add(%house)

  var eliminatedJson = newJArray()
  for house in combatResult.eliminated:
    eliminatedJson.add(%house)

  var victorJson: JsonNode
  if combatResult.victor.isSome:
    victorJson = %combatResult.victor.get()
  else:
    victorJson = newJNull()

  %*{
    "system_id": combatResult.systemId,
    "rounds": roundsJson,
    "survivors": survivorsJson,
    "retreated": retreatedJson,
    "eliminated": eliminatedJson,
    "victor": victorJson,
    "total_rounds": combatResult.totalRounds,
    "was_stalemate": combatResult.wasStalemate
  }

## Test Result Conversions

proc toJson*(severity: EdgeCaseSeverity): JsonNode =
  case severity
  of EdgeCaseSeverity.Info: return %"info"
  of EdgeCaseSeverity.Warning: return %"warning"
  of EdgeCaseSeverity.Critical: return %"critical"

proc toJson*(edgeCase: EdgeCase): JsonNode =
  %*{
    "type": edgeCase.caseType,
    "description": edgeCase.description,
    "severity": edgeCase.severity.toJson()
  }

proc toJson*(violation: SpecViolation): JsonNode =
  %*{
    "rule": violation.rule,
    "description": violation.description,
    "round_number": violation.roundNumber
  }

proc toJson*(scenario: BattleScenario): JsonNode =
  var taskForcesJson = newJArray()
  for tf in scenario.taskForces:
    taskForcesJson.add(tf.toJson())

  %*{
    "name": scenario.name,
    "description": scenario.description,
    "task_forces": taskForcesJson,
    "num_factions": scenario.taskForces.len,
    "system_id": scenario.systemId,
    "seed": scenario.seed,
    "expected_outcome": scenario.expectedOutcome
  }

proc toJson*(testResult: TestResult): JsonNode =
  var edgeCasesJson = newJArray()
  for ec in testResult.edgeCases:
    edgeCasesJson.add(ec.toJson())

  var violationsJson = newJArray()
  for v in testResult.violations:
    violationsJson.add(v.toJson())

  %*{
    "scenario": testResult.scenario.toJson(),
    "result": testResult.result.toJson(),
    "duration_seconds": testResult.duration,
    "edge_cases": edgeCasesJson,
    "violations": violationsJson
  }

## Test Suite Results

proc toJson*(suiteResults: TestSuiteResults): JsonNode =
  var resultsJson = newJArray()
  for r in suiteResults.results:
    resultsJson.add(r.toJson())

  var edgeCaseCountsJson = newJObject()
  for caseType, count in suiteResults.edgeCaseCounts:
    edgeCaseCountsJson[caseType] = %count

  var violationCountsJson = newJObject()
  for rule, count in suiteResults.violationCounts:
    violationCountsJson[rule] = %count

  # Calculate aggregate statistics
  let avgRounds = calculateAverageRounds(suiteResults.results)
  let criticalHits = countCriticalHits(suiteResults.results)
  let winRates = calculateWinRates(suiteResults.results)

  var winRatesJson = newJObject()
  for house, stats in winRates:
    winRatesJson[house] = %*{
      "wins": stats.wins,
      "total": stats.total,
      "win_rate": if stats.total > 0: float(stats.wins) / float(stats.total) else: 0.0
    }

  %*{
    "test_run_metadata": {
      "total_tests": suiteResults.totalTests,
      "total_duration_seconds": suiteResults.totalDuration,
      "avg_duration_per_test": suiteResults.totalDuration / float(suiteResults.totalTests)
    },
    "aggregate_statistics": {
      "average_rounds": avgRounds,
      "critical_hits_total": criticalHits,
      "critical_hit_rate_per_round": float(criticalHits) / (float(suiteResults.totalTests) * avgRounds),
      "win_rates_by_house": winRatesJson
    },
    "edge_cases_summary": edgeCaseCountsJson,
    "spec_violations_summary": violationCountsJson,
    "individual_results": resultsJson
  }

## Export Functions

proc exportToJsonFile*(suiteResults: TestSuiteResults, filename: string) =
  ## Export test results to JSON file
  let jsonData = suiteResults.toJson()
  let prettyJson = jsonData.pretty()
  writeFile(filename, prettyJson)
  echo fmt"Exported results to {filename}"

proc exportSummaryToJson*(suiteResults: TestSuiteResults, filename: string) =
  ## Export summary only (without individual test details)
  let fullJson = suiteResults.toJson()

  # Extract just summary data
  let summaryJson = %*{
    "test_run_metadata": fullJson["test_run_metadata"],
    "aggregate_statistics": fullJson["aggregate_statistics"],
    "edge_cases_summary": fullJson["edge_cases_summary"],
    "spec_violations_summary": fullJson["spec_violations_summary"]
  }

  writeFile(filename, summaryJson.pretty())
  echo fmt"Exported summary to {filename}"

## CSV Export (for spreadsheet analysis)

proc exportStatsToCsv*(suiteResults: TestSuiteResults, filename: string) =
  ## Export aggregate statistics to CSV
  var csv = "test_name,victor,rounds,duration,edge_cases,violations,num_factions,total_squadrons\n"

  for testResult in suiteResults.results:
    let victor = if testResult.result.victor.isSome: testResult.result.victor.get() else: "none"
    let numFactions = testResult.scenario.taskForces.len
    var totalSquadrons = 0
    for tf in testResult.scenario.taskForces:
      totalSquadrons += tf.squadrons.len
    let line = fmt"{testResult.scenario.name},{victor},{testResult.result.totalRounds},{testResult.duration:.4f},{testResult.edgeCases.len},{testResult.violations.len},{numFactions},{totalSquadrons}" & "\n"
    csv.add(line)

  writeFile(filename, csv)
  echo fmt"Exported CSV stats to {filename}"
