# EC4X Nostr Protocol Implementation

## Overview

EC4X uses Nostr as its transport layer, treating it like a modern BBS door game system. Players connect through desktop clients, submit orders as encrypted Nostr events, and the daemon processes turns on schedule.

## Module Structure

```
src/transport/nostr/
├── client.nim       # WebSocket relay connection management
├── events.nim       # Event creation, parsing, and validation
├── crypto.nim       # Cryptographic operations (secp256k1, NIP-44)
├── filter.nim       # Subscription filters and queries
└── types.nim        # Core Nostr types and constants

src/daemon/
├── subscriber.nim   # Listen for game events on relays
├── processor.nim    # Decrypt and validate order packets
└── publisher.nim    # Publish game state and results

src/main/
├── client.nim       # Desktop client (existing, add Nostr support)
└── daemon.nim       # Game daemon (new)
```

## Core Types (src/transport/nostr/types.nim)

```nim
import std/[json, tables, times]

type
  NostrEvent* = object
    id*: string                    # 32-byte lowercase hex event id
    pubkey*: string                # 32-byte lowercase hex public key
    created_at*: int64             # Unix timestamp
    kind*: int                     # Event type
    tags*: seq[seq[string]]        # Indexed tags
    content*: string               # Arbitrary content (often JSON)
    sig*: string                   # 64-byte hex signature

  NostrFilter* = object
    ids*: seq[string]              # Event IDs
    authors*: seq[string]          # Pubkeys
    kinds*: seq[int]               # Event kinds
    tags*: Table[string, seq[string]]  # Tag filters (e.g., #g for game)
    since*: Option[int64]          # Unix timestamp
    until*: Option[int64]          # Unix timestamp
    limit*: Option[int]            # Max results

  RelayMessage* = object
    case kind*: RelayMessageKind
    of rmEvent:
      subscriptionId*: string
      event*: NostrEvent
    of rmOk:
      eventId*: string
      accepted*: bool
      message*: string
    of rmEose:
      subId*: string
    of rmClosed:
      closedSubId*: string
      reason*: string
    of rmNotice:
      notice*: string

  RelayMessageKind* = enum
    rmEvent, rmOk, rmEose, rmClosed, rmNotice

  NostrClient* = ref object
    relays*: seq[string]           # WebSocket URLs
    connections*: Table[string, WebSocket]
    subscriptions*: Table[string, NostrFilter]
    eventCallback*: proc(event: NostrEvent)
    eoseCallback*: proc(subId: string)

  KeyPair* = object
    privateKey*: array[32, byte]
    publicKey*: array[32, byte]

# EC4X Custom Event Kinds
const
  EventKindOrderPacket* = 30001      # Player order submission
  EventKindGameState* = 30002        # Per-player game state view
  EventKindTurnComplete* = 30003     # Turn resolution announcement
  EventKindGameMeta* = 30004         # Game metadata (lobby, config)
  EventKindChatMessage* = 30005      # In-game diplomacy chat

# Standard tag names
const
  TagGame* = "g"          # Game ID
  TagHouse* = "h"         # Player's house name
  TagTurn* = "t"          # Turn number
  TagPlayer* = "p"        # Player pubkey (for encryption target)
  TagGamePhase* = "phase" # Game phase (setup, active, completed)
```

## Crypto Module (src/transport/nostr/crypto.nim)

```nim
import std/[sequtils, strutils]
import nimcrypto/[secp256k1, sha256, utils]
import types

proc generateKeyPair*(): KeyPair =
  ## Generate a new Nostr keypair
  var ctx = secp256k1_context_create(SECP256K1_CONTEXT_SIGN or SECP256K1_CONTEXT_VERIFY)
  var privKey: array[32, byte]
  var pubKey: secp256k1_pubkey

  # Generate random private key
  var rng = initRand()
  for i in 0..<32:
    privKey[i] = byte(rng.rand(255))

  # Derive public key
  discard secp256k1_ec_pubkey_create(ctx, addr pubKey, cast[ptr uint8](addr privKey[0]))

  var serializedPubKey: array[33, byte]
  var outputLen: csize_t = 33
  discard secp256k1_ec_pubkey_serialize(
    ctx,
    cast[ptr uint8](addr serializedPubKey[0]),
    addr outputLen,
    addr pubKey,
    SECP256K1_EC_COMPRESSED
  )

  result.privateKey = privKey
  # Use x-only pubkey (last 32 bytes)
  for i in 0..<32:
    result.publicKey[i] = serializedPubKey[i + 1]

  secp256k1_context_destroy(ctx)

proc toHex*(data: openArray[byte]): string =
  ## Convert bytes to lowercase hex string
  result = ""
  for b in data:
    result.add(b.toHex().toLowerAscii())

proc fromHex*(hexStr: string): seq[byte] =
  ## Convert hex string to bytes
  result = newSeq[byte](hexStr.len div 2)
  for i in 0..<result.len:
    result[i] = parseHexInt(hexStr[i*2..i*2+1]).byte

proc sha256Hash*(data: string): string =
  ## Compute SHA256 hash and return as hex
  var ctx: sha256
  ctx.init()
  ctx.update(data)
  let digest = ctx.finish()
  result = toHex(digest.data)

proc signEvent*(event: var NostrEvent, privateKey: array[32, byte]) =
  ## Sign a Nostr event with private key
  # 1. Compute event ID (hash of serialized event)
  let serialized = %*[
    0,  # Reserved for future use
    event.pubkey,
    event.created_at,
    event.kind,
    event.tags,
    event.content
  ]
  event.id = sha256Hash($serialized)

  # 2. Sign the event ID
  var ctx = secp256k1_context_create(SECP256K1_CONTEXT_SIGN)
  var signature: secp256k1_ecdsa_signature
  let msgHash = fromHex(event.id)

  discard secp256k1_ecdsa_sign(
    ctx,
    addr signature,
    cast[ptr uint8](addr msgHash[0]),
    cast[ptr uint8](unsafeAddr privateKey[0]),
    nil, nil
  )

  var sigOutput: array[64, byte]
  discard secp256k1_ecdsa_signature_serialize_compact(
    ctx,
    cast[ptr uint8](addr sigOutput[0]),
    addr signature
  )

  event.sig = toHex(sigOutput)
  secp256k1_context_destroy(ctx)

proc verifyEvent*(event: NostrEvent): bool =
  ## Verify event signature
  var ctx = secp256k1_context_create(SECP256K1_CONTEXT_VERIFY)

  # Verify ID matches content
  let serialized = %*[
    0,
    event.pubkey,
    event.created_at,
    event.kind,
    event.tags,
    event.content
  ]
  let computedId = sha256Hash($serialized)
  if computedId != event.id:
    return false

  # Verify signature
  var pubKey: secp256k1_pubkey
  let pubKeyBytes = fromHex(event.pubkey)
  discard secp256k1_xonly_pubkey_parse(
    ctx,
    cast[ptr secp256k1_xonly_pubkey](addr pubKey),
    cast[ptr uint8](unsafeAddr pubKeyBytes[0])
  )

  var signature: secp256k1_ecdsa_signature
  let sigBytes = fromHex(event.sig)
  discard secp256k1_ecdsa_signature_parse_compact(
    ctx,
    addr signature,
    cast[ptr uint8](unsafeAddr sigBytes[0])
  )

  let msgHash = fromHex(event.id)
  result = secp256k1_ecdsa_verify(
    ctx,
    addr signature,
    cast[ptr uint8](unsafeAddr msgHash[0]),
    addr pubKey
  ) == 1

  secp256k1_context_destroy(ctx)

proc encryptNIP44*(plaintext: string, senderPrivKey: array[32, byte],
                   recipientPubKey: array[32, byte]): string =
  ## Encrypt message using NIP-44 (simplified - full impl needs conversation key)
  ## TODO: Implement full NIP-44 spec with HKDF and ChaCha20
  result = ""  # Placeholder

proc decryptNIP44*(ciphertext: string, recipientPrivKey: array[32, byte],
                   senderPubKey: array[32, byte]): string =
  ## Decrypt NIP-44 message
  ## TODO: Implement full NIP-44 spec
  result = ""  # Placeholder
```

## Events Module (src/transport/nostr/events.nim)

```nim
import std/[json, times, options]
import types, crypto

proc newEvent*(kind: int, content: string, tags: seq[seq[string]] = @[]): NostrEvent =
  ## Create a new unsigned event
  result = NostrEvent(
    pubkey: "",  # Set by caller
    created_at: getTime().toUnix(),
    kind: kind,
    tags: tags,
    content: content
  )

proc addTag*(event: var NostrEvent, tag: seq[string]) =
  ## Add a tag to an event
  event.tags.add(tag)

proc getTag*(event: NostrEvent, tagName: string): Option[seq[string]] =
  ## Get first tag matching name
  for tag in event.tags:
    if tag.len > 0 and tag[0] == tagName:
      return some(tag)
  return none(seq[string])

proc getTags*(event: NostrEvent, tagName: string): seq[seq[string]] =
  ## Get all tags matching name
  result = @[]
  for tag in event.tags:
    if tag.len > 0 and tag[0] == tagName:
      result.add(tag)

proc parseEvent*(jsonStr: string): NostrEvent =
  ## Parse JSON into NostrEvent
  let j = parseJson(jsonStr)
  result = NostrEvent(
    id: j["id"].getStr(),
    pubkey: j["pubkey"].getStr(),
    created_at: j["created_at"].getInt(),
    kind: j["kind"].getInt(),
    content: j["content"].getStr(),
    sig: j["sig"].getStr()
  )

  for tag in j["tags"].getElems():
    var tagSeq: seq[string] = @[]
    for elem in tag.getElems():
      tagSeq.add(elem.getStr())
    result.tags.add(tagSeq)

proc toJson*(event: NostrEvent): JsonNode =
  ## Serialize event to JSON
  result = %*{
    "id": event.id,
    "pubkey": event.pubkey,
    "created_at": event.created_at,
    "kind": event.kind,
    "tags": event.tags,
    "content": event.content,
    "sig": event.sig
  }

# EC4X-specific event builders

proc createOrderPacket*(gameId: string, house: string, turnNum: int,
                       orderJson: string, moderatorPubkey: string,
                       playerKeys: KeyPair): NostrEvent =
  ## Create encrypted order submission event
  result = newEvent(EventKindOrderPacket, "", @[
    @[TagGame, gameId],
    @[TagHouse, house],
    @[TagTurn, $turnNum],
    @[TagPlayer, moderatorPubkey]
  ])

  result.pubkey = toHex(playerKeys.publicKey)

  # Encrypt order to moderator
  let moderatorPubKeyBytes = fromHex(moderatorPubkey)
  result.content = encryptNIP44(
    orderJson,
    playerKeys.privateKey,
    moderatorPubKeyBytes
  )

  signEvent(result, playerKeys.privateKey)

proc createGameState*(gameId: string, house: string, turnNum: int,
                     stateJson: string, playerPubkey: string,
                     moderatorKeys: KeyPair): NostrEvent =
  ## Create encrypted game state for specific player
  result = newEvent(EventKindGameState, "", @[
    @[TagGame, gameId],
    @[TagHouse, house],
    @[TagTurn, $turnNum],
    @[TagPlayer, playerPubkey]
  ])

  result.pubkey = toHex(moderatorKeys.publicKey)

  # Encrypt state to player
  let playerPubKeyBytes = fromHex(playerPubkey)
  result.content = encryptNIP44(
    stateJson,
    moderatorKeys.privateKey,
    playerPubKeyBytes
  )

  signEvent(result, moderatorKeys.privateKey)

proc createTurnComplete*(gameId: string, turnNum: int,
                        summaryJson: string,
                        moderatorKeys: KeyPair): NostrEvent =
  ## Create public turn completion announcement
  result = newEvent(EventKindTurnComplete, summaryJson, @[
    @[TagGame, gameId],
    @[TagTurn, $turnNum]
  ])

  result.pubkey = toHex(moderatorKeys.publicKey)
  signEvent(result, moderatorKeys.privateKey)
```

## Filter Module (src/transport/nostr/filter.nim)

```nim
import std/[json, options, tables]
import types

proc newFilter*(): NostrFilter =
  ## Create empty filter
  result = NostrFilter(
    ids: @[],
    authors: @[],
    kinds: @[],
    tags: initTable[string, seq[string]]()
  )

proc withKinds*(filter: NostrFilter, kinds: seq[int]): NostrFilter =
  ## Add kind filter
  result = filter
  result.kinds = kinds

proc withAuthors*(filter: NostrFilter, authors: seq[string]): NostrFilter =
  ## Add author filter
  result = filter
  result.authors = authors

proc withTag*(filter: NostrFilter, tagName: string, values: seq[string]): NostrFilter =
  ## Add tag filter (e.g., #g for game ID)
  result = filter
  result.tags[tagName] = values

proc withSince*(filter: NostrFilter, timestamp: int64): NostrFilter =
  ## Add since timestamp
  result = filter
  result.since = some(timestamp)

proc withLimit*(filter: NostrFilter, limit: int): NostrFilter =
  ## Add result limit
  result = filter
  result.limit = some(limit)

proc toJson*(filter: NostrFilter): JsonNode =
  ## Serialize filter to JSON for relay subscription
  result = newJObject()

  if filter.ids.len > 0:
    result["ids"] = %filter.ids
  if filter.authors.len > 0:
    result["authors"] = %filter.authors
  if filter.kinds.len > 0:
    result["kinds"] = %filter.kinds

  for tagName, values in filter.tags:
    result["#" & tagName] = %values

  if filter.since.isSome:
    result["since"] = %filter.since.get()
  if filter.until.isSome:
    result["until"] = %filter.until.get()
  if filter.limit.isSome:
    result["limit"] = %filter.limit.get()

# EC4X-specific filters

proc filterGameOrders*(gameId: string, turnNum: int): NostrFilter =
  ## Filter for all orders in a game turn
  result = newFilter()
    .withKinds(@[EventKindOrderPacket])
    .withTag(TagGame, @[gameId])
    .withTag(TagTurn, @[$turnNum])

proc filterPlayerState*(gameId: string, playerPubkey: string): NostrFilter =
  ## Filter for game states sent to specific player
  result = newFilter()
    .withKinds(@[EventKindGameState])
    .withTag(TagGame, @[gameId])
    .withTag(TagPlayer, @[playerPubkey])

proc filterGameHistory*(gameId: string): NostrFilter =
  ## Filter for all events in a game
  result = newFilter()
    .withKinds(@[EventKindOrderPacket, EventKindGameState, EventKindTurnComplete])
    .withTag(TagGame, @[gameId])
```

## Client Module (src/transport/nostr/client.nim)

```nim
import std/[asyncdispatch, tables, json, strutils]
import websocket  # nim-websocket package
import types, events, filter

proc newNostrClient*(relays: seq[string]): NostrClient =
  ## Create new Nostr client connected to relays
  result = NostrClient(
    relays: relays,
    connections: initTable[string, WebSocket](),
    subscriptions: initTable[string, NostrFilter]()
  )

proc connect*(client: NostrClient) {.async.} =
  ## Connect to all configured relays
  for relayUrl in client.relays:
    try:
      let ws = await newWebSocket(relayUrl)
      client.connections[relayUrl] = ws
      echo "Connected to relay: ", relayUrl
    except:
      echo "Failed to connect to relay: ", relayUrl

proc disconnect*(client: NostrClient) {.async.} =
  ## Disconnect from all relays
  for relayUrl, ws in client.connections:
    await ws.close()
  client.connections.clear()

proc subscribe*(client: NostrClient, subId: string, filters: seq[NostrFilter]) {.async.} =
  ## Subscribe to events matching filters
  let msg = %*["REQ", subId, filters.map(f => f.toJson())]

  for relayUrl, ws in client.connections:
    await ws.send($msg)

  echo "Subscribed: ", subId

proc publish*(client: NostrClient, event: NostrEvent): Future[bool] {.async.} =
  ## Publish event to all relays
  let msg = %*["EVENT", event.toJson()]

  var published = false
  for relayUrl, ws in client.connections:
    try:
      await ws.send($msg)
      published = true
    except:
      echo "Failed to publish to ", relayUrl

  result = published

proc listen*(client: NostrClient) {.async.} =
  ## Listen for incoming messages from relays
  while true:
    for relayUrl, ws in client.connections:
      try:
        let msg = await ws.receiveStrPacket()
        let json = parseJson(msg)

        case json[0].getStr()
        of "EVENT":
          let subId = json[1].getStr()
          let event = parseEvent($json[2])
          if client.eventCallback != nil:
            client.eventCallback(event)

        of "EOSE":
          let subId = json[1].getStr()
          if client.eoseCallback != nil:
            client.eoseCallback(subId)

        of "OK":
          let eventId = json[1].getStr()
          let accepted = json[2].getBool()
          echo "Event ", eventId, " ", if accepted: "accepted" else: "rejected"

        of "CLOSED":
          echo "Subscription closed: ", json[1].getStr()

        of "NOTICE":
          echo "Relay notice: ", json[1].getStr()

        else:
          discard
      except:
        discard  # Handle connection errors

    await sleepAsync(100)  # Prevent tight loop
```

## Dependencies (ec4x.nimble)

```nim
# Add to existing ec4x.nimble

requires "websocket >= 0.5.0"     # WebSocket client
requires "nimcrypto >= 0.6.0"     # Cryptographic primitives
requires "chronicles >= 0.10.3"   # Structured logging
```

## Usage Example

```nim
# Example: Client submitting orders
import asyncdispatch
import transport/nostr/[client, events, crypto, types]

proc submitOrders() {.async.} =
  # Load player keys
  let playerKeys = loadKeysFromConfig()

  # Create client
  let client = newNostrClient(@[
    "wss://relay.ec4x.game",
    "wss://relay.damus.io"
  ])

  await client.connect()

  # Create order packet
  let orderJson = """{"fleets": [...], "builds": [...]}"""
  let event = createOrderPacket(
    gameId = "game-abc123",
    house = "House-Atreides",
    turnNum = 5,
    orderJson = orderJson,
    moderatorPubkey = "moderator-npub...",
    playerKeys = playerKeys
  )

  # Publish
  let success = await client.publish(event)
  if success:
    echo "Orders submitted successfully"

  await client.disconnect()

waitFor submitOrders()
```

## Next Steps

1. **Implement crypto.nim fully** - Complete NIP-44 encryption
2. **Add error handling** - Robust relay connection management
3. **Write tests** - Unit tests for each module
4. **Integrate with existing engine/** - Bridge Nostr events to game logic
5. **Build daemon subscriber** - Watch for order events, decrypt, resolve turns

## References

- [NIP-01: Basic Protocol](https://github.com/nostr-protocol/nips/blob/master/01.md)
- [NIP-44: Encrypted Payloads](https://github.com/nostr-protocol/nips/blob/master/44.md)
- [secp256k1 in Nim](https://nimble.directory/pkg/secp256k1)
