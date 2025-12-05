## Tactical Strength Assessment Module
##
## Extracted from tactical.nim to maintain file size limits (<1000 LOC)
## Handles relative strength assessment and vulnerable target identification

import std/[tables, options, algorithm]
import ../common/types
import ../../engine/[gamestate, fog_of_war, fleet]
import ../../engine/intelligence/types as intel_types
import ../../common/types/core
import ./controller_types

proc assessRelativeStrength*(controller: AIController, filtered: FilteredGameState, targetHouse: HouseId): float =
  ## Assess relative strength of a house (0.0 = weakest, 1.0 = strongest)
  ## Uses prestige (50%), colony count (30%), and fleet strength (20%)
  ## USES INTELLIGENCE REPORTS: Accesses colonyReports and systemReports
  if targetHouse notin filtered.housePrestige:
    return 0.5

  let targetPrestige = filtered.housePrestige[targetHouse]
  let myHouse = filtered.ownHouse

  var targetStrength = 0.0
  var myStrength = 0.0

  # Prestige weight: 50%
  targetStrength += targetPrestige.float * 0.5
  myStrength += myHouse.prestige.float * 0.5

  # Colony count weight: 30%
  var targetKnownColonies = 0
  let myColonies = filtered.ownColonies.len

  for systemId, colonyReport in myHouse.intelligence.colonyReports:
    if colonyReport.targetOwner == targetHouse:
      targetKnownColonies += 1

  targetStrength += targetKnownColonies.float * 20.0 * 0.3
  myStrength += myColonies.float * 20.0 * 0.3

  # Fleet strength weight: 20%
  var myFleets = 0
  for fleet in filtered.ownFleets:
    myFleets += fleet.combatStrength()

  var targetEstimatedFleetCount = 0
  for systemId, systemReport in myHouse.intelligence.systemReports:
    for detectedFleet in systemReport.detectedFleets:
      if detectedFleet.owner == targetHouse:
        targetEstimatedFleetCount += 1

  let estimatedFleetStrength = targetEstimatedFleetCount * 100
  targetStrength += estimatedFleetStrength.float * 0.2
  myStrength += myFleets.float * 0.2

  if myStrength == 0:
    return 1.0
  return targetStrength / (targetStrength + myStrength)

proc identifyVulnerableTargets*(controller: var AIController, filtered: FilteredGameState): seq[tuple[systemId: SystemId, owner: HouseId, relativeStrength: float]] =
  ## Identify colonies owned by weaker players
  ## USES INTELLIGENCE REPORTS: Includes colonies from intelligence database, not just visible
  result = @[]

  # Track which systems we've already added to avoid duplicates
  var addedSystems: seq[SystemId] = @[]

  # Add currently visible colonies
  for visCol in filtered.visibleColonies:
    if visCol.owner == controller.houseId:
      continue

    let strength = controller.assessRelativeStrength(filtered, visCol.owner)
    result.add((visCol.systemId, visCol.owner, strength))
    addedSystems.add(visCol.systemId)

  # Add colonies from intelligence database (even if not currently visible)
  for systemId, report in filtered.ownHouse.intelligence.colonyReports:
    if report.targetOwner == controller.houseId:
      continue

    # Skip if already added from visible colonies
    if systemId in addedSystems:
      continue

    let strength = controller.assessRelativeStrength(filtered, report.targetOwner)
    result.add((systemId, report.targetOwner, strength))
    addedSystems.add(systemId)

  result.sort(proc(a, b: auto): int = cmp(a.relativeStrength, b.relativeStrength))
