## Daemon subscriber - listens for order events on Nostr relays

import std/asyncdispatch
import ../transport/nostr/[types, client, filter]

type
  Subscriber* = ref object
    client*: NostrClient
    gameIds*: seq[string]
    onOrderReceived*: proc(event: NostrEvent)

proc newSubscriber*(relays: seq[string]): Subscriber =
  ## Create new subscriber for game events
  result = Subscriber(
    client: newNostrClient(relays),
    gameIds: @[]
  )

proc subscribeToGame*(sub: Subscriber, gameId: string, currentTurn: int): Proposal[DaemonModel] {.async.} =
  ## Stub sub → order Proposal
  logInfo(\"Nostr subscriber\", \"Stub subscribed game \", gameId, \" turn \", $currentTurn)
  Proposal[DaemonModel](
    name: \"order_received_nostr\",
    payload: proc(model: var DaemonModel) =
      model.pendingOrders[gameId] += 1  # Stub 1 order
      if model.pendingOrders[gameId] >= 4:  # Stub ready
        daemonLoop.queueCmd(resolveTurnCmd(gameId))
  )

proc start*(sub: Subscriber) {.async.} =
  ## Start listening for events
  ## TODO: Implement event listening loop
  raise newException(CatchableError, "Not yet implemented")

proc stop*(sub: Subscriber) {.async.} =
  ## Stop subscriber and disconnect
  ## TODO: Implement graceful shutdown
  raise newException(CatchableError, "Not yet implemented")
