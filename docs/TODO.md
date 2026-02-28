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
   - `docs/guides/player-tui-playtest-checklist.md`
   - `docs/guides/player-tui-issue-template.md`
2. Add targeted regressions for issues found during playtests, keeping
   coverage near the modal/acceptor path where the bug occurs.
3. Track and prioritize gameplay-facing polish items that impact command
   confidence, especially around clarity of staged intent and summaries.


## Combat Engine Optimization & AAR Polish
Goal: Improve server-side calculation efficiency for large fleet battles and generate more narrative-rich After-Action Reports (AAR) for the player.

1. [ ] **Cascading Overkill:** Implement "Overwhelming Force" hit application bypass in `src/engine/systems/combat/hits.nim` to prevent doomstacks from spending wasted computational rounds chewing through tiny patrol screens.
2. [ ] **Pursuit Volleys:** Add a final `0.5x CER` attack phase against fleeing task forces in `src/engine/systems/combat/retreat.nim` to increase the risk/reward tension of ROE thresholds.
3. [ ] **Stalemate Detection:** Replace the 5-round wait with instantaneous mathematical stalemate detection to trigger Desperation (+2 DRM) or mutual withdrawal immediately.
4. [ ] **Targeted Criticals:** Update critical hit logic to prioritize highest-value assets and generate specific "High-Value Asset Destroyed" log strings for the AAR.


5. [ ] **Narrative AAR Generation:** Build structured `GameEvent` logs during hit application and retreat phases to be transported over Nostr inside the 30403 (Turn Results) payload, so the `ec4x-player` TUI can render cinematic Battle Reports.

## Future (Post-Playtesting)

- AI opponents and automation:
  - `docs/ai/neural_network_training.md`
