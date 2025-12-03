## Red Flags Analyzer Module
##
## Detects balance issues and anomalies in diagnostic data.
## Based on Phase 2 gap analysis criteria from the original Python scripts.

import datamancer
import std/[tables, sequtils, strformat, strutils]
import ../types
import ../data/[loader, statistics]

proc detectCapacityViolations*(df: DataFrame): seq[RedFlag] =
  ## Detect capacity violations (CRITICAL)
  ##
  ## Target: < 2% of all data points should have violations
  result = @[]

  if df.len == 0 or "capacity_violations" notin df.getKeys():
    return

  let violations = df["capacity_violations", int].toSeq()
  var violationCount = 0
  for v in violations:
    if v > 0:
      violationCount += 1

  let rate = (float(violationCount) / float(df.len)) * 100.0

  if rate > 2.0:
    var flag = newRedFlag(SeverityLevel.Critical, "Capacity Violations",
                          &"Capacity violations detected in {rate:.1f}% of data points")
    flag.impact = "Ships/facilities exceeding planetary capacity"
    flag.rootCause = "Insufficient capacity checks or aggressive build orders"
    flag.addEvidence(&"{violationCount} violations across {df.len} data points")
    result.add(flag)

proc detectEspionageIssues*(df: DataFrame): seq[RedFlag] =
  ## Detect espionage system issues (CRITICAL)
  ##
  ## Target: > 80% of games should have at least one espionage mission
  result = @[]

  if df.len == 0:
    return

  let hasGameSeed = "game_seed" in df.getKeys()
  let hasSpyPlanet = "spy_planet" in df.getKeys()
  let hasHackStarbase = "hack_starbase" in df.getKeys()

  if not (hasGameSeed and (hasSpyPlanet or hasHackStarbase)):
    return

  # Count games with espionage activity
  var gamesWithEsp = initTable[int, bool]()
  let seeds = df["game_seed", int].toSeq()
  let spyVals = if hasSpyPlanet: df["spy_planet", int].toSeq() else: @[]
  let hackVals = if hasHackStarbase: df["hack_starbase", int].toSeq() else: @[]

  let totalSpy = spyVals.sum()
  let totalHack = hackVals.sum()

  for i in 0 ..< seeds.len:
    let seed = seeds[i]
    let hasSpy = if i < spyVals.len: spyVals[i] > 0 else: false
    let hasHack = if i < hackVals.len: hackVals[i] > 0 else: false

    if hasSpy or hasHack:
      gamesWithEsp[seed] = true

  let uniqueGames = seeds.deduplicate().len
  let espRate = if uniqueGames > 0: (float(gamesWithEsp.len) / float(uniqueGames)) * 100.0 else: 0.0

  if espRate < 80.0:
    var flag = newRedFlag(SeverityLevel.Critical, "Insufficient Espionage Activity",
                          &"Only {espRate:.1f}% of games used espionage missions")
    flag.impact = "Espionage system underutilized or broken"
    flag.rootCause = "AI not generating spy/hack orders or missions failing"
    flag.addEvidence(&"Total SpyPlanet missions: {totalSpy}")
    flag.addEvidence(&"Total HackStarbase missions: {totalHack}")
    flag.addEvidence(&"Games with espionage: {gamesWithEsp.len} / {uniqueGames}")
    result.add(flag)

proc detectIdleCarriers*(df: DataFrame): seq[RedFlag] =
  ## Detect high idle carrier rates (HIGH)
  ##
  ## Target: < 20% average idle carrier rate
  result = @[]

  if df.len == 0:
    return

  let hasIdle = "idle_carriers" in df.getKeys()
  let hasTotal = "total_carriers" in df.getKeys()

  if not (hasIdle and hasTotal):
    return

  let idleVals = df["idle_carriers", float].toSeq()
  let totalVals = df["total_carriers", float].toSeq()

  var idleRates = newSeq[float]()
  for i in 0 ..< idleVals.len:
    if totalVals[i] > 0:
      idleRates.add(idleVals[i] / totalVals[i])

  if idleRates.len == 0:
    return

  let avgRate = idleRates.mean() * 100.0

  if avgRate > 20.0:
    var flag = newRedFlag(SeverityLevel.High, "High Idle Carrier Rate",
                          &"Average idle carrier rate: {avgRate:.1f}%")
    flag.impact = "Inefficient carrier utilization"
    flag.rootCause = "Carriers deployed without fighters or poor fleet management"
    flag.addEvidence(&"Target: < 20% idle rate")
    result.add(flag)

proc detectELIMeshIssues*(df: DataFrame): seq[RedFlag] =
  ## Detect invasions without ELI mesh support (HIGH)
  ##
  ## Target: < 50% of invasions without ELI mesh
  result = @[]

  if df.len == 0:
    return

  let hasTotal = "total_invasions" in df.getKeys()
  let hasNoELI = "invasions_no_eli" in df.getKeys()

  if not (hasTotal and hasNoELI):
    return

  let totalVals = df["total_invasions", int].toSeq()
  let noELIVals = df["invasions_no_eli", int].toSeq()

  var rates = newSeq[float]()
  for i in 0 ..< totalVals.len:
    if totalVals[i] > 0:
      rates.add(float(noELIVals[i]) / float(totalVals[i]))

  if rates.len == 0:
    return

  let avgRate = rates.mean() * 100.0

  if avgRate > 50.0:
    var flag = newRedFlag(SeverityLevel.High, "Invasions Without ELI Mesh",
                          &"{avgRate:.1f}% of invasions lack ELI mesh support")
    flag.impact = "Reduced invasion success rates and intel gathering"
    flag.rootCause = "Insufficient scout deployment or coordination issues"
    flag.addEvidence(&"Target: < 50% without ELI")
    result.add(flag)

proc detectRaiderIssues*(df: DataFrame): seq[RedFlag] =
  ## Detect raider ambush success rate issues (HIGH)
  ##
  ## Target: > 35% success rate when CLK > ELI
  result = @[]

  if df.len == 0:
    return

  let hasAttempts = "raider_attempts" in df.getKeys()
  let hasSuccess = "raider_success" in df.getKeys()

  if not (hasAttempts and hasSuccess):
    return

  let attemptVals = df["raider_attempts", int].toSeq()
  let successVals = df["raider_success", int].toSeq()

  var rates = newSeq[float]()
  for i in 0 ..< attemptVals.len:
    if attemptVals[i] > 0:
      rates.add(float(successVals[i]) / float(attemptVals[i]))

  if rates.len == 0:
    return

  let avgRate = rates.mean() * 100.0

  if avgRate < 35.0:
    var flag = newRedFlag(SeverityLevel.High, "Low Raider Success Rate",
                          &"Raider ambush success rate: {avgRate:.1f}%")
    flag.impact = "Raiders ineffective at intercepting fleets"
    flag.rootCause = "Insufficient CLK advantage or positioning issues"
    flag.addEvidence(&"Target: > 35% success rate")
    result.add(flag)

proc detectCLKWithoutRaiders*(df: DataFrame): seq[RedFlag] =
  ## Detect CLK research without Raider usage (MEDIUM)
  ##
  ## Target: < 10% of data points
  result = @[]

  if df.len == 0 or "clk_no_raiders" notin df.getKeys():
    return

  let clkNoRaiders = df["clk_no_raiders", string].toSeq()

  var count = 0
  for val in clkNoRaiders:
    if val.toLowerAscii() == "true":
      count += 1

  let rate = (float(count) / float(df.len)) * 100.0

  if rate > 10.0:
    var flag = newRedFlag(SeverityLevel.Medium, "CLK Research Without Raiders",
                          &"{rate:.1f}% of data points have CLK but no Raiders")
    flag.impact = "Wasted research on CLK without utilizing Raiders"
    flag.rootCause = "AI not building Raiders after CLK research"
    flag.addEvidence(&"Target: < 10%")
    result.add(flag)

proc detectUndefendedColonies*(df: DataFrame): seq[RedFlag] =
  ## Detect undefended colonies (MEDIUM)
  ##
  ## Target: < 30% average undefended rate
  result = @[]

  if df.len == 0:
    return

  let hasUndefended = "undefended_colonies" in df.getKeys()
  let hasTotal = "total_colonies" in df.getKeys()

  if not (hasUndefended and hasTotal):
    return

  let undefVals = df["undefended_colonies", float].toSeq()
  let totalVals = df["total_colonies", float].toSeq()

  var rates = newSeq[float]()
  for i in 0 ..< undefVals.len:
    if totalVals[i] > 0:
      rates.add(undefVals[i] / totalVals[i])

  if rates.len == 0:
    return

  let avgRate = rates.mean() * 100.0

  if avgRate > 30.0:
    var flag = newRedFlag(SeverityLevel.Medium, "High Undefended Colony Rate",
                          &"{avgRate:.1f}% of colonies lack defense")
    flag.impact = "Colonies vulnerable to invasion"
    flag.rootCause = "Insufficient fleet or starbase deployment"
    flag.addEvidence(&"Target: < 30% undefended")
    result.add(flag)

proc detectMothballingIssues*(df: DataFrame): seq[RedFlag] =
  ## Detect mothballing usage issues (MEDIUM)
  ##
  ## Target: > 70% of games should use mothballing
  result = @[]

  if df.len == 0:
    return

  let hasGameSeed = "game_seed" in df.getKeys()
  let hasMothball = "mothball_used" in df.getKeys()
  let hasTurn = "turn" in df.getKeys()

  if not (hasGameSeed and hasMothball and hasTurn):
    return

  # Get final turn data
  let finalTurnData = df.getFinalTurnData()

  let seeds = finalTurnData["game_seed", int].toSeq()
  let mothballVals = finalTurnData["mothball_used", int].toSeq()

  var gamesWithMothball = 0
  for val in mothballVals:
    if val > 0:
      gamesWithMothball += 1

  let uniqueGames = seeds.deduplicate().len
  let rate = if uniqueGames > 0: (float(gamesWithMothball) / float(uniqueGames)) * 100.0 else: 0.0

  if rate < 70.0:
    var flag = newRedFlag(SeverityLevel.Medium, "Low Mothballing Usage",
                          &"Only {rate:.1f}% of games used mothballing")
    flag.impact = "Inefficient late-game fleet maintenance"
    flag.rootCause = "AI not mothballing idle fleets to reduce costs"
    flag.addEvidence(&"Target: > 70% usage")
    result.add(flag)

proc detectAll*(df: DataFrame): RedFlagReport =
  ## Run all red flag detectors and organize by severity
  ##
  ## Args:
  ##   df: DataFrame with diagnostic data
  ##
  ## Returns:
  ##   RedFlagReport with flags organized by severity
  result = RedFlagReport()

  var allFlags = newSeq[RedFlag]()

  # Run all detectors
  allFlags.add(detectCapacityViolations(df))
  allFlags.add(detectEspionageIssues(df))
  allFlags.add(detectIdleCarriers(df))
  allFlags.add(detectELIMeshIssues(df))
  allFlags.add(detectRaiderIssues(df))
  allFlags.add(detectCLKWithoutRaiders(df))
  allFlags.add(detectUndefendedColonies(df))
  allFlags.add(detectMothballingIssues(df))

  # Organize by severity
  result.critical = @[]
  result.high = @[]
  result.medium = @[]
  result.low = @[]

  for flag in allFlags:
    case flag.severity
    of SeverityLevel.Critical:
      result.critical.add(flag)
    of SeverityLevel.High:
      result.high.add(flag)
    of SeverityLevel.Medium:
      result.medium.add(flag)
    of SeverityLevel.Low:
      result.low.add(flag)
    of SeverityLevel.Pass:
      discard
