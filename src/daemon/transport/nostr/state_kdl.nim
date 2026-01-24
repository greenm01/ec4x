## PlayerState full-state KDL formatting (30405)

import std/[algorithm, options, tables, strutils]
import kdl
import ../../../engine/state/fog_of_war
import ../../../engine/state/engine
import ../../../engine/types/[core, colony, fleet, ship, ground_unit, player_state,
  production, progression, capacity]
import ../../../engine/types/tech
import ../../../engine/types/game_state

proc kdlEnum(value: string): string =
  value.toLowerAscii().replace("_", "-")

proc idVal(id: HouseId): KdlVal =
  initKVal(id.uint32, some("HouseId"))

proc idVal(id: SystemId): KdlVal =
  initKVal(id.uint32, some("SystemId"))

proc idVal(id: ColonyId): KdlVal =
  initKVal(id.uint32, some("ColonyId"))

proc idVal(id: FleetId): KdlVal =
  initKVal(id.uint32, some("FleetId"))

proc idVal(id: ShipId): KdlVal =
  initKVal(id.uint32, some("ShipId"))

proc idVal(id: GroundUnitId): KdlVal =
  initKVal(id.uint32, some("GroundUnitId"))

proc idVal(id: ConstructionProjectId): KdlVal =
  initKVal(id.uint32, some("ConstructionProjectId"))

proc idVal(id: RepairProjectId): KdlVal =
  initKVal(id.uint32, some("RepairProjectId"))

proc idVal(id: NeoriaId): KdlVal =
  initKVal(id.uint32, some("NeoriaId"))

proc idVal(id: KastraId): KdlVal =
  initKVal(id.uint32, some("KastraId"))

proc nodeWithArg(name: string, arg: KdlVal): KdlNode =
  initKNode(name, args = @[arg])

proc formatTechLevels(levels: TechLevel): KdlNode =
  var techNode = initKNode("tech")
  techNode.children.add(nodeWithArg("economic", initKVal(levels.el)))
  techNode.children.add(nodeWithArg("science", initKVal(levels.sl)))
  techNode.children.add(nodeWithArg("weapons", initKVal(levels.wep)))
  techNode.children.add(nodeWithArg("shields", initKVal(levels.sld)))
  techNode.children.add(nodeWithArg("construction", initKVal(levels.cst)))
  techNode.children.add(nodeWithArg("terraforming", initKVal(levels.ter)))
  techNode.children.add(
    nodeWithArg("electronic-intelligence", initKVal(levels.eli))
  )
  techNode.children.add(nodeWithArg("cloaking", initKVal(levels.clk)))
  techNode.children.add(nodeWithArg("strategic-lift", initKVal(levels.stl)))
  techNode.children.add(
    nodeWithArg("counter-intelligence", initKVal(levels.cic))
  )
  techNode.children.add(
    nodeWithArg("flagship-command", initKVal(levels.fc))
  )
  techNode.children.add(
    nodeWithArg("strategic-command", initKVal(levels.sc))
  )
  techNode.children.add(
    nodeWithArg("fighter-doctrine", initKVal(levels.fd))
  )
  techNode.children.add(
    nodeWithArg("advanced-carrier-operations", initKVal(levels.aco))
  )
  techNode

proc formatHouseSection(state: GameState, houseId: HouseId): Option[KdlNode] =
  let houseOpt = state.house(houseId)
  if houseOpt.isNone:
    return none(KdlNode)

  let house = houseOpt.get()
  var houseNode = initKNode("house")
  houseNode.children.add(nodeWithArg("name", initKVal(house.name)))
  houseNode.children.add(nodeWithArg("treasury", initKVal(house.treasury)))
  houseNode.children.add(nodeWithArg("prestige", initKVal(house.prestige)))
  houseNode.children.add(
    nodeWithArg("eliminated", initKVal(house.isEliminated))
  )
  houseNode.children.add(formatTechLevels(house.techTree.levels))
  some(houseNode)


proc formatColonies(
  state: GameState,
  playerState: PlayerState
): Option[KdlNode] =
  if playerState.ownColonies.len == 0:
    return none(KdlNode)

  var coloniesNode = initKNode("colonies")
  for colony in playerState.ownColonies:
    var props = initTable[string, KdlVal]()
    props["id"] = idVal(colony.id)
    props["system"] = idVal(colony.systemId)
    props["owner"] = idVal(colony.owner)
    let systemOpt = state.system(colony.systemId)
    if systemOpt.isSome:
      props["name"] = initKVal(systemOpt.get().name)

    var colonyNode = initKNode("colony", props = props)
    colonyNode.children.add(
      nodeWithArg("population", initKVal(colony.population))
    )
    colonyNode.children.add(
      nodeWithArg("souls", initKVal(colony.souls))
    )
    colonyNode.children.add(
      nodeWithArg("population-units", initKVal(colony.populationUnits))
    )
    colonyNode.children.add(
      nodeWithArg("population-transfer-units",
        initKVal(colony.populationTransferUnits))
    )
    colonyNode.children.add(
      nodeWithArg("infrastructure", initKVal(colony.infrastructure))
    )
    colonyNode.children.add(
      nodeWithArg("industrial-units", initKVal(colony.industrial.units))
    )
    colonyNode.children.add(
      nodeWithArg("industrial-investment",
        initKVal(colony.industrial.investmentCost))
    )
    colonyNode.children.add(
      nodeWithArg("production", initKVal(colony.production))
    )
    colonyNode.children.add(
      nodeWithArg("gross-output", initKVal(colony.grossOutput))
    )
    colonyNode.children.add(nodeWithArg("tax-rate", initKVal(colony.taxRate)))
    colonyNode.children.add(
      nodeWithArg("infrastructure-damage",
        initKVal(colony.infrastructureDamage))
    )
    if colony.underConstruction.isSome:
      colonyNode.children.add(
        nodeWithArg("under-construction", idVal(colony.underConstruction.get()))
      )
    if colony.constructionQueue.len > 0:
      var queueArgs: seq[KdlVal] = @[]
      for projectId in colony.constructionQueue:
        queueArgs.add(idVal(projectId))
      colonyNode.children.add(initKNode("construction-queue", args = queueArgs))
    if colony.repairQueue.len > 0:
      var repairArgs: seq[KdlVal] = @[]
      for projectId in colony.repairQueue:
        repairArgs.add(idVal(projectId))
      colonyNode.children.add(initKNode("repair-queue", args = repairArgs))
    if colony.activeTerraforming.isSome:
      let terra = colony.activeTerraforming.get()
      var terraProps = initTable[string, KdlVal]()
      terraProps["start-turn"] = initKVal(terra.startTurn)
      terraProps["turns-remaining"] = initKVal(terra.turnsRemaining)
      terraProps["target-class"] = initKVal(terra.targetClass)
      terraProps["pp-cost"] = initKVal(terra.ppCost)
      terraProps["pp-paid"] = initKVal(terra.ppPaid)
      colonyNode.children.add(initKNode("terraforming", props = terraProps))
    if colony.fighterIds.len > 0:
      var fighterArgs: seq[KdlVal] = @[]
      for fighterId in colony.fighterIds:
        fighterArgs.add(idVal(fighterId))
      colonyNode.children.add(initKNode("fighters", args = fighterArgs))
    if colony.groundUnitIds.len > 0:
      var unitArgs: seq[KdlVal] = @[]
      for unitId in colony.groundUnitIds:
        unitArgs.add(idVal(unitId))
      colonyNode.children.add(initKNode("ground-units", args = unitArgs))
    if colony.neoriaIds.len > 0:
      var neoriaArgs: seq[KdlVal] = @[]
      for neoriaId in colony.neoriaIds:
        neoriaArgs.add(idVal(neoriaId))
      colonyNode.children.add(initKNode("neorias", args = neoriaArgs))
    if colony.kastraIds.len > 0:
      var kastraArgs: seq[KdlVal] = @[]
      for kastraId in colony.kastraIds:
        kastraArgs.add(idVal(kastraId))
      colonyNode.children.add(initKNode("kastras", args = kastraArgs))
    colonyNode.children.add(
      nodeWithArg("blockaded", initKVal(colony.blockaded))
    )

    if colony.blockadedBy.len > 0:
      var blockadedArgs: seq[KdlVal] = @[]
      for houseId in colony.blockadedBy:
        blockadedArgs.add(idVal(houseId))
      colonyNode.children.add(initKNode("blockaded-by", args = blockadedArgs))
    colonyNode.children.add(
      nodeWithArg("blockade-turns", initKVal(colony.blockadeTurns))
    )
    colonyNode.children.add(
      nodeWithArg("auto-repair", initKVal(colony.autoRepair))
    )
    colonyNode.children.add(
      nodeWithArg("auto-load-marines", initKVal(colony.autoLoadMarines))
    )
    colonyNode.children.add(
      nodeWithArg("auto-load-fighters", initKVal(colony.autoLoadFighters))
    )
    let capacity = colony.capacityViolation
    if capacity.capacityType != CapacityType.FighterSquadron or
        capacity.maximum != 0 or
        capacity.current != 0 or
        capacity.excess != 0 or
        capacity.severity != ViolationSeverity.None or
        capacity.graceTurnsRemaining != 0 or
        capacity.violationTurn != 0:
      var capacityProps = initTable[string, KdlVal]()
      capacityProps["type"] = initKVal(kdlEnum($capacity.capacityType))
      capacityProps["current"] = initKVal(capacity.current)
      capacityProps["maximum"] = initKVal(capacity.maximum)
      capacityProps["excess"] = initKVal(capacity.excess)
      capacityProps["severity"] = initKVal(kdlEnum($capacity.severity))
      capacityProps["grace-turns"] = initKVal(capacity.graceTurnsRemaining)
      capacityProps["violation-turn"] = initKVal(capacity.violationTurn)
      case capacity.entity.kind
      of CapacityType.FighterSquadron, CapacityType.ConstructionDock:
        capacityProps["colony"] = idVal(capacity.entity.colonyId)
      of CapacityType.CapitalSquadron, CapacityType.TotalSquadron,
         CapacityType.PlanetBreaker, CapacityType.FleetCount, CapacityType.C2Pool:
        capacityProps["house"] = idVal(capacity.entity.houseId)
      of CapacityType.CarrierHangar:
        capacityProps["ship"] = idVal(capacity.entity.shipId)
      of CapacityType.FleetSize:
        capacityProps["fleet"] = idVal(capacity.entity.fleetId)
      colonyNode.children.add(initKNode("capacity-violation", props = capacityProps))

    coloniesNode.children.add(colonyNode)


  some(coloniesNode)

proc formatShipDetails(ship: Ship): KdlNode =
  var props = initTable[string, KdlVal]()
  props["id"] = idVal(ship.id)
  props["class"] = initKVal(kdlEnum($ship.shipClass))
  props["state"] = initKVal(kdlEnum($ship.state))

  var shipNode = initKNode("ship", props = props)
  shipNode.children.add(
    nodeWithArg("attack", initKVal(ship.stats.attackStrength))
  )
  shipNode.children.add(
    nodeWithArg("defense", initKVal(ship.stats.defenseStrength))
  )
  shipNode.children.add(nodeWithArg("wep", initKVal(ship.stats.wep)))

  if ship.cargo.isSome:
    let cargo = ship.cargo.get()
    var cargoProps = initTable[string, KdlVal]()
    cargoProps["type"] = initKVal(kdlEnum($cargo.cargoType))
    cargoProps["quantity"] = initKVal(cargo.quantity)
    cargoProps["capacity"] = initKVal(cargo.capacity)
    shipNode.children.add(initKNode("cargo", props = cargoProps))

  if ship.assignedToCarrier.isSome:
    shipNode.children.add(
      nodeWithArg("assigned-to", idVal(ship.assignedToCarrier.get()))
    )

  if ship.embarkedFighters.len > 0:
    var fighterArgs: seq[KdlVal] = @[]
    for fighterId in ship.embarkedFighters:
      fighterArgs.add(idVal(fighterId))
    shipNode.children.add(initKNode("embarked-fighters", args = fighterArgs))

  shipNode.children.add(nodeWithArg("house", idVal(ship.houseId)))
  shipNode.children.add(nodeWithArg("fleet", idVal(ship.fleetId)))
  shipNode

proc formatFleetCommand(command: FleetCommand): KdlNode =
  var props = initTable[string, KdlVal]()
  props["type"] = initKVal(kdlEnum($command.commandType))
  props["priority"] = initKVal(command.priority)
  if command.targetSystem.isSome:
    props["target"] = idVal(command.targetSystem.get())
  if command.targetFleet.isSome:
    props["target-fleet"] = idVal(command.targetFleet.get())
  if command.roe.isSome:
    props["roe"] = initKVal(command.roe.get())

  initKNode("command", props = props)

proc formatFleets(playerState: PlayerState): Option[KdlNode] =
  if playerState.ownFleets.len == 0:
    return none(KdlNode)

  var fleetsNode = initKNode("fleets")
  for fleet in playerState.ownFleets:
    var props = initTable[string, KdlVal]()
    props["id"] = idVal(fleet.id)
    props["location"] = idVal(fleet.location)
    props["status"] = initKVal(kdlEnum($fleet.status))
    props["house"] = idVal(fleet.houseId)

    var fleetNode = initKNode("fleet", props = props)
    if fleet.ships.len > 0:
      var shipArgs: seq[KdlVal] = @[]
      for shipId in fleet.ships:
        shipArgs.add(idVal(shipId))
      fleetNode.children.add(initKNode("ships", args = shipArgs))
    fleetNode.children.add(nodeWithArg("roe", initKVal(fleet.roe)))
    fleetNode.children.add(formatFleetCommand(fleet.command))
    fleetNode.children.add(
      nodeWithArg("mission-state", initKVal(kdlEnum($fleet.missionState)))
    )
    if fleet.missionTarget.isSome:
      fleetNode.children.add(
        nodeWithArg("mission-target", idVal(fleet.missionTarget.get()))
      )
    fleetNode.children.add(
      nodeWithArg("mission-start-turn", initKVal(fleet.missionStartTurn))
    )
    for ship in playerState.ownShips:
      if ship.fleetId == fleet.id:
        fleetNode.children.add(formatShipDetails(ship))
    fleetsNode.children.add(fleetNode)

  some(fleetsNode)

proc formatGroundUnits(playerState: PlayerState): Option[KdlNode] =
  if playerState.ownGroundUnits.len == 0:
    return none(KdlNode)

  var unitsNode = initKNode("ground-units")
  for unit in playerState.ownGroundUnits:
    var props = initTable[string, KdlVal]()
    props["id"] = idVal(unit.id)
    props["house"] = idVal(unit.houseId)
    props["type"] = initKVal(kdlEnum($unit.stats.unitType))
    props["state"] = initKVal(kdlEnum($unit.state))
    var unitNode = initKNode("unit", props = props)
    unitNode.children.add(
      nodeWithArg("attack", initKVal(unit.stats.attackStrength))
    )
    unitNode.children.add(
      nodeWithArg("defense", initKVal(unit.stats.defenseStrength))
    )
    case unit.garrison.locationType
    of GroundUnitLocation.OnColony:
      unitNode.children.add(nodeWithArg("colony",
        idVal(unit.garrison.colonyId)))
    of GroundUnitLocation.OnTransport:
      unitNode.children.add(nodeWithArg("transport",
        idVal(unit.garrison.shipId)))
    unitsNode.children.add(unitNode)

  some(unitsNode)

proc formatSystems(
  state: GameState,
  playerState: PlayerState
): KdlNode =
  var systems: seq[VisibleSystem] = @[]
  for _, visibleSys in playerState.visibleSystems:
    systems.add(visibleSys)
  systems.sort(proc(a, b: VisibleSystem): int =
    cmp(a.systemId.uint32, b.systemId.uint32))

  var systemsNode = initKNode("systems")
  for visibleSys in systems:
    var props = initTable[string, KdlVal]()
    props["id"] = idVal(visibleSys.systemId)

    var name = "Unknown System"
    var ring = 0'u32
    var planetClass = ""
    var resourceRating = ""
    let sysOpt = state.system(visibleSys.systemId)
    if sysOpt.isSome:
      let sys = sysOpt.get()
      ring = sys.ring
      name = sys.name
      if visibleSys.visibility != VisibilityLevel.Adjacent and
         visibleSys.visibility != VisibilityLevel.None:
        planetClass = kdlEnum($sys.planetClass)
        resourceRating = kdlEnum($sys.resourceRating)

    props["name"] = initKVal(name)
    var systemNode = initKNode("system", props = props)

    systemNode.children.add(
      nodeWithArg("visibility", initKVal(kdlEnum($visibleSys.visibility)))
    )
    if visibleSys.lastScoutedTurn.isSome:
      systemNode.children.add(
        nodeWithArg(
          "last-scouted",
          initKVal(visibleSys.lastScoutedTurn.get())
        )
      )
    if visibleSys.coordinates.isSome:
      let coords = visibleSys.coordinates.get()
      var coordsProps = initTable[string, KdlVal]()
      coordsProps["q"] = initKVal(coords.q)
      coordsProps["r"] = initKVal(coords.r)
      systemNode.children.add(initKNode("coords", props = coordsProps))

    if visibleSys.jumpLaneIds.len > 0:
      var laneArgs: seq[KdlVal] = @[]
      for laneId in visibleSys.jumpLaneIds:
        laneArgs.add(idVal(laneId))
      systemNode.children.add(initKNode("lanes", args = laneArgs))

    systemNode.children.add(nodeWithArg("ring", initKVal(ring)))
    if planetClass.len > 0:
      systemNode.children.add(
        nodeWithArg("planet-class", initKVal(planetClass))
      )
    if resourceRating.len > 0:
      systemNode.children.add(
        nodeWithArg("resource-rating", initKVal(resourceRating))
      )
    systemsNode.children.add(systemNode)

  systemsNode

proc formatIntel(playerState: PlayerState): Option[KdlNode] =
  if playerState.visibleFleets.len == 0 and playerState.visibleColonies.len == 0:
    return none(KdlNode)

  var intelNode = initKNode("intel")
  if playerState.visibleFleets.len > 0:
    var fleetsNode = initKNode("fleets")
    for fleet in playerState.visibleFleets:
      var props = initTable[string, KdlVal]()
      props["id"] = idVal(fleet.fleetId)
      props["owner"] = idVal(fleet.owner)
      var fleetNode = initKNode("fleet", props = props)
      fleetNode.children.add(
        nodeWithArg("location", idVal(fleet.location))
      )
      if fleet.intelTurn.isSome:
        fleetNode.children.add(
          nodeWithArg("detected-turn", initKVal(fleet.intelTurn.get()))
        )
      if fleet.estimatedShipCount.isSome:
        fleetNode.children.add(
          nodeWithArg("estimated-ships", initKVal(
            fleet.estimatedShipCount.get()
          ))
        )
      if fleet.detectedInSystem.isSome:
        fleetNode.children.add(
          nodeWithArg("detected-system", idVal(fleet.detectedInSystem.get()))
        )
      fleetsNode.children.add(fleetNode)
    intelNode.children.add(fleetsNode)

  if playerState.visibleColonies.len > 0:
    var coloniesNode = initKNode("colonies")
    for colony in playerState.visibleColonies:
      var props = initTable[string, KdlVal]()
      props["id"] = idVal(colony.colonyId)
      props["owner"] = idVal(colony.owner)
      var colonyNode = initKNode("colony", props = props)
      colonyNode.children.add(
        nodeWithArg("system", idVal(colony.systemId))
      )
      if colony.intelTurn.isSome:
        colonyNode.children.add(
          nodeWithArg("intel-turn", initKVal(colony.intelTurn.get()))
        )
      if colony.estimatedPopulation.isSome:
        colonyNode.children.add(
          nodeWithArg("estimated-population", initKVal(
            colony.estimatedPopulation.get()
          ))
        )
      if colony.estimatedIndustry.isSome:
        colonyNode.children.add(
          nodeWithArg("estimated-industry", initKVal(
            colony.estimatedIndustry.get()
          ))
        )
      if colony.estimatedDefenses.isSome:
        colonyNode.children.add(
          nodeWithArg("estimated-defenses", initKVal(
            colony.estimatedDefenses.get()
          ))
        )
      if colony.starbaseLevel.isSome:
        colonyNode.children.add(
          nodeWithArg("starbase-level", initKVal(
            colony.starbaseLevel.get()
          ))
        )
      if colony.reserveFleetCount.isSome:
        colonyNode.children.add(
          nodeWithArg("reserve-fleet-count", initKVal(
            colony.reserveFleetCount.get()
          ))
        )
      if colony.mothballedFleetCount.isSome:
        colonyNode.children.add(
          nodeWithArg("mothballed-fleet-count", initKVal(
            colony.mothballedFleetCount.get()
          ))
        )
      if colony.shipyardCount.isSome:
        colonyNode.children.add(
          nodeWithArg("shipyard-count", initKVal(
            colony.shipyardCount.get()
          ))
        )
      if colony.unassignedSquadronCount.isSome:
        colonyNode.children.add(
          nodeWithArg("unassigned-squadrons", initKVal(
            colony.unassignedSquadronCount.get()
          ))
        )
      coloniesNode.children.add(colonyNode)
    intelNode.children.add(coloniesNode)

  some(intelNode)

proc formatPublicInfo(playerState: PlayerState): KdlNode =
  var publicNode = initKNode("public")

  if playerState.housePrestige.len > 0:
    var prestigeNode = initKNode("prestige")
    for houseId, value in playerState.housePrestige:
      var props = initTable[string, KdlVal]()
      props["id"] = idVal(houseId)
      props["value"] = initKVal(value)
      let node = initKNode("house", props = props)
      prestigeNode.children.add(node)
    publicNode.children.add(prestigeNode)

  if playerState.houseColonyCounts.len > 0:
    var countsNode = initKNode("colony-counts")
    for houseId, count in playerState.houseColonyCounts:
      var props = initTable[string, KdlVal]()
      props["id"] = idVal(houseId)
      props["count"] = initKVal(count)
      let node = initKNode("house", props = props)
      countsNode.children.add(node)
    publicNode.children.add(countsNode)

  if playerState.diplomaticRelations.len > 0:
    var diplomacyNode = initKNode("diplomacy")
    for key, relation in playerState.diplomaticRelations:
      var props = initTable[string, KdlVal]()
      props["from"] = idVal(key[0])
      props["to"] = idVal(key[1])
      props["state"] = initKVal(kdlEnum($relation))
      let node = initKNode("relation", props = props)
      diplomacyNode.children.add(node)
    publicNode.children.add(diplomacyNode)

  if playerState.eliminatedHouses.len > 0:
    var eliminatedNode = initKNode("eliminated-houses")
    for houseId in playerState.eliminatedHouses:
      var props = initTable[string, KdlVal]()
      props["id"] = idVal(houseId)
      let node = initKNode("house", props = props)
      eliminatedNode.children.add(node)
    publicNode.children.add(eliminatedNode)

  let progression = playerState.actProgression
  var progressionNode = initKNode("act-progression")
  progressionNode.children.add(
    nodeWithArg("current-act", initKVal(kdlEnum($progression.currentAct)))
  )
  progressionNode.children.add(
    nodeWithArg("act-start-turn", initKVal(progression.actStartTurn))
  )
  progressionNode.children.add(
    nodeWithArg("colonization-percent", initKVal(
      progression.lastColonizationPercent
    ))
  )
  progressionNode.children.add(
    nodeWithArg("total-prestige", initKVal(
      progression.lastTotalPrestige
    ))
  )
  if progression.act2TopThreeHouses.len > 0:
    var houseArgs: seq[KdlVal] = @[]
    for houseId in progression.act2TopThreeHouses:
      houseArgs.add(idVal(houseId))
    progressionNode.children.add(initKNode("act2-top-houses", args = houseArgs))
  if progression.act2TopThreePrestige.len > 0:
    var prestigeArgs: seq[KdlVal] = @[]
    for value in progression.act2TopThreePrestige:
      prestigeArgs.add(initKVal(value))
    progressionNode.children.add(
      initKNode("act2-top-prestige", args = prestigeArgs)
    )
  publicNode.children.add(progressionNode)

  publicNode

proc formatPlayerStateKdl*(
  gameId: string,
  state: GameState,
  houseId: HouseId
): string =
  let playerState = createPlayerState(state, houseId)

  var rootProps = initTable[string, KdlVal]()
  rootProps["turn"] = initKVal(state.turn)
  rootProps["game"] = initKVal(gameId)

  var root = initKNode("state", props = rootProps)
  let houseOpt = state.house(houseId)
  if houseOpt.isSome:
    let house = houseOpt.get()
    var viewProps = initTable[string, KdlVal]()
    viewProps["id"] = idVal(houseId)
    viewProps["name"] = initKVal(house.name)
    root.children.add(initKNode("viewing-house", props = viewProps))

  let houseNodeOpt = formatHouseSection(state, houseId)
  if houseNodeOpt.isSome:
    root.children.add(houseNodeOpt.get())

  let coloniesOpt = formatColonies(state, playerState)
  if coloniesOpt.isSome:
    root.children.add(coloniesOpt.get())

  let fleetsOpt = formatFleets(playerState)
  if fleetsOpt.isSome:
    root.children.add(fleetsOpt.get())

  let groundOpt = formatGroundUnits(playerState)
  if groundOpt.isSome:
    root.children.add(groundOpt.get())

  root.children.add(formatSystems(state, playerState))

  let intelOpt = formatIntel(playerState)
  if intelOpt.isSome:
    root.children.add(intelOpt.get())

  root.children.add(formatPublicInfo(playerState))

  let doc: KdlDoc = @[root]
  doc.pretty()
