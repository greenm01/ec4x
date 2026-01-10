## Core Nostr types and constants for EC4X transport layer

import std/[json, tables, times, options]

type
  NostrEvent* = object
    id*: string                    # 32-byte lowercase hex event id
    pubkey*: string                # 32-byte lowercase hex public key
    created_at*: int64             # Unix timestamp
    kind*: int                     # Event type
    tags*: seq[seq[string]]        # Indexed tags
    content*: string               # Arbitrary content (often JSON)
    sig*: string                   # 64-byte hex signature

  NostrFilter* = object
    ids*: seq[string]              # Event IDs
    authors*: seq[string]          # Pubkeys
    kinds*: seq[int]               # Event kinds
    tags*: Table[string, seq[string]]  # Tag filters (e.g., #g for game)
    since*: Option[int64]          # Unix timestamp
    until*: Option[int64]          # Unix timestamp
    limit*: Option[int]            # Max results

  RelayMessage* = object
    case kind*: RelayMessageKind
    of RelayMessageKind.Event:
      subscriptionId*: string
      event*: NostrEvent
    of RelayMessageKind.Ok:
      eventId*: string
      accepted*: bool
      message*: string
    of RelayMessageKind.Eose:
      subId*: string
    of RelayMessageKind.Closed:
      closedSubId*: string
      reason*: string
    of RelayMessageKind.Notice:
      notice*: string

  RelayMessageKind* {.pure.} = enum
    Event, Ok, Eose, Closed, Notice

  NostrClient* = ref object
    relays*: seq[string]           # WebSocket URLs
    # connections*: Table[string, WebSocket]  # TODO: Add when WebSocket impl ready
    subscriptions*: Table[string, NostrFilter]
    eventCallback*: proc(event: NostrEvent)
    eoseCallback*: proc(subId: string)

  KeyPair* = object
    privateKey*: array[32, byte]
    publicKey*: array[32, byte]

# EC4X Custom Event Kinds
const
  EventKindOrderPacket* = 30001      # Player order submission
  EventKindGameState* = 30002        # Per-player game state view
  EventKindTurnComplete* = 30003     # Turn resolution announcement
  EventKindGameMeta* = 30004         # Game metadata (lobby, config)
  EventKindDiplomacy* = 30005        # Private diplomatic messages
  EventKindSpectate* = 30006         # Public spectator feed

# Standard tag names
const
  TagGame* = "g"          # Game ID
  TagHouse* = "h"         # Player's house name
  TagTurn* = "t"          # Turn number
  TagPlayer* = "p"        # Player pubkey (for encryption target)
  TagGamePhase* = "phase" # Game phase (setup, active, completed)
