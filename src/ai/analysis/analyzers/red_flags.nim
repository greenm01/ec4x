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
  ## PHASE F: DISABLED - This metric was misleading
  ##
  ## Original metric tracked "invasions without ELI mesh" which doesn't make sense
  ## because scouts can be destroyed in space combat before ground invasions occur.
  ##
  ## ELI mesh (3+ scouts) is critical for:
  ## 1. **Space combat** - Intelligence bonus (scout_count metric)
  ## 2. **Raider detection** - Prevents ambush/surprise attacks (detectRaiderIssues handles this)
  ## 3. **Scout espionage** - Spy missions (spy_planet, hack_starbase metrics)
  ##
  ## Proper ELI mesh tracking is handled by:
  ## - detectRaiderIssues() - Tracks raider ambush success (low rate = poor ELI mesh)
  ## - detectCLKWithoutRaiders() - Tracks CLK tech without raider utilization
  ## - Future: Can add scout espionage utilization tracking
  result = @[]

proc detectRaiderIssues*(df: DataFrame): seq[RedFlag] =
  ## Detect raider ambush success rate issues (CRITICAL)
  ##
  ## Phase F: Upgraded to CRITICAL severity
  ## Raiders use ELI checks for ambush/surprise attacks
  ## Low success rate indicates poor ELI mesh (insufficient scouts) or CLK disadvantage
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
    var flag = newRedFlag(SeverityLevel.Critical, "Low Raider Success Rate",
                          &"Raider ambush/surprise success rate: {avgRate:.1f}%")
    flag.impact = "Raiders ineffective at ambush (lying in wait) and surprise (space combat) - indicates poor defensive ELI mesh"
    flag.rootCause = "Enemy has ELI mesh (3+ scouts) detecting raiders, or insufficient CLK advantage"
    flag.addEvidence(&"Target: > 35% success rate when CLK > ELI")
    flag.addEvidence(&"Raider modes: Ambush (stealth positioning) and Surprise (space combat advantage)")
    flag.addEvidence(&"Enemy ELI mesh (3+ scouts) can detect raiders and prevent both modes")
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

proc detectPlanetaryShieldUsage*(df: DataFrame): seq[RedFlag] =
  ## Detect underutilization of planetary shields (HIGH)
  ##
  ## Phase F: Track planetary shield deployment
  ## Planetary shields provide passive defense (DS=100) and slow invasions
  ## Cost: 67 PP (after Phase F reduction from 100)
  ##
  ## Target: > 40% of high-value colonies should have shields
  result = @[]

  if df.len == 0:
    return

  let hasShields = "planetary_shield_units" in df.getKeys()
  let hasColonies = "total_colonies" in df.getKeys()

  if not (hasShields and hasColonies):
    return

  let shieldVals = df["planetary_shield_units", int].toSeq()
  let colonyVals = df["total_colonies", int].toSeq()

  var shieldRates = newSeq[float]()
  for i in 0 ..< shieldVals.len:
    if colonyVals[i] > 0:
      # Shield rate per colony
      shieldRates.add(float(shieldVals[i]) / float(colonyVals[i]))

  if shieldRates.len == 0:
    return

  let avgShieldRate = shieldRates.mean() * 100.0

  if avgShieldRate < 40.0:
    var flag = newRedFlag(SeverityLevel.High, "Low Planetary Shield Deployment",
                          &"Only {avgShieldRate:.1f}% shield deployment rate")
    flag.impact = "Colonies vulnerable to rapid invasions - shields slow invasion progress"
    flag.rootCause = "Insufficient investment in passive defense (67 PP per shield)"
    flag.addEvidence(&"Target: > 40% of colonies with shields")
    flag.addEvidence(&"Planetary shields: DS=100, slows invasions, costs 67 PP")
    result.add(flag)

proc detectPlanetBreakerUsage*(df: DataFrame): seq[RedFlag] =
  ## Detect underutilization of planet breakers (MEDIUM)
  ##
  ## Phase F: Track planet breaker deployment
  ## Planet breakers: Max 1 per colony, AS=50, orbital bombardment specialists
  ## Cost: 400 PP, CST 10 required
  ##
  ## Target: > 50% of games with CST 10 should use planet breakers
  result = @[]

  if df.len == 0:
    return

  let hasPBs = "planet_breaker_ships" in df.getKeys()
  let hasCST = "tech_cst" in df.getKeys()
  let hasGameSeed = "game_seed" in df.getKeys()

  if not (hasPBs and hasCST and hasGameSeed):
    return

  # Filter to games that reached CST 10
  let cstVals = df["tech_cst", int].toSeq()
  let pbVals = df["planet_breaker_ships", int].toSeq()
  let seedVals = df["game_seed", int].toSeq()

  var gamesWithCST10 = newSeq[int]()
  var gamesWithPBs = newSeq[int]()

  for i in 0 ..< cstVals.len:
    if cstVals[i] >= 10:
      let seed = seedVals[i]
      if seed notin gamesWithCST10:
        gamesWithCST10.add(seed)
      if pbVals[i] > 0 and seed notin gamesWithPBs:
        gamesWithPBs.add(seed)

  if gamesWithCST10.len == 0:
    return  # No games reached CST 10

  let pbUsageRate = (float(gamesWithPBs.len) / float(gamesWithCST10.len)) * 100.0

  if pbUsageRate < 50.0:
    var flag = newRedFlag(SeverityLevel.Medium, "Low Planet Breaker Usage",
                          &"Only {pbUsageRate:.1f}% of CST10 games used planet breakers")
    flag.impact = "Missing high-power orbital bombardment capability"
    flag.rootCause = "AI not building planet breakers despite reaching CST 10"
    flag.addEvidence(&"Target: > 50% usage in CST10 games")
    flag.addEvidence(&"Planet breakers: AS=50, 400 PP, max 1 per colony")
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
  allFlags.add(detectELIMeshIssues(df))  # Phase F: Disabled (was misleading)
  allFlags.add(detectRaiderIssues(df))  # Phase F: Upgraded to CRITICAL
  allFlags.add(detectCLKWithoutRaiders(df))
  allFlags.add(detectUndefendedColonies(df))
  allFlags.add(detectMothballingIssues(df))
  allFlags.add(detectPlanetaryShieldUsage(df))  # Phase F: New
  allFlags.add(detectPlanetBreakerUsage(df))  # Phase F: New

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
