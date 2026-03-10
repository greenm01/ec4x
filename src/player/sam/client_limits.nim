## Client-side limit analysis and validation for Player TUI.
##
## Mirrors engine-side limit formulas where data is available in PlayerState.

import std/[options, tables, math]

import ./tui_model
import ../../engine/types/[core, player_state, ship, production, facilities,
  ground_unit, fleet, tech, combat]
import ../../engine/globals

type
  StagedColonyLimits = object
    etacPtu*: int
    fighters: int
    spaceports: int
    starbases: int
    shields: int

  ShipCostBreakdown* = object
    totalCost*: int
    nextIncrementCost*: int
    nextIncrementSource*: ShipBuildSource
    shipyardSlotsRemaining*: int
    triggersSpillover*: bool

  ColonyDockState = object
    shipyardRemaining: int
    spaceportRemaining: int

proc effectiveDockCount(baseDocks: int32, techLevels: Option[TechLevel]): int =
  let cstLevel =
    if techLevels.isSome:
      max(1'i32, techLevels.get().cst)
    else:
      1'i32
  int(floor(
    float32(baseDocks) *
    (gameConfig.tech.cst.baseModifier +
      (float32(cstLevel - 1'i32) * gameConfig.tech.cst.incrementPerLevel))
  ))

proc shipUnitCost(shipClass: ShipClass, source: ShipBuildSource): int =
  let baseCost = int(gameConfig.ships.ships[shipClass].productionCost)
  case source
  of ShipBuildSource.Spaceport:
    baseCost * 2
  else:
    baseCost

proc initColonyDockState(
    snapshot: ColonyLimitSnapshot,
    techLevels: Option[TechLevel],
): ColonyDockState =
  ColonyDockState(
    shipyardRemaining: snapshot.shipyards * effectiveDockCount(
      gameConfig.facilities.facilities[FacilityClass.Shipyard].docks,
      techLevels,
    ),
    spaceportRemaining: snapshot.spaceports * effectiveDockCount(
      gameConfig.facilities.facilities[FacilityClass.Spaceport].docks,
      techLevels,
    ),
  )

proc initColonyDockState(docks: DockSummary): ColonyDockState =
  ColonyDockState(
    shipyardRemaining: max(0, docks.shipyardAvailable),
    spaceportRemaining: max(0, docks.spaceportAvailable),
  )

proc consumeShipDock(
    state: var ColonyDockState,
    shipClass: ShipClass,
): ShipBuildSource =
  if shipClass == ShipClass.Fighter:
    return ShipBuildSource.Planetside

  if state.shipyardRemaining > 0:
    state.shipyardRemaining.dec
    return ShipBuildSource.Shipyard

  if state.spaceportRemaining > 0:
    state.spaceportRemaining.dec
    return ShipBuildSource.Spaceport

  ShipBuildSource.None

proc simulateShipCommandCost(
    dockState: var ColonyDockState,
    shipClass: ShipClass,
    quantity: int,
    trackNextIncrement: bool = false,
): ShipCostBreakdown =
  let qty = max(0, quantity)
  for _ in 0 ..< qty:
    let source = consumeShipDock(dockState, shipClass)
    if source == ShipBuildSource.None:
      break
    result.totalCost += shipUnitCost(shipClass, source)

  result.shipyardSlotsRemaining = max(0, dockState.shipyardRemaining)

  if not trackNextIncrement:
    return

  let directSource = consumeShipDock(dockState, shipClass)
  result.nextIncrementSource = directSource
  if directSource != ShipBuildSource.None:
    result.nextIncrementCost = shipUnitCost(shipClass, directSource)
    result.shipyardSlotsRemaining = max(0, dockState.shipyardRemaining)

proc commandIncrementPreview*(
    stagedBuildCommands: seq[BuildCommand],
    colonyId: ColonyId,
    shipClass: ShipClass,
    dockSummary: DockSummary,
): ShipCostBreakdown =
  var currentDocks = initColonyDockState(dockSummary)
  var hypotheticalDocks = initColonyDockState(dockSummary)

  var currentCost = 0
  var hypotheticalCost = 0
  var matchedExisting = false
  var preview = ShipCostBreakdown(
    nextIncrementSource: ShipBuildSource.None,
  )

  for cmd in stagedBuildCommands:
    if cmd.colonyId != colonyId:
      continue

    let qty = max(0, int(cmd.quantity))
    if cmd.buildType != BuildType.Ship or cmd.shipClass.isNone:
      continue

    let cmdShipClass = cmd.shipClass.get()
    currentCost += simulateShipCommandCost(
      currentDocks,
      cmdShipClass,
      qty,
    ).totalCost

    if cmdShipClass == shipClass and not matchedExisting:
      matchedExisting = true
      let currentBreakdown = simulateShipCommandCost(
        hypotheticalDocks,
        cmdShipClass,
        qty,
        trackNextIncrement = true,
      )
      hypotheticalCost += currentBreakdown.totalCost
      preview = currentBreakdown

      if currentBreakdown.nextIncrementSource != ShipBuildSource.None:
        hypotheticalCost += shipUnitCost(
          shipClass,
          currentBreakdown.nextIncrementSource,
        )
    else:
      hypotheticalCost += simulateShipCommandCost(
        hypotheticalDocks,
        cmdShipClass,
        qty,
      ).totalCost

  if not matchedExisting:
    preview = simulateShipCommandCost(
      hypotheticalDocks,
      shipClass,
      0,
      trackNextIncrement = true,
    )
    if preview.nextIncrementSource != ShipBuildSource.None:
      hypotheticalCost = currentCost + shipUnitCost(
        shipClass,
        preview.nextIncrementSource,
      )
    else:
      hypotheticalCost = currentCost

  preview.totalCost = currentCost
  preview.nextIncrementCost = max(0, hypotheticalCost - currentCost)
  let directCost = shipUnitCost(shipClass, preview.nextIncrementSource)
  preview.triggersSpillover =
    preview.nextIncrementSource != ShipBuildSource.None and
    preview.nextIncrementCost > directCost
  preview

proc stagedShipCommandCosts*(
    stagedBuildCommands: seq[BuildCommand],
    colonyLimits: Table[int, ColonyLimitSnapshot],
    techLevels: Option[TechLevel],
): seq[int] =
  result = newSeq[int](stagedBuildCommands.len)
  var dockStates = initTable[int, ColonyDockState]()

  for idx, cmd in stagedBuildCommands:
    let qty = max(0, int(cmd.quantity))
    case cmd.buildType
    of BuildType.Ship:
      if cmd.shipClass.isSome:
        let shipClass = cmd.shipClass.get()
        if shipClass != ShipClass.Fighter:
          let key = int(cmd.colonyId)
          if key notin colonyLimits:
            result[idx] = qty * shipUnitCost(
              shipClass,
              ShipBuildSource.Shipyard,
            )
            continue
          if key notin dockStates:
            let snapshot = colonyLimits.getOrDefault(key)
            dockStates[key] = initColonyDockState(snapshot, techLevels)
          result[idx] = simulateShipCommandCost(
            dockStates[key],
            shipClass,
            qty,
          ).totalCost
        else:
          result[idx] = qty * shipUnitCost(
            shipClass,
            ShipBuildSource.Planetside,
          )
    of BuildType.Facility:
      if cmd.facilityClass.isSome:
        let facilityClass = cmd.facilityClass.get()
        result[idx] =
          qty * int(gameConfig.facilities.facilities[facilityClass].buildCost)
    of BuildType.Ground:
      if cmd.groundClass.isSome:
        let groundClass = cmd.groundClass.get()
        result[idx] =
          qty * int(gameConfig.groundUnits.units[groundClass].productionCost)
    of BuildType.Industrial:
      let cost = int(gameConfig.economy.industrialInvestment.baseCost)
      let units = max(0, int(cmd.industrialUnits))
      result[idx] = cost * units
    else:
      discard

proc stagedShipCommandCostsAtColony*(
    stagedBuildCommands: seq[BuildCommand],
    colonyId: ColonyId,
    dockSummary: DockSummary,
): seq[int] =
  result = newSeq[int](stagedBuildCommands.len)
  var dockState = initColonyDockState(dockSummary)

  for idx, cmd in stagedBuildCommands:
    if cmd.colonyId != colonyId:
      continue

    let qty = max(0, int(cmd.quantity))
    case cmd.buildType
    of BuildType.Ship:
      if cmd.shipClass.isSome:
        let shipClass = cmd.shipClass.get()
        if shipClass != ShipClass.Fighter:
          result[idx] = simulateShipCommandCost(
            dockState,
            shipClass,
            qty,
          ).totalCost
        else:
          result[idx] = qty * shipUnitCost(
            shipClass,
            ShipBuildSource.Planetside,
          )
    of BuildType.Facility:
      if cmd.facilityClass.isSome:
        let facilityClass = cmd.facilityClass.get()
        result[idx] =
          qty * int(gameConfig.facilities.facilities[facilityClass].buildCost)
    of BuildType.Ground:
      if cmd.groundClass.isSome:
        let groundClass = cmd.groundClass.get()
        result[idx] =
          qty * int(gameConfig.groundUnits.units[groundClass].productionCost)
    of BuildType.Industrial:
      let cost = int(gameConfig.economy.industrialInvestment.baseCost)
      let units = max(0, int(cmd.industrialUnits))
      result[idx] = cost * units
    else:
      discard

proc canSupportEtacBuild*(
    snapshot: ColonyLimitSnapshot,
    stagedEtacPtu: int,
): bool =
  ## Returns true when a colony can spare this many PTU and still remain
  ## above the minimum viable population threshold.
  let minSouls = int(gameConfig.limits.populationLimits.minColonyPopulation)
  let requiredSouls =
    stagedEtacPtu * int(gameConfig.economy.ptuDefinition.soulsPerPtu)
  requiredSouls == 0 or snapshot.souls - requiredSouls >= minSouls

proc shipLookup(ps: PlayerState): Table[ShipId, Ship] =
  result = initTable[ShipId, Ship]()
  for ship in ps.ownShips:
    result[ship.id] = ship

proc c2StatusModifier(status: FleetStatus): float32 =
  case status
  of FleetStatus.Active:
    1.0'f32
  of FleetStatus.Reserve:
    0.5'f32
  of FleetStatus.Mothballed:
    0.0'f32

proc fighterDoctrineMultiplier(fdLevel: int): float32 =
  case fdLevel
  of 1:
    1.0'f32
  of 2:
    1.5'f32
  of 3:
    2.0'f32
  else:
    1.0'f32

proc fdLevel(techLevels: Option[TechLevel]): int =
  if techLevels.isSome:
    max(1, int(techLevels.get().fd))
  else:
    1

proc scLevel(techLevels: Option[TechLevel]): int32 =
  if techLevels.isSome:
    max(1'i32, techLevels.get().sc)
  else:
    1'i32

proc fcLevel(techLevels: Option[TechLevel]): int32 =
  if techLevels.isSome:
    max(1'i32, techLevels.get().fc)
  else:
    1'i32

proc lowestLevelKey[T](levels: Table[int32, T]): Option[int32] =
  var hasValue = false
  var lowest = 0'i32
  for level, _ in levels.pairs:
    if not hasValue or level < lowest:
      hasValue = true
      lowest = level
  if hasValue:
    some(lowest)
  else:
    none(int32)

proc scC2Bonus(sc: int32): int32 =
  if gameConfig.tech.sc.levels.hasKey(sc):
    return gameConfig.tech.sc.levels[sc].c2Bonus
  let fallback = lowestLevelKey(gameConfig.tech.sc.levels)
  if fallback.isSome:
    return gameConfig.tech.sc.levels[fallback.get()].c2Bonus
  else:
    return 0'i32

proc stagedCounts(
    commands: seq[BuildCommand],
    colonyLimits: Table[int, ColonyLimitSnapshot],
): tuple[byColony: Table[int, StagedColonyLimits], planetBreakers: int,
         invalidColonyIds: seq[int]] =
  result.byColony = initTable[int, StagedColonyLimits]()
  result.invalidColonyIds = @[]
  for cmd in commands:
    let colonyId = int(cmd.colonyId)
    if colonyId notin colonyLimits:
      result.invalidColonyIds.add(colonyId)
      continue
    let qty = max(0, int(cmd.quantity))
    var limits = result.byColony.getOrDefault(colonyId)
    case cmd.buildType
    of BuildType.Ship:
      if cmd.shipClass.isSome:
        case cmd.shipClass.get()
        of ShipClass.ETAC:
          let ptu = int(gameConfig.ships.ships[ShipClass.ETAC].carryLimit)
          limits.etacPtu += ptu * qty
        of ShipClass.Fighter:
          limits.fighters += qty
        of ShipClass.PlanetBreaker:
          result.planetBreakers += qty
        else:
          discard
    of BuildType.Facility:
      if cmd.facilityClass.isSome:
        case cmd.facilityClass.get()
        of FacilityClass.Spaceport:
          limits.spaceports += qty
        of FacilityClass.Starbase:
          limits.starbases += qty
        else:
          discard
    of BuildType.Ground:
      if cmd.groundClass.isSome and
          cmd.groundClass.get() == GroundClass.PlanetaryShield:
        limits.shields += qty
    else:
      discard
    result.byColony[colonyId] = limits

proc fighterCapacity(iu: int, techLevels: Option[TechLevel]): int =
  let divisor = gameConfig.limits.fighterCapacity.iuDivisor
  if divisor <= 0'i32:
    return 0
  let base = float32(iu) / float32(divisor)
  let mult = fighterDoctrineMultiplier(fdLevel(techLevels))
  int(floor(base * mult))

proc fcMaxShips(techLevels: Option[TechLevel]): int =
  let level = fcLevel(techLevels)
  if gameConfig.tech.fc.levels.hasKey(level):
    return int(gameConfig.tech.fc.levels[level].maxShipsPerFleet)
  let fallback = lowestLevelKey(gameConfig.tech.fc.levels)
  if fallback.isSome:
    return int(gameConfig.tech.fc.levels[fallback.get()].maxShipsPerFleet)
  else:
    return 0

proc formatLimitError(prefix: string, current: int, maxAllowed: int): string =
  prefix & " (" & $current & "/" & $maxAllowed & ")"

proc planetBreakerLimit(colonyCount: int): int =
  max(0, colonyCount)

proc validateStagedBuildLimits*(
    model: TuiModel,
    stagedCommands: seq[BuildCommand] = @[],
): seq[string]
proc stagedPpCost*(
    stagedBuildCommands: seq[BuildCommand],
    colonyLimits: Table[int, ColonyLimitSnapshot] = initTable[
      int, ColonyLimitSnapshot
    ](),
    techLevels: Option[TechLevel] = none(TechLevel),
): int
proc stagedResearchPp*(deposits: ResearchDeposits): int
proc stagedEspionagePp*(stagedEbpInvestment, stagedCipInvestment: int32): int

proc remainingBuildPp*(model: TuiModel,
                       stagedCommands: seq[BuildCommand] = @[]): int =
  ## Remaining PP after all staged PP-consuming actions.
  let commands =
    if stagedCommands.len > 0:
      stagedCommands
    else:
      model.ui.stagedBuildCommands
  max(
    0,
    model.view.treasury -
      stagedPpCost(commands, model.view.colonyLimits, model.view.techLevels) -
      stagedResearchPp(model.ui.researchDeposits) -
      stagedEspionagePp(
        model.ui.stagedEbpInvestment,
        model.ui.stagedCipInvestment
      )
  )

proc singleIncrementError(
    model: TuiModel,
    cmd: BuildCommand,
): Option[string] =
  var staged = model.ui.stagedBuildCommands
  staged.add(cmd)
  let errors = validateStagedBuildLimits(model, staged)
  if errors.len > 0:
    some(errors[0])
  else:
    none(string)

proc validateStagedBuildLimits*(
    model: TuiModel,
    stagedCommands: seq[BuildCommand] = @[],
): seq[string] =
  ## Validate staged build commands against client-side hard limits.
  ## Defaults to model.ui.stagedBuildCommands when no list is provided.
  let commands =
    if stagedCommands.len > 0:
      stagedCommands
    else:
      model.ui.stagedBuildCommands
  let buildPp = stagedPpCost(
    commands,
    model.view.colonyLimits,
    model.view.techLevels,
  )
  let researchPp = stagedResearchPp(model.ui.researchDeposits)
  let espionagePp = stagedEspionagePp(
    model.ui.stagedEbpInvestment,
    model.ui.stagedCipInvestment
  )
  let totalPp = buildPp + researchPp + espionagePp
  if totalPp > model.view.treasury:
    result.add(formatLimitError(
      "PP exceeded",
      totalPp,
      model.view.treasury,
    ))

  let staged = stagedCounts(commands, model.view.colonyLimits)

  for colonyId in staged.invalidColonyIds:
    result.add("Colony " & $colonyId & " is not available")

  let maxSpaceports =
    int(gameConfig.limits.quantityLimits.maxSpaceportsPerColony)
  let maxStarbases =
    int(gameConfig.limits.quantityLimits.maxStarbasesPerColony)
  let maxShields =
    int(gameConfig.limits.quantityLimits.maxPlanetaryShieldsPerColony)

  for colonyId, base in model.view.colonyLimits.pairs:
    let pending = staged.byColony.getOrDefault(colonyId)
    let etacSoulsRequired =
      pending.etacPtu * int(gameConfig.economy.ptuDefinition.soulsPerPtu)
    if not canSupportEtacBuild(base, pending.etacPtu):
      let minSouls = int(gameConfig.limits.populationLimits.minColonyPopulation)
      result.add(
        "ETAC PTU limit exceeded at colony " & $colonyId &
        " (need " & $etacSoulsRequired & " souls plus " & $minSouls &
        " minimum viable)"
      )

    let fightersTotal = base.fighters + pending.fighters
    let fightersMax = fighterCapacity(base.industrialUnits,
      model.view.techLevels)
    if fightersTotal > fightersMax:
      result.add(formatLimitError(
        "Fighter limit exceeded at colony " & $colonyId,
        fightersTotal,
        fightersMax,
      ))

    let spaceportsTotal = base.spaceports + pending.spaceports
    if spaceportsTotal > maxSpaceports:
      result.add(formatLimitError(
        "Spaceport limit exceeded at colony " & $colonyId,
        spaceportsTotal,
        maxSpaceports,
      ))

    let starbasesTotal = base.starbases + pending.starbases
    if starbasesTotal > maxStarbases:
      result.add(formatLimitError(
        "Starbase limit exceeded at colony " & $colonyId,
        starbasesTotal,
        maxStarbases,
      ))

    let shieldsTotal = base.shields + pending.shields
    if shieldsTotal > maxShields:
      result.add(formatLimitError(
        "Planetary shield limit exceeded at colony " & $colonyId,
        shieldsTotal,
        maxShields,
      ))

  let pbCurrent = model.view.planetBreakersInFleets + staged.planetBreakers
  let pbMax = planetBreakerLimit(model.view.colonyLimits.len)
  if pbCurrent > pbMax:
    result.add(formatLimitError(
      "Planet-breaker limit exceeded",
      pbCurrent,
      pbMax,
    ))

proc validateBuildIncrement*(
    model: TuiModel,
    cmd: BuildCommand,
): Option[string] =
  ## Validate a new staged build increment (candidate command).
  singleIncrementError(model, cmd)

proc stagedC2Delta*(stagedBuildCommands: seq[BuildCommand]): int =
  ## Sum command-cost impact from staged ship builds.
  for cmd in stagedBuildCommands:
    if cmd.buildType != BuildType.Ship or cmd.shipClass.isNone:
      continue
    let shipClass = cmd.shipClass.get()
    let cc = int(gameConfig.ships.ships[shipClass].commandCost)
    result += cc * int(cmd.quantity)

proc optimisticC2Used*(baseUsed: int,
                       stagedBuildCommands: seq[BuildCommand]): int =
  baseUsed + stagedC2Delta(stagedBuildCommands)

proc stagedPpCost*(
    stagedBuildCommands: seq[BuildCommand],
    colonyLimits: Table[int, ColonyLimitSnapshot] = initTable[
      int, ColonyLimitSnapshot
    ](),
    techLevels: Option[TechLevel] = none(TechLevel),
): int =
  ## Sum PP committed by staged build commands (client-side preview).
  let perCommandCosts = stagedShipCommandCosts(
    stagedBuildCommands,
    colonyLimits,
    techLevels,
  )
  for cost in perCommandCosts:
    result += cost

proc stagedResearchPp*(deposits: ResearchDeposits): int =
  ## Sum staged PP deposited into research pools.
  (deposits.erp + deposits.srp + deposits.mrp).int

proc stagedEspionagePp*(stagedEbpInvestment, stagedCipInvestment: int32): int =
  ## Sum staged PP allocated to EBP/CIP investments.
  let ebpCost = int(gameConfig.espionage.costs.ebpCostPp)
  let cipCost = int(gameConfig.espionage.costs.cipCostPp)
  int(stagedEbpInvestment) * ebpCost + int(stagedCipInvestment) * cipCost

proc optimisticTreasury*(baseTreasury: int,
                         stagedBuildCommands: seq[BuildCommand]): int =
  max(0, baseTreasury - stagedPpCost(stagedBuildCommands))

proc optimisticTreasury*(baseTreasury: int,
                         stagedBuildCommands: seq[BuildCommand],
                         researchDeposits: ResearchDeposits,
                         stagedEbpInvestment, stagedCipInvestment: int32): int =
  ## Client-side treasury preview including staged build/research/espionage.
  max(
    0,
    baseTreasury -
      stagedPpCost(stagedBuildCommands) -
      stagedResearchPp(researchDeposits) -
      stagedEspionagePp(stagedEbpInvestment, stagedCipInvestment)
  )

proc computeBaseC2FromPlayerState*(
    ps: PlayerState,
): tuple[used: int, max: int] =
  ## Compute base C2 usage and pool from PlayerState (no staged orders).
  let shipsById = shipLookup(ps)
  var totalIU = 0'i32
  for colony in ps.ownColonies:
    totalIU += colony.industrial.units

  let level = scLevel(ps.techLevels)
  let ratio = gameConfig.limits.c2Limits.c2ConversionRatio
  let iuC2 = int32(floor(float32(totalIU) * ratio))
  let c2Pool = iuC2 + scC2Bonus(level)

  var used = 0'i32
  for fleet in ps.ownFleets:
    let modifier = c2StatusModifier(fleet.status)
    for shipId in fleet.ships:
      if shipId notin shipsById:
        continue
      let shipClass = shipsById[shipId].shipClass
      let baseCc = gameConfig.ships.ships[shipClass].commandCost
      used += int32(floor(float32(baseCc) * modifier))

  (used: int(used), max: int(c2Pool))

proc countPlanetBreakersInFleets*(ps: PlayerState): int =
  ## Count planet-breakers currently assigned to fleets.
  let shipsById = shipLookup(ps)
  for fleet in ps.ownFleets:
    for shipId in fleet.ships:
      if shipId notin shipsById:
        continue
      if shipsById[shipId].shipClass == ShipClass.PlanetBreaker:
        result.inc

proc colonyLimitSnapshotsFromPlayerState*(
    ps: PlayerState,
): Table[int, ColonyLimitSnapshot] =
  ## Build per-colony base metrics used by client-side limit checks.
  var neorias = initTable[NeoriaId, Neoria]()
  var kastras = initTable[KastraId, Kastra]()
  var groundUnits = initTable[GroundUnitId, GroundUnit]()

  for neoria in ps.ownNeorias:
    neorias[neoria.id] = neoria
  for kastra in ps.ownKastras:
    kastras[kastra.id] = kastra
  for unit in ps.ownGroundUnits:
    groundUnits[unit.id] = unit

  result = initTable[int, ColonyLimitSnapshot]()
  for colony in ps.ownColonies:
    var snapshot = ColonyLimitSnapshot(
      souls: int(colony.souls),
      industrialUnits: int(colony.industrial.units),
      fighters: colony.fighterIds.len,
      spaceports: 0,
      shipyards: 0,
      starbases: 0,
      shields: 0,
    )

    for neoriaId in colony.neoriaIds:
      if neoriaId notin neorias:
        continue
      if neorias[neoriaId].state in {CombatState.Crippled, CombatState.Destroyed}:
        continue
      case neorias[neoriaId].neoriaClass
      of NeoriaClass.Spaceport:
        snapshot.spaceports.inc
      of NeoriaClass.Shipyard:
        snapshot.shipyards.inc
      else:
        discard

    for kastraId in colony.kastraIds:
      if kastraId notin kastras:
        continue
      if kastras[kastraId].kastraClass == KastraClass.Starbase:
        snapshot.starbases.inc

    for unitId in colony.groundUnitIds:
      if unitId notin groundUnits:
        continue
      if groundUnits[unitId].stats.unitType == GroundClass.PlanetaryShield:
        snapshot.shields.inc

    result[int(colony.id)] = snapshot

proc validateJoinFleetFc*(
    model: TuiModel,
    sourceFleetId: int,
    targetFleetId: int,
): Option[string] =
  ## Validate FC ships-per-fleet limit for JoinFleet staging.
  var source = none(FleetInfo)
  var target = none(FleetInfo)
  for fleet in model.view.fleets:
    if fleet.id == sourceFleetId:
      source = some(fleet)
    elif fleet.id == targetFleetId:
      target = some(fleet)

  if source.isNone:
    return some("JoinFleet rejected: source fleet not found")
  if target.isNone:
    return some("JoinFleet rejected: target fleet not found")

  let maxShips = fcMaxShips(model.view.techLevels)
  let combined = source.get().shipCount + target.get().shipCount
  if combined > maxShips:
    return some(formatLimitError(
      "JoinFleet exceeds FC fleet-size limit",
      combined,
      maxShips,
    ))

  none(string)

proc validateStagedFleetLimits*(model: TuiModel): seq[string] =
  ## Validate staged fleet commands for applicable hard limits.
  for _, cmd in model.ui.stagedFleetCommands.pairs:
    if cmd.commandType == FleetCommandType.JoinFleet and
        cmd.targetFleet.isSome:
      let err = validateJoinFleetFc(
        model,
        int(cmd.fleetId),
        int(cmd.targetFleet.get()),
      )
      if err.isSome:
        result.add(err.get())
