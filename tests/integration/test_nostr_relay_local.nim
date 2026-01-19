## Integration test for relay-backed Nostr flow (local relay).

import std/[asyncdispatch, os, options, unittest]
import ../../src/daemon/transport/nostr/[client, events, wire, crypto, filter]
import ../../src/daemon/transport/nostr/types
import kdl

const
  GameId = "test-game"

proc relayUrl(): string =
  let url = getEnv("RELAY_URL")
  if url.len == 0:
    return ""
  url

suite "Nostr Relay (Local)":
  test "publish and receive encrypted delta":
    let url = relayUrl()
    if url.len == 0:
      skip()

    let daemonKeys = generateKeyPair()
    let playerKeys = generateKeyPair()

    var playerClient = newNostrClient(@[url])
    var daemonClient = newNostrClient(@[url])
    waitFor playerClient.connect()
    waitFor daemonClient.connect()

    var received = false

    playerClient.onEvent = proc(subId: string, event: NostrEvent) =
      if event.kind != EventKindTurnResults:
        return
      let privBytes = hexToBytes32(playerKeys.privateKey)
      let pubBytes = hexToBytes32(event.pubkey)
      let payload = decodePayload(event.content, privBytes, pubBytes)
      discard parseKdl(payload)
      received = true

    let playerFilter = filterTurnResults(GameId, playerKeys.publicKey)
    waitFor playerClient.subscribe("player-results", @[playerFilter])

    let kdlPayload = "delta turn=1 {}"
    let daemonPriv = hexToBytes32(daemonKeys.privateKey)
    let playerPub = hexToBytes32(playerKeys.publicKey)
    let encrypted = encodePayload(kdlPayload, daemonPriv, playerPub)
    var event = createTurnResults(
      gameId = GameId,
      turn = 1,
      encryptedPayload = encrypted,
      playerPubkey = playerKeys.publicKey,
      daemonPubkey = daemonKeys.publicKey
    )
    signEvent(event, daemonPriv)

    waitFor daemonClient.publish(event)

    for _ in 0..<30:
      if received:
        break
      sleep(100)

    check received

    waitFor playerClient.disconnect()
    waitFor daemonClient.disconnect()
