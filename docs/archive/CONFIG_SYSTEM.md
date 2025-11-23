# EC4X Config File System

## Core Strategy

EC4X uses a **single source of truth** configuration system where TOML files define all game values. These same config files are used by:

1. **Documentation Generation**: `scripts/sync_specs.py` reads TOML and updates markdown specs
2. **Game Engine**: Loads TOML files directly for game rules

This ensures specifications and implementation never drift out of sync.

---

## Three Types of Configuration

### 1. Balance Variables (Tunable)

Values that **will change** during playtesting and balance adjustments:

```toml
# config/economy.toml
[population]
natural_growth_rate = 0.02         # BALANCE: Adjust if growth too slow/fast
ptu_growth_rate = 0.015            # BALANCE: Colony expansion rate

[construction]
ship_repair_cost_multiplier = 0.25 # BALANCE: 25% of PC to repair
```

**Examples:**
- Growth rates, tax bonuses/penalties
- Ship/facility costs (PC values)
- Shield effectiveness percentages
- Research breakthrough chances
- Blockade/invasion penalties

### 2. Core Mechanics (Fixed)

Fundamental game rules that define **how the game works**:

```toml
# config/economy.toml
[population]
ptu_to_souls = 50000               # MECHANIC: Scale constant (formula)
pu_to_ptu_conversion = 0.00657     # MECHANIC: Exponential formula constant

[planet_classes]
extreme_pu_min = 1                 # MECHANIC: Defines 7 planet types
extreme_pu_max = 20
desolate_pu_min = 21
# ...
```

**Examples:**
- Mathematical formula constants
- Type systems (planet classes, ship roles)
- Core game rules (fighters are planet-based, squadrons fight as units)

### 3. Game Setup (Per-Game)

Configuration set by the **game moderator** when creating a new game:

```toml
# game_setup/standard.toml
[starting_resources]
treasury = 1000                    # SETUP: What players start with
starting_population = 5

[victory_conditions]
prestige_threshold = 200           # SETUP: Win conditions

# game_setup/server.toml.template
[game]
turnDuration = 24                  # SETUP: Real-time hours per turn
```

**Examples:**
- Starting resources, tech levels, fleets
- Victory conditions, turn timers
- Server settings (IP, port)
- Map generation parameters

---

## How It Works

### Workflow Overview

```
┌─────────────────┐
│  config/*.toml  │  ← Game designer edits balance/mechanics
└────────┬────────┘
         │
         ├──────────────────────┐
         │                      │
         ▼                      ▼
  ┌──────────────┐      ┌──────────────┐
  │ sync_specs.py│      │ Game Engine  │
  │  (Python)    │      │   (Nim)      │
  └──────┬───────┘      └──────────────┘
         │
         ▼
  ┌──────────────┐
  │docs/specs/*.md│  ← Generated documentation
  └──────────────┘
```

### Example: Changing Growth Rate

**1. Edit config file:**
```toml
# config/economy.toml
[population]
natural_growth_rate = 0.03  # Changed from 0.02 to 0.03
```

**2. Run sync script:**
```bash
python3 scripts/sync_specs.py
```

**3. Result:**
- `docs/specs/economy.md` updates to show "3%" everywhere
- Game engine loads 0.03 from the same TOML file
- Docs and game stay in sync automatically

---

## File Organization

```
config/
├── economy.toml      # Balance variables + core mechanics
├── combat.toml       # Combat rules and modifiers
├── tech.toml         # Tech progression costs
└── ships.toml        # Unit stats

game_setup/
├── server.toml.template  # Server/hosting config
└── standard.toml         # Default game scenario

docs/specs/
├── economy.md        # Generated from config
├── operations.md     # Generated from config
└── reference.md      # Generated from config

scripts/
└── sync_specs.py     # Generates specs from config
```

---

## How Sync Works

### Tables

Tables in markdown specs are marked with HTML comments:

```markdown
<!-- SPACE_FORCE_TABLE_START -->
| Class | Name     | PC | AS | DS |
|-------|----------|----|----|-----|
| CT    | Corvette | 20 | 2  | 3   |
<!-- SPACE_FORCE_TABLE_END -->
```

The sync script:
1. Reads `config/ships.toml`
2. Generates a new table
3. Replaces content between the markers

### Inline Values

Inline values use markers that get replaced with plain text:

**Before sync (in git):**
```markdown
Growth rate is <!-- NATURAL_GROWTH -->2%<!-- /NATURAL_GROWTH --> per turn.
```

**After sync (visible output):**
```markdown
Growth rate is 2% per turn.
```

The markers exist in source control so the sync script knows what to replace, but the output is plain readable text.

---

## Best Practices

### DO:
✅ Always edit config files, never spec markdown directly
✅ Run `sync_specs.py` after every config change
✅ Commit config and spec files together
✅ Add comments to TOML: `# BALANCE:` or `# MECHANIC:`
✅ Test balance changes in-game before committing

### DON'T:
❌ Edit hardcoded numbers in markdown specs
❌ Commit config without syncing specs
❌ Change core mechanics without team discussion
❌ Mix scenario setup with balance variables
❌ Use magic numbers in engine code (always load from config)

---

## Distinguishing Config Types

Use clear comments in TOML files:

```toml
# ============================================================================
# POPULATION MECHANICS
# ============================================================================

[population]
# BALANCE VARIABLES - Tunable growth rates
natural_growth_rate = 0.02         # 2% natural birth rate per turn
growth_rate_per_starbase = 0.05    # +5% per starbase (max 3 starbases)

# GAME CONSTANTS - Mathematical formulas
ptu_to_souls = 50000               # One PTU ≈ 50k souls (scale constant)
pu_to_ptu_conversion = 0.00657     # PU to PTU conversion (exponential formula)
```

This helps developers know:
- What to adjust during balance testing (BALANCE)
- What should rarely/never change (MECHANIC/CONSTANT)

---

## Questions?

For issues or suggestions, file a GitHub issue or discuss in the development channel.

**Remember**: The config files ARE the single source of truth for both documentation and gameplay!
