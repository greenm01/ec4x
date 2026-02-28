# EC4X Roadmap

**Last Updated:** 2026-02-28

## Current Status

- Engine command surface is stable and playable through the Player TUI.
- Player TUI command staging is feature-complete for canonical
  `CommandPacket` fields.
- Current priority is P2 gameplay ergonomics and confidence hardening.
- Detailed command/target audit lives in:
  - `docs/architecture/player-tui-command-audit.md`

## Player TUI Gameplay Readiness (Complete)

Goal: make normal Player TUI flows robust for sustained human playtesting.

### P2 Completion

1. [x] Add visual/layout polish for narrow terminals where modal/table
   labels and footer hints still truncate or clip.
2. [x] Add consistent drop/edit interactions across all staged command
   categories (uniform behavior and status messaging).
3. [x] Add expert-mode parity checks so expert command flows match normal
   TUI validation/staging behavior.
4. [x] Add one focused regression test for optimistic replay after draft
   restore when fleet-affecting staged commands are present.

Evidence:

- `tests/unit/test_tui_modal_layout.nim`
- `tests/unit/test_tui_command_staging.nim`
- `tests/unit/test_tui_modal_acceptors.nim`
- `tests/unit/test_tui_expert_parity.nim`
- `tests/unit/test_tui_draft_apply_resume.nim`

## Validation Gate (Latest Run)

All readiness gate checks pass:

- `nim c -r tests/unit/test_tui_command_staging.nim`
- `nim c -r tests/unit/test_tui_modal_acceptors.nim`
- `nim c -r tests/unit/test_tui_draft_apply_resume.nim`
- `nim c -r tests/unit/test_tui_fleet_batch_keyboard_smoke.nim`
- `nim c -r tests/unit/test_tui_expert_parity.nim`
- `nim c -r tests/unit/test_tui_modal_layout.nim`
- `nimble buildTui`

## Next Focus (Post-P2)

1. Run structured human playtest sessions and capture UX friction points
   from real command submission loops.
2. Add targeted regressions for issues found during playtests, keeping
   coverage near the modal/acceptor path where the bug occurs.
3. Track and prioritize gameplay-facing polish items that impact command
   confidence, especially around clarity of staged intent and summaries.

## Future (Post-Playtesting)

- AI opponents and automation:
  - `docs/ai/neural_network_training.md`
