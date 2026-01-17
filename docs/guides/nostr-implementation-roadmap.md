# EC4X Nostr Implementation Roadmap

This document details the technical implementation plan for full Nostr
transport in EC4X. It covers the phases, code changes, and testing
strategies needed to complete the integration.

## Current State

**Completed:**
- Schema: `nostr_pubkey` field in `houses` table
- Schema: `state_deltas` table for delta persistence
- Dependencies: `ws`, `zippy`, `nimcrypto` added to nimble
- KDL parser: Command parsing implemented (`kdl_orders.nim`)
- Daemon: Basic structure with game discovery
- Protocol spec: `docs/architecture/nostr-protocol.md`

**Stubbed/TODO:**
- Nostr client: WebSocket connection, subscribe, publish
- NIP-44 encryption/decryption
- Delta generation and serialization to KDL
- Command serialization from packet to KDL
- Full state serialization to KDL
- Player client Nostr integration

---

## Phase 1: Nostr Client Foundation

**Goal:** Working WebSocket client that can connect, subscribe, publish.

### 1.1 WebSocket Client (`src/daemon/transport/nostr/client.nim`)

```nim
## Nostr WebSocket client using treeform/ws

import std/[asyncdispatch, tables, json, strutils, options]
import ws
import types, nip01, filter
import ../../../common/logger

type
  MessageCallback* = proc(subId: string, event: NostrEvent): Future[void]
  
  NostrClient* = ref object
    relayUrl*: string
    ws*: WebSocket
    subscriptions*: Table[string, NostrFilter]
    callbacks*: Table[string, MessageCallback]
    connected*: bool
    reconnecting*: bool

proc newNostrClient*(relayUrl: string): NostrClient =
  result = NostrClient(
    relayUrl: relayUrl,
    subscriptions: initTable[string, NostrFilter](),
    callbacks: initTable[string, MessageCallback](),
    connected: false,
    reconnecting: false
  )

proc connect*(client: NostrClient) {.async.} =
  logInfo("Nostr", "Connecting to ", client.relayUrl)
  client.ws = await newWebSocket(client.relayUrl)
  client.connected = true
  logInfo("Nostr", "Connected")

proc disconnect*(client: NostrClient) {.async.} =
  if client.ws != nil and client.connected:
    client.ws.close()
    client.connected = false
  logInfo("Nostr", "Disconnected")

proc subscribe*(
  client: NostrClient,
  subId: string,
  filters: seq[NostrFilter],
  callback: MessageCallback
) {.async.} =
  ## Subscribe to events matching filters
  client.callbacks[subId] = callback
  
  var req = newJArray()
  req.add(%"REQ")
  req.add(%subId)
  for f in filters:
    req.add(f.toJson())
  
  await client.ws.send($req)
  logInfo("Nostr", "Subscribed: ", subId)

proc unsubscribe*(client: NostrClient, subId: string) {.async.} =
  let msg = %*["CLOSE", subId]
  await client.ws.send($msg)
  client.callbacks.del(subId)
  logInfo("Nostr", "Unsubscribed: ", subId)

proc publish*(client: NostrClient, event: NostrEvent): Future[bool] {.async.} =
  ## Publish signed event to relay
  let msg = %*["EVENT", event.toJson()]
  await client.ws.send($msg)
  # TODO: Wait for OK response
  result = true

proc listen*(client: NostrClient) {.async.} =
  ## Listen for incoming messages
  while client.connected:
    try:
      let packet = await client.ws.receiveStrPacket()
      let msg = parseJson(packet)
      let msgType = msg[0].getStr()
      
      case msgType
      of "EVENT":
        let subId = msg[1].getStr()
        let event = parseNostrEvent($msg[2])
        if client.callbacks.hasKey(subId):
          await client.callbacks[subId](subId, event)
      
      of "EOSE":
        logInfo("Nostr", "EOSE: ", msg[1].getStr())
      
      of "OK":
        let eventId = msg[1].getStr()
        let success = msg[2].getBool()
        let message = if msg.len > 3: msg[3].getStr() else: ""
        logInfo("Nostr", "OK: ", eventId, " success=", $success)
      
      of "CLOSED":
        let subId = msg[1].getStr()
        logInfo("Nostr", "Subscription closed: ", subId)
      
      of "NOTICE":
        logWarn("Nostr", "Notice: ", msg[1].getStr())
      
      else:
        logWarn("Nostr", "Unknown message: ", msgType)
    
    except WebSocketClosedError:
      logError("Nostr", "Connection closed")
      client.connected = false
      break
    except CatchableError as e:
      logError("Nostr", "Error: ", e.msg)
```

### 1.2 NIP-01 Event Handling (`src/daemon/transport/nostr/nip01.nim`)

```nim
## NIP-01 basic protocol: event creation, serialization, parsing

import std/[json, strutils, times, sequtils]
import nimcrypto/[sha2, utils]
import types

proc computeEventId*(event: NostrEvent): string =
  ## Compute event ID as SHA-256 of serialized event
  let serialized = $(%*[
    0,                    # Reserved
    event.pubkey,
    event.created_at,
    event.kind,
    event.tags,
    event.content
  ])
  let hash = sha256.digest(serialized)
  result = hash.data.toHex().toLowerAscii()

proc serializeForSigning*(event: NostrEvent): string =
  ## Serialize event for Schnorr signing
  result = $(%*[
    0,
    event.pubkey,
    event.created_at,
    event.kind,
    event.tags,
    event.content
  ])

proc toJson*(event: NostrEvent): JsonNode =
  result = %*{
    "id": event.id,
    "pubkey": event.pubkey,
    "created_at": event.created_at,
    "kind": event.kind,
    "tags": event.tags,
    "content": event.content,
    "sig": event.sig
  }

proc parseNostrEvent*(jsonStr: string): NostrEvent =
  let j = parseJson(jsonStr)
  result = NostrEvent(
    id: j["id"].getStr(),
    pubkey: j["pubkey"].getStr(),
    created_at: j["created_at"].getInt(),
    kind: j["kind"].getInt(),
    content: j["content"].getStr(),
    sig: j["sig"].getStr(),
    tags: @[]
  )
  for tag in j["tags"]:
    result.tags.add(tag.getElems().mapIt(it.getStr()))

proc newEvent*(kind: int, content: string, tags: seq[seq[string]] = @[]): NostrEvent =
  result = NostrEvent(
    created_at: getTime().toUnix(),
    kind: kind,
    content: content,
    tags: tags
  )
```

### 1.3 Filter Construction (`src/daemon/transport/nostr/filter.nim`)

```nim
## Nostr subscription filters

import std/[json, tables]
import types

proc toJson*(filter: NostrFilter): JsonNode =
  result = newJObject()
  
  if filter.ids.len > 0:
    result["ids"] = %filter.ids
  if filter.authors.len > 0:
    result["authors"] = %filter.authors
  if filter.kinds.len > 0:
    result["kinds"] = %filter.kinds
  if filter.since > 0:
    result["since"] = %filter.since
  if filter.until > 0:
    result["until"] = %filter.until
  if filter.limit > 0:
    result["limit"] = %filter.limit
  
  # Tag filters (#d, #p, #e, etc.)
  for key, values in filter.tags:
    result["#" & key] = %values

proc gameFilter*(gameId: string, kinds: seq[int]): NostrFilter =
  ## Create filter for EC4X game events
  result = NostrFilter(
    kinds: kinds,
    tags: {"d": @[gameId]}.toTable()
  )

proc commandFilter*(gameId: string, daemonPubkey: string): NostrFilter =
  ## Filter for incoming player commands
  result = NostrFilter(
    kinds: @[30402],
    tags: {
      "d": @[gameId],
      "p": @[daemonPubkey]
    }.toTable()
  )
```

---

## Phase 2: NIP-44 Encryption

**Goal:** Encrypted message exchange between daemon and players.

### 2.1 Cryptographic Primitives (`src/daemon/transport/nostr/crypto.nim`)

```nim
## NIP-44 encryption using nimcrypto

import std/[strutils, base64, random]
import nimcrypto/[sha2, hmac, chacha20, utils]
import types

type
  KeyPair* = object
    privateKey*: string  # 32 bytes hex
    publicKey*: string   # 32 bytes hex (x-only)
    npub*: string        # bech32 encoded

proc generateKeyPair*(): KeyPair =
  ## Generate new secp256k1 keypair
  # TODO: Use proper secp256k1 library
  var privBytes: array[32, byte]
  for i in 0..<32:
    privBytes[i] = byte(rand(255))
  result.privateKey = privBytes.toHex()
  # TODO: Derive public key from private key
  result.publicKey = "stub-pubkey"
  result.npub = "npub1stub"

proc sharedSecret*(myPrivkey: string, theirPubkey: string): array[32, byte] =
  ## Compute ECDH shared secret
  # TODO: Implement using secp256k1
  # For now, return deterministic stub
  let combined = myPrivkey & theirPubkey
  let hash = sha256.digest(combined)
  result = hash.data

proc encrypt*(plaintext: string, myPrivkey: string, theirPubkey: string): string =
  ## NIP-44 encrypt message
  ## Returns: base64(nonce || ciphertext || mac)
  
  # 1. Compute shared secret
  let secret = sharedSecret(myPrivkey, theirPubkey)
  
  # 2. Generate random nonce (24 bytes for XChaCha20)
  var nonce: array[24, byte]
  for i in 0..<24:
    nonce[i] = byte(rand(255))
  
  # 3. Derive encryption key using HKDF
  # Simplified: just use first 32 bytes of SHA256(secret || "nip44-encryption")
  let keyMaterial = sha256.digest(secret.toHex() & "nip44-encryption")
  var key: array[32, byte]
  for i in 0..<32:
    key[i] = keyMaterial.data[i]
  
  # 4. Encrypt with ChaCha20
  var ciphertext = newString(plaintext.len)
  # TODO: Implement ChaCha20 encryption
  ciphertext = plaintext  # Stub: no encryption yet
  
  # 5. Compute HMAC
  var mac: array[32, byte]
  # TODO: Compute HMAC-SHA256(key, nonce || ciphertext)
  
  # 6. Encode
  result = encode(nonce.toOpenArray(0, 23).join("") & ciphertext & mac.toOpenArray(0, 31).join(""))

proc decrypt*(ciphertext: string, myPrivkey: string, theirPubkey: string): string =
  ## NIP-44 decrypt message
  
  # 1. Decode base64
  let decoded = decode(ciphertext)
  
  # 2. Extract nonce, ciphertext, mac
  # TODO: Proper parsing
  
  # 3. Compute shared secret
  let secret = sharedSecret(myPrivkey, theirPubkey)
  
  # 4. Verify MAC
  # TODO: Verify HMAC
  
  # 5. Decrypt
  # TODO: ChaCha20 decryption
  
  result = decoded  # Stub: return as-is
```

### 2.2 Identity Management (`src/daemon/identity.nim`)

```nim
## Daemon identity management

import std/[os, times, strutils]
import transport/nostr/crypto
import ../common/logger
import kdl

const IdentityDir = ".local/share/ec4x"
const IdentityFile = "daemon_identity.kdl"

proc identityPath*(): string =
  expandTilde("~") / IdentityDir / IdentityFile

proc loadOrCreateIdentity*(): KeyPair =
  let path = identityPath()
  
  if fileExists(path):
    logInfo("Identity", "Loading identity from ", path)
    let content = readFile(path)
    let doc = parseKdl(content)
    let node = doc[0]
    result.privateKey = node.props["nsec"].getString()
    result.publicKey = node.props["npub"].getString()
    result.npub = result.publicKey
  else:
    logInfo("Identity", "Generating new identity")
    result = generateKeyPair()
    
    # Save to file
    createDir(expandTilde("~") / IdentityDir)
    let kdl = """identity {
  nsec "$1"
  npub "$2"
  created "$3"
}
""" % [result.privateKey, result.publicKey, $now().utc]
    writeFile(path, kdl)
    logInfo("Identity", "Saved to ", path)
  
  logInfo("Identity", "Daemon npub: ", result.npub)
```

---

## Phase 3: Compression Layer

**Goal:** Compress KDL payloads before encryption.

### 3.1 Compression Utilities (`src/daemon/transport/nostr/compression.nim`)

```nim
## Compression for Nostr payloads using zippy

import zippy

proc compressPayload*(data: string): string =
  ## Compress data using gzip
  result = compress(data, BestSpeed, dfGzip)

proc decompressPayload*(data: string): string =
  ## Decompress gzipped data
  result = uncompress(data)

proc compressAndEncode*(data: string): string =
  ## Compress then base64 encode
  import std/base64
  result = encode(compressPayload(data))

proc decodeAndDecompress*(data: string): string =
  ## Base64 decode then decompress
  import std/base64
  result = decompressPayload(decode(data))
```

### 3.2 Wire Format Utilities (`src/daemon/transport/nostr/wire.nim`)

```nim
## Wire format encoding/decoding

import compression, crypto, nip01
import std/base64

type
  WireEncoder* = object
    myPrivkey*: string
  
  WireDecoder* = object
    myPrivkey*: string

proc encode*(encoder: WireEncoder, kdl: string, recipientPubkey: string): string =
  ## KDL -> compress -> encrypt -> base64
  let compressed = compressPayload(kdl)
  let encrypted = encrypt(compressed, encoder.myPrivkey, recipientPubkey)
  result = encrypted  # Already base64 from encrypt()

proc decode*(decoder: WireDecoder, content: string, senderPubkey: string): string =
  ## base64 -> decrypt -> decompress -> KDL
  let decrypted = decrypt(content, decoder.myPrivkey, senderPubkey)
  result = decompressPayload(decrypted)
```

---

## Phase 4: Delta System

**Goal:** Generate and apply state deltas in KDL format.

### 4.1 Delta Generator (`src/engine/state/delta_generator.nim`)

```nim
## Generate KDL deltas from state changes

import std/[tables, options, strutils]
import kdl
import ../types/[game_state, core, fleet, colony, ship]

type
  DeltaType* {.pure.} = enum
    FleetMoved
    FleetDestroyed
    ColonyUpdated
    ColonyCaptured
    TechAdvance
    RelationChanged
    ShipCommissioned
    ShipDestroyed
    CombatResult

proc generateDelta*(
  prevState: GameState,
  newState: GameState,
  houseId: HouseId
): string =
  ## Generate KDL delta for a specific house's view
  var doc = newKdlDocument()
  var root = newKdlNode("delta")
  root.props["turn"] = newKdlVal(newState.turn)
  root.props["game"] = newKdlVal(newState.gameId)
  
  # Fleet movements
  for fleetId, fleet in newState.allFleets():
    if fleet.owner == houseId or fleet.isVisibleTo(houseId, newState):
      let prevFleet = prevState.fleet(fleetId)
      if prevFleet.isSome:
        if prevFleet.get().location != fleet.location:
          var node = newKdlNode("fleet-moved")
          node.props["id"] = newKdlVal(fleetId.uint32.int64)
          node.props["from"] = newKdlVal(prevFleet.get().location.uint32.int64)
          node.props["to"] = newKdlVal(fleet.location.uint32.int64)
          root.children.add(node)
  
  # Colony updates
  for colonyId, colony in newState.allColonies():
    if colony.owner == houseId:
      let prevColony = prevState.colony(colonyId)
      if prevColony.isSome:
        let pc = prevColony.get()
        if pc.population != colony.population or pc.industry != colony.industry:
          var node = newKdlNode("colony-updated")
          node.props["id"] = newKdlVal(colonyId.uint32.int64)
          var details = newKdlNode("_")
          details.props["population"] = newKdlVal(colony.population.int64)
          details.props["industry"] = newKdlVal(colony.industry.int64)
          node.children.add(details)
          root.children.add(node)
  
  # Events visible to this house
  var eventsNode = newKdlNode("events")
  for event in newState.lastTurnEvents:
    if event.isVisibleTo(houseId):
      var eventNode = newKdlNode("event")
      eventNode.props["type"] = newKdlVal($event.eventType)
      eventNode.props["description"] = newKdlVal(event.description)
      eventsNode.children.add(eventNode)
  root.children.add(eventsNode)
  
  doc.add(root)
  result = $doc
```

### 4.2 Delta Applicator (`src/player/state/delta_applicator.nim`)

```nim
## Apply KDL deltas to local player state

import kdl
import ../sam/tui_model
import ../../engine/types/[core, player_state]

proc applyDelta*(model: var TuiModel, kdlString: string) =
  ## Parse and apply delta to local state
  let doc = parseKdl(kdlString)
  let root = doc[0]
  
  for child in root.children:
    case child.name
    of "fleet-moved":
      let fleetId = FleetId(child.props["id"].getInt().uint32)
      let toSystem = SystemId(child.props["to"].getInt().uint32)
      # Update fleet location in model
      for i, fleet in model.ownFleets:
        if fleet.id == fleetId:
          model.ownFleets[i].location = toSystem
          break
    
    of "colony-updated":
      let colonyId = ColonyId(child.props["id"].getInt().uint32)
      if child.children.len > 0:
        let details = child.children[0]
        for i, colony in model.ownColonies:
          if colony.id == colonyId:
            if details.props.hasKey("population"):
              model.ownColonies[i].population = details.props["population"].getInt().int32
            if details.props.hasKey("industry"):
              model.ownColonies[i].industry = details.props["industry"].getInt().int32
            break
    
    of "events":
      for eventNode in child.children:
        # Add to event log
        discard
    
    else:
      discard
```

### 4.3 Delta Persistence (`src/daemon/persistence/delta_writer.nim`)

```nim
## Persist deltas to state_deltas table

import db_connector/db_sqlite
import std/times

proc saveDelta*(
  db: DbConn,
  gameId: string,
  turn: int,
  houseId: string,
  deltaKdl: string
) =
  db.exec(sql"""
    INSERT INTO state_deltas (
      game_id, turn, house_id, delta_type, data, created_at
    ) VALUES (?, ?, ?, 'turn_complete', ?, ?)
  """, gameId, turn, houseId, deltaKdl, getTime().toUnix())

proc loadDelta*(
  db: DbConn,
  gameId: string,
  turn: int,
  houseId: string
): string =
  let row = db.getRow(sql"""
    SELECT data FROM state_deltas
    WHERE game_id = ? AND turn = ? AND house_id = ?
  """, gameId, turn, houseId)
  if row[0].len > 0:
    result = row[0]
```

---

## Phase 5: Daemon Integration

**Goal:** Connect all pieces in the daemon.

### 5.1 Subscriber Module (`src/daemon/subscriber.nim`)

```nim
## Subscribe to player commands

import std/[asyncdispatch, tables]
import transport/nostr/[client, types, filter, wire]
import persistence/[reader, writer]
import parser/kdl_orders
import ../common/logger

type
  CommandSubscriber* = ref object
    gameId*: string
    daemonKeys*: KeyPair
    client*: NostrClient
    onCommand*: proc(packet: CommandPacket): Future[void]

proc newCommandSubscriber*(
  gameId: string,
  daemonKeys: KeyPair,
  relayUrl: string
): CommandSubscriber =
  result = CommandSubscriber(
    gameId: gameId,
    daemonKeys: daemonKeys,
    client: newNostrClient(relayUrl)
  )

proc start*(sub: CommandSubscriber) {.async.} =
  await sub.client.connect()
  
  let filter = commandFilter(sub.gameId, sub.daemonKeys.publicKey)
  
  await sub.client.subscribe(
    "commands-" & sub.gameId,
    @[filter],
    proc(subId: string, event: NostrEvent) {.async.} =
      logInfo("Subscriber", "Received command event")
      
      # Decrypt and decompress
      let decoder = WireDecoder(myPrivkey: sub.daemonKeys.privateKey)
      let kdl = decoder.decode(event.content, event.pubkey)
      
      # Parse command packet
      let packet = parseOrdersString(kdl)
      
      # Invoke callback
      if sub.onCommand != nil:
        await sub.onCommand(packet)
  )
  
  asyncCheck sub.client.listen()

proc stop*(sub: CommandSubscriber) {.async.} =
  await sub.client.disconnect()
```

### 5.2 Publisher Module (`src/daemon/publisher.nim`)

```nim
## Publish game state and deltas

import std/[asyncdispatch, tables]
import transport/nostr/[client, types, events, wire, crypto]
import ../engine/types/game_state
import ../engine/state/delta_generator
import ../common/logger

type
  StatePublisher* = ref object
    gameId*: string
    daemonKeys*: KeyPair
    client*: NostrClient

proc newStatePublisher*(
  gameId: string,
  daemonKeys: KeyPair,
  relayUrl: string
): StatePublisher =
  result = StatePublisher(
    gameId: gameId,
    daemonKeys: daemonKeys,
    client: newNostrClient(relayUrl)
  )

proc start*(pub: StatePublisher) {.async.} =
  await pub.client.connect()

proc publishDelta*(
  pub: StatePublisher,
  prevState: GameState,
  newState: GameState,
  housePubkey: string,
  houseId: HouseId
) {.async.} =
  ## Publish encrypted delta for a specific house
  
  # Generate delta KDL
  let deltaKdl = generateDelta(prevState, newState, houseId)
  
  # Encode: compress + encrypt
  let encoder = WireEncoder(myPrivkey: pub.daemonKeys.privateKey)
  let content = encoder.encode(deltaKdl, housePubkey)
  
  # Create and sign event
  var event = newEvent(
    30403,  # Turn Results
    content,
    @[
      @["d", pub.gameId],
      @["turn", $newState.turn],
      @["p", housePubkey]
    ]
  )
  event.pubkey = pub.daemonKeys.publicKey
  event.id = computeEventId(event)
  # TODO: Sign event
  event.sig = "stub-signature"
  
  discard await pub.client.publish(event)
  logInfo("Publisher", "Published delta for house ", $houseId)

proc publishFullState*(
  pub: StatePublisher,
  state: GameState,
  housePubkey: string,
  houseId: HouseId
) {.async.} =
  ## Publish full state for initial sync
  
  # Generate full state KDL
  let stateKdl = generateFullState(state, houseId)
  
  # Encode
  let encoder = WireEncoder(myPrivkey: pub.daemonKeys.privateKey)
  let content = encoder.encode(stateKdl, housePubkey)
  
  # Create event
  var event = newEvent(
    30405,  # Game State
    content,
    @[
      @["d", pub.gameId],
      @["turn", $state.turn],
      @["p", housePubkey]
    ]
  )
  event.pubkey = pub.daemonKeys.publicKey
  event.id = computeEventId(event)
  event.sig = "stub-signature"
  
  discard await pub.client.publish(event)
  logInfo("Publisher", "Published full state for house ", $houseId)

proc stop*(pub: StatePublisher) {.async.} =
  await pub.client.disconnect()
```

---

## Phase 6: Player Client Integration

**Goal:** TUI receives state updates and submits commands via Nostr.

### 6.1 Player Nostr Client (`src/player/nostr/client.nim`)

```nim
## Player-side Nostr client

import std/[asyncdispatch, tables]
import ../../daemon/transport/nostr/[client, types, filter, wire, crypto]
import ../state/delta_applicator
import ../sam/tui_model

type
  PlayerNostrClient* = ref object
    gameId*: string
    playerKeys*: KeyPair
    daemonPubkey*: string
    client*: NostrClient
    model*: ptr TuiModel

proc newPlayerNostrClient*(
  gameId: string,
  playerKeys: KeyPair,
  daemonPubkey: string,
  relayUrl: string
): PlayerNostrClient =
  result = PlayerNostrClient(
    gameId: gameId,
    playerKeys: playerKeys,
    daemonPubkey: daemonPubkey,
    client: newNostrClient(relayUrl)
  )

proc start*(pc: PlayerNostrClient) {.async.} =
  await pc.client.connect()
  
  # Subscribe to state updates
  let filter = NostrFilter(
    kinds: @[30403, 30405],
    tags: {
      "d": @[pc.gameId],
      "p": @[pc.playerKeys.publicKey]
    }.toTable()
  )
  
  await pc.client.subscribe(
    "state-" & pc.gameId,
    @[filter],
    proc(subId: string, event: NostrEvent) {.async.} =
      # Decrypt and decompress
      let decoder = WireDecoder(myPrivkey: pc.playerKeys.privateKey)
      let kdl = decoder.decode(event.content, event.pubkey)
      
      if event.kind == 30403:
        # Apply delta
        pc.model[].applyDelta(kdl)
      elif event.kind == 30405:
        # Full state sync
        pc.model[].loadFullState(kdl)
  )
  
  asyncCheck pc.client.listen()

proc submitCommands*(pc: PlayerNostrClient, commandKdl: string) {.async.} =
  ## Submit player commands
  
  # Encode: compress + encrypt to daemon
  let encoder = WireEncoder(myPrivkey: pc.playerKeys.privateKey)
  let content = encoder.encode(commandKdl, pc.daemonPubkey)
  
  # Create event
  var event = newEvent(
    30402,  # Turn Commands
    content,
    @[
      @["d", pc.gameId],
      @["p", pc.daemonPubkey]
    ]
  )
  event.pubkey = pc.playerKeys.publicKey
  event.id = computeEventId(event)
  event.sig = "stub-signature"
  
  discard await pc.client.publish(event)

proc stop*(pc: PlayerNostrClient) {.async.} =
  await pc.client.disconnect()
```

---

## Phase 7: Testing

### 7.1 Unit Tests

```bash
# Test Nostr client
nim c -r tests/unit/test_nostr_client.nim

# Test compression
nim c -r tests/unit/test_compression.nim

# Test delta generation
nim c -r tests/unit/test_delta_generator.nim
```

### 7.2 Integration Tests

```bash
# Test full flow
nim c -r tests/integration/test_nostr_transport.nim

# Test with real relay
RELAY_URL=ws://localhost:8080 nim c -r tests/integration/test_relay_connection.nim
```

### 7.3 End-to-End Test Script

```bash
#!/bin/bash
# scripts/e2e_nostr_test.sh

set -e

# Start relay
cd ~/dev/nostr-rs-relay
./target/release/nostr-rs-relay -c config.toml &
RELAY_PID=$!
sleep 2

cd ~/dev/ec4x

# Create game
GAME_ID=$(./bin/ec4x new --name "E2E Test" | grep "Game ID:" | cut -d: -f2 | tr -d ' ')

# Assign test players
sqlite3 "data/games/$GAME_ID/ec4x.db" << EOF
UPDATE houses SET nostr_pubkey = 'test-alpha' WHERE name LIKE '%Alpha%';
EOF

# Start daemon
./bin/ec4x-daemon start &
DAEMON_PID=$!
sleep 3

# Resolve turn
./bin/ec4x-daemon resolve --gameId "$GAME_ID"

# Verify events published
echo '["REQ","test",{"kinds":[30403],"#d":["'"$GAME_ID"'"]}]' | \
  timeout 5 websocat ws://localhost:8080 | grep -q "EVENT" && \
  echo "SUCCESS: Delta published" || echo "FAILED: No delta found"

# Cleanup
kill $DAEMON_PID $RELAY_PID 2>/dev/null

echo "E2E test complete"
```

---

## Implementation Checklist

### Phase 1: Nostr Client Foundation
- [ ] `src/daemon/transport/nostr/client.nim` - WebSocket client
- [ ] `src/daemon/transport/nostr/nip01.nim` - Event handling
- [ ] `src/daemon/transport/nostr/filter.nim` - Subscription filters
- [ ] `src/daemon/transport/nostr/types.nim` - Type definitions

### Phase 2: NIP-44 Encryption
- [ ] `src/daemon/transport/nostr/crypto.nim` - ECDH + ChaCha20
- [ ] `src/daemon/identity.nim` - Keypair management
- [ ] Test encryption/decryption roundtrip

### Phase 3: Compression Layer
- [ ] `src/daemon/transport/nostr/compression.nim` - zippy integration
- [ ] `src/daemon/transport/nostr/wire.nim` - Wire format encoding
- [ ] Test compression ratio

### Phase 4: Delta System
- [ ] `src/engine/state/delta_generator.nim` - Generate KDL deltas
- [ ] `src/player/state/delta_applicator.nim` - Apply deltas
- [ ] `src/daemon/persistence/delta_writer.nim` - Persist deltas
- [ ] Rename `kdl_orders.nim` to `kdl_commands.nim`

### Phase 5: Daemon Integration
- [ ] `src/daemon/subscriber.nim` - Command subscription
- [ ] `src/daemon/publisher.nim` - State publishing
- [ ] Update `daemon.nim` main loop

### Phase 6: Player Client
- [ ] `src/player/nostr/client.nim` - Player Nostr client
- [ ] Update TUI to use Nostr for state sync
- [ ] Implement command submission UI

### Phase 7: Testing
- [ ] Unit tests for each module
- [ ] Integration tests with local relay
- [ ] E2E test script
- [ ] Test against public relay

---

## Timeline Estimate

| Phase | Duration | Dependencies |
|-------|----------|--------------|
| 1. Nostr Client | 2-3 days | ws library |
| 2. NIP-44 | 2-3 days | nimcrypto |
| 3. Compression | 1 day | zippy |
| 4. Delta System | 2-3 days | KDL, game state types |
| 5. Daemon Integration | 2-3 days | Phases 1-4 |
| 6. Player Client | 2-3 days | Phases 1-5 |
| 7. Testing | 2-3 days | All phases |

**Total: 2-3 weeks**

---

## Related Documentation

- [Local Development Guide](local-nostr-development.md)
- [Nostr Protocol Specification](../architecture/nostr-protocol.md)
- [Transport Architecture](../architecture/transport.md)
- [Storage Architecture](../architecture/storage.md)
