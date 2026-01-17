## PlayerState KDL parsing helpers for 30405

import std/[options, tables, json, jsonutils]
import kdl
import ../../common/logger
import ../../engine/types/[core, player_state, colony, fleet, ship, ground_unit,
  diplomacy, progression]
import ../../daemon/persistence/player_state_snapshot

proc parseJsonPayload[T](node: KdlNode): Option[T] =
  if not node.props.hasKey("data"):
    return none(T)
  let raw = node.props["data"].getString()
  try:
    return some(parseJson(raw).jsonTo(T))
  except CatchableError as e:
    logError("StateKDL", "Failed to parse payload: ", e.msg)
    return none(T)

proc parseVisibleSystems(node: KdlNode): Table[SystemId, VisibleSystem] =
  result = initTable[SystemId, VisibleSystem]()
  for child in node.children:
    if child.name != "system":
      continue
    let payloadOpt = parseJsonPayload[VisibleSystem](child)
    if payloadOpt.isSome:
      let payload = payloadOpt.get()
      result[payload.systemId] = payload

proc parseVisibleColonies(node: KdlNode): seq[VisibleColony] =
  result = @[]
  for child in node.children:
    if child.name != "colony":
      continue
    let payloadOpt = parseJsonPayload[VisibleColony](child)
    if payloadOpt.isSome:
      result.add(payloadOpt.get())

proc parseVisibleFleets(node: KdlNode): seq[VisibleFleet] =
  result = @[]
  for child in node.children:
    if child.name != "fleet":
      continue
    let payloadOpt = parseJsonPayload[VisibleFleet](child)
    if payloadOpt.isSome:
      result.add(payloadOpt.get())

proc parseHousePrestige(node: KdlNode): Table[HouseId, int32] =
  result = initTable[HouseId, int32]()
  for child in node.children:
    if child.name != "house":
      continue
    let payloadOpt = parseJsonPayload[HouseValue](child)
    if payloadOpt.isSome:
      let payload = payloadOpt.get()
      result[payload.houseId] = payload.value

proc parseHouseCounts(node: KdlNode): Table[HouseId, int32] =
  result = initTable[HouseId, int32]()
  for child in node.children:
    if child.name != "house":
      continue
    let payloadOpt = parseJsonPayload[HouseCount](child)
    if payloadOpt.isSome:
      let payload = payloadOpt.get()
      result[payload.houseId] = payload.count

proc parseDiplomacy(node: KdlNode): Table[(HouseId, HouseId), DiplomaticState] =
  result = initTable[(HouseId, HouseId), DiplomaticState]()
  for child in node.children:
    if child.name != "relation":
      continue
    let payloadOpt = parseJsonPayload[RelationSnapshot](child)
    if payloadOpt.isSome:
      let payload = payloadOpt.get()
      result[(payload.sourceHouse, payload.targetHouse)] = payload.state

proc parseEliminated(node: KdlNode): seq[HouseId] =
  result = @[]
  for child in node.children:
    if child.name != "house":
      continue
    let payloadOpt = parseJsonPayload[HouseId](child)
    if payloadOpt.isSome:
      result.add(payloadOpt.get())

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
      let payloadOpt = parseJsonPayload[ActProgressionState](child)
      if payloadOpt.isSome:
        state.actProgression = payloadOpt.get()
    else:
      discard

proc parseOwnedColonies(node: KdlNode): seq[Colony] =
  result = @[]
  for child in node.children:
    if child.name != "colony":
      continue
    let payloadOpt = parseJsonPayload[Colony](child)
    if payloadOpt.isSome:
      result.add(payloadOpt.get())

proc parseOwnedFleets(node: KdlNode): seq[Fleet] =
  result = @[]
  for child in node.children:
    if child.name != "fleet":
      continue
    let payloadOpt = parseJsonPayload[Fleet](child)
    if payloadOpt.isSome:
      result.add(payloadOpt.get())

proc parseOwnedShips(node: KdlNode): seq[Ship] =
  result = @[]
  for child in node.children:
    if child.name != "fleet":
      continue
    for shipNode in child.children:
      if shipNode.name != "ship":
        continue
      let payloadOpt = parseJsonPayload[Ship](shipNode)
      if payloadOpt.isSome:
        result.add(payloadOpt.get())

proc parseOwnedGroundUnits(node: KdlNode): seq[GroundUnit] =
  result = @[]
  for child in node.children:
    if child.name != "colony":
      continue
    for unitNode in child.children:
      if unitNode.name != "ground-units":
        continue
      let payloadOpt = parseJsonPayload[GroundUnit](unitNode)
      if payloadOpt.isSome:
        result.add(payloadOpt.get())

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
          try:
            state.viewingHouse = HouseId(child.props["id"].getInt().uint32)
          except CatchableError:
            discard

    for child in root.children:
      case child.name
      of "colonies":
        state.ownColonies = parseOwnedColonies(child)
        state.ownGroundUnits = parseOwnedGroundUnits(child)
      of "fleets":
        state.ownFleets = parseOwnedFleets(child)
        state.ownShips = parseOwnedShips(child)
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
