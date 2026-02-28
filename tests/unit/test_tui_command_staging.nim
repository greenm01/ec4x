## Unit tests for TUI command staging coverage.

import std/unittest
import std/[options, tables]
import std/strutils

import ../../src/player/sam/tui_model
import ../../src/engine/types/[core, fleet, ship, facilities, ground_unit,
  production, command, colony, tech, diplomacy, espionage, zero_turn]

suite "TUI command staging":
  proc summaryValue(
      rows: seq[tuple[label: string, value: string]],
      label: string
  ): string =
    for row in rows:
      if row.label == label:
        return row.value
    ""

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

  test "stagedCommandsSummary renders transfer and terraform labels":
    var model = initTuiModel()
    model.view.colonies = @[
      ColonyInfo(
        colonyId: 41,
        systemId: 401,
        systemName: "Icarus",
        populationUnits: 80,
        industrialUnits: 15,
        owner: 1
      ),
      ColonyInfo(
        colonyId: 42,
        systemId: 402,
        systemName: "Hestia",
        populationUnits: 60,
        industrialUnits: 12,
        owner: 1
      )
    ]
    model.ui.stagedPopulationTransfers = @[
      PopulationTransferCommand(
        houseId: HouseId(1),
        sourceColony: ColonyId(41),
        destColony: ColonyId(42),
        ptuAmount: 5
      )
    ]
    model.ui.stagedTerraformCommands = @[
      TerraformCommand(
        houseId: HouseId(1),
        colonyId: ColonyId(41),
        startTurn: 8,
        turnsRemaining: 0,
        ppCost: 0,
        targetClass: 0
      )
    ]

    let summary = model.stagedCommandsSummary()
    check summary.contains("Transfer 5 PTU: Icarus -> Hestia")
    check summary.contains("Terraform: Icarus")

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

  test "buildCommandPacket includes full staged command queue":
    var model = initTuiModel()

    model.ui.stagedZeroTurnCommands = @[
      ZeroTurnCommand(
        houseId: HouseId(1),
        commandType: ZeroTurnCommandType.Reactivate,
        colonySystem: none(SystemId),
        sourceFleetId: some(FleetId(1001)),
        targetFleetId: none(FleetId),
        shipIndices: @[],
        shipIds: @[],
        cargoType: none(CargoClass),
        cargoQuantity: none(int),
        fighterIds: @[],
        carrierShipId: none(ShipId),
        sourceCarrierShipId: none(ShipId),
        targetCarrierShipId: none(ShipId),
        newFleetId: none(FleetId)
      )
    ]

    model.ui.stagedFleetCommands[int(FleetId(1001))] = FleetCommand(
      fleetId: FleetId(1001),
      commandType: FleetCommandType.Move,
      targetSystem: some(SystemId(42)),
      targetFleet: none(FleetId),
      priority: 1,
      roe: some(5'i32)
    )

    model.ui.stagedBuildCommands = @[
      BuildCommand(
        colonyId: ColonyId(61),
        buildType: BuildType.Ground,
        quantity: 1,
        shipClass: none(ShipClass),
        facilityClass: none(FacilityClass),
        groundClass: some(GroundClass.Army),
        industrialUnits: 0
      )
    ]

    model.ui.stagedRepairCommands = @[
      RepairCommand(
        colonyId: ColonyId(61),
        targetType: RepairTargetType.Ship,
        targetId: 500,
        priority: 1
      )
    ]

    model.ui.stagedScrapCommands = @[
      ScrapCommand(
        colonyId: ColonyId(61),
        targetType: ScrapTargetType.Kastra,
        targetId: 77,
        acknowledgeQueueLoss: false
      )
    ]

    model.ui.researchAllocation = ResearchAllocation(
      economic: 10,
      science: 20,
      technology: initTable[TechField, int32]()
    )
    model.ui.researchAllocation.technology[TechField.WeaponsTech] = 30

    model.ui.stagedDiplomaticCommands = @[
      DiplomaticCommand(
        houseId: HouseId(1),
        targetHouse: HouseId(2),
        actionType: DiplomaticActionType.DeclareEnemy,
        proposalId: none(ProposalId),
        proposalType: none(ProposalType),
        message: some("Hostilities escalate")
      )
    ]

    model.ui.stagedPopulationTransfers = @[
      PopulationTransferCommand(
        houseId: HouseId(1),
        sourceColony: ColonyId(61),
        destColony: ColonyId(62),
        ptuAmount: 6
      )
    ]

    model.ui.stagedTerraformCommands = @[
      TerraformCommand(
        houseId: HouseId(1),
        colonyId: ColonyId(61),
        startTurn: 13,
        turnsRemaining: 0,
        ppCost: 0,
        targetClass: 0
      )
    ]

    model.ui.stagedColonyManagement = @[
      ColonyManagementCommand(
        colonyId: ColonyId(61),
        autoRepair: true,
        autoLoadFighters: false,
        autoLoadMarines: true,
        taxRate: none(int32)
      )
    ]

    model.ui.stagedEspionageActions = @[
      EspionageAttempt(
        attacker: HouseId(1),
        target: HouseId(2),
        action: EspionageAction.TechTheft,
        targetSystem: none(SystemId)
      )
    ]
    model.ui.stagedEbpInvestment = 7
    model.ui.stagedCipInvestment = 3

    let packet = model.buildCommandPacket(13, HouseId(1))
    check packet.zeroTurnCommands.len == 1
    check packet.fleetCommands.len == 1
    check packet.buildCommands.len == 1
    check packet.repairCommands.len == 1
    check packet.scrapCommands.len == 1
    check packet.diplomaticCommand.len == 1
    check packet.populationTransfers.len == 1
    check packet.terraformCommands.len == 1
    check packet.colonyManagement.len == 1
    check packet.espionageActions.len == 1
    check packet.ebpInvestment == 7
    check packet.cipInvestment == 3
    check packet.researchAllocation.technology[TechField.WeaponsTech] == 30

  test "staged command category summary includes all staged categories":
    var model = initTuiModel()

    model.ui.stagedFleetCommands[1001] = FleetCommand(
      fleetId: FleetId(1001),
      commandType: FleetCommandType.Hold,
      targetSystem: none(SystemId),
      targetFleet: none(FleetId),
      roe: some(6'i32)
    )
    model.ui.stagedZeroTurnCommands = @[
      ZeroTurnCommand(
        houseId: HouseId(1),
        commandType: ZeroTurnCommandType.Reactivate,
        sourceFleetId: some(FleetId(1001)),
        targetFleetId: none(FleetId)
      )
    ]
    model.ui.stagedBuildCommands = @[
      BuildCommand(
        colonyId: ColonyId(88),
        buildType: BuildType.Industrial,
        quantity: 1,
        shipClass: none(ShipClass),
        facilityClass: none(FacilityClass),
        groundClass: none(GroundClass),
        industrialUnits: 1
      )
    ]
    model.ui.stagedRepairCommands = @[
      RepairCommand(
        colonyId: ColonyId(88),
        targetType: RepairTargetType.Ship,
        targetId: 501,
        priority: 1
      )
    ]
    model.ui.stagedScrapCommands = @[
      ScrapCommand(
        colonyId: ColonyId(88),
        targetType: ScrapTargetType.Ship,
        targetId: 502,
        acknowledgeQueueLoss: false
      )
    ]
    model.ui.stagedPopulationTransfers = @[
      PopulationTransferCommand(
        houseId: HouseId(1),
        sourceColony: ColonyId(88),
        destColony: ColonyId(89),
        ptuAmount: 2
      )
    ]
    model.ui.stagedTerraformCommands = @[
      TerraformCommand(
        houseId: HouseId(1),
        colonyId: ColonyId(88),
        startTurn: 14,
        turnsRemaining: 0,
        ppCost: 0,
        targetClass: 0
      )
    ]
    model.ui.stagedColonyManagement = @[
      ColonyManagementCommand(
        colonyId: ColonyId(88),
        autoRepair: true,
        autoLoadFighters: true,
        autoLoadMarines: false,
        taxRate: some(19'i32)
      )
    ]
    model.ui.stagedTaxRate = some(19)
    model.ui.stagedDiplomaticCommands = @[
      DiplomaticCommand(
        houseId: HouseId(1),
        targetHouse: HouseId(2),
        actionType: DiplomaticActionType.DeclareEnemy,
        proposalId: none(ProposalId),
        proposalType: none(ProposalType),
        message: none(string)
      )
    ]
    model.ui.stagedEspionageActions = @[
      EspionageAttempt(
        attacker: HouseId(1),
        target: HouseId(2),
        action: EspionageAction.TechTheft,
        targetSystem: none(SystemId)
      )
    ]
    model.ui.stagedEbpInvestment = 4
    model.ui.stagedCipInvestment = 2

    let summary = model.stagedCommandCategorySummary()
    check summaryValue(summary, "Fleet orders") == "1"
    check summaryValue(summary, "Zero-turn orders") == "1"
    check summaryValue(summary, "Build orders") == "1"
    check summaryValue(summary, "Repair orders") == "1"
    check summaryValue(summary, "Scrap orders") == "1"
    check summaryValue(summary, "Population transfers") == "1"
    check summaryValue(summary, "Terraform orders") == "1"
    check summaryValue(summary, "Colony management") == "1"
    check summaryValue(summary, "Tax rate") == "19%"
    check summaryValue(summary, "Diplomacy") == "1"
    check summaryValue(summary, "Espionage actions") == "1"
    check summaryValue(summary, "EBP investment") == "4 credits"
    check summaryValue(summary, "CIP investment") == "2 credits"
