## Diplomatic Event Intelligence Reporting
##
## Generates intelligence reports for diplomatic events
## All houses receive intelligence about major diplomatic shifts

import std/[tables, options, strformat]
import types as intel_types
import ../gamestate
import ../diplomacy/types as dip_types

proc generateWarDeclarationIntel*(
  state: var GameState,
  declaringHouse: HouseId,
  targetHouse: HouseId,
  turn: int
) =
  ## Generate intelligence reports when war is declared
  ## All houses receive this intelligence (public event)

  # Notify all houses of the war declaration
  for houseId in state.houses.keys:
    let significance = if houseId == declaringHouse or houseId == targetHouse:
      10  # Maximum significance for direct participants
    else:
      8  # High significance for observers (affects diplomatic landscape)

    let description = if houseId == declaringHouse:
      &"WAR DECLARED: Your house has declared war on {targetHouse}. All diplomatic ties severed."
    elif houseId == targetHouse:
      &"WAR DECLARED: {declaringHouse} has declared war on your house! Prepare for conflict."
    else:
      &"DIPLOMATIC ALERT: {declaringHouse} has declared war on {targetHouse}. Galaxy-wide conflict escalates."

    let report = intel_types.ScoutEncounterReport(
      reportId: &"{houseId}-war-declaration-{turn}-{declaringHouse}-{targetHouse}",
      scoutId: "diplomatic-corps",
      turn: turn,
      systemId: 0.SystemId,  # No specific system
      encounterType: intel_types.ScoutEncounterType.DiplomaticActivity,
      observedHouses: @[declaringHouse, targetHouse],
      fleetDetails: @[],
      colonyDetails: none(intel_types.ColonyIntelReport),
      fleetMovements: @[],
      description: description,
      significance: significance
    )

    # CRITICAL: Get, modify, write back to persist
    var house = state.houses[houseId]
    house.intelligence.addScoutEncounter(report)
    state.houses[houseId] = house

proc generatePeaceTreatyIntel*(
  state: var GameState,
  house1: HouseId,
  house2: HouseId,
  turn: int
) =
  ## Generate intelligence reports when peace treaty is signed
  ## All houses receive this intelligence (public event)

  for houseId in state.houses.keys:
    let significance = if houseId == house1 or houseId == house2:
      9  # Very significant for direct participants
    else:
      7  # Significant for observers

    let otherHouse = if houseId == house1: house2 else: house1
    let description = if houseId == house1 or houseId == house2:
      &"PEACE TREATY: Your house has signed a peace treaty with {otherHouse}. Hostilities cease."
    else:
      &"DIPLOMATIC UPDATE: {house1} and {house2} have signed a peace treaty. Conflict resolved."

    let report = intel_types.ScoutEncounterReport(
      reportId: &"{houseId}-peace-treaty-{turn}-{house1}-{house2}",
      scoutId: "diplomatic-corps",
      turn: turn,
      systemId: 0.SystemId,
      encounterType: intel_types.ScoutEncounterType.DiplomaticActivity,
      observedHouses: @[house1, house2],
      fleetDetails: @[],
      colonyDetails: none(intel_types.ColonyIntelReport),
      fleetMovements: @[],
      description: description,
      significance: significance
    )

    # CRITICAL: Get, modify, write back to persist
    var house = state.houses[houseId]
    house.intelligence.addScoutEncounter(report)
    state.houses[houseId] = house

proc generateAllianceFormedIntel*(
  state: var GameState,
  house1: HouseId,
  house2: HouseId,
  turn: int
) =
  ## Generate intelligence reports when alliance is formed
  ## All houses receive this intelligence (public event)

  for houseId in state.houses.keys:
    let significance = if houseId == house1 or houseId == house2:
      9  # Very significant for direct participants
    else:
      8  # Highly significant for observers (major power shift)

    let otherHouse = if houseId == house1: house2 else: house1
    let description = if houseId == house1 or houseId == house2:
      &"ALLIANCE FORMED: Your house has formed an alliance with {otherHouse}. Mutual defense activated."
    else:
      &"DIPLOMATIC ALERT: {house1} and {house2} have formed an alliance. Power balance shifts."

    let report = intel_types.ScoutEncounterReport(
      reportId: &"{houseId}-alliance-formed-{turn}-{house1}-{house2}",
      scoutId: "diplomatic-corps",
      turn: turn,
      systemId: 0.SystemId,
      encounterType: intel_types.ScoutEncounterType.DiplomaticActivity,
      observedHouses: @[house1, house2],
      fleetDetails: @[],
      colonyDetails: none(intel_types.ColonyIntelReport),
      fleetMovements: @[],
      description: description,
      significance: significance
    )

    # CRITICAL: Get, modify, write back to persist
    var house = state.houses[houseId]
    house.intelligence.addScoutEncounter(report)
    state.houses[houseId] = house

proc generatePactFormedIntel*(
  state: var GameState,
  house1: HouseId,
  house2: HouseId,
  pactType: string,
  turn: int
) =
  ## Generate intelligence reports when pact is formed
  ## All houses receive this intelligence (public event)

  for houseId in state.houses.keys:
    let significance = if houseId == house1 or houseId == house2:
      8  # Significant for direct participants
    else:
      6  # Moderately significant for observers

    let otherHouse = if houseId == house1: house2 else: house1
    let description = if houseId == house1 or houseId == house2:
      &"PACT SIGNED: Your house has signed a {pactType} pact with {otherHouse}."
    else:
      &"DIPLOMATIC UPDATE: {house1} and {house2} have signed a {pactType} pact."

    let report = intel_types.ScoutEncounterReport(
      reportId: &"{houseId}-pact-formed-{turn}-{house1}-{house2}",
      scoutId: "diplomatic-corps",
      turn: turn,
      systemId: 0.SystemId,
      encounterType: intel_types.ScoutEncounterType.DiplomaticActivity,
      observedHouses: @[house1, house2],
      fleetDetails: @[],
      colonyDetails: none(intel_types.ColonyIntelReport),
      fleetMovements: @[],
      description: description,
      significance: significance
    )

    # CRITICAL: Get, modify, write back to persist
    var house = state.houses[houseId]
    house.intelligence.addScoutEncounter(report)
    state.houses[houseId] = house

proc generateDiplomaticBreakIntel*(
  state: var GameState,
  house1: HouseId,
  house2: HouseId,
  relationshipType: string,  # "alliance", "pact", etc.
  turn: int
) =
  ## Generate intelligence reports when diplomatic relationship is broken
  ## All houses receive this intelligence (public event)

  for houseId in state.houses.keys:
    let significance = if houseId == house1 or houseId == house2:
      8  # Significant for direct participants
    else:
      7  # Significant for observers (warning sign)

    let otherHouse = if houseId == house1: house2 else: house1
    let description = if houseId == house1 or houseId == house2:
      &"DIPLOMATIC BREAK: Your {relationshipType} with {otherHouse} has been dissolved. Relations deteriorate."
    else:
      &"DIPLOMATIC ALERT: {house1} and {house2} have broken their {relationshipType}. Tensions rise."

    let report = intel_types.ScoutEncounterReport(
      reportId: &"{houseId}-diplomatic-break-{turn}-{house1}-{house2}",
      scoutId: "diplomatic-corps",
      turn: turn,
      systemId: 0.SystemId,
      encounterType: intel_types.ScoutEncounterType.DiplomaticActivity,
      observedHouses: @[house1, house2],
      fleetDetails: @[],
      colonyDetails: none(intel_types.ColonyIntelReport),
      fleetMovements: @[],
      description: description,
      significance: significance
    )

    # CRITICAL: Get, modify, write back to persist
    var house = state.houses[houseId]
    house.intelligence.addScoutEncounter(report)
    state.houses[houseId] = house
