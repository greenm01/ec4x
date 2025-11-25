# EC4X TODO & Implementation Status

**Last Updated:** 2025-11-24
**Project Phase:** Phase 3 - AI Neural Network Training Pipeline
**Test Coverage:** 101 integration tests passing
**Engine Status:** 100% functional, production-ready
**Config Status:** ✅ **CLEAN** - Comprehensive audit complete

**Recent:**
- ✅ **Phase 2c Complete: Scout Operational Modes + FoW Bug Fixes (2025-11-24)**
  - Implemented single-scout squadrons for espionage (SpyPlanet, HackStarbase)
  - Implemented multi-scout (3+) for ELI mesh networks on invasions
  - Enhanced build strategy: 5-7 scouts instead of 2-3
  - Invasion planning attaches up to 4 scouts for strong ELI mesh
  - Added scout_count diagnostic metric for future analysis
  - **Bonus:** Fixed 11 fog-of-war Option.get() bugs that could crash AI
  - **Impact:** Scout operations fully functional, ELI mesh coordination active
- ✅ **FOG-OF-WAR REFACTORING COMPLETE (2025-11-24)**
  - Removed TEMPORARY BRIDGE that defeated fog-of-war enforcement
  - Refactored ALL ~37 functions to use FilteredGameState instead of GameState
  - AI now CANNOT access omniscient information (type-level enforcement)
  - Added helpers: isSystemColonized(), getColony()
  - Compiled successfully, tested with 50-game batch (100% success)
  - **Impact:** Fair play guaranteed, realistic AI behavior enforced
- ✅ **Engine-Level Safe Fallback Routes with Auto-Retreat Policy (2025-11-24)**
  - Integrated AI-planned fallback routes into engine's automatic seek-home system
  - Routes validate safe paths avoiding enemy territory using pathfinding
  - Added AutoRetreatPolicy (Never/MissionsOnly/Conservative/Aggressive)
  - findClosestOwnedColony() prioritizes safe routes, uses fallback routes first
  - Syncs AI controller routes to engine state after order generation
- ✅ **Phase 2d+2f+2h Complete: Tactical AI Improvements (2025-11-24)**
  - **2d - ELI/CLK:** Aggressive AI researches CLK, builds Raiders with ambush (+4 CER)
  - **2f - Defense Layering:** Priority 2.5 defends colonies before offense (74.7% → 38.2% undefended)
  - **2h - Fallback Routes:** Smart retreat system finds nearest safe colony (starbase/2+ squadrons)
  - **Results:** Improved tactical decision-making, safer fleet positioning
- ✅ **Phase 2a-2b-2g Complete: Critical AI Infrastructure (2025-11-24)**
  - **2a:** FoW Integration with RBA - FilteredGameState enforcing limited visibility
  - **2b:** Fighter/Carrier Ownership - Auto-loading, capacity violation detection
  - **2g:** Espionage Mission Targeting - 100% espionage usage, 292 missions/game
  - **Scout Auto-Fleet Creation:** Scouts now auto-deploy, enabling intelligence ops
  - **Diagnostic Infrastructure:** 29 metrics tracked, gap analysis dashboard complete
- ✅ **Gap Analysis Complete (2025-11-24)**
  - Identified 5 critical missing features (espionage, fallback, etc)
  - Diagnostic infrastructure implemented with Python analysis tools
  - Phase 2 priorities revised based on Grok feedback
  - **Key Results:** 0% capacity violations, 100% espionage, identified defense gaps
- ✅ **Architecture Revision: Removed LLM approach, added neural network self-play training (2025-11-24)**
  - Removed Mistral-7B/llama.cpp/prompt engineering
  - Added AlphaZero-style reinforcement learning
  - Small specialized networks (3.2MB vs 4GB)
  - Fast inference (10-20ms vs 3-5 seconds)
  - Leverage existing 2,800-line rule-based AI for bootstrap
- ✅ **100,000 Game Stress Test - ZERO CRASHES! (2025-11-24)**
  - Ran 100k games with GNU parallel (32 cores)
  - 100% success rate - no crashes detected
  - Tested 4-12 players across small/medium/large maps
  - Production-ready engine validation complete
- ✅ **Refactored resolve.nim into modular architecture (2025-11-24)**
  - Split 4,102 line monolith into 5 focused modules (89.7% reduction)
  - All 101 integration tests passing ✅
- ✅ **Dynamic prestige scaling system**
  - Perfect 4-act pacing across all map sizes
- ✅ Phase 2 balance testing complete across all map sizes

---

## 🎯 Project Overview

EC4X is a turn-based 4X space strategy game built in Nim with neural network AI using AlphaZero-style self-play training.

**Key Principles:**
- All enums are `{.pure.}`
- All game balance values in TOML config files
- Comprehensive integration test coverage
- NEP-1 compliant code standards
- Neural network AI via self-play (not LLMs)

---

## ✅ Complete Systems

### 1. Combat System
**Status:** ✅ Complete and tested
**Files:** `src/engine/combat/`
- 3-phase combat (Space → Orbital → Planetary)
- ELI/CLK detection mechanics
- Fighter squadron combat (no crippled state)
- Multi-faction battles

### 2. Research System  
**Status:** ✅ Complete and integrated
**Files:** `src/engine/research/`
- 11 tech fields (EL, SL, CST, WEP, TER, ELI, CLK, SLD, CIC, FD, ACO)
- Tech level advancement
- Research cost calculations

### 3. Economy System
**Status:** ✅ Complete and tested
**Files:** `src/engine/economy/`, `src/engine/salvage.nim`
- Production/income calculation
- Maintenance & upkeep
- Salvage operations
- Repair system

### 4. Prestige System
**Status:** ✅ Complete and fully integrated
**Files:** `src/engine/prestige/`
- 18 prestige sources
- Dynamic scaling by map size
- Morale system integration

### 5. Espionage System
**Status:** ✅ Complete and fully integrated
**Files:** `src/engine/espionage/`
- 7 espionage actions
- EBP/CIP budget system
- Counter-Intelligence Capability (CIC0-CIC5)
- Detection system

### 6. Diplomacy System
**Status:** ✅ Complete and integrated
**Files:** `src/engine/diplomacy/`
- Non-aggression pacts
- Violation tracking
- Diplomatic isolation

### 7. Colonization System
**Status:** ✅ Complete and integrated
**Files:** `src/engine/colonization/`
- Colony establishment
- PTU requirements
- System availability validation

### 8. Victory Conditions System
**Status:** ✅ Complete and tested
**Files:** `src/engine/victory/`
- 3 victory types (prestige, elimination, turn limit)
- Leaderboard generation

### 9. Morale System
**Status:** ✅ Complete and integrated
**Files:** `src/engine/morale/`
- 7 morale levels based on prestige
- Tax efficiency modifiers
- Combat bonus modifiers

### 10. Turn Resolution System
**Status:** ✅ Complete and integrated
**Files:** `src/engine/resolve.nim` (refactored into resolution/ modules)
- 4-phase turn structure
- Modular architecture (5 focused modules)

### 11. Fleet Management & Automated Retreat
**Status:** ✅ Complete and tested
**Files:** `src/engine/squadron.nim`, `src/engine/fleet.nim`
- Fleet composition and movement
- Automated Seek Home (strategic + tactical retreat)

### 12. Star Map System
**Status:** ✅ Complete and tested
**Files:** `src/engine/starmap.nim`
- Procedural generation
- Jump route networks

### 13. Configuration System
**Status:** ✅ Complete and integrated
**Files:** `src/engine/config/`, `config/*.toml`
- 13 type-safe TOML configuration loaders
- 2000+ configurable parameters
- Documentation sync system

---

## 🤖 AI Development Roadmap (REVISED)

### Overview: Neural Network Self-Play Training

**Approach Change:**
- ❌ **Removed**: LLM approach (Mistral-7B, llama.cpp, 4GB models, 3-5s inference)
- ✅ **Added**: Specialized neural networks (3.6MB models, 10-20ms inference)
- **Technique**: AlphaZero-style reinforcement learning with self-play
- **Bootstrap**: Use existing 2,800-line rule-based AI for initial training data

**Why This Is Better:**
1. **1,111x smaller models** (3.6MB vs 4GB)
2. **150-500x faster inference** (10-20ms vs 3-5 seconds)
3. **Game-specific learning** (EC4X strategy, not general text)
4. **Proven technique** (AlphaZero defeated world champions)
5. **Leverages existing assets** (sophisticated rule-based AI already built)

### Phase 1: Environment Setup ✅ COMPLETE
**Status:** ✅ Complete
**Deliverable:** Ready development environment

**Completed:**
- ✅ PyTorch + ROCm installed on AMD RX 7900 GRE
- ✅ ONNX Runtime available
- ✅ Rule-based AI fully functional (2,800+ lines)
- ✅ 100k game stress test (engine production-ready)
- ✅ Engine refactored and modularized

---

### Phase 2: Rule-Based AI Enhancements 🔄 IN PROGRESS
**Status:** 🔄 In Progress
**Goal:** Maximize bootstrap training data quality
**Files:** `tests/balance/ai_controller.nim`, `src/engine/fog_of_war.nim`

**Prerequisites:**
- ✅ Fog-of-war system implemented (2025-11-24)
- ✅ FoW integrated with ai_controller.nim (bridge pattern, 2025-11-24)
- ⏳ **NEXT:** Diagnostic infrastructure (before any Phase 2 tasks!)

**Critical Insight from Grok Gap Analysis:**
> "Run diagnostics. Let the numbers tell you exactly what's missing. Every flaw you fix now compounds through every self-play iteration later."

**Diagnostic Infrastructure** ✅ **COMPLETE** (2025-11-24)
- ✅ Added per-house, per-turn metric logging (tests/balance/diagnostics.nim)
- ✅ Created batch runner and analysis tools (Python)
- ✅ CSV export with 29 tracked metrics
- ✅ Gap analysis dashboard showing red flags
- **Results:** 0% capacity violations, 100% espionage usage, identified defense gaps

**Target Improvements:**

**2a. FoW Integration with RBA** ✅ **COMPLETE** (2025-11-24)
- ✅ Refactored ALL ~37 functions to use FilteredGameState instead of GameState
- ✅ **REMOVED TEMPORARY BRIDGE** - Enforces fog-of-war at type level
- ✅ Added helper functions: isSystemColonized(), getColony()
- ✅ Handle incomplete information (Option[T] for VisibleColony.production)
- ✅ Intelligence-gathering behavior (scouting, espionage targeting)
- ✅ Tested with 50-game batch - 100% success rate
- **Impact:** AI CANNOT access omniscient data, fair play guaranteed

**Actual Effort:** High complexity (~146 lines changed in ai_controller.nim)
**Documentation:** See `docs/FOG_OF_WAR_REFACTORING.md` for completion status

**2b. Fighter/Carrier Ownership System** ✅ **COMPLETE** (2025-11-24)
- ✅ Colony-owned vs carrier-owned fighters tracked (gamestate.nim)
- ✅ Capacity violation detection with grace period (economy_resolution.nim)
- ✅ Auto-loading fighters to carriers after commissioning (autoLoadFightersToCarriers)
- ✅ Fighters remain at colony if no suitable carriers available
- **Results:** 0% capacity violations, 0% idle carriers in diagnostics

**2c. Scout Operational Modes** ✅ **COMPLETE** (2025-11-24)
- ✅ Single-scout squadrons for espionage missions (SpyPlanet, HackStarbase)
- ✅ Multi-scout squadrons (3+) for ELI mesh networks on invasions
- ✅ Enhanced build strategy: 5-7 scouts instead of 2-3
- ✅ Invasion planning attaches up to 4 scouts for strong ELI mesh
- ✅ Added scout_count diagnostic metric for future analysis
- **Bonus:** Fixed 11 fog-of-war Option.get() bugs that could crash AI
- **Results:** Scout operational modes implemented, ELI mesh coordination active

**2d. ELI/CLK Arms Race Dynamics** ✅ **COMPLETE** (2025-11-24)
- ✅ CLK research in heavy tech path (20% allocation) and moderate path (33%)
- ✅ Raider builds when CLK researched (requires aggression > 0.4, militaryCount > 3)
- ✅ Lowered Raider build threshold to 100 PP (from 150 PP)
- ✅ Fixed moderate research condition from > 0.4 to >= 0.4 (enables Aggressive strategy)
- **Results:** Aggressive AI now builds Raiders with CLK ambush advantage (+4 CER)
- **Remaining:** ELI mesh network coordination (multi-scout bonuses) - deferred to Phase 3

**2e. Fighter Doctrine & ACO Research** ⏳ MEDIUM PRIORITY (After FoW + ELI/CLK)
- FD research timing (capacity utilization > 70%)
- ACO synergy with FD investment
- Starbase infrastructure requirements (1 per 5 fighters)
- Capacity multiplication strategy

**Estimated Effort:** Medium complexity (~200 lines, 7 tests)

**2f. Defense Layering Strategy** ✅ **COMPLETE** (2025-11-24)
- ✅ Priority 2.5 defense check before offensive operations
- ✅ Important colonies defended (production >= 30, lowered from 50)
- ✅ Frontier colonies defended (adjacent to enemy territory)
- ✅ Defense prioritized over expansion/offense for undefended colonies
- **Results:** 74.7% → 38.2% undefended colonies (48% reduction)
- **Remaining 38%:** Rear-area, low-value colonies (acceptable trade-off for offense)

**2g. Espionage Mission Targeting** ✅ **COMPLETE** (2025-11-24)
- ✅ Fixed scout fleet deployment (autoBalanceSquadronsToFleets now creates fleets)
- ✅ Strategic HackStarbase targeting for enemy production centers
- ✅ SpyPlanet mission execution for intel gathering
- ✅ Pre-invasion intelligence thresholds lowered
- **Results:** 100% games with espionage usage, ~292 spy missions per 100-turn game

**2h. Fallback System Designation** ✅ **COMPLETE** (2025-11-24)
- ✅ Added `FallbackRoute` type to track safe retreat destinations
- ✅ Implemented `updateFallbackRoutes()` - finds nearest safe colony (starbase or 2+ squadrons)
- ✅ Implemented `findFallbackSystem()` - lookup pre-planned retreat route
- ✅ Enhanced Priority 1 retreat logic to use fallback system (with hex distance calculation)
- ✅ Routes auto-expire after 20 turns, refreshed every 5 turns
- **Integration:** Works with engine's automatic seek-home system (`shouldAutoSeekHome`)

**2i. Multi-player Threat Assessment** ⏳ MEDIUM PRIORITY (NEW - from gap analysis)
- Problem: Attacks strongest instead of weakest player
- Implementation: `assessRelativeStrength()`, `identifyVulnerableTargets()`

**Estimated Effort:** Medium complexity (~200 lines, 6 tests)

**2j. Blockade & Economic Warfare** ⏳ LOW PRIORITY (NEW - from gap analysis)
- Problem: Ignores enemy supply lanes
- Implementation: `identifyBlockadeTargets()`, `generateBlockadeOrders()`

**Estimated Effort:** Low complexity (~150 lines, 5 tests)

**2k. Prestige Victory Path** ⏳ LOW PRIORITY (NEW - from gap analysis)
- Problem: Never pursues prestige-focused strategies
- Implementation: `assessPrestigeOpportunities()`, `prioritizePrestigeActions()`

**Estimated Effort:** Low complexity (~150 lines, 5 tests)

**Overall Phase 2 Deliverable:** Enhanced ai_controller.nim with ~2,850 lines added/modified, 85+ new tests

**Critical Path:**
1. ✅ FoW integration (2a) - COMPLETE
2. ⏳ Diagnostic infrastructure - IMMEDIATE NEXT
3. ⏳ Critical fixes (2b, 2g, 2h, 2c, 2d) based on diagnostic results

**See:** `docs/PHASE_2_PRIORITIES_ANALYSIS.md` for full gap analysis and implementation order

---

### Phase 3: Bootstrap Data Generation ⏳ TODO
**Status:** ⏳ Not Started
**Goal:** Generate 10,000+ high-quality training examples
**Files:** `training_data/bootstrap/`

**Steps:**
1. Create `tests/balance/export_training_data.nim`
2. Run 10,000 games (4 AI players each)
3. Record state-action-outcome (~1.6M examples)
4. Generate training dataset (train/validation split)

**Deliverable:** `training_data/bootstrap/*.json` (100MB-500MB compressed)

**Estimated Effort:** Low development complexity, high compute time (100 games/hour = ~100 hours CPU)

---

### Phase 4: Supervised Learning ⏳ TODO
**Status:** ⏳ Not Started
**Goal:** Train neural networks to imitate rule-based AI
**Files:** `ai_training/*.py`, `models/*.onnx`

**Steps:**
1. Implement state encoding (600-dim vector)
2. Implement action encoding (multi-head output)
3. Create PyTorch dataset loader
4. Train policy network (20 epochs)
5. Train value network (20 epochs)
6. Export to ONNX format
7. Validate ONNX inference in Nim

**Deliverable:** `models/policy_v1.onnx`, `models/value_v1.onnx` (~3.6MB total)

**Estimated Effort:** Medium complexity (Python ML pipeline), plus 1-2 hours GPU training time

---

### Phase 5: Nim Integration ⏳ TODO
**Status:** ⏳ Not Started
**Goal:** Neural network AI playable in EC4X
**Files:** `src/ai/nn_player.nim`

**Steps:**
1. Create `src/ai/nn_player.nim`
2. Implement ONNX Runtime integration
3. Add neural net AI type to game engine
4. Create evaluation framework (NN vs rule-based)
5. Run 100-game benchmark

**Deliverable:** Playable neural network AI with performance benchmarks

**Estimated Effort:** Medium complexity (Nim/ONNX integration)

---

### Phase 6: Self-Play Reinforcement Learning ⏳ TODO
**Status:** ⏳ Not Started
**Goal:** Improve beyond rule-based AI
**Files:** `ai_training/self_play.py`, `models/policy_v*.onnx`

**Steps:**
1. Create self-play game generator
2. Run 1,000 self-play games per iteration
3. Combine with bootstrap data
4. Retrain networks
5. Evaluate improvement (win rate, ELO)
6. Repeat 5-10 iterations

**Deliverable:** `models/policy_v10.onnx`, `models/value_v10.onnx` with ELO progression data

**Estimated Effort:** Low development complexity, high compute time (1000 games + training per iteration)

---

### Phase 7: Production Deployment ⏳ TODO
**Status:** ⏳ Not Started
**Goal:** Best AI available for gameplay
**Files:** Distribution package

**Steps:**
1. Package ONNX models with game
2. Add AI difficulty levels (v1 = Easy, v5 = Medium, v10 = Hard)
3. Profile inference performance
4. Optimize if needed (quantization, pruning)
5. Document AI player usage

**Deliverable:** Production-ready AI with multiple difficulty levels

**Estimated Effort:** Low-medium complexity (packaging and polish)

---

## 📋 Code Health Issues

### Code Organization & Refactoring
**Status:** ✅ **COMPLETE**

**Completed:**
- ✅ resolve.nim modularized (4,102 → 424 lines, 89.7% reduction)
- ✅ 5 focused modules created
- ✅ All 101 integration tests passing

### Pure Enum Violations
**Status:** ✅ Complete

### Hardcoded Constants
**Status:** ✅ Complete

### Constant Naming Conventions
**Status:** ✅ Complete

### Placeholder Code
**Status:** ✅ Clean

---

## 📁 Documentation Status

### Current Documentation

**Standards:**
- ✅ `docs/CLAUDE_CONTEXT.md`
- ✅ `docs/STYLE_GUIDE.md`
- ✅ `docs/TODO.md`

**AI Architecture:**
- ✅ `docs/architecture/ai-system.md` (neural network approach)
- ✅ `docs/AI_CONTROLLER_IMPROVEMENTS.md` (Phase 2 implementation plan)

**Specifications:**
- ✅ `docs/specs/reference.md`
- ✅ `docs/specs/gameplay.md`
- ✅ `docs/specs/economy.md`
- ✅ `docs/specs/diplomacy.md`
- ✅ `docs/specs/operations.md`
- ✅ `docs/specs/assets.md`

**Completion Reports:**
- ✅ `docs/PRESTIGE_IMPLEMENTATION_COMPLETE.md`
- ✅ `docs/ESPIONAGE_COMPLETE.md`
- ✅ `docs/TURN_RESOLUTION_COMPLETE.md`
- ✅ `docs/CONFIG_AUDIT_COMPLETE.md`

---

## 🧪 Test Coverage Summary

### Integration Tests (15 files, 101 total tests)
All passing ✅

### Balance Tests
- 100k game stress test complete
- Zero crashes detected
- Multi-player validated (4-12 players)

---

## 📊 Project Statistics

**Lines of Code:**
- Core engine: ~5,000+ lines
- AI controller: 2,800+ lines
- Test suite: ~2,000+ lines
- Total: ~10,000+ lines Nim

**Module Count:**
- Engine modules: 13 systems
- Test suites: 15+ integration test files
- Config files: 13 TOML files

**Documentation:**
- 50+ markdown files
- Comprehensive specs
- Complete AI architecture

---

## 🎯 Milestone History

1. ✅ M1: Basic combat and fleet mechanics
2. ✅ M5: Economy and research integration
3. ✅ Prestige: Full prestige system with 18 sources
4. ✅ Espionage: 7 espionage actions with CIC system
5. ✅ Turn Resolution: 4-phase turn structure
6. ✅ Victory & Morale: Victory conditions and morale system
7. ✅ Config System: 13 TOML files + sync script
8. ✅ Engine Integration: All config loaders implemented
9. ✅ Strategic AI (Phase 1): Rule-based AI for balance testing
10. ✅ Engine Verification: 100k game stress test (zero crashes)
11. ✅ Architecture Revision: Neural network self-play approach

---

## 📝 Notes

### PRIORITY TODO(s) ###

#### 1. ✅ **DONE** - Implement fog of war for AI (Core System Complete - 2025-11-24)

**Status:** Core fog-of-war system implemented in `src/engine/fog_of_war.nim`

**Completed:**
- `FilteredGameState` type for AI-specific game views
- `createFogOfWarView()` function to filter full GameState
- Visibility levels: Owned, Occupied, Scouted, Adjacent, None
- Integration with intelligence database for stale intel
- Helper functions: `canSeeColonyDetails()`, `canSeeFleets()`, `getIntelStaleness()`

**Next Steps:** See `docs/FOG_OF_WAR_INTEGRATION.md` for full integration plan
- Refactor ai_controller.nim to use FilteredGameState (~800 lines)
- Add intelligence-gathering behavior to RBA (~300 lines)
- Test FoW integration with balance tests

##### Fog of War – Mandatory for Both AIs (RBA and NNA)
| Question                                 | Final Decision                                   |
|------------------------------------------|--------------------------------------------------|
| Should AI have full map knowledge?       | No — never (except explicit “cheat” mode)       |
| Rule-based AI (RBA)                      | Must use same fog-of-war view as human player   |
| Neural network AI (NNA)                  | Must train and play with fog-of-war only         |
| Self-play training                       | Each empire receives its own private FoW view    |

**Why**  
- Perfect information breaks scouting, ELI/CLK, espionage, and Raider mechanics  
- Creates domain shift between training and deployment  
- Forces the neural net to learn information-gathering (the heart of 4X strategy)  
- Matches real imperfect-information research (MuZero hidden state, Libratus, etc.)

**State encoding impact**  
Add ~50–80 dims for last-seen values, stale intel, estimated enemy tech, detection risk, etc.

##### 2. Official Three-Letter Acronyms
| AI Type                  | Acronym | Full Name                        | Flavor / Usage                              |
|--------------------------|---------|----------------------------------|---------------------------------------------|
| Rule-based AI            | RBA     | Rule-Based Advisor               | “The Codex of the Great Houses”             |
| Neural network AI        | NNA     | Neural Network Autarch           | “The Mind that Devours Galaxies”            |

**UI / Difficulty example**  
- Easy  → RBA (Economic)  
- Normal → RBA (Balanced)  
- Hard  → NNA v5  
- Nightmare → NNA v10

Use RBA and NNA everywhere: code, logs, model files, menus, leaderboards.

#### 2. Combine run_balance_test_parallel.py and run_balance_test.py, with archive_old_results(). Command line args to run parallel or single. Remove old files.

#### 3. Read and consider Grok's feedback for AI architecture into phase 2+: ec4x/docs/architecture/2025-11-24-grok-ec4x-ai-feedback.md

#### 4. Incorporate gap analyses into phase 2+: ec4x/docs/architecture/2025-11-24-grok_EC4X_Bootstrap_Gap_Analysis.md

#### 5. Remove old LLM related files and folders from project

#### 6. Remove and exclude json files from repo and db if possible.

### General Notes

**Design Philosophy:**
- Event-based architecture
- Minimal coupling between systems
- All mechanics configurable via TOML
- Comprehensive test coverage
- Neural network AI via self-play

**AI Development Philosophy:**
- Leverage existing rule-based AI (don't rebuild)
- Small specialized models (not general-purpose LLMs)
- Game-specific learning (EC4X strategy, not text)
- Proven AlphaZero approach
- Incremental improvement via self-play

**Git Workflow:**
- Main branch: `main`
- Frequent commits with descriptive messages
- Pre-commit tests required
- No binaries in version control

**Session Continuity:**
- Load `@docs/STYLE_GUIDE.md` and `@docs/TODO.md` at session start
- Update TODO.md after completing milestones
- Document major changes in completion reports

---

**Last Updated:** 2025-11-24 by Claude Code
