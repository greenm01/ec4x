## EC4X Nostr event builders
##
## Creates properly structured Nostr events for EC4X protocol:
## - 30400: Game definition (lobby, slots)
## - 30401: Player slot claim
## - 30402: Turn commands (encrypted)
## - 30403: Turn results/deltas (encrypted)
## - 30405: Full game state (encrypted)

import std/[json, options, strutils, sequtils]
import types, nip01, crypto
import ../../../common/wordlist

# =============================================================================
# Game Definition Events (30400)
# =============================================================================

type
  SlotInfo* = object
    index*: int
    code*: string        # Invite code hash
    status*: string      # "pending" or "claimed"
    pubkey*: string      # Player pubkey if claimed

  GameDefinitionContent* = object
    name*: string
    maxPlayers*: int
    slots*: seq[SlotInfo]

proc inviteCodeHash*(code: string): string =
  let normalized = normalizeInviteCode(code)
  if normalized.len == 0:
    return ""
  sha256Hash(normalized)

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
  
  # Add slot tags with invite code hashes and pubkeys
  for slot in slots:
    let slotHash = if slot.code.len > 0:
      inviteCodeHash(slot.code)
    else:
      "-"
    if slot.status == SlotStatusClaimed:
      tags.add(@[TagSlot, $slot.index, slotHash, slot.pubkey, slot.status])
    else:
      tags.add(@[TagSlot, $slot.index, slotHash, "", slot.status])
  
  result = newEvent(
    kind = EventKindGameDefinition,
    content = $content,
    tags = tags,
    pubkey = daemonPubkey
  )
  result.id = computeEventId(result)

proc createGameDefinitionNoSlots*(
  gameId: string,
  name: string,
  status: string,
  daemonPubkey: string
): NostrEvent =
  ## Create game definition event without slot tags
  let content = %*{
    "name": name,
    "slots": 0,
    "claimed": 0
  }

  let tags: seq[seq[string]] = @[
    @[TagD, gameId],
    @[TagName, name],
    @[TagStatus, status]
  ]

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
# Join Error Events (30404)
# =============================================================================

proc createJoinError*(daemonPubkey: string, playerPubkey: string,
  encryptedMessage: string): NostrEvent =
  ## Create join error event (30404)
  let tags = @[
    @[TagP, playerPubkey]
  ]

  result = newEvent(
    kind = EventKindJoinError,
    content = encryptedMessage,
    tags = tags,
    pubkey = daemonPubkey
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
  ## Content is: msgpack -> zstd -> NIP-44 encrypt -> base64
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
  ## Content is: msgpack -> zstd -> NIP-44 encrypt -> base64
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
  ## Content is: msgpack -> zstd -> NIP-44 encrypt -> base64
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

# =============================================================================
# Player Messages Events (30406)
# =============================================================================

proc createPlayerMessage*(
  gameId: string,
  encryptedPayload: string,
  recipientPubkey: string,
  senderPubkey: string,
  fromHouse: int32,
  toHouse: int32
): NostrEvent =
  ## Create player message event (encrypted to recipient)
  ## Content is: msgpack -> zstd -> NIP-44 encrypt -> base64
  let tags = @[
    @[TagD, gameId],
    @[TagP, recipientPubkey],
    @[TagFromHouse, $fromHouse],
    @[TagToHouse, $toHouse]
  ]

  result = newEvent(
    kind = EventKindPlayerMessage,
    content = encryptedPayload,
    tags = tags,
    pubkey = senderPubkey
  )
  result.id = computeEventId(result)

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
    if tag.len >= 5:
      var slot = SlotInfo(
        index: parseInt(tag[1]),
        status: tag[4]
      )
      slot.code = tag[2]
      slot.pubkey = tag[3]
      result.add(slot)
    elif tag.len >= 3:
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
