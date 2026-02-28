import std/unittest

import ../../src/bot/[types, transport]
import ../../src/player/nostr/client

suite "bot transport":
  test "newBotNostrClient maps config fields":
    let cfg = BotConfig(
      relays: @["wss://relay.example"],
      gameId: "game-x",
      daemonPubkey: "deadbeef",
      playerPrivHex: "cafebabe",
      playerPubHex: "01020304"
    )
    let handlers = PlayerNostrHandlers()
    let client = newBotNostrClient(cfg, handlers)

    check client.gameId == "game-x"
    check client.daemonPubkey == "deadbeef"
    check client.playerPrivHex == "cafebabe"
    check client.playerPubHex == "01020304"
    check client.client.relays.len == 1
