## Daemon subscriber - listens for Nostr relay events

import std/asyncdispatch
import ../common/logger
import ./transport/nostr/[types, client, filter]

type
  Subscriber* = ref object
    client*: NostrClient
    onCommand*: proc(event: NostrEvent) {.closure.}
    onSlotClaim*: proc(event: NostrEvent) {.closure.}
    onMessage*: proc(event: NostrEvent) {.closure.}

proc newSubscriber*(client: NostrClient): Subscriber =
  ## Create new subscriber wrapper for a Nostr client
  result = Subscriber(client: client)

proc attachHandlers*(sub: Subscriber) =
  ## Attach event handler to client
  ## Attach event handler to client
  sub.client.onEvent = proc(subId: string, event: NostrEvent) =
    try:
      logDebug("Nostr", "Received event: kind=", $event.kind, " sub=", subId,
        " pubkey=", event.pubkey[0..7])
    except CatchableError:
      logDebug("Nostr", "Received event: kind=", $event.kind, " sub=", subId)

    if event.kind == EventKindPlayerSlotClaim:
      if sub.onSlotClaim != nil:
        sub.onSlotClaim(event)
    elif event.kind == EventKindTurnCommands:
      if sub.onCommand != nil:
        sub.onCommand(event)
    elif event.kind == EventKindPlayerMessage:
      if sub.onMessage != nil:
        sub.onMessage(event)

proc subscribeDaemon*(sub: Subscriber, gameId: string,
  daemonPubkey: string) {.async.} =
  ## Subscribe to command + slot claim events for a game
  await sub.client.subscribeDaemon(gameId, daemonPubkey)

proc subscribeInviteClaims*(sub: Subscriber) {.async.} =
  ## Subscribe to invite-only slot claims
  let filter = newFilter()
    .withKinds(@[EventKindPlayerSlotClaim])
    .withTag(TagD, @["invite"])
  await sub.client.subscribe("daemon:invite", @[filter])
