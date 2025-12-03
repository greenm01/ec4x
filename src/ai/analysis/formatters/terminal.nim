## Terminal Formatter Module
##
## Formats analysis reports for rich terminal output using terminaltables.
## Produces human-friendly output with Unicode box-drawing characters.

import terminaltables
import std/[strformat, strutils, tables, algorithm]
import ../types
import ../analyzers/performance

proc formatStrategyTable*(report: StrategyReport): string =
  ## Format strategy performance as a terminal table
  ##
  ## Returns:
  ##   Formatted table string with Unicode borders
  let table = newUnicodeTable()
  table.setHeaders(@["Strategy", "Games", "Prestige", "Treasury", "Colonies", "Ships", "Win%"])

  # Rank strategies by prestige
  let ranked = rankStrategies(report)

  for item in ranked:
    let name = item.name
    let s = item.stats
    table.addRow(@[
      name,
      $s.count,
      fmt"{s.avgPrestige:.0f} (±{s.stdPrestige:.0f})",
      fmt"{s.avgTreasury:.0f}",
      fmt"{s.avgColonies:.1f}",
      fmt"{s.avgShips:.1f}",
      fmt"{s.winRate:.1f}%"
    ])

  result = "\n📈 STRATEGY PERFORMANCE\n\n"
  result &= table.render()
  result &= fmt"\n\nTotal games: {report.totalGames}  |  Max turns: {report.maxTurn}\n"

proc formatEconomyStats*(stats: EconomyStats): string =
  ## Format economy statistics
  result = "\n💰 ECONOMY METRICS\n\n"
  result &= fmt"  Average Treasury:        {stats.avgTreasury:>12.0f}" & "\n"
  result &= fmt"  Average PU Growth:       {stats.avgPUGrowth:>12.1f}" & "\n"
  result &= fmt"  Avg Zero-Spend Turns:    {stats.avgZeroSpendTurns:>12.1f}" & "\n"
  result &= fmt"  Chronic Zero-Spend Rate: {stats.chronicZeroSpendRate:>12.1f}%" & "\n"

proc formatMilitaryStats*(stats: MilitaryStats): string =
  ## Format military statistics
  result = "\n⚔️  MILITARY METRICS\n\n"
  result &= fmt"  Average Total Ships:     {stats.avgTotalShips:>12.1f}" & "\n"
  result &= fmt"  Average Total Fighters:  {stats.avgTotalFighters:>12.1f}" & "\n"
  result &= fmt"  Avg Idle Carrier Rate:   {stats.avgIdleCarrierRate:>12.1f}%" & "\n"
  result &= fmt"  High Idle Games:         {stats.highIdleGamesPercent:>12.1f}%" & "\n"

proc formatEspionageStats*(stats: EspionageStats): string =
  ## Format espionage statistics
  result = "\n🕵️  ESPIONAGE METRICS\n\n"
  result &= fmt"  Total Spy Missions:      {stats.totalSpyMissions:>12}" & "\n"
  result &= fmt"  Total Hack Missions:     {stats.totalHackMissions:>12}" & "\n"
  result &= fmt"  Games with Espionage:    {stats.gamesWithEspionagePercent:>12.1f}%" & "\n"

proc formatRedFlags*(report: RedFlagReport): string =
  ## Format red flags with severity indicators
  result = "\n🚨 RED FLAGS & ISSUES\n\n"

  # Critical flags
  if report.critical.len > 0:
    result &= "❌ CRITICAL:\n"
    for flag in report.critical:
      result &= fmt"  • {flag.title}" & "\n"
      result &= fmt"    {flag.description}" & "\n"
      for evidence in flag.evidence:
        result &= fmt"    → {evidence}" & "\n"
      result &= "\n"

  # High priority flags
  if report.high.len > 0:
    result &= "⚠️  HIGH PRIORITY:\n"
    for flag in report.high:
      result &= fmt"  • {flag.title}" & "\n"
      result &= fmt"    {flag.description}" & "\n"
      result &= "\n"

  # Medium priority flags
  if report.medium.len > 0:
    result &= "ℹ️  MEDIUM PRIORITY:\n"
    for flag in report.medium:
      result &= fmt"  • {flag.title}" & "\n"
      result &= fmt"    {flag.description}" & "\n"
      result &= "\n"

  # All clear message
  if report.critical.len == 0 and report.high.len == 0 and report.medium.len == 0:
    result &= "✅ No significant issues detected!\n\n"

proc formatTerminal*(report: AnalysisReport): string =
  ## Format complete analysis report for terminal display
  ##
  ## This is the main terminal formatter that combines all sections.
  ##
  ## Args:
  ##   report: Complete analysis report
  ##
  ## Returns:
  ##   Formatted string for terminal output
  result = "\n" & "=".repeat(80) & "\n"
  result &= "EC4X BALANCE ANALYSIS REPORT\n"
  result &= "=".repeat(80) & "\n"

  # Strategy performance table
  result &= formatStrategyTable(report.strategyReport)

  # Economy metrics
  result &= formatEconomyStats(report.economyStats)

  # Military metrics
  result &= formatMilitaryStats(report.militaryStats)

  # Espionage metrics
  result &= formatEspionageStats(report.espionageStats)

  # Red flags
  result &= formatRedFlags(report.redFlags)

  # Footer
  result &= "=".repeat(80) & "\n"
  result &= fmt"Generated: {report.metadata.timestamp}" & "\n"
  if report.metadata.gitHash.len > 0:
    result &= fmt"Git hash: {report.metadata.gitHash}" & "\n"
  result &= "=".repeat(80) & "\n"

proc formatSummary*(report: AnalysisReport): string =
  ## Format quick summary for terminal (shortened version)
  ##
  ## This provides a condensed view focusing on key metrics.
  result = "\n" & "=".repeat(60) & "\n"
  result &= "EC4X QUICK SUMMARY\n"
  result &= "=".repeat(60) & "\n"

  # Just show top 3 strategies
  let ranked = rankStrategies(report.strategyReport)
  result &= "\nTop Strategies:\n"
  for i in 0 ..< min(3, ranked.len):
    let item = ranked[i]
    result &= fmt"  {i+1}. {item.name}: {item.stats.avgPrestige:.0f} prestige" & "\n"

  # Critical issues only
  if report.redFlags.critical.len > 0:
    result &= "\n❌ Critical Issues:\n"
    for flag in report.redFlags.critical:
      result &= fmt"  • {flag.title}" & "\n"
  else:
    result &= "\n✅ No critical issues\n"

  result &= "\n" & "=".repeat(60) & "\n"
