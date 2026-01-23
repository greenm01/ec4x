## Player-side Nostr client wrapper for EC4X.

import std/[asyncdispatch, options]
import ../../daemon/transport/nostr/[client, types, events, wire, crypto]
import ../../common/logger

export types
export crypto

type
  PlayerNostrHandlers* = object
    onDelta*: proc(event: NostrEvent, kdl: string) {.closure.}
    onFullState*: proc(event: NostrEvent, kdl: string) {.closure.}
    onEvent*: proc(subId: string, event: NostrEvent) {.closure.}
    onJoinError*: proc(message: string) {.closure.}
    onError*: proc(message: string) {.closure.}

  PlayerNostrClient* = ref object
    gameId*: string
    daemonPubkey*: string
    playerPrivHex*: string
    playerPubHex*: string
    client*: NostrClient
    handlers*: PlayerNostrHandlers


proc handleError(pc: PlayerNostrClient, message: string) =
  logWarn("Nostr", message)
  if pc.handlers.onError != nil:
    pc.handlers.onError(message)

proc hexToBytes32Safe*(hexStr: string): Option[array[32, byte]] =
  try:
    some(crypto.hexToBytes32(hexStr))
  except CatchableError:
    none(array[32, byte])

proc handleEvent*(pc: PlayerNostrClient, subId: string, event: NostrEvent) =
  logDebug("Nostr/Player", "handleEvent",
    "subId=", subId,
    "kind=", $event.kind,
    "eventId=", event.id[0..min(15, event.id.len-1)])
  if event.kind == EventKindTurnResults or
      event.kind == EventKindGameState or
      event.kind == EventKindJoinError:
    let privOpt = hexToBytes32Safe(pc.playerPrivHex)
    let pubOpt = hexToBytes32Safe(event.pubkey)
    if privOpt.isNone or pubOpt.isNone:
      pc.handleError("Invalid key material")
      return
    try:
      let payload = decodePayload(event.content, privOpt.get(), pubOpt.get())
      if event.kind == EventKindTurnResults:
        if pc.handlers.onDelta != nil:
          pc.handlers.onDelta(event, payload)
      elif event.kind == EventKindGameState:
        if pc.handlers.onFullState != nil:
          pc.handlers.onFullState(event, payload)
      else:
        if pc.handlers.onJoinError != nil:
          pc.handlers.onJoinError(payload)
    except CatchableError as e:
      pc.handleError("Failed to decode payload: " & e.msg)
  else:
    if pc.handlers.onEvent != nil:
      pc.handlers.onEvent(subId, event)

proc newPlayerNostrClient*(
  relays: seq[string],
  gameId: string,
  playerPrivHex: string,
  playerPubHex: string,
  daemonPubkey: string,
  handlers: PlayerNostrHandlers
): PlayerNostrClient =
  result = PlayerNostrClient(
    gameId: gameId,
    daemonPubkey: daemonPubkey,
    playerPrivHex: playerPrivHex,
    playerPubHex: playerPubHex,
    client: newNostrClient(relays),
    handlers: handlers
  )

  let pc = result
  pc.client.onEvent = proc(subId: string, event: NostrEvent) =
    pc.handleEvent(subId, event)

proc start*(pc: PlayerNostrClient) {.async.} =
  await pc.client.connect()

proc listen*(pc: PlayerNostrClient) {.async.} =
  await pc.client.listen()

proc stop*(pc: PlayerNostrClient) {.async.} =
  await pc.client.disconnect()

proc isConnected*(pc: PlayerNostrClient): bool =
  pc.client.isConnected()

proc subscribe*(pc: PlayerNostrClient, subId: string,
    filters: seq[NostrFilter]) {.async.} =
  await pc.client.subscribe(subId, filters)

proc subscribeGame*(pc: PlayerNostrClient, gameId: string) {.async.} =
  pc.gameId = gameId
  await pc.client.subscribeGame(gameId, pc.playerPubHex)

proc publish*(pc: PlayerNostrClient, event: NostrEvent): Future[bool] {.async.} =
  await pc.client.publish(event)

proc setDaemonPubkey*(pc: PlayerNostrClient, daemonPubkey: string) =
  pc.daemonPubkey = daemonPubkey

proc setGameId*(pc: PlayerNostrClient, gameId: string) =
  pc.gameId = gameId

proc submitCommands*(
  pc: PlayerNostrClient,
  commandKdl: string,
  turn: int
): Future[bool] {.async.} =
  if pc.daemonPubkey.len == 0:
    pc.handleError("Missing daemon pubkey")
    return false
  if pc.gameId.len == 0:
    pc.handleError("Missing game id")
    return false

  let privOpt = hexToBytes32Safe(pc.playerPrivHex)
  let daemonOpt = hexToBytes32Safe(pc.daemonPubkey)
  if privOpt.isNone or daemonOpt.isNone:
    pc.handleError("Invalid key material")
    return false

  let encrypted = encodePayload(commandKdl, privOpt.get(), daemonOpt.get())
  var event = createTurnCommands(
    gameId = pc.gameId,
    turn = turn,
    encryptedPayload = encrypted,
    daemonPubkey = pc.daemonPubkey,
    playerPubkey = pc.playerPubHex
  )
  signEvent(event, privOpt.get())
  await pc.client.publish(event)
