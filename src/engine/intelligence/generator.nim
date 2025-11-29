## Intelligence Report Generation
##
## Generates intelligence reports from successful spy scout missions
## Per intel.md and operations.md specifications

import std/[tables, options, random, hashes]
import types as intel_types
import corruption
import ../gamestate, ../fleet  # Need FleetStatus from fleet module
import ../espionage/types as esp_types

proc generateColonyIntelReport*(state: GameState, scoutOwner: HouseId, targetSystem: SystemId, quality: intel_types.IntelQuality): Option[intel_types.ColonyIntelReport] =
  ## Generate colony intelligence report from SpyOnPlanet mission
  ## Per intel.md:107-121

  if targetSystem notin state.colonies:
    return none(intel_types.ColonyIntelReport)

  let colony = state.colonies[targetSystem]

  # Don't spy on your own colonies
  if colony.owner == scoutOwner:
    return none(intel_types.ColonyIntelReport)

  # Count reserve and mothballed fleets at this system (orbital assets)
  var reserveFleets = 0
  var mothballedFleets = 0
  for fleet in state.fleets.values:
    if fleet.owner == colony.owner and fleet.location == targetSystem:
      if fleet.status == FleetStatus.Reserve:
        reserveFleets += 1
      elif fleet.status == FleetStatus.Mothballed:
        mothballedFleets += 1

  var report = intel_types.ColonyIntelReport(
    colonyId: targetSystem,
    targetOwner: colony.owner,
    gatheredTurn: state.turn,
    quality: quality,
    population: colony.population,
    industry: colony.infrastructure,  # Infrastructure level (0-10)
    defenses: colony.armies + colony.marines + colony.groundBatteries,  # Total ground defenses
    starbaseLevel: colony.starbases.len,
    constructionQueue: @[],
    grossOutput: none(int),
    taxRevenue: none(int),
    # Orbital defenses (visible when approaching for orbital missions)
    unassignedSquadronCount: colony.unassignedSquadrons.len,
    reserveFleetCount: reserveFleets,
    mothballedFleetCount: mothballedFleets,
    shipyardCount: colony.shipyards.len  # Space-based construction only, NOT spaceports
  )

  # Economic intelligence visible if spy quality is high enough
  if quality == intel_types.IntelQuality.Spy or quality == intel_types.IntelQuality.Perfect:
    # Get colony economic data from latest income report
    let targetHouse = state.houses[colony.owner]
    if targetHouse.latestIncomeReport.isSome:
      let incomeReport = targetHouse.latestIncomeReport.get()
      # Find this colony's data in the house income report
      for colonyReport in incomeReport.colonies:
        if colonyReport.colonyId == targetSystem:
          report.grossOutput = some(colonyReport.grossOutput)
          report.taxRevenue = some(colonyReport.netValue)
          break

  # Construction queue visible if spy quality is high enough
  if quality == intel_types.IntelQuality.Spy or quality == intel_types.IntelQuality.Perfect:
    # Add all construction projects in queue (NEW multi-project system)
    for project in colony.constructionQueue:
      report.constructionQueue.add(project.itemId)
    # Also check legacy underConstruction field for backward compatibility
    if colony.underConstruction.isSome:
      let legacyItem = colony.underConstruction.get().itemId
      if legacyItem notin report.constructionQueue:
        report.constructionQueue.add(legacyItem)

  # Apply corruption if scout owner's intelligence is compromised (disinformation or dishonor)
  let corruptionEffect = corruption.hasIntelCorruption(state.ongoingEffects, scoutOwner)
  let dishonoredCorruption = corruption.hasDishonoredCorruption(state.houses[scoutOwner].dishonoredStatus)

  if corruptionEffect.isSome or dishonoredCorruption.isSome:
    var rng = initRand(state.turn + hash(scoutOwner) + int(targetSystem))
    # Use highest corruption magnitude (disinformation or dishonor)
    let magnitude = if corruptionEffect.isSome: corruptionEffect.get().magnitude
                    else: dishonoredCorruption.get()
    let corrupted = corruption.corruptColonyIntel(report, magnitude, rng)
    return some(corrupted)

  return some(report)

proc generateSystemIntelReport*(state: GameState, scoutOwner: HouseId, targetSystem: SystemId, quality: intel_types.IntelQuality): Option[intel_types.SystemIntelReport] =
  ## Generate system intelligence report from SpyOnSystem mission
  ## Per intel.md:96-105

  var fleetIntels: seq[intel_types.FleetIntel] = @[]

  # Find all fleets in this system that are not owned by the scout owner
  for fleetId, fleet in state.fleets:
    if fleet.location == targetSystem and fleet.owner != scoutOwner:
      var fleetIntel = intel_types.FleetIntel(
        fleetId: fleetId,
        owner: fleet.owner,
        location: targetSystem,
        shipCount: fleet.squadrons.len,
        standingOrders: none(string),  # Future enhancement: Report fleet standing orders if detected
        spaceLiftShipCount: none(int)
      )

      # Visual quality: Can see ship types and squadron sizes, but NOT tech levels or damage
      # Spy/Perfect quality: Full intel including tech levels and hull integrity
      var squadDetails: seq[intel_types.SquadronIntel] = @[]
      for squadron in fleet.squadrons:
        let squadIntel = intel_types.SquadronIntel(
          squadronId: squadron.id,
          shipClass: $squadron.flagship.shipClass,
          shipCount: 1 + squadron.ships.len,  # Flagship + other ships
          # Tech level and hull integrity only for Spy+ quality
          techLevel: if quality >= intel_types.IntelQuality.Spy: squadron.flagship.stats.techLevel else: 0,
          hullIntegrity: if quality >= intel_types.IntelQuality.Spy:
                          (if squadron.flagship.isCrippled: some(50) else: some(100))
                         else: none(int)
        )
        squadDetails.add(squadIntel)
      fleetIntel.squadronDetails = some(squadDetails)

      # Visual quality: Can see number of transports, but NOT cargo contents
      # Spy/Perfect quality: Full cargo manifest
      if fleet.spaceLiftShips.len > 0:
        fleetIntel.spaceLiftShipCount = some(fleet.spaceLiftShips.len)

      fleetIntels.add(fleetIntel)

  if fleetIntels.len == 0:
    return none(intel_types.SystemIntelReport)

  var report = intel_types.SystemIntelReport(
    systemId: targetSystem,
    gatheredTurn: state.turn,
    quality: quality,
    detectedFleets: fleetIntels
  )

  # Apply corruption if scout owner's intelligence is compromised (disinformation or dishonor)
  let corruptionEffect = corruption.hasIntelCorruption(state.ongoingEffects, scoutOwner)
  let dishonoredCorruption = corruption.hasDishonoredCorruption(state.houses[scoutOwner].dishonoredStatus)

  if corruptionEffect.isSome or dishonoredCorruption.isSome:
    var rng = initRand(state.turn + hash(scoutOwner) + int(targetSystem))
    let magnitude = if corruptionEffect.isSome: corruptionEffect.get().magnitude
                    else: dishonoredCorruption.get()
    report = corruption.corruptSystemIntel(report, magnitude, rng)

  return some(report)

proc generateStarbaseIntelReport*(state: GameState, scoutOwner: HouseId, targetSystem: SystemId, quality: intel_types.IntelQuality): Option[intel_types.StarbaseIntelReport] =
  ## Generate starbase intelligence report from HackStarbase mission
  ## Per intel.md and operations.md:6.2.11 - "economic and R&D intelligence"

  if targetSystem notin state.colonies:
    return none(intel_types.StarbaseIntelReport)

  let colony = state.colonies[targetSystem]

  # Don't hack your own starbases
  if colony.owner == scoutOwner:
    return none(intel_types.StarbaseIntelReport)

  # No starbase to hack
  if colony.starbases.len == 0:
    return none(intel_types.StarbaseIntelReport)

  # Get target house data
  let targetHouse = state.houses[colony.owner]

  var report = intel_types.StarbaseIntelReport(
    systemId: targetSystem,
    targetOwner: colony.owner,
    gatheredTurn: state.turn,
    quality: quality
  )

  # Economic intelligence - always available from starbase hack
  report.treasuryBalance = some(targetHouse.treasury)
  report.taxRate = some(targetHouse.taxPolicy.currentRate.float)

  # Gross and net income from latest income report (if available)
  if targetHouse.latestIncomeReport.isSome:
    let incomeReport = targetHouse.latestIncomeReport.get()
    report.grossIncome = some(incomeReport.totalGross)
    report.netIncome = some(incomeReport.totalNet)
  else:
    report.grossIncome = none(int)
    report.netIncome = none(int)

  # R&D intelligence - tech tree data
  report.techLevels = some(targetHouse.techTree.levels)

  # Research allocations (from accumulated research)
  # Calculate total TRP across all fields
  var totalTRP = 0
  for field, points in targetHouse.techTree.accumulated.technology:
    totalTRP += points

  report.researchAllocations = some((
    erp: targetHouse.techTree.accumulated.economic,
    srp: targetHouse.techTree.accumulated.science,
    trp: totalTRP
  ))

  # Current research focus (most accumulated type)
  let maxAccum = max([
    targetHouse.techTree.accumulated.economic,
    targetHouse.techTree.accumulated.science,
    totalTRP
  ])

  if maxAccum == targetHouse.techTree.accumulated.economic:
    report.currentResearch = some("Economic")
  elif maxAccum == targetHouse.techTree.accumulated.science:
    report.currentResearch = some("Science")
  else:
    report.currentResearch = some("Technology")

  # Apply corruption if scout owner's intelligence is compromised (disinformation or dishonor)
  let corruptionEffect = corruption.hasIntelCorruption(state.ongoingEffects, scoutOwner)
  let dishonoredCorruption = corruption.hasDishonoredCorruption(state.houses[scoutOwner].dishonoredStatus)

  if corruptionEffect.isSome or dishonoredCorruption.isSome:
    var rng = initRand(state.turn + hash(scoutOwner) + int(targetSystem))
    let magnitude = if corruptionEffect.isSome: corruptionEffect.get().magnitude
                    else: dishonoredCorruption.get()
    report = corruption.corruptStarbaseIntel(report, magnitude, rng)

  return some(report)
