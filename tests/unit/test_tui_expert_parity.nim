## Expert-mode parity regressions for representative commands.

import std/[unittest, options, strutils, tables]

import ../../src/player/sam/tui_model
import ../../src/player/sam/expert_parser
import ../../src/player/sam/expert_executor
import ../../src/engine/types/[core, fleet, colony, command]

suite "TUI expert parity":
  test "expert fleet move stages canonical fleet command":
    var model = initTuiModel()
    model.view.viewingHouse = 1
    model.view.fleets = @[
      FleetInfo(id: 41, owner: 1, name: "A1", location: 101)
    ]
    model.view.systems[(q: 0, r: 0)] = SystemInfo(id: 101, name: "Home")
    model.view.systems[(q: 1, r: 0)] = SystemInfo(id: 102, name: "Target")

    let ast = parseExpertCommand("fleet A1 move Target")
    check ast.kind == ExpertCommandKind.FleetMove
    let exec = executeExpertCommand(model, ast)
    check exec.success
    check 41 in model.ui.stagedFleetCommands
    let cmd = model.ui.stagedFleetCommands[41]
    check cmd.commandType == FleetCommandType.Move
    check cmd.targetSystem.isSome
    check int(cmd.targetSystem.get()) == 102

  test "expert colony auto marine toggles marine only":
    var model = initTuiModel()
    model.view.viewingHouse = 1
    model.view.colonies = @[
      ColonyInfo(colonyId: 77, systemName: "Alpha", owner: 1)
    ]

    let ast = parseExpertCommand("colony Alpha auto mar on")
    check ast.kind == ExpertCommandKind.ColonyAuto
    let exec = executeExpertCommand(model, ast)
    check exec.success
    check model.ui.stagedColonyManagement.len == 1
    let cmd = model.ui.stagedColonyManagement[0]
    check cmd.autoLoadMarines
    check not cmd.autoRepair
    check not cmd.autoLoadFighters

  test "unsupported expert variants fail with explicit message":
    var model = initTuiModel()
    model.view.viewingHouse = 1
    model.view.fleets = @[
      FleetInfo(id: 88, owner: 1, name: "A8", location: 201)
    ]

    let ast = parseExpertCommand("fleet A8 split 1 frigate")
    check ast.kind == ExpertCommandKind.FleetSplit
    let exec = executeExpertCommand(model, ast)
    check not exec.success
    check exec.message.contains("not implemented")
