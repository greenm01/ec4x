# EC4X TODO & Roadmap

**Last Updated:** 2026-01-09
**Branch:** refactor-engine
**Current Phase:** Phase 1 - Engine Refactoring (90% complete)
**Test Status:** KDL config migration complete, integration tests passing

---

## Overview

EC4X is a **social game** designed for human players interacting over asynchronous
turns. Development priorities focus on:

1. **Core Engine** - Clean, tested, config-driven game logic
2. **Network Protocol** - Nostr-based multiplayer infrastructure
3. **Game Server** - Daemon for turn processing
4. **Player Client** - Human interface (terminal or web)
5. **Play-Testing** - Claude-based validation (future)
6. **AI Opponents** - Optional, only if warranted (future)

**See:** [docs/README.md](README.md) for complete documentation structure

---

## Development Phases

| Phase | Status | Progress | Deliverable |
|-------|--------|----------|-------------|
| **Phase 1** | 🔄 In Progress | 90% | Engine refactoring complete |
| **Phase 2** | ⏳ Next | 0% | Nostr network protocol |
| **Phase 3** | ⏳ TODO | 0% | Game server (daemon) |
| **Phase 4** | ⏳ TODO | 0% | Player client |
| **Phase 5** | ⏳ TODO | 0% | Play-testing framework |
| **Phase 6** | ⏳ Future | 0% | AI opponents (optional) |

---

## Phase 1: Engine Refactoring 🔄 In Progress (90%)

**Goal:** Clean, tested, config-driven engine following DoD principles

### ✅ Complete

- **Config system migration to KDL** (2025-12-25)
  - All 18+ config files converted from TOML to KDL
  - `kdl_config_helpers.nim` with macro-based parsing
  - Integration tests: `test_kdl_tech.nim`, `test_kdl_economy.nim` passing
  - Boolean syntax fixed (`#true`/`#false`)
  - Float type handling for all KDL variants

- **Data-Oriented Design patterns established**
  - Types in `src/engine/types/`
  - State management in `src/engine/state/`
  - Entity mutators in `src/engine/entities/`
  - Game logic in `src/engine/systems/`

- **13 core engine systems operational**
  - Economy, research, construction, combat, diplomacy, etc.
  - Fog-of-war integrated
  - Turn cycle orchestration

### 🔄 In Progress

1. **Complete remaining KDL config loaders**
   - Convert remaining TOML loaders to KDL (if any)
   - Add integration tests for each config type
   - Verify all config fields load correctly

2. **Engine system verification**
   - Run full integration test suite
   - Verify all game mechanics work with KDL configs
   - Test edge cases and error handling

3. **Remove AI dependencies from engine**
   - Ensure engine is AI-agnostic
   - Move AI-specific code out of core systems
   - Clean separation: engine vs AI layer

### 📋 TODO

4. **Documentation cleanup**
   - Archive obsolete docs to `docs/archive/2025-12/`
   - Update architecture docs to reflect current state
   - Document engine API for client integration
   - **Update `docs/engine/ec4x_canonical_turn_cycle.md`**:
     - Specify that auto-repairs are submitted at Command Phase Part A Step 2 (Colony Automation)
     - Clarify that players can cancel auto-repair orders during submission window (Part B)
     - Document that all repairs (auto and manual) execute in Production Phase Step 2c
     - Emphasize that auto-repair and manual-repair use the same unified repair queue system

5. **Performance optimization**
   - Profile turn cycle execution
   - Optimize hot paths if needed
   - Benchmark config loading

6. **Validation and error handling**
   - Comprehensive validation for all input data
   - Clear error messages with context
   - Graceful degradation for invalid state

7. **Systems Compliance Audit Fixes** (2026-01-09 audit)
   
   **Critical (spec violations affecting game mechanics):**
   - [x] `production/commissioning.nim`: Implement repair payment at commissioning (CMD2b) ✅
     - Added treasury check before commissioning repaired ships
     - Deduct repair cost (25% build cost) from house treasury
     - Mark repairs as Stalled if insufficient funds
     - Generate RepairStalled event
     - **Location:** `commissionRepairedShips()` lines 844-933
   - [x] `espionage/spy_resolution.nim`: Fix scout detection formula (inverted signs) ✅
     - **Spec:** `1d20 + ELI + starbaseBonus vs 15 + scoutCount`
     - **Fixed:** `roll >= 15 + scoutCount - (ELI + starbase)` (correct signs)
     - Detection probabilities now match spec intent
     - **Location:** Lines 44-49
   - [x] `tech/costs.nim`: Implement logarithmic PP→RP conversion formulas ✅
     - **New:** `ERP = PP * (1 + log₁₀(GHO)/3) * (1 + SL/10)`
     - **New:** `SRP = PP * (1 + log₁₀(GHO)/4) * (1 + SL/5)`
     - **New:** `TRP = PP * (1 + log₁₀(GHO)/3.5) * (1 + SL/20)`
     - Logarithmic scaling prevents runaway snowballing
     - Updated spec and canonical doc to match
     - **Location:** Lines 18-104
   
   **Medium (game works but behavior differs from spec):**
   - [x] `income/engine.nim`: Add prestige penalty for maintenance shortfall (INC6c) ✅
     - Config exists: `prestige.kdl` maintenanceShortfall { basePenalty -5; escalationPerTurn -2 }
     - Apply escalating penalty: -5, -7, -9, -11... during shortfall processing
     - **COMPLETED:** Added prestige penalty calculation and event generation (lines 442-461)
     - **Location:** Shortfall block around line 237-463
   - [x] `combat/planetary.nim`: Verify bombardment round limit (3 vs spec's 20) ✅
     - **Spec 7.7.3:** "Maximum 20 rounds" refers to space/orbital combat
     - **Current:** `maxRounds = 3` at line 571 is **CORRECT** - 3 rounds per turn for balance
     - **Rationale:** Bombardment per turn (pacing), not continuous like space combat (20 rounds total)
     - **VERIFIED:** Intentional design choice, not a spec violation
     - Determine if 3-round limit is intentional per-turn limit or deviation
   - [x] `combat/retreat.nim`: Implement morale modifier to ROE threshold ✅
     - **Spec 7.2.3:** Morale affects effective ROE threshold (e.g., ROE 8 → ROE 6 at Crisis morale)
     - **COMPLETED:** Implemented relative morale system (prestige relative to leading house)
     - **Config:** Added `retreat.moraleRoeModifiers` with percentage thresholds to `combat.kdl`
     - **Module:** Created `combat/morale.nim` with `getMoraleROEModifier()` and `getMoraleTier()`
     - **Zero-Sum Aware:** Morale = `your_prestige / leader_prestige × 100` (scales naturally)
     - **Spec Updated:** Documented relative morale system with percentage thresholds
   - [x] `combat/drm.nim`: Fix detection bonus to apply to winner (not attacker only) ✅
     - **Spec 7.3.2:** Detection winner (either side) gets bonus
     - **COMPLETED:** Added `attackerWonDetection` field to Battle type
     - **Updated:** detection.nim returns tuple with winner info
     - **Updated:** drm.nim applies bonus to detection winner (attacker OR defender)
     - **Updated:** MultiHouseBattle uses DetectionOutcome to track winner per house
   - [ ] `fleet/dispatcher.nim`: Enforce reactivation timing
     - **Spec:** Reserve→Active: 1 turn, Mothball→Active: 3 turns
     - **Current:** Applies Active status immediately (lines 1828-1864)
     - Add `reactivationTurnsRemaining` counter to Fleet type
   
   **Minor (enhancements, cleanup):**
   - [ ] `combat/hits.nim`: Implement Critical Hit mechanic (natural 9 bypasses cripple-first)
     - **Spec 7.2.2 Rule 2:** Natural 9 can bypass cripple-all-first protection
     - Noted in code as "Phase 6 enhancement"
   - [ ] `tech/advancement.nim`: Implement breakthrough % scaling
     - **Spec:** Base 5% + 1% per 100 RP invested, capped at 15%
     - **Current:** Fixed 5% chance (line 100 hardcodes `successfulRolls = 1`)
   - [ ] `capacity/sc_fleet_count.nim`: Replace placeholder map scaling values
     - Lines 137-139, 202-203: `totalSystems = 100`, `playerCount = 4` hardcoded
     - Integrate with `state.starmap` for actual values
   - [ ] `colony/colonization.nim`: Move hardcoded `StrengthWeight` to config
     - Line 26: `StrengthWeight = 2` should be in config per CLAUDE.md guideline
   - [ ] `diplomacy/proposals.nim`: Verify/implement proposal expiration logic
     - Proposal expiration may be missing or implemented elsewhere
   - [ ] `combat/cleanup.nim`: Verify crippled facility queue clearing (CON2c)
     - Spec requires clearing queues from crippled (not just destroyed) facilities
     - May need explicit `cleanupCrippledNeorias()` function

**Estimated Completion:** 1-2 weeks

---

## Phase 2: Nostr Network Protocol ⏳ Next (0%)

**Goal:** Implement decentralized multiplayer infrastructure over Nostr

**See:** [docs/architecture/transport.md](architecture/transport.md) for design

### Key Components

1. **Order submission protocol**
   - Cryptographic signing of orders
   - Order format (likely KDL-based)
   - Verification and validation

2. **Relay communication**
   - Connect to Nostr relays
   - Publish orders as events
   - Subscribe to game events

3. **Turn coordination**
   - Detect when all players have submitted orders
   - Trigger turn resolution
   - Broadcast results

4. **Security**
   - Public key authentication
   - Order tamper detection
   - Replay attack prevention

### Implementation Steps

1. Choose Nim Nostr library or implement protocol
2. Design order event format (NIP specification)
3. Implement signing and verification
4. Test with local relay
5. Test with public relays

**Estimated Effort:** 3-4 weeks

---

## Phase 3: Game Server (Daemon) ⏳ TODO (0%)

**Goal:** Server that processes turns and maintains authoritative game state

**See:** [docs/architecture/daemon.md](architecture/daemon.md) for design

### Key Components

1. **Turn processor**
   - Accept orders from all players via Nostr
   - Execute turn cycle
   - Generate result events

2. **State management**
   - SQLite persistence
   - State snapshots per turn
   - Fog-of-war views per player

3. **Order validation**
   - Verify order signatures
   - Validate game rules
   - Reject invalid orders with clear messages

4. **Game lifecycle**
   - New game creation
   - Player registration
   - Victory detection
   - Game archival

### Implementation Steps

1. Design daemon architecture (event loop vs service)
2. Implement order queue and validation
3. Integrate with engine turn cycle
4. Implement state persistence (SQLite)
5. Add fog-of-war state export per player
6. Create admin interface for game management

**Estimated Effort:** 4-6 weeks

---

## Phase 4: Player Client ⏳ TODO (0%)

**Goal:** Human interface for submitting orders and viewing game state

### Options

**Option A: Terminal UI (TUI)**
- Nim-based (nimwave, illwill, or custom)
- Fast, lightweight
- Works over SSH

**Option B: Web Interface**
- Backend: Nim + Jester/Prologue
- Frontend: HTMX or simple JS
- Better visualization
- More accessible

**Option C: Both**
- TUI for advanced players
- Web for casual players

### Key Features

1. **Game state viewing**
   - Fog-of-war filtered view
   - Colony management
   - Fleet status
   - Research progress
   - Diplomatic relations

2. **Order submission**
   - Fleet movement orders
   - Construction queues
   - Research allocation
   - Diplomatic actions
   - Espionage operations

3. **Order validation**
   - Client-side validation (fast feedback)
   - Preview order effects
   - Confirm before submission

4. **Turn history**
   - Review past turns
   - View combat reports
   - Track prestige changes

### Implementation Steps

1. Choose UI approach (TUI vs web)
2. Design UX flow (screens, navigation)
3. Implement state viewer (read-only first)
4. Implement order builder
5. Integrate with Nostr protocol
6. Add order submission and confirmation

**Estimated Effort:** 6-8 weeks (TUI) or 8-12 weeks (web)

---

## Phase 5: Play-Testing Framework ⏳ TODO (0%)

**Goal:** Validate game mechanics and balance without building AI first

**See:** [docs/play_testing/README.md](play_testing/README.md) for overview

### Approach: Claude as Opponent

Use KDL-formatted orders with fog-of-war state exports to play against Claude.

**See:** [docs/play_testing/claude_opponent.md](play_testing/claude_opponent.md)

**Benefits:**
- Zero AI development time
- Intelligent, strategic play
- Explained reasoning for decisions
- Fast iteration on balance changes
- Transparent debugging

### Implementation Requirements

1. **State export tool**
   - Export fog-of-war view from SQLite
   - Text format for Claude to analyze
   - Include: colonies, fleets, intel, resources

2. **Orders parser**
   - Parse KDL orders format
   - Validate order syntax and legality
   - Clear error messages

3. **Orders executor**
   - Submit orders to game server
   - Execute turn
   - Generate results report

4. **Workflow automation**
   - Script to: export state → share with Claude → parse orders → execute turn
   - Iterate quickly through test games

### Testing Focus

- Game balance (economy, combat, research pacing)
- Victory condition tuning
- Strategic depth (multiple viable paths to victory)
- Diplomatic system validation
- Espionage system validation

**Estimated Effort:** 1 week implementation + ongoing play-testing

---

## Phase 6: AI Opponents ⏳ Future (0%)

**Goal:** Optional AI opponents for single-player or mixed multiplayer games

**Status:** On hold until play-testing phase complete

### Approach: Neural Network Training

Train neural networks using game data from Claude play-testing sessions.

**See:** [docs/play_testing/neural_network_training.md](play_testing/neural_network_training.md)

**Why this approach:**
- Train from expert demonstrations (Claude's games)
- 10-20 games enough to bootstrap
- Self-play generates unlimited additional training data
- Proven approach (AlphaGo, AlphaZero)
- 6-8 weeks to strong AI vs 8-12 weeks with RBA

**Prerequisites:**
- 10-20 complete Claude games
- SQLite diagnostics with state-action-outcome data
- PyTorch/ML infrastructure

**Decision point:** Only build if warranted after play-testing reveals need

---

## Current Tasks (This Week)

### 1. 🎯 HIGH - Verify Config Migration
- [ ] Run full integration test suite
- [ ] Test all engine systems with KDL configs
- [ ] Fix any remaining config loading issues

### 2. 📝 MEDIUM - Documentation Review
- [ ] Update architecture docs to reflect current state
- [ ] Archive obsolete AI/RBA docs (move to `docs/archive/2025-12/`)
- [ ] Verify all links in documentation work

### 3. 🧹 LOW - Repository Cleanup
- [ ] Remove obsolete files shown in git status
- [ ] Clean up build artifacts
- [ ] Verify `.gitignore` is complete

---

## Recent Completions

### KDL Config Migration (2025-12-25)

**Complete:**
- ✅ Created `kdl_config_helpers.nim` with macro-based parsing
- ✅ Migrated `ships_config.nim` to KDL (reference implementation)
- ✅ Converted all 18+ TOML config files to KDL format
- ✅ Fixed boolean syntax (`true` → `#true`, `false` → `#false`)
- ✅ Fixed float type handling (KFloat, KFloat32, KFloat64)
- ✅ Created integration tests: `test_kdl_tech.nim`, `test_kdl_economy.nim`
- ✅ All tests passing (395+ config fields verified)

### Documentation Cleanup (2025-12-25)

**Complete:**
- ✅ Removed AI-focused docs from `docs/architecture/`
- ✅ Removed directories: `docs/ai/`, `docs/testing/`, `docs/balance/`
- ✅ Merged `docs/architecture/engine/` into `docs/engine/`
- ✅ Completely rewrote `docs/README.md` for refactor-engine branch
- ✅ Created `docs/play_testing/` with Claude opponent design
- ✅ Documented neural network training approach

---

## Branch Strategy

**Current Branch:** `refactor-engine`

**Goal:** When engine refactoring is complete and tested, this branch will
replace `main` as the canonical version.

**Why separate branch:**
- Main branch has old RBA/AI code we're removing
- Clean slate for architecture improvements
- Freedom to make breaking changes
- Merge when ready, not incrementally

**Criteria for merge to main:**
- Engine refactoring 100% complete
- All integration tests passing
- Config system fully migrated and tested
- Documentation up to date
- No AI dependencies in core engine

---

## Documentation Organization

**See:** [docs/README.md](README.md) for complete structure

### Key Documentation

- **Specifications:** `docs/specs/*.md` - Game rules (preserve)
- **Architecture:** `docs/architecture/*.md` - System design
  - `transport.md` - Nostr protocol ⭐
  - `daemon.md` - Game server ⭐
  - `storage.md` - Persistence
  - `dataflow.md` - Turn resolution
- **Engine Details:** `docs/engine/**/*.md` - Implementation
  - `architecture/turn-cycle.md` - Turn execution
  - `mechanics/*.md` - Game mechanics
  - `telemetry/*.md` - Diagnostics system
- **Play-Testing:** `docs/play_testing/*.md` - Testing approach

---

## Design Philosophy

**Data-Oriented Design:**
- Separate data (types) from behavior (procs)
- Use `Table[Id, Entity]` for all game entities
- Pure functions for game logic
- State mutations through entity operations

**Configuration-Driven:**
- All game balance values in KDL configs
- No hardcoded magic numbers
- Easy tuning without recompilation
- Reload configs for rapid iteration

**Fog-of-War Enforcement:**
- Engine provides filtered views per player
- AI/clients only see what they should
- No omniscient state access
- Intelligence system tracks visibility

**Multiplayer-First:**
- Core experience is human vs human
- Asynchronous turn-based gameplay
- Decentralized Nostr protocol
- No trusted central authority required

**AI is Optional:**
- Build playable game first
- Validate with Claude play-testing
- Only add AI if needed
- Train from expert demonstrations

---

## Notes

**When refactor-engine is complete:**
1. Merge to main (or make refactor-engine the new main)
2. Archive old main branch for reference
3. Update README.md at project root
4. Tag release: v2.0.0 (clean architecture)

**This branch will become the canonical version when:**
- Engine systems are fully tested and stable
- Config migration is complete and verified
- Documentation reflects current architecture
- Ready to begin Phase 2 (Nostr protocol)

---

**For historical context:**
- See `docs/archive/` for previous versions of TODO.md
- Previous focus was on AI development (RBA, GOAP, neural networks)
- New focus is on core engine + network + multiplayer
