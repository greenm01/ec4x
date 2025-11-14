## Nostr event creation, parsing, and EC4X-specific event builders

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
  ## TODO: Implement JSON parsing
  raise newException(CatchableError, "Not yet implemented")

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
  ## TODO: Implement with encryption
  raise newException(CatchableError, "Not yet implemented")

proc createGameState*(gameId: string, house: string, turnNum: int,
                     stateJson: string, playerPubkey: string,
                     moderatorKeys: KeyPair): NostrEvent =
  ## Create encrypted game state for specific player
  ## TODO: Implement with encryption
  raise newException(CatchableError, "Not yet implemented")

proc createTurnComplete*(gameId: string, turnNum: int,
                        summaryJson: string,
                        moderatorKeys: KeyPair): NostrEvent =
  ## Create public turn completion announcement
  ## TODO: Implement event creation and signing
  raise newException(CatchableError, "Not yet implemented")
