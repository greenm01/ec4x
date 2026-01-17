## EC4X Nostr event builders
##
## Creates properly structured Nostr events for EC4X protocol:
## - 30400: Game definition (lobby, slots)
## - 30401: Player slot claim
## - 30402: Turn commands (encrypted)
## - 30403: Turn results/deltas (encrypted)
## - 30405: Full game state (encrypted)

import std/[json, times, options, strutils]
import types, nip01

# =============================================================================
# Game Definition Events (30400)
# =============================================================================

type
  SlotInfo* = object
    index*: int
    code*: string        # Invite code
    status*: string      # "pending" or "claimed"
    pubkey*: string      # Player pubkey if claimed

  GameDefinitionContent* = object
    name*: string
    maxPlayers*: int
    slots*: seq[SlotInfo]

proc createGameDefinition*(
  gameId: string,
  name: string,
  status: string,
  slots: seq[SlotInfo],
  daemonPubkey: string
): NostrEvent =
  ## Create game definition event (public, unencrypted)
  ## This is the lobby/game advertisement
  let content = %*{
    "name": name,
    "slots": slots.len,
    "claimed": slots.filterIt(it.status == SlotStatusClaimed).len
  }
  
  var tags: seq[seq[string]] = @[
    @[TagD, gameId],
    @[TagName, name],
    @[TagStatus, status]
  ]
  
  # Add slot tags with invite codes (for pending) or pubkeys (for claimed)
  for slot in slots:
    if slot.status == SlotStatusClaimed:
      tags.add(@[TagSlot, $slot.index, slot.status, slot.pubkey])
    else:
      tags.add(@[TagSlot, $slot.index, slot.status, slot.code])
  
  result = newEvent(
    kind = EventKindGameDefinition,
    content = $content,
    tags = tags,
    pubkey = daemonPubkey
  )
  result.id = computeEventId(result)

# =============================================================================
# Slot Claim Events (30401)
# =============================================================================

proc createSlotClaim*(
  gameId: string,
  inviteCode: string,
  playerPubkey: string
): NostrEvent =
  ## Create slot claim event from player
  ## Player sends this to claim a slot using invite code
  let tags = @[
    @[TagD, gameId],
    @[TagCode, inviteCode]
  ]
  
  result = newEvent(
    kind = EventKindPlayerSlotClaim,
    content = "",  # No content needed
    tags = tags,
    pubkey = playerPubkey
  )
  result.id = computeEventId(result)

# =============================================================================
# Turn Commands Events (30402)
# =============================================================================

proc createTurnCommands*(
  gameId: string,
  turn: int,
  encryptedPayload: string,
  daemonPubkey: string,
  playerPubkey: string
): NostrEvent =
  ## Create turn commands event (encrypted to daemon)
  ## Content is: KDL -> compress -> NIP-44 encrypt -> base64
  let tags = @[
    @[TagD, gameId],
    @[TagP, daemonPubkey],  # Recipient (daemon)
    @[TagTurn, $turn]
  ]
  
  result = newEvent(
    kind = EventKindTurnCommands,
    content = encryptedPayload,
    tags = tags,
    pubkey = playerPubkey
  )
  result.id = computeEventId(result)

proc createTurnCommandsPlaintext*(
  gameId: string,
  turn: int,
  kdlCommands: string,
  daemonPubkey: string,
  playerPubkey: string
): NostrEvent =
  ## Create turn commands with plaintext KDL (for testing/dev)
  ## In production, use createTurnCommands with encrypted payload
  createTurnCommands(gameId, turn, kdlCommands, daemonPubkey, playerPubkey)

# =============================================================================
# Turn Results Events (30403)
# =============================================================================

proc createTurnResults*(
  gameId: string,
  turn: int,
  encryptedPayload: string,
  playerPubkey: string,
  daemonPubkey: string
): NostrEvent =
  ## Create turn results/delta event (encrypted to player)
  ## Content is: KDL -> compress -> NIP-44 encrypt -> base64
  let tags = @[
    @[TagD, gameId],
    @[TagP, playerPubkey],  # Recipient (player)
    @[TagTurn, $turn]
  ]
  
  result = newEvent(
    kind = EventKindTurnResults,
    content = encryptedPayload,
    tags = tags,
    pubkey = daemonPubkey
  )
  result.id = computeEventId(result)

proc createTurnResultsPlaintext*(
  gameId: string,
  turn: int,
  kdlDelta: string,
  playerPubkey: string,
  daemonPubkey: string
): NostrEvent =
  ## Create turn results with plaintext KDL (for testing/dev)
  createTurnResults(gameId, turn, kdlDelta, playerPubkey, daemonPubkey)

# =============================================================================
# Full Game State Events (30405)
# =============================================================================

proc createGameState*(
  gameId: string,
  turn: int,
  encryptedPayload: string,
  playerPubkey: string,
  daemonPubkey: string
): NostrEvent =
  ## Create full game state snapshot (encrypted to player)
  ## Content is: KDL -> compress -> NIP-44 encrypt -> base64
  let tags = @[
    @[TagD, gameId],
    @[TagP, playerPubkey],  # Recipient (player)
    @[TagTurn, $turn]
  ]
  
  result = newEvent(
    kind = EventKindGameState,
    content = encryptedPayload,
    tags = tags,
    pubkey = daemonPubkey
  )
  result.id = computeEventId(result)

proc createGameStatePlaintext*(
  gameId: string,
  turn: int,
  kdlState: string,
  playerPubkey: string,
  daemonPubkey: string
): NostrEvent =
  ## Create game state with plaintext KDL (for testing/dev)
  createGameState(gameId, turn, kdlState, playerPubkey, daemonPubkey)

# =============================================================================
# Event Parsing Helpers
# =============================================================================

proc getGameId*(event: NostrEvent): Option[string] =
  ## Extract game ID from event's d tag
  event.getTagValue(TagD)

proc getTurn*(event: NostrEvent): Option[int] =
  ## Extract turn number from event
  let turnStr = event.getTagValue(TagTurn)
  if turnStr.isSome:
    try:
      return some(parseInt(turnStr.get()))
    except ValueError:
      discard
  return none(int)

proc getRecipient*(event: NostrEvent): Option[string] =
  ## Extract recipient pubkey from p tag
  event.getTagValue(TagP)

proc getInviteCode*(event: NostrEvent): Option[string] =
  ## Extract invite code from slot claim event
  event.getTagValue(TagCode)

proc getStatus*(event: NostrEvent): Option[string] =
  ## Extract game status from game definition
  event.getTagValue(TagStatus)

proc getSlots*(event: NostrEvent): seq[SlotInfo] =
  ## Extract slot info from game definition event
  result = @[]
  for tag in event.getTags(TagSlot):
    if tag.len >= 3:
      var slot = SlotInfo(
        index: parseInt(tag[1]),
        status: tag[2]
      )
      if tag.len >= 4:
        if slot.status == SlotStatusClaimed:
          slot.pubkey = tag[3]
        else:
          slot.code = tag[3]
      result.add(slot)

# Helper for filterIt used above
template filterIt[T](s: openArray[T], pred: untyped): seq[T] =
  var result: seq[T] = @[]
  for it {.inject.} in s:
    if pred:
      result.add(it)
  result
