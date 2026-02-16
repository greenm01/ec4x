## Unit tests for staged fleet command sync between list and console views.

import std/[unittest, options, tables]

import ../../src/player/sam/tui_model
import ../../src/engine/types/[core, fleet]

proc makeFleetInfo(id: int, roe: int): FleetInfo =
  FleetInfo(
    id: id,
    name: "A" & $id,
    location: 1,
    locationName: "Theophanes",
    sectorLabel: "D13",
    shipCount: 1,
    owner: 1,
    command: CmdHold,
    commandLabel: "Hold",
    isIdle: true,
    roe: roe,
    attackStrength: 5,
    defenseStrength: 6,
    statusLabel: "Active",
    destinationLabel: "-",
    destinationSystemId: 0,
    eta: 0,
    hasCrippled: false,
    hasCombatShips: true,
    hasSupportShips: false,
    hasScouts: false,
    hasTroopTransports: false,
    hasEtacs: false,
    isScoutOnly: false,
    seekHomeTarget: none(int),
    needsAttention: true
  )

proc makeConsoleFleet(id: int, roe: int): FleetConsoleFleet =
  FleetConsoleFleet(
    fleetId: id,
    name: "A" & $id,
    shipCount: 1,
    attackStrength: 5,
    defenseStrength: 6,
    troopTransports: 0,
    etacs: 0,
    commandLabel: "Hold",
    destinationLabel: "-",
    eta: 0,
    roe: roe,
    status: "A",
    needsAttention: true
  )

suite "Fleet Console Sync":
  test "staged ROE updates only target fleet in both views":
    var model = initTuiModel()
    model.view.fleets = @[
      makeFleetInfo(1, 6),
      makeFleetInfo(2, 6)
    ]
    model.ui.fleetConsoleFleetsBySystem[1] = @[
      makeConsoleFleet(1, 6),
      makeConsoleFleet(2, 6)
    ]

    let staged = FleetCommand(
      fleetId: FleetId(2'u32),
      commandType: FleetCommandType.Hold,
      targetSystem: none(SystemId),
      targetFleet: none(FleetId),
      roe: some(10'i32)
    )
    model.stageFleetCommand(staged)

    check model.view.fleets[0].roe == 6
    check model.view.fleets[1].roe == 10

    let consoleRows = model.ui.fleetConsoleFleetsBySystem[1]
    check consoleRows[0].roe == 6
    check consoleRows[1].roe == 10
