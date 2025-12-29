## Blockade Intelligence Reporting
##
## Generates intelligence reports when blockades are established or lifted
## Both blockaders and defenders receive the same reports
##
## **Architecture Role:** Business logic (like @systems modules)
## - Reads from @state using safe accessors
## - Writes using Table read-modify-write pattern

import std/[strformat, tables, options]
import ../state/engine as state_helpers
import ../types/[core, game_state, intel]
import ../globals  # For gameConfig to get GCO reduction %

proc generateBlockadeEstablishedIntel*(
    state: var GameState,
    systemId: SystemId,
    blockadingFleetIds: seq[FleetId],
    turn: int32,
) =
  ## Generate intelligence reports when a blockade is established
  ## Both defenders and blockaders receive the same report
  ##
  ## The colony under blockade detects this automatically - no fleet/starbase required

  # Look up colony to get defending house
  # ColonyId and SystemId are same value (colony is identified by its system)
  let colonyId = ColonyId(systemId)
  let colonyOpt = state_helpers.colony(state, colonyId)
  if colonyOpt.isNone:
    return # No colony at this system

  let colony = colonyOpt.get()
  let defendingHouse = colony.owner

  # Look up blockading fleets to get house IDs
  var blockadingHouses: seq[HouseId] = @[]
  for fleetId in blockadingFleetIds:
    let fleetOpt = state_helpers.fleet(state, fleetId)
    if fleetOpt.isSome:
      let fleet = fleetOpt.get()
      if fleet.houseId notin blockadingHouses:
        blockadingHouses.add(fleet.houseId)

  if blockadingHouses.len == 0:
    return # No valid blockading fleets

  # Get GCO reduction percentage from config
  # blockadePenalty = 0.4 means operates at 40% → 60% reduction
  let blockadePenalty = gameConfig.economy.productionModifiers.blockadePenalty
  let gcoReduction = int32((1.0 - blockadePenalty) * 100)

  # Create blockade report (same for defender and all blockaders)
  let report = BlockadeReport(
    reportId: &"blockade-{systemId}-{turn}",
    turn: turn,
    systemId: systemId,
    colonyId: colonyId,
    status: BlockadeStatus.Established,
    blockadingHouses: blockadingHouses,
    blockadingFleetIds: blockadingFleetIds,
    gcoReduction: gcoReduction,
  )

  # Add report to defender's intelligence database
  if state.intelligence.contains(defendingHouse):
    var intel = state.intelligence[defendingHouse]
    intel.blockadeReports.add(report)
    state.intelligence[defendingHouse] = intel

  # Add same report to each blockader's intelligence database
  for house in blockadingHouses:
    if state.intelligence.contains(house):
      var intel = state.intelligence[house]
      intel.blockadeReports.add(report)
      state.intelligence[house] = intel

proc generateBlockadeLiftedIntel*(
    state: var GameState,
    systemId: SystemId,
    previousBlockadingFleetIds: seq[FleetId],
    turn: int32,
) =
  ## Generate intelligence reports when a blockade is lifted
  ## Both defenders and former blockaders receive the same report
  ##
  ## The colony detects when blockade is lifted automatically

  # Look up colony to get defending house
  # ColonyId and SystemId are same value (colony is identified by its system)
  let colonyId = ColonyId(systemId)
  let colonyOpt = state_helpers.colony(state, colonyId)
  if colonyOpt.isNone:
    return # No colony at this system

  let colony = colonyOpt.get()
  let defendingHouse = colony.owner

  # Look up previous blockading fleets to get house IDs
  var previousBlockaders: seq[HouseId] = @[]
  for fleetId in previousBlockadingFleetIds:
    let fleetOpt = state_helpers.fleet(state, fleetId)
    if fleetOpt.isSome:
      let fleet = fleetOpt.get()
      if fleet.houseId notin previousBlockaders:
        previousBlockaders.add(fleet.houseId)

  # Get GCO reduction percentage from config (0 when lifted, but record original)
  # blockadePenalty = 0.4 means operates at 40% → 60% reduction
  let blockadePenalty = gameConfig.economy.productionModifiers.blockadePenalty
  let gcoReduction = int32((1.0 - blockadePenalty) * 100)

  # Create blockade lifted report (same for defender and all former blockaders)
  let report = BlockadeReport(
    reportId: &"blockade-{systemId}-{turn}",
    turn: turn,
    systemId: systemId,
    colonyId: colonyId,
    status: BlockadeStatus.Lifted,
    blockadingHouses: previousBlockaders,
    blockadingFleetIds: previousBlockadingFleetIds,
    gcoReduction: gcoReduction,
  )

  # Add report to defender's intelligence database
  if state.intelligence.contains(defendingHouse):
    var intel = state.intelligence[defendingHouse]
    intel.blockadeReports.add(report)
    state.intelligence[defendingHouse] = intel

  # Add same report to each former blockader's intelligence database
  for house in previousBlockaders:
    if state.intelligence.contains(house):
      var intel = state.intelligence[house]
      intel.blockadeReports.add(report)
      state.intelligence[house] = intel
