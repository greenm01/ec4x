## Unit tests for slot tag parsing and hashing.

import std/unittest
import ../../src/daemon/transport/nostr/events
import ../../src/daemon/transport/nostr/types
import ../../src/common/wordlist

suite "Slot Tag Parsing":
  test "parses new slot schema with hash":
    let code = normalizeInviteCode("Velvet-Mountain")
    let slot = SlotInfo(
      index: 1,
      code: code,
      status: SlotStatusPending,
      pubkey: ""
    )
    let event = createGameDefinition(
      gameId = "game-123",
      name = "Test Game",
      status = GameStatusSetup,
      slots = @[slot],
      daemonPubkey = "daemon"
    )

    let slots = event.getSlots()
    check slots.len == 1
    check slots[0].index == 1
    check slots[0].status == SlotStatusPending
    check slots[0].code == inviteCodeHash(code)
    check slots[0].pubkey.len == 0

  test "parses legacy slot schema":
    var legacyEvent = NostrEvent(
      kind: EventKindGameDefinition,
      tags: @[
        @[TagSlot, "2", SlotStatusClaimed, "playerpub"]
      ]
    )
    let slots = legacyEvent.getSlots()
    check slots.len == 1
    check slots[0].index == 2
    check slots[0].status == SlotStatusClaimed
    check slots[0].pubkey == "playerpub"
