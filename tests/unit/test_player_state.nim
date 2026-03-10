##
## PlayerState serialization tests
##

import std/[unittest, options, tables]
import ../../src/engine/engine
import ../../src/engine/state/[iterators, player_state, event_filter]
import ../../src/daemon/persistence/msgpack_state
import ../../src/engine/types/[core, event, player_state as ps_types]

suite "PlayerState: Tax Rate":
  test "tax rate persists through msgpack":
    let game = newGame()
    for house in game.allHouses():
      let ps = game.createPlayerState(house.id)
      check ps.taxRate.isSome()
      check ps.ebpPool.isSome()
      check ps.cipPool.isSome()
      let encoded = serializePlayerState(ps)
      let decoded = deserializePlayerState(encoded)
      check decoded.taxRate == ps.taxRate
      check decoded.ebpPool == ps.ebpPool
      check decoded.cipPool == ps.cipPool

suite "PlayerState: Event Filtering":
  test "enemy command lifecycle events do not leak through visible systems":
    var visibleSystems = initTable[SystemId, ps_types.VisibleSystem]()
    visibleSystems[SystemId(7)] = ps_types.VisibleSystem(
      systemId: SystemId(7),
      name: "Ambrose",
      visibility: VisibilityLevel.Occupied,
      lastScoutedTurn: some(1'i32),
      planetClass: 0,
      resourceRating: 0,
      coordinates: some((q: 0'i32, r: 0'i32)),
      jumpLaneIds: @[],
    )

    let enemyEvent = GameEvent(
      eventType: GameEventType.CommandIssued,
      houseId: some(HouseId(2)),
      systemId: some(SystemId(7)),
      description: "Fleet F3: Command issued - View",
      orderType: some("View"),
      fleetId: some(FleetId(3)),
    )

    check not enemyEvent.isEventVisibleToHouse(HouseId(1), visibleSystems)
