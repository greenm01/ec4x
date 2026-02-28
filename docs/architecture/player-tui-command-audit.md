# Player TUI Command Audit

**Date:** 2026-02-28
**Status:** In progress (P1/P2 validation and ergonomics)
**Goal:** Make the player TUI capable of producing the full canonical
turn command queue for practical human playtesting and bug hunting.

---

## Scope

This audit compares the engine's canonical `CommandPacket` surface to what
the player TUI can currently stage, persist, restore, and submit.

Primary references:
- `src/engine/types/command.nim`
- `src/engine/turn_cycle/command_phase.nim`
- `src/player/sam/tui_model.nim`
- `src/player/sam/acceptors.nim`
- `src/player/tui/app.nim`
- `src/player/tui/draft_apply.nim`

Related regression coverage:
- `tests/unit/test_tui_command_staging.nim`
- `tests/unit/test_tui_cache_config_snapshot.nim`
- `tests/unit/test_tui_modal_acceptors.nim`
- `tests/unit/test_tui_colony_action_parity.nim`
- `tests/unit/test_tui_draft_apply_resume.nim`
- `tests/unit/test_tui_fleet_batch_keyboard_smoke.nim`

---

## CommandPacket Coverage

Legend: `Complete`, `Partial`, `Missing`

| CommandPacket field | TUI support | Notes |
|---|---|---|
| `zeroTurnCommands` | Complete | Fleet detail ZTC picker and staging flow implemented. |
| `fleetCommands` | Complete | Single + batch fleet command staging implemented. |
| `buildCommands` | Complete | Build modal queues and staging implemented. |
| `repairCommands` | Complete | Normal TUI maintenance modal now stages/unstages repair commands. |
| `scrapCommands` | Complete | Normal TUI maintenance modal now stages/unstages scrap commands. |
| `researchAllocation` | Complete | Research panel staging implemented. |
| `diplomaticCommand` | Complete | Economy/diplomacy flow stages commands. |
| `populationTransfers` | Complete | Normal TUI transfer modal stages commands and submit path is wired. |
| `terraformCommands` | Complete | Colony-level terraform staging is wired into submit path. |
| `colonyManagement` | Complete | Tax/toggles overlay into packet generation. |
| `espionageActions` | Complete | Espionage queue and budget flow implemented. |
| `ebpInvestment` | Complete | Staged and submitted. |
| `cipInvestment` | Complete | Staged and submitted. |

---

## Key Findings

1. Canonical `CommandPacket` command-surface coverage is now available in
   standard TUI flows, including population transfer, terraforming,
   repair, and scrap.
2. Draft save/load and optimistic replay coverage have been expanded, with
   dedicated restore helpers extracted to `src/player/tui/draft_apply.nim`.
3. Fleet batch operations now use snapshot semantics for X-selected fleets
   across ROE/command/ZTC flows, avoiding cursor/selection drift issues.
4. Primary remaining work is validation depth and playtesting ergonomics
   (full end-to-end submit/resume smoke paths and UI polish).

---

## Gameplay Readiness Definition

The player TUI is considered gameplay-ready when a human can complete a full
turn using only the standard TUI flows (without file editing or hidden dev
paths), and every intended order domain can be staged, reviewed, edited,
draft-restored, and submitted through `CommandPacket`.

---

## TODO: Gameplay Readiness Backlog

### P0 - Required for feature completeness

- [x] Implement population transfer staging in normal TUI flow.
- [x] Implement terraforming staging in normal TUI flow.
- [x] Implement complete repair command staging flow in normal TUI flow.
- [x] Implement complete scrap command staging flow in normal TUI flow.
- [x] Add focused integration-style tests for submit/resume UX paths
  (packet/draft restore + optimistic replay regression coverage).

### P1 - Validation and quality

- [x] Add packet coverage tests that verify all command categories can be
  produced by TUI staging and appear in submitted `CommandPacket`.
  - `tests/unit/test_tui_command_staging.nim`
- [x] Add draft persistence tests for all staged command categories.
  - `tests/unit/test_tui_cache_config_snapshot.nim`
  - `tests/unit/test_tui_draft_apply_resume.nim`
- [x] Add submit-summary category verification coverage.
  - `tests/unit/test_tui_command_staging.nim`
- [x] Ensure command dock labels map to real, reachable actions.
  - `tests/unit/test_tui_colony_action_parity.nim`
- [x] Add fleet batch smoke coverage for ZTC execution submission path
  (beyond picker applicability and staging).
  - `tests/unit/test_tui_fleet_batch_keyboard_smoke.nim`

### P2 - Playtesting ergonomics

- Add consistent drop/edit interactions across all command categories.
- Add expert-mode parity checks to avoid unsupported command variants.
- Add one focused regression test for optimistic replay after draft restore
  whenever fleet-affecting commands are present.
- Add visual/layout polish for narrow terminals where command labels are
  prone to truncation.

---

## Acceptance Criteria

- All canonical `CommandPacket` fields used by the engine are reachable from
  standard TUI gameplay flows.
- All staged command categories survive app restart through draft restore.
- Submit confirmation accurately reflects staged command totals by category.
- At least one end-to-end integration test covers mixed-category submission:
  fleet + ZTC + economy + diplomacy + espionage + population transfer +
  terraforming + repair/scrap.

Current evidence:
- `tests/unit/test_tui_mixed_submit_smoke.nim`
