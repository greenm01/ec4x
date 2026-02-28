import std/[unittest, options]

import ../../src/bot/[order_schema, order_compiler]
import ../../src/engine/types/[fleet, production, ship, colony, zero_turn]

suite "bot order compiler":
  test "compiles fleet move and ship build":
    let draft = BotOrderDraft(
      turn: 9,
      houseId: 1,
      fleetCommands: @[
        BotFleetOrder(
          fleetId: 41,
          commandType: "move",
          targetSystemId: some(22),
          targetFleetId: none(int),
          roe: some(6)
        )
      ],
      buildCommands: @[
        BotBuildOrder(
          colonyId: 7,
          buildType: "ship",
          shipClass: some("destroyer"),
          facilityClass: none(string),
          groundClass: none(string),
          quantity: some(2)
        )
      ],
      repairCommands: @[],
      scrapCommands: @[],
      zeroTurnCommands: @[],
      populationTransfers: @[],
      terraformCommands: @[],
      colonyManagement: @[],
      espionageActions: @[],
      diplomaticCommand: none(BotDiplomaticOrder),
      researchAllocation: none(BotResearchAllocation),
      ebpInvestment: some(0),
      cipInvestment: some(0)
    )

    let compiled = compileCommandPacket(draft)
    check compiled.ok
    check compiled.errors.len == 0
    check compiled.packet.turn == 9
    check compiled.packet.fleetCommands.len == 1
    check compiled.packet.fleetCommands[0].commandType ==
      FleetCommandType.Move
    check compiled.packet.fleetCommands[0].targetSystem.isSome
    check int(compiled.packet.fleetCommands[0].targetSystem.get()) == 22
    check compiled.packet.buildCommands.len == 1
    check compiled.packet.buildCommands[0].buildType == BuildType.Ship
    check compiled.packet.buildCommands[0].shipClass.isSome
    check compiled.packet.buildCommands[0].shipClass.get() ==
      ShipClass.Destroyer

  test "rejects duplicate fleet orders":
    let draft = BotOrderDraft(
      turn: 3,
      houseId: 1,
      fleetCommands: @[
        BotFleetOrder(
          fleetId: 5,
          commandType: "hold",
          targetSystemId: none(int),
          targetFleetId: none(int),
          roe: none(int)
        ),
        BotFleetOrder(
          fleetId: 5,
          commandType: "move",
          targetSystemId: some(11),
          targetFleetId: none(int),
          roe: none(int)
        )
      ],
      buildCommands: @[],
      repairCommands: @[],
      scrapCommands: @[],
      zeroTurnCommands: @[],
      populationTransfers: @[],
      terraformCommands: @[],
      colonyManagement: @[],
      espionageActions: @[],
      diplomaticCommand: none(BotDiplomaticOrder),
      researchAllocation: none(BotResearchAllocation),
      ebpInvestment: none(int),
      cipInvestment: none(int)
    )

    let compiled = compileCommandPacket(draft)
    check not compiled.ok
    check compiled.errors.len > 0

  test "compiles transfer, terraform, and colony management":
    let draft = BotOrderDraft(
      turn: 10,
      houseId: 2,
      fleetCommands: @[],
      buildCommands: @[],
      repairCommands: @[],
      scrapCommands: @[],
      zeroTurnCommands: @[],
      populationTransfers: @[
        BotPopulationTransfer(
          sourceColonyId: 7,
          destColonyId: 8,
          ptuAmount: 1
        )
      ],
      terraformCommands: @[
        BotTerraformOrder(colonyId: 7)
      ],
      colonyManagement: @[
        BotColonyManagementOrder(
          colonyId: 7,
          taxRate: some(22),
          autoRepair: some(true),
          autoLoadMarines: some(false),
          autoLoadFighters: some(true)
        )
      ],
      espionageActions: @[],
      diplomaticCommand: none(BotDiplomaticOrder),
      researchAllocation: none(BotResearchAllocation),
      ebpInvestment: some(2),
      cipInvestment: some(1)
    )

    let compiled = compileCommandPacket(draft)
    check compiled.ok
    check compiled.packet.populationTransfers.len == 1
    check compiled.packet.terraformCommands.len == 1
    check compiled.packet.colonyManagement.len == 1
    check compiled.packet.colonyManagement[0].taxRate.isSome
    check int(compiled.packet.populationTransfers[0].sourceColony) == 7
    check int(compiled.packet.terraformCommands[0].colonyId) == 7

  test "compiles repair and scrap commands":
    let draft = BotOrderDraft(
      turn: 10,
      houseId: 2,
      fleetCommands: @[],
      buildCommands: @[],
      repairCommands: @[
        BotRepairOrder(
          colonyId: 7,
          targetType: "ship",
          targetId: 301,
          priority: some(2)
        )
      ],
      scrapCommands: @[
        BotScrapOrder(
          colonyId: 7,
          targetType: "facility",
          targetId: 33,
          acknowledgeQueueLoss: some(true)
        )
      ],
      zeroTurnCommands: @[],
      populationTransfers: @[],
      terraformCommands: @[],
      colonyManagement: @[],
      espionageActions: @[],
      diplomaticCommand: none(BotDiplomaticOrder),
      researchAllocation: none(BotResearchAllocation),
      ebpInvestment: none(int),
      cipInvestment: none(int)
    )

    let compiled = compileCommandPacket(draft)
    check compiled.ok
    check compiled.packet.repairCommands.len == 1
    check compiled.packet.scrapCommands.len == 1

  test "rejects invalid espionage and diplomatic variants":
    let draft = BotOrderDraft(
      turn: 11,
      houseId: 1,
      fleetCommands: @[],
      buildCommands: @[],
      repairCommands: @[],
      scrapCommands: @[],
      zeroTurnCommands: @[],
      populationTransfers: @[],
      terraformCommands: @[],
      colonyManagement: @[],
      espionageActions: @[
        BotEspionageOrder(operation: "unknown-op", targetHouseId: some(2))
      ],
      diplomaticCommand: some(BotDiplomaticOrder(
        targetHouseId: 2,
        action: "accept-proposal",
        proposalId: none(int)
      )),
      researchAllocation: none(BotResearchAllocation),
      ebpInvestment: none(int),
      cipInvestment: none(int)
    )

    let compiled = compileCommandPacket(draft)
    check not compiled.ok
    check compiled.errors.len >= 2

  test "compiles espionage and diplomatic commands":
    let draft = BotOrderDraft(
      turn: 11,
      houseId: 1,
      fleetCommands: @[],
      buildCommands: @[],
      repairCommands: @[],
      scrapCommands: @[],
      zeroTurnCommands: @[],
      populationTransfers: @[],
      terraformCommands: @[],
      colonyManagement: @[],
      espionageActions: @[
        BotEspionageOrder(
          operation: "sabotage-high",
          targetHouseId: some(2),
          targetSystemId: some(7)
        )
      ],
      diplomaticCommand: some(BotDiplomaticOrder(
        targetHouseId: 2,
        action: "propose-deescalate",
        proposedState: some("hostile")
      )),
      researchAllocation: none(BotResearchAllocation),
      ebpInvestment: none(int),
      cipInvestment: none(int)
    )

    let compiled = compileCommandPacket(draft)
    check compiled.ok
    check compiled.packet.espionageActions.len == 1
    check compiled.packet.diplomaticCommand.len == 1

  test "compiles supported zero-turn commands":
    let draft = BotOrderDraft(
      turn: 12,
      houseId: 1,
      fleetCommands: @[],
      buildCommands: @[],
      repairCommands: @[],
      scrapCommands: @[],
      zeroTurnCommands: @[
        BotZeroTurnOrder(
          commandType: "reactivate",
          sourceFleetId: some(20),
          targetFleetId: none(int),
          shipIndices: @[],
          cargoType: none(string),
          quantity: none(int)
        ),
        BotZeroTurnOrder(
          commandType: "detach-ships",
          sourceFleetId: some(21),
          targetFleetId: none(int),
          shipIndices: @[0, 2],
          cargoType: none(string),
          quantity: none(int)
        ),
        BotZeroTurnOrder(
          commandType: "load-cargo",
          sourceFleetId: some(22),
          targetFleetId: none(int),
          shipIndices: @[],
          cargoType: some("marines"),
          quantity: some(5)
        )
      ],
      populationTransfers: @[],
      terraformCommands: @[],
      colonyManagement: @[],
      espionageActions: @[],
      diplomaticCommand: none(BotDiplomaticOrder),
      researchAllocation: none(BotResearchAllocation),
      ebpInvestment: none(int),
      cipInvestment: none(int)
    )

    let compiled = compileCommandPacket(draft)
    check compiled.ok
    check compiled.packet.zeroTurnCommands.len == 3
    check compiled.packet.zeroTurnCommands[0].commandType ==
      ZeroTurnCommandType.Reactivate
    check compiled.packet.zeroTurnCommands[1].commandType ==
      ZeroTurnCommandType.DetachShips
    check compiled.packet.zeroTurnCommands[2].commandType ==
      ZeroTurnCommandType.LoadCargo
    check compiled.packet.zeroTurnCommands[2].cargoType.isSome
    check compiled.packet.zeroTurnCommands[2].cargoQuantity.isSome

  test "compiles fighter zero-turn commands":
    let draft = BotOrderDraft(
      turn: 13,
      houseId: 1,
      fleetCommands: @[],
      buildCommands: @[],
      repairCommands: @[],
      scrapCommands: @[],
      zeroTurnCommands: @[
        BotZeroTurnOrder(
          commandType: "load-fighters",
          sourceFleetId: some(22),
          targetFleetId: none(int),
          shipIndices: @[],
          fighterShipIds: @[1001, 1002],
          carrierShipId: some(501),
          sourceCarrierShipId: none(int),
          targetCarrierShipId: none(int),
          cargoType: none(string),
          quantity: none(int)
        ),
        BotZeroTurnOrder(
          commandType: "transfer-fighters",
          sourceFleetId: some(22),
          targetFleetId: some(23),
          shipIndices: @[],
          fighterShipIds: @[1002],
          carrierShipId: none(int),
          sourceCarrierShipId: some(501),
          targetCarrierShipId: some(502),
          cargoType: none(string),
          quantity: none(int)
        )
      ],
      populationTransfers: @[],
      terraformCommands: @[],
      colonyManagement: @[],
      espionageActions: @[],
      diplomaticCommand: none(BotDiplomaticOrder),
      researchAllocation: none(BotResearchAllocation),
      ebpInvestment: none(int),
      cipInvestment: none(int)
    )

    let compiled = compileCommandPacket(draft)
    check compiled.ok
    check compiled.packet.zeroTurnCommands.len == 2
    check compiled.packet.zeroTurnCommands[0].commandType ==
      ZeroTurnCommandType.LoadFighters
    check compiled.packet.zeroTurnCommands[0].carrierShipId.isSome
    check compiled.packet.zeroTurnCommands[0].fighterIds.len == 2
    check compiled.packet.zeroTurnCommands[1].commandType ==
      ZeroTurnCommandType.TransferFighters
    check compiled.packet.zeroTurnCommands[1].sourceCarrierShipId.isSome
    check compiled.packet.zeroTurnCommands[1].targetCarrierShipId.isSome

  test "rejects fighter commands with missing required fields":
    let draft = BotOrderDraft(
      turn: 14,
      houseId: 1,
      fleetCommands: @[],
      buildCommands: @[],
      repairCommands: @[],
      scrapCommands: @[],
      zeroTurnCommands: @[
        BotZeroTurnOrder(
          commandType: "load-fighters",
          sourceFleetId: some(22),
          targetFleetId: none(int),
          shipIndices: @[],
          fighterShipIds: @[],
          carrierShipId: none(int),
          sourceCarrierShipId: none(int),
          targetCarrierShipId: none(int),
          cargoType: none(string),
          quantity: none(int)
        )
      ],
      populationTransfers: @[],
      terraformCommands: @[],
      colonyManagement: @[],
      espionageActions: @[],
      diplomaticCommand: none(BotDiplomaticOrder),
      researchAllocation: none(BotResearchAllocation),
      ebpInvestment: none(int),
      cipInvestment: none(int)
    )

    let compiled = compileCommandPacket(draft)
    check not compiled.ok
    check compiled.errors.len > 0
