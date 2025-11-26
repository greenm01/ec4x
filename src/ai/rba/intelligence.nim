## Intelligence Gathering Module for EC4X Rule-Based AI
##
## Handles reconnaissance, intel updates, and target identification
## Respects fog-of-war - only uses visible information

import std/[tables, options, sets, hashes, algorithm]
import ../common/types
import ../../engine/[gamestate, fog_of_war, fleet, squadron, starmap]
import ../../common/types/[core, planets]

# =============================================================================
# Intelligence Gathering & Analysis
# =============================================================================

proc identifyEnemyHomeworlds*(filtered: FilteredGameState): seq[SystemId] =
  ## Identify likely enemy homeworlds for reconnaissance
  ## Uses prestige rankings to find enemy starting positions
  ## RESPECTS FOG-OF-WAR: Uses only public prestige data
  result = @[]

  # Get enemy houses (sorted by prestige, most powerful first)
  var enemies: seq[HouseId] = @[]
  for houseId, prestige in filtered.housePrestige:
    if houseId != filtered.viewingHouse and not filtered.houseEliminated.getOrDefault(houseId, false):
      enemies.add(houseId)

  # Identify enemy homeworlds from visible colonies
  # Homeworld = first colony we see from each house
  var seenHouses: HashSet[HouseId]
  for visCol in filtered.visibleColonies:
    if visCol.owner != filtered.viewingHouse and visCol.owner notin seenHouses:
      result.add(visCol.systemId)
      seenHouses.incl(visCol.owner)

  # If we haven't found all enemy homeworlds yet, we need to scout more
  # Return systems we know exist but haven't visited yet (adjacent systems)
  if result.len < enemies.len:
    for systemId, visSystem in filtered.visibleSystems:
      if visSystem.visibility == VisibilityLevel.Adjacent:
        # Prioritize unvisited adjacent systems
        if systemId notin result:
          result.add(systemId)
          if result.len >= enemies.len:
            break

proc needsReconnaissance*(filtered: FilteredGameState, targetSystem: SystemId): bool =
  ## Check if a system needs reconnaissance (stale or no intel)
  ## Returns true if we should send scouts to gather intelligence
  let visSystem = filtered.visibleSystems.getOrDefault(targetSystem)

  # Need reconnaissance if:
  # 1. Never visited (Adjacent or None visibility)
  # 2. Stale intel (visited >10 turns ago)
  case visSystem.visibility
  of VisibilityLevel.None, VisibilityLevel.Adjacent:
    return true  # Never visited, definitely need recon
  of VisibilityLevel.Scouted:
    # Stale if last scouted >10 turns ago
    if visSystem.lastScoutedTurn.isSome:
      return filtered.turn - visSystem.lastScoutedTurn.get() > 10
    return true  # No scout record, should recon
  of VisibilityLevel.Occupied, VisibilityLevel.Owned:
    return false  # Already have current intel
  else:
    return true

import ./controller_types

proc isSystemColonized*(filtered: FilteredGameState, systemId: SystemId): bool =
  ## Check if a system is colonized (respects fog-of-war)
  # Check our own colonies
  for colony in filtered.ownColonies:
    if colony.systemId == systemId:
      return true

  # Check visible enemy colonies
  for visCol in filtered.visibleColonies:
    if visCol.systemId == systemId:
      return true

  return false

proc getColony*(filtered: FilteredGameState, systemId: SystemId): Option[Colony] =
  ## Get colony at a system (respects fog-of-war)
  for colony in filtered.ownColonies:
    if colony.systemId == systemId:
      return some(colony)
  return none(Colony)

proc updateIntelligence*(controller: var AIController, filtered: FilteredGameState, systemId: SystemId,
                         turn: int, confidenceLevel: float = 1.0) =
  ## Update intelligence report for a system
  ## Called when scouts gather intel or when we have direct visibility
  ## RESPECTS FOG-OF-WAR: Updates based on visible/scouted information
  var report = IntelligenceReport(
    systemId: systemId,
    lastUpdated: turn,
    hasColony: isSystemColonized(filtered, systemId),
    confidenceLevel: confidenceLevel
  )

  if report.hasColony:
    # Check if it's our colony (full details)
    var foundOwn = false
    for colony in filtered.ownColonies:
      if colony.systemId == systemId:
        report.owner = some(colony.owner)
        report.planetClass = some(colony.planetClass)
        report.resources = some(colony.resources)
        report.estimatedDefenses = colony.starbases.len * 10 + colony.groundBatteries * 5
        foundOwn = true
        break

    # Otherwise check visible enemy colonies (limited intel)
    if not foundOwn:
      for visCol in filtered.visibleColonies:
        if visCol.systemId == systemId:
          report.owner = some(visCol.owner)
          report.planetClass = visCol.planetClass
          report.resources = visCol.resources
          report.estimatedDefenses = visCol.estimatedDefenses.get(0)
          break

  # Estimate fleet strength at this system (only visible fleets)
  var totalStrength = 0
  for fleet in filtered.ownFleets:
    if fleet.location == systemId:
      for squadron in fleet.squadrons:
        totalStrength += squadron.combatStrength()
  for visFleet in filtered.visibleFleets:
    if visFleet.location == systemId:
      # Rough estimate based on ship count
      totalStrength += visFleet.estimatedShipCount.get(0) * 20

  report.estimatedFleetStrength = totalStrength

  controller.intelligence[systemId] = report

proc getIntelAge*(controller: AIController, systemId: SystemId, currentTurn: int): Option[int] =
  ## Get how many turns old our intelligence is for a system
  if systemId in controller.intelligence:
    return some(currentTurn - controller.intelligence[systemId].lastUpdated)
  return none(int)

proc needsReconnaissanceController*(controller: AIController, systemId: SystemId, currentTurn: int): bool =
  ## Check if a system needs reconnaissance
  ## Returns true if we have no intel or intel is stale (>5 turns old)
  if systemId notin controller.intelligence:
    return true

  let age = currentTurn - controller.intelligence[systemId].lastUpdated
  return age > 5  # Intel becomes stale after 5 turns

proc findBestColonizationTarget*(controller: var AIController, filtered: FilteredGameState,
                                  fromSystem: SystemId, fleetId: FleetId): Option[SystemId] =
  ## Find best colonization target using intelligence
  ## Prioritizes: Eden/Abundant > Strategic > Nearby > Unknown
  ## NOTE: "uncolonized" includes UNKNOWN systems - fog-of-war means we don't know if they're colonized
  ## ETACs will discover on arrival if a system is already taken (realistic exploration)
  type TargetScore = tuple[systemId: SystemId, score: float, distance: int]
  var candidates: seq[TargetScore] = @[]

  let fromCoords = filtered.starMap.systems[fromSystem].coords

  for systemId, system in filtered.starMap.systems:
    if not isSystemColonized(filtered, systemId):
      # Not colonized = either truly empty OR unknown (fog-of-war)
      var score = 0.0

      # Calculate distance
      let dx = abs(system.coords.q - fromCoords.q)
      let dy = abs(system.coords.r - fromCoords.r)
      let dz = abs((system.coords.q + system.coords.r) - (fromCoords.q + fromCoords.r))
      let distance = (dx + dy + dz) div 2

      # Distance penalty (prefer nearby, but not overwhelmingly)
      score -= float(distance) * 0.5

      # Use intelligence if available
      if systemId in controller.intelligence:
        let intel = controller.intelligence[systemId]

        # Planet quality bonus (per spec: Extreme/Desolate/Hostile/Harsh/Benign/Lush/Eden)
        if intel.planetClass.isSome:
          case intel.planetClass.get()
          of PlanetClass.Eden:
            score += 25.0  # Highest priority (Level VII: 2k+ PU)
          of PlanetClass.Lush:
            score += 20.0  # Level VI: 1k-2k PU
          of PlanetClass.Benign:
            score += 15.0  # Level V: 501-1000 PU
          of PlanetClass.Harsh:
            score += 10.0  # Level IV: 181-500 PU
          of PlanetClass.Hostile:
            score += 5.0   # Level III: 61-180 PU
          of PlanetClass.Desolate:
            score += 2.0   # Level II: 21-60 PU
          of PlanetClass.Extreme:
            score += 1.0   # Level I: 1-20 PU (still colonize if close)

        # Resource bonus
        if intel.resources.isSome:
          case intel.resources.get()
          of ResourceRating.VeryRich:
            score += 20.0  # Exceptional resources
          of ResourceRating.Rich:
            score += 15.0  # Excellent resources
          of ResourceRating.Abundant:
            score += 10.0  # Good resources
          of ResourceRating.Poor:
            score += 3.0   # Minimal resources
          of ResourceRating.VeryPoor:
            score += 0.0   # Worst resources

        # Confidence modifier (prefer systems we've scouted)
        score *= intel.confidenceLevel
      else:
        # Unknown system - small bonus for exploration
        score += 2.0

      let item: TargetScore = (systemId: systemId, score: score, distance: distance)
      candidates.add(item)

  if candidates.len > 0:
    # Sort by score (highest first)
    candidates.sort(proc(a, b: TargetScore): int =
      if b.score > a.score: 1
      elif b.score < a.score: -1
      else: 0
    )

    # Use fleetId hash to get consistent but unique selection per fleet
    # This prevents all ETAC fleets from targeting the same system
    let maxScore = candidates[0].score
    var topSystems: seq[SystemId] = @[]
    for candidate in candidates:
      if candidate.score == maxScore:
        topSystems.add(candidate.systemId)
      else:
        break  # candidates sorted by score, so we're done

    if topSystems.len > 1:
      # Multiple systems with same score - use fleet ID hash for deterministic but unique selection
      let fleetHash = hash(fleetId)
      let selectedIdx = abs(fleetHash) mod topSystems.len
      return some(topSystems[selectedIdx])
    else:
      return some(topSystems[0])

  return none(SystemId)

proc gatherEconomicIntelligence*(controller: var AIController, filtered: FilteredGameState): seq[EconomicIntelligence] =
  ## Assess enemy economic strength for targeting
  result = @[]

  let ourHouse = filtered.ownHouse
  var ourProduction = 0
  for colony in filtered.ownColonies:
    if colony.owner == controller.houseId:
      ourProduction += colony.production

  for targetHouse in filtered.housePrestige.keys:
    if targetHouse == controller.houseId:
      continue

    var intel = EconomicIntelligence(
      targetHouse: targetHouse,
      estimatedProduction: 0,
      highValueTargets: @[],
      economicStrength: 0.0
    )

    # Gather data from visible enemy colonies
    for colony in filtered.visibleColonies:
      if colony.owner != targetHouse:
        continue

      # VisibleColony has Option[int] for production (limited intel)
      if colony.production.isSome:
        intel.estimatedProduction += colony.production.get()

        # Identify high-value economic targets
        if colony.production.get() >= 50:
          intel.highValueTargets.add(colony.systemId)

    # Calculate relative strength
    if ourProduction > 0:
      intel.economicStrength = float(intel.estimatedProduction) / float(ourProduction)

    result.add(intel)

# =============================================================================
# Travel Time & ETA Calculations
# =============================================================================

proc calculateETA*(starMap: StarMap, fromSystem: SystemId, toSystem: SystemId,
                   fleet: Fleet): Option[int] =
  ## Calculate estimated turns for fleet to reach target system
  ## Returns none if target is unreachable
  ##
  ## Uses conservative estimate: assumes 1 jump per turn (enemy/neutral territory)
  ## Actual travel may be faster if using major lanes through friendly space
  ##
  ## RESPECTS FOG-OF-WAR: Uses pathfinding with fleet's lane access rules

  if fromSystem == toSystem:
    return some(0)  # Already there

  let path = findPath(starMap, fromSystem, toSystem, fleet)
  if not path.found:
    return none(int)  # Unreachable

  # PathResult.totalCost is in movement points (lane weights)
  # Major lanes: weight 1
  # Minor lanes: weight 2
  # Restricted lanes: weight 3
  #
  # Conservative estimate: 1 jump per turn minimum
  # This accounts for enemy territory, unknown lane types, etc.
  let estimatedTurns = max(1, int(path.totalCost))

  return some(estimatedTurns)

proc calculateMultiFleetETA*(starMap: StarMap, assemblyPoint: SystemId,
                              fleets: seq[Fleet]): Option[int] =
  ## Calculate when all fleets can reach assembly point
  ## Returns the maximum ETA (when the slowest fleet arrives)
  ## Returns none if any fleet cannot reach the assembly point

  var maxETA = 0
  for fleet in fleets:
    let eta = calculateETA(starMap, fleet.location, assemblyPoint, fleet)
    if eta.isNone:
      return none(int)  # At least one fleet can't reach assembly
    maxETA = max(maxETA, eta.get())

  return some(maxETA)
