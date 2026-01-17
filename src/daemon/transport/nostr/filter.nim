## Nostr subscription filters for querying events
##
## Provides fluent API for building NIP-01 filters and
## EC4X-specific filter presets.

import std/[json, options, tables]
import types

# =============================================================================
# Filter Construction
# =============================================================================

proc newFilter*(): NostrFilter =
  ## Create empty filter
  result = NostrFilter(
    ids: @[],
    authors: @[],
    kinds: @[],
    tags: initTable[string, seq[string]]()
  )

proc withIds*(filter: NostrFilter, ids: seq[string]): NostrFilter =
  ## Filter by event IDs
  result = filter
  result.ids = ids

proc withKinds*(filter: NostrFilter, kinds: seq[int]): NostrFilter =
  ## Filter by event kinds
  result = filter
  result.kinds = kinds

proc withAuthors*(filter: NostrFilter, authors: seq[string]): NostrFilter =
  ## Filter by author pubkeys
  result = filter
  result.authors = authors

proc withTag*(filter: NostrFilter, tagName: string,
    values: seq[string]): NostrFilter =
  ## Add tag filter (e.g., #d for identifier, #p for recipient)
  result = filter
  result.tags[tagName] = values

proc withSince*(filter: NostrFilter, timestamp: int64): NostrFilter =
  ## Filter events created after timestamp
  result = filter
  result.since = some(timestamp)

proc withUntil*(filter: NostrFilter, timestamp: int64): NostrFilter =
  ## Filter events created before timestamp
  result = filter
  result.until = some(timestamp)

proc withLimit*(filter: NostrFilter, limit: int): NostrFilter =
  ## Limit number of results
  result = filter
  result.limit = some(limit)

# =============================================================================
# JSON Serialization
# =============================================================================

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

# =============================================================================
# EC4X-Specific Filters
# =============================================================================

proc filterGameDefinition*(gameId: string): NostrFilter =
  ## Filter for game definition/lobby events
  result = newFilter()
    .withKinds(@[EventKindGameDefinition])
    .withTag(TagD, @[gameId])

proc filterSlotClaims*(gameId: string): NostrFilter =
  ## Filter for player slot claim events
  result = newFilter()
    .withKinds(@[EventKindPlayerSlotClaim])
    .withTag(TagD, @[gameId])

proc filterTurnCommands*(gameId: string, daemonPubkey: string,
    turn: int): NostrFilter =
  ## Filter for player commands for a specific turn
  ## Commands are encrypted to the daemon's pubkey
  result = newFilter()
    .withKinds(@[EventKindTurnCommands])
    .withTag(TagD, @[gameId])
    .withTag(TagP, @[daemonPubkey])
    .withTag(TagTurn, @[$turn])

proc filterTurnResults*(gameId: string, playerPubkey: string): NostrFilter =
  ## Filter for turn results (deltas) sent to a player
  result = newFilter()
    .withKinds(@[EventKindTurnResults])
    .withTag(TagD, @[gameId])
    .withTag(TagP, @[playerPubkey])

proc filterGameState*(gameId: string, playerPubkey: string): NostrFilter =
  ## Filter for full game state snapshots sent to a player
  result = newFilter()
    .withKinds(@[EventKindGameState])
    .withTag(TagD, @[gameId])
    .withTag(TagP, @[playerPubkey])

proc filterAllPlayerData*(gameId: string, playerPubkey: string): NostrFilter =
  ## Filter for all data sent to a player (results + state)
  result = newFilter()
    .withKinds(@[EventKindTurnResults, EventKindGameState])
    .withTag(TagD, @[gameId])
    .withTag(TagP, @[playerPubkey])

proc filterGameHistory*(gameId: string, since: int64): NostrFilter =
  ## Filter for all game events since timestamp (for catch-up)
  result = newFilter()
    .withKinds(@[
      EventKindGameDefinition,
      EventKindPlayerSlotClaim,
      EventKindTurnCommands,
      EventKindTurnResults,
      EventKindGameState
    ])
    .withTag(TagD, @[gameId])
    .withSince(since)
