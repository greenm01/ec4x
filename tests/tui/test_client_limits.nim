## Tests for player-client limit validation helpers.

import std/[unittest, options, tables, math, strutils]

import ../../src/player/sam/[tui_model, client_limits]
import ../../src/engine/config/engine
import ../../src/engine/types/[core, production, ship, facilities, ground_unit,
  fleet, tech]
import ../../src/engine/globals

gameConfig = loadGameConfig()

proc mkFleetInfo(id: int, shipCount: int): FleetInfo =
  FleetInfo(
    id: id,
    name: "Fleet " & $id,
    location: 1,
    locationName: "A1",
    sectorLabel: "A1",
    shipCount: shipCount,
    owner: 1,
    command: 0,
    commandLabel: "Hold",
    isIdle: true,
    roe: 6,
    attackStrength: 0,
    defenseStrength: 0,
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
    needsAttention: false,
  )

suite "Client limits":
  test "optimistic C2 includes staged ship command cost":
    let staged = @[
      BuildCommand(
        colonyId: ColonyId(10),
        buildType: BuildType.Ship,
        quantity: 2,
        shipClass: some(ShipClass.Corvette),
        facilityClass: none(FacilityClass),
        groundClass: none(GroundClass),
        industrialUnits: 0,
      ),
    ]
    let expectedDelta =
      int(gameConfig.ships.ships[ShipClass.Corvette].commandCost) * 2
    check stagedC2Delta(staged) == expectedDelta
    check optimisticC2Used(5, staged) == 5 + expectedDelta

  test "optimistic treasury subtracts staged build PP":
    let staged = @[
      BuildCommand(
        colonyId: ColonyId(10),
        buildType: BuildType.Ship,
        quantity: 2,
        shipClass: some(ShipClass.Corvette),
        facilityClass: none(FacilityClass),
        groundClass: none(GroundClass),
        industrialUnits: 0,
      ),
      BuildCommand(
        colonyId: ColonyId(10),
        buildType: BuildType.Facility,
        quantity: 1,
        shipClass: none(ShipClass),
        facilityClass: some(FacilityClass.Spaceport),
        groundClass: none(GroundClass),
        industrialUnits: 0,
      ),
    ]
    let expected =
      int(gameConfig.ships.ships[ShipClass.Corvette].productionCost) * 2 +
      int(gameConfig.facilities.facilities[FacilityClass.Spaceport].buildCost)
    check stagedPpCost(staged) == expected
    check optimisticTreasury(1000, staged) == 1000 - expected

  test "spaceport cap blocks staged build":
    var model = initTuiModel()
    let maxSpaceports =
      int(gameConfig.limits.quantityLimits.maxSpaceportsPerColony)
    model.view.colonyLimits[10] = ColonyLimitSnapshot(
      industrialUnits: 300,
      fighters: 0,
      spaceports: maxSpaceports,
      starbases: 0,
      shields: 0,
    )
    let cmd = BuildCommand(
      colonyId: ColonyId(10),
      buildType: BuildType.Facility,
      quantity: 1,
      shipClass: none(ShipClass),
      facilityClass: some(FacilityClass.Spaceport),
      groundClass: none(GroundClass),
      industrialUnits: 0,
    )
    let errs = validateStagedBuildLimits(model, @[cmd])
    check errs.len > 0
    check errs[0].contains("Spaceport limit exceeded")

  test "starbase cap blocks staged build":
    var model = initTuiModel()
    let maxStarbases =
      int(gameConfig.limits.quantityLimits.maxStarbasesPerColony)
    model.view.colonyLimits[10] = ColonyLimitSnapshot(
      industrialUnits: 300,
      fighters: 0,
      spaceports: 1,
      starbases: maxStarbases,
      shields: 0,
    )
    let cmd = BuildCommand(
      colonyId: ColonyId(10),
      buildType: BuildType.Facility,
      quantity: 1,
      shipClass: none(ShipClass),
      facilityClass: some(FacilityClass.Starbase),
      groundClass: none(GroundClass),
      industrialUnits: 0,
    )
    let errs = validateStagedBuildLimits(model, @[cmd])
    check errs.len > 0
    check errs[0].contains("Starbase limit exceeded")

  test "planetary shield cap blocks staged build":
    var model = initTuiModel()
    let maxShields =
      int(gameConfig.limits.quantityLimits.maxPlanetaryShieldsPerColony)
    model.view.colonyLimits[10] = ColonyLimitSnapshot(
      industrialUnits: 300,
      fighters: 0,
      spaceports: 0,
      starbases: 0,
      shields: maxShields,
    )
    let cmd = BuildCommand(
      colonyId: ColonyId(10),
      buildType: BuildType.Ground,
      quantity: 1,
      shipClass: none(ShipClass),
      facilityClass: none(FacilityClass),
      groundClass: some(GroundClass.PlanetaryShield),
      industrialUnits: 0,
    )
    let errs = validateStagedBuildLimits(model, @[cmd])
    check errs.len > 0
    check errs[0].contains("Planetary shield limit exceeded")

  test "fighter cap blocks staged fighter build":
    var model = initTuiModel()
    let divisor = gameConfig.limits.fighterCapacity.iuDivisor
    let iu = max(100, int(divisor))
    let fighterCap =
      if divisor > 0'i32:
        int(floor((float32(iu) / float32(divisor)) * 1.0'f32))
      else:
        0
    model.view.colonyLimits[10] = ColonyLimitSnapshot(
      industrialUnits: iu,
      fighters: fighterCap,
      spaceports: 0,
      starbases: 0,
      shields: 0,
    )
    model.view.techLevels = some(TechLevel(fd: 1))
    let cmd = BuildCommand(
      colonyId: ColonyId(10),
      buildType: BuildType.Ship,
      quantity: 1,
      shipClass: some(ShipClass.Fighter),
      facilityClass: none(FacilityClass),
      groundClass: none(GroundClass),
      industrialUnits: 0,
    )
    let errs = validateStagedBuildLimits(model, @[cmd])
    check errs.len > 0
    check errs[0].contains("Fighter limit exceeded")

  test "planet-breaker cap blocks staged build":
    var model = initTuiModel()
    model.view.colonyLimits[10] = ColonyLimitSnapshot(industrialUnits: 200)
    model.view.colonyLimits[11] = ColonyLimitSnapshot(industrialUnits: 200)
    model.view.planetBreakersInFleets = 2
    let cmd = BuildCommand(
      colonyId: ColonyId(10),
      buildType: BuildType.Ship,
      quantity: 1,
      shipClass: some(ShipClass.PlanetBreaker),
      facilityClass: none(FacilityClass),
      groundClass: none(GroundClass),
      industrialUnits: 0,
    )
    let errs = validateStagedBuildLimits(model, @[cmd])
    check errs.len > 0
    check errs[0].contains("Planet-breaker limit exceeded")

  test "join fleet FC limit blocks command":
    var model = initTuiModel()
    model.view.fleets = @[
      mkFleetInfo(1, 999),
      mkFleetInfo(2, 1),
    ]
    let err = validateJoinFleetFc(model, 1, 2)
    check err.isSome
    check err.get().contains("FC")

    model.ui.stagedFleetCommands = initTable[int, FleetCommand]()
    model.ui.stagedFleetCommands[1] = FleetCommand(
      fleetId: FleetId(1),
      commandType: FleetCommandType.JoinFleet,
      targetSystem: none(SystemId),
      targetFleet: some(FleetId(2)),
      roe: none(int32),
    )
    let stagedErrs = validateStagedFleetLimits(model)
    check stagedErrs.len > 0
