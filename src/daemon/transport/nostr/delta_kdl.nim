## PlayerState delta generation and KDL formatting

import std/[options, tables, strutils, json, jsonutils]
import ../../../engine/types/[core, colony, fleet, ship, ground_unit, player_state,
  progression]
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
    proc(a: Colony, b: Colony): bool = $toJson(a) == $toJson(b)
  )

proc diffFleets(oldItems: seq[Fleet], newItems: seq[Fleet]): EntityDelta[Fleet] =
  diffById(
    oldItems,
    newItems,
    proc(item: Fleet): FleetId = item.id,
    proc(id: FleetId): uint32 = id.uint32,
    proc(a: Fleet, b: Fleet): bool = $toJson(a) == $toJson(b)
  )

proc diffShips(oldItems: seq[Ship], newItems: seq[Ship]): EntityDelta[Ship] =
  diffById(
    oldItems,
    newItems,
    proc(item: Ship): ShipId = item.id,
    proc(id: ShipId): uint32 = id.uint32,
    proc(a: Ship, b: Ship): bool = $toJson(a) == $toJson(b)
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
    proc(a: GroundUnit, b: GroundUnit): bool = $toJson(a) == $toJson(b)
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
  result.ownGroundUnits = diffGroundUnits(oldSnapshot.ownGroundUnits, current.ownGroundUnits)
  result.visibleSystems = diffVisibleSystems(oldSnapshot.visibleSystems, current.visibleSystems)
  result.visibleColonies = diffVisibleColonies(oldSnapshot.visibleColonies, current.visibleColonies)
  result.visibleFleets = diffVisibleFleets(oldSnapshot.visibleFleets, current.visibleFleets)
  result.housePrestige = diffHouseValues(oldSnapshot.housePrestige, current.housePrestige)
  result.houseColonyCounts = diffHouseCounts(oldSnapshot.houseColonyCounts, current.houseColonyCounts)
  result.diplomaticRelations = diffRelations(oldSnapshot.diplomaticRelations, current.diplomaticRelations)
  result.eliminatedHouses = diffHouseIds(oldSnapshot.eliminatedHouses, current.eliminatedHouses)

  if oldSnapshot.actProgression != current.actProgression:
    result.actProgressionChanged = true
    result.actProgression = some(current.actProgression)

# =============================================================================
# KDL Formatting
# =============================================================================

proc kdlEsc(value: string): string =
  value.multiReplace({
    "\\": "\\\\",
    "\"": "\\\"",
    "\n": "\\n",
    "\r": "\\r",
    "\t": "\\t",
  })

proc kdlString(value: string): string =
  "\"" & kdlEsc(value) & "\""

proc addLine(lines: var seq[string], indent: int, content: string) =
  lines.add("  ".repeat(indent) & content)

proc formatColonies(delta: EntityDelta[Colony], lines: var seq[string], indent: int) =
  if delta.added.len == 0 and delta.updated.len == 0 and delta.removed.len == 0:
    return

  addLine(lines, indent, "colonies {")
  for colony in delta.added:
    addLine(lines, indent + 1,
      "added colony id=(ColonyId)" & $colony.id.uint32 &
      " system=(SystemId)" & $colony.systemId.uint32 &
      " owner=(HouseId)" & $colony.owner.uint32 &
      " population=" & $colony.population &
      " industry=" & $colony.industrial.units &
      " tax-rate=" & $colony.taxRate &
      " under-siege=" & $(colony.blockaded))
  for colony in delta.updated:
    addLine(lines, indent + 1,
      "updated colony id=(ColonyId)" & $colony.id.uint32 &
      " system=(SystemId)" & $colony.systemId.uint32 &
      " owner=(HouseId)" & $colony.owner.uint32 &
      " population=" & $colony.population &
      " industry=" & $colony.industrial.units &
      " tax-rate=" & $colony.taxRate &
      " under-siege=" & $(colony.blockaded))
  for colonyId in delta.removed:
    addLine(lines, indent + 1,
      "removed colony id=(ColonyId)" & $colonyId)
  addLine(lines, indent, "}")

proc formatFleets(delta: EntityDelta[Fleet], lines: var seq[string], indent: int) =
  if delta.added.len == 0 and delta.updated.len == 0 and delta.removed.len == 0:
    return

  addLine(lines, indent, "fleets {")
  for fleet in delta.added:
    addLine(lines, indent + 1,
      "added fleet id=(FleetId)" & $fleet.id.uint32 &
      " owner=(HouseId)" & $fleet.houseId.uint32 &
      " location=(SystemId)" & $fleet.location.uint32 &
      " status=" & $fleet.status)
  for fleet in delta.updated:
    addLine(lines, indent + 1,
      "updated fleet id=(FleetId)" & $fleet.id.uint32 &
      " owner=(HouseId)" & $fleet.houseId.uint32 &
      " location=(SystemId)" & $fleet.location.uint32 &
      " status=" & $fleet.status)
  for fleetId in delta.removed:
    addLine(lines, indent + 1,
      "removed fleet id=(FleetId)" & $fleetId)
  addLine(lines, indent, "}")

proc formatShips(delta: EntityDelta[Ship], lines: var seq[string], indent: int) =
  if delta.added.len == 0 and delta.updated.len == 0 and delta.removed.len == 0:
    return

  addLine(lines, indent, "ships {")
  for ship in delta.added:
    addLine(lines, indent + 1,
      "added ship id=(ShipId)" & $ship.id.uint32 &
      " class=" & $ship.shipClass &
      " house=(HouseId)" & $ship.houseId.uint32 &
      " fleet=(FleetId)" & $ship.fleetId.uint32)
  for ship in delta.updated:
    addLine(lines, indent + 1,
      "updated ship id=(ShipId)" & $ship.id.uint32 &
      " class=" & $ship.shipClass &
      " house=(HouseId)" & $ship.houseId.uint32 &
      " fleet=(FleetId)" & $ship.fleetId.uint32)
  for shipId in delta.removed:
    addLine(lines, indent + 1,
      "removed ship id=(ShipId)" & $shipId)
  addLine(lines, indent, "}")

proc formatGroundUnits(
  delta: EntityDelta[GroundUnit],
  lines: var seq[string],
  indent: int
) =
  if delta.added.len == 0 and delta.updated.len == 0 and delta.removed.len == 0:
    return

  addLine(lines, indent, "ground-units {")
  for unit in delta.added:
    var locationInfo = ""
    case unit.garrison.locationType
    of GroundUnitLocation.OnColony:
      locationInfo = " colony=(ColonyId)" & $unit.garrison.colonyId.uint32
    of GroundUnitLocation.OnTransport:
      locationInfo = " transport=(ShipId)" & $unit.garrison.shipId.uint32
    addLine(lines, indent + 1,
      "added unit id=(GroundUnitId)" & $unit.id.uint32 &
      " house=(HouseId)" & $unit.houseId.uint32 &
      " type=" & $unit.stats.unitType &
      locationInfo)
  for unit in delta.updated:
    var locationInfo = ""
    case unit.garrison.locationType
    of GroundUnitLocation.OnColony:
      locationInfo = " colony=(ColonyId)" & $unit.garrison.colonyId.uint32
    of GroundUnitLocation.OnTransport:
      locationInfo = " transport=(ShipId)" & $unit.garrison.shipId.uint32
    addLine(lines, indent + 1,
      "updated unit id=(GroundUnitId)" & $unit.id.uint32 &
      " house=(HouseId)" & $unit.houseId.uint32 &
      " type=" & $unit.stats.unitType &
      locationInfo)
  for unitId in delta.removed:
    addLine(lines, indent + 1,
      "removed unit id=(GroundUnitId)" & $unitId)
  addLine(lines, indent, "}")

proc formatVisibleSystems(
  delta: EntityDelta[VisibleSystem],
  lines: var seq[string],
  indent: int
) =
  if delta.added.len == 0 and delta.updated.len == 0 and delta.removed.len == 0:
    return

  addLine(lines, indent, "visible-systems {")
  for system in delta.added:
    addLine(lines, indent + 1,
      "added system id=(SystemId)" & $system.systemId.uint32 &
      " visibility=" & $system.visibility)
  for system in delta.updated:
    addLine(lines, indent + 1,
      "updated system id=(SystemId)" & $system.systemId.uint32 &
      " visibility=" & $system.visibility)
  for systemId in delta.removed:
    addLine(lines, indent + 1,
      "removed system id=(SystemId)" & $systemId)
  addLine(lines, indent, "}")

proc formatVisibleColonies(
  delta: EntityDelta[VisibleColony],
  lines: var seq[string],
  indent: int
) =
  if delta.added.len == 0 and delta.updated.len == 0 and delta.removed.len == 0:
    return

  addLine(lines, indent, "visible-colonies {")
  for colony in delta.added:
    addLine(lines, indent + 1,
      "added colony id=(ColonyId)" & $colony.colonyId.uint32 &
      " system=(SystemId)" & $colony.systemId.uint32 &
      " owner=(HouseId)" & $colony.owner.uint32)
  for colony in delta.updated:
    addLine(lines, indent + 1,
      "updated colony id=(ColonyId)" & $colony.colonyId.uint32 &
      " system=(SystemId)" & $colony.systemId.uint32 &
      " owner=(HouseId)" & $colony.owner.uint32)
  for colonyId in delta.removed:
    addLine(lines, indent + 1,
      "removed colony id=(ColonyId)" & $colonyId)
  addLine(lines, indent, "}")

proc formatVisibleFleets(
  delta: EntityDelta[VisibleFleet],
  lines: var seq[string],
  indent: int
) =
  if delta.added.len == 0 and delta.updated.len == 0 and delta.removed.len == 0:
    return

  addLine(lines, indent, "visible-fleets {")
  for fleet in delta.added:
    addLine(lines, indent + 1,
      "added fleet id=(FleetId)" & $fleet.fleetId.uint32 &
      " owner=(HouseId)" & $fleet.owner.uint32 &
      " location=(SystemId)" & $fleet.location.uint32)
  for fleet in delta.updated:
    addLine(lines, indent + 1,
      "updated fleet id=(FleetId)" & $fleet.fleetId.uint32 &
      " owner=(HouseId)" & $fleet.owner.uint32 &
      " location=(SystemId)" & $fleet.location.uint32)
  for fleetId in delta.removed:
    addLine(lines, indent + 1,
      "removed fleet id=(FleetId)" & $fleetId)
  addLine(lines, indent, "}")

proc formatHousePrestige(
  delta: EntityDelta[HouseValue],
  lines: var seq[string],
  indent: int
) =
  if delta.added.len == 0 and delta.updated.len == 0 and delta.removed.len == 0:
    return

  addLine(lines, indent, "house-prestige {")
  for entry in delta.added:
    addLine(lines, indent + 1,
      "added house=(HouseId)" & $entry.houseId.uint32 & " value=" & $entry.value)
  for entry in delta.updated:
    addLine(lines, indent + 1,
      "updated house=(HouseId)" & $entry.houseId.uint32 & " value=" & $entry.value)
  for houseId in delta.removed:
    addLine(lines, indent + 1,
      "removed house=(HouseId)" & $houseId)
  addLine(lines, indent, "}")

proc formatHouseColonyCounts(
  delta: EntityDelta[HouseCount],
  lines: var seq[string],
  indent: int
) =
  if delta.added.len == 0 and delta.updated.len == 0 and delta.removed.len == 0:
    return

  addLine(lines, indent, "house-colony-counts {")
  for entry in delta.added:
    addLine(lines, indent + 1,
      "added house=(HouseId)" & $entry.houseId.uint32 & " count=" & $entry.count)
  for entry in delta.updated:
    addLine(lines, indent + 1,
      "updated house=(HouseId)" & $entry.houseId.uint32 & " count=" & $entry.count)
  for houseId in delta.removed:
    addLine(lines, indent + 1,
      "removed house=(HouseId)" & $houseId)
  addLine(lines, indent, "}")

proc formatDiplomaticRelations(
  delta: EntityDelta[RelationSnapshot],
  lines: var seq[string],
  indent: int
) =
  if delta.added.len == 0 and delta.updated.len == 0 and delta.removed.len == 0:
    return

  addLine(lines, indent, "diplomacy {")
  for entry in delta.added:
    addLine(lines, indent + 1,
      "added from=(HouseId)" & $entry.sourceHouse.uint32 &
      " to=(HouseId)" & $entry.targetHouse.uint32 &
      " state=" & $entry.state)
  for entry in delta.updated:
    addLine(lines, indent + 1,
      "updated from=(HouseId)" & $entry.sourceHouse.uint32 &
      " to=(HouseId)" & $entry.targetHouse.uint32 &
      " state=" & $entry.state)
  for relationId in delta.removed:
    let sourceId = relationId shr 16
    let targetId = relationId and 0xFFFF'u32
    addLine(lines, indent + 1,
      "removed from=(HouseId)" & $sourceId &
      " to=(HouseId)" & $targetId)
  addLine(lines, indent, "}")

proc formatEliminatedHouses(
  delta: EntityDelta[HouseId],
  lines: var seq[string],
  indent: int
) =
  if delta.added.len == 0 and delta.updated.len == 0 and delta.removed.len == 0:
    return

  addLine(lines, indent, "eliminated-houses {")
  for houseId in delta.added:
    addLine(lines, indent + 1,
      "added house=(HouseId)" & $houseId.uint32)
  for houseId in delta.removed:
    addLine(lines, indent + 1,
      "removed house=(HouseId)" & $houseId.uint32)
  addLine(lines, indent, "}")

proc formatActProgression(
  delta: PlayerStateDelta,
  lines: var seq[string],
  indent: int
) =
  if not delta.actProgressionChanged or delta.actProgression.isNone:
    return

  let progression = delta.actProgression.get()
  addLine(lines, indent, "act-progression {")
  addLine(lines, indent + 1, "current-act=" & $progression.currentAct)
  addLine(lines, indent + 1, "act-start-turn=" & $progression.actStartTurn)
  addLine(lines, indent + 1,
    "colonization-percent=" & $progression.lastColonizationPercent)
  addLine(lines, indent + 1, "total-prestige=" & $progression.lastTotalPrestige)
  if progression.act2TopThreeHouses.len > 0:
    var houses: seq[string] = @[]
    for houseId in progression.act2TopThreeHouses:
      houses.add("(HouseId)" & $houseId.uint32)
    addLine(lines, indent + 1, "act2-top-houses=" & houses.join(","))
  if progression.act2TopThreePrestige.len > 0:
    var prestigeValues: seq[string] = @[]
    for prestige in progression.act2TopThreePrestige:
      prestigeValues.add($prestige)
    addLine(lines, indent + 1, "act2-top-prestige=" & prestigeValues.join(","))
  addLine(lines, indent, "}")

proc formatPlayerStateDeltaKdl*(
  gameId: string,
  delta: PlayerStateDelta
): string =
  var lines: seq[string] = @[]
  addLine(lines, 0,
    "delta version=1 turn=" & $delta.turn &
    " game=" & kdlString(gameId) &
    " house=(HouseId)" & $delta.viewingHouse.uint32 & " {")

  formatColonies(delta.ownColonies, lines, 1)
  formatFleets(delta.ownFleets, lines, 1)
  formatShips(delta.ownShips, lines, 1)
  formatGroundUnits(delta.ownGroundUnits, lines, 1)
  formatVisibleSystems(delta.visibleSystems, lines, 1)
  formatVisibleColonies(delta.visibleColonies, lines, 1)
  formatVisibleFleets(delta.visibleFleets, lines, 1)
  formatHousePrestige(delta.housePrestige, lines, 1)
  formatHouseColonyCounts(delta.houseColonyCounts, lines, 1)
  formatDiplomaticRelations(delta.diplomaticRelations, lines, 1)
  formatEliminatedHouses(delta.eliminatedHouses, lines, 1)
  formatActProgression(delta, lines, 1)

  addLine(lines, 0, "}")
  result = lines.join("\n") & "\n"

# =============================================================================
# Snapshot Helpers
# =============================================================================

proc buildPlayerStateSnapshot*(
  state: GameState,
  houseId: HouseId
): PlayerStateSnapshot =
  let playerState = createPlayerState(state, houseId)
  snapshotFromPlayerState(playerState)
