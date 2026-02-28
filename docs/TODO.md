# EC4X Roadmap

**Last Updated:** 2026-01-17

## Engine Status

The game engine is stable and tested. Ready for client development and playtesting.

**Test Coverage:**
- Unit Tests: 9 suites passing
- Integration Tests: 310 tests passing
- Stress Tests: 24 tests passing
- **Total: 343+ tests passing**

**What Works:**
- Full turn cycle (Conflict → Income → Command → Production)
- All 13 game systems operational (combat, economy, research, diplomacy, etc.)
- Config-driven architecture (KDL format, no hardcoded values)
- Fog-of-war intelligence system
- Entity management (houses, colonies, fleets, ships, facilities, ground units)
- Command validation and execution
- State persistence ready (GameState structure stable)

**Known Gaps:**
- No AI opponents (by design - social game for humans first)
- Balance untested (needs playtesting with real games)
- Some edge cases may surface during play (stress tests found several we fixed)

## What's Next

Building the infrastructure to actually play the game:

1. **Player client** - Human interface for viewing state and submitting commands
2. **Playtesting** - Run actual games to validate mechanics and balance
3. **LLM Bot Integration** - Build a headless Nostr client that condenses `PlayerState` to prompt an LLM (Claude/Gemini) to play the game and submit orders.

Once we can play real games, we'll know what needs adjustment.

## Player TUI Gameplay Readiness

Goal: make the player TUI command surface feature-complete for practical
playtesting and bug discovery.

Reference audit:
- `docs/architecture/player-tui-command-audit.md`

Priority backlog:

1. [x] Add integration tests proving submit/resume behavior for all
   command categories in normal TUI flows.
   - `tests/unit/test_tui_draft_apply_resume.nim`
2. [x] Expand UI-level regression coverage for maintenance and transfer
   modal interactions.
   - `tests/unit/test_tui_modal_acceptors.nim`
3. [x] Validate command-dock/action-hint parity across all colony actions.
   - `tests/unit/test_tui_colony_action_parity.nim`

Next focus:

1. [x] Add real TUI end-to-end smoke tests for fleet multi-select and batch
   operations under live keyboard event handling.
   - `tests/unit/test_tui_fleet_batch_keyboard_smoke.nim`
2. [x] Expand submit/resume regression tests for fleet-detail batch snapshot
   behavior (ROE/Command/ZTC) across cursor movement and sort changes.
   - `tests/unit/test_tui_modal_acceptors.nim`
   - `tests/unit/test_tui_fleet_batch_keyboard_smoke.nim`

## Future (Post-Playtesting)

- **AI opponents** - Neural network trained on LLM-bot generated games (see `docs/ai/neural_network_training.md`)

---

## Documentation
- **Game Management**: [Chat Bot Admin Guide](guides/game-management-chatbot.md)

- **Game Rules:** [docs/specs/index.md](specs/index.md) - Complete gameplay specification
- **Architecture:** [docs/architecture/](architecture/) - System design
- **Engine Details:** [docs/engine/](engine/) - Implementation details
- **Play-Testing:** [docs/play_testing/](play_testing/) - Testing approach

---

## Recent Major Work

**Nostr Transport Integration (2026-01-17):**
- Wired daemon to Nostr relays with encrypted command ingestion and delta publishing
- Added slot claim handling with pubkey persistence in houses table
- Implemented PlayerState snapshot persistence + diff-based delta KDL generation
- Added 30405 full-state serialization + publish-on-claim

**Code Style Cleanup (2026-01-10):**
- Removed 130+ `get` prefixes from function names (NEP-1 compliance)
- Fixed all UFCS violations (uniform function call syntax)
- Removed all unnecessary import aliases
- Updated CLAUDE.md with enforced style guidelines

**Test Suite Expansion (2026-01-10):**
- Added 4 missing integration test suites (234 tests)
- Created 3 new integration tests (economy, diplomacy, elimination)
- Fixed stress test framework false positive (eliminated house validation)
- Expanded from 51 to 310 integration tests (6x increase)

**Stress Test Fixes (2026-01-10):**
- Removed SQLite dependencies from all nimble tasks (no longer needed)
- Fixed CommandPacket structure in stress tests
- Fixed turn validation logic in test_engine_stress.nim
- All 24 stress tests now passing

---

**For detailed history:** See git log - this file focuses on current status and next steps.
