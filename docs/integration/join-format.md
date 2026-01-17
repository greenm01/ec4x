# EC4X Join Protocol (Localhost + Nostr)

**Version:** 1.0
**Last Updated:** 2026-01-16

## Overview

This document specifies the KDL format for player join requests and daemon
responses. The same format is used for localhost transport and future Nostr
transport. The join flow assigns a `houseId` and binds it to a Nostr public key.

## Localhost Flow

1. Client writes a join request KDL file.
2. Daemon validates and assigns a house (first-come, first-served).
3. Daemon persists `nostr_pubkey` on the assigned house.
4. Daemon writes a join response KDL file.

## Transport Paths (Localhost)

- Requests: `data/games/<gameId>/requests/join_*.kdl`
- Responses: `data/games/<gameId>/responses/join_*.kdl`

## Pubkey Rules

- Clients MAY submit `npub` or hex.
- Daemon normalizes to hex for storage.
- Pubkeys are unique per game. If a pubkey already exists, it reuses the
  assigned house.

## Request Format

```kdl
join game="<gameId>" nostr_pubkey="<npub_or_hex>" name="<player_name>"
```

### Required Attributes

- `game` - Game identifier (directory name under `data/games/`).
- `nostr_pubkey` - Player public key, `npub` or hex.

### Optional Attributes

- `name` - Player display name.

## Response Format

```kdl
join-response game="<gameId>" house=(HouseId)1 status=accepted
```

### Required Attributes

- `game` - Game identifier from the request.
- `status` - `accepted` or `rejected`.

### Conditional Attributes

- `house` - Assigned house ID, required when `status=accepted`.
- `reason` - Human-readable error message when `status=rejected`.

## Example (Accepted)

```kdl
join game="game-123" nostr_pubkey="npub1..." name="Ariadne"
```

```kdl
join-response game="game-123" house=(HouseId)3 status=accepted
```

## Example (Rejected)

```kdl
join game="game-123" nostr_pubkey="npub1..."
```

```kdl
join-response game="game-123" status=rejected reason="game is full"
```
