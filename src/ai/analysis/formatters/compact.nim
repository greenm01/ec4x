## Compact Formatter Module
##
## Generates token-efficient output optimized for Claude analysis.
## Target: ~1500 tokens using markdown tables without verbose explanations.

import std/[strformat, tables, algorithm]
import ../types
import ../analyzers/performance

proc formatCompact*(report: AnalysisReport): string =
  ## Format analysis report in compact markdown format for Claude
  ##
  ## This format prioritizes:
  ## - Markdown tables for structured data
  ## - Minimal prose
  ## - Critical information only
  ##
  ## Target: ~1500 tokens
  ##
  ## Args:
  ##   report: Complete analysis report
  ##
  ## Returns:
  ##   Compact markdown string
  result = "## Balance Analysis\n\n"
  result &= fmt"**Games:** {report.metadata.numGames}  |  **Turns:** {report.metadata.numTurns}\n\n"

  # Strategy Performance Table
  result &= "### Strategy Performance\n\n"
  result &= "| Strategy | Games | Prestige | Treasury | Colonies | Win% |\n"
  result &= "|----------|-------|----------|----------|----------|------|\n"

  let ranked = rankStrategies(report.strategyReport)
  for item in ranked:
    let s = item.stats
    result &= fmt"| {item.name} | {s.count} | {s.avgPrestige:.0f} | {s.avgTreasury:.0f} | {s.avgColonies:.1f} | {s.winRate:.1f}% |" & "\n"

  # Economy
  result &= "\n### Economy\n\n"
  result &= fmt"- Avg Treasury: {report.economyStats.avgTreasury:.0f}" & "\n"
  result &= fmt"- Avg PU Growth: {report.economyStats.avgPUGrowth:.1f}" & "\n"
  result &= fmt"- Chronic Zero-Spend: {report.economyStats.chronicZeroSpendRate:.1f}%" & "\n"

  # Military
  result &= "\n### Military\n\n"
  result &= fmt"- Avg Ships: {report.militaryStats.avgTotalShips:.1f}" & "\n"
  result &= fmt"- Avg Fighters: {report.militaryStats.avgTotalFighters:.1f}" & "\n"
  result &= fmt"- Idle Carrier Rate: {report.militaryStats.avgIdleCarrierRate:.1f}%" & "\n"

  # Espionage
  result &= "\n### Espionage\n\n"
  result &= fmt"- Spy Missions: {report.espionageStats.totalSpyMissions}" & "\n"
  result &= fmt"- Hack Missions: {report.espionageStats.totalHackMissions}" & "\n"
  result &= fmt"- Games w/ Espionage: {report.espionageStats.gamesWithEspionagePercent:.1f}%" & "\n"

  # Critical Issues
  if report.redFlags.critical.len > 0:
    result &= "\n### ❌ Critical Issues\n\n"
    for flag in report.redFlags.critical:
      result &= fmt"- **{flag.title}:** {flag.description}" & "\n"

  # High Priority Issues
  if report.redFlags.high.len > 0:
    result &= "\n### ⚠️ High Priority\n\n"
    for flag in report.redFlags.high:
      result &= fmt"- **{flag.title}:** {flag.description}" & "\n"

  # Medium Issues (only titles)
  if report.redFlags.medium.len > 0:
    result &= "\n### Medium Priority\n\n"
    for flag in report.redFlags.medium:
      result &= fmt"- {flag.title}" & "\n"

  # All clear
  if report.redFlags.critical.len == 0 and report.redFlags.high.len == 0:
    result &= "\n### ✅ Status\n\nNo critical or high-priority issues detected.\n"
