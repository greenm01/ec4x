## Apply PlayerState deltas to local PlayerState cache

import std/[options]
import kdl
import ../../common/logger
import ../../engine/types/[core, player_state, colony, fleet, ship, ground_unit,
  diplomacy, progression, capacity, production]
import ../../daemon/persistence/player_state_snapshot
import ./kdl_player_state

proc parseEnumFromStr[T: enum](value: string): Option[T] =
  let normalized = value.toLowerAscii().replace("-", "")
  for enumVal in T:
    if ($enumVal).toLowerAscii() == normalized:
      return some(enumVal)
  return none(T)

proc parseEnumPureFromStr[T: enum](value: string): Option[T] =
  let normalized = value.toLowerAscii().replace("-", "")
  for enumVal in T:
    let name = substr($enumVal, 1)
    if name.toLowerAscii() == normalized:
      return some(enumVal)
  return none(T)

proc parseIntVal(val: KdlVal): Option[int32] =
  try:
    return some(val.getInt().int32)
  except CatchableError:
    return none(int32)

proc parseFloatVal(val: KdlVal): Option[float32] =
  try:
    return some(val.getFloat().float32)
  except CatchableError:
    return none(float32)

proc parseBoolVal(val: KdlVal): Option[bool] =
  try:
    return some(val.getBool())
  except CatchableError:
    return none(bool)

proc parseHouseId(val: KdlVal): Option[HouseId] =
  try:
    return some(HouseId(val.getInt().uint32))
  except CatchableError:
    return none(HouseId)

proc parseSystemId(val: KdlVal): Option[SystemId] =
  try:
    return some(SystemId(val.getInt().uint32))
  except CatchableError:
    return none(SystemId)

proc parseColonyId(val: KdlVal): Option[ColonyId] =
  try:
    return some(ColonyId(val.getInt().uint32))
  except CatchableError:
    return none(ColonyId)

proc parseFleetId(val: KdlVal): Option[FleetId] =
  try:
    return some(FleetId(val.getInt().uint32))
  except CatchableError:
    return none(FleetId)

proc parseShipId(val: KdlVal): Option[ShipId] =
  try:
    return some(ShipId(val.getInt().uint32))
  except CatchableError:
    return none(ShipId)

proc parseGroundUnitId(val: KdlVal): Option[GroundUnitId] =
  try:
    return some(GroundUnitId(val.getInt().uint32))
  except CatchableError:
    return none(GroundUnitId)

proc parseConstructionProjectId(val: KdlVal): Option[ConstructionProjectId] =
  try:
    return some(ConstructionProjectId(val.getInt().uint32))
  except CatchableError:
    return none(ConstructionProjectId)

proc parseRepairProjectId(val: KdlVal): Option[RepairProjectId] =
  try:
    return some(RepairProjectId(val.getInt().uint32))
  except CatchableError:
    return none(RepairProjectId)

proc parseNeoriaId(val: KdlVal): Option[NeoriaId] =
  try:
    return some(NeoriaId(val.getInt().uint32))
  except CatchableError:
    return none(NeoriaId)

proc parseKastraId(val: KdlVal): Option[KastraId] =
  try:
    return some(KastraId(val.getInt().uint32))
  except CatchableError:
    return none(KastraId)

proc parseValSeq[T](val: KdlVal, parser: proc(item: KdlVal): Option[T]): seq[T] =
  result = @[]
  let parsed = parser(val)
  if parsed.isSome:
    result.add(parsed.get())

proc parseChildSeq[T](node: KdlNode, name: string,
  parser: proc(item: KdlVal): Option[T]): seq[T] =
  result = @[]
  let childOpt = nodeChild(node, name)
  if childOpt.isNone:
    return
  for arg in childOpt.get().args:
    let parsed = parser(arg)
    if parsed.isSome:
      result.add(parsed.get())

proc nodeChild(node: KdlNode, name: string): Option[KdlNode] =
  for child in node.children:
    if child.name == name:
      return some(child)
  none(KdlNode)

proc childVal(node: KdlNode, name: string): Option[KdlVal] =
  let childOpt = nodeChild(node, name)
  if childOpt.isNone:
    return none(KdlVal)
  if childOpt.get().args.len == 0:
    return none(KdlVal)
  some(childOpt.get().args[0])

proc removeFromSeqById[T, Id](
  items: var seq[T],
  id: Id,
  idFn: proc(item: T): Id
) =
  var idx = -1
  for i, item in items:
    if idFn(item) == id:
      idx = i
      break
  if idx >= 0:
    items.delete(idx)

proc upsertById[T, Id](
  items: var seq[T],
  item: T,
  idFn: proc(item: T): Id
) =
  for i, existing in items:
    if idFn(existing) == idFn(item):
      items[i] = item
      return
  items.add(item)

proc parseCapacityViolationProps(node: KdlNode): CapacityViolation =
  var violation = CapacityViolation()
  if node.props.hasKey("capacity-violation-type"):
    let typeOpt = parseEnumPureFromStr[CapacityType](
      node.props["capacity-violation-type"].getString())
    if typeOpt.isSome:
      violation.capacityType = typeOpt.get()
  if node.props.hasKey("capacity-violation-current"):
    let valOpt = parseIntVal(node.props["capacity-violation-current"])
    if valOpt.isSome:
      violation.current = valOpt.get()
  if node.props.hasKey("capacity-violation-maximum"):
    let valOpt = parseIntVal(node.props["capacity-violation-maximum"])
    if valOpt.isSome:
      violation.maximum = valOpt.get()
  if node.props.hasKey("capacity-violation-excess"):
    let valOpt = parseIntVal(node.props["capacity-violation-excess"])
    if valOpt.isSome:
      violation.excess = valOpt.get()
  if node.props.hasKey("capacity-violation-severity"):
    let enumOpt = parseEnumPureFromStr[ViolationSeverity](
      node.props["capacity-violation-severity"].getString())
    if enumOpt.isSome:
      violation.severity = enumOpt.get()
  if node.props.hasKey("capacity-violation-grace"):
    let valOpt = parseIntVal(node.props["capacity-violation-grace"])
    if valOpt.isSome:
      violation.graceTurnsRemaining = valOpt.get()
  if node.props.hasKey("capacity-violation-turn"):
    let valOpt = parseIntVal(node.props["capacity-violation-turn"])
    if valOpt.isSome:
      violation.violationTurn = valOpt.get()
  if node.props.hasKey("capacity-violation-colony"):
    let idOpt = parseColonyId(node.props["capacity-violation-colony"])
    if idOpt.isSome:
      violation.entity = EntityIdUnion(kind: CapacityType.FighterSquadron,
        colonyId: idOpt.get())
  elif node.props.hasKey("capacity-violation-house"):
    let idOpt = parseHouseId(node.props["capacity-violation-house"])
    if idOpt.isSome:
      violation.entity = EntityIdUnion(kind: CapacityType.CapitalSquadron,
        houseId: idOpt.get())
  elif node.props.hasKey("capacity-violation-ship"):
    let idOpt = parseShipId(node.props["capacity-violation-ship"])
    if idOpt.isSome:
      violation.entity = EntityIdUnion(kind: CapacityType.CarrierHangar,
        shipId: idOpt.get())
  elif node.props.hasKey("capacity-violation-fleet"):
    let idOpt = parseFleetId(node.props["capacity-violation-fleet"])
    if idOpt.isSome:
      violation.entity = EntityIdUnion(kind: CapacityType.FleetSize,
        fleetId: idOpt.get())
  violation

proc parseColonyFromEntry(entry: KdlNode): Colony =
  var colony = Colony()
  if entry.props.hasKey("id"):
    let idOpt = parseColonyId(entry.props["id"])
    if idOpt.isSome:
      colony.id = idOpt.get()
  if entry.props.hasKey("system"):
    let idOpt = parseSystemId(entry.props["system"])
    if idOpt.isSome:
      colony.systemId = idOpt.get()
  if entry.props.hasKey("owner"):
    let idOpt = parseHouseId(entry.props["owner"])
    if idOpt.isSome:
      colony.owner = idOpt.get()
  if entry.props.hasKey("population"):
    let valOpt = parseIntVal(entry.props["population"])
    if valOpt.isSome:
      colony.population = valOpt.get()
  if entry.props.hasKey("souls"):
    let valOpt = parseIntVal(entry.props["souls"])
    if valOpt.isSome:
      colony.souls = valOpt.get()
  if entry.props.hasKey("population-units"):
    let valOpt = parseIntVal(entry.props["population-units"])
    if valOpt.isSome:
      colony.populationUnits = valOpt.get()
  if entry.props.hasKey("population-transfer-units"):
    let valOpt = parseIntVal(entry.props["population-transfer-units"])
    if valOpt.isSome:
      colony.populationTransferUnits = valOpt.get()
  if entry.props.hasKey("infrastructure"):
    let valOpt = parseIntVal(entry.props["infrastructure"])
    if valOpt.isSome:
      colony.infrastructure = valOpt.get()
  if entry.props.hasKey("industrial-units"):
    let valOpt = parseIntVal(entry.props["industrial-units"])
    if valOpt.isSome:
      colony.industrial.units = valOpt.get()
  if entry.props.hasKey("industrial-investment"):
    let valOpt = parseIntVal(entry.props["industrial-investment"])
    if valOpt.isSome:
      colony.industrial.investmentCost = valOpt.get()
  if entry.props.hasKey("production"):
    let valOpt = parseIntVal(entry.props["production"])
    if valOpt.isSome:
      colony.production = valOpt.get()
  if entry.props.hasKey("gross-output"):
    let valOpt = parseIntVal(entry.props["gross-output"])
    if valOpt.isSome:
      colony.grossOutput = valOpt.get()
  if entry.props.hasKey("tax-rate"):
    let valOpt = parseIntVal(entry.props["tax-rate"])
    if valOpt.isSome:
      colony.taxRate = valOpt.get()
  if entry.props.hasKey("infrastructure-damage"):
    let valOpt = parseFloatVal(entry.props["infrastructure-damage"])
    if valOpt.isSome:
      colony.infrastructureDamage = valOpt.get()
  if entry.props.hasKey("under-construction"):
    let idOpt = parseConstructionProjectId(entry.props["under-construction"])
    if idOpt.isSome:
      colony.underConstruction = some(idOpt.get())
  colony.constructionQueue = parseChildSeq(entry, "construction-queue",
    parseConstructionProjectId)
  colony.repairQueue = parseChildSeq(entry, "repair-queue",
    parseRepairProjectId)
  if entry.props.hasKey("terraforming-start"):
    var terra = TerraformProject()
    let startOpt = parseIntVal(entry.props["terraforming-start"])
    if startOpt.isSome:
      terra.startTurn = startOpt.get()
    if entry.props.hasKey("terraforming-remaining"):
      let remOpt = parseIntVal(entry.props["terraforming-remaining"])
      if remOpt.isSome:
        terra.turnsRemaining = remOpt.get()
    if entry.props.hasKey("terraforming-class"):
      let classOpt = parseIntVal(entry.props["terraforming-class"])
      if classOpt.isSome:
        terra.targetClass = classOpt.get()
    if entry.props.hasKey("terraforming-cost"):
      let costOpt = parseIntVal(entry.props["terraforming-cost"])
      if costOpt.isSome:
        terra.ppCost = costOpt.get()
    if entry.props.hasKey("terraforming-paid"):
      let paidOpt = parseIntVal(entry.props["terraforming-paid"])
      if paidOpt.isSome:
        terra.ppPaid = paidOpt.get()
    colony.activeTerraforming = some(terra)
  colony.fighterIds = parseChildSeq(entry, "fighters", parseShipId)
  colony.groundUnitIds = parseChildSeq(entry, "ground-units", parseGroundUnitId)
  colony.neoriaIds = parseChildSeq(entry, "neorias", parseNeoriaId)
  colony.kastraIds = parseChildSeq(entry, "kastras", parseKastraId)
  if entry.props.hasKey("blockaded"):
    let valOpt = parseBoolVal(entry.props["blockaded"])
    if valOpt.isSome:
      colony.blockaded = valOpt.get()
  colony.blockadedBy = parseChildSeq(entry, "blockaded-by", parseHouseId)
  if entry.props.hasKey("blockade-turns"):
    let valOpt = parseIntVal(entry.props["blockade-turns"])
    if valOpt.isSome:
      colony.blockadeTurns = valOpt.get()
  if entry.props.hasKey("auto-repair"):
    let valOpt = parseBoolVal(entry.props["auto-repair"])
    if valOpt.isSome:
      colony.autoRepair = valOpt.get()
  if entry.props.hasKey("auto-load-marines"):
    let valOpt = parseBoolVal(entry.props["auto-load-marines"])
    if valOpt.isSome:
      colony.autoLoadMarines = valOpt.get()
  if entry.props.hasKey("auto-load-fighters"):
    let valOpt = parseBoolVal(entry.props["auto-load-fighters"])
    if valOpt.isSome:
      colony.autoLoadFighters = valOpt.get()
  if entry.props.hasKey("capacity-violation-type"):
    colony.capacityViolation = parseCapacityViolationProps(entry)
  colony

proc parseFleetFromEntry(entry: KdlNode): Fleet =
  var fleet = Fleet()
  if entry.props.hasKey("id"):
    let idOpt = parseFleetId(entry.props["id"])
    if idOpt.isSome:
      fleet.id = idOpt.get()
  if entry.props.hasKey("owner"):
    let idOpt = parseHouseId(entry.props["owner"])
    if idOpt.isSome:
      fleet.houseId = idOpt.get()
  if entry.props.hasKey("location"):
    let idOpt = parseSystemId(entry.props["location"])
    if idOpt.isSome:
      fleet.location = idOpt.get()
  if entry.props.hasKey("status"):
    let enumOpt = parseEnumPureFromStr[FleetStatus](
      entry.props["status"].getString())
    if enumOpt.isSome:
      fleet.status = enumOpt.get()
  if entry.props.hasKey("roe"):
    let valOpt = parseIntVal(entry.props["roe"])
    if valOpt.isSome:
      fleet.roe = valOpt.get()
  if entry.props.hasKey("mission-state"):
    let enumOpt = parseEnumPureFromStr[MissionState](
      entry.props["mission-state"].getString())
    if enumOpt.isSome:
      fleet.missionState = enumOpt.get()
  if entry.props.hasKey("mission-target"):
    let idOpt = parseSystemId(entry.props["mission-target"])
    if idOpt.isSome:
      fleet.missionTarget = some(idOpt.get())
  if entry.props.hasKey("mission-start-turn"):
    let valOpt = parseIntVal(entry.props["mission-start-turn"])
    if valOpt.isSome:
      fleet.missionStartTurn = valOpt.get()
  fleet.ships = parseChildSeq(entry, "ships", parseShipId)
  if entry.props.hasKey("command"):
    let cmdOpt = parseEnumPureFromStr[FleetCommandType](
      entry.props["command"].getString())
    if cmdOpt.isSome:
      fleet.command.commandType = cmdOpt.get()
  if entry.props.hasKey("command-target"):
    let idOpt = parseSystemId(entry.props["command-target"])
    if idOpt.isSome:
      fleet.command.targetSystem = some(idOpt.get())
  if entry.props.hasKey("command-target-fleet"):
    let idOpt = parseFleetId(entry.props["command-target-fleet"])
    if idOpt.isSome:
      fleet.command.targetFleet = some(idOpt.get())
  if entry.props.hasKey("command-priority"):
    let valOpt = parseIntVal(entry.props["command-priority"])
    if valOpt.isSome:
      fleet.command.priority = valOpt.get()
  if entry.props.hasKey("command-roe"):
    let valOpt = parseIntVal(entry.props["command-roe"])
    if valOpt.isSome:
      fleet.command.roe = some(valOpt.get())
  fleet.command.fleetId = fleet.id
  fleet

proc parseShipFromEntry(entry: KdlNode): Ship =
  var ship = Ship()
  if entry.props.hasKey("id"):
    let idOpt = parseShipId(entry.props["id"])
    if idOpt.isSome:
      ship.id = idOpt.get()
  if entry.props.hasKey("house"):
    let idOpt = parseHouseId(entry.props["house"])
    if idOpt.isSome:
      ship.houseId = idOpt.get()
  if entry.props.hasKey("fleet"):
    let idOpt = parseFleetId(entry.props["fleet"])
    if idOpt.isSome:
      ship.fleetId = idOpt.get()
  if entry.props.hasKey("class"):
    let enumOpt = parseEnumPureFromStr[ShipClass](
      entry.props["class"].getString())
    if enumOpt.isSome:
      ship.shipClass = enumOpt.get()
  if entry.props.hasKey("state"):
    let enumOpt = parseEnumPureFromStr[CombatState](
      entry.props["state"].getString())
    if enumOpt.isSome:
      ship.state = enumOpt.get()
  if entry.props.hasKey("attack"):
    let valOpt = parseIntVal(entry.props["attack"])
    if valOpt.isSome:
      ship.stats.attackStrength = valOpt.get()
  if entry.props.hasKey("defense"):
    let valOpt = parseIntVal(entry.props["defense"])
    if valOpt.isSome:
      ship.stats.defenseStrength = valOpt.get()
  if entry.props.hasKey("wep"):
    let valOpt = parseIntVal(entry.props["wep"])
    if valOpt.isSome:
      ship.stats.wep = valOpt.get()
  if entry.props.hasKey("cargo-type"):
    let enumOpt = parseEnumPureFromStr[CargoClass](
      entry.props["cargo-type"].getString())
    if enumOpt.isSome:
      ship.cargo = some(ShipCargo(cargoType: enumOpt.get()))
  if entry.props.hasKey("cargo-quantity"):
    if ship.cargo.isNone:
      ship.cargo = some(ShipCargo())
    var cargo = ship.cargo.get()
    let valOpt = parseIntVal(entry.props["cargo-quantity"])
    if valOpt.isSome:
      cargo.quantity = valOpt.get()
    ship.cargo = some(cargo)
  if entry.props.hasKey("cargo-capacity"):
    if ship.cargo.isNone:
      ship.cargo = some(ShipCargo())
    var cargo = ship.cargo.get()
    let valOpt = parseIntVal(entry.props["cargo-capacity"])
    if valOpt.isSome:
      cargo.capacity = valOpt.get()
    ship.cargo = some(cargo)
  if entry.props.hasKey("assigned-to"):
    let idOpt = parseShipId(entry.props["assigned-to"])
    if idOpt.isSome:
      ship.assignedToCarrier = some(idOpt.get())
  ship.embarkedFighters = parseChildSeq(entry, "embarked-fighters", parseShipId)
  ship

proc parseGroundUnitFromEntry(entry: KdlNode): GroundUnit =
  var unit = GroundUnit()
  if entry.props.hasKey("id"):
    let idOpt = parseGroundUnitId(entry.props["id"])
    if idOpt.isSome:
      unit.id = idOpt.get()
  if entry.props.hasKey("house"):
    let idOpt = parseHouseId(entry.props["house"])
    if idOpt.isSome:
      unit.houseId = idOpt.get()
  if entry.props.hasKey("type"):
    let enumOpt = parseEnumPureFromStr[GroundClass](
      entry.props["type"].getString())
    if enumOpt.isSome:
      unit.stats.unitType = enumOpt.get()
  if entry.props.hasKey("attack"):
    let valOpt = parseIntVal(entry.props["attack"])
    if valOpt.isSome:
      unit.stats.attackStrength = valOpt.get()
  if entry.props.hasKey("defense"):
    let valOpt = parseIntVal(entry.props["defense"])
    if valOpt.isSome:
      unit.stats.defenseStrength = valOpt.get()
  if entry.props.hasKey("state"):
    let enumOpt = parseEnumPureFromStr[CombatState](
      entry.props["state"].getString())
    if enumOpt.isSome:
      unit.state = enumOpt.get()
  if entry.props.hasKey("colony"):
    let idOpt = parseColonyId(entry.props["colony"])
    if idOpt.isSome:
      unit.garrison = GroundUnitGarrison(
        locationType: GroundUnitLocation.OnColony,
        colonyId: idOpt.get())
  elif entry.props.hasKey("transport"):
    let idOpt = parseShipId(entry.props["transport"])
    if idOpt.isSome:
      unit.garrison = GroundUnitGarrison(
        locationType: GroundUnitLocation.OnTransport,
        shipId: idOpt.get())
  unit

proc parseVisibleSystemFromEntry(entry: KdlNode): VisibleSystem =
  var system = VisibleSystem()
  if entry.props.hasKey("id"):
    let idOpt = parseSystemId(entry.props["id"])
    if idOpt.isSome:
      system.systemId = idOpt.get()
  if entry.props.hasKey("visibility"):
    let enumOpt = parseEnumPureFromStr[VisibilityLevel](
      entry.props["visibility"].getString())
    if enumOpt.isSome:
      system.visibility = enumOpt.get()
  if entry.props.hasKey("last-scouted"):
    let valOpt = parseIntVal(entry.props["last-scouted"])
    if valOpt.isSome:
      system.lastScoutedTurn = some(valOpt.get())
  if entry.props.hasKey("coord-q") and entry.props.hasKey("coord-r"):
    let qOpt = parseIntVal(entry.props["coord-q"])
    let rOpt = parseIntVal(entry.props["coord-r"])
    if qOpt.isSome and rOpt.isSome:
      system.coordinates = some((qOpt.get(), rOpt.get()))
  system.jumpLaneIds = parseChildSeq(entry, "lanes", parseSystemId)
  system

proc parseVisibleColonyFromEntry(entry: KdlNode): VisibleColony =
  var colony = VisibleColony()
  if entry.props.hasKey("id"):
    let idOpt = parseColonyId(entry.props["id"])
    if idOpt.isSome:
      colony.colonyId = idOpt.get()
  if entry.props.hasKey("system"):
    let idOpt = parseSystemId(entry.props["system"])
    if idOpt.isSome:
      colony.systemId = idOpt.get()
  if entry.props.hasKey("owner"):
    let idOpt = parseHouseId(entry.props["owner"])
    if idOpt.isSome:
      colony.owner = idOpt.get()
  if entry.props.hasKey("intel-turn"):
    let valOpt = parseIntVal(entry.props["intel-turn"])
    if valOpt.isSome:
      colony.intelTurn = some(valOpt.get())
  if entry.props.hasKey("estimated-population"):
    let valOpt = parseIntVal(entry.props["estimated-population"])
    if valOpt.isSome:
      colony.estimatedPopulation = some(valOpt.get())
  if entry.props.hasKey("estimated-industry"):
    let valOpt = parseIntVal(entry.props["estimated-industry"])
    if valOpt.isSome:
      colony.estimatedIndustry = some(valOpt.get())
  if entry.props.hasKey("estimated-defenses"):
    let valOpt = parseIntVal(entry.props["estimated-defenses"])
    if valOpt.isSome:
      colony.estimatedDefenses = some(valOpt.get())
  if entry.props.hasKey("starbase-level"):
    let valOpt = parseIntVal(entry.props["starbase-level"])
    if valOpt.isSome:
      colony.starbaseLevel = some(valOpt.get())
  if entry.props.hasKey("unassigned-squadrons"):
    let valOpt = parseIntVal(entry.props["unassigned-squadrons"])
    if valOpt.isSome:
      colony.unassignedSquadronCount = some(valOpt.get())
  if entry.props.hasKey("reserve-fleet-count"):
    let valOpt = parseIntVal(entry.props["reserve-fleet-count"])
    if valOpt.isSome:
      colony.reserveFleetCount = some(valOpt.get())
  if entry.props.hasKey("mothballed-fleet-count"):
    let valOpt = parseIntVal(entry.props["mothballed-fleet-count"])
    if valOpt.isSome:
      colony.mothballedFleetCount = some(valOpt.get())
  if entry.props.hasKey("shipyard-count"):
    let valOpt = parseIntVal(entry.props["shipyard-count"])
    if valOpt.isSome:
      colony.shipyardCount = some(valOpt.get())
  colony

proc parseVisibleFleetFromEntry(entry: KdlNode): VisibleFleet =
  var fleet = VisibleFleet()
  if entry.props.hasKey("id"):
    let idOpt = parseFleetId(entry.props["id"])
    if idOpt.isSome:
      fleet.fleetId = idOpt.get()
  if entry.props.hasKey("owner"):
    let idOpt = parseHouseId(entry.props["owner"])
    if idOpt.isSome:
      fleet.owner = idOpt.get()
  if entry.props.hasKey("location"):
    let idOpt = parseSystemId(entry.props["location"])
    if idOpt.isSome:
      fleet.location = idOpt.get()
  if entry.props.hasKey("detected-turn"):
    let valOpt = parseIntVal(entry.props["detected-turn"])
    if valOpt.isSome:
      fleet.intelTurn = some(valOpt.get())
  if entry.props.hasKey("estimated-ships"):
    let valOpt = parseIntVal(entry.props["estimated-ships"])
    if valOpt.isSome:
      fleet.estimatedShipCount = some(valOpt.get())
  if entry.props.hasKey("detected-system"):
    let idOpt = parseSystemId(entry.props["detected-system"])
    if idOpt.isSome:
      fleet.detectedInSystem = some(idOpt.get())
  fleet

proc applyEntityDelta[T, Id](
  parent: KdlNode,
  section: string,
  items: var seq[T],
  idFn: proc(item: T): Id,
  idParser: proc(val: KdlVal): Option[Id],
  parseFn: proc(entry: KdlNode): T
) =
  for child in parent.children:
    if child.name != section:
      continue
    for entry in child.children:
      if entry.name notin @["added", "updated", "removed"]:
        continue

      if entry.name == "removed":
        if not entry.props.hasKey("id"):
          continue
        let idOpt = idParser(entry.props["id"])
        if idOpt.isNone:
          continue
        removeFromSeqById(items, idOpt.get(), idFn)
        continue

      let parsed = parseFn(entry)
      upsertById(items, parsed, idFn)

proc parseHouseIdProp(node: KdlNode, key: string): Option[HouseId] =
  if not node.props.hasKey(key):
    return none(HouseId)
  parseHouseId(node.props[key])

proc applyHouseValueDelta(
  parent: KdlNode,
  section: string,
  target: var Table[HouseId, int32]
) =
  for child in parent.children:
    if child.name != section:
      continue
    for entry in child.children:
      if entry.name == "removed":
        let idOpt = parseHouseIdProp(entry, "house")
        if idOpt.isSome:
          target.del(idOpt.get())
        continue

      if entry.props.hasKey("house") and entry.props.hasKey("value"):
        let idOpt = parseHouseId(entry.props["house"])
        let valueOpt = parseIntVal(entry.props["value"])
        if idOpt.isSome and valueOpt.isSome:
          target[idOpt.get()] = valueOpt.get()

proc applyHouseCountDelta(
  parent: KdlNode,
  section: string,
  target: var Table[HouseId, int32]
) =
  for child in parent.children:
    if child.name != section:
      continue
    for entry in child.children:
      if entry.name == "removed":
        let idOpt = parseHouseIdProp(entry, "house")
        if idOpt.isSome:
          target.del(idOpt.get())
        continue

      if entry.props.hasKey("house") and entry.props.hasKey("count"):
        let idOpt = parseHouseId(entry.props["house"])
        let valueOpt = parseIntVal(entry.props["count"])
        if idOpt.isSome and valueOpt.isSome:
          target[idOpt.get()] = valueOpt.get()

proc applyRelationsDelta(
  parent: KdlNode,
  section: string,
  target: var Table[(HouseId, HouseId), DiplomaticState]
) =
  for child in parent.children:
    if child.name != section:
      continue
    for entry in child.children:
      if entry.name == "removed":
        if entry.props.hasKey("from") and entry.props.hasKey("to"):
          let srcOpt = parseHouseId(entry.props["from"])
          let tgtOpt = parseHouseId(entry.props["to"])
          if srcOpt.isSome and tgtOpt.isSome:
            target.del((srcOpt.get(), tgtOpt.get()))
        continue

      if entry.props.hasKey("from") and entry.props.hasKey("to") and
          entry.props.hasKey("state"):
        let srcOpt = parseHouseId(entry.props["from"])
        let tgtOpt = parseHouseId(entry.props["to"])
        let stateOpt = parseEnumPureFromStr[DiplomaticState](
          entry.props["state"].getString())
        if srcOpt.isSome and tgtOpt.isSome and stateOpt.isSome:
          target[(srcOpt.get(), tgtOpt.get())] = stateOpt.get()

proc applyEliminatedDelta(
  parent: KdlNode,
  section: string,
  target: var seq[HouseId]
) =
  for child in parent.children:
    if child.name != section:
      continue
    for entry in child.children:
      if entry.name == "removed":
        if entry.props.hasKey("house"):
          let idOpt = parseHouseId(entry.props["house"])
          if idOpt.isSome:
            removeFromSeqById(target, idOpt.get(), proc(v: HouseId): HouseId = v)
        continue

      if entry.props.hasKey("house"):
        let idOpt = parseHouseId(entry.props["house"])
        if idOpt.isSome:
          upsertById(target, idOpt.get(), proc(v: HouseId): HouseId = v)

proc applyActProgressionDelta(parent: KdlNode, state: var PlayerState) =
  for child in parent.children:
    if child.name != "act-progression":
      continue
    var progression = ActProgressionState()
    if child.props.hasKey("current-act"):
      let enumOpt = parseEnumPureFromStr[GameAct](
        child.props["current-act"].getString())
      if enumOpt.isSome:
        progression.currentAct = enumOpt.get()
    if child.props.hasKey("act-start-turn"):
      let valOpt = parseIntVal(child.props["act-start-turn"])
      if valOpt.isSome:
        progression.actStartTurn = valOpt.get()
    if child.props.hasKey("colonization-percent"):
      let valOpt = parseFloatVal(child.props["colonization-percent"])
      if valOpt.isSome:
        progression.lastColonizationPercent = valOpt.get()
    if child.props.hasKey("total-prestige"):
      let valOpt = parseIntVal(child.props["total-prestige"])
      if valOpt.isSome:
        progression.lastTotalPrestige = valOpt.get()
    let topHousesOpt = nodeChild(child, "act2-top-houses")
    if topHousesOpt.isSome:
      for value in topHousesOpt.get().args:
        let idOpt = parseHouseId(value)
        if idOpt.isSome:
          progression.act2TopThreeHouses.add(idOpt.get())
    let topPrestigeOpt = nodeChild(child, "act2-top-prestige")
    if topPrestigeOpt.isSome:
      for value in topPrestigeOpt.get().args:
        let valOpt = parseIntVal(value)
        if valOpt.isSome:
          progression.act2TopThreePrestige.add(valOpt.get().int)
    state.actProgression = progression

proc applyVisibleSystemsDelta(
  parent: KdlNode,
  state: var PlayerState
) =
  for child in parent.children:
    if child.name != "visible-systems":
      continue
    for entry in child.children:
      if entry.name == "removed":
        if entry.props.hasKey("id"):
          let idOpt = parseSystemId(entry.props["id"])
          if idOpt.isSome:
            state.visibleSystems.del(idOpt.get())
        continue

      let parsed = parseVisibleSystemFromEntry(entry)
      state.visibleSystems[parsed.systemId] = parsed

proc applyDeltaToPlayerState*(
  state: var PlayerState,
  deltaKdl: string
): Option[int32] =
  ## Apply delta KDL to local PlayerState
  try:
    let doc = parseKdl(deltaKdl)
    if doc.len == 0 or doc[0].name != "delta":
      return none(int32)

    let root = doc[0]
    if root.props.hasKey("turn"):
      try:
        state.turn = root.props["turn"].getInt().int32
      except CatchableError:
        discard

    applyEntityDelta(root, "colonies", state.ownColonies,
      proc(item: Colony): ColonyId = item.id,
      parseColonyId,
      parseColonyFromEntry
    )

    applyEntityDelta(root, "fleets", state.ownFleets,
      proc(item: Fleet): FleetId = item.id,
      parseFleetId,
      parseFleetFromEntry
    )

    applyEntityDelta(root, "ships", state.ownShips,
      proc(item: Ship): ShipId = item.id,
      parseShipId,
      parseShipFromEntry
    )

    applyEntityDelta(root, "ground-units", state.ownGroundUnits,
      proc(item: GroundUnit): GroundUnitId = item.id,
      parseGroundUnitId,
      parseGroundUnitFromEntry
    )

    applyVisibleSystemsDelta(root, state)

    applyEntityDelta(root, "visible-colonies", state.visibleColonies,
      proc(item: VisibleColony): ColonyId = item.colonyId,
      parseColonyId,
      parseVisibleColonyFromEntry
    )

    applyEntityDelta(root, "visible-fleets", state.visibleFleets,
      proc(item: VisibleFleet): FleetId = item.fleetId,
      parseFleetId,
      parseVisibleFleetFromEntry
    )

    applyHouseValueDelta(root, "house-prestige", state.housePrestige)
    applyHouseCountDelta(root, "house-colony-counts", state.houseColonyCounts)
    applyRelationsDelta(root, "diplomacy", state.diplomaticRelations)
    applyEliminatedDelta(root, "eliminated-houses", state.eliminatedHouses)
    applyActProgressionDelta(root, state)

    return some(state.turn)
  except CatchableError as e:
    logError("Delta", "Failed to apply delta: ", e.msg)
    return none(int32)

proc applyFullStateKdl*(kdlState: string): Option[PlayerState] =
  ## Parse full-state KDL into PlayerState
  parsePlayerStateKdl(kdlState)
