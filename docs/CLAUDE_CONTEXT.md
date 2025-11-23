# Claude Code Session Context

**Load these files at the start of EVERY session:**
```
@docs/STYLE_GUIDE.md
@docs/STATUS.md
@docs/BALANCE_TESTING_METHODOLOGY.md (if working on AI/balance)
```

---

## Critical Rules (Never Forget)

1. **All enums MUST be `{.pure.}`** in code
2. **No hardcoded game balance values** - use TOML config files
3. **Follow NEP-1 Nim conventions** - see STYLE_GUIDE.md
4. **Update STATUS.md** after completing milestones
5. **Run tests before committing** - all tests must pass

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

2. **Current System Status** → `docs/STATUS.md` (single source of truth)
   - What's complete, what's in progress, what's next
   - Test coverage status
   - Recent changes

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

❌ DO NOT create `ENGINE_GAPS_SPACELIFT.md`
✅ Add architecture notes to `src/engine/spacelift.nim` header

❌ DO NOT create `AI_STRATEGIC_GAPS.md`
✅ Add to `docs/OPEN_ISSUES.md` under "AI System" section

❌ DO NOT create `SESSION_SUMMARY_*.md`
✅ Update `docs/STATUS.md` with changes

❌ DO NOT create random markdown files anywhere
✅ Use the hierarchy above

### When You Need To Track Something:

1. **Bug/gap found?** → Add to `docs/OPEN_ISSUES.md` with [ ] checkbox
2. **Feature complete?** → Update `docs/STATUS.md`, remove from OPEN_ISSUES.md
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
├── milestones/      # Historical completion reports
├── guides/          # How-tos and standards
└── api/             # Generated API documentation (HTML)

tests/
├── unit/            # Unit tests
├── integration/     # Integration tests
├── balance/         # Balance testing
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

**IMPORTANT:** Always use the balance test runner script for AI testing:

```bash
# Correct: Run full 10-game test suite
python3 run_balance_test.py

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

## When Compacting Context

**Include in summary:**
- "Project follows STYLE_GUIDE.md (NEP-1 + pure enums)"
- "All balance values in TOML configs"
- "76+ integration tests passing"
- Current system status from STATUS.md

---

## Pre-Commit Checklist

- [ ] All enums are `{.pure.}`
- [ ] No hardcoded game values (check TOML)
- [ ] Tests pass: `nim c -r tests/integration/test_*.nim`
- [ ] Project builds: `nimble build`
- [ ] No binaries committed
- [ ] Updated STATUS.md if milestone complete
- [ ] Followed NEP-1 naming conventions

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

**See STATUS.md for full details**

✅ **Complete:**
- Prestige system (fully integrated)
- Espionage (7 actions, configurable)
- Diplomacy (pacts, violations)
- Colonization (prestige awards)
- Victory conditions (3 types)
- Morale system (7 levels)
- Turn resolution integration

📋 **Next Up:**
- Blockade mechanics
- Espionage order execution
- Documentation cleanup (in progress)

**Test Coverage:** 76+ integration tests passing
