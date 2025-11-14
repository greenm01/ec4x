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

proc subscribeToGame*(sub: Subscriber, gameId: string, currentTurn: int) {.async.} =
  ## Subscribe to order events for a specific game
  ## TODO: Implement subscription to game orders
  raise newException(CatchableError, "Not yet implemented")

proc start*(sub: Subscriber) {.async.} =
  ## Start listening for events
  ## TODO: Implement event listening loop
  raise newException(CatchableError, "Not yet implemented")

proc stop*(sub: Subscriber) {.async.} =
  ## Stop subscriber and disconnect
  ## TODO: Implement graceful shutdown
  raise newException(CatchableError, "Not yet implemented")
