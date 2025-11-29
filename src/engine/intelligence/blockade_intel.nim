## Blockade Intelligence Reporting
##
## Generates intelligence reports when blockades are established or lifted
## Both blockaders and defenders receive detailed reports

import std/[tables, options, strformat]
import types as intel_types
import ../gamestate

proc generateBlockadeEstablishedIntel*(
  state: var GameState,
  systemId: SystemId,
  defendingHouse: HouseId,
  blockadingHouses: seq[HouseId],
  turn: int
) =
  ## Generate intelligence reports when a blockade is established
  ## Both defenders and blockaders receive reports

  # Defender's report (colony is being blockaded)
  var blockadersList = ""
  for i, houseId in blockadingHouses:
    if i > 0:
      blockadersList &= ", "
    blockadersList &= $houseId

  let defenderReport = intel_types.ScoutEncounterReport(
    reportId: &"{defendingHouse}-blockade-established-{turn}-{systemId}",
    scoutId: "starbase-sensors",  # Detected by starbase/colony sensors
    turn: turn,
    systemId: systemId,
    encounterType: intel_types.ScoutEncounterType.Blockade,
    observedHouses: blockadingHouses,
    fleetDetails: @[],  # Future enhancement: Could add fleet composition if scouted
    colonyDetails: none(intel_types.ColonyIntelReport),
    fleetMovements: @[],
    description: &"BLOCKADE ESTABLISHED: System {systemId} is under blockade by {blockadersList}. GCO reduced by 60%.",
    significance: 9  # Blockade is critical threat
  )

  # CRITICAL: Get, modify, write back to persist
  var defenderHouse = state.houses[defendingHouse]
  defenderHouse.intelligence.addScoutEncounter(defenderReport)
  state.houses[defendingHouse] = defenderHouse

  # Blockaders' reports (they know they established the blockade)
  for blockader in blockadingHouses:
    let blockaderReport = intel_types.ScoutEncounterReport(
      reportId: &"{blockader}-blockade-success-{turn}-{systemId}",
      scoutId: "fleet-commander",
      turn: turn,
      systemId: systemId,
      encounterType: intel_types.ScoutEncounterType.Blockade,
      observedHouses: @[defendingHouse],
      fleetDetails: @[],
      colonyDetails: none(intel_types.ColonyIntelReport),
      fleetMovements: @[],
      description: &"Blockade established at {systemId} against {defendingHouse}. Target economy disrupted (60% GCO reduction).",
      significance: 8
    )

    # CRITICAL: Get, modify, write back to persist
    var blockaderHouse = state.houses[blockader]
    blockaderHouse.intelligence.addScoutEncounter(blockaderReport)
    state.houses[blockader] = blockaderHouse

proc generateBlockadeLiftedIntel*(
  state: var GameState,
  systemId: SystemId,
  defendingHouse: HouseId,
  previousBlockaders: seq[HouseId],
  turn: int
) =
  ## Generate intelligence reports when a blockade is lifted
  ## Both defenders and former blockaders receive reports

  # Defender's report (blockade has been lifted)
  let defenderReport = intel_types.ScoutEncounterReport(
    reportId: &"{defendingHouse}-blockade-lifted-{turn}-{systemId}",
    scoutId: "starbase-sensors",
    turn: turn,
    systemId: systemId,
    encounterType: intel_types.ScoutEncounterType.Blockade,
    observedHouses: previousBlockaders,
    fleetDetails: @[],
    colonyDetails: none(intel_types.ColonyIntelReport),
    fleetMovements: @[],
    description: &"BLOCKADE LIFTED: System {systemId} is no longer under blockade. Economy restored to normal operation.",
    significance: 7  # Important but less urgent than establishment
  )

  # CRITICAL: Get, modify, write back to persist
  var defenderHouse = state.houses[defendingHouse]
  defenderHouse.intelligence.addScoutEncounter(defenderReport)
  state.houses[defendingHouse] = defenderHouse

  # Former blockaders' reports (their blockade was broken/withdrawn)
  for blockader in previousBlockaders:
    let blockaderReport = intel_types.ScoutEncounterReport(
      reportId: &"{blockader}-blockade-ended-{turn}-{systemId}",
      scoutId: "fleet-commander",
      turn: turn,
      systemId: systemId,
      encounterType: intel_types.ScoutEncounterType.Blockade,
      observedHouses: @[defendingHouse],
      fleetDetails: @[],
      colonyDetails: none(intel_types.ColonyIntelReport),
      fleetMovements: @[],
      description: &"Blockade at {systemId} has ended. Target {defendingHouse} economy no longer disrupted.",
      significance: 6
    )

    # CRITICAL: Get, modify, write back to persist
    var blockaderHouse = state.houses[blockader]
    blockaderHouse.intelligence.addScoutEncounter(blockaderReport)
    state.houses[blockader] = blockaderHouse
