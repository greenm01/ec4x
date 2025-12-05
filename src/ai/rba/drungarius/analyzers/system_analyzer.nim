## System Intelligence Analyzer
##
## Processes SystemIntelReport from engine intelligence database
## Tracks enemy fleet movements and composition
##
## Phase B implementation - second priority analyzer

import std/[tables, options, sets, algorithm]
import ../../../../engine/[gamestate, fog_of_war, starmap, fleet]
import ../../../../engine/intelligence/types as intel_types
import ../../../../common/types/[core, units]
import ../../controller_types
import ../../config
import ../../shared/intelligence_types

proc calculateDistance(starMap: StarMap, fromSystem: SystemId, toSystem: SystemId): int =
  ## Calculate jump distance between two systems
  let pathResult = starMap.findPath(fromSystem, toSystem, Fleet())
  if pathResult.found:
    return pathResult.path.len
  return 999

proc analyzeFleetComposition(squadronDetails: Option[seq[intel_types.SquadronIntel]]): FleetComposition =
  ## Analyze squadron details to determine fleet composition
  result = FleetComposition(
    capitalShips: 0,
    cruisers: 0,
    destroyers: 0,
    escorts: 0,
    scouts: 0,
    spaceLiftShips: 0,
    totalShips: 0,
    avgTechLevel: 0
  )

  if squadronDetails.isNone:
    return

  var techLevelSum = 0
  var techLevelCount = 0

  for squadron in squadronDetails.get():
    let shipCount = squadron.shipCount
    result.totalShips += shipCount

    # Classify by ship class
    case squadron.shipClass
    of "Battleship", "Carrier":
      result.capitalShips += shipCount
    of "Cruiser":
      result.cruisers += shipCount
    of "Destroyer":
      result.destroyers += shipCount
    of "Escort", "Frigate":
      result.escorts += shipCount
    of "Scout":
      result.scouts += shipCount
    else:
      discard  # Unknown type

    # Track tech level
    if squadron.techLevel > 0:
      techLevelSum += squadron.techLevel * shipCount
      techLevelCount += shipCount

  # Calculate average tech level
  if techLevelCount > 0:
    result.avgTechLevel = techLevelSum div techLevelCount

proc findThreatenedColonies(
  fleetLocation: SystemId,
  ownColonies: seq[Colony],
  starMap: StarMap,
  threatRadius: int
): seq[SystemId] =
  ## Find friendly colonies within threat range of enemy fleet
  result = @[]
  for colony in ownColonies:
    let distance = calculateDistance(starMap, fleetLocation, colony.systemId)
    if distance <= threatRadius:
      result.add(colony.systemId)

proc analyzeSystemIntelligence*(
  filtered: FilteredGameState,
  controller: AIController
): seq[EnemyFleetSummary] =
  ## Analyze SystemIntelReport data to track enemy fleet locations and composition
  ## Phase B implementation

  result = @[]
  let config = globalRBAConfig.intelligence
  var processedFleets = initHashSet[FleetId]()

  # Process SystemIntelReports (detailed fleet intel)
  for systemId, report in filtered.ownHouse.intelligence.systemReports:
    for fleetIntel in report.detectedFleets:
      # Skip own fleets
      if fleetIntel.owner == controller.houseId:
        continue

      # Skip if already processed
      if fleetIntel.fleetId in processedFleets:
        continue
      processedFleets.incl(fleetIntel.fleetId)

      # Analyze composition
      let composition = analyzeFleetComposition(fleetIntel.squadronDetails)

      # Calculate estimated strength
      let estimatedStrength =
        composition.capitalShips * 200 +
        composition.cruisers * 100 +
        composition.destroyers * 50 +
        composition.escorts * 25 +
        composition.scouts * 10

      # Find threatened colonies
      let threatened = findThreatenedColonies(
        fleetIntel.location,
        filtered.ownColonies,
        filtered.starMap,
        config.threat_high_distance
      )

      result.add(EnemyFleetSummary(
        fleetId: fleetIntel.fleetId,
        owner: fleetIntel.owner,
        lastKnownLocation: fleetIntel.location,
        lastSeen: report.gatheredTurn,
        estimatedStrength: estimatedStrength,
        composition: some(composition),
        threatenedColonies: threatened,
        isMoving: false  # Can't determine from static report
      ))

  # Supplement with FleetMovementHistory (for fleets without detailed intel)
  for fleetId, history in filtered.ownHouse.intelligence.fleetMovementHistory:
    # Skip own fleets
    if history.owner == controller.houseId:
      continue

    # Skip if already processed from SystemIntelReport
    if fleetId in processedFleets:
      continue

    # Find threatened colonies
    let threatened = findThreatenedColonies(
      history.lastKnownLocation,
      filtered.ownColonies,
      filtered.starMap,
      config.threat_high_distance
    )

    # Rough strength estimate (we don't have composition data)
    let roughStrength = 100  # Default unknown fleet strength

    result.add(EnemyFleetSummary(
      fleetId: fleetId,
      owner: history.owner,
      lastKnownLocation: history.lastKnownLocation,
      lastSeen: history.lastSeen,
      estimatedStrength: roughStrength,
      composition: none(FleetComposition),
      threatenedColonies: threatened,
      isMoving: false
    ))

  # Sort by threat level (strength * threatened colonies)
  result.sort(proc(a, b: EnemyFleetSummary): int =
    let aThreat = a.estimatedStrength * max(a.threatenedColonies.len, 1)
    let bThreat = b.estimatedStrength * max(b.threatenedColonies.len, 1)
    return cmp(bThreat, aThreat)  # Descending (highest threat first)
  )
