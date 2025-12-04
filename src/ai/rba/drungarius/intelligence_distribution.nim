## Drungarius Intelligence Distribution Module
##
## Byzantine Drungarius - Intelligence Hub
##
## Consolidates fog-of-war visibility, reconnaissance reports, and espionage data
## into a unified IntelligenceSnapshot for all imperial advisors

import std/[tables, strformat, options]
import ../../../common/types/[core, diplomacy]
import ../../../engine/[gamestate, fog_of_war, logger]
import ../../../engine/diplomacy/types as dip_types
import ../controller_types

proc assessThreat*(
  filtered: FilteredGameState,
  ownSystemId: SystemId,
  controller: AIController
): ThreatLevel =
  ## Assess threat level to one of our systems based on enemy presence

  # Check for enemy fleets in system (from fog-of-war)
  var enemyFleetCount = 0
  var totalEnemyStrength = 0

  for fleetId, visFleet in filtered.visibleFleets:
    if visFleet.location == ownSystemId and visFleet.owner != controller.houseId:
      enemyFleetCount += 1
      # Use estimated ship count for enemy fleets, or full details if available
      if visFleet.fullDetails.isSome:
        totalEnemyStrength += visFleet.fullDetails.get().squadrons.len
      elif visFleet.estimatedShipCount.isSome:
        totalEnemyStrength += visFleet.estimatedShipCount.get()
      else:
        totalEnemyStrength += 1  # Unknown strength, assume 1

  if enemyFleetCount > 0:
    # Assess based on fleet strength
    if totalEnemyStrength >= 10:
      return ThreatLevel.Critical  # Large enemy force
    elif totalEnemyStrength >= 5:
      return ThreatLevel.High  # Moderate enemy force
    else:
      return ThreatLevel.Moderate  # Small enemy presence

  # Check intelligence for recent enemy activity
  for fleetId, history in filtered.ownHouse.intelligence.fleetMovementHistory:
    if history.lastKnownLocation == ownSystemId:
      # Enemy was here recently - elevated threat
      let turnsSince = filtered.turn - history.lastSeen
      if turnsSince <= 2:
        return ThreatLevel.Moderate  # Recent enemy activity
      elif turnsSince <= 5:
        return ThreatLevel.Low  # Enemy was here recently

  return ThreatLevel.None  # No known threats

proc needsReconnaissance*(
  filtered: FilteredGameState,
  systemId: SystemId,
  controller: AIController
): bool =
  ## Determine if a system needs reconnaissance (stale intel)

  # Check if we have recent intel on this system
  if filtered.ownHouse.intelligence.colonyReports.hasKey(systemId):
    let report = filtered.ownHouse.intelligence.colonyReports[systemId]
    let turnsSince = filtered.turn - report.gatheredTurn

    # Intel is stale if > 10 turns old
    if turnsSince > 10:
      return true

  # Check if we have any fleet movement intel for this system
  var hasRecentMovementIntel = false
  for fleetId, history in filtered.ownHouse.intelligence.fleetMovementHistory:
    if history.lastKnownLocation == systemId:
      let turnsSince = filtered.turn - history.lastSeen
      if turnsSince <= 10:
        hasRecentMovementIntel = true
        break

  if not hasRecentMovementIntel:
    # No recent movement intel - needs reconnaissance
    return true

  return false

proc generateIntelligenceReport*(
  filtered: FilteredGameState,
  controller: AIController
): IntelligenceSnapshot =
  ## Consolidate fog-of-war + reconnaissance + espionage intel
  ## Drungarius provides this to all advisors

  result.turn = filtered.turn
  result.knownEnemyColonies = @[]
  result.enemyFleetMovements = initTable[HouseId, seq[FleetMovement]]()
  result.highValueTargets = @[]
  result.threatAssessment = initTable[SystemId, ThreatLevel]()
  result.staleIntelSystems = @[]
  result.espionageOpportunities = @[]

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Drungarius: Generating intelligence report for turn {result.turn}")

  # === ENEMY COLONIES ===
  # Aggregate all known enemy colonies from intelligence database
  for systemId, colonyReport in filtered.ownHouse.intelligence.colonyReports:
    if colonyReport.targetOwner != controller.houseId:
      # Non-self colony = potential target
      result.knownEnemyColonies.add((systemId, colonyReport.targetOwner))

      # Check if this is a high-value target (weak defenses)
      let hasDefenders = block:
        var found = false
        for fleetId, history in filtered.ownHouse.intelligence.fleetMovementHistory:
          if history.owner == colonyReport.targetOwner and
             history.lastKnownLocation == systemId:
            found = true
            break
        found

      if not hasDefenders and colonyReport.industry > 0:
        # Undefended colony with production = high value target
        result.highValueTargets.add(systemId)
        logInfo(LogCategory.lcAI,
                &"{controller.houseId} Drungarius: High-value target identified - " &
                &"system {systemId} (owner: {colonyReport.targetOwner}, industry: {colonyReport.industry})")

  # === ENEMY FLEET MOVEMENTS ===
  # Track enemy fleet positions per house
  for fleetId, history in filtered.ownHouse.intelligence.fleetMovementHistory:
    if history.owner != controller.houseId:
      let movement = FleetMovement(
        fleetId: fleetId,
        owner: history.owner,
        lastKnownLocation: history.lastKnownLocation,
        lastSeenTurn: history.lastSeen,
        estimatedStrength: 0  # TODO: Add strength tracking in future
      )

      if not result.enemyFleetMovements.hasKey(history.owner):
        result.enemyFleetMovements[history.owner] = @[]
      result.enemyFleetMovements[history.owner].add(movement)

  # === THREAT ASSESSMENT ===
  # Assess threats to our own colonies
  for colony in filtered.ownColonies:
    let threat = assessThreat(filtered, colony.systemId, controller)
    if threat != ThreatLevel.None:
      result.threatAssessment[colony.systemId] = threat
      logInfo(LogCategory.lcAI,
              &"{controller.houseId} Drungarius: Threat {threat} detected at colony {colony.systemId}")

  # === STALE INTEL SYSTEMS ===
  # Identify systems that need reconnaissance
  # Check all visible systems first
  for systemId in filtered.visibleSystems.keys:
    if needsReconnaissance(filtered, systemId, controller):
      result.staleIntelSystems.add(systemId)

  # Also check systems in intelligence database but not currently visible
  for systemId in filtered.ownHouse.intelligence.colonyReports.keys:
    if not filtered.visibleSystems.hasKey(systemId):
      if needsReconnaissance(filtered, systemId, controller):
        result.staleIntelSystems.add(systemId)

  if result.staleIntelSystems.len > 0:
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Drungarius: {result.staleIntelSystems.len} systems need reconnaissance")

  # === ESPIONAGE OPPORTUNITIES ===
  # Identify houses that are good targets for espionage
  let house = filtered.ownHouse
  let myPrestige = house.prestige

  for houseId, prestige in filtered.housePrestige:
    if houseId == controller.houseId:
      continue

    let prestigeGap = prestige - myPrestige
    let relation = dip_types.getDiplomaticState(house.diplomaticRelations, houseId)

    # Prioritize: enemies, prestige leaders, economic powerhouses
    if relation == dip_types.DiplomaticState.Enemy or prestigeGap > 100:
      result.espionageOpportunities.add(houseId)

  # Summary logging
  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Drungarius: Intelligence summary - " &
          &"{result.knownEnemyColonies.len} enemy colonies, " &
          &"{result.highValueTargets.len} high-value targets, " &
          &"{result.threatAssessment.len} threats, " &
          &"{result.staleIntelSystems.len} stale intel, " &
          &"{result.espionageOpportunities.len} espionage opportunities")

  return result
