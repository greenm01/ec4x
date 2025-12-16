## Diplomatic Events Analyzer - Phase E
##
## Processes ScoutEncounterReport to extract diplomatic intelligence:
## - Active blockades (60% GCO reduction impact!)
## - Diplomatic events (war, peace, alliances, pacts, breaks)
## - House hostility tracking
## - Diplomatic landscape changes

import std/[tables, options, strformat, strutils]
import ../../../../engine/[gamestate, fog_of_war, logger]
import ../../../../engine/intelligence/types as intel_types
import ../../../../common/types/core
import ../../controller_types
import ../../config
import ../../shared/intelligence_types

proc parseDiplomaticEventType(description: string): DiplomaticEventType =
  ## Parse diplomatic event type from description string
  ## Simple keyword matching (engine generates descriptive strings)

  let desc = description.toLowerAscii()

  if "war" in desc or "declared war" in desc:
    return DiplomaticEventType.WarDeclared
  elif "peace" in desc or "treaty" in desc:
    return DiplomaticEventType.PeaceTreaty
  elif "alliance" in desc or "allied" in desc:
    return DiplomaticEventType.AllianceFormed
  elif "pact" in desc and "signed" in desc:
    return DiplomaticEventType.PactSigned
  elif "violated" in desc or "broke" in desc:
    return DiplomaticEventType.PactViolated
  elif "diplomatic break" in desc or "relations severed" in desc:
    return DiplomaticEventType.DiplomaticBreak
  else:
    # Default - could be any diplomatic activity
    return DiplomaticEventType.DiplomaticBreak

proc analyzeDiplomaticEvents*(
  filtered: FilteredGameState,
  controller: AIController
): tuple[
  blockades: seq[BlockadeInfo],
  events: seq[DiplomaticEvent],
  hostility: Table[HouseId, HostilityLevel],
  potentialAllies: seq[HouseId],
  potentialThreats: seq[HouseId]
] =
  ## Analyze ScoutEncounterReport data for diplomatic intelligence
  ## Phase E: Critical for blockade detection and diplomatic awareness

  let config = controller.rbaConfig.intelligence_diplomatic_events
  var blockades: seq[BlockadeInfo] = @[]
  var events: seq[DiplomaticEvent] = @[]
  var hostility = initTable[HouseId, HostilityLevel]()
  var potentialAllies: seq[HouseId] = @[]
  var potentialThreats: seq[HouseId] = @[]

  # Initialize hostility tracking for all known houses
  for houseId in filtered.housePrestige.keys:
    if houseId != controller.houseId:
      hostility[houseId] = HostilityLevel.Unknown

  # Process all scout encounter reports
  for report in filtered.ownHouse.intelligence.scoutEncounters:
    case report.encounterType
    of intel_types.ScoutEncounterType.Blockade:
      # Blockade detected - CRITICAL economic impact!
      # Check if this blockade affects our colonies
      var targetOwner: Option[HouseId] = none(HouseId)
      var blockader: Option[HouseId] = none(HouseId)

      # Determine blockader and target from observedHouses
      if report.observedHouses.len >= 2:
        # First house is typically the blockader, second is target
        blockader = some(report.observedHouses[0])
        if report.observedHouses.len > 1:
          targetOwner = some(report.observedHouses[1])

      # If we're the target, this is critical
      let affectsUs = targetOwner.isSome and targetOwner.get() == controller.houseId

      if blockader.isSome and targetOwner.isSome:
        blockades.add(BlockadeInfo(
          systemId: report.systemId,
          blockader: blockader.get(),
          targetOwner: targetOwner.get(),
          established: report.turn,
          economicImpact: 0.6  # 60% GCO reduction per spec
        ))

        # Blockade against us = high hostility
        if affectsUs:
          hostility[blockader.get()] = HostilityLevel.Aggressive
          logInfo(LogCategory.lcAI,
                  &"{controller.houseId} Drungarius: BLOCKADE detected at system {report.systemId} " &
                  &"by {blockader.get()} (60% GCO reduction!)")

    of intel_types.ScoutEncounterType.DiplomaticActivity:
      # Diplomatic events - wars, alliances, pacts, breaks
      let eventType = parseDiplomaticEventType(report.description)

      events.add(DiplomaticEvent(
        turn: report.turn,
        eventType: eventType,
        houses: report.observedHouses,
        significance: report.significance,
        description: report.description
      ))

      # Update hostility based on diplomatic events
      for house in report.observedHouses:
        if house == controller.houseId:
          continue

        case eventType
        of DiplomaticEventType.WarDeclared:
          # If war involves us, max hostility
          if controller.houseId in report.observedHouses:
            hostility[house] = HostilityLevel.Aggressive
          else:
            # War between other houses - note as potential threat
            if not potentialThreats.contains(house):
              potentialThreats.add(house)

        of DiplomaticEventType.PactSigned, DiplomaticEventType.AllianceFormed:
          # Friendly activity - potential ally
          if controller.houseId in report.observedHouses:
            hostility[house] = HostilityLevel.Neutral
            if not potentialAllies.contains(house):
              potentialAllies.add(house)

        of DiplomaticEventType.PactViolated, DiplomaticEventType.DiplomaticBreak:
          # Hostile activity
          if controller.houseId in report.observedHouses:
            hostility[house] = HostilityLevel.Hostile

        else:
          discard

      # Log significant diplomatic events
      if report.significance >= config.war_significance_threshold:
        logInfo(LogCategory.lcAI,
                &"{controller.houseId} Drungarius: Diplomatic event - {report.description}")

    else:
      discard  # Other encounter types handled by different analyzers

  # Calculate potential allies/threats based on hostility
  for houseId, level in hostility:
    case level
    of HostilityLevel.Hostile, HostilityLevel.Aggressive:
      if not potentialThreats.contains(houseId):
        potentialThreats.add(houseId)
    of HostilityLevel.Neutral:
      if not potentialAllies.contains(houseId):
        potentialAllies.add(houseId)
    else:
      discard

  # Log summary
  if blockades.len > 0:
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Drungarius: {blockades.len} active blockades detected")
  if events.len > 0:
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Drungarius: {events.len} diplomatic events processed")

  result = (blockades, events, hostility, potentialAllies, potentialThreats)

proc calculateHouseRelativeStrength*(
  filtered: FilteredGameState,
  controller: AIController,
  targetHouse: HouseId
): HouseRelativeStrength =
  ## Calculate relative strength comparison with another house
  ## Used to populate DiplomaticIntelligence.houseRelativeStrength

  # Get prestige as proxy for overall strength
  let ourPrestige = filtered.housePrestige.getOrDefault(controller.houseId, 0)
  let theirPrestige = filtered.housePrestige.getOrDefault(targetHouse, 0)

  # Calculate strength ratios (1.0 = parity, 2.0 = they're twice as strong)
  let prestigeRatio = if ourPrestige > 0: theirPrestige.float / ourPrestige.float else: 1.0

  # Overall strength is weighted average (prestige heavily weighted)
  let overallStrength = prestigeRatio  # Simplified - prestige = overall

  # Determine trend (simplified - would need historical data)
  let trend = StrengthTrend.Unknown

  result = HouseRelativeStrength(
    houseId: targetHouse,
    militaryStrength: prestigeRatio,  # Simplified approximation
    economicStrength: prestigeRatio,  # Simplified approximation
    techStrength: 1.0,  # Unknown without tech intel
    overallStrength: overallStrength,
    prestigeGap: theirPrestige - ourPrestige,
    trend: trend
  )
