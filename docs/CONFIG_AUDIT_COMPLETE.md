# EC4X Config Extraction - Complete Audit Report

**Date:** 2025-11-21
**Status:** ✅ COMPLETE - All specs audited and synced

---

## Summary

All game setup values, balance variables, and core mechanics from specification documents have been extracted to TOML config files and are being synced via `scripts/sync_specs.py`.

---

## Config Files (13 total)

### Core Mechanics & Balance
1. **`config/economy.toml`** (278 lines)
   - Population mechanics, growth rates
   - Production, research, tax systems
   - Colonization costs, material efficiency

2. **`config/construction.toml`** (81 lines)
   - Construction times, costs, repair
   - Facility costs and upkeep
   - Build capacity modifiers

3. **`config/military.toml`** (27 lines)
   - Fighter squadron limits and capacity
   - Salvage values
   - Squadron mechanics

4. **`config/combat.toml`** (~150 lines)
   - Combat resolution rules
   - Blockade and invasion mechanics
   - Shield effectiveness
   - Morale system

5. **`config/tech.toml`** (~200 lines)
   - Tech progression costs (EL, SL, CST, WEP, TER, ELI, CLK, SLD, CIC, FD, ACO)
   - Research breakthrough mechanics
   - Terraforming costs

6. **`config/prestige.toml`** (135 lines)
   - All prestige gain/loss values
   - Morale thresholds
   - Penalty mechanics
   - Victory conditions

7. **`config/diplomacy.toml`** (67 lines)
   - Non-Aggression Pact violation penalties
   - Dishonored status duration (3 turns)
   - Diplomatic isolation (5 turns)
   - Pact reinstatement cooldown (5 turns)
   - Repeat violation window (10 turns)
   - Espionage effect durations

8. **`config/espionage.toml`** (169 lines)
   - EBP/CIP costs and effects
   - Detection thresholds and modifiers
   - Scout/Raider detection tables (5×5 matrices)
   - Mesh network modifiers
   - Starbase bonuses

9. **`config/gameplay.toml`** (47 lines)
   - Defensive Collapse threshold (3 consecutive turns below 0 prestige)
   - MIA Autopilot activation (3 missed turns)
   - Autopilot/Defensive Collapse behaviors
   - Victory condition rules

### Unit Statistics
10. **`config/ships.toml`** (~400 lines)
    - All 17 ship classes with stats (PC, AS, DS, HP, SR, MR, TL, SO, CC)

11. **`config/ground_units.toml`** (~100 lines)
    - All 4 ground unit types (Marines, Mech Infantry, Armor, Planetary Assault)

12. **`config/facilities.toml`** (~50 lines)
    - Spaceport and Shipyard stats

### Game Setup
13. **`game_setup/standard.toml`** (67 lines)
    - Starting resources (420 PP, 50 prestige, 50% tax)
    - Starting fleet (1 ETAC, 1 LC, 2 DD, 2 SC)
    - Starting facilities (1 Spaceport, 1 Shipyard)
    - Homeworld (Abundant Eden, Level V, 840 PU)
    - Starting tech (EL1, SL1, CST1, WEP1, TER1, ELI1, CIC1)
    - Victory conditions
    - Map generation

---

## Specification Files - Sync Status

### ✅ Fully Synced Files

| Spec File | Inline Values | Tables | Status |
|-----------|---------------|--------|--------|
| `gameplay.md` | 21 markers | None | ✅ Complete |
| `economy.md` | 30+ markers | 13 tables | ✅ Complete |
| `operations.md` | 5 markers | 1 table | ✅ Complete |
| `diplomacy.md` | 13 markers | 3 tables | ✅ Complete |
| `assets.md` | 11 markers | 2 tables | ✅ Complete |
| `reference.md` | None | 7 tables | ✅ Complete |

### 📖 Documentation Only (No Config Values)
- `glossary.md` - Definitions only
- `index.md` - Navigation only

---

## Inline Value Markers

Total markers across all specs: **80+ inline values**

### Example Marker Usage:
```markdown
<!-- Before sync (in git) -->
Growth rate is <!-- NATURAL_GROWTH_RATE -->2%<!-- /NATURAL_GROWTH_RATE --> per turn.

<!-- After sync (visible output) -->
Growth rate is 2% per turn.
```

Markers remain in source for sync script, but output is plain text.

---

## Table Generation

Total generated tables: **26 tables**

### Tables by Spec:
- **reference.md**: 7 tables (ships, ground units, spacelift, prestige, morale, espionage, penalties)
- **economy.md**: 13 tables (RAW materials, tax, IU, colonization, maintenance, all tech trees)
- **diplomacy.md**: 3 tables (espionage prestige, CIC modifiers, CIC thresholds)
- **operations.md**: 1 table (shield effectiveness)
- **assets.md**: 2 tables (spy detection 5×5, raider detection 5×5)

---

## Sync Script Analysis

### `scripts/sync_specs.py` - 1,625 lines

**Functions:**
- `load_toml()` - Parse TOML files
- `generate_*_table()` - 26 table generation functions
- `replace_inline_values_*()` - 5 inline replacement functions
- `update_*_spec()` - 5 spec update functions
- `main()` - Orchestrates full sync

**Loaded Configs:** All 13 config files

**Updated Specs:** All 6 gameplay specs

**Workflow:**
1. Load all 13 TOML files
2. Generate 26 markdown tables from config data
3. Replace 80+ inline markers with plain text values
4. Write updated specs to docs/specs/

**Runtime:** ~2-3 seconds for full sync

---

## Missing Values Analysis

### ❌ Known Intentionally Excluded

These are **CORE MECHANICS** (hardcoded game rules, not tunable):
- Turn phase order (Conflict → Income → Command → Maintenance)
- Fog of war rules
- Intelligence gathering mechanics
- ROE (Rules of Engagement) definitions
- Fleet order type codes
- Diplomatic status types (Neutral, Enemy, Non-Aggression)

These define **HOW** the game works, not **balance values** that need tuning.

---

## Validation Checklist

✅ All numeric costs (PP, PC) are in config
✅ All percentages are in config
✅ All turn durations are in config
✅ All tech progression values are in config
✅ All prestige values are in config
✅ All detection mechanics are in config
✅ All starting resources are in config
✅ All table data is generated from config
✅ Sync script loads all config files
✅ Sync script updates all relevant specs
✅ Markers exist for all config values that appear in prose

---

## For Engine Implementation

The Nim engine should load these config files in this order:

1. **Game Setup** (per-game settings):
   ```nim
   let gameSetup = loadToml("game_setup/standard.toml")
   ```

2. **Core Mechanics** (game rules):
   ```nim
   let ships = loadToml("config/ships.toml")
   let groundUnits = loadToml("config/ground_units.toml")
   let facilities = loadToml("config/facilities.toml")
   let economy = loadToml("config/economy.toml")
   let construction = loadToml("config/construction.toml")
   let military = loadToml("config/military.toml")
   let combat = loadToml("config/combat.toml")
   let tech = loadToml("config/tech.toml")
   let prestige = loadToml("config/prestige.toml")
   let diplomacy = loadToml("config/diplomacy.toml")
   let espionage = loadToml("config/espionage.toml")
   let gameplay = loadToml("config/gameplay.toml")
   ```

All engine calculations should reference these config values, never hardcode numbers.

---

## Testing Workflow

1. **Designer edits config value:**
   ```bash
   vim config/economy.toml  # Change natural_growth_rate = 0.03
   ```

2. **Run sync script:**
   ```bash
   python3 scripts/sync_specs.py
   ```

3. **Verify specs updated:**
   ```bash
   grep "3%" docs/specs/economy.md  # Should show 3% instead of 2%
   ```

4. **Commit together:**
   ```bash
   git add config/economy.toml docs/specs/economy.md
   git commit -m "Increase growth rate to 3%"
   ```

5. **Engine auto-loads new value** (no recompile for Nim, just restart game)

---

## Audit Completion Notes

- **Total config extraction time**: 4 conversation sessions
- **Files audited**: 8 specification files
- **Config files created**: 9 new + 4 existing = 13 total
- **Inline markers added**: 80+
- **Table generators created**: 26
- **Sync functions created**: 10
- **Test scripts created**: 2 (Python + Nim)

### Recent Additions (Final Audit):
- Added 4 diplomacy.md markers (dishonored turns, isolation, pact reinstatement, repeat window)
- Added 1 assets.md marker (capacity grace period)
- Updated sync_specs.py to handle these values
- Verified all values sync correctly

**Status**: Ready for Nim engine integration. All game values are now in config files and documented via sync.

---

## Next Steps for Nim Integration

1. ✅ **Config files exist and are complete**
2. ✅ **Documentation syncs from config**
3. ⏭️ **Update Nim config loaders** to read all 13 files
4. ⏭️ **Replace magic numbers in Nim engine** with config references
5. ⏭️ **Add config validation** in Nim (ensure required keys exist)
6. ⏭️ **Test end-to-end** - edit config, sync docs, run engine

The config system is complete and ready for engine integration!
