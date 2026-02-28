## Integration-style unit tests for TUI draft restore behavior.

import std/[unittest, options, tables]

import ../../src/player/sam/tui_model
import ../../src/player/tui/draft_apply
import ../../src/engine/types/[core, fleet, ship, production, command,
  diplomacy, colony, espionage, tech, zero_turn, combat, facilities,
  ground_unit]

suite "TUI draft apply resume":
  test "applyOrderDraft restores all command categories":
    var model = initTuiModel()
    model.view.viewingHouse = 1
    model.view.turn = 9

    model.view.fleets = @[
      FleetInfo(
        id: 100,
        name: "A1",
        location: 11,
        locationName: "Columba",
        shipCount: 1,
        command: int(FleetCommandType.Hold),
        commandLabel: "Hold",
        destinationLabel: "-",
        statusLabel: "Active",
        roe: 6,
        hasCombatShips: true,
        hasCrippled: true
      )
    ]
    model.view.ownFleetsById[100] = Fleet(
      id: FleetId(100),
      houseId: HouseId(1),
      location: SystemId(11),
      ships: @[ShipId(201)]
    )
    model.view.ownShipsById[201] = Ship(
      id: ShipId(201),
      houseId: HouseId(1),
      shipClass: ShipClass.Destroyer,
      state: CombatState.Crippled
    )
    model.ui.pristineFleets = model.view.fleets
    model.ui.pristineFleetConsoleFleetsBySystem =
      model.ui.fleetConsoleFleetsBySystem
    model.ui.pristineOwnFleetsById = model.view.ownFleetsById

    var packet = CommandPacket()
    packet.houseId = HouseId(1)
    packet.turn = 9
    packet.zeroTurnCommands = @[
      ZeroTurnCommand(
        houseId: HouseId(1),
        commandType: ZeroTurnCommandType.Reactivate,
        sourceFleetId: some(FleetId(100)),
        targetFleetId: none(FleetId)
      )
    ]
    packet.fleetCommands = @[
      FleetCommand(
        fleetId: FleetId(100),
        commandType: FleetCommandType.Move,
        targetSystem: some(SystemId(12)),
        targetFleet: none(FleetId),
        roe: some(4'i32)
      )
    ]
    packet.buildCommands = @[
      BuildCommand(
        colonyId: ColonyId(70),
        buildType: BuildType.Industrial,
        quantity: 1,
        shipClass: none(ShipClass),
        facilityClass: none(FacilityClass),
        groundClass: none(GroundClass),
        industrialUnits: 2
      )
    ]
    packet.repairCommands = @[
      RepairCommand(
        colonyId: ColonyId(70),
        targetType: RepairTargetType.Ship,
        targetId: 201,
        priority: 1
      )
    ]
    packet.scrapCommands = @[
      ScrapCommand(
        colonyId: ColonyId(70),
        targetType: ScrapTargetType.Neoria,
        targetId: 10,
        acknowledgeQueueLoss: true
      )
    ]
    packet.populationTransfers = @[
      PopulationTransferCommand(
        houseId: HouseId(1),
        sourceColony: ColonyId(70),
        destColony: ColonyId(71),
        ptuAmount: 3
      )
    ]
    packet.terraformCommands = @[
      TerraformCommand(
        houseId: HouseId(1),
        colonyId: ColonyId(70),
        startTurn: 9,
        turnsRemaining: 0,
        ppCost: 0,
        targetClass: 0
      )
    ]
    packet.colonyManagement = @[
      ColonyManagementCommand(
        colonyId: ColonyId(70),
        autoRepair: true,
        autoLoadFighters: false,
        autoLoadMarines: true,
        taxRate: some(17'i32)
      )
    ]
    packet.diplomaticCommand = @[
      DiplomaticCommand(
        houseId: HouseId(1),
        targetHouse: HouseId(2),
        actionType: DiplomaticActionType.DeclareHostile,
        proposalId: none(ProposalId),
        proposalType: none(ProposalType),
        message: some("resume")
      )
    ]
    packet.researchAllocation = ResearchAllocation(
      economic: 10,
      science: 5,
      technology: initTable[TechField, int32]()
    )
    packet.researchAllocation.technology[TechField.WeaponsTech] = 7
    packet.espionageActions = @[
      EspionageAttempt(
        attacker: HouseId(1),
        target: HouseId(2),
        action: EspionageAction.TechTheft,
        targetSystem: none(SystemId)
      )
    ]
    packet.ebpInvestment = 3
    packet.cipInvestment = 1

    model.applyOrderDraft(packet)

    check model.ui.stagedZeroTurnCommands.len == 1
    check model.ui.stagedFleetCommands.len == 1
    check model.ui.stagedBuildCommands.len == 1
    check model.ui.stagedRepairCommands.len == 1
    check model.ui.stagedScrapCommands.len == 1
    check model.ui.stagedPopulationTransfers.len == 1
    check model.ui.stagedTerraformCommands.len == 1
    check model.ui.stagedColonyManagement.len == 1
    check model.ui.stagedDiplomaticCommands.len == 1
    check model.ui.stagedEspionageActions.len == 1
    check model.ui.stagedEbpInvestment == 3
    check model.ui.stagedCipInvestment == 1
    check model.ui.stagedTaxRate.isSome
    check model.ui.stagedTaxRate.get() == 17
    check model.ui.modifiedSinceSubmit == false

    # Optimistic replay should update displayed fleet command from Hold.
    check model.view.fleets[0].commandLabel != "Hold"
