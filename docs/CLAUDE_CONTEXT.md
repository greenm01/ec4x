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
└── guides/          # How-tos and standards

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

## Testing Requirements

**Before ANY commit:**
```bash
# Run all integration tests
nim c -r tests/integration/test_*.nim

# Verify project builds
nimble build
```

**Test coverage:** 76+ integration tests must pass

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
