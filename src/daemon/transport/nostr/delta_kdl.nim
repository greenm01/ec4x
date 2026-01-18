## PlayerState delta generation and KDL formatting

import std/[options, tables, strutils]
import kdl
import ../../../engine/types/[core, colony, fleet, ship, ground_unit, player_state,
  progression, capacity]
import ../../../engine/types/game_state
import ../../../engine/state/fog_of_war
import ../../persistence/player_state_snapshot

# =============================================================================
# Delta Types
# =============================================================================

type
  EntityDelta*[T] = object
    added*: seq[T]
    updated*: seq[T]
    removed*: seq[uint32]

  PlayerStateDelta* = object
    viewingHouse*: HouseId
    turn*: int32
    ownColonies*: EntityDelta[Colony]
    ownFleets*: EntityDelta[Fleet]
    ownShips*: EntityDelta[Ship]
    ownGroundUnits*: EntityDelta[GroundUnit]
    visibleSystems*: EntityDelta[VisibleSystem]
    visibleColonies*: EntityDelta[VisibleColony]
    visibleFleets*: EntityDelta[VisibleFleet]
    housePrestige*: EntityDelta[HouseValue]
    houseColonyCounts*: EntityDelta[HouseCount]
    diplomaticRelations*: EntityDelta[RelationSnapshot]
    eliminatedHouses*: EntityDelta[HouseId]
    actProgressionChanged*: bool
    actProgression*: Option[ActProgressionState]

# =============================================================================
# Delta Builders
# =============================================================================

proc sameEntityId(a: EntityIdUnion, b: EntityIdUnion): bool =
  if a.kind != b.kind:
    return false
  case a.kind
  of FighterSquadron, ConstructionDock:
    a.colonyId == b.colonyId
  of CapitalSquadron, TotalSquadron, PlanetBreaker, FleetCount, C2Pool:
    a.houseId == b.houseId
  of CarrierHangar:
    a.shipId == b.shipId
  of FleetSize:
    a.fleetId == b.fleetId

proc sameCapacityViolation(a: CapacityViolation, b: CapacityViolation): bool =
  a.capacityType == b.capacityType and
    sameEntityId(a.entity, b.entity) and
    a.current == b.current and
    a.maximum == b.maximum and
    a.excess == b.excess and
    a.severity == b.severity and
    a.graceTurnsRemaining == b.graceTurnsRemaining and
    a.violationTurn == b.violationTurn

proc sameGroundUnitGarrison(a: GroundUnitGarrison, b: GroundUnitGarrison): bool =
  if a.locationType != b.locationType:
    return false
  case a.locationType
  of OnColony:
    a.colonyId == b.colonyId
  of OnTransport:
    a.shipId == b.shipId

proc sameGroundUnit(a: GroundUnit, b: GroundUnit): bool =
  a.id == b.id and
    a.houseId == b.houseId and
    a.stats == b.stats and
    a.state == b.state and
    sameGroundUnitGarrison(a.garrison, b.garrison)

proc sameColony(a: Colony, b: Colony): bool =
  a.id == b.id and
    a.systemId == b.systemId and
    a.owner == b.owner and
    a.population == b.population and
    a.souls == b.souls and
    a.populationUnits == b.populationUnits and
    a.populationTransferUnits == b.populationTransferUnits and
    a.infrastructure == b.infrastructure and
    a.industrial == b.industrial and
    a.production == b.production and
    a.grossOutput == b.grossOutput and
    a.taxRate == b.taxRate and
    a.infrastructureDamage == b.infrastructureDamage and
    a.underConstruction == b.underConstruction and
    a.constructionQueue == b.constructionQueue and
    a.repairQueue == b.repairQueue and
    a.activeTerraforming == b.activeTerraforming and
    a.fighterIds == b.fighterIds and
    sameCapacityViolation(a.capacityViolation, b.capacityViolation) and
    a.groundUnitIds == b.groundUnitIds and
    a.neoriaIds == b.neoriaIds and
    a.kastraIds == b.kastraIds and
    a.blockaded == b.blockaded and
    a.blockadedBy == b.blockadedBy and
    a.blockadeTurns == b.blockadeTurns and
    a.autoRepair == b.autoRepair and
    a.autoLoadMarines == b.autoLoadMarines and
    a.autoLoadFighters == b.autoLoadFighters

proc buildIdMap[T, Id](items: seq[T], idFn: proc(item: T): Id): Table[Id, T] =
  result = initTable[Id, T]()
  for item in items:
    result[idFn(item)] = item

proc diffById[T, Id](
  oldItems: seq[T],
  newItems: seq[T],
  idFn: proc(item: T): Id,
  toRemoved: proc(id: Id): uint32,
  equalFn: proc(a: T, b: T): bool
): EntityDelta[T] =
  let oldMap = buildIdMap(oldItems, idFn)
  let newMap = buildIdMap(newItems, idFn)

  for id, newItem in newMap:
    if not oldMap.hasKey(id):
      result.added.add(newItem)
    elif not equalFn(newItem, oldMap[id]):
      result.updated.add(newItem)

  for id, oldItem in oldMap:
    if not newMap.hasKey(id):
      discard oldItem
      result.removed.add(toRemoved(id))

proc diffVisibleSystems(
  oldItems: seq[VisibleSystem],
  newItems: seq[VisibleSystem]
): EntityDelta[VisibleSystem] =
  diffById(
    oldItems,
    newItems,
    proc(item: VisibleSystem): SystemId = item.systemId,
    proc(id: SystemId): uint32 = id.uint32,
    proc(a: VisibleSystem, b: VisibleSystem): bool = a == b
  )

proc diffVisibleColonies(
  oldItems: seq[VisibleColony],
  newItems: seq[VisibleColony]
): EntityDelta[VisibleColony] =
  diffById(
    oldItems,
    newItems,
    proc(item: VisibleColony): ColonyId = item.colonyId,
    proc(id: ColonyId): uint32 = id.uint32,
    proc(a: VisibleColony, b: VisibleColony): bool = a == b
  )

proc diffVisibleFleets(
  oldItems: seq[VisibleFleet],
  newItems: seq[VisibleFleet]
): EntityDelta[VisibleFleet] =
  diffById(
    oldItems,
    newItems,
    proc(item: VisibleFleet): FleetId = item.fleetId,
    proc(id: FleetId): uint32 = id.uint32,
    proc(a: VisibleFleet, b: VisibleFleet): bool = a == b
  )

proc diffHouseValues(
  oldItems: seq[HouseValue],
  newItems: seq[HouseValue]
): EntityDelta[HouseValue] =
  diffById(
    oldItems,
    newItems,
    proc(item: HouseValue): HouseId = item.houseId,
    proc(id: HouseId): uint32 = id.uint32,
    proc(a: HouseValue, b: HouseValue): bool = a.value == b.value
  )

proc diffHouseCounts(
  oldItems: seq[HouseCount],
  newItems: seq[HouseCount]
): EntityDelta[HouseCount] =
  diffById(
    oldItems,
    newItems,
    proc(item: HouseCount): HouseId = item.houseId,
    proc(id: HouseId): uint32 = id.uint32,
    proc(a: HouseCount, b: HouseCount): bool = a.count == b.count
  )

proc relationKey(item: RelationSnapshot): tuple[source: HouseId, target: HouseId] =
  (item.sourceHouse, item.targetHouse)

proc diffRelations(
  oldItems: seq[RelationSnapshot],
  newItems: seq[RelationSnapshot]
): EntityDelta[RelationSnapshot] =
  diffById(
    oldItems,
    newItems,
    relationKey,
    proc(id: tuple[source: HouseId, target: HouseId]): uint32 =
      id.source.uint32 shl 16 or id.target.uint32,
    proc(a: RelationSnapshot, b: RelationSnapshot): bool = a.state == b.state
  )

proc diffHouseIds(
  oldItems: seq[HouseId],
  newItems: seq[HouseId]
): EntityDelta[HouseId] =
  diffById(
    oldItems,
    newItems,
    proc(item: HouseId): HouseId = item,
    proc(id: HouseId): uint32 = id.uint32,
    proc(a: HouseId, b: HouseId): bool = a == b
  )

proc diffColonies(oldItems: seq[Colony], newItems: seq[Colony]): EntityDelta[Colony] =
  diffById(
    oldItems,
    newItems,
    proc(item: Colony): ColonyId = item.id,
    proc(id: ColonyId): uint32 = id.uint32,
    proc(a: Colony, b: Colony): bool = sameColony(a, b)
  )

proc diffFleets(oldItems: seq[Fleet], newItems: seq[Fleet]): EntityDelta[Fleet] =
  diffById(
    oldItems,
    newItems,
    proc(item: Fleet): FleetId = item.id,
    proc(id: FleetId): uint32 = id.uint32,
    proc(a: Fleet, b: Fleet): bool = a == b
  )

proc diffShips(oldItems: seq[Ship], newItems: seq[Ship]): EntityDelta[Ship] =
  diffById(
    oldItems,
    newItems,
    proc(item: Ship): ShipId = item.id,
    proc(id: ShipId): uint32 = id.uint32,
    proc(a: Ship, b: Ship): bool = a == b
  )

proc diffGroundUnits(
  oldItems: seq[GroundUnit],
  newItems: seq[GroundUnit]
): EntityDelta[GroundUnit] =
  diffById(
    oldItems,
    newItems,
    proc(item: GroundUnit): GroundUnitId = item.id,
    proc(id: GroundUnitId): uint32 = id.uint32,
    proc(a: GroundUnit, b: GroundUnit): bool = sameGroundUnit(a, b)
  )

proc diffPlayerState*(
  oldSnapshotOpt: Option[PlayerStateSnapshot],
  current: PlayerStateSnapshot
): PlayerStateDelta =
  result.viewingHouse = current.viewingHouse
  result.turn = current.turn

  if oldSnapshotOpt.isNone:
    result.ownColonies.added = current.ownColonies
    result.ownFleets.added = current.ownFleets
    result.ownShips.added = current.ownShips
    result.ownGroundUnits.added = current.ownGroundUnits
    result.visibleSystems.added = current.visibleSystems
    result.visibleColonies.added = current.visibleColonies
    result.visibleFleets.added = current.visibleFleets
    result.housePrestige.added = current.housePrestige
    result.houseColonyCounts.added = current.houseColonyCounts
    result.diplomaticRelations.added = current.diplomaticRelations
    result.eliminatedHouses.added = current.eliminatedHouses
    result.actProgressionChanged = true
    result.actProgression = some(current.actProgression)
    return

  let oldSnapshot = oldSnapshotOpt.get()
  result.ownColonies = diffColonies(oldSnapshot.ownColonies, current.ownColonies)
  result.ownFleets = diffFleets(oldSnapshot.ownFleets, current.ownFleets)
  result.ownShips = diffShips(oldSnapshot.ownShips, current.ownShips)
  result.ownGroundUnits = diffGroundUnits(
    oldSnapshot.ownGroundUnits,
    current.ownGroundUnits
  )
  result.visibleSystems = diffVisibleSystems(
    oldSnapshot.visibleSystems,
    current.visibleSystems
  )
  result.visibleColonies = diffVisibleColonies(
    oldSnapshot.visibleColonies,
    current.visibleColonies
  )
  result.visibleFleets = diffVisibleFleets(
    oldSnapshot.visibleFleets,
    current.visibleFleets
  )
  result.housePrestige = diffHouseValues(
    oldSnapshot.housePrestige,
    current.housePrestige
  )
  result.houseColonyCounts = diffHouseCounts(
    oldSnapshot.houseColonyCounts,
    current.houseColonyCounts
  )
  result.diplomaticRelations = diffRelations(
    oldSnapshot.diplomaticRelations,
    current.diplomaticRelations
  )
  result.eliminatedHouses = diffHouseIds(
    oldSnapshot.eliminatedHouses,
    current.eliminatedHouses
  )

  if oldSnapshot.actProgression != current.actProgression:
    result.actProgressionChanged = true
    result.actProgression = some(current.actProgression)

# =============================================================================
# KDL Formatting
# =============================================================================

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

proc entryNode(name: string, kind: string, props: Table[string, KdlVal]): KdlNode =
  initKNode(name, args = @[initKVal(kind)], props = props)

proc addFleetCommandProps(props: var Table[string, KdlVal],
  command: FleetCommand) =
  props["command"] = initKVal(kdlEnum($command.commandType))
  if command.targetSystem.isSome:
    props["command-target"] = idVal(command.targetSystem.get())
  if command.targetFleet.isSome:
    props["command-target-fleet"] = idVal(command.targetFleet.get())
  props["command-priority"] = initKVal(command.priority)
  if command.roe.isSome:
    props["command-roe"] = initKVal(command.roe.get())

proc addColonyProps(props: var Table[string, KdlVal], colony: Colony) =
  props["id"] = idVal(colony.id)
  props["system"] = idVal(colony.systemId)
  props["owner"] = idVal(colony.owner)
  props["population"] = initKVal(colony.population)
  props["souls"] = initKVal(colony.souls)
  props["population-units"] = initKVal(colony.populationUnits)
  props["population-transfer-units"] = initKVal(colony.populationTransferUnits)
  props["infrastructure"] = initKVal(colony.infrastructure)
  props["industrial-units"] = initKVal(colony.industrial.units)
  props["industrial-investment"] = initKVal(colony.industrial.investmentCost)
  props["production"] = initKVal(colony.production)
  props["gross-output"] = initKVal(colony.grossOutput)
  props["tax-rate"] = initKVal(colony.taxRate)
  props["infrastructure-damage"] = initKVal(colony.infrastructureDamage)
  if colony.underConstruction.isSome:
    props["under-construction"] = idVal(colony.underConstruction.get())
  if colony.capacityViolation.capacityType != CapacityType.FighterSquadron or
      colony.capacityViolation.maximum != 0 or
      colony.capacityViolation.current != 0 or
      colony.capacityViolation.excess != 0 or
      colony.capacityViolation.severity != ViolationSeverity.None or
      colony.capacityViolation.graceTurnsRemaining != 0 or
      colony.capacityViolation.violationTurn != 0:
    props["capacity-violation-type"] = initKVal(
      kdlEnum($colony.capacityViolation.capacityType))
    props["capacity-violation-current"] = initKVal(
      colony.capacityViolation.current)
    props["capacity-violation-maximum"] = initKVal(
      colony.capacityViolation.maximum)
    props["capacity-violation-excess"] = initKVal(
      colony.capacityViolation.excess)
    props["capacity-violation-severity"] = initKVal(
      kdlEnum($colony.capacityViolation.severity))
    props["capacity-violation-grace"] = initKVal(
      colony.capacityViolation.graceTurnsRemaining)
    props["capacity-violation-turn"] = initKVal(
      colony.capacityViolation.violationTurn)
    case colony.capacityViolation.entity.kind
    of CapacityType.FighterSquadron, CapacityType.ConstructionDock:
      props["capacity-violation-colony"] = idVal(
        colony.capacityViolation.entity.colonyId)
    of CapacityType.CapitalSquadron, CapacityType.TotalSquadron,
       CapacityType.PlanetBreaker, CapacityType.FleetCount, CapacityType.C2Pool:
      props["capacity-violation-house"] = idVal(
        colony.capacityViolation.entity.houseId)
    of CapacityType.CarrierHangar:
      props["capacity-violation-ship"] = idVal(
        colony.capacityViolation.entity.shipId)
    of CapacityType.FleetSize:
      props["capacity-violation-fleet"] = idVal(
        colony.capacityViolation.entity.fleetId)
  if colony.activeTerraforming.isSome:
    let terra = colony.activeTerraforming.get()
    props["terraforming-start"] = initKVal(terra.startTurn)
    props["terraforming-remaining"] = initKVal(terra.turnsRemaining)
    props["terraforming-class"] = initKVal(terra.targetClass)
    props["terraforming-cost"] = initKVal(terra.ppCost)
    props["terraforming-paid"] = initKVal(terra.ppPaid)
  props["blockaded"] = initKVal(colony.blockaded)
  props["blockade-turns"] = initKVal(colony.blockadeTurns)
  props["auto-repair"] = initKVal(colony.autoRepair)
  props["auto-load-marines"] = initKVal(colony.autoLoadMarines)
  props["auto-load-fighters"] = initKVal(colony.autoLoadFighters)

proc addColonyChildren(node: var KdlNode, colony: Colony) =
  if colony.constructionQueue.len > 0:
    var args: seq[KdlVal] = @[]
    for projectId in colony.constructionQueue:
      args.add(idVal(projectId))
    node.children.add(initKNode("construction-queue", args = args))
  if colony.repairQueue.len > 0:
    var args: seq[KdlVal] = @[]
    for projectId in colony.repairQueue:
      args.add(idVal(projectId))
    node.children.add(initKNode("repair-queue", args = args))
  if colony.fighterIds.len > 0:
    var args: seq[KdlVal] = @[]
    for fighterId in colony.fighterIds:
      args.add(idVal(fighterId))
    node.children.add(initKNode("fighters", args = args))
  if colony.groundUnitIds.len > 0:
    var args: seq[KdlVal] = @[]
    for unitId in colony.groundUnitIds:
      args.add(idVal(unitId))
    node.children.add(initKNode("ground-units", args = args))
  if colony.neoriaIds.len > 0:
    var args: seq[KdlVal] = @[]
    for neoriaId in colony.neoriaIds:
      args.add(idVal(neoriaId))
    node.children.add(initKNode("neorias", args = args))
  if colony.kastraIds.len > 0:
    var args: seq[KdlVal] = @[]
    for kastraId in colony.kastraIds:
      args.add(idVal(kastraId))
    node.children.add(initKNode("kastras", args = args))
  if colony.blockadedBy.len > 0:
    var args: seq[KdlVal] = @[]
    for houseId in colony.blockadedBy:
      args.add(idVal(houseId))
    node.children.add(initKNode("blockaded-by", args = args))

proc addFleetProps(props: var Table[string, KdlVal], fleet: Fleet) =
  props["id"] = idVal(fleet.id)
  props["owner"] = idVal(fleet.houseId)
  props["location"] = idVal(fleet.location)
  props["status"] = initKVal(kdlEnum($fleet.status))
  props["roe"] = initKVal(fleet.roe)
  props["mission-state"] = initKVal(kdlEnum($fleet.missionState))
  if fleet.missionTarget.isSome:
    props["mission-target"] = idVal(fleet.missionTarget.get())
  props["mission-start-turn"] = initKVal(fleet.missionStartTurn)
  addFleetCommandProps(props, fleet.command)

proc addFleetChildren(node: var KdlNode, fleet: Fleet) =
  if fleet.ships.len > 0:
    var args: seq[KdlVal] = @[]
    for shipId in fleet.ships:
      args.add(idVal(shipId))
    node.children.add(initKNode("ships", args = args))

proc addShipProps(props: var Table[string, KdlVal], ship: Ship) =
  props["id"] = idVal(ship.id)
  props["house"] = idVal(ship.houseId)
  props["fleet"] = idVal(ship.fleetId)
  props["class"] = initKVal(kdlEnum($ship.shipClass))
  props["state"] = initKVal(kdlEnum($ship.state))
  props["attack"] = initKVal(ship.stats.attackStrength)
  props["defense"] = initKVal(ship.stats.defenseStrength)
  props["wep"] = initKVal(ship.stats.wep)
  if ship.cargo.isSome:
    let cargo = ship.cargo.get()
    props["cargo-type"] = initKVal(kdlEnum($cargo.cargoType))
    props["cargo-quantity"] = initKVal(cargo.quantity)
    props["cargo-capacity"] = initKVal(cargo.capacity)
  if ship.assignedToCarrier.isSome:
    props["assigned-to"] = idVal(ship.assignedToCarrier.get())

proc addShipChildren(node: var KdlNode, ship: Ship) =
  if ship.embarkedFighters.len > 0:
    var args: seq[KdlVal] = @[]
    for fighterId in ship.embarkedFighters:
      args.add(idVal(fighterId))
    node.children.add(initKNode("embarked-fighters", args = args))

proc addGroundUnitProps(props: var Table[string, KdlVal], unit: GroundUnit) =
  props["id"] = idVal(unit.id)
  props["house"] = idVal(unit.houseId)
  props["type"] = initKVal(kdlEnum($unit.stats.unitType))
  props["attack"] = initKVal(unit.stats.attackStrength)
  props["defense"] = initKVal(unit.stats.defenseStrength)
  props["state"] = initKVal(kdlEnum($unit.state))
  case unit.garrison.locationType
  of GroundUnitLocation.OnColony:
    props["colony"] = idVal(unit.garrison.colonyId)
  of GroundUnitLocation.OnTransport:
    props["transport"] = idVal(unit.garrison.shipId)

proc addVisibleSystemProps(props: var Table[string, KdlVal], system: VisibleSystem) =
  props["id"] = idVal(system.systemId)
  props["visibility"] = initKVal(kdlEnum($system.visibility))
  if system.lastScoutedTurn.isSome:
    props["last-scouted"] = initKVal(system.lastScoutedTurn.get())
  if system.coordinates.isSome:
    let coords = system.coordinates.get()
    props["coord-q"] = initKVal(coords.q)
    props["coord-r"] = initKVal(coords.r)

proc addVisibleSystemChildren(node: var KdlNode, system: VisibleSystem) =
  if system.jumpLaneIds.len > 0:
    var args: seq[KdlVal] = @[]
    for laneId in system.jumpLaneIds:
      args.add(idVal(laneId))
    node.children.add(initKNode("lanes", args = args))

proc addVisibleColonyProps(props: var Table[string, KdlVal], colony: VisibleColony) =
  props["id"] = idVal(colony.colonyId)
  props["system"] = idVal(colony.systemId)
  props["owner"] = idVal(colony.owner)
  if colony.intelTurn.isSome:
    props["intel-turn"] = initKVal(colony.intelTurn.get())
  if colony.estimatedPopulation.isSome:
    props["estimated-population"] = initKVal(colony.estimatedPopulation.get())
  if colony.estimatedIndustry.isSome:
    props["estimated-industry"] = initKVal(colony.estimatedIndustry.get())
  if colony.estimatedDefenses.isSome:
    props["estimated-defenses"] = initKVal(colony.estimatedDefenses.get())
  if colony.starbaseLevel.isSome:
    props["starbase-level"] = initKVal(colony.starbaseLevel.get())
  if colony.unassignedSquadronCount.isSome:
    props["unassigned-squadrons"] = initKVal(
      colony.unassignedSquadronCount.get())
  if colony.reserveFleetCount.isSome:
    props["reserve-fleet-count"] = initKVal(colony.reserveFleetCount.get())
  if colony.mothballedFleetCount.isSome:
    props["mothballed-fleet-count"] = initKVal(
      colony.mothballedFleetCount.get())
  if colony.shipyardCount.isSome:
    props["shipyard-count"] = initKVal(colony.shipyardCount.get())

proc addVisibleFleetProps(props: var Table[string, KdlVal], fleet: VisibleFleet) =
  props["id"] = idVal(fleet.fleetId)
  props["owner"] = idVal(fleet.owner)
  props["location"] = idVal(fleet.location)
  if fleet.intelTurn.isSome:
    props["detected-turn"] = initKVal(fleet.intelTurn.get())
  if fleet.estimatedShipCount.isSome:
    props["estimated-ships"] = initKVal(fleet.estimatedShipCount.get())
  if fleet.detectedInSystem.isSome:
    props["detected-system"] = idVal(fleet.detectedInSystem.get())

proc formatColonies(delta: EntityDelta[Colony]): Option[KdlNode] =
  if delta.added.len == 0 and delta.updated.len == 0 and delta.removed.len == 0:
    return none(KdlNode)

  var node = initKNode("colonies")
  for colony in delta.added:
    var props = initTable[string, KdlVal]()
    addColonyProps(props, colony)
    var entry = entryNode("added", "colony", props)
    addColonyChildren(entry, colony)
    node.children.add(entry)
  for colony in delta.updated:
    var props = initTable[string, KdlVal]()
    addColonyProps(props, colony)
    var entry = entryNode("updated", "colony", props)
    addColonyChildren(entry, colony)
    node.children.add(entry)
  for colonyId in delta.removed:
    var props = initTable[string, KdlVal]()
    props["id"] = initKVal(colonyId, some("ColonyId"))
    node.children.add(entryNode("removed", "colony", props))

  some(node)

proc formatFleets(delta: EntityDelta[Fleet]): Option[KdlNode] =
  if delta.added.len == 0 and delta.updated.len == 0 and delta.removed.len == 0:
    return none(KdlNode)

  var node = initKNode("fleets")
  for fleet in delta.added:
    var props = initTable[string, KdlVal]()
    addFleetProps(props, fleet)
    var entry = entryNode("added", "fleet", props)
    addFleetChildren(entry, fleet)
    node.children.add(entry)
  for fleet in delta.updated:
    var props = initTable[string, KdlVal]()
    addFleetProps(props, fleet)
    var entry = entryNode("updated", "fleet", props)
    addFleetChildren(entry, fleet)
    node.children.add(entry)
  for fleetId in delta.removed:
    var props = initTable[string, KdlVal]()
    props["id"] = initKVal(fleetId, some("FleetId"))
    node.children.add(entryNode("removed", "fleet", props))

  some(node)

proc formatShips(delta: EntityDelta[Ship]): Option[KdlNode] =
  if delta.added.len == 0 and delta.updated.len == 0 and delta.removed.len == 0:
    return none(KdlNode)

  var node = initKNode("ships")
  for ship in delta.added:
    var props = initTable[string, KdlVal]()
    addShipProps(props, ship)
    var entry = entryNode("added", "ship", props)
    addShipChildren(entry, ship)
    node.children.add(entry)
  for ship in delta.updated:
    var props = initTable[string, KdlVal]()
    addShipProps(props, ship)
    var entry = entryNode("updated", "ship", props)
    addShipChildren(entry, ship)
    node.children.add(entry)
  for shipId in delta.removed:
    var props = initTable[string, KdlVal]()
    props["id"] = initKVal(shipId, some("ShipId"))
    node.children.add(entryNode("removed", "ship", props))

  some(node)

proc formatGroundUnits(delta: EntityDelta[GroundUnit]): Option[KdlNode] =
  if delta.added.len == 0 and delta.updated.len == 0 and delta.removed.len == 0:
    return none(KdlNode)

  var node = initKNode("ground-units")
  for unit in delta.added:
    var props = initTable[string, KdlVal]()
    addGroundUnitProps(props, unit)
    node.children.add(entryNode("added", "unit", props))
  for unit in delta.updated:
    var props = initTable[string, KdlVal]()
    addGroundUnitProps(props, unit)
    node.children.add(entryNode("updated", "unit", props))
  for unitId in delta.removed:
    var props = initTable[string, KdlVal]()
    props["id"] = initKVal(unitId, some("GroundUnitId"))
    node.children.add(entryNode("removed", "unit", props))

  some(node)

proc formatVisibleSystems(delta: EntityDelta[VisibleSystem]): Option[KdlNode] =
  if delta.added.len == 0 and delta.updated.len == 0 and delta.removed.len == 0:
    return none(KdlNode)

  var node = initKNode("visible-systems")
  for system in delta.added:
    var props = initTable[string, KdlVal]()
    addVisibleSystemProps(props, system)
    var entry = entryNode("added", "system", props)
    addVisibleSystemChildren(entry, system)
    node.children.add(entry)
  for system in delta.updated:
    var props = initTable[string, KdlVal]()
    addVisibleSystemProps(props, system)
    var entry = entryNode("updated", "system", props)
    addVisibleSystemChildren(entry, system)
    node.children.add(entry)
  for systemId in delta.removed:
    var props = initTable[string, KdlVal]()
    props["id"] = initKVal(systemId, some("SystemId"))
    node.children.add(entryNode("removed", "system", props))

  some(node)

proc formatVisibleColonies(delta: EntityDelta[VisibleColony]): Option[KdlNode] =
  if delta.added.len == 0 and delta.updated.len == 0 and delta.removed.len == 0:
    return none(KdlNode)

  var node = initKNode("visible-colonies")
  for colony in delta.added:
    var props = initTable[string, KdlVal]()
    addVisibleColonyProps(props, colony)
    node.children.add(entryNode("added", "colony", props))
  for colony in delta.updated:
    var props = initTable[string, KdlVal]()
    addVisibleColonyProps(props, colony)
    node.children.add(entryNode("updated", "colony", props))
  for colonyId in delta.removed:
    var props = initTable[string, KdlVal]()
    props["id"] = initKVal(colonyId, some("ColonyId"))
    node.children.add(entryNode("removed", "colony", props))

  some(node)

proc formatVisibleFleets(delta: EntityDelta[VisibleFleet]): Option[KdlNode] =
  if delta.added.len == 0 and delta.updated.len == 0 and delta.removed.len == 0:
    return none(KdlNode)

  var node = initKNode("visible-fleets")
  for fleet in delta.added:
    var props = initTable[string, KdlVal]()
    addVisibleFleetProps(props, fleet)
    node.children.add(entryNode("added", "fleet", props))
  for fleet in delta.updated:
    var props = initTable[string, KdlVal]()
    addVisibleFleetProps(props, fleet)
    node.children.add(entryNode("updated", "fleet", props))
  for fleetId in delta.removed:
    var props = initTable[string, KdlVal]()
    props["id"] = initKVal(fleetId, some("FleetId"))
    node.children.add(entryNode("removed", "fleet", props))

  some(node)

proc formatHousePrestige(delta: EntityDelta[HouseValue]): Option[KdlNode] =
  if delta.added.len == 0 and delta.updated.len == 0 and delta.removed.len == 0:
    return none(KdlNode)

  var node = initKNode("house-prestige")
  for entry in delta.added:
    var props = initTable[string, KdlVal]()
    props["house"] = idVal(entry.houseId)
    props["value"] = initKVal(entry.value)
    node.children.add(entryNode("added", "prestige", props))
  for entry in delta.updated:
    var props = initTable[string, KdlVal]()
    props["house"] = idVal(entry.houseId)
    props["value"] = initKVal(entry.value)
    node.children.add(entryNode("updated", "prestige", props))
  for houseId in delta.removed:
    var props = initTable[string, KdlVal]()
    props["house"] = initKVal(houseId, some("HouseId"))
    node.children.add(entryNode("removed", "prestige", props))

  some(node)

proc formatHouseColonyCounts(delta: EntityDelta[HouseCount]): Option[KdlNode] =
  if delta.added.len == 0 and delta.updated.len == 0 and delta.removed.len == 0:
    return none(KdlNode)

  var node = initKNode("house-colony-counts")
  for entry in delta.added:
    var props = initTable[string, KdlVal]()
    props["house"] = idVal(entry.houseId)
    props["count"] = initKVal(entry.count)
    node.children.add(entryNode("added", "count", props))
  for entry in delta.updated:
    var props = initTable[string, KdlVal]()
    props["house"] = idVal(entry.houseId)
    props["count"] = initKVal(entry.count)
    node.children.add(entryNode("updated", "count", props))
  for houseId in delta.removed:
    var props = initTable[string, KdlVal]()
    props["house"] = initKVal(houseId, some("HouseId"))
    node.children.add(entryNode("removed", "count", props))

  some(node)

proc formatDiplomaticRelations(
  delta: EntityDelta[RelationSnapshot]
): Option[KdlNode] =
  if delta.added.len == 0 and delta.updated.len == 0 and delta.removed.len == 0:
    return none(KdlNode)

  var node = initKNode("diplomacy")
  for entry in delta.added:
    var props = initTable[string, KdlVal]()
    props["from"] = idVal(entry.sourceHouse)
    props["to"] = idVal(entry.targetHouse)
    props["state"] = initKVal(kdlEnum($entry.state))
    node.children.add(entryNode("added", "relation", props))
  for entry in delta.updated:
    var props = initTable[string, KdlVal]()
    props["from"] = idVal(entry.sourceHouse)
    props["to"] = idVal(entry.targetHouse)
    props["state"] = initKVal(kdlEnum($entry.state))
    node.children.add(entryNode("updated", "relation", props))
  for relationId in delta.removed:
    let sourceId = relationId shr 16
    let targetId = relationId and 0xFFFF'u32
    var props = initTable[string, KdlVal]()
    props["from"] = initKVal(sourceId, some("HouseId"))
    props["to"] = initKVal(targetId, some("HouseId"))
    node.children.add(entryNode("removed", "relation", props))

  some(node)

proc formatEliminatedHouses(delta: EntityDelta[HouseId]): Option[KdlNode] =
  if delta.added.len == 0 and delta.updated.len == 0 and delta.removed.len == 0:
    return none(KdlNode)

  var node = initKNode("eliminated-houses")
  for houseId in delta.added:
    var props = initTable[string, KdlVal]()
    props["house"] = idVal(houseId)
    node.children.add(entryNode("added", "house", props))
  for houseId in delta.removed:
    var props = initTable[string, KdlVal]()
    props["house"] = initKVal(houseId, some("HouseId"))
    node.children.add(entryNode("removed", "house", props))

  some(node)

proc formatActProgression(delta: PlayerStateDelta): Option[KdlNode] =
  if not delta.actProgressionChanged or delta.actProgression.isNone:
    return none(KdlNode)

  let progression = delta.actProgression.get()
  var node = initKNode("act-progression")
  node.children.add(
    nodeWithArg("current-act", initKVal(kdlEnum($progression.currentAct)))
  )
  node.children.add(
    nodeWithArg("act-start-turn", initKVal(progression.actStartTurn))
  )
  node.children.add(
    nodeWithArg("colonization-percent", initKVal(
      progression.lastColonizationPercent
    ))
  )
  node.children.add(
    nodeWithArg("total-prestige", initKVal(
      progression.lastTotalPrestige
    ))
  )
  if progression.act2TopThreeHouses.len > 0:
    var houseArgs: seq[KdlVal] = @[]
    for houseId in progression.act2TopThreeHouses:
      houseArgs.add(idVal(houseId))
    node.children.add(initKNode("act2-top-houses", args = houseArgs))
  if progression.act2TopThreePrestige.len > 0:
    var prestigeArgs: seq[KdlVal] = @[]
    for value in progression.act2TopThreePrestige:
      prestigeArgs.add(initKVal(value))
    node.children.add(initKNode("act2-top-prestige", args = prestigeArgs))

  some(node)

proc formatPlayerStateDeltaKdl*(
  gameId: string,
  delta: PlayerStateDelta
): string =
  var props = initTable[string, KdlVal]()
  props["version"] = initKVal(1)
  props["turn"] = initKVal(delta.turn)
  props["game"] = initKVal(gameId)
  props["house"] = idVal(delta.viewingHouse)

  var root = initKNode("delta", props = props)

  let coloniesOpt = formatColonies(delta.ownColonies)
  if coloniesOpt.isSome:
    root.children.add(coloniesOpt.get())

  let fleetsOpt = formatFleets(delta.ownFleets)
  if fleetsOpt.isSome:
    root.children.add(fleetsOpt.get())

  let shipsOpt = formatShips(delta.ownShips)
  if shipsOpt.isSome:
    root.children.add(shipsOpt.get())

  let unitsOpt = formatGroundUnits(delta.ownGroundUnits)
  if unitsOpt.isSome:
    root.children.add(unitsOpt.get())

  let systemsOpt = formatVisibleSystems(delta.visibleSystems)
  if systemsOpt.isSome:
    root.children.add(systemsOpt.get())

  let visibleColoniesOpt = formatVisibleColonies(delta.visibleColonies)
  if visibleColoniesOpt.isSome:
    root.children.add(visibleColoniesOpt.get())

  let visibleFleetsOpt = formatVisibleFleets(delta.visibleFleets)
  if visibleFleetsOpt.isSome:
    root.children.add(visibleFleetsOpt.get())

  let prestigeOpt = formatHousePrestige(delta.housePrestige)
  if prestigeOpt.isSome:
    root.children.add(prestigeOpt.get())

  let countsOpt = formatHouseColonyCounts(delta.houseColonyCounts)
  if countsOpt.isSome:
    root.children.add(countsOpt.get())

  let diplomacyOpt = formatDiplomaticRelations(delta.diplomaticRelations)
  if diplomacyOpt.isSome:
    root.children.add(diplomacyOpt.get())

  let eliminatedOpt = formatEliminatedHouses(delta.eliminatedHouses)
  if eliminatedOpt.isSome:
    root.children.add(eliminatedOpt.get())

  let actOpt = formatActProgression(delta)
  if actOpt.isSome:
    root.children.add(actOpt.get())

  let doc: KdlDoc = @[root]
  doc.pretty()

# =============================================================================
# Snapshot Helpers
# =============================================================================

proc buildPlayerStateSnapshot*(
  state: GameState,
  houseId: HouseId
): PlayerStateSnapshot =
  let playerState = createPlayerState(state, houseId)
  snapshotFromPlayerState(playerState)
