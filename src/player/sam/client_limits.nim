## Client-side limit analysis and validation for Player TUI.
##
## Mirrors engine-side limit formulas where data is available in PlayerState.

import std/[options, tables, math]

import ./tui_model
import ../../engine/types/[core, player_state, ship, production, facilities,
  ground_unit, fleet, tech]
import ../../engine/globals

type
  StagedColonyLimits = object
    fighters: int
    spaceports: int
    starbases: int
    shields: int

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

proc stagedPpCost*(stagedBuildCommands: seq[BuildCommand]): int =
  ## Sum PP committed by staged build commands (client-side preview).
  for cmd in stagedBuildCommands:
    let qty = max(0, int(cmd.quantity))
    case cmd.buildType
    of BuildType.Ship:
      if cmd.shipClass.isSome:
        let shipClass = cmd.shipClass.get()
        let cost = int(gameConfig.ships.ships[shipClass].productionCost)
        result += cost * qty
    of BuildType.Facility:
      if cmd.facilityClass.isSome:
        let facilityClass = cmd.facilityClass.get()
        let cost =
          int(gameConfig.facilities.facilities[facilityClass].buildCost)
        result += cost * qty
    of BuildType.Ground:
      if cmd.groundClass.isSome:
        let groundClass = cmd.groundClass.get()
        let cost = int(gameConfig.groundUnits.units[groundClass].productionCost)
        result += cost * qty
    else:
      discard

proc stagedResearchPp*(allocation: ResearchAllocation): int =
  ## Sum staged PP allocated to research tracks.
  var total = allocation.economic + allocation.science
  for pp in allocation.technology.values:
    total += pp
  total.int

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
                         researchAllocation: ResearchAllocation,
                         stagedEbpInvestment, stagedCipInvestment: int32): int =
  ## Client-side treasury preview including staged build/research/espionage.
  max(
    0,
    baseTreasury -
      stagedPpCost(stagedBuildCommands) -
      stagedResearchPp(researchAllocation) -
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
      industrialUnits: int(colony.industrial.units),
      fighters: colony.fighterIds.len,
      spaceports: 0,
      starbases: 0,
      shields: 0,
    )

    for neoriaId in colony.neoriaIds:
      if neoriaId notin neorias:
        continue
      if neorias[neoriaId].neoriaClass == NeoriaClass.Spaceport:
        snapshot.spaceports.inc

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
