## PlayerState delta generation and msgpack serialization
##
## Computes differences between PlayerState snapshots and serializes
## to msgpack binary for efficient wire transmission.

import std/[options, tables]
import msgpack4nim
import ../../../engine/types/[core, colony, fleet, ship, ground_unit, player_state,
  progression, capacity]
import ../../../engine/types/game_state
import ../../../engine/state/fog_of_war
import ../../persistence/player_state_snapshot
import ../../../common/msgpack_types
export msgpack_types

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

proc sameGroundUnitGarrison(
  a: GroundUnitGarrison,
  b: GroundUnitGarrison
): bool =
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

proc relationKey(
  item: RelationSnapshot
): tuple[source: HouseId, target: HouseId] =
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

proc diffColonies(
  oldItems: seq[Colony],
  newItems: seq[Colony]
): EntityDelta[Colony] =
  diffById(
    oldItems,
    newItems,
    proc(item: Colony): ColonyId = item.id,
    proc(id: ColonyId): uint32 = id.uint32,
    proc(a: Colony, b: Colony): bool = sameColony(a, b)
  )

proc diffFleets(
  oldItems: seq[Fleet],
  newItems: seq[Fleet]
): EntityDelta[Fleet] =
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
# Msgpack Serialization
# =============================================================================

proc serializePlayerStateDelta*(delta: PlayerStateDelta): string =
  ## Serialize PlayerStateDelta to msgpack binary
  pack(delta)

proc deserializePlayerStateDelta*(data: string): PlayerStateDelta =
  ## Deserialize msgpack binary to PlayerStateDelta
  unpack(data, PlayerStateDelta)

proc formatPlayerStateDeltaMsgpack*(
  gameId: string,
  delta: PlayerStateDelta
): string =
  ## Serialize delta to msgpack binary for wire transmission
  ## gameId is included for logging/debugging but not in the payload
  ## (the Nostr event tags already identify the game)
  discard gameId  # Used for logging context only
  serializePlayerStateDelta(delta)

# =============================================================================
# Snapshot Helpers
# =============================================================================

proc buildPlayerStateSnapshot*(
  state: GameState,
  houseId: HouseId
): PlayerStateSnapshot =
  let playerState = createPlayerState(state, houseId)
  snapshotFromPlayerState(playerState)
