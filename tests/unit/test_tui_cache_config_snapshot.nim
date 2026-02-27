## Unit tests for TUI cache config snapshot storage.

import std/[unittest, os, times, options]
import std/tables

import ../../src/common/config_sync
import ../../src/engine/config/engine as config_engine
import ../../src/engine/globals
import ../../src/engine/types/[command, core, fleet, production, tech,
  diplomacy, colony, espionage, zero_turn, ship, facilities, ground_unit]
import ../../src/player/state/tui_cache

gameConfig = config_engine.loadGameConfig()

proc tempCachePath(): string =
  let ts = $epochTime().int64
  getTempDir() / ("ec4x_cache_test_" & ts & ".db")

suite "TuiCache Config Snapshot":
  test "save and load latest config snapshot":
    let path = tempCachePath()
    if fileExists(path):
      removeFile(path)
    let cache = openTuiCacheAt(path)
    defer:
      cache.close()
      if fileExists(path):
        removeFile(path)

    let snapshot = buildTuiRulesSnapshot(gameConfig)
    cache.saveConfigSnapshot("game-test", snapshot)

    let loadedOpt = cache.loadLatestConfigSnapshot("game-test")
    check loadedOpt.isSome
    check loadedOpt.get().configHash == snapshot.configHash
    check loadedOpt.get().schemaVersion == snapshot.schemaVersion

  test "save/load/clear order draft":
    let path = tempCachePath()
    if fileExists(path):
      removeFile(path)
    let cache = openTuiCacheAt(path)
    defer:
      cache.close()
      if fileExists(path):
        removeFile(path)

    var packet = CommandPacket()
    packet.houseId = HouseId(2)
    packet.turn = 7
    packet.researchAllocation.economic = 25
    packet.researchAllocation.science = 10

    cache.saveOrderDraft(
      "game-test",
      2,
      7,
      "cfg-hash-1",
      packet
    )

    let loadedOpt = cache.loadOrderDraft("game-test", 2)
    check loadedOpt.isSome
    let draft = loadedOpt.get()
    check draft.turn == 7
    check draft.configHash == "cfg-hash-1"
    check draft.packet.researchAllocation.economic == 25
    check draft.packet.researchAllocation.science == 10

    cache.clearOrderDraft("game-test", 2)
    let clearedOpt = cache.loadOrderDraft("game-test", 2)
    check clearedOpt.isNone

  test "order draft roundtrip preserves full command categories":
    let path = tempCachePath()
    if fileExists(path):
      removeFile(path)
    let cache = openTuiCacheAt(path)
    defer:
      cache.close()
      if fileExists(path):
        removeFile(path)

    var packet = CommandPacket()
    packet.houseId = HouseId(3)
    packet.turn = 12

    packet.zeroTurnCommands = @[
      ZeroTurnCommand(
        houseId: HouseId(3),
        commandType: ZeroTurnCommandType.Reactivate,
        colonySystem: none(SystemId),
        sourceFleetId: some(FleetId(400)),
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

    packet.fleetCommands = @[
      FleetCommand(
        fleetId: FleetId(400),
        commandType: FleetCommandType.Move,
        targetSystem: some(SystemId(22)),
        targetFleet: none(FleetId),
        priority: 1,
        roe: some(6'i32)
      )
    ]

    packet.buildCommands = @[
      BuildCommand(
        colonyId: ColonyId(77),
        buildType: BuildType.Industrial,
        quantity: 1,
        shipClass: none(ShipClass),
        facilityClass: none(FacilityClass),
        groundClass: none(GroundClass),
        industrialUnits: 3
      )
    ]

    packet.repairCommands = @[
      RepairCommand(
        colonyId: ColonyId(77),
        targetType: RepairTargetType.Ship,
        targetId: 9001,
        priority: 2
      )
    ]

    packet.scrapCommands = @[
      ScrapCommand(
        colonyId: ColonyId(77),
        targetType: ScrapTargetType.Neoria,
        targetId: 55,
        acknowledgeQueueLoss: true
      )
    ]

    packet.researchAllocation = ResearchAllocation(
      economic: 30,
      science: 20,
      technology: initTable[TechField, int32]()
    )
    packet.researchAllocation.technology[TechField.WeaponsTech] = 10

    packet.diplomaticCommand = @[
      DiplomaticCommand(
        houseId: HouseId(3),
        targetHouse: HouseId(5),
        actionType: DiplomaticActionType.DeclareHostile,
        proposalId: none(ProposalId),
        proposalType: none(ProposalType),
        message: some("Testing roundtrip")
      )
    ]

    packet.populationTransfers = @[
      PopulationTransferCommand(
        houseId: HouseId(3),
        sourceColony: ColonyId(77),
        destColony: ColonyId(78),
        ptuAmount: 4
      )
    ]

    packet.terraformCommands = @[
      TerraformCommand(
        houseId: HouseId(3),
        colonyId: ColonyId(77),
        startTurn: 12,
        turnsRemaining: 0,
        ppCost: 0,
        targetClass: 0
      )
    ]

    packet.colonyManagement = @[
      ColonyManagementCommand(
        colonyId: ColonyId(77),
        autoRepair: false,
        autoLoadFighters: true,
        autoLoadMarines: true,
        taxRate: some(18'i32)
      )
    ]

    packet.espionageActions = @[
      EspionageAttempt(
        attacker: HouseId(3),
        target: HouseId(5),
        action: EspionageAction.TechTheft,
        targetSystem: none(SystemId)
      )
    ]
    packet.ebpInvestment = 6
    packet.cipInvestment = 2

    cache.saveOrderDraft(
      "game-test",
      3,
      12,
      "cfg-hash-full",
      packet
    )

    let loadedOpt = cache.loadOrderDraft("game-test", 3)
    check loadedOpt.isSome
    let loaded = loadedOpt.get().packet

    check loaded.houseId == HouseId(3)
    check loaded.turn == 12
    check loaded.zeroTurnCommands.len == 1
    check loaded.fleetCommands.len == 1
    check loaded.buildCommands.len == 1
    check loaded.repairCommands.len == 1
    check loaded.scrapCommands.len == 1
    check loaded.diplomaticCommand.len == 1
    check loaded.populationTransfers.len == 1
    check loaded.terraformCommands.len == 1
    check loaded.colonyManagement.len == 1
    check loaded.espionageActions.len == 1
    check loaded.ebpInvestment == 6
    check loaded.cipInvestment == 2
    check loaded.scrapCommands[0].acknowledgeQueueLoss
    check loaded.researchAllocation.technology[TechField.WeaponsTech] == 10
