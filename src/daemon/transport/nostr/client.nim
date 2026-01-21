## Nostr WebSocket client for connecting to relays
##
## Uses treeform/ws library for WebSocket connections.
## Supports multiple relays with automatic reconnection.

import std/[asyncdispatch, tables, strutils, sequtils]
import ws
import types, nip01, filter
import ../../../common/logger

type
  RelayConnection* = object
    url*: string
    socket*: WebSocket
    state*: ConnectionState

  EventCallback* = proc(subId: string, event: NostrEvent) {.closure.}
  EoseCallback* = proc(subId: string) {.closure.}
  OkCallback* = proc(eventId: string, accepted: bool, msg: string) {.closure.}
  NoticeCallback* = proc(msg: string) {.closure.}

  NostrClient* = ref object
    relays*: seq[string]
    connections*: Table[string, RelayConnection]
    subscriptions*: Table[string, seq[NostrFilter]]
    onEvent*: EventCallback
    onEose*: EoseCallback
    onOk*: OkCallback
    onNotice*: NoticeCallback
    running*: bool

# =============================================================================
# Client Creation
# =============================================================================

proc newNostrClient*(relays: seq[string]): NostrClient =
  ## Create new Nostr client for connecting to relays
  result = NostrClient(
    relays: relays,
    connections: initTable[string, RelayConnection](),
    subscriptions: initTable[string, seq[NostrFilter]](),
    running: false
  )

# =============================================================================
# Connection Management
# =============================================================================

proc connectToRelay(client: NostrClient, url: string) {.async.} =
  ## Connect to a single relay
  try:
    logDebug("Nostr", "Connecting to relay: ", url)
    let socket = await newWebSocket(url)
    client.connections[url] = RelayConnection(
      url: url,
      socket: socket,
      state: ConnectionState.Connected
    )
    logDebug("Nostr", "Connected to relay: ", url)
  except CatchableError as e:
    logError("Nostr", "Failed to connect to relay: ", url, " - ", e.msg)
    client.connections[url] = RelayConnection(
      url: url,
      state: ConnectionState.Disconnected
    )

proc connect*(client: NostrClient) {.async.} =
  ## Connect to all configured relays
  logInfo("Nostr", "Connecting to ", $client.relays.len, " relays")
  
  var futures: seq[Future[void]] = @[]
  for url in client.relays:
    futures.add(client.connectToRelay(url))
  
  await all(futures)
  
  let connected = client.connections.values.toSeq.filterIt(
    it.state == ConnectionState.Connected
  ).len
  logDebug("Nostr", "Connected to ", $connected, "/", $client.relays.len,
    " relays")

proc disconnect*(client: NostrClient) {.async.} =
  ## Disconnect from all relays
  client.running = false
  
  for url, conn in client.connections.pairs:
    if conn.state == ConnectionState.Connected:
      try:
        conn.socket.close()
        logDebug("Nostr", "Disconnected from: ", url)
      except CatchableError:
        discard
  
  client.connections.clear()
  logInfo("Nostr", "Disconnected from all relays")

proc isConnected*(client: NostrClient): bool =
  ## Check if connected to at least one relay
  for conn in client.connections.values:
    if conn.state == ConnectionState.Connected:
      return true
  return false

# =============================================================================
# Subscriptions
# =============================================================================

proc subscribe*(client: NostrClient, subId: string,
    filters: seq[NostrFilter]) {.async.} =
  ## Subscribe to events matching filters on all connected relays
  client.subscriptions[subId] = filters

  let filterJsons = filters.mapIt(it.toJson())
  let reqMsg = makeReqMessage(subId, filterJsons)

  for url, conn in client.connections.mpairs:
    if conn.state == ConnectionState.Connected:
      try:
        await conn.socket.send(reqMsg)
        logDebug("Nostr", "Subscribed ", subId, " on ", url)
      except CatchableError as e:
        logError("Nostr", "Failed to subscribe on ", url, ": ", e.msg)
        conn.state = ConnectionState.Disconnected

proc resubscribeAll*(client: NostrClient) {.async.} =
  ## Re-send subscriptions to all connected relays
  for subId, filters in client.subscriptions.pairs:
    await client.subscribe(subId, filters)

proc reconnectWithBackoff*(client: NostrClient, backoffMs: int,
  maxBackoffMs: int): Future[int] {.async.} =
  ## Reconnect with backoff, returning next backoff delay
  var delayMs = backoffMs
  if delayMs <= 0:
    delayMs = 1000

  await client.connect()
  if client.isConnected():
    await client.resubscribeAll()
    logInfo("Nostr", "Reconnected to relays and resubscribed")
    return 1000

  logWarn("Nostr", "Reconnect failed; retrying in ", $delayMs, "ms")
  await sleepAsync(delayMs)
  min(delayMs * 2, maxBackoffMs)

proc unsubscribe*(client: NostrClient, subId: string) {.async.} =
  ## Unsubscribe from a subscription on all relays
  let closeMsg = makeCloseMessage(subId)
  
  for url, conn in client.connections.mpairs:
    if conn.state == ConnectionState.Connected:
      try:
        await conn.socket.send(closeMsg)
      except CatchableError:
        discard
  
  client.subscriptions.del(subId)
  logDebug("Nostr", "Unsubscribed: ", subId)

# =============================================================================
# Publishing
# =============================================================================

proc publish*(client: NostrClient, event: NostrEvent): Future[bool] {.async.} =
  ## Publish event to all connected relays
  ## Returns true if at least one relay accepted the event
  let eventMsg = makeEventMessage(event)
  var published = false
  
  for url, conn in client.connections.mpairs:
    if conn.state == ConnectionState.Connected:
      try:
        await conn.socket.send(eventMsg)
        published = true
        logDebug("Nostr", "Published event ", event.id[0..7], " to ", url)
      except CatchableError as e:
        logError("Nostr", "Failed to publish to ", url, ": ", e.msg)
        conn.state = ConnectionState.Disconnected
  
  return published

# =============================================================================
# Message Handling
# =============================================================================

proc handleMessage(client: NostrClient, url: string, data: string) =
  ## Handle incoming message from relay
  try:
    let msg = parseRelayMessage(data)
    
    case msg.kind
    of RelayMessageKind.Event:
      if client.onEvent != nil:
        client.onEvent(msg.subscriptionId, msg.event)
    
    of RelayMessageKind.Eose:
      if client.onEose != nil:
        client.onEose(msg.eoseSubId)
      logDebug("Nostr", "EOSE for ", msg.eoseSubId, " from ", url)
    
    of RelayMessageKind.Ok:
      if client.onOk != nil:
        client.onOk(msg.eventId, msg.accepted, msg.message)
      if not msg.accepted:
        logWarn("Nostr", "Event rejected by ", url, ": ", msg.message)
    
    of RelayMessageKind.Notice:
      if client.onNotice != nil:
        client.onNotice(msg.notice)
      logInfo("Nostr", "Notice from ", url, ": ", msg.notice)
    
    of RelayMessageKind.Closed:
      logWarn("Nostr", "Subscription ", msg.closedSubId, " closed by ", url,
        ": ", msg.reason)
    
    of RelayMessageKind.Auth:
      logWarn("Nostr", "Auth challenge from ", url, " (NIP-42 not implemented)")
  
  except CatchableError as e:
    logError("Nostr", "Failed to parse message from ", url, ": ", e.msg)

proc listenToRelay(client: NostrClient, url: string) {.async.} =
  ## Listen for messages from a single relay
  if url notin client.connections:
    return
  
  while client.running:
    let conn = client.connections[url]
    if conn.state != ConnectionState.Connected:
      break
    
    try:
      let (opcode, data) = await conn.socket.receivePacket()
      
      case opcode
      of Opcode.Text:
        client.handleMessage(url, data)
      of Opcode.Close:
        logInfo("Nostr", "Connection closed by relay: ", url)
        client.connections[url].state = ConnectionState.Disconnected
        break
      of Opcode.Ping:
        await conn.socket.send(data, Opcode.Pong)
      else:
        discard
    
    except CatchableError as e:
      logError("Nostr", "Error receiving from ", url, ": ", e.msg)
      client.connections[url].state = ConnectionState.Disconnected
      break

proc listen*(client: NostrClient) {.async.} =
  ## Listen for incoming messages from all relays
  ## This runs until disconnect() is called
  client.running = true
  logInfo("Nostr", "Starting relay listeners")
  
  var futures: seq[Future[void]] = @[]
  for url in client.connections.keys:
    futures.add(client.listenToRelay(url))
  
  await all(futures)
  logInfo("Nostr", "All relay listeners stopped")

# =============================================================================
# Convenience Methods
# =============================================================================

proc subscribeGame*(client: NostrClient, gameId: string,
    playerPubkey: string) {.async.} =
  ## Subscribe to all events for a game relevant to this player
  let filters = @[
    # Game definition updates
    newFilter()
      .withKinds(@[EventKindGameDefinition])
      .withTag(TagD, @[gameId]),
    # Turn results (deltas) for this player
    newFilter()
      .withKinds(@[EventKindTurnResults])
      .withTag(TagD, @[gameId])
      .withTag(TagP, @[playerPubkey]),
    # Full state snapshots for this player
    newFilter()
      .withKinds(@[EventKindGameState])
      .withTag(TagD, @[gameId])
      .withTag(TagP, @[playerPubkey])
  ]
  
  await client.subscribe("game:" & gameId, filters)

proc subscribeDaemon*(client: NostrClient, gameId: string,
    daemonPubkey: string) {.async.} =
  ## Subscribe to commands from all players for daemon processing
  let filters = @[
    # Player commands for this game
    newFilter()
      .withKinds(@[EventKindTurnCommands])
      .withTag(TagD, @[gameId])
      .withTag(TagP, @[daemonPubkey]),
    # Slot claims
    newFilter()
      .withKinds(@[EventKindPlayerSlotClaim])
      .withTag(TagD, @[gameId])
  ]
  
  await client.subscribe("daemon:" & gameId, filters)
