## Unit tests for TUI command staging coverage.

import std/unittest

import ../../src/player/sam/tui_model
import ../../src/engine/types/[core, production, command, colony]

suite "TUI command staging":
  test "staged entries include population transfer and terraform":
    var model = initTuiModel()
    model.ui.stagedPopulationTransfers = @[
      PopulationTransferCommand(
        houseId: HouseId(1),
        sourceColony: ColonyId(11),
        destColony: ColonyId(12),
        ptuAmount: 3
      )
    ]
    model.ui.stagedTerraformCommands = @[
      TerraformCommand(
        houseId: HouseId(1),
        colonyId: ColonyId(11),
        startTurn: 5,
        turnsRemaining: 0,
        ppCost: 0,
        targetClass: 0
      )
    ]

    let entries = model.stagedCommandEntries()
    var sawTransfer = false
    var sawTerraform = false
    for entry in entries:
      if entry.kind == StagedCommandKind.PopulationTransfer:
        sawTransfer = true
      elif entry.kind == StagedCommandKind.Terraform:
        sawTerraform = true

    check sawTransfer
    check sawTerraform

  test "dropStagedCommand removes transfer and terraform entries":
    var model = initTuiModel()
    model.ui.stagedPopulationTransfers = @[
      PopulationTransferCommand(
        houseId: HouseId(1),
        sourceColony: ColonyId(21),
        destColony: ColonyId(22),
        ptuAmount: 2
      )
    ]
    model.ui.stagedTerraformCommands = @[
      TerraformCommand(
        houseId: HouseId(1),
        colonyId: ColonyId(21),
        startTurn: 7,
        turnsRemaining: 0,
        ppCost: 0,
        targetClass: 0
      )
    ]

    check model.dropStagedCommand(StagedCommandEntry(
      kind: StagedCommandKind.PopulationTransfer,
      index: 0
    ))
    check model.dropStagedCommand(StagedCommandEntry(
      kind: StagedCommandKind.Terraform,
      index: 0
    ))
    check model.ui.stagedPopulationTransfers.len == 0
    check model.ui.stagedTerraformCommands.len == 0

  test "buildCommandPacket includes colony command categories":
    var model = initTuiModel()

    model.ui.stagedRepairCommands = @[
      RepairCommand(
        colonyId: ColonyId(31),
        targetType: RepairTargetType.Ship,
        targetId: 901,
        priority: 1
      )
    ]
    model.ui.stagedScrapCommands = @[
      ScrapCommand(
        colonyId: ColonyId(31),
        targetType: ScrapTargetType.Neoria,
        targetId: 44,
        acknowledgeQueueLoss: true
      )
    ]
    model.ui.stagedPopulationTransfers = @[
      PopulationTransferCommand(
        houseId: HouseId(1),
        sourceColony: ColonyId(31),
        destColony: ColonyId(32),
        ptuAmount: 4
      )
    ]
    model.ui.stagedTerraformCommands = @[
      TerraformCommand(
        houseId: HouseId(1),
        colonyId: ColonyId(31),
        startTurn: 9,
        turnsRemaining: 0,
        ppCost: 0,
        targetClass: 0
      )
    ]

    let packet = model.buildCommandPacket(9, HouseId(1))
    check packet.repairCommands.len == 1
    check packet.scrapCommands.len == 1
    check packet.populationTransfers.len == 1
    check packet.terraformCommands.len == 1
    check packet.populationTransfers[0].ptuAmount == 4
    check packet.scrapCommands[0].acknowledgeQueueLoss
