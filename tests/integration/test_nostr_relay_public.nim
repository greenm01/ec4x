## Smoke test for public relay connectivity (optional).

import std/[asyncdispatch, os, unittest]
import ../../src/daemon/transport/nostr/[client, events, crypto, filter]
import ../../src/daemon/transport/nostr/types

const
  GameId = "test-game-public"

proc relayUrl(): string =
  let url = getEnv("RELAY_URL_PUBLIC")
  if url.len == 0:
    return ""
  url

suite "Nostr Relay (Public)":
  test "publish and receive event":
    let url = relayUrl()
    if url.len == 0:
      skip()

    let daemonKeys = generateKeyPair()
    let playerKeys = generateKeyPair()

    var playerClient = newNostrClient(@[url])
    var daemonClient = newNostrClient(@[url])
    waitFor playerClient.connect()
    waitFor daemonClient.connect()
    asyncCheck playerClient.listen()
    asyncCheck daemonClient.listen()

    var received = false

    playerClient.onEvent = proc(subId: string, event: NostrEvent) =
      if event.kind == EventKindTurnResults:
        received = true

    let playerFilter = filterTurnResults(GameId, playerKeys.publicKey)
    waitFor playerClient.subscribe("player-results", @[playerFilter])
    waitFor sleepAsync(200)

    var event = createTurnResults(
      gameId = GameId,
      turn = 1,
      encryptedPayload = "test",
      playerPubkey = playerKeys.publicKey,
      daemonPubkey = daemonKeys.publicKey
    )
    let daemonPriv = hexToBytes32(daemonKeys.privateKey)
    signEvent(event, daemonPriv)

    discard waitFor daemonClient.publish(event)
    waitFor sleepAsync(200)

    for _ in 0..<30:
      if received:
        break
      sleep(100)

    check received

    waitFor playerClient.disconnect()
    waitFor daemonClient.disconnect()
