# Player TUI Command Audit

**Date:** 2026-02-27
**Status:** In progress (P0 implementation underway)
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

1. The TUI is strong for fleet, ZTC, build, research, diplomacy, and
   espionage play loops.
2. The engine resolves population transfer and terraforming command queues,
   but the TUI does not currently produce those command types.
3. Repair/scrap plumbing exists in packet and draft paths, but user-facing
   staging UX is incomplete for gameplay readiness.
4. Some command-dock labels imply actions that are not yet backed by a full
   command staging workflow.

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
- [ ] Add focused integration tests for submit/resume UX paths
  (beyond unit packet/draft coverage).

### P1 - Validation and quality

- Add packet coverage tests that verify all command categories can be
  produced by TUI staging and appear in submitted `CommandPacket`.
- Add draft persistence tests for all staged command categories.
- Add submit-summary UI rows for all staged categories so players can verify
  intent pre-submit.
- Ensure command dock labels map to real, reachable actions.

### P2 - Playtesting ergonomics

- Add consistent drop/edit interactions across all command categories.
- Add expert-mode parity checks to avoid unsupported command variants.
- Add one focused regression test for optimistic replay after draft restore
  whenever fleet-affecting commands are present.

---

## Acceptance Criteria

- All canonical `CommandPacket` fields used by the engine are reachable from
  standard TUI gameplay flows.
- All staged command categories survive app restart through draft restore.
- Submit confirmation accurately reflects staged command totals by category.
- At least one end-to-end integration test covers mixed-category submission:
  fleet + ZTC + economy + diplomacy + espionage + population transfer +
  terraforming + repair/scrap.
