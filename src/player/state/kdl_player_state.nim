## PlayerState KDL parsing helpers for 30405

import std/[options, tables, strutils]
import kdl
import ../../common/logger
import ../../engine/types/[core, player_state, colony, fleet, ship, ground_unit,
  diplomacy, progression, production, capacity, combat]

proc parseEnumPureFromStr[T: enum](value: string): Option[T] =
  let normalized = value.toLowerAscii().replace("-", "")
  for enumVal in T:
    let name = substr($enumVal, 1)
    if name.toLowerAscii() == normalized:
      return some(enumVal)
  return none(T)

proc parseBoolVal(val: KdlVal): Option[bool] =
  try:
    return some(val.getBool())
  except CatchableError:
    return none(bool)

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

proc parseCapacityViolation(node: KdlNode): Option[CapacityViolation] =
  if node.name != "capacity-violation":
    return none(CapacityViolation)
  var violation = CapacityViolation()
  if node.props.hasKey("type"):
    let typeOpt = parseEnumPureFromStr[CapacityType](
      node.props["type"].getString())
    if typeOpt.isSome:
      violation.capacityType = typeOpt.get()
  if node.props.hasKey("current"):
    let currentOpt = parseIntVal(node.props["current"])
    if currentOpt.isSome:
      violation.current = currentOpt.get()
  if node.props.hasKey("maximum"):
    let maxOpt = parseIntVal(node.props["maximum"])
    if maxOpt.isSome:
      violation.maximum = maxOpt.get()
  if node.props.hasKey("excess"):
    let excessOpt = parseIntVal(node.props["excess"])
    if excessOpt.isSome:
      violation.excess = excessOpt.get()
  if node.props.hasKey("severity"):
    let severityOpt = parseEnumPureFromStr[ViolationSeverity](
      node.props["severity"].getString())
    if severityOpt.isSome:
      violation.severity = severityOpt.get()
  if node.props.hasKey("grace-turns"):
    let graceOpt = parseIntVal(node.props["grace-turns"])
    if graceOpt.isSome:
      violation.graceTurnsRemaining = graceOpt.get()
  if node.props.hasKey("violation-turn"):
    let turnOpt = parseIntVal(node.props["violation-turn"])
    if turnOpt.isSome:
      violation.violationTurn = turnOpt.get()
  if node.props.hasKey("colony"):
    let idOpt = parseColonyId(node.props["colony"])
    if idOpt.isSome:
      violation.entity = EntityIdUnion(kind: CapacityType.FighterSquadron,
        colonyId: idOpt.get())
  elif node.props.hasKey("house"):
    let idOpt = parseHouseId(node.props["house"])
    if idOpt.isSome:
      violation.entity = EntityIdUnion(kind: CapacityType.CapitalSquadron,
        houseId: idOpt.get())
  elif node.props.hasKey("ship"):
    let idOpt = parseShipId(node.props["ship"])
    if idOpt.isSome:
      violation.entity = EntityIdUnion(kind: CapacityType.CarrierHangar,
        shipId: idOpt.get())
  elif node.props.hasKey("fleet"):
    let idOpt = parseFleetId(node.props["fleet"])
    if idOpt.isSome:
      violation.entity = EntityIdUnion(kind: CapacityType.FleetSize,
        fleetId: idOpt.get())
  some(violation)

proc parseVisibleSystems(node: KdlNode): Table[SystemId, VisibleSystem] =
  result = initTable[SystemId, VisibleSystem]()
  for child in node.children:
    if child.name != "system":
      continue
    var system = VisibleSystem()
    if child.props.hasKey("id"):
      let idOpt = parseSystemId(child.props["id"])
      if idOpt.isSome:
        system.systemId = idOpt.get()
    let visibilityOpt = childVal(child, "visibility")
    if visibilityOpt.isSome:
      let parsedOpt = parseEnumPureFromStr[VisibilityLevel](
        visibilityOpt.get().getString())
      if parsedOpt.isSome:
        system.visibility = parsedOpt.get()

    let lastScoutedOpt = childVal(child, "last-scouted")
    if lastScoutedOpt.isSome:
      let valueOpt = parseIntVal(lastScoutedOpt.get())
      if valueOpt.isSome:
        system.lastScoutedTurn = some(valueOpt.get())
    let coordsNodeOpt = nodeChild(child, "coords")
    if coordsNodeOpt.isSome:
      let coordsNode = coordsNodeOpt.get()
      if coordsNode.props.hasKey("q") and coordsNode.props.hasKey("r"):
        let qOpt = parseIntVal(coordsNode.props["q"])
        let rOpt = parseIntVal(coordsNode.props["r"])
        if qOpt.isSome and rOpt.isSome:
          system.coordinates = some((qOpt.get(), rOpt.get()))
    let lanesNodeOpt = nodeChild(child, "lanes")
    if lanesNodeOpt.isSome:
      for laneVal in lanesNodeOpt.get().args:
        let laneOpt = parseSystemId(laneVal)
        if laneOpt.isSome:
          system.jumpLaneIds.add(laneOpt.get())
    result[system.systemId] = system

proc parseVisibleColonies(node: KdlNode): seq[VisibleColony] =
  result = @[]
  for child in node.children:
    if child.name != "colony":
      continue
    var colony = VisibleColony()
    if child.props.hasKey("id"):
      let idOpt = parseColonyId(child.props["id"])
      if idOpt.isSome:
        colony.colonyId = idOpt.get()
    if child.props.hasKey("system"):
      let sysOpt = parseSystemId(child.props["system"])
      if sysOpt.isSome:
        colony.systemId = sysOpt.get()
    if child.props.hasKey("owner"):
      let ownerOpt = parseHouseId(child.props["owner"])
      if ownerOpt.isSome:
        colony.owner = ownerOpt.get()
    let intelOpt = childVal(child, "intel-turn")
    if intelOpt.isSome:
      let valueOpt = parseIntVal(intelOpt.get())
      if valueOpt.isSome:
        colony.intelTurn = some(valueOpt.get())
    let popOpt = childVal(child, "estimated-population")
    if popOpt.isSome:
      let valueOpt = parseIntVal(popOpt.get())
      if valueOpt.isSome:
        colony.estimatedPopulation = some(valueOpt.get())
    let indOpt = childVal(child, "estimated-industry")
    if indOpt.isSome:
      let valueOpt = parseIntVal(indOpt.get())
      if valueOpt.isSome:
        colony.estimatedIndustry = some(valueOpt.get())
    let defOpt = childVal(child, "estimated-defenses")
    if defOpt.isSome:
      let valueOpt = parseIntVal(defOpt.get())
      if valueOpt.isSome:
        colony.estimatedDefenses = some(valueOpt.get())
    let starOpt = childVal(child, "starbase-level")
    if starOpt.isSome:
      let valueOpt = parseIntVal(starOpt.get())
      if valueOpt.isSome:
        colony.starbaseLevel = some(valueOpt.get())
    let unassignedOpt = childVal(child, "unassigned-squadrons")
    if unassignedOpt.isSome:
      let valueOpt = parseIntVal(unassignedOpt.get())
      if valueOpt.isSome:
        colony.unassignedSquadronCount = some(valueOpt.get())
    let reserveOpt = childVal(child, "reserve-fleet-count")
    if reserveOpt.isSome:
      let valueOpt = parseIntVal(reserveOpt.get())
      if valueOpt.isSome:
        colony.reserveFleetCount = some(valueOpt.get())
    let mothballedOpt = childVal(child, "mothballed-fleet-count")
    if mothballedOpt.isSome:
      let valueOpt = parseIntVal(mothballedOpt.get())
      if valueOpt.isSome:
        colony.mothballedFleetCount = some(valueOpt.get())
    let shipyardOpt = childVal(child, "shipyard-count")
    if shipyardOpt.isSome:
      let valueOpt = parseIntVal(shipyardOpt.get())
      if valueOpt.isSome:
        colony.shipyardCount = some(valueOpt.get())
    result.add(colony)

proc parseVisibleFleets(node: KdlNode): seq[VisibleFleet] =
  result = @[]
  for child in node.children:
    if child.name != "fleet":
      continue
    var fleet = VisibleFleet()
    if child.props.hasKey("id"):
      let idOpt = parseFleetId(child.props["id"])
      if idOpt.isSome:
        fleet.fleetId = idOpt.get()
    if child.props.hasKey("owner"):
      let ownerOpt = parseHouseId(child.props["owner"])
      if ownerOpt.isSome:
        fleet.owner = ownerOpt.get()
    let locOpt = childVal(child, "location")
    if locOpt.isSome:
      let idOpt = parseSystemId(locOpt.get())
      if idOpt.isSome:
        fleet.location = idOpt.get()
    let intelOpt = childVal(child, "detected-turn")
    if intelOpt.isSome:
      let valueOpt = parseIntVal(intelOpt.get())
      if valueOpt.isSome:
        fleet.intelTurn = some(valueOpt.get())
    let shipCountOpt = childVal(child, "estimated-ships")
    if shipCountOpt.isSome:
      let valueOpt = parseIntVal(shipCountOpt.get())
      if valueOpt.isSome:
        fleet.estimatedShipCount = some(valueOpt.get())
    let detectedOpt = childVal(child, "detected-system")
    if detectedOpt.isSome:
      let idOpt = parseSystemId(detectedOpt.get())
      if idOpt.isSome:
        fleet.detectedInSystem = some(idOpt.get())
    result.add(fleet)

proc parseHousePrestige(node: KdlNode): Table[HouseId, int32] =
  result = initTable[HouseId, int32]()
  for child in node.children:
    if child.name != "house":
      continue
    if child.props.hasKey("id") and child.props.hasKey("value"):
      let idOpt = parseHouseId(child.props["id"])
      let valueOpt = parseIntVal(child.props["value"])
      if idOpt.isSome and valueOpt.isSome:
        result[idOpt.get()] = valueOpt.get()

proc parseHouseCounts(node: KdlNode): Table[HouseId, int32] =
  result = initTable[HouseId, int32]()
  for child in node.children:
    if child.name != "house":
      continue
    if child.props.hasKey("id") and child.props.hasKey("count"):
      let idOpt = parseHouseId(child.props["id"])
      let valueOpt = parseIntVal(child.props["count"])
      if idOpt.isSome and valueOpt.isSome:
        result[idOpt.get()] = valueOpt.get()

proc parseDiplomacy(node: KdlNode): Table[(HouseId, HouseId), DiplomaticState] =
  result = initTable[(HouseId, HouseId), DiplomaticState]()
  for child in node.children:
    if child.name != "relation":
      continue
    if child.props.hasKey("from") and child.props.hasKey("to") and
        child.props.hasKey("state"):
      let sourceOpt = parseHouseId(child.props["from"])
      let targetOpt = parseHouseId(child.props["to"])
      let stateOpt = parseEnumPureFromStr[DiplomaticState](
        child.props["state"].getString())
      if sourceOpt.isSome and targetOpt.isSome and stateOpt.isSome:
        result[(sourceOpt.get(), targetOpt.get())] = stateOpt.get()

proc parseEliminated(node: KdlNode): seq[HouseId] =
  result = @[]
  for child in node.children:
    if child.name != "house":
      continue
    if child.props.hasKey("id"):
      let idOpt = parseHouseId(child.props["id"])
      if idOpt.isSome:
        result.add(idOpt.get())

proc parseActProgression(node: KdlNode): Option[ActProgressionState] =
  var progression = ActProgressionState()
  let actOpt = childVal(node, "current-act")
  if actOpt.isSome:
    let parsedOpt = parseEnumPureFromStr[GameAct](actOpt.get().getString())
    if parsedOpt.isSome:
      progression.currentAct = parsedOpt.get()
  let startOpt = childVal(node, "act-start-turn")
  if startOpt.isSome:
    let valueOpt = parseIntVal(startOpt.get())
    if valueOpt.isSome:
      progression.actStartTurn = valueOpt.get()
  let colonizationOpt = childVal(node, "colonization-percent")
  if colonizationOpt.isSome:
    let valueOpt = parseFloatVal(colonizationOpt.get())
    if valueOpt.isSome:
      progression.lastColonizationPercent = valueOpt.get()
  let prestigeOpt = childVal(node, "total-prestige")
  if prestigeOpt.isSome:
    let valueOpt = parseIntVal(prestigeOpt.get())
    if valueOpt.isSome:
      progression.lastTotalPrestige = valueOpt.get()
  let topHousesOpt = nodeChild(node, "act2-top-houses")
  if topHousesOpt.isSome:
    for value in topHousesOpt.get().args:
      let idOpt = parseHouseId(value)
      if idOpt.isSome:
        progression.act2TopThreeHouses.add(idOpt.get())
  let topPrestigeOpt = nodeChild(node, "act2-top-prestige")
  if topPrestigeOpt.isSome:
    for value in topPrestigeOpt.get().args:
      let valOpt = parseIntVal(value)
      if valOpt.isSome:
        progression.act2TopThreePrestige.add(valOpt.get().int)
  some(progression)

proc parsePublicSection(node: KdlNode, state: var PlayerState) =
  for child in node.children:
    case child.name
    of "prestige":
      state.housePrestige = parseHousePrestige(child)
    of "colony-counts":
      state.houseColonyCounts = parseHouseCounts(child)
    of "diplomacy":
      state.diplomaticRelations = parseDiplomacy(child)
    of "eliminated-houses":
      state.eliminatedHouses = parseEliminated(child)
    of "act-progression":
      let progressionOpt = parseActProgression(child)
      if progressionOpt.isSome:
        state.actProgression = progressionOpt.get()
    else:
      discard

proc parseOwnedColonies(node: KdlNode): seq[Colony] =
  result = @[]
  for child in node.children:
    if child.name != "colony":
      continue
    var colony = Colony()
    if child.props.hasKey("id"):
      let idOpt = parseColonyId(child.props["id"])
      if idOpt.isSome:
        colony.id = idOpt.get()
    if child.props.hasKey("system"):
      let sysOpt = parseSystemId(child.props["system"])
      if sysOpt.isSome:
        colony.systemId = sysOpt.get()
    if child.props.hasKey("owner"):
      let ownerOpt = parseHouseId(child.props["owner"])
      if ownerOpt.isSome:
        colony.owner = ownerOpt.get()
    let populationOpt = childVal(child, "population")
    if populationOpt.isSome:
      let valueOpt = parseIntVal(populationOpt.get())
      if valueOpt.isSome:
        colony.population = valueOpt.get()
    let soulsOpt = childVal(child, "souls")
    if soulsOpt.isSome:
      let valueOpt = parseIntVal(soulsOpt.get())
      if valueOpt.isSome:
        colony.souls = valueOpt.get()
    let popUnitsOpt = childVal(child, "population-units")
    if popUnitsOpt.isSome:
      let valueOpt = parseIntVal(popUnitsOpt.get())
      if valueOpt.isSome:
        colony.populationUnits = valueOpt.get()
    let ptuOpt = childVal(child, "population-transfer-units")
    if ptuOpt.isSome:
      let valueOpt = parseIntVal(ptuOpt.get())
      if valueOpt.isSome:
        colony.populationTransferUnits = valueOpt.get()
    let infraOpt = childVal(child, "infrastructure")
    if infraOpt.isSome:
      let valueOpt = parseIntVal(infraOpt.get())
      if valueOpt.isSome:
        colony.infrastructure = valueOpt.get()
    let unitsOpt = childVal(child, "industrial-units")
    if unitsOpt.isSome:
      let valueOpt = parseIntVal(unitsOpt.get())
      if valueOpt.isSome:
        colony.industrial.units = valueOpt.get()
    let investOpt = childVal(child, "industrial-investment")
    if investOpt.isSome:
      let valueOpt = parseIntVal(investOpt.get())
      if valueOpt.isSome:
        colony.industrial.investmentCost = valueOpt.get()
    let productionOpt = childVal(child, "production")
    if productionOpt.isSome:
      let valueOpt = parseIntVal(productionOpt.get())
      if valueOpt.isSome:
        colony.production = valueOpt.get()
    let grossOpt = childVal(child, "gross-output")
    if grossOpt.isSome:
      let valueOpt = parseIntVal(grossOpt.get())
      if valueOpt.isSome:
        colony.grossOutput = valueOpt.get()
    let taxOpt = childVal(child, "tax-rate")
    if taxOpt.isSome:
      let valueOpt = parseIntVal(taxOpt.get())
      if valueOpt.isSome:
        colony.taxRate = valueOpt.get()
    let infraDamageOpt = childVal(child, "infrastructure-damage")
    if infraDamageOpt.isSome:
      let valueOpt = parseFloatVal(infraDamageOpt.get())
      if valueOpt.isSome:
        colony.infrastructureDamage = valueOpt.get()
    let underConstructionOpt = childVal(child, "under-construction")
    if underConstructionOpt.isSome:
      let idOpt = parseConstructionProjectId(underConstructionOpt.get())
      if idOpt.isSome:
        colony.underConstruction = some(idOpt.get())
    let queueNodeOpt = nodeChild(child, "construction-queue")
    if queueNodeOpt.isSome:
      for value in queueNodeOpt.get().args:
        let idOpt = parseConstructionProjectId(value)
        if idOpt.isSome:
          colony.constructionQueue.add(idOpt.get())
    let repairNodeOpt = nodeChild(child, "repair-queue")
    if repairNodeOpt.isSome:
      for value in repairNodeOpt.get().args:
        let idOpt = parseRepairProjectId(value)
        if idOpt.isSome:
          colony.repairQueue.add(idOpt.get())
    let terraOpt = nodeChild(child, "terraforming")
    if terraOpt.isSome:
      let terraNode = terraOpt.get()
      var terra = TerraformProject()
      if terraNode.props.hasKey("start-turn"):
        let valueOpt = parseIntVal(terraNode.props["start-turn"])
        if valueOpt.isSome:
          terra.startTurn = valueOpt.get()
      if terraNode.props.hasKey("turns-remaining"):
        let valueOpt = parseIntVal(terraNode.props["turns-remaining"])
        if valueOpt.isSome:
          terra.turnsRemaining = valueOpt.get()
      if terraNode.props.hasKey("target-class"):
        let valueOpt = parseIntVal(terraNode.props["target-class"])
        if valueOpt.isSome:
          terra.targetClass = valueOpt.get()
      if terraNode.props.hasKey("pp-cost"):
        let valueOpt = parseIntVal(terraNode.props["pp-cost"])
        if valueOpt.isSome:
          terra.ppCost = valueOpt.get()
      if terraNode.props.hasKey("pp-paid"):
        let valueOpt = parseIntVal(terraNode.props["pp-paid"])
        if valueOpt.isSome:
          terra.ppPaid = valueOpt.get()
      colony.activeTerraforming = some(terra)
    let fightersNodeOpt = nodeChild(child, "fighters")
    if fightersNodeOpt.isSome:
      for value in fightersNodeOpt.get().args:
        let idOpt = parseShipId(value)
        if idOpt.isSome:
          colony.fighterIds.add(idOpt.get())
    let unitsNodeOpt = nodeChild(child, "ground-units")
    if unitsNodeOpt.isSome:
      for value in unitsNodeOpt.get().args:
        let idOpt = parseGroundUnitId(value)
        if idOpt.isSome:
          colony.groundUnitIds.add(idOpt.get())
    let neoriaNodeOpt = nodeChild(child, "neorias")
    if neoriaNodeOpt.isSome:
      for value in neoriaNodeOpt.get().args:
        let idOpt = parseNeoriaId(value)
        if idOpt.isSome:
          colony.neoriaIds.add(idOpt.get())
    let kastraNodeOpt = nodeChild(child, "kastras")
    if kastraNodeOpt.isSome:
      for value in kastraNodeOpt.get().args:
        let idOpt = parseKastraId(value)
        if idOpt.isSome:
          colony.kastraIds.add(idOpt.get())
    let blockadedOpt = childVal(child, "blockaded")
    if blockadedOpt.isSome:
      let valueOpt = parseBoolVal(blockadedOpt.get())
      if valueOpt.isSome:
        colony.blockaded = valueOpt.get()
    let blockadedByOpt = nodeChild(child, "blockaded-by")
    if blockadedByOpt.isSome:
      for value in blockadedByOpt.get().args:
        let idOpt = parseHouseId(value)
        if idOpt.isSome:
          colony.blockadedBy.add(idOpt.get())
    let blockadedTurnsOpt = childVal(child, "blockade-turns")
    if blockadedTurnsOpt.isSome:
      let valueOpt = parseIntVal(blockadedTurnsOpt.get())
      if valueOpt.isSome:
        colony.blockadeTurns = valueOpt.get()
    let autoRepairOpt = childVal(child, "auto-repair")
    if autoRepairOpt.isSome:
      let valueOpt = parseBoolVal(autoRepairOpt.get())
      if valueOpt.isSome:
        colony.autoRepair = valueOpt.get()
    let autoMarinesOpt = childVal(child, "auto-load-marines")
    if autoMarinesOpt.isSome:
      let valueOpt = parseBoolVal(autoMarinesOpt.get())
      if valueOpt.isSome:
        colony.autoLoadMarines = valueOpt.get()
    let autoFightersOpt = childVal(child, "auto-load-fighters")
    if autoFightersOpt.isSome:
      let valueOpt = parseBoolVal(autoFightersOpt.get())
      if valueOpt.isSome:
        colony.autoLoadFighters = valueOpt.get()
    let capacityNodeOpt = nodeChild(child, "capacity-violation")
    if capacityNodeOpt.isSome:
      let capacityOpt = parseCapacityViolation(capacityNodeOpt.get())
      if capacityOpt.isSome:
        colony.capacityViolation = capacityOpt.get()
    else:
      if child.props.hasKey("capacity-violation-type"):
        var violation = CapacityViolation()
        let typeOpt = parseEnumPureFromStr[CapacityType](
          child.props["capacity-violation-type"].getString())
        if typeOpt.isSome:
          violation.capacityType = typeOpt.get()
        if child.props.hasKey("capacity-violation-current"):
          let valOpt = parseIntVal(child.props["capacity-violation-current"])
          if valOpt.isSome:
            violation.current = valOpt.get()
        if child.props.hasKey("capacity-violation-maximum"):
          let valOpt = parseIntVal(child.props["capacity-violation-maximum"])
          if valOpt.isSome:
            violation.maximum = valOpt.get()
        if child.props.hasKey("capacity-violation-excess"):
          let valOpt = parseIntVal(child.props["capacity-violation-excess"])
          if valOpt.isSome:
            violation.excess = valOpt.get()
        if child.props.hasKey("capacity-violation-severity"):
          let parsedOpt = parseEnumPureFromStr[ViolationSeverity](
            child.props["capacity-violation-severity"].getString())
          if parsedOpt.isSome:
            violation.severity = parsedOpt.get()
        if child.props.hasKey("capacity-violation-grace"):
          let valOpt = parseIntVal(child.props["capacity-violation-grace"])
          if valOpt.isSome:
            violation.graceTurnsRemaining = valOpt.get()
        if child.props.hasKey("capacity-violation-turn"):
          let valOpt = parseIntVal(child.props["capacity-violation-turn"])
          if valOpt.isSome:
            violation.violationTurn = valOpt.get()
        if child.props.hasKey("capacity-violation-colony"):
          let idOpt = parseColonyId(child.props["capacity-violation-colony"])
          if idOpt.isSome:
            violation.entity = EntityIdUnion(kind: CapacityType.FighterSquadron,
              colonyId: idOpt.get())
        elif child.props.hasKey("capacity-violation-house"):
          let idOpt = parseHouseId(child.props["capacity-violation-house"])
          if idOpt.isSome:
            violation.entity = EntityIdUnion(kind: CapacityType.CapitalSquadron,
              houseId: idOpt.get())
        elif child.props.hasKey("capacity-violation-ship"):
          let idOpt = parseShipId(child.props["capacity-violation-ship"])
          if idOpt.isSome:
            violation.entity = EntityIdUnion(kind: CapacityType.CarrierHangar,
              shipId: idOpt.get())
        elif child.props.hasKey("capacity-violation-fleet"):
          let idOpt = parseFleetId(child.props["capacity-violation-fleet"])
          if idOpt.isSome:
            violation.entity = EntityIdUnion(kind: CapacityType.FleetSize,
              fleetId: idOpt.get())
        colony.capacityViolation = violation
    result.add(colony)


proc parseOwnedFleets(node: KdlNode): seq[Fleet] =
  result = @[]
  for child in node.children:
    if child.name != "fleet":
      continue
    var fleet = Fleet()
    if child.props.hasKey("id"):
      let idOpt = parseFleetId(child.props["id"])
      if idOpt.isSome:
        fleet.id = idOpt.get()
    if child.props.hasKey("house"):
      let houseOpt = parseHouseId(child.props["house"])
      if houseOpt.isSome:
        fleet.houseId = houseOpt.get()
    let locationOpt = childVal(child, "location")
    if locationOpt.isSome:
      let idOpt = parseSystemId(locationOpt.get())
      if idOpt.isSome:
        fleet.location = idOpt.get()
    let statusOpt = childVal(child, "status")
    if statusOpt.isSome:
      let parsedOpt = parseEnumPureFromStr[FleetStatus](statusOpt.get().getString())
      if parsedOpt.isSome:
        fleet.status = parsedOpt.get()
    let roeOpt = childVal(child, "roe")
    if roeOpt.isSome:
      let valueOpt = parseIntVal(roeOpt.get())
      if valueOpt.isSome:
        fleet.roe = valueOpt.get()
    let shipsNodeOpt = nodeChild(child, "ships")
    if shipsNodeOpt.isSome:
      for value in shipsNodeOpt.get().args:
        let idOpt = parseShipId(value)
        if idOpt.isSome:
          fleet.ships.add(idOpt.get())
    let commandNodeOpt = nodeChild(child, "command")
    if commandNodeOpt.isSome:
      let commandNode = commandNodeOpt.get()
      if commandNode.props.hasKey("type"):
        let parsedOpt = parseEnumPureFromStr[FleetCommandType](
          commandNode.props["type"].getString())
        if parsedOpt.isSome:
          fleet.command.commandType = parsedOpt.get()
      if commandNode.props.hasKey("priority"):
        let valueOpt = parseIntVal(commandNode.props["priority"])
        if valueOpt.isSome:
          fleet.command.priority = valueOpt.get()
      if commandNode.props.hasKey("target"):
        let idOpt = parseSystemId(commandNode.props["target"])
        if idOpt.isSome:
          fleet.command.targetSystem = some(idOpt.get())
      if commandNode.props.hasKey("target-fleet"):
        let idOpt = parseFleetId(commandNode.props["target-fleet"])
        if idOpt.isSome:
          fleet.command.targetFleet = some(idOpt.get())
      if commandNode.props.hasKey("roe"):
        let valueOpt = parseIntVal(commandNode.props["roe"])
        if valueOpt.isSome:
          fleet.command.roe = some(valueOpt.get())
      fleet.command.fleetId = fleet.id
    let missionStateOpt = childVal(child, "mission-state")
    if missionStateOpt.isSome:
      let parsedOpt = parseEnumPureFromStr[MissionState](
        child.props["mission-state"].getString())
      if parsedOpt.isSome:
        fleet.missionState = parsedOpt.get()

    let missionTargetOpt = childVal(child, "mission-target")
    if missionTargetOpt.isSome:
      let idOpt = parseSystemId(missionTargetOpt.get())
      if idOpt.isSome:
        fleet.missionTarget = some(idOpt.get())
    let missionStartOpt = childVal(child, "mission-start-turn")
    if missionStartOpt.isSome:
      let valueOpt = parseIntVal(missionStartOpt.get())
      if valueOpt.isSome:
        fleet.missionStartTurn = valueOpt.get()
    result.add(fleet)

proc parseOwnedShips(node: KdlNode): seq[Ship] =
  result = @[]
  for child in node.children:
    if child.name != "fleet":
      continue
    for shipNode in child.children:
      if shipNode.name != "ship":
        continue
      var ship = Ship()
      if shipNode.props.hasKey("id"):
        let idOpt = parseShipId(shipNode.props["id"])
        if idOpt.isSome:
          ship.id = idOpt.get()
      if shipNode.props.hasKey("class"):
       if shipNode.props.hasKey("class"):
         let parsedOpt = parseEnumPureFromStr[ShipClass](
           shipNode.props["class"].getString())
         if parsedOpt.isSome:
           ship.shipClass = parsedOpt.get()

       if shipNode.props.hasKey("state"):
         let parsedOpt = parseEnumPureFromStr[CombatState](
           shipNode.props["state"].getString())
         if parsedOpt.isSome:
           ship.state = parsedOpt.get()


      let attackOpt = childVal(shipNode, "attack")
      if attackOpt.isSome:
        let valueOpt = parseIntVal(attackOpt.get())
        if valueOpt.isSome:
          ship.stats.attackStrength = valueOpt.get()
      let defenseOpt = childVal(shipNode, "defense")
      if defenseOpt.isSome:
        let valueOpt = parseIntVal(defenseOpt.get())
        if valueOpt.isSome:
          ship.stats.defenseStrength = valueOpt.get()
      let wepOpt = childVal(shipNode, "wep")
      if wepOpt.isSome:
        let valueOpt = parseIntVal(wepOpt.get())
        if valueOpt.isSome:
          ship.stats.wep = valueOpt.get()
      let houseOpt = childVal(shipNode, "house")
      if houseOpt.isSome:
        let idOpt = parseHouseId(houseOpt.get())
        if idOpt.isSome:
          ship.houseId = idOpt.get()
      let fleetOpt = childVal(shipNode, "fleet")
      if fleetOpt.isSome:
        let idOpt = parseFleetId(fleetOpt.get())
        if idOpt.isSome:
          ship.fleetId = idOpt.get()
      let cargoNodeOpt = nodeChild(shipNode, "cargo")
      if cargoNodeOpt.isSome:
        let cargoNode = cargoNodeOpt.get()
        if cargoNode.props.hasKey("type"):
          let parsedOpt = parseEnumPureFromStr[CargoClass](
            cargoNode.props["type"].getString())
          if parsedOpt.isSome:
            ship.cargo = some(ShipCargo(cargoType: parsedOpt.get()))
        if ship.cargo.isSome:
          var cargo = ship.cargo.get()
          if cargoNode.props.hasKey("quantity"):
            let valueOpt = parseIntVal(cargoNode.props["quantity"])
            if valueOpt.isSome:
              cargo.quantity = valueOpt.get()
          if cargoNode.props.hasKey("capacity"):
            let valueOpt = parseIntVal(cargoNode.props["capacity"])
            if valueOpt.isSome:
              cargo.capacity = valueOpt.get()
          ship.cargo = some(cargo)
      let assignedOpt = childVal(shipNode, "assigned-to")
      if assignedOpt.isSome:
        let idOpt = parseShipId(assignedOpt.get())
        if idOpt.isSome:
          ship.assignedToCarrier = some(idOpt.get())
      let embarkedOpt = nodeChild(shipNode, "embarked-fighters")
      if embarkedOpt.isSome:
        for value in embarkedOpt.get().args:
          let idOpt = parseShipId(value)
          if idOpt.isSome:
            ship.embarkedFighters.add(idOpt.get())
      result.add(ship)

proc parseOwnedGroundUnits(node: KdlNode): seq[GroundUnit] =
  result = @[]
  for child in node.children:
    if child.name != "ground-units":
      continue
    for unitNode in child.children:
      if unitNode.name != "unit":
        continue
      var unit = GroundUnit()
      if unitNode.props.hasKey("id"):
        let idOpt = parseGroundUnitId(unitNode.props["id"])
        if idOpt.isSome:
          unit.id = idOpt.get()
      if unitNode.props.hasKey("house"):
        let houseOpt = parseHouseId(unitNode.props["house"])
        if houseOpt.isSome:
          unit.houseId = houseOpt.get()
      if unitNode.props.hasKey("type"):
        let parsedOpt = parseEnumPureFromStr[GroundClass](
          unitNode.props["type"].getString())
        if parsedOpt.isSome:
          unit.stats.unitType = parsedOpt.get()


      let attackOpt = childVal(unitNode, "attack")
      if attackOpt.isSome:
        let valueOpt = parseIntVal(attackOpt.get())
        if valueOpt.isSome:
          unit.stats.attackStrength = valueOpt.get()
      let defenseOpt = childVal(unitNode, "defense")
      if defenseOpt.isSome:
        let valueOpt = parseIntVal(defenseOpt.get())
        if valueOpt.isSome:
          unit.stats.defenseStrength = valueOpt.get()
      let stateOpt = childVal(unitNode, "state")
      if stateOpt.isSome:
        let parsedOpt = parseEnumPureFromStr[CombatState](
          child.props["state"].getString())
        if parsedOpt.isSome:
          unit.state = parsedOpt.get()

      if unitNode.props.hasKey("colony"):
        let idOpt = parseColonyId(unitNode.props["colony"])
        if idOpt.isSome:
          unit.garrison = GroundUnitGarrison(
            locationType: GroundUnitLocation.OnColony,
            colonyId: idOpt.get()
          )
      elif unitNode.props.hasKey("transport"):
        let idOpt = parseShipId(unitNode.props["transport"])
        if idOpt.isSome:
          unit.garrison = GroundUnitGarrison(
            locationType: GroundUnitLocation.OnTransport,
            shipId: idOpt.get()
          )
      result.add(unit)

proc parsePlayerStateKdl*(kdlState: string): Option[PlayerState] =
  try:
    let doc = parseKdl(kdlState)
    if doc.len == 0 or doc[0].name != "state":
      return none(PlayerState)
    let root = doc[0]

    var state = PlayerState()
    if root.props.hasKey("turn"):
      try:
        state.turn = root.props["turn"].getInt().int32
      except CatchableError:
        discard

    if root.children.len > 0:
      for child in root.children:
        if child.name == "viewing-house" and child.props.hasKey("id"):
          let idOpt = parseHouseId(child.props["id"])
          if idOpt.isSome:
            state.viewingHouse = idOpt.get()

      for child in root.children:
        case child.name
        of "colonies":
          state.ownColonies = parseOwnedColonies(child)
        of "fleets":
          state.ownFleets = parseOwnedFleets(child)
          state.ownShips = parseOwnedShips(child)
        of "ground-units":
          state.ownGroundUnits = parseOwnedGroundUnits(child)
        of "systems":
          state.visibleSystems = parseVisibleSystems(child)
        of "intel":
          for intelChild in child.children:
            case intelChild.name
            of "colonies":
              state.visibleColonies = parseVisibleColonies(intelChild)
            of "fleets":
              state.visibleFleets = parseVisibleFleets(intelChild)
            else:
              discard
        of "public":
          parsePublicSection(child, state)
        else:
          discard

    some(state)
  except CatchableError as e:
    logError("StateKDL", "Failed to parse KDL state: ", e.msg)
    none(PlayerState)
