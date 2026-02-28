## Unit tests for TUI command staging coverage.

import std/unittest
import std/[options, tables]
import std/strutils
import std/sets

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

  proc linkSystems(model: var TuiModel, a: int, b: int) =
    model.view.laneNeighbors[a] =
      model.view.laneNeighbors.getOrDefault(a, @[])
    model.view.laneNeighbors[b] =
      model.view.laneNeighbors.getOrDefault(b, @[])
    model.view.laneNeighbors[a].add(b)
    model.view.laneNeighbors[b].add(a)
    model.view.laneTypes[(a, b)] = 0
    model.view.laneTypes[(b, a)] = 0

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

  test "system picker entries include pathfinding ETA labels":
    var model = initTuiModel()
    model.view.systems[(0, 0)] = SystemInfo(id: 11, name: "A")
    model.view.systems[(1, 0)] = SystemInfo(id: 12, name: "B")
    model.view.systems[(2, 0)] = SystemInfo(id: 13, name: "C")
    model.view.systemCoords[11] = (0, 0)
    model.view.systemCoords[12] = (1, 0)
    model.view.systemCoords[13] = (2, 0)
    model.view.laneNeighbors[11] = @[12]
    model.view.laneNeighbors[12] = @[11, 13]
    model.view.laneNeighbors[13] = @[12]
    model.view.laneTypes[(11, 12)] = 0
    model.view.laneTypes[(12, 11)] = 0
    model.view.laneTypes[(12, 13)] = 0
    model.view.laneTypes[(13, 12)] = 0
    model.view.ownedSystemIds.incl(11)
    model.view.ownedSystemIds.incl(12)
    model.view.ownedSystemIds.incl(13)
    model.view.ownFleetsById[100] = Fleet(
      id: FleetId(100),
      houseId: HouseId(1),
      location: SystemId(11),
      ships: @[ShipId(500)]
    )
    model.view.ownShipsById[500] = Ship(
      id: ShipId(500),
      houseId: HouseId(1),
      shipClass: ShipClass.Destroyer
    )

    let picker = model.buildSystemPickerListForCommand(
      FleetCommandType.Move,
      @[100]
    )
    var found11 = false
    var found12 = false
    for row in picker.systems:
      if row.systemId == 11:
        found11 = true
        check row.etaLabel == "0"
      if row.systemId == 12:
        found12 = true
        check row.etaLabel.len > 0
        check row.etaLabel != "-"
        check row.etaLabel != "N/A"
    check found11
    check found12

  test "system picker is sorted by shortest ETA":
    var model = initTuiModel()
    model.view.systems[(9, 0)] = SystemInfo(id: 21, name: "Home")
    model.view.systems[(0, 0)] = SystemInfo(id: 22, name: "Near")
    model.view.systems[(1, 0)] = SystemInfo(id: 23, name: "Far")
    model.view.systemCoords[21] = (9, 0)
    model.view.systemCoords[22] = (0, 0)
    model.view.systemCoords[23] = (1, 0)
    model.view.laneNeighbors[21] = @[22]
    model.view.laneNeighbors[22] = @[21, 23]
    model.view.laneNeighbors[23] = @[22]
    model.view.laneTypes[(21, 22)] = 0
    model.view.laneTypes[(22, 21)] = 0
    model.view.laneTypes[(22, 23)] = 0
    model.view.laneTypes[(23, 22)] = 0
    model.view.ownedSystemIds.incl(21)
    model.view.ownedSystemIds.incl(22)
    model.view.ownedSystemIds.incl(23)
    model.view.ownFleetsById[101] = Fleet(
      id: FleetId(101),
      houseId: HouseId(1),
      location: SystemId(21),
      ships: @[ShipId(501)]
    )
    model.view.ownShipsById[501] = Ship(
      id: ShipId(501),
      houseId: HouseId(1),
      shipClass: ShipClass.Destroyer
    )

    let picker = model.buildSystemPickerListForCommand(
      FleetCommandType.Move,
      @[101]
    )
    check picker.systems.len == 3
    check picker.systems[0].systemId == 21
    check picker.systems[0].etaLabel == "0"
    check picker.systems[0].etaSortMin <= picker.systems[1].etaSortMin
    check picker.systems[1].etaSortMin <= picker.systems[2].etaSortMin

  test "colonize picker excludes known colonized systems":
    var model = initTuiModel()
    model.view.systems[(0, 0)] = SystemInfo(id: 31, name: "Owned")
    model.view.systems[(1, 0)] = SystemInfo(id: 32, name: "Enemy")
    model.view.systems[(2, 0)] = SystemInfo(id: 33, name: "Free")
    model.view.planetsRows = @[
      PlanetRow(
        systemId: 31,
        colonyId: some(1),
        systemName: "Owned",
        isOwned: true
      )
    ]
    model.view.knownEnemyColonySystemIds.incl(32)

    let picker = model.buildSystemPickerListForCommand(
      FleetCommandType.Colonize,
      @[]
    )
    check picker.systems.len == 1
    check picker.systems[0].systemId == 33

  test "colonize picker excludes systems targeted by other fleets":
    var model = initTuiModel()
    model.view.systems[(0, 0)] = SystemInfo(id: 41, name: "OpenA")
    model.view.systems[(1, 0)] = SystemInfo(id: 42, name: "Taken")
    model.view.systems[(2, 0)] = SystemInfo(id: 43, name: "OpenB")
    model.view.systemCoords[41] = (0, 0)
    model.view.systemCoords[42] = (1, 0)
    model.view.systemCoords[43] = (2, 0)
    model.linkSystems(41, 42)
    model.linkSystems(42, 43)
    model.view.fleets = @[
      FleetInfo(
        id: 401,
        owner: 1,
        location: 41,
        command: CmdColonize,
        destinationSystemId: 42
      ),
      FleetInfo(
        id: 402,
        owner: 1,
        location: 41,
        command: CmdColonize,
        destinationSystemId: 43
      )
    ]

    let picker = model.buildSystemPickerListForCommand(
      FleetCommandType.Colonize,
      @[402]
    )
    var has41 = false
    var has42 = false
    var has43 = false
    for row in picker.systems:
      if row.systemId == 41: has41 = true
      if row.systemId == 42: has42 = true
      if row.systemId == 43: has43 = true
    check has41
    check has43
    check not has42

  test "view picker keeps visible non-owned reachable systems":
    var model = initTuiModel()
    model.view.systems[(0, 0)] = SystemInfo(id: 51, name: "Owned")
    model.view.systems[(1, 0)] = SystemInfo(id: 52, name: "Visible")
    model.view.systems[(2, 0)] = SystemInfo(id: 53, name: "Far")
    model.view.systemCoords[51] = (0, 0)
    model.view.systemCoords[52] = (1, 0)
    model.view.systemCoords[53] = (2, 0)
    model.linkSystems(51, 52)
    model.view.planetsRows = @[
      PlanetRow(systemId: 51, isOwned: true)
    ]
    model.view.intelRows = @[
      IntelRow(systemId: 51, ownerName: "You"),
      IntelRow(systemId: 52, ownerName: "Enemy"),
      IntelRow(systemId: 53, ownerName: "---")
    ]
    model.view.fleets = @[
      FleetInfo(id: 501, owner: 1, location: 51)
    ]

    let picker = model.buildSystemPickerListForCommand(
      FleetCommandType.View,
      @[501]
    )
    check picker.systems.len == 1
    check picker.systems[0].systemId == 52

  test "scout colony picker only shows known enemy colonies":
    var model = initTuiModel()
    model.view.systems[(0, 0)] = SystemInfo(id: 61, name: "EnemyCol")
    model.view.systems[(1, 0)] = SystemInfo(id: 62, name: "Unknown")
    model.view.systemCoords[61] = (0, 0)
    model.view.systemCoords[62] = (1, 0)
    model.linkSystems(61, 62)
    model.view.intelRows = @[
      IntelRow(systemId: 61, ownerName: "Enemy"),
      IntelRow(systemId: 62, ownerName: "---")
    ]
    model.view.knownEnemyColonySystemIds.incl(61)
    model.view.fleets = @[
      FleetInfo(id: 601, owner: 1, location: 61)
    ]

    let picker = model.buildSystemPickerListForCommand(
      FleetCommandType.ScoutColony,
      @[601]
    )
    check picker.systems.len == 1
    check picker.systems[0].systemId == 61

  test "blockade picker includes known uncolonized visible systems":
    var model = initTuiModel()
    model.view.systems[(0, 0)] = SystemInfo(id: 71, name: "EnemyCol")
    model.view.systems[(1, 0)] = SystemInfo(id: 72, name: "Open")
    model.view.systemCoords[71] = (0, 0)
    model.view.systemCoords[72] = (1, 0)
    model.linkSystems(71, 72)
    model.view.intelRows = @[
      IntelRow(systemId: 71, ownerName: "Enemy"),
      IntelRow(systemId: 72, ownerName: "---")
    ]
    model.view.knownEnemyColonySystemIds.incl(71)
    model.view.fleets = @[
      FleetInfo(id: 701, owner: 1, location: 71)
    ]

    let picker = model.buildSystemPickerListForCommand(
      FleetCommandType.Blockade,
      @[701]
    )
    var has71 = false
    var has72 = false
    for row in picker.systems:
      if row.systemId == 71:
        has71 = true
      if row.systemId == 72:
        has72 = true
    check has71
    check has72

  test "command picker filters irrelevant single-fleet missions":
    var model = initTuiModel()
    model.view.fleets = @[
      FleetInfo(
        id: 200,
        name: "A1",
        hasCombatShips: true,
        hasTroopTransports: false,
        hasEtacs: false,
        isScoutOnly: false
      )
    ]
    model.ui.fleetDetailModal.fleetId = 200

    let commands = model.buildCommandPickerList()
    check FleetCommandType.Move in commands
    check FleetCommandType.GuardColony in commands
    check FleetCommandType.Blitz notin commands
    check FleetCommandType.Colonize notin commands
    check FleetCommandType.ScoutSystem notin commands

  test "batch command picker excludes join and invalid missions":
    var model = initTuiModel()
    model.view.fleets = @[
      FleetInfo(
        id: 301,
        name: "A1",
        hasCombatShips: true,
        hasTroopTransports: true,
        hasEtacs: false,
        isScoutOnly: false
      ),
      FleetInfo(
        id: 302,
        name: "A2",
        hasCombatShips: true,
        hasTroopTransports: false,
        hasEtacs: false,
        isScoutOnly: false
      )
    ]
    model.ui.fleetDetailModal.batchFleetIds = @[301, 302]

    let commands = model.buildCommandPickerList()
    check FleetCommandType.GuardColony in commands
    check FleetCommandType.JoinFleet notin commands
    check FleetCommandType.Invade notin commands
    check FleetCommandType.Colonize notin commands

  test "clearStagedCommands resets all categories and optimistic fleet view":
    var model = initTuiModel()
    model.view.fleets = @[
      FleetInfo(
        id: 801,
        name: "A1",
        location: 21,
        command: int(FleetCommandType.Hold),
        commandLabel: "Hold",
        destinationLabel: "-",
        owner: 1,
        roe: 6,
        hasCombatShips: true
      )
    ]
    model.ui.pristineFleets = model.view.fleets
    model.ui.pristineFleetConsoleFleetsBySystem =
      model.ui.fleetConsoleFleetsBySystem
    model.ui.pristineOwnFleetsById = model.view.ownFleetsById

    model.ui.stagedZeroTurnCommands = @[
      ZeroTurnCommand(commandType: ZeroTurnCommandType.Reactivate)
    ]
    model.ui.stagedBuildCommands = @[
      BuildCommand(colonyId: ColonyId(1), buildType: BuildType.Industrial)
    ]
    model.ui.stagedRepairCommands = @[
      RepairCommand(colonyId: ColonyId(1), targetType: RepairTargetType.Ship)
    ]
    model.ui.stagedScrapCommands = @[
      ScrapCommand(colonyId: ColonyId(1), targetType: ScrapTargetType.Ship)
    ]
    model.ui.stagedPopulationTransfers = @[
      PopulationTransferCommand(houseId: HouseId(1))
    ]
    model.ui.stagedTerraformCommands = @[
      TerraformCommand(houseId: HouseId(1))
    ]
    model.ui.stagedColonyManagement = @[
      ColonyManagementCommand(colonyId: ColonyId(1))
    ]
    model.ui.stagedDiplomaticCommands = @[
      DiplomaticCommand(houseId: HouseId(1), targetHouse: HouseId(2))
    ]
    model.ui.stagedEspionageActions = @[
      EspionageAttempt(attacker: HouseId(1), target: HouseId(2))
    ]
    model.ui.stagedEbpInvestment = 4
    model.ui.stagedCipInvestment = 3
    model.ui.stagedTaxRate = some(18)

    model.stageFleetCommand(FleetCommand(
      fleetId: FleetId(801),
      commandType: FleetCommandType.Move,
      targetSystem: some(SystemId(22))
    ))
    check model.view.fleets[0].commandLabel == "Move"

    model.clearStagedCommands()

    check model.stagedCommandCount() == 0
    check model.ui.stagedFleetCommands.len == 0
    check model.ui.stagedZeroTurnCommands.len == 0
    check model.ui.stagedBuildCommands.len == 0
    check model.ui.stagedRepairCommands.len == 0
    check model.ui.stagedScrapCommands.len == 0
    check model.ui.stagedPopulationTransfers.len == 0
    check model.ui.stagedTerraformCommands.len == 0
    check model.ui.stagedColonyManagement.len == 0
    check model.ui.stagedDiplomaticCommands.len == 0
    check model.ui.stagedEspionageActions.len == 0
    check model.ui.stagedEbpInvestment == 0
    check model.ui.stagedCipInvestment == 0
    check model.ui.stagedTaxRate.isNone
    check model.view.fleets[0].commandLabel == "Hold"
