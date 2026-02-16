##
## PlayerState serialization tests
##

import std/[unittest, options]
import ../../src/engine/engine
import ../../src/engine/state/[engine, iterators, player_state]
import ../../src/daemon/persistence/msgpack_state

suite "PlayerState: Tax Rate":
  test "tax rate persists through msgpack":
    let game = newGame()
    for house in game.allHouses():
      let ps = game.createPlayerState(house.id)
      check ps.taxRate.isSome()
      let encoded = serializePlayerState(ps)
      let decoded = deserializePlayerState(encoded)
      check decoded.taxRate == ps.taxRate
