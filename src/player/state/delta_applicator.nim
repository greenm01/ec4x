## Apply PlayerState deltas to local PlayerState cache

import std/[json, jsonutils, options]
import kdl
import ../../common/logger
import ../../engine/types/[core, player_state, colony, fleet, ship, ground_unit,
  diplomacy, progression]
import ../../daemon/persistence/player_state_snapshot
import ./kdl_player_state

proc parseHouseId(val: KdlVal): Option[HouseId] =
  try:
    return some(HouseId(val.getInt().uint32))
  except CatchableError:
    return none(HouseId)

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

proc parseSystemId(val: KdlVal): Option[SystemId] =
  try:
    return some(SystemId(val.getInt().uint32))
  except CatchableError:
    return none(SystemId)

proc parseJsonPayload[T](node: KdlNode): Option[T] =
  if not node.props.hasKey("data"):
    return none(T)
  let raw = node.props["data"].getString()
  try:
    return some(parseJson(raw).jsonTo(T))
  except CatchableError as e:
    logError("Delta", "Failed to parse payload: ", e.msg)
    return none(T)

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

proc applyEntityDelta[T, Id](
  parent: KdlNode,
  section: string,
  items: var seq[T],
  idFn: proc(item: T): Id,
  idParser: proc(val: KdlVal): Option[Id]
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

      let payloadOpt = parseJsonPayload[T](entry)
      if payloadOpt.isNone:
        continue
      upsertById(items, payloadOpt.get(), idFn)

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

      let payloadOpt = parseJsonPayload[HouseValue](entry)
      if payloadOpt.isNone:
        continue
      let payload = payloadOpt.get()
      target[payload.houseId] = payload.value

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

      let payloadOpt = parseJsonPayload[HouseCount](entry)
      if payloadOpt.isNone:
        continue
      let payload = payloadOpt.get()
      target[payload.houseId] = payload.count

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

      let payloadOpt = parseJsonPayload[RelationSnapshot](entry)
      if payloadOpt.isNone:
        continue
      let payload = payloadOpt.get()
      target[(payload.sourceHouse, payload.targetHouse)] = payload.state

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

      let payloadOpt = parseJsonPayload[HouseId](entry)
      if payloadOpt.isNone:
        continue
      upsertById(target, payloadOpt.get(), proc(v: HouseId): HouseId = v)

proc applyActProgressionDelta(parent: KdlNode, state: var PlayerState) =
  for child in parent.children:
    if child.name != "act-progression":
      continue
    let payloadOpt = parseJsonPayload[ActProgressionState](child)
    if payloadOpt.isSome:
      state.actProgression = payloadOpt.get()

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

      let payloadOpt = parseJsonPayload[VisibleSystem](entry)
      if payloadOpt.isNone:
        continue
      let payload = payloadOpt.get()
      state.visibleSystems[payload.systemId] = payload

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
      parseColonyId
    )

    applyEntityDelta(root, "fleets", state.ownFleets,
      proc(item: Fleet): FleetId = item.id,
      parseFleetId
    )

    applyEntityDelta(root, "ships", state.ownShips,
      proc(item: Ship): ShipId = item.id,
      parseShipId
    )

    applyEntityDelta(root, "ground-units", state.ownGroundUnits,
      proc(item: GroundUnit): GroundUnitId = item.id,
      parseGroundUnitId
    )

    applyVisibleSystemsDelta(root, state)

    applyEntityDelta(root, "visible-colonies", state.visibleColonies,
      proc(item: VisibleColony): ColonyId = item.colonyId,
      parseColonyId
    )

    applyEntityDelta(root, "visible-fleets", state.visibleFleets,
      proc(item: VisibleFleet): FleetId = item.fleetId,
      parseFleetId
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
