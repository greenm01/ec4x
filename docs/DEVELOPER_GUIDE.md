# EC4X Developer Guide

## Configuration System Architecture

EC4X uses a **single source of truth** configuration system where TOML files define all game mechanics, balance values, and setup parameters. These same files are used by both:
- **Documentation Generation**: `scripts/sync_specs.py` updates markdown specs
- **Game Engine**: Loads TOML files directly for game rules

This ensures specifications and implementation never drift out of sync.

---

## File Organization

### Core Config Files (Game Designer)

Located in `config/`, these define game mechanics and balance:

```
config/
├── economy.toml      # Economic mechanics, costs, growth rates
├── combat.toml       # Combat rules, CER tables, damage mechanics
├── tech.toml         # Technology progression, research costs
├── ships.toml        # Ship stats (AS, DS, PC, MC, etc.)
├── ground_units.toml # Ground unit stats
├── facilities.toml   # Facility stats and costs
├── prestige.toml     # Prestige sources and penalties
└── espionage.toml    # Espionage mechanics and costs
```

**Contents:**
- **Balance Variables**: Tunable parameters for playtesting (growth rates, costs, modifiers)
- **Core Mechanics**: Fundamental rules (mathematical formulas, type systems)

### Game Setup Files (Game Moderator)

Located in `game_setup/`, these define how to run and configure games:

```
game_setup/
├── server.toml.template  # Server/hosting settings (IP, port, turn duration)
├── standard.toml                # Default balanced 4-player game
├── quick_game.toml              # Fast 2-hour game (example)
└── epic_campaign.toml           # Long strategic game (example)
```

**Server Config (`server.toml.template`):**
- Server IP, port, hosting settings
- Turn duration (real-time hours)
- Chat, notifications, save settings
- Server administration

**Scenario Files (`*.toml`):**
- Starting resources (treasury, population)
- Starting tech levels
- Starting units and facilities
- Victory conditions (game mechanics)
- Map settings (systems, jump lanes)
- Optional balance overrides

### Specification Documents

Located in `docs/specs/`, these are **generated** from config files:

```
docs/specs/
├── reference.md     # Tables: ships, ground units, prestige
├── diplomacy.md     # Diplomacy, espionage, CIC
├── economy.md       # Economics, research, construction
└── operations.md    # Movement, combat, orders
```

**Important**: Never edit hardcoded values in specs manually! Always update the config files and run sync.

---

## Configuration Categories

### 1. Balance Variables (Tune During Playtesting)

These values are **expected to change** during game balance testing:

**Economic:**
- Growth rates: `natural_growth_rate = 0.02`
- Tax penalties/bonuses
- Research breakthrough chances
- IU investment costs
- Colonization costs

**Combat:**
- Shield effectiveness percentages
- Bombardment max rounds
- Blockade penalties

**Tech:**
- Research costs (ERP, SRP, TRP formulas)
- Tech level progression costs

**Example:**
```toml
[population]
natural_growth_rate = 0.02         # BALANCE: Adjust if growth too slow/fast
ptu_growth_rate = 0.015            # BALANCE: Colony expansion rate
```

### 2. Core Mechanics (Rarely/Never Change)

These define **how the game works** fundamentally:

**Mathematical Constants:**
- `pu_to_ptu_conversion = 0.00657` - Exponential formula constant
- `ptu_to_souls = 50000` - Scale constant

**Type Systems:**
- Planet class PU ranges (defines 7 planet types)
- Ship classes and roles

**Game Rules:**
- `fighter_squadron_planet_based = true` - Design decision
- `squadron_fights_as_unit = true` - Combat rule

**Example:**
```toml
[population]
# CORE MECHANIC: Mathematical formula (don't change)
pu_to_ptu_conversion = 0.00657     # Exponential conversion constant
```

### 3. Game Setup (Per-Game Configuration)

These are set by the **game moderator** when creating a new game:

**Server Config (`game_setup/server_config.toml`):**
```toml
[game]
serverIp = "127.0.0.1"
port = "8080"
turnDuration = 24           # Real-time hours per turn
```

**Scenario Config (`game_setup/standard.toml`):**
```toml
[starting_resources]
treasury = 1000
starting_population = 5

[victory_conditions]
primary_condition = "conquest"
prestige_threshold = 200
```

---

## Updating Game Balance

### Step 1: Identify the Value

Find which config file contains the value you want to change:
- Economic mechanics → `config/economy.toml`
- Combat mechanics → `config/combat.toml`
- Unit stats → `config/ships.toml` or `config/ground_units.toml`
- Tech progression → `config/tech.toml`

### Step 2: Edit the Config

Edit the TOML value:

```toml
# Before
natural_growth_rate = 0.02         # 2% per turn

# After (for faster growth testing)
natural_growth_rate = 0.03         # 3% per turn
```

### Step 3: Sync Specifications

Run the sync script to update all spec documents:

```bash
python3 scripts/sync_specs.py
```

This updates:
- All tables in specs (ship stats, tech costs, etc.)
- All inline values in prose (percentages, multipliers, etc.)

### Step 4: Verify Changes

Check the updated specs:

```bash
git diff docs/specs/economy.md
```

You should see the value changed everywhere it appears.

### Step 5: Test in Engine

The game engine loads the same TOML files, so your changes are automatically live. Test gameplay with the new values.

### Step 6: Commit

```bash
git add config/economy.toml docs/specs/
git commit -m "Balance: Increase population growth rate to 3%"
```

---

## How Sync Works

### Tables

Tables use HTML comment markers for replacement:

```markdown
<!-- SPACE_FORCE_TABLE_START -->
| Class | Name     | PC | AS | DS |
|-------|----------|----|----|-----|
| CT    | Corvette | 20 | 2  | 3   |
...
<!-- SPACE_FORCE_TABLE_END -->
```

The sync script:
1. Reads `config/ships.toml`
2. Generates a new table
3. Replaces content between markers
4. Adds source reference footer

### Inline Values

Inline values also use markers, but they're **removed** in the final output:

**Source markdown (before sync):**
```markdown
Growth rate is <!-- NATURAL_GROWTH -->2%<!-- /NATURAL_GROWTH --> per turn.
```

**After sync:**
```markdown
Growth rate is 2% per turn.
```

The markers exist in git history but are replaced with plain text in the output.

### Script Flow

```python
# 1. Load all config files
economy_config = load_toml("config/economy.toml")
combat_config = load_toml("config/combat.toml")
# ...

# 2. Generate tables from config
ships_table = generate_space_force_table(ships_config)
shield_table = generate_shield_effectiveness_table(combat_config)
# ...

# 3. Update each spec file
update_economy_spec(tables, economy_config)
update_operations_spec(tables, economy_config, combat_config)
# ...
```

---

## Adding New Config Values

### 1. Add to Config File

Add the value to the appropriate TOML file:

```toml
[research]
research_breakthrough_base_chance = 0.10
new_breakthrough_bonus = 5         # NEW VALUE
```

### 2. Add to Spec with Markers

In the spec file, add markers around the value:

```markdown
Players receive <!-- BREAKTHROUGH_BONUS -->5<!-- /BREAKTHROUGH_BONUS --> bonus points.
```

### 3. Update Sync Script

Add the value to the replacements dictionary in `scripts/sync_specs.py`:

```python
def replace_inline_values(content: str, economy_config: Dict[str, Any]) -> str:
    replacements = {
        'BREAKTHROUGH_BONUS': lambda: str(economy_config['research']['new_breakthrough_bonus']),
        # ... other replacements
    }
```

### 4. Run Sync

```bash
python3 scripts/sync_specs.py
```

The value is now synced between config and specs!

---

## Creating New Games

### Option 1: Copy Templates

```bash
# Copy server config
cp game_setup/server.toml.template game_setup/my_server.toml

# Copy scenario
cp game_setup/standard.toml game_setup/my_scenario.toml
```

Edit values as needed for your custom game.

### Option 2: UI Tool (Future)

A moderator UI tool will:
1. Load `game_setup/standard.toml` as defaults
2. Present editable fields for both server and scenario
3. Validate inputs
4. Save to `game_setup/my_game.toml` and `game_setup/my_server.toml`

### Option 3: Programmatic

```python
import tomllib

# Load and modify scenario
with open('game_setup/standard.toml', 'rb') as f:
    scenario = tomllib.load(f)

scenario['starting_resources']['treasury'] = 2000
scenario['game_info']['name'] = "Rich Start Game"

# Save
with open('game_setup/rich_start.toml', 'w') as f:
    toml.dump(scenario, f)
```

---

## Engine Integration

### Loading Configs

The game engine should load configs in this order:

```python
import tomllib
from pathlib import Path

def load_game_config(scenario_name: str):
    config_dir = Path("config")

    # 1. Load core mechanics and balance
    economy = load_toml(config_dir / "economy.toml")
    combat = load_toml(config_dir / "combat.toml")
    tech = load_toml(config_dir / "tech.toml")
    ships = load_toml(config_dir / "ships.toml")
    # ... load all config files

    # 2. Load scenario
    scenario = load_toml(Path(f"game_setup/{scenario_name}.toml"))

    # 3. Apply optional balance overrides from scenario
    if 'optional_balance_overrides' in scenario:
        for key, value in scenario['optional_balance_overrides'].items():
            # Override specific balance values for this game
            economy[section][key] = value

    return {
        'economy': economy,
        'combat': combat,
        'scenario': scenario,
        # ...
    }
```

### Using Config Values

```python
# Example: Calculate population growth
growth_rate = config['economy']['population']['natural_growth_rate']
new_population = current_population * (1 + growth_rate)

# Example: Check ship stats
ship_as = config['ships']['corvette']['attack_strength']
ship_pc = config['ships']['corvette']['production_cost']
```

---

## Best Practices

### DO:
✅ Always edit config files, never spec markdown directly
✅ Run `sync_specs.py` after every config change
✅ Commit config and spec files together
✅ Use clear variable names in TOML
✅ Add comments explaining balance values
✅ Test balance changes in-game before committing

### DON'T:
❌ Edit hardcoded numbers in markdown specs
❌ Commit config without syncing specs
❌ Change core mechanics without team discussion
❌ Add scenario-specific values to core config files
❌ Use magic numbers in engine code (always load from config)

---

## Common Tasks

### Change a ship's stats

```bash
# 1. Edit config/ships.toml
vim config/ships.toml  # Change corvette PC from 20 to 25

# 2. Sync
python3 scripts/sync_specs.py

# 3. Verify
git diff docs/specs/reference.md  # Should show PC: 25

# 4. Commit
git add config/ships.toml docs/specs/reference.md
git commit -m "Balance: Increase Corvette cost to 25 PP"
```

### Add a new tech level

```bash
# 1. Add to config/tech.toml
[weapons_tech]
level_6_sl = 6
level_6_trp = 50

# 2. Sync (automatically picks up new level)
python3 scripts/sync_specs.py

# 3. Spec now shows WEP6 row in table
```

### Create a tournament scenario

```bash
# 1. Copy template
cp scenarios/standard.toml scenarios/tournament_2025.toml

# 2. Edit for tournament rules
vim scenarios/tournament_2025.toml

# 3. Players select this scenario when starting game
```

---

## Troubleshooting

### "Markers not found" warning

The sync script reports missing markers:
```
⚠ Shield effectiveness table markers not found in operations.md
```

**Fix:** Add markers to the spec file:
```markdown
<!-- SHIELD_EFFECTIVENESS_TABLE_START -->
... table content ...
<!-- SHIELD_EFFECTIVENESS_TABLE_END -->
```

### Values not updating

If values don't change after sync:

1. Check marker names match exactly
2. Verify config path is correct in sync script
3. Check the replacement dictionary has the marker
4. Ensure sync script has no errors

### Sync script errors

```bash
# Run with full output to see errors
python3 scripts/sync_specs.py 2>&1 | less
```

Common issues:
- Missing config file
- Malformed TOML syntax
- Wrong config key path

---

## File Conventions

### Naming

- Config files: `lowercase_with_underscores.toml`
- Scenario files: `descriptive_name.toml`
- Spec files: `lowercase.md`

### TOML Structure

```toml
# Use section headers
[section_name]

# Group related values
natural_growth_rate = 0.02
growth_rate_per_starbase = 0.05

# Use comments liberally
blockade_penalty = 0.60  # 60% GCO reduction (BALANCE)

# Use descriptive key names
research_breakthrough_base_chance = 0.10  # Not: rb_chance
```

### Comments

Mark values as BALANCE or CORE:

```toml
# BALANCE: Tunable parameter
natural_growth_rate = 0.02

# CORE: Mathematical constant (don't change)
pu_to_ptu_conversion = 0.00657
```

---

## Future Enhancements

### Scenario Builder UI

A web-based tool for moderators:
- Load scenario template
- Edit in form fields with validation
- Preview impact on game balance
- Export to TOML file

### Balance Analyzer

Tooling to analyze config values:
- Show economic curves (growth rates, costs)
- Calculate early/mid/late game power levels
- Compare scenarios
- Suggest balanced starting conditions

### Version Control

Track balance changes over time:
- Git tags for major balance patches
- Changelog generation from config diffs
- Rollback to previous balance versions

---

## Questions?

For issues or suggestions, file a GitHub issue or discuss in the development channel.

Remember: **The config files ARE the game design document.** Keep them clean, documented, and synchronized!
