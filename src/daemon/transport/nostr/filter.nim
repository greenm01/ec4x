## Nostr subscription filters for querying events

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
