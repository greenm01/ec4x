## NIP-01: Basic Nostr Protocol
##
## Implements event creation, serialization, parsing, and ID computation.
## https://github.com/nostr-protocol/nips/blob/master/01.md

import std/[json, strutils, times, sequtils]
import nimcrypto/[sha2, utils]
import types

# =============================================================================
# Event ID Computation
# =============================================================================

proc computeEventId*(event: NostrEvent): string =
  ## Compute event ID as SHA-256 of the serialized event.
  ## The serialization is: [0, pubkey, created_at, kind, tags, content]
  let serialized = $(%*[
    0,
    event.pubkey,
    event.created_at,
    event.kind,
    event.tags,
    event.content
  ])
  
  var hash: array[32, byte]
  sha256.digest(serialized.cstring, serialized.len.uint, hash)
  result = hash.toHex().toLowerAscii()

proc serializeForSigning*(event: NostrEvent): string =
  ## Serialize event for Schnorr signing (same as ID computation input)
  result = $(%*[
    0,
    event.pubkey,
    event.created_at,
    event.kind,
    event.tags,
    event.content
  ])

# =============================================================================
# Event Serialization
# =============================================================================

proc toJson*(event: NostrEvent): JsonNode =
  ## Serialize event to JSON for transmission
  result = %*{
    "id": event.id,
    "pubkey": event.pubkey,
    "created_at": event.created_at,
    "kind": event.kind,
    "tags": event.tags,
    "content": event.content,
    "sig": event.sig
  }

proc `$`*(event: NostrEvent): string =
  ## String representation of event
  $event.toJson()

# =============================================================================
# Event Parsing
# =============================================================================

proc parseNostrEvent*(j: JsonNode): NostrEvent =
  ## Parse JsonNode into NostrEvent
  result = NostrEvent(
    id: j["id"].getStr(),
    pubkey: j["pubkey"].getStr(),
    created_at: j["created_at"].getBiggestInt(),
    kind: j["kind"].getInt(),
    content: j["content"].getStr(),
    sig: j["sig"].getStr(),
    tags: @[]
  )
  
  for tag in j["tags"]:
    var tagSeq: seq[string] = @[]
    for item in tag:
      tagSeq.add(item.getStr())
    result.tags.add(tagSeq)

proc parseNostrEvent*(jsonStr: string): NostrEvent =
  ## Parse JSON string into NostrEvent
  let j = parseJson(jsonStr)
  result = parseNostrEvent(j)

# =============================================================================
# Event Creation
# =============================================================================

proc newEvent*(
  kind: int,
  content: string,
  tags: seq[seq[string]] = @[],
  pubkey: string = ""
): NostrEvent =
  ## Create a new unsigned event
  result = NostrEvent(
    pubkey: pubkey,
    created_at: getTime().toUnix(),
    kind: kind,
    tags: tags,
    content: content,
    id: "",
    sig: ""
  )

proc finalizeEvent*(event: var NostrEvent, pubkey: string) =
  ## Set pubkey and compute event ID (call before signing)
  event.pubkey = pubkey
  event.id = computeEventId(event)

# =============================================================================
# Tag Helpers
# =============================================================================

proc addTag*(event: var NostrEvent, tag: seq[string]) =
  ## Add a tag to an event
  event.tags.add(tag)

proc addTag*(event: var NostrEvent, name: string, values: varargs[string]) =
  ## Add a tag with name and values
  var tag = @[name]
  for v in values:
    tag.add(v)
  event.tags.add(tag)

proc getTag*(event: NostrEvent, tagName: string): Option[seq[string]] =
  ## Get first tag matching name
  for tag in event.tags:
    if tag.len > 0 and tag[0] == tagName:
      return some(tag)
  return none(seq[string])

proc getTagValue*(event: NostrEvent, tagName: string): Option[string] =
  ## Get value of first tag matching name (tag[1])
  let tag = event.getTag(tagName)
  if tag.isSome and tag.get().len > 1:
    return some(tag.get()[1])
  return none(string)

proc getTags*(event: NostrEvent, tagName: string): seq[seq[string]] =
  ## Get all tags matching name
  result = @[]
  for tag in event.tags:
    if tag.len > 0 and tag[0] == tagName:
      result.add(tag)

# =============================================================================
# Relay Message Parsing
# =============================================================================

proc parseRelayMessage*(jsonStr: string): RelayMessage =
  ## Parse relay message from JSON array
  let j = parseJson(jsonStr)
  let msgType = j[0].getStr()
  
  case msgType
  of "EVENT":
    result = RelayMessage(
      kind: RelayMessageKind.Event,
      subscriptionId: j[1].getStr(),
      event: parseNostrEvent(j[2])
    )
  
  of "OK":
    result = RelayMessage(
      kind: RelayMessageKind.Ok,
      eventId: j[1].getStr(),
      accepted: j[2].getBool(),
      message: if j.len > 3: j[3].getStr() else: ""
    )
  
  of "EOSE":
    result = RelayMessage(
      kind: RelayMessageKind.Eose,
      eoseSubId: j[1].getStr()
    )
  
  of "CLOSED":
    result = RelayMessage(
      kind: RelayMessageKind.Closed,
      closedSubId: j[1].getStr(),
      reason: if j.len > 2: j[2].getStr() else: ""
    )
  
  of "NOTICE":
    result = RelayMessage(
      kind: RelayMessageKind.Notice,
      notice: j[1].getStr()
    )
  
  of "AUTH":
    result = RelayMessage(
      kind: RelayMessageKind.Auth,
      challenge: j[1].getStr()
    )
  
  else:
    raise newException(ValueError, "Unknown relay message type: " & msgType)

# =============================================================================
# Client Message Construction
# =============================================================================

proc makeReqMessage*(subId: string, filters: seq[JsonNode]): string =
  ## Create REQ message for subscription
  var msg = newJArray()
  msg.add(%"REQ")
  msg.add(%subId)
  for f in filters:
    msg.add(f)
  result = $msg

proc makeEventMessage*(event: NostrEvent): string =
  ## Create EVENT message for publishing
  result = $(%*["EVENT", event.toJson()])

proc makeCloseMessage*(subId: string): string =
  ## Create CLOSE message for unsubscribing
  result = $(%*["CLOSE", subId])
