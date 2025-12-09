# EC4X TODO & Roadmap

**Last Updated:** 2025-12-08
**Current Phase:** Phase 2 Complete - Ready for Phase 3
**Test Status:** 36 integration test files, 673 test cases - ALL PASSING ✅
**Balance Status:** RBA functional, 2 balance issues identified

---

## Quick Links

- 🔴 **[Active Issues](KNOWN_ISSUES.md)** - 2 critical balance issues
- 📋 **[Open Issues](OPEN_ISSUES.md)** - Pending tasks
- 📊 **[AI Status](ai/STATUS.md)** - Detailed phase tracking
- 📈 **[Balance Testing](BALANCE_TESTING_METHODOLOGY.md)** - Testing approach
- 📦 **[Archive](archive/)** - Historical docs

---

## Current Status

✅ **Complete:**
- 13 engine systems operational
- 101+ integration tests passing
- Fog-of-war integrated
- RBA AI functional (Phase 2 complete)
- Diagnostic infrastructure (130+ metrics)
- GOAP infrastructure (not yet integrated)
- Game initialization refactoring (modular, config-driven)

🔴 **Active Issues:**
1. Alliance pacts: 0 formed (thresholds too high)
2. Strategy imbalance: Turtle/Balanced dominate (80%+ win rate)

---

## AI Development Roadmap

| Phase | Status | Completion | Key Deliverable |
|-------|--------|-----------|-----------------|
| **Phase 1** | ✅ Complete | 100% | Environment setup, engine production-ready |
| **Phase 2** | ✅ Complete | 100% | RBA enhancements (2a-2k), diagnostics |
| **Phase 2.5** | ⏳ TODO | 0% | Refactor test harness to production modules |
| **Phase 3** | ⏳ TODO | 0% | Bootstrap data generation (10,000 games) |
| **Phase 4** | ⏳ TODO | 0% | Supervised learning (policy + value networks) |
| **Phase 5** | ⏳ TODO | 0% | Nim integration (ONNX Runtime) |
| **Phase 6** | ⏳ TODO | 0% | Self-play reinforcement learning |
| **Phase 7** | ⏳ TODO | 0% | Production deployment |

**Overall AI Progress:** 25% (2 of 8 phases)

**See:** `docs/ai/STATUS.md` for detailed phase breakdowns and task lists

---

## Priority Tasks

### 1. 🔴 HIGH - Balance Issues (Immediate)

**Alliance Pacts (0 formed):**
- Root cause: Thresholds too high for balanced games
- Action: Tune diplomacy thresholds in `config/rba.toml`
- Test: 100-game validation after tuning

**Strategy Imbalance (Turtle/Balanced 80%+ wins):**
- Root cause: Aggressive strategies underperforming
- Action: Rebalance strategy profiles in `config/rba.toml`
- Test: Win rate should be 40-60% for all strategies

### 2. 🎯 HIGH - Imperial Administrators System

**Context:** Need competing advisors (Science, Spymaster, Diplomat, Economic) mediated by House Duke coordinator.

**Architecture:** Multi-advisor system with budget competition and personality-driven priorities.

**Implementation Phases:**
1. Science Advisor (4-6 hours) - Research priorities
2. Spymaster (4-6 hours) - Espionage operations
3. House Duke (6-8 hours) - Strategic coordinator
4. Diplomat (3-4 hours) - Alliance management
5. Economic Advisor (3-4 hours) - Infrastructure/taxation

**Estimated Effort:** 20-30 hours total

**See:** `docs/ai/balance/cfo-non-ship-expenditures-and-imperial-government.md`

### 3. 📦 MEDIUM - Archive Old Context File

**Action:** Move `docs/archive/CONTEXT-OLD.md` to dated archive folder (shown in git status)

### 4. 🧹 LOW - Remove Old Files

**Cleanup Tasks:**
- Remove old LLM-related files/folders
- Exclude JSON files from repo if possible
- Clean up any remaining obsolete documentation

---

## Phase 2.5: Test Harness Refactoring ⏳ TODO

**Status:** Not Started
**Goal:** Move AI features from test harness to production modules
**Blocked By:** Balance issues (#1, #2)

**Refactoring Tasks:**
1. Move espionage logic → `src/ai/rba/espionage.nim`
2. Move strategic helpers → `src/ai/rba/strategic.nim`
3. Move diplomatic logic → `src/ai/rba/diplomacy.nim`

**Why:** Required before Phase 3 bootstrap data generation

---

## Phase 3: Bootstrap Data Generation ⏳ TODO

**Status:** Not Started
**Goal:** Generate 10,000+ high-quality training examples
**Blocked By:** Phase 2.5 refactoring

**Steps:**
1. Create `tests/balance/export_training_data.nim`
2. Run 10,000 games (4 AI players each)
3. Record state-action-outcome (~1.6M examples)
4. Generate train/validation split

**Deliverable:** `training_data/bootstrap/*.json` (100-500MB compressed)

---

## Phase 4-7: Neural Network Training ⏳ TODO

**Status:** Not Started
**Goal:** Train AlphaZero-style neural network AI

**Phases:**
- **Phase 4:** Supervised learning (imitate RBA)
- **Phase 5:** Nim integration (ONNX Runtime)
- **Phase 6:** Self-play reinforcement learning
- **Phase 7:** Production deployment

**See:** `docs/ai/STATUS.md` for detailed specifications

---

## Recent Completions (Last 30 Days)

**For detailed completion reports, see:** `docs/archive/2025-12/TODO-2025-12-06.md`

### Major Milestones

- ✅ Dynamic AI Systems (2025-12-01) - Expansion, diplomacy, combat tracking
- ✅ Population Transfer Fix (2025-11-29) - Config initialization bug
- ✅ TODO Comment Resolution (2025-11-28) - 50 of 54 resolved (93%)
- ✅ RBA Unknown-Unknowns Testing (2025-11-28) - 3 critical bugs found/fixed
- ✅ Simultaneous Order Resolution (2025-11-27) - Eliminated turn-order bias
- ✅ Terminal Analysis System (2025-11-27) - Polars-based balance analyzer
- ✅ RBA Config Migration (2025-11-27) - All values in TOML
- ✅ AI Critical Bug Fixes (2025-11-27) - Scout production, espionage, spending

---

## Documentation Organization

### /docs Root (MAX 7 FILES - Currently at 6/7)

**Current:**
1. `TODO.md` - This file
2. `KNOWN_ISSUES.md` - Active issues
3. `OPEN_ISSUES.md` - Tracked tasks
4. `BALANCE_TESTING_METHODOLOGY.md` - Testing approach
5. `README.md` - Docs overview
6. (1 slot available)

**Subdirectories:**
- `/docs/architecture/` - System design
- `/docs/specs/` - Game rules
- `/docs/ai/` - AI development
- `/docs/guides/` - Implementation guides
- `/docs/archive/` - Historical docs

---

## Notes

**Design Philosophy:**
- Event-based architecture
- Minimal coupling between systems
- All mechanics configurable via TOML
- Comprehensive test coverage
- Neural network AI via self-play (not LLMs)

**AI Development Philosophy:**
- Leverage existing rule-based AI
- Small specialized models (~3.6MB, not 4GB)
- Game-specific learning (EC4X strategy)
- AlphaZero approach
- Incremental improvement via self-play

---

**For historical details and completion reports:**
- See `docs/archive/2025-12/TODO-2025-12-06.md` (previous version with full history)
- See milestone docs in `docs/milestones/`
- See completion reports in `docs/archive/`
