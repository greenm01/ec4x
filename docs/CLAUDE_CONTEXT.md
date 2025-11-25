# Claude Code Session Context

**Load at session start:** `@docs/TODO.md` `@docs/STYLE_GUIDE.md`

---

## Critical Rules (Never Forget)

1. **All enums MUST be `{.pure.}`**
2. **No hardcoded balance values** - use TOML configs
3. **Follow NEP-1** - see STYLE_GUIDE.md
4. **Update TODO.md** after milestones
5. **Run tests before commits** - `nimble test`
6. **Max 7 markdown files in /docs root** - archive old docs to `/docs/archive/[date]/`
7. **Add focused doc comments** when touching engine code
8. **Engine respects fog-of-war** - use house.intelligence, not omniscient state
9. **Use proper logging** - `std/logging`, NOT echo statements
10. **🔴 ALWAYS use nimble tasks** - NEVER run Python/bash/nim directly

---

## File Organization (Keep Project Clean!)

### /docs Root (MAX 7 FILES - Current)
1. CLAUDE_CONTEXT.md - This file
2. TODO.md - Living roadmap
3. STYLE_GUIDE.md - Coding standards
4. README.md - Docs overview
5. KNOWN_ISSUES.md - Current issues
6. OPEN_ISSUES.md - Tracked issues
7. BALANCE_TESTING_METHODOLOGY.md - Testing approach

**❌ NO other .md files in /docs root!**

### Organized Subdirectories
- `/docs/architecture/` - System design, vision (**PRESERVE**)
- `/docs/specs/` - Game rules (**PRESERVE**)
- `/docs/guides/` - Implementation guides
- `/docs/milestones/` - Historical milestones
- `/docs/archive/` - Obsolete docs (organized by date)

### When Creating Documentation
1. ✅ Can it go in TODO.md? → Add there
2. ✅ Completion report? → Archive to `/docs/archive/[date]/`
3. ✅ Architecture? → `/docs/architecture/`
4. ✅ Guide? → `/docs/guides/`
5. ✅ Milestone? → `/docs/milestones/`

### Periodic Cleanup
```bash
ls docs/*.md | wc -l  # Should be 7
# If more: archive to docs/archive/YYYY-MM-obsolete/
```

---

## Testing Workflow (Nimble-First)

**🔴 CRITICAL: Use nimble tasks ONLY. Never run Python/bash/nim directly.**

### Quick Commands
```bash
# Standard tests
nimble test                    # All integration tests
nimble testBalanceQuick        # Quick validation (20 games, ~10s)
nimble buildBalance            # Build balance binary
nimble cleanBalance            # Clean artifacts

# 4-Act testing
nimble testBalanceAct1         # Act 1 (7 turns)
nimble testBalanceAct2         # Act 2 (15 turns)
nimble testBalanceAct3         # Act 3 (25 turns)
nimble testBalanceAct4         # Act 4 (30 turns)
nimble testBalanceAll4Acts     # All 4 acts (400 games)

# Unknown-unknowns detection
nimble testUnknownUnknowns     # 200 games + analysis
nimble analyzeDiagnostics      # Analyze Phase 2 gaps

# Stress testing
nimble testStressAI            # 1000 games
nimble testStress              # 100k games
```

### Why Nimble?
- **Prevents stale binaries**: Uses `--forceBuild` (full recompilation every time)
- **Git hash tracking**: Verifies binary matches source
- **Regression safe**: No incremental compilation bugs
- **Cross-platform**: Works everywhere

**Output:** `balance_results/diagnostics/game_*.csv` + git hash verification

---

## Logging Rules

**Use `std/logging`, NOT echo:**

```nim
import std/logging

# Critical events
info "Turn ", state.turn, " resolved: ", result.events.len, " events"

# Debug traces
debug "Fleet ", fleetId, " moved from ", oldLoc, " to ", newLoc

# Errors with context
error "Invalid order from ", houseId, ": ", reason
```

**Why:** Echo disappears in release builds. The "Brain-Dead AI" bug (2025-11-25) was invisible for 4 hours because of echo statements.

---

## Unknown-Unknowns Testing

### Philosophy
> "You don't know what you don't know until you observe it."

Complex systems exhibit emergent behaviors. Catch them with **comprehensive observation**.

### Key Metrics (see tests/balance/diagnostics.nim)
```nim
# Track EVERYTHING that affects gameplay
- Orders submitted/rejected (catches AI failures)
- Build queue depth (catches construction stalls)
- Ships commissioned (catches production bugs)
- Fleet movement (catches stuck fleets)
- ETAC activity (catches expansion failures)
```

### Detection Workflow
1. Run 100+ games → CSV diagnostics
2. Analyze with Polars (Python)
3. Find anomalies → Formulate hypotheses
4. Add targeted logging → Re-test
5. Fix → Regression test with nimble

---

## Configuration System

**All balance values from TOML (13 files):**
- `config/prestige.toml`, `config/espionage.toml`, etc.
- Type-safe loaders via `toml_serialization`
- TOML uses `snake_case`, Nim fields match exactly

```nim
# ❌ BAD - hardcoded
result.prestige = 2

# ✅ GOOD - from config
result.prestige = globalPrestigeConfig.economic.tech_advancement
```

---

## Architecture Quick Reference

```
src/engine/          # 13 major systems (combat, economy, etc.)
  └─ fog_of_war.nim  # FoW filtering (mandatory for AI)

tests/balance/       # AI testing + diagnostics
  ├─ ai_controller.nim        # Rule-Based AI (2,800+ lines)
  ├─ run_simulation.nim       # Test binary
  └─ diagnostics.nim          # Metric logging

balance_results/diagnostics/  # CSV output (gitignored)

docs/
  ├─ architecture/   # Vision (**PRESERVE**)
  ├─ specs/          # Rules (**PRESERVE**)
  └─ archive/        # Old docs
```

**Key principle:** Fleet → Squadrons (combat) + SpaceLift ships (individual units, NOT squadrons)

---

## Fog-of-War System

**Mandatory for AI (RBA and NNA)**

```nim
type FilteredGameState* = object
  viewingHouse*: HouseId
  ownColonies*: seq[Colony]              # Full details
  visibleSystems*: Table[SystemId, VisibleSystem]  # Limited view
  visibleFleets*: seq[VisibleFleet]      # If detected
```

**Visibility:** Owned > Occupied > Scouted > Adjacent > None

**Usage:** `let view = createFogOfWarView(gameState, houseId)`

---

## Pre-Commit Checklist

- [ ] Enums are `{.pure.}`
- [ ] No hardcoded values
- [ ] `nimble test` passes
- [ ] `nimble testBalanceQuick` (if AI/balance code)
- [ ] TODO.md updated (if milestone)
- [ ] Used nimble tasks (not direct commands)
- [ ] /docs root has ≤7 files
- [ ] Engine respects fog-of-war

---

## Current Status

**See TODO.md for full details**

✅ **Complete:** Engine (13 systems), 101+ tests, FoW integrated, Cipher Ledger timeline
🔄 **In Progress:** Phase 2 RBA enhancements (diagnostic-driven improvement)

**Test Coverage:** 101+ integration tests passing
