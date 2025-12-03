## Markdown Formatter Module
##
## Generates detailed markdown reports for git commits and documentation.
## More comprehensive than compact format, suitable for long-term reference.

import std/[strformat, tables, algorithm]
import ../types
import ../analyzers/performance

proc formatMarkdown*(report: AnalysisReport): string =
  ## Format complete analysis report as detailed markdown
  ##
  ## This format is suitable for:
  ## - Git-committable documentation
  ## - Historical records
  ## - Detailed analysis reports
  ##
  ## Args:
  ##   report: Complete analysis report
  ##
  ## Returns:
  ##   Detailed markdown string
  result = "# EC4X Balance Analysis Report\n\n"

  # Metadata
  result &= "## Test Configuration\n\n"
  result &= fmt"- **Games Analyzed:** {report.metadata.numGames}" & "\n"
  result &= fmt"- **Turns per Game:** {report.metadata.numTurns}" & "\n"
  result &= fmt"- **Generated:** {report.metadata.timestamp}" & "\n"
  if report.metadata.gitHash.len > 0:
    result &= fmt"- **Git Hash:** `{report.metadata.gitHash}`" & "\n"
  result &= "\n"

  # Executive Summary
  result &= "## Executive Summary\n\n"
  let ranked = rankStrategies(report.strategyReport)
  if ranked.len > 0:
    let topStrategy = ranked[0]
    result &= fmt"- **Dominant Strategy:** {topStrategy.name} ({topStrategy.stats.avgPrestige:.0f} avg prestige)" & "\n"
  result &= fmt"- **Critical Issues:** {report.redFlags.critical.len}" & "\n"
  result &= fmt"- **High Priority Issues:** {report.redFlags.high.len}" & "\n"
  result &= fmt"- **Medium Priority Issues:** {report.redFlags.medium.len}" & "\n"
  result &= "\n"

  # Strategy Performance
  result &= "## Strategy Performance Analysis\n\n"
  result &= "### Overall Rankings\n\n"
  result &= "| Rank | Strategy | Games | Avg Prestige | Std Dev | Avg Treasury | Avg Colonies | Avg Ships | Win Rate |\n"
  result &= "|------|----------|-------|--------------|---------|--------------|--------------|-----------|----------|\n"

  for i, item in ranked:
    let s = item.stats
    result &= fmt"| {i+1} | {item.name} | {s.count} | {s.avgPrestige:.0f} | {s.stdPrestige:.0f} | {s.avgTreasury:.0f} | {s.avgColonies:.1f} | {s.avgShips:.1f} | {s.winRate:.1f}% |" & "\n"

  result &= "\n"

  # Detailed Strategy Analysis
  result &= "### Strategy Details\n\n"
  for i, item in ranked:
    result &= fmt"#### {i+1}. {item.name}\n\n"
    let s = item.stats
    result &= fmt"- **Sample Size:** {s.count} games" & "\n"
    result &= fmt"- **Average Prestige:** {s.avgPrestige:.0f} (±{s.stdPrestige:.0f})" & "\n"
    result &= fmt"- **Average Treasury:** {s.avgTreasury:.0f}" & "\n"
    result &= fmt"- **Average Colonies:** {s.avgColonies:.2f}" & "\n"
    result &= fmt"- **Average Ships:** {s.avgShips:.2f}" & "\n"
    result &= fmt"- **Average PU Growth:** {s.avgPUGrowth:.1f}" & "\n"
    result &= fmt"- **Win Rate:** {s.winRate:.1f}%" & "\n"
    result &= "\n"

  # Economy Analysis
  result &= "## Economy Analysis\n\n"
  result &= "### Key Metrics\n\n"
  result &= fmt"- **Average Treasury:** {report.economyStats.avgTreasury:.0f}" & "\n"
  result &= fmt"- **Average PU Growth:** {report.economyStats.avgPUGrowth:.1f}" & "\n"
  result &= fmt"- **Average Zero-Spend Turns:** {report.economyStats.avgZeroSpendTurns:.2f}" & "\n"
  result &= fmt"- **Chronic Zero-Spend Rate:** {report.economyStats.chronicZeroSpendRate:.1f}%" & "\n"
  result &= "\n"

  # Military Analysis
  result &= "## Military Analysis\n\n"
  result &= "### Fleet Metrics\n\n"
  result &= fmt"- **Average Total Ships:** {report.militaryStats.avgTotalShips:.1f}" & "\n"
  result &= fmt"- **Average Total Fighters:** {report.militaryStats.avgTotalFighters:.1f}" & "\n"
  result &= fmt"- **Average Idle Carrier Rate:** {report.militaryStats.avgIdleCarrierRate:.1f}%" & "\n"
  result &= fmt"- **High Idle Games (>20%):** {report.militaryStats.highIdleGamesPercent:.1f}%" & "\n"
  result &= "\n"

  # Espionage Analysis
  result &= "## Espionage Analysis\n\n"
  result &= "### Mission Statistics\n\n"
  result &= fmt"- **Total Spy Planet Missions:** {report.espionageStats.totalSpyMissions}" & "\n"
  result &= fmt"- **Total Hack Starbase Missions:** {report.espionageStats.totalHackMissions}" & "\n"
  result &= fmt"- **Games with Espionage Activity:** {report.espionageStats.gamesWithEspionagePercent:.1f}%" & "\n"
  result &= "\n"

  # Red Flags
  result &= "## Issues and Red Flags\n\n"

  if report.redFlags.critical.len > 0:
    result &= "### ❌ Critical Issues\n\n"
    for flag in report.redFlags.critical:
      result &= fmt"#### {flag.title}\n\n"
      result &= fmt"**Description:** {flag.description}\n\n"
      if flag.impact.len > 0:
        result &= fmt"**Impact:** {flag.impact}\n\n"
      if flag.rootCause.len > 0:
        result &= fmt"**Root Cause:** {flag.rootCause}\n\n"
      if flag.evidence.len > 0:
        result &= "**Evidence:**\n\n"
        for evidence in flag.evidence:
          result &= fmt"- {evidence}" & "\n"
        result &= "\n"

  if report.redFlags.high.len > 0:
    result &= "### ⚠️ High Priority Issues\n\n"
    for flag in report.redFlags.high:
      result &= fmt"#### {flag.title}\n\n"
      result &= fmt"**Description:** {flag.description}\n\n"
      if flag.impact.len > 0:
        result &= fmt"**Impact:** {flag.impact}\n\n"

  if report.redFlags.medium.len > 0:
    result &= "### ℹ️ Medium Priority Issues\n\n"
    for flag in report.redFlags.medium:
      result &= fmt"- **{flag.title}:** {flag.description}" & "\n"
    result &= "\n"

  if report.redFlags.critical.len == 0 and report.redFlags.high.len == 0 and report.redFlags.medium.len == 0:
    result &= "✅ **No significant issues detected.**\n\n"

  # Recommendations
  result &= "## Recommendations\n\n"
  if report.redFlags.critical.len > 0:
    result &= "### Immediate Action Required\n\n"
    for flag in report.redFlags.critical:
      result &= fmt"- **{flag.title}:** Address this critical issue before further testing" & "\n"
    result &= "\n"

  # Footer
  result &= "---\n\n"
  result &= fmt"*Report generated on {report.metadata.timestamp}*\n"
