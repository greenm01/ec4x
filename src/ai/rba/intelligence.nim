## Intelligence Gathering Module for EC4X Rule-Based AI
##
## Handles reconnaissance, intel updates, and target identification
## Respects fog-of-war - only uses visible information

import std/[tables, options, sets, hashes, algorithm]
import ../common/types
import ../../engine/[gamestate, fog_of_war, fleet, squadron, starmap]
import ../../common/types/[core, planets]
import ./config
import ./shared/intelligence_types as intel_types # For IntelligenceSnapshot
import ./shared/intelligence_helpers # DRY: Snapshot lookup utilities

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

proc updateIntelligence*(controller: var AIController,
                         filtered: FilteredGameState, systemId: SystemId,
                         turn: int, confidenceLevel: float = 1.0) =
  ## DEPRECATED: This function wrote to controller.intelligence which has been
  ## removed. In the new architecture, intelligence updates are handled by:
  ##   1. Engine's IntelligenceDatabase (authoritative source)
  ##   2. IntelligenceSnapshot (regenerated from database for AI)
  ##   3. This function now triggers a snapshot refresh
  ##
  ## Called when scouts gather intel or when we have direct visibility
  ## RESPECTS FOG-OF-WAR: Based on visible/scouted information
  ##
  ## NEW BEHAVIOR: Sets intelligenceNeedsRefresh flag to trigger snapshot
  ## regeneration. The engine's intelligence system handles the actual data
  ## updates automatically through fog-of-war filtering and scouting.

  # Trigger snapshot refresh - engine will have updated intelligence data
  controller.intelligenceNeedsRefresh = true

  # OLD CODE REMOVED: Previously maintained separate intelligence cache
  # Now relies on engine's IntelligenceDatabase as single source of truth
  # (DRY principle)

proc getIntelAge*(controller: AIController, systemId: SystemId,
                  currentTurn: int): Option[int] =
  ## Get how many turns old our intelligence is for a system
  ## Uses intelligenceSnapshot for lookup (DRY principle)
  if controller.intelligenceSnapshot.isNone:
    return none(int)

  let snap = controller.intelligenceSnapshot.get()
  let systemIntel = snap.getSystemIntel(systemId)

  if systemIntel.isSome:
    return some(currentTurn - systemIntel.get().lastIntelTurn)

  return none(int)

proc needsReconnaissanceController*(controller: AIController,
                                    systemId: SystemId,
                                    currentTurn: int): bool =
  ## Check if a system needs reconnaissance
  ## Returns true if we have no intel or intel is stale
  ## Uses intelligenceSnapshot + intelligence_helpers (DRY principle)
  if controller.intelligenceSnapshot.isNone:
    return true  # No snapshot = need intel

  let snap = controller.intelligenceSnapshot.get()
  let threshold = config.globalRBAConfig.intelligence.colony_intel_stale_threshold

  return snap.isIntelStale(systemId, currentTurn, threshold)

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

      # TODO: Planet quality scoring needs proper data structure
      # Planet class data for uncolonized systems is not currently available
      # in VisibleSystem or IntelligenceSnapshot.
      # For now, use simple heuristics based on visibility level.
      let visSystem = filtered.visibleSystems.getOrDefault(systemId)
      if visSystem.visibility in [VisibilityLevel.Scouted,
                                  VisibilityLevel.Occupied]:
        # System has been scouted - prefer over unknown
        score += 5.0
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

proc gatherEconomicIntelligence*(controller: var AIController, filtered: FilteredGameState): intel_types.EconomicIntelligence =
  ## Assess enemy economic strength for targeting
  result = intel_types.EconomicIntelligence(
    enemyEconomicStrength: initTable[HouseId, intel_types.EconomicAssessment](),
    highValueTargets: @[], # This will be populated with HighValueTarget objects
    enemyTechGaps: initTable[HouseId, intel_types.TechGapAnalysis](),
    constructionActivity: initTable[SystemId, intel_types.ConstructionTrend](),
    lastUpdated: filtered.turn
  )

  var ourProduction = 0
  for colony in filtered.ownColonies:
    if colony.owner == controller.houseId:
      ourProduction += colony.production

  for targetHouseId in filtered.housePrestige.keys:
    if targetHouseId == controller.houseId:
      continue

    var enemyAssessment = intel_types.EconomicAssessment(
      houseId: targetHouseId,
      knownColonyCount: 0,
      estimatedTotalProduction: 0,
      estimatedIncome: none(int),
      estimatedTechSpending: none(int),
      taxRate: none(float),
      relativeStrength: 0.0,
      lastUpdated: filtered.turn
    )
    
    var knownColonyCountForTarget = 0

    # Gather data from visible enemy colonies for this targetHouseId
    for visibleColony in filtered.visibleColonies:
      if visibleColony.owner == targetHouseId:
        knownColonyCountForTarget += 1
        if visibleColony.production.isSome:
          enemyAssessment.estimatedTotalProduction += visibleColony.production.get()

          # Identify high-value economic targets and convert to HighValueTarget type
          if visibleColony.production.get() >= 50:
            result.highValueTargets.add(intel_types.HighValueTarget(
              systemId: visibleColony.systemId,
              owner: visibleColony.owner,
              estimatedValue: visibleColony.production.get() * 10, # Example multiplier
              estimatedDefenses: visibleColony.estimatedDefenses.get(0), # Requires Option.get(0) fallback
              hasStarbase: visibleColony.starbaseLevel.get(0) > 0, # Requires Option.get(0) fallback
              shipyardCount: visibleColony.shipyardCount.get(0), # Requires Option.get(0) fallback
              lastUpdated: visibleColony.intelTurn.get(filtered.turn), # Requires Option.get(0) fallback
              intelQuality: intel_types.IntelQuality.Visual # Or derive from context
            ))

    enemyAssessment.knownColonyCount = knownColonyCountForTarget

    # Calculate relative strength
    if ourProduction > 0:
      enemyAssessment.relativeStrength = float(enemyAssessment.estimatedTotalProduction) / float(ourProduction)
    else:
      enemyAssessment.relativeStrength = 1.0

    result.enemyEconomicStrength[targetHouseId] = enemyAssessment

# =============================================================================
# Fog-of-War Strategic Assessment
# =============================================================================

proc countUncolonizedSystems*(filtered: FilteredGameState): int =
  ## Count uncolonized systems visible through fog-of-war
  ## Used for dynamic ETAC production decisions
  ##
  ## RESPECTS FOG-OF-WAR: Only counts systems we can see
  ## - Visible systems from exploration and intel reports
  ## - Unknown systems beyond fog-of-war are NOT counted
  ## - Enables dynamic expansion strategy based on known opportunities
  result = 0

  for systemId, visSystem in filtered.visibleSystems:
    # Check if this system has a colony (owned by anyone)
    var isColonized = false

    # Check visible colonies
    for colony in filtered.visibleColonies:
      if colony.systemId == systemId:
        isColonized = true
        break

    # Count uncolonized systems
    if not isColonized:
      result += 1

# =============================================================================
# Travel Time & ETA Calculations
# =============================================================================
# NOTE: These functions have been moved to src/engine/starmap.nim
# They are now available to both AI and human players via the engine
# Re-export them here for backwards compatibility

export starmap.calculateETA
export starmap.calculateMultiFleetETA

proc calculateDistance*(starMap: StarMap, fromSystem: SystemId, toSystem: SystemId): int =
  ## Calculate jump distance between two systems
  ## Centralized helper for intelligence modules
  let pathResult = starMap.findPath(fromSystem, toSystem, Fleet())
  if pathResult.found:
    return pathResult.path.len
  return 999  # Unreachable

proc countSharedBorders*(filtered: FilteredGameState, intelSnapshot: IntelligenceSnapshot, ownHouse: HouseId, targetHouse: HouseId): int =
  ## Count systems where we share borders with the target house
  ## Uses filtered.ownColonies for our colonies and intelSnapshot.knownEnemyColonies for enemy colonies
  result = 0

  # Find our colonies (from filtered.ownColonies)
  var ownColonySystems: seq[SystemId] = @[]
  for colony in filtered.ownColonies:
    ownColonySystems.add(colony.systemId)

  # Find target colonies (from intelSnapshot.knownEnemyColonies)
  var targetColonySystems: seq[SystemId] = @[]
  for (systemId, owner) in intelSnapshot.knownEnemyColonies:
    if owner == targetHouse:
      targetColonySystems.add(systemId)

  # Count adjacent pairs
  for ownSys in ownColonySystems:
    for targetSys in targetColonySystems:
      let distance = calculateDistance(filtered.starMap, ownSys, targetSys)
      if distance == 1: # Systems are adjacent if distance is 1 jump
        result += 1
        # IMPORTANT: Break here to count each of our colonies once for shared border
        # This prevents overcounting if one of our colonies borders multiple of theirs
        break
