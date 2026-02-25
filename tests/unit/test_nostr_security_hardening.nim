import std/[unittest, strutils]

import ../../src/player/tui/app
import ../../src/player/nostr/client
import ../../src/daemon/transport/nostr/[crypto, events, wire]

suite "Nostr Security Hardening":
  test "game definition validation rejects invalid signatures":
    let daemonKeys = generateKeyPair()
    let daemonPriv = hexToBytes32(daemonKeys.privateKey)

    var gameDef = createGameDefinitionNoSlots(
      "game-1",
      "Test Game",
      "active",
      daemonKeys.publicKey
    )
    signEvent(gameDef, daemonPriv)

    check validateGameDefinitionEvent(
      gameDef,
      0'i64,
      daemonKeys.publicKey
    ) == GameDefinitionEventValidation.Accept

    var tampered = gameDef
    tampered.content.add("x")
    check validateGameDefinitionEvent(
      tampered,
      0'i64,
      daemonKeys.publicKey
    ) == GameDefinitionEventValidation.InvalidSignature

  test "player client rejects encrypted events from non-daemon sender":
    let playerKeys = generateKeyPair()
    let daemonKeys = generateKeyPair()
    let attackerKeys = generateKeyPair()

    var gotJoinError = false
    var lastError = ""

    let handlers = PlayerNostrHandlers(
      onJoinError: proc(message: string) =
        discard message
        gotJoinError = true,
      onError: proc(message: string) =
        lastError = message
    )

    let pc = newPlayerNostrClient(
      @[],
      "game-1",
      playerKeys.privateKey,
      playerKeys.publicKey,
      daemonKeys.publicKey,
      handlers
    )

    let attackerPriv = hexToBytes32(attackerKeys.privateKey)
    let playerPub = hexToBytes32(playerKeys.publicKey)
    let spoofedPayload = encodePayload("spoof", attackerPriv, playerPub)

    var spoofed = createJoinError(
      attackerKeys.publicKey,
      playerKeys.publicKey,
      spoofedPayload
    )
    signEvent(spoofed, attackerPriv)
    check verifyEvent(spoofed)

    pc.handleEvent("sub", spoofed)
    check gotJoinError == false
    check lastError.contains("non-daemon sender")

    # Control case: daemon-authored join error is accepted.
    gotJoinError = false
    lastError = ""
    let daemonPriv = hexToBytes32(daemonKeys.privateKey)
    let validPayload = encodePayload("valid", daemonPriv, playerPub)
    var valid = createJoinError(
      daemonKeys.publicKey,
      playerKeys.publicKey,
      validPayload
    )
    signEvent(valid, daemonPriv)
    check verifyEvent(valid)

    pc.handleEvent("sub", valid)
    check gotJoinError == true
    check lastError.len == 0

  test "forwarded 30406 uses signer-consistent daemon pubkey":
    let daemonKeys = generateKeyPair()
    let senderKeys = generateKeyPair()
    let recipientKeys = generateKeyPair()
    let daemonPriv = hexToBytes32(daemonKeys.privateKey)
    let recipientPub = hexToBytes32(recipientKeys.publicKey)
    let payload = encodePayload("msg", daemonPriv, recipientPub)

    var forwardEvent = createPlayerMessage(
      gameId = "game-1",
      encryptedPayload = payload,
      recipientPubkey = recipientKeys.publicKey,
      senderPubkey = daemonKeys.publicKey,
      fromHouse = 1'i32,
      toHouse = 2'i32
    )
    signEvent(forwardEvent, daemonPriv)
    check verifyEvent(forwardEvent)

    var brokenEvent = createPlayerMessage(
      gameId = "game-1",
      encryptedPayload = payload,
      recipientPubkey = recipientKeys.publicKey,
      senderPubkey = senderKeys.publicKey,
      fromHouse = 1'i32,
      toHouse = 2'i32
    )
    signEvent(brokenEvent, daemonPriv)
    check not verifyEvent(brokenEvent)

  test "verifyEvent returns false for malformed pubkey hex":
    var malformed = createGameDefinitionNoSlots(
      "game-1",
      "Malformed Pubkey",
      "active",
      "zz"
    )
    malformed.sig = "00".repeat(64)
    check not verifyEvent(malformed)

  test "verifyEvent returns false for malformed signature hex":
    let daemonKeys = generateKeyPair()
    var malformed = createGameDefinitionNoSlots(
      "game-1",
      "Malformed Sig",
      "active",
      daemonKeys.publicKey
    )
    malformed.sig = "zz"
    check not verifyEvent(malformed)
