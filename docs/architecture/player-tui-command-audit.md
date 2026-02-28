# Player TUI Command Audit

**Date:** 2026-02-28
**Status:** Complete (P2 ergonomics + confidence hardening done)
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
4. P2 ergonomics and confidence hardening are complete: narrow-terminal
   polish, drop/edit interaction consistency, expert-mode parity checks,
   and draft-restore replay regression coverage are now in place.

---

## Fleet Target Filtering Matrix (Spec-aligned)

Goal: system target pickers should only present destinations that are
both strategically meaningful and executable for the selected fleet
context, while respecting fog-of-war.

Principles:
- Fog-of-war safe: target policies use only known/visible player intel.
- Executable first: unreachable systems are filtered out.
- Batch-safe: multi-fleet pickers use intersection semantics.
- No duplicate colonize intent: colonize excludes systems already
  targeted by other friendly colonize missions.

| Command | Target filter policy | Data source |
|---|---|---|
| Move (01) | Reachable systems only | ETA/pathfinding |
| Patrol (03) | Reachable systems only | ETA/pathfinding |
| Guard Starbase (04) | Friendly starbase systems + reachable | Planets/intel |
| Guard Colony (05) | Friendly colony systems + reachable | Planets |
| Blockade (06) | Known enemy colonies + known uncolonized visible + reachable | Intel/visibility |
| Bombard (07) | Known enemy colonies + reachable | Intel |
| Invade (08) | Known enemy colonies + reachable | Intel |
| Blitz (09) | Known enemy colonies + reachable | Intel |
| Colonize (10) | Known uncolonized; exclude known colonized and other friendly colonize targets; reachable | Planets/intel/fleet intents |
| Scout Colony (11) | Known enemy colonies + reachable | Intel |
| Scout System (12) | Visible non-owned systems + reachable | Intel visibility |
| Hack Starbase (13) | Known enemy starbases + reachable | Intel |
| Rendezvous (15) | Reachable systems only | ETA/pathfinding |
| Salvage (16) | Friendly colony systems with salvage support + reachable | Planets |
| Reserve (17) | Friendly colony systems + reachable | Planets |
| Mothball (18) | Friendly colony systems + reachable | Planets |
| View (19) | Visible non-owned systems + reachable | Intel visibility |

### DRY Implementation Rules

- Keep all fleet system-target filtering in one pipeline inside
  `buildSystemPickerListForCommand`.
- Precompute reusable filter sets once per picker build, then reuse.
- Keep command-specific policy mapping centralized in one `case` block.
- Apply reachability filtering through one shared helper.
- Keep empty-state messages centralized and consistent.

### Implementation Checklist

- [x] Document command-to-target policy matrix for Player TUI.
- [x] Add DRY rules for target filtering implementation.
- [x] Add shared helper for reachability filtering.
- [x] Expand command-specific filters for Scout/View/Blockade.
- [x] Keep Colonize duplicate-target prevention in policy pipeline.
- [x] Add regression tests for new target filter policies.

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

- [x] Add consistent drop/edit interactions across all command categories.
  - `src/player/sam/tui_model.nim`
  - `src/player/sam/acceptors.nim`
- [x] Add expert-mode parity checks to avoid unsupported command variants.
  - `tests/unit/test_tui_expert_parity.nim`
- [x] Add one focused regression test for optimistic replay after draft restore
   whenever fleet-affecting commands are present.
- `tests/unit/test_tui_draft_apply_resume.nim`
- [x] Add visual/layout polish for narrow terminals where command labels are
   prone to truncation.
  - `src/player/tui/widget/modal.nim`
  - `src/player/tui/widget/entry_modal.nim`
  - `tests/unit/test_tui_modal_layout.nim`

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
