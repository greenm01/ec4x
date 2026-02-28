import std/[unittest, options, tables]

import ../../src/bot/[order_schema, order_compiler]
import ../../src/engine/types/[fleet, production, ship, colony]

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
