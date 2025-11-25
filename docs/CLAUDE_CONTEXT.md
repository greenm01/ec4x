# Claude Code Session Context

**Load these files at the start of EVERY session:**
```
@docs/STYLE_GUIDE.md
@docs/TODO.md
@docs/BALANCE_TESTING_METHODOLOGY.md (if working on AI/balance)
```

---

## Critical Rules (Never Forget)

1. **All enums MUST be `{.pure.}`** in code
2. **No hardcoded game balance values** - use TOML config files
3. **Follow NEP-1 Nim conventions** - see STYLE_GUIDE.md
4. **Update TODO.md** after completing milestones
5. **Run tests before committing** - all tests must pass
6. **Don't create new markdown docs without explicit permission**
7. **Add focused API documentation** - when touching engine code, add concise doc comments explaining purpose and key behavior. Prioritize maintainability over comprehensiveness. Avoid verbose explanations or rationale unless architecturally critical.
8. **Engine respects fog-of-war** - Never use omniscient game state. Only use intelligence database (house.intelligence) and visible systems.
9. **Use Data Oriented Design (DOD) software principles when feasible**
10. **🔴 CRITICAL: Use proper logging, not echo** - See "Logging Rules" section below
11. **🔴 CRITICAL: Track all player-affecting metrics** - See "Unknown-Unknowns Testing" section below
12. **🔴 CRITICAL: Force recompile in test scripts** - Prevent stale binary bugs

## File Organization Rules (CRITICAL - Read First!)

**NEVER create scattered markdown files.** Follow this strict hierarchy:

### Where Things Go:

1. **Architecture/Implementation Notes** → Source code doc comments (shows in API docs)
   ```nim
   ## Module: spacelift.nim
   ##
   ## ARCHITECTURE: Spacelift ships are individual units NOT squadrons
   ## Per operations.md:1036, they travel with fleets but separately
   ```

2. **Current System Status** → `docs/TODO.md` (single source of truth)
   - What's complete, what's in progress, what's next
   - Test coverage status
   - Recent changes
   - Task tracking and milestones

3. **Open Issues/Gaps** → `docs/OPEN_ISSUES.md` (single file, organized by system)
   - Known bugs
   - Missing features
   - Architecture debt
   - Delete after fixing

4. **Balance Testing Results** → `balance_results/` directory
   - ONLY generated reports (ANALYSIS_REPORT.md from tests)
   - Archives are auto-managed
   - DO NOT create manual markdown files here

5. **Session Context** → This file (CLAUDE_CONTEXT.md)
   - Rules and conventions
   - Quick reference
   - NOT a dumping ground

### What NOT To Do:

❌ DO NOT create new markdown docs without explicit permission
✅ Add architecture notes to `src/engine/spacelift.nim` header

❌ DO NOT create random markdown files anywhere
✅ Use the hierarchy above

### When You Need To Track Something:

1. **Bug/gap found?** → Add to `docs/OPEN_ISSUES.md` with [ ] checkbox
2. **Feature complete?** → Update `docs/TODO.md`, remove from OPEN_ISSUES.md
3. **Architecture explanation?** → Add as doc comment in source file
4. **Balance test result?** → Auto-generated, already in balance_results/

---

## 🔴 Logging Rules (CRITICAL)

### Why Logging Matters

The "Brain-Dead AI" bug (2025-11-25) was invisible for hours because we used `echo` statements that disappear in release builds. Proper logging would have caught this immediately.

### Nim Logging Architecture

**Use `std/logging` for all engine code:**

```nim
import std/logging

# Initialize logger in main.nim or daemon.nim
var logger = newConsoleLogger(lvlInfo, useStderr=true)
addHandler(logger)

# In engine modules
import std/logging

proc resolveTurn*(state: var GameState, orders: Table[HouseId, OrderPacket]): TurnResult =
  info "Resolving turn ", state.turn
  debug "Processing ", orders.len, " order packets"

  # Critical events - always logged
  info "Turn ", state.turn, " resolved: ", result.events.len, " events"

  # Detailed traces - only in debug builds
  debug "Fleet ", fleetId, " moved from ", oldLoc, " to ", newLoc

  # Errors - always logged with context
  error "Invalid order from ", houseId, ": ", order, " - reason: ", reason
```

### Log Levels

- **`lvlError`** - Critical failures (invalid orders, state corruption)
- **`lvlWarn`** - Concerning behavior (missing orders, zero expansion)
- **`lvlInfo`** - Important events (turn resolution, colonization, combat)
- **`lvlDebug`** - Detailed traces (fleet movement, order processing)
- **`lvlAll`** - Everything (use sparingly - performance impact)

### When to Log

✅ **Always Log:**
- Turn start/end
- Order validation failures
- Combat outcomes
- Colony establishment
- Fleet commissioning
- State mutations (with before/after values)

✅ **Log at Info Level:**
- AI decision rationale (why this order was chosen)
- Resource allocation (why build X not Y)
- Strategic pivots (economy → military)

✅ **Log at Debug Level:**
- Fleet pathfinding
- Fog-of-war filtering
- Intelligence gathering
- Detailed combat calculations

❌ **Don't Log:**
- Inside tight loops (performance)
- Redundant info (already in TurnResult)
- Secrets/passwords (security)

### File Logging for Post-Mortem

```nim
# For balance testing, write to files
var fileLogger = newFileLogger("balance_results/game_12345.log",
                               fmtStr="$time [$levelname] $appname: ")
addHandler(fileLogger)
```

### Integration with Diagnostics

Logging complements diagnostics:
- **Diagnostics (CSV):** Quantitative metrics for pattern analysis
- **Logs (text):** Qualitative context for debugging specific games

---

## 🔴 Unknown-Unknowns Testing (CRITICAL)

### Philosophy

> "You don't know what you don't know until you observe it happening."

Complex AI systems exhibit emergent behaviors that can't be predicted. The only way to catch them is **comprehensive observation** of live gameplay.

### The Unknown-Unknown Discovery That Almost Cost Us

**2025-11-25: The "Stale Binary" Meta-Bug**

**Symptom:** 100-game test showed AI stuck at 1 colony forever (0% expansion)
**Investigation:** Manual test showed AI working perfectly
**Root Cause:** Test script was using **stale binary compiled before persistent orders**
**Impact:** 4+ hours wasted chasing a "bug" that didn't exist in code
**Lesson:** Testing infrastructure itself can have unknown-unknowns!

### Comprehensive Metrics Tracking

**Rule:** Track EVERY metric that affects player experience.

See `tests/balance/diagnostics.nim` for full implementation. Minimum metrics:

```nim
type DiagnosticMetrics = object
  # Economy
  treasury, production, grossOutput, maintenanceCost, constructionSpending

  # Military
  squadronCount, etacCount, scoutCount, fighterCount, raiderCount

  # Orders (CRITICAL for catching AI failures)
  fleetOrdersSubmitted, buildOrdersSubmitted, colonizeOrdersSubmitted
  ordersRejected, rejectionReasons

  # Build Queues (CRITICAL for catching construction stalls)
  totalBuildQueueDepth, etacInConstruction, shipsUnderConstruction

  # Commissioning (CRITICAL for catching production failures)
  shipsCommissionedThisTurn, etacCommissionedThisTurn

  # Fleet Activity (CRITICAL for catching movement bugs)
  fleetsMoved, systemsColonized, failedColonizationAttempts
  fleetsWithOrders, stuckFleets

  # ETAC Specific (CRITICAL for expansion)
  totalETACs, etacsWithoutOrders, etacsInTransit
```

### Detection Workflow

```
1. Run 100+ games with full diagnostic logging
   ↓
2. Analyze with Polars (Python dataframes)
   - Find anomalies (zero orders, stuck colonies)
   - Correlate metrics (treasury up, orders down = bug)
   ↓
3. Formulate hypotheses
   ↓
4. Add targeted logging to engine
   ↓
5. Run 50 more games with enhanced logs
   ↓
6. Confirm root cause → fix → regression test
```

### Regression Prevention

**Test Script Rules:**

```python
# ❌ BAD - uses cached binary
def run_test():
    subprocess.run(["./run_simulation", ...])

# ✅ GOOD - forces recompile
def run_test():
    # Check if source newer than binary
    if is_source_newer("run_simulation.nim", "run_simulation"):
        subprocess.run(["nim", "c", "-d:release", "run_simulation.nim"])

    # Verify binary timestamp
    binary_time = os.path.getmtime("run_simulation")
    if time.time() - binary_time > 3600:  # 1 hour old
        logger.warning("Binary is >1 hour old - may be stale")

    subprocess.run(["./run_simulation", ...])
```

### Integration with CI/CD

```yaml
# .github/workflows/balance-tests.yml
- name: Force Clean Build
  run: |
    rm -f tests/balance/run_simulation
    nim c -d:release tests/balance/run_simulation.nim

- name: Verify Binary Timestamp
  run: |
    if [ $(find tests/balance/run_simulation -mmin +5) ]; then
      echo "ERROR: Binary not freshly compiled!"
      exit 1
    fi
```

### Documentation

See `docs/BALANCE_TESTING_METHODOLOGY.md` section "Unknown-Unknowns Testing Philosophy" for complete methodology.

---

## Project Architecture Quick Reference

```
src/
├── common/          # Shared types, utilities (source of truth)
├── engine/          # Game engine modules
│   ├── combat/
│   ├── economy/
│   ├── espionage/
│   ├── diplomacy/
│   ├── research/
│   ├── victory/
│   ├── morale/
│   ├── intelligence/  # Intel reports & fog-of-war
│   ├── fog_of_war.nim # FoW filtering system (NEW - 2025-11-24)
│   └── config/      # TOML config loaders
├── client/          # Client-side code
└── main.nim         # Entry point

config/              # TOML configuration files
├── prestige.toml
├── espionage.toml
└── ...

balance_results/     # Balance testing output (gitignored)
└── diagnostics/     # Per-turn CSV metrics (game_*.csv)

docs/
├── specs/           # Game design specifications
├── architecture/    # Technical design docs
│   ├── intel.md     # Fog-of-war specification
│   └── 2025-11-24-grok-ec4x-ai-feedback.md  # AI architecture review
├── milestones/      # Historical completion reports
├── guides/          # How-tos and standards
├── api/             # Generated API documentation (HTML)
├── FOG_OF_WAR_INTEGRATION.md  # FoW integration plan (NEW)
└── AI_CONTROLLER_IMPROVEMENTS.md  # Phase 2 implementation plan

tests/
├── unit/            # Unit tests
├── integration/     # Integration tests (101+ tests)
├── balance/         # Balance testing + AI controller (RBA)
│   ├── ai_controller.nim          # Rule-Based AI (2,800+ lines)
│   ├── run_simulation.nim         # Balance test binary (called by Python)
│   ├── game_setup.nim             # Test game initialization
│   ├── diagnostics.nim            # Per-turn metric logging
│   ├── run_parallel_diagnostics.py # Parallel diagnostic runner
│   └── analyze_phase2_gaps.py     # Polars-based CSV analysis
└── scenarios/       # Scenario tests

# Root-level Python scripts (IMPORTANT: These are the main test runners)
run_balance_test.py              # Strategic balance (win rates, prestige)
run_balance_test_parallel.py     # Parallel strategic testing
run_map_size_test.py            # Map size scaling tests
run_stress_test.py              # Stability/stress testing
```

---

## Configuration System

**IMPORTANT:** See `docs/CONFIG_SYSTEM.md` for complete architecture details.

**All game balance values come from TOML files (13 total):**
- `config/prestige.toml` - Prestige event values
- `config/espionage.toml` - Espionage costs, effects, detection
- `config/economy.toml`, `config/tech.toml`, `config/combat.toml`, etc.
- `game_setup/standard.toml` - Starting conditions (scenario files)

**Config loaders use toml_serialization for type-safety:**
```nim
# Config loader (in src/engine/config/)
import toml_serialization

type
  PrestigeConfig* = object
    victory*: VictoryConfig
    economic*: EconomicPrestigeConfig
    # ... nested structure matches TOML sections

var globalPrestigeConfig* = loadPrestigeConfig()

# Usage in engine code
result.prestige = config.economic.tech_advancement  # NOT hardcoded +2
```

**Key conventions:**
- TOML field names use `snake_case`
- Nim field names match TOML exactly (e.g., `tech_advancement*: int`)
- Config structure is nested matching TOML sections
- Global config instances auto-load at module import

---

## Enum Convention

**In code:** Always `{.pure.}` and fully qualified
```nim
type
  MoraleLevel* {.pure.} = enum
    Low, Normal, High

# Usage
let level = MoraleLevel.High  # NOT just "High"
```

**In specs:** Use short names for readability
```markdown
When morale is High, tax efficiency increases by 10%.
```

---

## API Documentation

**IMPORTANT:** Complete API reference available at `docs/api/engine/index.html`

**Use API docs to:**
- Verify correct enum values (PlanetClass, ResourceRating, ShipClass, etc.)
- Check function signatures before writing code
- Understand module architecture and relationships
- Prevent compilation errors from wrong type names

**Regenerate docs after API changes:**
```bash
cd docs/api
./generate_docs.sh
```

**Key modules documented:**
- `core.html` - Base types (HouseId, SystemId, FleetId)
- `units.html` - Ship classes and weapon systems
- `planets.html` - Planet/resource enums
- `spacelift.html` - Spacelift ships (individual units, NOT squadrons)
- `fleet.html` - Fleet management with separated squadrons/spacelift
- `squadron.html` - Combat squadrons with CR/CC
- `gamestate.html` - Complete game state structure

**Architecture reminder:**
```
Fleet → Squadrons (combat) + SpaceLiftShips (transport/colonization)
```
Spacelift ships are individual units per operations.md:1036, NOT squadrons.

---

## Testing Requirements

**Before ANY commit:**
```bash
# Run all integration tests
nim c -r tests/integration/test_*.nim

# Verify project builds
nimble build
```

**Test coverage:** 76+ integration tests must pass

### Balance Testing

**IMPORTANT:** Balance testing scripts are in the **project root directory**, not tests/balance/.

#### Test Runner Scripts (Project Root)

```bash
# Strategic balance tests (win rates, prestige analysis)
python3 run_balance_test.py                      # Sequential 10-game test
python3 run_balance_test_parallel.py             # Parallel multi-game test
python3 run_map_size_test.py                     # Map size scaling tests
python3 run_stress_test.py                       # Stability testing

# Diagnostic tests (Phase 2 metrics, per-turn CSV data)
cd tests/balance
python3 run_parallel_diagnostics.py 50 30 16    # 50 games, 30 turns, 16 workers
python3 analyze_phase2_gaps.py                   # Analyze diagnostic CSVs
```

**Output Locations:**
- **Diagnostic CSVs:** `balance_results/diagnostics/game_*.csv`
- **Analysis reports:** Console output or specified files
- **Archives:** `~/.ec4x_test_data/` (restic backup with date tags)

**Why use run_balance_test.py:**
- Runs 10 games with unique seeds for statistical significance
- Automatically archives old results to restic backup (before tests)
- Provides comprehensive win rate and prestige analysis
- Ensures consistent testing methodology

**The script flow:**
1. Archives existing `balance_results/` to `~/.ec4x_test_data/` (restic backup with date tag)
2. Cleans up old results directory
3. Runs 10 games with strategies: Aggressive, Economic, Balanced, Turtle
4. Aggregates results showing win counts and average prestige per strategy

**Diagnostic CSV Format:**
- Per-house, per-turn metrics (29+ columns)
- Used for Phase 2 gap analysis (scouts, fighters, espionage, defense, invasions)
- Generated by `tests/balance/diagnostics.nim` during simulation
- Analyzed by `tests/balance/analyze_phase2_gaps.py` using Polars

**Analysis workflow:**
1. Run: `python3 run_balance_test.py > /tmp/balance_test_full.log`
2. Analyze: Review win rates, prestige trends, and turn snapshots in balance_results/
3. Archive: Script handles this automatically before next run

---

## Fog-of-War System (NEW - 2025-11-24)

**Critical for AI development:** FoW is MANDATORY for both RBA and NNA.

**Module:** `src/engine/fog_of_war.nim`

**Key types:**
```nim
type
  FilteredGameState* = object
    ## AI-specific view with limited visibility
    viewingHouse*: HouseId
    ownColonies*: seq[Colony]      # Full details
    ownFleets*: seq[Fleet]         # Full details
    visibleSystems*: Table[SystemId, VisibleSystem]  # Filtered view
    visibleColonies*: seq[VisibleColony]  # Enemy colonies (if visible)
    visibleFleets*: seq[VisibleFleet]     # Enemy fleets (if detected)

  VisibilityLevel* {.pure.} = enum
    Owned, Occupied, Scouted, Adjacent, None
```

**Usage:**
```nim
# In simulation runner or AI interface
let filteredView = createFogOfWarView(gameState, houseId)
let orders = aiController.generateAIOrders(filteredView, rng)
```

**Visibility rules:**
- **Owned**: Full details where house has colonies
- **Occupied**: Full details where house has fleets
- **Scouted**: Stale intel from intelligence database
- **Adjacent**: System awareness only, no details
- **None**: System not visible

**Integration status:**
- ✅ Core system complete
- ⏳ ai_controller.nim refactoring pending (~800 lines)
- ⏳ Intelligence-gathering behavior pending (~300 lines)

**Documentation:** See `docs/FOG_OF_WAR_INTEGRATION.md` for full integration plan

---

## When Compacting Context

**Include in summary:**
- "Project follows STYLE_GUIDE.md (NEP-1 + pure enums)"
- "All balance values in TOML configs"
- "101+ integration tests passing"
- "Fog-of-war system implemented (mandatory for AI)"
- "Engine respects fog-of-war - no omniscient automatic behavior"
- Current system status from TODO.md

---

## Pre-Commit Checklist

- [ ] All enums are `{.pure.}`
- [ ] No hardcoded game values (check TOML)
- [ ] Tests pass: `nim c -r tests/integration/test_*.nim`
- [ ] Project builds: `nimble build`
- [ ] No binaries or generated data files (json, etc) committed
- [ ] Updated TODO.md if milestone complete
- [ ] Followed NEP-1 naming conventions
- [ ] Update OPEN_ISSUES.md
- [ ] Engine respects fog-of-war (uses house.intelligence only)

---

## Quick Commands

```bash
# Integration tests
nim c -r tests/integration/test_espionage.nim
bash scripts/run_all_tests.sh

# Balance testing (from project root)
python3 run_balance_test_parallel.py --workers 8 --games 50 --turns 30
cd tests/balance && python3 run_parallel_diagnostics.py 50 30 16
cd tests/balance && python3 analyze_phase2_gaps.py

# Code audits
grep -r "prestige.*= [0-9]" src/engine/                    # Hardcoded values
grep -r "enum$" src/ --include="*.nim" | grep -v "{.pure.}" # Non-pure enums

# Build and docs
nimble build
cd docs/api && ./generate_docs.sh
python3 scripts/sync_specs.py
```

---

## Current State (Brief)

**See TODO.md for full details**

✅ **Complete:**
- Core engine (100% functional)
- Prestige system (fully integrated)
- Espionage (7 actions, configurable)
- Diplomacy (pacts, violations)
- Victory conditions (3 types)
- Morale system (7 levels)
- Turn resolution integration
- Phase 1: Fixed 4-player balance testing (parallel infrastructure)

🔄 **In Progress:**
- Phase 2: Rule-Based AI (RBA) Enhancements
  - ✅ Cipher Ledger timeline system (abstract cycles, 2025-11-24)
  - ✅ Parallel diagnostic infrastructure (3,000 games/min, 2025-11-24)
  - ✅ Fog-of-war fully integrated (2025-11-24)
  - ✅ Fighter/carrier ownership system (2025-11-24)
  - ✅ Scout operational modes (2025-11-24)
  - ✅ Defense layering strategy (2025-11-24)
  - ✅ Espionage mission system (2025-11-24)
  - ⏳ Build queue refactor (architectural bottleneck documented)
  - ⏳ Invasion logic investigation (zero invasions in 100-turn tests)
  - ⏳ HackStarbase targeting (currently 0 missions, 100% SpyPlanet)

**Test Coverage:** 101+ integration tests passing
