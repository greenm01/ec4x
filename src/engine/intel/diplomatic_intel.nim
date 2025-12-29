## Diplomatic Event Intelligence Reporting
##
## Generates intelligence reports for diplomatic events
## All houses receive intelligence about major diplomatic shifts
##
## **Architecture Role:** Business logic (like @systems modules)
## - Reads from @state using safe accessors
## - Writes using Table read-modify-write pattern

import std/[tables, options, strformat]
import ../types/[core, game_state, intel]

proc generateHostilityDeclarationIntel*(
    state: var GameState, declaringHouse: HouseId, targetHouse: HouseId, turn: int32
) =
  ## Generate intelligence reports when hostility is declared
  ## All houses receive this intelligence (public event)

  # Notify all houses of the hostility declaration
  for houseId in state.intelligence.keys:
    let significance: int32 =
      if houseId == declaringHouse or houseId == targetHouse:
        7 # High significance for direct participants
      else:
        5 # Moderate significance for observers

    let description =
      if houseId == declaringHouse:
        &"TENSIONS ESCALATE: Your house has declared {targetHouse} as hostile. Deep space combat authorized."
      elif houseId == targetHouse:
        &"ALERT: {declaringHouse} has declared your house hostile! Expect deep space engagements."
      else:
        &"DIPLOMATIC UPDATE: {declaringHouse} has declared {targetHouse} hostile. Tensions rising in the galaxy."

    let report = ScoutEncounterReport(
      reportId: &"{houseId}-hostility-declaration-{turn}-{declaringHouse}-{targetHouse}",
      fleetId: FleetId(0), # Diplomatic intelligence, not fleet-specific
      turn: turn,
      systemId: SystemId(0), # No specific system
      encounterType: ScoutEncounterType.DiplomaticActivity,
      observedHouses: @[declaringHouse, targetHouse],
      observedFleetIds: @[],
      colonyId: none(ColonyId),
      fleetMovements: @[],
      description: description,
      significance: significance,
    )

    # Write to intelligence database (Table read-modify-write)
    if state.intelligence.contains(houseId):
      var intel = state.intelligence[houseId]
      intel.scoutEncounters.add(report)
      state.intelligence[houseId] = intel

proc generateWarDeclarationIntel*(
    state: var GameState, declaringHouse: HouseId, targetHouse: HouseId, turn: int32
) =
  ## Generate intelligence reports when war is declared
  ## All houses receive this intelligence (public event)

  # Notify all houses of the war declaration
  for houseId in state.intelligence.keys:
    let significance: int32 =
      if houseId == declaringHouse or houseId == targetHouse:
        10 # Maximum significance for direct participants
      else:
        8 # High significance for observers (affects diplomatic landscape)

    let description =
      if houseId == declaringHouse:
        &"WAR DECLARED: Your house has declared war on {targetHouse}. All diplomatic ties severed."
      elif houseId == targetHouse:
        &"WAR DECLARED: {declaringHouse} has declared war on your house! Prepare for conflict."
      else:
        &"DIPLOMATIC ALERT: {declaringHouse} has declared war on {targetHouse}. Galaxy-wide conflict escalates."

    let report = ScoutEncounterReport(
      reportId: &"{houseId}-war-declaration-{turn}-{declaringHouse}-{targetHouse}",
      fleetId: FleetId(0), # Diplomatic intelligence, not fleet-specific
      turn: turn,
      systemId: SystemId(0), # No specific system
      encounterType: ScoutEncounterType.DiplomaticActivity,
      observedHouses: @[declaringHouse, targetHouse],
      observedFleetIds: @[],
      colonyId: none(ColonyId),
      fleetMovements: @[],
      description: description,
      significance: significance,
    )

    # Write to intelligence database (Table read-modify-write)
    if state.intelligence.contains(houseId):
      var intel = state.intelligence[houseId]
      intel.scoutEncounters.add(report)
      state.intelligence[houseId] = intel

proc generatePeaceTreatyIntel*(
    state: var GameState, house1: HouseId, house2: HouseId, turn: int32
) =
  ## Generate intelligence reports when peace treaty is signed
  ## All houses receive this intelligence (public event)

  for houseId in state.intelligence.keys:
    let significance: int32 =
      if houseId == house1 or houseId == house2:
        9 # Very significant for direct participants
      else:
        7 # Significant for observers

    let otherHouse = if houseId == house1: house2 else: house1
    let description =
      if houseId == house1 or houseId == house2:
        &"PEACE TREATY: Your house has signed a peace treaty with {otherHouse}. Hostilities cease."
      else:
        &"DIPLOMATIC UPDATE: {house1} and {house2} have signed a peace treaty. Conflict resolved."

    let report = ScoutEncounterReport(
      reportId: &"{houseId}-peace-treaty-{turn}-{house1}-{house2}",
      fleetId: FleetId(0), # Diplomatic intelligence, not fleet-specific
      turn: turn,
      systemId: SystemId(0),
      encounterType: ScoutEncounterType.DiplomaticActivity,
      observedHouses: @[house1, house2],
      observedFleetIds: @[],
      colonyId: none(ColonyId),
      fleetMovements: @[],
      description: description,
      significance: significance,
    )

    # Write to intelligence database (Table read-modify-write)
    if state.intelligence.contains(houseId):
      var intel = state.intelligence[houseId]
      intel.scoutEncounters.add(report)
      state.intelligence[houseId] = intel

proc generateAllianceFormedIntel*(
    state: var GameState, house1: HouseId, house2: HouseId, turn: int32
) =
  ## Generate intelligence reports when alliance is formed
  ## All houses receive this intelligence (public event)

  for houseId in state.intelligence.keys:
    let significance: int32 =
      if houseId == house1 or houseId == house2:
        9 # Very significant for direct participants
      else:
        8 # Highly significant for observers (major power shift)

    let otherHouse = if houseId == house1: house2 else: house1
    let description =
      if houseId == house1 or houseId == house2:
        &"ALLIANCE FORMED: Your house has formed an alliance with {otherHouse}. Mutual defense activated."
      else:
        &"DIPLOMATIC ALERT: {house1} and {house2} have formed an alliance. Power balance shifts."

    let report = ScoutEncounterReport(
      reportId: &"{houseId}-alliance-formed-{turn}-{house1}-{house2}",
      fleetId: FleetId(0), # Diplomatic intelligence, not fleet-specific
      turn: turn,
      systemId: SystemId(0),
      encounterType: ScoutEncounterType.DiplomaticActivity,
      observedHouses: @[house1, house2],
      observedFleetIds: @[],
      colonyId: none(ColonyId),
      fleetMovements: @[],
      description: description,
      significance: significance,
    )

    # Write to intelligence database (Table read-modify-write)
    if state.intelligence.contains(houseId):
      var intel = state.intelligence[houseId]
      intel.scoutEncounters.add(report)
      state.intelligence[houseId] = intel

proc generatePactFormedIntel*(
    state: var GameState, house1: HouseId, house2: HouseId, pactType: string, turn: int32
) =
  ## Generate intelligence reports when pact is formed
  ## All houses receive this intelligence (public event)

  for houseId in state.intelligence.keys:
    let significance: int32 =
      if houseId == house1 or houseId == house2:
        8 # Significant for direct participants
      else:
        6 # Moderately significant for observers

    let otherHouse = if houseId == house1: house2 else: house1
    let description =
      if houseId == house1 or houseId == house2:
        &"PACT SIGNED: Your house has signed a {pactType} pact with {otherHouse}."
      else:
        &"DIPLOMATIC UPDATE: {house1} and {house2} have signed a {pactType} pact."

    let report = ScoutEncounterReport(
      reportId: &"{houseId}-pact-formed-{turn}-{house1}-{house2}",
      fleetId: FleetId(0), # Diplomatic intelligence, not fleet-specific
      turn: turn,
      systemId: SystemId(0),
      encounterType: ScoutEncounterType.DiplomaticActivity,
      observedHouses: @[house1, house2],
      observedFleetIds: @[],
      colonyId: none(ColonyId),
      fleetMovements: @[],
      description: description,
      significance: significance,
    )

    # Write to intelligence database (Table read-modify-write)
    if state.intelligence.contains(houseId):
      var intel = state.intelligence[houseId]
      intel.scoutEncounters.add(report)
      state.intelligence[houseId] = intel

proc generateDiplomaticBreakIntel*(
    state: var GameState,
    house1: HouseId,
    house2: HouseId,
    relationshipType: string, # "alliance", "pact", etc.
    turn: int32,
) =
  ## Generate intelligence reports when diplomatic relationship is broken
  ## All houses receive this intelligence (public event)

  for houseId in state.intelligence.keys:
    let significance: int32 =
      if houseId == house1 or houseId == house2:
        8 # Significant for direct participants
      else:
        7 # Significant for observers (warning sign)

    let otherHouse = if houseId == house1: house2 else: house1
    let description =
      if houseId == house1 or houseId == house2:
        &"DIPLOMATIC BREAK: Your {relationshipType} with {otherHouse} has been dissolved. Relations deteriorate."
      else:
        &"DIPLOMATIC ALERT: {house1} and {house2} have broken their {relationshipType}. Tensions rise."

    let report = ScoutEncounterReport(
      reportId: &"{houseId}-diplomatic-break-{turn}-{house1}-{house2}",
      fleetId: FleetId(0), # Diplomatic intelligence, not fleet-specific
      turn: turn,
      systemId: SystemId(0),
      encounterType: ScoutEncounterType.DiplomaticActivity,
      observedHouses: @[house1, house2],
      observedFleetIds: @[],
      colonyId: none(ColonyId),
      fleetMovements: @[],
      description: description,
      significance: significance,
    )

    # Write to intelligence database (Table read-modify-write)
    if state.intelligence.contains(houseId):
      var intel = state.intelligence[houseId]
      intel.scoutEncounters.add(report)
      state.intelligence[houseId] = intel
