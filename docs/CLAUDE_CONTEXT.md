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
8. **ALWAYS respect fog-of-war** - Engine automatic behavior (retreats, pathfinding, AI decisions) must ONLY use information available to the player/house. Never use omniscient game state. Check intelligence database (house.intelligence) and visible systems only.

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
│   ├── ai_controller.nim  # Rule-Based AI (2,800+ lines)
│   ├── run_simulation.nim # Balance test runner
│   └── game_setup.nim     # Test game initialization
└── scenarios/       # Scenario tests
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

**IMPORTANT:** Always use the balance test runner scripts for AI testing:

```bash
# Correct: Run full 10-game test suite
python3 run_balance_test.py

Or for parallel tests:
python3 run_balance_test_parallel.py

# Incorrect: Don't run individual simulations
# ./tests/balance/run_simulation 100 42  # NO - use script instead
```

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
- [ ] Engine automatic behavior respects fog-of-war (uses house.intelligence only)

---

## Quick Commands

```bash
# Run specific test suite
nim c -r tests/integration/test_espionage.nim

# Check for hardcoded values (audit)
grep -r "prestige.*= [0-9]" src/engine/

# Find non-pure enums (audit)
grep -r "enum$" src/ --include="*.nim" | grep -v "{.pure.}"

# Sync specs from TOML
python3 scripts/sync_specs.py

# Run all tests
bash scripts/run_all_tests.sh
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
  - ✅ Fog-of-war core system complete (2025-11-24)
  - ⏳ FoW integration with ai_controller.nim (~800 lines to refactor)
  - ⏳ Fighter/carrier ownership system
  - ⏳ Scout operational modes & ELI/CLK arms race
- Multi-generational timeline validation (1 turn = 5-10 years)
- 4-act game structure testing

**Test Coverage:** 101+ integration tests passing
