## Analyze Coevolution Results and Generate Report
##
## Processes multiple coevolution runs and generates a comprehensive analysis

import std/[json, os, strformat, tables, algorithm, sequtils, strutils, times, math]

type
  SpeciesStats = object
    name: string
    totalWins: int
    totalGames: int
    winRate: float
    avgFitness: float
    championGenes: JsonNode
    evolution: seq[float]  # Fitness over generations

  BalanceIssue = object
    severity: string       # "CRITICAL", "HIGH", "MEDIUM", "LOW"
    category: string       # "Economy", "Military", "Diplomacy", "Technology"
    description: string
    evidence: string
    recommendation: string

  AnalysisReport = object
    runs: int
    totalGenerations: int
    totalGames: int
    speciesStats: seq[SpeciesStats]
    balanceIssues: seq[BalanceIssue]
    winRateVariance: float
    dominantStrategy: string

proc loadCoevolutionResult(path: string): JsonNode =
  ## Load a single coevolution result file
  parseJson(readFile(path))

proc analyzeSpecies(allResults: seq[JsonNode]): seq[SpeciesStats] =
  ## Aggregate statistics across all runs for each species
  var statsBySpecies = initTable[string, SpeciesStats]()

  # Initialize species
  for speciesName in ["Economic", "Military", "Diplomatic", "Technology", "Espionage"]:
    statsBySpecies[speciesName] = SpeciesStats(
      name: speciesName,
      evolution: @[]
    )

  # Aggregate data from all runs
  for resultJson in allResults:
    let finalChampions = resultJson["finalChampions"]
    for champion in finalChampions:
      let speciesName = champion["species"].getStr()
      let winRate = champion["winRate"].getFloat()

      var stats = statsBySpecies[speciesName]
      stats.totalWins += int(winRate * 100)  # Approximate wins
      stats.totalGames += 100
      statsBySpecies[speciesName] = stats

    # Track evolution over generations
    let generations = resultJson["generations"]
    for genJson in generations:
      for speciesJson in genJson["species"]:
        let speciesName = speciesJson["type"].getStr()
        let avgFit = speciesJson["avgFitness"].getFloat()
        statsBySpecies[speciesName].evolution.add(avgFit)

  # Calculate final stats
  for speciesName, stats in statsBySpecies:
    var s = stats
    s.winRate = if s.totalGames > 0: (s.totalWins.float / s.totalGames.float) else: 0.0
    s.avgFitness = if s.evolution.len > 0: (s.evolution.sum / s.evolution.len.float) else: 0.0
    result.add(s)

  # Sort by win rate
  result.sort(proc(a, b: SpeciesStats): int = cmp(b.winRate, a.winRate))

proc detectBalanceIssues(speciesStats: seq[SpeciesStats]): seq[BalanceIssue] =
  ## Detect balance issues based on species performance
  result = @[]

  # Check for dominant strategy (>60% win rate)
  let topSpecies = speciesStats[0]
  if topSpecies.winRate > 0.6:
    result.add(BalanceIssue(
      severity: "CRITICAL",
      category: topSpecies.name,
      description: &"{topSpecies.name} strategy dominates with {topSpecies.winRate * 100:.1f}% win rate",
      evidence: &"Won {topSpecies.totalWins}/{topSpecies.totalGames} games across all runs",
      recommendation: &"Review {topSpecies.name.toLower()} bonuses and costs for overpowered mechanics"
    ))

  # Check for unviable strategy (<10% win rate)
  for species in speciesStats:
    if species.winRate < 0.1:
      result.add(BalanceIssue(
        severity: "HIGH",
        category: species.name,
        description: &"{species.name} strategy is unviable with {species.winRate * 100:.1f}% win rate",
        evidence: &"Won only {species.totalWins}/{species.totalGames} games",
        recommendation: &"Buff {species.name.toLower()} mechanics or reduce costs"
      ))

  # Check win rate variance (should be ~20% each in balanced 5-player game)
  let expectedWinRate = 1.0 / speciesStats.len.float
  let variance = speciesStats.mapIt(abs(it.winRate - expectedWinRate)).sum / speciesStats.len.float
  if variance > 0.12:
    result.add(BalanceIssue(
      severity: "MEDIUM",
      category: "Overall Balance",
      description: &"High win rate variance ({variance * 100:.1f}%) indicates imbalance",
      evidence: &"Species win rates deviate significantly from {expectedWinRate * 100:.0f}% expected average",
      recommendation: "Consider adjusting relative power levels across all strategies"
    ))

  # Check for stagnant evolution (fitness not improving)
  for species in speciesStats:
    if species.evolution.len >= 5:
      let early = species.evolution[0..2].sum / 3.0
      let late = species.evolution[^3..^1].sum / 3.0
      if late <= early * 1.05:  # Less than 5% improvement
        result.add(BalanceIssue(
          severity: "LOW",
          category: species.name,
          description: &"{species.name} evolution stagnated (fitness not improving)",
          evidence: &"Early fitness: {early:.3f}, Late fitness: {late:.3f}",
          recommendation: &"{species.name} may have hit a local optimum or ceiling"
        ))

proc generateReport(results: seq[JsonNode]): string =
  ## Generate comprehensive markdown report
  let speciesStats = analyzeSpecies(results)
  let issues = detectBalanceIssues(speciesStats)

  var report = ""

  # Header
  report.add("# EC4X Balance Analysis Report\n\n")
  report.add(&"**Generated:** {now().format(\"yyyy-MM-dd HH:mm:ss\")}\n\n")
  report.add(&"**Total Runs:** {results.len}\n")
  report.add(&"**Total Games:** {speciesStats.mapIt(it.totalGames).sum div 4}\n\n")

  report.add("---\n\n")

  # Executive Summary
  report.add("## Executive Summary\n\n")

  let topSpecies = speciesStats[0]
  let bottomSpecies = speciesStats[^1]

  if topSpecies.winRate > 0.6:
    report.add(&"🔴 **CRITICAL IMBALANCE DETECTED**\n\n")
    report.add(&"The **{topSpecies.name}** strategy dominates with {topSpecies.winRate * 100:.1f}% win rate, ")
    report.add(&"significantly outperforming other strategies.\n\n")
  elif topSpecies.winRate < 0.35:
    report.add(&"🟢 **GOOD BALANCE**\n\n")
    report.add(&"No single strategy dominates. Win rates are relatively balanced.\n\n")
  else:
    report.add(&"🟡 **MODERATE IMBALANCE**\n\n")
    report.add(&"{topSpecies.name} has a slight advantage ({topSpecies.winRate * 100:.1f}% win rate).\n\n")

  # Species Performance
  report.add("## Species Performance\n\n")
  report.add("| Rank | Species | Win Rate | Wins | Games | Avg Fitness |\n")
  report.add("|------|---------|----------|------|-------|-------------|\n")

  for i, species in speciesStats:
    let rank = i + 1
    let emoji = if rank == 1: "🥇" elif rank == 2: "🥈" elif rank == 3: "🥉" else: &"{rank}."
    report.add(&"| {emoji} | **{species.name}** | {species.winRate * 100:.1f}% | {species.totalWins} | {species.totalGames} | {species.avgFitness:.3f} |\n")

  report.add("\n")

  # Balance Issues
  if issues.len > 0:
    report.add("## Balance Issues Detected\n\n")

    # Group by severity
    let critical = issues.filterIt(it.severity == "CRITICAL")
    let high = issues.filterIt(it.severity == "HIGH")
    let medium = issues.filterIt(it.severity == "MEDIUM")
    let low = issues.filterIt(it.severity == "LOW")

    if critical.len > 0:
      report.add("### 🔴 Critical Issues\n\n")
      for issue in critical:
        report.add(&"#### {issue.category}: {issue.description}\n\n")
        report.add(&"**Evidence:** {issue.evidence}\n\n")
        report.add(&"**Recommendation:** {issue.recommendation}\n\n")

    if high.len > 0:
      report.add("### 🟠 High Priority Issues\n\n")
      for issue in high:
        report.add(&"#### {issue.category}: {issue.description}\n\n")
        report.add(&"**Evidence:** {issue.evidence}\n\n")
        report.add(&"**Recommendation:** {issue.recommendation}\n\n")

    if medium.len > 0:
      report.add("### 🟡 Medium Priority Issues\n\n")
      for issue in medium:
        report.add(&"**{issue.category}:** {issue.description}\n\n")

    if low.len > 0:
      report.add("### 🔵 Low Priority Issues\n\n")
      for issue in low:
        report.add(&"**{issue.category}:** {issue.description}\n\n")
  else:
    report.add("## ✅ No Major Balance Issues Detected\n\n")
    report.add("All species are performing within acceptable ranges.\n\n")

  # Evolution Trends
  report.add("## Evolution Trends\n\n")
  for species in speciesStats:
    if species.evolution.len >= 3:
      let trend = if species.evolution[^1] > species.evolution[0]: "📈 Improving" else: "📉 Declining"
      report.add(&"- **{species.name}**: {trend} (Start: {species.evolution[0]:.3f}, End: {species.evolution[^1]:.3f})\n")

  report.add("\n")

  # Recommendations
  report.add("## Next Steps\n\n")
  if issues.len > 0:
    report.add("1. Address critical and high-priority balance issues\n")
    report.add("2. Run longer evolution (50+ generations) for confirmation\n")
    report.add("3. Test fixes with targeted simulations\n")
    report.add("4. Monitor evolution trends for convergence\n")
  else:
    report.add("1. Run longer evolution tests for deeper analysis\n")
    report.add("2. Test edge cases and corner strategies\n")
    report.add("3. Validate with player playtesting\n")

  report.add("\n---\n\n")
  report.add("*Report generated by EC4X Coevolution Analysis Tool*\n")

  return report

# Main
when isMainModule:
  let resultsDir = "balance_results/coevolution"

  if not dirExists(resultsDir):
    echo "Error: Results directory not found: ", resultsDir
    quit(1)

  # Load all result files
  var results: seq[JsonNode] = @[]
  for file in walkFiles(resultsDir / "run_*.json"):
    echo "Loading: ", file
    results.add(loadCoevolutionResult(file))

  if results.len == 0:
    echo "Error: No result files found (run_*.json)"
    quit(1)

  # Generate report
  echo &"\nAnalyzing {results.len} coevolution runs..."
  let report = generateReport(results)

  # Save report
  let reportPath = resultsDir / "ANALYSIS_REPORT.md"
  writeFile(reportPath, report)

  echo &"\n✅ Analysis complete!"
  echo &"Report saved to: {reportPath}"
  echo ""
  echo "=" .repeat(70)
  echo report
  echo "=" .repeat(70)
