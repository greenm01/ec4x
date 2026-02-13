## Core Nostr types and constants for EC4X transport layer

import std/[tables, options]

type
  NostrEvent* = object
    id*: string                    # 32-byte lowercase hex event id
    pubkey*: string                # 32-byte lowercase hex public key
    created_at*: int64             # Unix timestamp
    kind*: int                     # Event type
    tags*: seq[seq[string]]        # Indexed tags
    content*: string               # Arbitrary content
    sig*: string                   # 64-byte hex signature

  NostrFilter* = object
    ids*: seq[string]              # Event IDs
    authors*: seq[string]          # Pubkeys
    kinds*: seq[int]               # Event kinds
    tags*: Table[string, seq[string]]  # Tag filters (#d, #p, etc.)
    since*: Option[int64]          # Unix timestamp
    until*: Option[int64]          # Unix timestamp
    limit*: Option[int]            # Max results

  RelayMessageKind* {.pure.} = enum
    Event
    Ok
    Eose
    Closed
    Notice
    Auth      # NIP-42

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
      eoseSubId*: string
    of RelayMessageKind.Closed:
      closedSubId*: string
      reason*: string
    of RelayMessageKind.Notice:
      notice*: string
    of RelayMessageKind.Auth:
      challenge*: string

  KeyPair* = object
    privateKey*: string   # 32-byte hex private key
    publicKey*: string    # 32-byte hex public key (x-only)
    npub*: string         # bech32 npub (for display)
    nsec*: string         # bech32 nsec (for display)

  ConnectionState* {.pure.} = enum
    Disconnected
    Connecting
    Connected
    Reconnecting

# =============================================================================
# EC4X Custom Event Kinds (per nostr-protocol.md)
# =============================================================================

const
  # Parameterized replaceable events (30xxx range)
  EventKindGameDefinition* = 30400   # Admin: Game metadata, slot status
  EventKindPlayerSlotClaim* = 30401  # Player: Claims invite code
  EventKindTurnCommands* = 30402     # Player: Commands for a turn
  EventKindTurnResults* = 30403      # Server: Delta from turn resolution
  EventKindJoinError* = 30404        # Server: Join errors
  EventKindGameState* = 30405        # Server: Full current state
  EventKindPlayerMessage* = 30406    # Player: Direct message

# =============================================================================
# Standard Nostr Tag Names
# =============================================================================

const
  TagD* = "d"             # Unique identifier (for replaceable events)
  TagP* = "p"             # Pubkey (recipient for encryption)
  TagE* = "e"             # Event reference
  TagName* = "name"       # Human-readable name
  TagStatus* = "status"   # Game status
  TagTurn* = "turn"       # Turn number
  TagSlot* = "slot"       # Player slot
  TagCode* = "code"       # Invite code
  TagError* = "error"     # Error message
  TagFromHouse* = "from_house"  # Sender house id
  TagToHouse* = "to_house"      # Recipient house id

# =============================================================================
# Game Status Values
# =============================================================================

const
  GameStatusSetup* = "setup"
  GameStatusActive* = "active"
  GameStatusFinished* = "finished"
  GameStatusCompleted* = "completed"
  GameStatusCancelled* = "cancelled"
  GameStatusRemoved* = "removed"

# =============================================================================
# Slot Status Values
# =============================================================================

const
  SlotStatusPending* = "pending"
  SlotStatusClaimed* = "claimed"
