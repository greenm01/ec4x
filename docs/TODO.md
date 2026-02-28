# EC4X Roadmap

**Last Updated:** 2026-02-28

## Current Status

- Engine command surface is stable and playable through the Player TUI.
- Player TUI command staging is feature-complete for canonical
  `CommandPacket` fields.
- Current priority is P2 gameplay ergonomics and confidence hardening.
- Detailed command/target audit lives in:
  - `docs/architecture/player-tui-command-audit.md`

## Player TUI Gameplay Readiness (Active)

Goal: make normal Player TUI flows robust for sustained human playtesting.

### Open P2 Work

1. [ ] Add visual/layout polish for narrow terminals where modal/table
   labels and footer hints still truncate or clip.
2. [ ] Add consistent drop/edit interactions across all staged command
   categories (uniform behavior and status messaging).
3. [ ] Add expert-mode parity checks so expert command flows match normal
   TUI validation/staging behavior.
4. [ ] Add one focused regression test for optimistic replay after draft
   restore when fleet-affecting staged commands are present.

## Next Milestones (Execution Order)

### Milestone 1: Narrow-Terminal UX Polish

- Normalize modal/footer width behavior in fleet/detail pickers.
- Ensure no footer clipping and no table/footer mismatch at small widths.
- Verify stable rendering under compact viewport constraints.

### Milestone 2: Staged Command UX Consistency

- Unify staged command drop/edit behavior across command categories.
- Centralize shared handling to reduce category-specific drift (DRY).

### Milestone 3: Expert-Mode Parity Hardening

- Ensure expert parser/executor paths use the same validation and staging
  semantics as normal TUI actions.
- Add parity coverage for representative fleet and colony commands.

### Milestone 4: Draft Restore + Replay Confidence

- Add targeted regression coverage for draft restore + optimistic replay
  involving fleet-affecting commands and batch contexts.
- Confirm replay ordering and post-restore visual state consistency.

## Validation Gate

Run after each milestone:

- `nim c -r tests/unit/test_tui_command_staging.nim`
- `nim c -r tests/unit/test_tui_modal_acceptors.nim`
- `nim c -r tests/unit/test_tui_draft_apply_resume.nim`
- `nim c -r tests/unit/test_tui_fleet_batch_keyboard_smoke.nim`
- `nimble buildTui`

## Future (Post-Playtesting)

- AI opponents and automation:
  - `docs/ai/neural_network_training.md`
