# EC4X Integration TODO (TUI + Localhost + Nostr Join)

**Last Updated:** 2026-01-16

## Goals (MVP)

- TUI can discover games in `data/games/*`.
- TUI can join a game with a Nostr public key.
- Daemon assigns `houseId` (first-come, enforce max players).
- TUI submits KDL orders to `orders/`.
- Manual resolve workflow is documented and visible in the TUI.
- TUI reads results into Reports.

## Join Protocol (KDL)

- **Request:** `join` KDL file in `requests/`.
- **Response:** `join-response` KDL file in `responses/`.
- Fields: `gameId`, `nostr_pubkey`, `player_name?`, `houseId`,
  `status`, `reason?`.
- Pubkey accepted as `npub` or hex, normalized to hex.

## Localhost Transport Paths

- `data/games/<gameId>/requests/join_*.kdl`
- `data/games/<gameId>/responses/join_*.kdl`
- `data/games/<gameId>/orders/turn_{N}_house_{H}.kdl`
- `data/games/<gameId>/houses/<houseId>/turn_results/turn_N.kdl`

## Daemon Responsibilities

- Watch `requests/` for join KDL files.
- Parse join KDL and validate pubkey.
- Assign house (reuse if pubkey already mapped).
- Enforce max players from game setup.
- Persist mapping in `houses.nostr_pubkey`.
- Emit response KDL with `houseId` or error.

## TUI Responsibilities

- Join screen with Nostr public key input.
- Cache `houseId` locally in KDL.
- Render join status and errors.
- Order builder and serialization to KDL.
- Display responses and results in Reports.

## Manual Resolve (Now)

- UI hint for `./bin/ec4x-daemon resolve <gameId>`.
- Later: daemon scheduled resolution once per day.

## Tests / Validation (Optional for MVP)

- Join response accepted/rejected cases.
- Orders written in valid format.
- Reports load after resolution.
