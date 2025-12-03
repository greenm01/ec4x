## Minimal Balance Test - Quick Report Generation
##
## Runs a simplified balance test to demonstrate the framework
## without requiring full AI implementation.

import std/[json, tables, times, strformat, random, math, algorithm, strutils, os]
import ../../engine/[gamestate, orders]
import ../../common/types/[core, units, planets, tech]
import ../../engine/config/[gameplay_config, prestige_config]

# =============================================================================
# Simplified Test Data Generation
# =============================================================================

type
  MinimalHouseData = object
    houseId: HouseId
    prestige: seq[int]
    gco: seq[int]
    ncv: seq[int]
    fleetStrength: seq[int]
    colonies: seq[int]
    techLevel: seq[int]

proc generateMockGameData(numHouses: int, numTurns: int): seq[MinimalHouseData] =
  ## Generate mock game data for demonstration
  result = @[]
  var rng = initRand(42)

  for h in 0..<numHouses:
    var house = MinimalHouseData(
      houseId: ("House" & $(h+1)).HouseId,
      prestige: @[],
      gco: @[],
      ncv: @[],
      fleetStrength: @[],
      colonies: @[],
      techLevel: @[]
    )

    # Starting values
    var prestige = globalPrestigeConfig.victory.starting_prestige
    var gco = 100
    var ncv = 50
    var fleetStrength = 50
    var colonies = 3
    var techLevel = 1

    # Different growth patterns for different strategies
    let growthPattern = h mod 3

    for turn in 1..numTurns:
      # Economic growth
      case growthPattern
      of 0:  # Military-focused
        gco = int(float(gco) * 1.02)  # Slow economic growth
        fleetStrength = int(float(fleetStrength) * 1.08)  # Fast military
        prestige += rng.rand(15..25)  # Combat prestige
      of 1:  # Economic-focused
        gco = int(float(gco) * 1.05)  # Fast economic growth
        fleetStrength = int(float(fleetStrength) * 1.03)  # Slow military
        prestige += rng.rand(5..15)  # Economic prestige
      else:  # Balanced
        gco = int(float(gco) * 1.035)  # Medium growth
        fleetStrength = int(float(fleetStrength) * 1.05)  # Medium military
        prestige += rng.rand(10..20)  # Mixed prestige

      ncv = int(float(gco) * 0.5)  # Simple NCV calculation

      # Tech advancement every 15 turns
      if turn mod 15 == 0:
        techLevel += 1
        prestige += globalPrestigeConfig.economic.tech_advancement

      # Colony expansion
      if turn mod 20 == 0 and colonies < 10:
        colonies += 1
        prestige += globalPrestigeConfig.economic.establish_colony

      # Random prestige variance
      prestige += rng.rand(-5..5)

      # Add volatility for interesting dynamics
      if turn > 30 and rng.rand(100) < 10:  # 10% chance of major event
        let eventImpact = rng.rand(-200..300)
        prestige += eventImpact
        if eventImpact > 0:
          fleetStrength = int(float(fleetStrength) * 1.2)
        else:
          fleetStrength = int(float(fleetStrength) * 0.8)

      # Record snapshot
      house.prestige.add(prestige)
      house.gco.add(gco)
      house.ncv.add(ncv)
      house.fleetStrength.add(fleetStrength)
      house.colonies.add(colonies)
      house.techLevel.add(techLevel)

    result.add(house)

# =============================================================================
# Analysis Functions
# =============================================================================

proc generateBalanceAssessment(metrics: JsonNode): JsonNode  # Forward declaration

proc calculateMetrics(houses: seq[MinimalHouseData]): JsonNode =
  ## Calculate balance metrics from game data
  let numTurns = houses[0].prestige.len

  # Track leader changes
  var leaderChanges = 0
  var previousLeader = -1

  # Prestige volatility
  var prestigeDeltas: seq[float] = @[]

  # Comebacks
  var comebacks = 0

  for turn in 0..<numTurns:
    # Find current leader
    var maxPrestige = -1000000
    var currentLeader = 0
    for h in 0..<houses.len:
      if houses[h].prestige[turn] > maxPrestige:
        maxPrestige = houses[h].prestige[turn]
        currentLeader = h

    # Count leader change
    if turn > 0 and currentLeader != previousLeader:
      leaderChanges += 1
    previousLeader = currentLeader

    # Calculate prestige deltas
    if turn > 0:
      for h in 0..<houses.len:
        let delta = float(houses[h].prestige[turn] - houses[h].prestige[turn-1])
        prestigeDeltas.add(delta)

    # Check for comebacks (house in last place at turn 30 that isn't last at turn 60)
    if turn == 30:
      var minPrestige = 1000000
      var lastPlace = 0
      for h in 0..<houses.len:
        if houses[h].prestige[turn] < minPrestige:
          minPrestige = houses[h].prestige[turn]
          lastPlace = h

      # Check if they recovered by turn 60
      if numTurns > 60:
        let turn60Prestige = houses[lastPlace].prestige[59]
        var stillLast = true
        for h in 0..<houses.len:
          if h != lastPlace and houses[h].prestige[59] < turn60Prestige:
            stillLast = false
            break
        if not stillLast:
          comebacks += 1

  # Calculate volatility (std dev of deltas)
  var mean = 0.0
  for delta in prestigeDeltas:
    mean += delta
  mean /= float(prestigeDeltas.len)

  var variance = 0.0
  for delta in prestigeDeltas:
    variance += (delta - mean) * (delta - mean)
  variance /= float(prestigeDeltas.len)
  let volatility = sqrt(variance)

  # Check for domination (leader at turn 20 wins)
  let turn20Leader = (proc(): int =
    var maxP = -1000000
    var leader = 0
    for h in 0..<houses.len:
      if houses[h].prestige[min(19, numTurns-1)] > maxP:
        maxP = houses[h].prestige[min(19, numTurns-1)]
        leader = h
    return leader
  )()

  let finalLeader = (proc(): int =
    var maxP = -1000000
    var leader = 0
    for h in 0..<houses.len:
      if houses[h].prestige[numTurns-1] > maxP:
        maxP = houses[h].prestige[numTurns-1]
        leader = h
    return leader
  )()

  let domination = if turn20Leader == finalLeader: 1 else: 0

  # Closeness score (inverse of prestige gap)
  var finalPrestiges: seq[int] = @[]
  for h in houses:
    finalPrestiges.add(h.prestige[numTurns-1])
  finalPrestiges.sort()
  let prestigeGap = finalPrestiges[^1] - finalPrestiges[0]
  let closeness = 1000.0 / float(max(prestigeGap, 1))

  result = %* {
    "leader_changes": leaderChanges,
    "prestige_volatility": volatility,
    "comebacks_observed": comebacks,
    "domination_games": domination,
    "closeness_score": closeness,
    "average_game_length": numTurns,
    "final_prestige_gap": prestigeGap
  }

proc generateReport(houses: seq[MinimalHouseData]): JsonNode =
  ## Generate complete balance test report
  let numTurns = houses[0].prestige.len

  # Build turn snapshots (sample every 10 turns for brevity)
  var turnSnapshots = newJArray()
  for turn in countup(0, numTurns-1, 10):
    var snapshot = %* {
      "turn": turn + 1,
      "houses": []
    }

    for house in houses:
      snapshot["houses"].add(%* {
        "house_id": $house.houseId,
        "prestige": house.prestige[turn],
        "gco": house.gco[turn],
        "ncv": house.ncv[turn],
        "fleet_strength": house.fleetStrength[turn],
        "colonies": house.colonies[turn],
        "tech_level": house.techLevel[turn]
      })

    turnSnapshots.add(snapshot)

  # Final rankings
  var rankings = newJArray()
  var finalData: seq[tuple[house: HouseId, prestige: int]] = @[]
  for house in houses:
    finalData.add((house.houseId, house.prestige[numTurns-1]))
  finalData.sort(proc(a, b: auto): int = cmp(b.prestige, a.prestige))

  for i, data in finalData:
    rankings.add(%* {
      "rank": i + 1,
      "house_id": $data.house,
      "final_prestige": data.prestige
    })

  # Calculate metrics
  let metrics = calculateMetrics(houses)

  # Build complete report
  result = %* {
    "metadata": {
      "test_id": "minimal_balance_test",
      "timestamp": $now(),
      "engine_version": "0.1.0",
      "test_description": "Demonstration balance test with mock data"
    },
    "config": {
      "test_name": "minimal_balance_demo",
      "number_of_houses": houses.len,
      "number_of_turns": numTurns,
      "strategies": ["Military", "Economic", "Balanced"]
    },
    "turn_snapshots": turnSnapshots,
    "outcome": {
      "victor": $finalData[0].house,
      "victory_type": "prestige",
      "final_rankings": rankings
    },
    "metrics": metrics,
    "balance_assessment": generateBalanceAssessment(metrics)
  }

proc generateBalanceAssessment(metrics: JsonNode): JsonNode =
  ## Generate human-readable balance assessment
  var concerns = newJArray()
  var findings = newJArray()

  let leaderChanges = metrics["leader_changes"].getInt()
  let volatility = metrics["prestige_volatility"].getFloat()
  let comebacks = metrics["comebacks_observed"].getInt()
  let domination = metrics["domination_games"].getInt()
  let closeness = metrics["closeness_score"].getFloat()

  # Evaluate leader changes
  if leaderChanges < 3:
    concerns.add(%* {
      "severity": "high",
      "category": "pacing",
      "issue": "Leadership too static",
      "evidence": &"Only {leaderChanges} leader changes over the game",
      "impact": "Game lacks competitive dynamics, early leader dominates"
    })
  elif leaderChanges > 10:
    concerns.add(%* {
      "severity": "medium",
      "category": "pacing",
      "issue": "Leadership too volatile",
      "evidence": &"{leaderChanges} leader changes indicates unstable dynamics",
      "impact": "Game feels random, strategy may not matter"
    })
  else:
    findings.add(%"Leader changes ({leaderChanges}) indicate healthy competition")

  # Evaluate volatility
  if volatility > 100:
    concerns.add(%* {
      "severity": "medium",
      "category": "balance",
      "issue": "High prestige volatility",
      "evidence": &"Prestige volatility: {volatility:.1f}",
      "impact": "Large swings make strategic planning difficult"
    })
  else:
    findings.add(% &"Prestige volatility ({volatility:.1f}) within acceptable range")

  # Evaluate comebacks
  if comebacks == 0:
    concerns.add(%* {
      "severity": "high",
      "category": "comeback",
      "issue": "No comeback potential",
      "evidence": "Houses in last place at turn 30 never recovered",
      "impact": "Early setbacks are insurmountable, reduces strategic depth"
    })
  else:
    findings.add(% "Comeback observed - houses can recover from setbacks")

  # Evaluate domination
  if domination > 0:
    concerns.add(%* {
      "severity": "critical",
      "category": "snowball",
      "issue": "Runaway leader problem",
      "evidence": "Turn 20 leader won the game",
      "impact": "Early advantages compound, mid/late game irrelevant"
    })
  else:
    findings.add(%"No domination - early lead doesn't guarantee victory")

  # Evaluate closeness
  if closeness < 0.5:
    concerns.add(%* {
      "severity": "medium",
      "category": "competitiveness",
      "issue": "Large final prestige gap",
      "evidence": &"Closeness score: {closeness:.2f} (large gap between winner and others)",
      "impact": "Games not competitive, outcome determined early"
    })
  else:
    findings.add(% &"Close finish (score: {closeness:.2f}) - competitive game")

  result = %* {
    "concerns": concerns,
    "positive_findings": findings
  }

# =============================================================================
# Main
# =============================================================================

when isMainModule:
  echo repeat("=", 70)
  echo "EC4X Balance Test - Minimal Demo"
  echo repeat("=", 70)
  echo ""

  echo "Generating mock game data (4 houses, 100 turns)..."
  let houses = generateMockGameData(4, 100)

  echo "Analyzing game trajectory..."
  let report = generateReport(houses)

  echo "\n" & repeat("=", 70)
  echo "BALANCE TEST REPORT"
  echo repeat("=", 70)

  # Print key metrics
  let metrics = report["metrics"]
  echo "\n📊 Key Metrics:"
  echo &"  Leader Changes: {metrics[\"leader_changes\"].getInt()}"
  echo &"  Prestige Volatility: {metrics[\"prestige_volatility\"].getFloat():.1f}"
  echo &"  Comebacks Observed: {metrics[\"comebacks_observed\"].getInt()}"
  echo &"  Domination Games: {metrics[\"domination_games\"].getInt()}"
  echo &"  Closeness Score: {metrics[\"closeness_score\"].getFloat():.2f}"
  echo &"  Final Prestige Gap: {metrics[\"final_prestige_gap\"].getInt()}"

  # Print final rankings
  echo "\n🏆 Final Rankings:"
  let rankings = report["outcome"]["final_rankings"]
  for ranking in rankings:
    let rank = ranking["rank"].getInt()
    let house = ranking["house_id"].getStr()
    let prestige = ranking["final_prestige"].getInt()
    echo &"  {rank}. {house}: {prestige} prestige"

  # Print balance assessment
  echo "\n⚠️  Balance Concerns:"
  let concerns = report["balance_assessment"]["concerns"]
  if concerns.len == 0:
    echo "  ✓ No major concerns detected"
  else:
    for concern in concerns:
      let severity = concern["severity"].getStr()
      let issue = concern["issue"].getStr()
      let evidence = concern["evidence"].getStr()
      echo &"  [{severity.toUpper()}] {issue}"
      echo &"    Evidence: {evidence}"

  echo "\n✅ Positive Findings:"
  let findings = report["balance_assessment"]["positive_findings"]
  for finding in findings:
    echo &"  • {finding.getStr()}"

  # Export full JSON
  echo "\n📄 Exporting full report to: balance_results/minimal_test.json"
  createDir("balance_results")
  writeFile("balance_results/minimal_test.json", report.pretty())

  echo "\n" & repeat("=", 70)
  echo "Test complete! Review balance_results/minimal_test.json for details."
  echo repeat("=", 70)
