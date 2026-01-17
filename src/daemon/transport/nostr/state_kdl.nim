## PlayerState full-state KDL formatting (30405)

import std/[algorithm, options, tables, strutils, json, jsonutils]
import kdl
import ../../../engine/state/fog_of_war
import ../../../engine/state/engine
import ../../../engine/types/[core, colony, fleet, ship, ground_unit, player_state,
  facilities, production, progression]
import ../../../engine/types/tech
import ../../../engine/types/game_state
import ../../persistence/player_state_snapshot

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
  houseNode.children.add(nodeWithArg("treasury", initKVal(house.treasury)))
  houseNode.children.add(nodeWithArg("prestige", initKVal(house.prestige)))
  houseNode.children.add(
    nodeWithArg("eliminated", initKVal(house.isEliminated))
  )
  houseNode.children.add(
    nodeWithArg("data", initKVal($toJson(house)))
  )
  houseNode.children.add(formatTechLevels(house.techTree.levels))
  some(houseNode)

proc formatColonyFacilities(state: GameState, colony: Colony): KdlNode =
  var spaceport = 0
  var shipyard = 0
  var drydock = 0
  var starbase = 0

  for neoriaId in colony.neoriaIds:
    let neoriaOpt = state.neoria(neoriaId)
    if neoriaOpt.isSome:
      case neoriaOpt.get().neoriaClass
      of NeoriaClass.Spaceport:
        inc(spaceport)
      of NeoriaClass.Shipyard:
        inc(shipyard)
      of NeoriaClass.Drydock:
        inc(drydock)

  for kastraId in colony.kastraIds:
    let kastraOpt = state.kastra(kastraId)
    if kastraOpt.isSome:
      case kastraOpt.get().kastraClass
      of KastraClass.Starbase:
        inc(starbase)

  var facilitiesNode = initKNode("facilities")
  facilitiesNode.children.add(nodeWithArg("spaceport", initKVal(spaceport)))
  facilitiesNode.children.add(nodeWithArg("shipyard", initKVal(shipyard)))
  facilitiesNode.children.add(nodeWithArg("drydock", initKVal(drydock)))
  facilitiesNode.children.add(nodeWithArg("starbase", initKVal(starbase)))
  facilitiesNode

proc formatColonyGroundUnits(state: GameState, colony: Colony): KdlNode =
  var army = 0
  var marine = 0
  var battery = 0
  var shield = 0

  for unitId in colony.groundUnitIds:
    let unitOpt = state.groundUnit(unitId)
    if unitOpt.isSome:
      case unitOpt.get().stats.unitType
      of GroundClass.Army:
        inc(army)
      of GroundClass.Marine:
        inc(marine)
      of GroundClass.GroundBattery:
        inc(battery)
      of GroundClass.PlanetaryShield:
        inc(shield)

  var unitsNode = initKNode("ground-units")
  unitsNode.children.add(nodeWithArg("army", initKVal(army)))
  unitsNode.children.add(nodeWithArg("marine", initKVal(marine)))
  unitsNode.children.add(nodeWithArg("ground-battery", initKVal(battery)))
  unitsNode.children.add(nodeWithArg("planetary-shield", initKVal(shield)))
  unitsNode

proc projectTypeLabel(project: ConstructionProject): string =
  case project.projectType
  of BuildType.Ship:
    "ship"
  of BuildType.Facility:
    "facility"
  of BuildType.Ground:
    "ground"
  of BuildType.Industrial:
    "industrial"
  of BuildType.Infrastructure:
    "infrastructure"

proc formatConstructionQueue(
  state: GameState,
  colony: Colony
): Option[KdlNode] =
  if colony.constructionQueue.len == 0:
    return none(KdlNode)

  var queueNode = initKNode("construction-queue")
  for projectId in colony.constructionQueue:
    let projectOpt = state.constructionProject(projectId)
    if projectOpt.isNone:
      continue
    let project = projectOpt.get()
    var props = initTable[string, KdlVal]()
    props["type"] = initKVal(projectTypeLabel(project))
    if project.shipClass.isSome:
      props["class"] = initKVal($project.shipClass.get())
    elif project.facilityClass.isSome:
      props["class"] = initKVal($project.facilityClass.get())
    elif project.groundClass.isSome:
      props["class"] = initKVal($project.groundClass.get())
    if project.industrialUnits > 0:
      props["units"] = initKVal(project.industrialUnits)
    props["progress"] = initKVal(project.costPaid)
    props["cost"] = initKVal(project.costTotal)
    props["turns"] = initKVal(project.turnsRemaining)
    queueNode.children.add(initKNode("project", props = props))

  some(queueNode)

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
    let systemOpt = state.system(colony.systemId)
    if systemOpt.isSome:
      props["name"] = initKVal(systemOpt.get().name)

    var colonyNode = initKNode("colony", props = props)
    colonyNode.children.add(
      nodeWithArg("population", initKVal(colony.population))
    )
    colonyNode.children.add(
      nodeWithArg("industry", initKVal(colony.industrial.units))
    )
    colonyNode.children.add(nodeWithArg("tax-rate", initKVal(colony.taxRate)))
    colonyNode.children.add(
      nodeWithArg("auto-repair", initKVal(colony.autoRepair))
    )
    colonyNode.children.add(
      nodeWithArg("under-siege", initKVal(colony.blockaded))
    )
    colonyNode.children.add(nodeWithArg("data", initKVal($toJson(colony))))
    colonyNode.children.add(formatColonyFacilities(state, colony))
    colonyNode.children.add(formatColonyGroundUnits(state, colony))

    let queueOpt = formatConstructionQueue(state, colony)
    if queueOpt.isSome:
      colonyNode.children.add(queueOpt.get())

    coloniesNode.children.add(colonyNode)

  some(coloniesNode)

proc formatShipDetails(ship: Ship): KdlNode =
  var props = initTable[string, KdlVal]()
  props["id"] = idVal(ship.id)
  props["class"] = initKVal($ship.shipClass)
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
    cargoProps["type"] = initKVal($cargo.cargoType)
    cargoProps["quantity"] = initKVal(cargo.quantity)
    cargoProps["capacity"] = initKVal(cargo.capacity)
    cargoProps["data"] = initKVal($toJson(cargo))
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

  shipNode.children.add(nodeWithArg("data", initKVal($toJson(ship))))
  shipNode

proc formatFleetCommand(command: FleetCommand): KdlNode =
  var props = initTable[string, KdlVal]()
  props["type"] = initKVal(kdlEnum($command.commandType))
  if command.targetSystem.isSome:
    props["target"] = idVal(command.targetSystem.get())
  if command.targetFleet.isSome:
    props["target-fleet"] = idVal(command.targetFleet.get())

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

    var fleetNode = initKNode("fleet", props = props)
    fleetNode.children.add(nodeWithArg("data", initKVal($toJson(fleet))))
    fleetNode.children.add(formatFleetCommand(fleet.command))
    for ship in playerState.ownShips:
      if ship.fleetId == fleet.id:
        fleetNode.children.add(formatShipDetails(ship))
    fleetsNode.children.add(fleetNode)

  some(fleetsNode)

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
      if visibleSys.visibility != VisibilityLevel.Adjacent and
         visibleSys.visibility != VisibilityLevel.None:
        name = sys.name
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

    systemNode.children.add(nodeWithArg("ring", initKVal(ring)))
    systemNode.children.add(nodeWithArg("data", initKVal($toJson(visibleSys))))
    if planetClass.len > 0:
      systemNode.children.add(
        nodeWithArg("planet-class", initKVal(planetClass))
      )
    if resourceRating.len > 0:
      systemNode.children.add(
        nodeWithArg("resource-rating", initKVal(resourceRating))
      )
    if visibleSys.jumpLaneIds.len > 0:
      var laneArgs: seq[KdlVal] = @[]
      for laneId in visibleSys.jumpLaneIds:
        laneArgs.add(idVal(laneId))
      systemNode.children.add(initKNode("lanes", args = laneArgs))

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
      fleetNode.children.add(nodeWithArg("data", initKVal($toJson(fleet))))
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
      colonyNode.children.add(nodeWithArg("data", initKVal($toJson(colony))))
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
      var node = initKNode("house", props = props)
      node.children.add(nodeWithArg("data", initKVal($toJson(HouseValue(
        houseId: houseId,
        value: value
      )))))
      prestigeNode.children.add(node)
    publicNode.children.add(prestigeNode)

  if playerState.houseColonyCounts.len > 0:
    var countsNode = initKNode("colony-counts")
    for houseId, count in playerState.houseColonyCounts:
      var props = initTable[string, KdlVal]()
      props["id"] = idVal(houseId)
      props["count"] = initKVal(count)
      var node = initKNode("house", props = props)
      node.children.add(nodeWithArg("data", initKVal($toJson(HouseCount(
        houseId: houseId,
        count: count
      )))))
      countsNode.children.add(node)
    publicNode.children.add(countsNode)

  if playerState.diplomaticRelations.len > 0:
    var diplomacyNode = initKNode("diplomacy")
    for key, relation in playerState.diplomaticRelations:
      var props = initTable[string, KdlVal]()
      props["from"] = idVal(key[0])
      props["to"] = idVal(key[1])
      props["state"] = initKVal(kdlEnum($relation))
      var node = initKNode("relation", props = props)
      node.children.add(nodeWithArg("data", initKVal($toJson(RelationSnapshot(
        sourceHouse: key[0],
        targetHouse: key[1],
        state: relation
      )))))
      diplomacyNode.children.add(node)
    publicNode.children.add(diplomacyNode)

  if playerState.eliminatedHouses.len > 0:
    var eliminatedNode = initKNode("eliminated-houses")
    for houseId in playerState.eliminatedHouses:
      var props = initTable[string, KdlVal]()
      props["id"] = idVal(houseId)
      var node = initKNode("house", props = props)
      node.children.add(nodeWithArg("data", initKVal($toJson(houseId))))
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
  progressionNode.children.add(
    nodeWithArg("data", initKVal($toJson(progression)))
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

  root.children.add(formatSystems(state, playerState))

  let intelOpt = formatIntel(playerState)
  if intelOpt.isSome:
    root.children.add(intelOpt.get())

  root.children.add(formatPublicInfo(playerState))

  let doc: KdlDoc = @[root]
  doc.pretty()
