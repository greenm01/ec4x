## Performance Analyzer Module
##
## Analyzes RBA (Rule-Based AI) strategy performance from diagnostic data.
## Computes metrics like average prestige, treasury, colonies, win rates, etc.

import datamancer
import std/[tables, algorithm, sequtils, strformat]
import ../types
import ../data/[loader, statistics]

proc analyzeStrategies*(df: DataFrame): StrategyReport =
  ## Analyze performance by AI strategy
  ##
  ## Computes final-turn metrics aggregated by strategy:
  ## - Count (number of games played with this strategy)
  ## - Average prestige, treasury, colonies, ships
  ## - Standard deviation of prestige
  ## - Win rate (percentage finishing in top position)
  ##
  ## Args:
  ##   df: DataFrame with diagnostic data
  ##
  ## Returns:
  ##   StrategyReport with per-strategy statistics

  result = StrategyReport()
  result.strategies = initTable[string, StrategyStats]()

  if df.len == 0:
    result.totalGames = 0
    result.maxTurn = 0
    return

  # Get final turn data
  let finalTurnData = df.getFinalTurnData()
  result.maxTurn = df["turn", int].toSeq().max()

  # Count unique games (by game_seed if available)
  if "game_seed" in df.getKeys():
    let seeds = df["game_seed", int].toSeq()
    result.totalGames = seeds.deduplicate().len
  else:
    # Estimate from total rows / houses
    result.totalGames = df.len div 4  # Assuming 4 houses per game

  # Get unique strategies
  let strategies = finalTurnData["strategy", string].toSeq().deduplicate()

  # For each strategy, compute detailed stats
  for strategy in strategies:
    let strategyData = finalTurnData.filterByStrategy(strategy)

    var stats = StrategyStats()
    stats.count = strategyData.len

    # Average prestige and std dev
    if "prestige" in strategyData.getKeys():
      let prestigeVals = strategyData["prestige", float].toSeq()
      stats.avgPrestige = prestigeVals.mean()
      stats.stdPrestige = prestigeVals.stdDev()

    # Average treasury
    if "treasury" in strategyData.getKeys():
      let treasuryVals = strategyData["treasury", float].toSeq()
      stats.avgTreasury = treasuryVals.mean()

    # Average colonies
    if "total_colonies" in strategyData.getKeys():
      let colonyVals = strategyData["total_colonies", float].toSeq()
      stats.avgColonies = colonyVals.mean()

    # Average ships
    if "total_ships" in strategyData.getKeys():
      let shipVals = strategyData["total_ships", float].toSeq()
      stats.avgShips = shipVals.mean()

    # Average PU growth
    if "pu_growth" in strategyData.getKeys():
      let puVals = strategyData["pu_growth", float].toSeq()
      stats.avgPUGrowth = puVals.mean()

    # Win rate calculation (top prestige = win)
    # Count how many times this strategy had the max prestige in its game
    if "prestige" in finalTurnData.getKeys():
      var wins = 0
      # This is simplified - ideally we'd check max prestige per game
      # For now, use top 25th percentile as proxy
      let allPrestige = finalTurnData["prestige", float].toSeq()
      let topThreshold = percentile(allPrestige, 0.75)
      let prestigeVals = strategyData["prestige", float].toSeq()
      for p in prestigeVals:
        if p >= topThreshold:
          wins += 1
      stats.winRate = if stats.count > 0: (float(wins) / float(stats.count)) * 100.0 else: 0.0

    result.strategies[strategy] = stats

proc rankStrategies*(report: StrategyReport): seq[tuple[name: string, stats: StrategyStats]] =
  ## Rank strategies by average prestige (descending)
  ##
  ## Returns:
  ##   Sequence of (strategy_name, stats) tuples sorted by prestige
  result = newSeq[tuple[name: string, stats: StrategyStats]]()

  for name, stats in report.strategies.pairs():
    result.add((name, stats))

  result.sort do (a, b: tuple[name: string, stats: StrategyStats]) -> int:
    # Sort descending by prestige
    if a.stats.avgPrestige > b.stats.avgPrestige:
      return -1
    elif a.stats.avgPrestige < b.stats.avgPrestige:
      return 1
    else:
      return 0

proc analyzeEconomy*(df: DataFrame): EconomyStats =
  ## Analyze economic performance metrics
  ##
  ## Args:
  ##   df: DataFrame with diagnostic data
  ##
  ## Returns:
  ##   EconomyStats with economic metrics
  result = EconomyStats()

  if df.len == 0:
    return

  # Average treasury (all turns)
  if "treasury" in df.getKeys():
    let treasuryVals = df["treasury", float].toSeq()
    result.avgTreasury = treasuryVals.mean()

  # Average PU growth
  if "pu_growth" in df.getKeys():
    let puVals = df["pu_growth", float].toSeq()
    result.avgPUGrowth = puVals.mean()

  # Zero-spend turns analysis
  if "zero_spend_turns" in df.getKeys():
    let zeroSpendVals = df["zero_spend_turns", float].toSeq()
    result.avgZeroSpendTurns = zeroSpendVals.mean()

    # Chronic zero-spend rate (>5 turns)
    var chronicCount = 0
    for val in zeroSpendVals:
      if val > 5.0:
        chronicCount += 1
    result.chronicZeroSpendRate = if df.len > 0: (float(chronicCount) / float(df.len)) * 100.0 else: 0.0

proc analyzeMilitary*(df: DataFrame): MilitaryStats =
  ## Analyze military performance metrics
  ##
  ## Args:
  ##   df: DataFrame with diagnostic data
  ##
  ## Returns:
  ##   MilitaryStats with military metrics
  result = MilitaryStats()

  if df.len == 0:
    return

  # Average total ships
  if "total_ships" in df.getKeys():
    let shipVals = df["total_ships", float].toSeq()
    result.avgTotalShips = shipVals.mean()

  # Average total fighters
  if "total_fighters" in df.getKeys():
    let fighterVals = df["total_fighters", float].toSeq()
    result.avgTotalFighters = fighterVals.mean()

  # Idle carrier analysis
  if "idle_carriers" in df.getKeys() and "total_carriers" in df.getKeys():
    let idleVals = df["idle_carriers", float].toSeq()
    let totalVals = df["total_carriers", float].toSeq()

    var idleRates = newSeq[float]()
    for i in 0 ..< idleVals.len:
      if totalVals[i] > 0:
        idleRates.add(idleVals[i] / totalVals[i])

    if idleRates.len > 0:
      result.avgIdleCarrierRate = idleRates.mean() * 100.0

      # Count games with >20% idle
      var highIdleCount = 0
      for rate in idleRates:
        if rate > 0.2:
          highIdleCount += 1
      result.highIdleGamesPercent = if idleRates.len > 0: (float(highIdleCount) / float(idleRates.len)) * 100.0 else: 0.0

proc analyzeEspionage*(df: DataFrame): EspionageStats =
  ## Analyze espionage activity metrics
  ##
  ## Args:
  ##   df: DataFrame with diagnostic data
  ##
  ## Returns:
  ##   EspionageStats with espionage metrics
  result = EspionageStats()

  if df.len == 0:
    return

  # Count spy missions
  if "spy_planet" in df.getKeys():
    let spyVals = df["spy_planet", int].toSeq()
    result.totalSpyMissions = spyVals.sum()

  # Count hack missions
  if "hack_starbase" in df.getKeys():
    let hackVals = df["hack_starbase", int].toSeq()
    result.totalHackMissions = hackVals.sum()

  # Percentage of games with espionage
  if "game_seed" in df.getKeys():
    var gamesWithEsp = initTable[int, bool]()

    let seeds = df["game_seed", int].toSeq()
    let spyVals = if "spy_planet" in df.getKeys(): df["spy_planet", int].toSeq() else: @[]
    let hackVals = if "hack_starbase" in df.getKeys(): df["hack_starbase", int].toSeq() else: @[]

    for i in 0 ..< seeds.len:
      let seed = seeds[i]
      let hasSpy = if i < spyVals.len: spyVals[i] > 0 else: false
      let hasHack = if i < hackVals.len: hackVals[i] > 0 else: false

      if hasSpy or hasHack:
        gamesWithEsp[seed] = true

    let uniqueGames = seeds.deduplicate().len
    result.gamesWithEspionagePercent = if uniqueGames > 0: (float(gamesWithEsp.len) / float(uniqueGames)) * 100.0 else: 0.0
