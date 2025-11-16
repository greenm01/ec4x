# Configuration System Design

## Philosophy

- **Defaults in data files, not code** - No hardcoded game stats
- **Admin-controlled** - No player mods, consistent rules per game
- **Optional overrides** - Use defaults unless admin wants customization
- **Simple layering** - Load defaults → apply game-specific overrides

## Structure

### Default Configuration Files (Shipped with Game)

```
ec4x/
├── data/
│   ├── ships_default.toml       # Ship classes and stats
│   ├── combat_default.toml      # Combat rules and modifiers
│   ├── economy_default.toml     # Production and costs
│   └── tech_default.toml        # Tech tree costs and effects
└── games/
    └── my_game/
        ├── game_config.toml     # Optional game-specific overrides
        ├── state.json
        └── orders/
```

### Default Files Format

**data/ships_default.toml:**
```toml
# EC4X Default Ship Stats
# Edit to change defaults for all games

[destroyer]
name = "Destroyer"
class = "DD"
attack_strength = 4
defense_strength = 3
command_cost = 2
command_rating = 3
tech_level = 0
build_cost = 200
upkeep_cost = 3
special_capability = ""

[cruiser]
name = "Cruiser"
class = "CR"
attack_strength = 6
defense_strength = 4
command_cost = 3
command_rating = 5
tech_level = 1
build_cost = 400
upkeep_cost = 5
special_capability = ""

[battlecruiser]
name = "Battlecruiser"
class = "BC"
attack_strength = 8
defense_strength = 5
command_cost = 4
command_rating = 7
tech_level = 2
build_cost = 600
upkeep_cost = 8
special_capability = ""

[battleship]
name = "Battleship"
class = "BS"
attack_strength = 10
defense_strength = 6
command_cost = 5
command_rating = 9
tech_level = 3
build_cost = 1000
upkeep_cost = 12
special_capability = ""

[dreadnought]
name = "Dreadnought"
class = "DN"
attack_strength = 15
defense_strength = 8
command_cost = 7
command_rating = 12
tech_level = 5
build_cost = 2000
upkeep_cost = 20
special_capability = ""

[scout]
name = "Scout"
class = "SC"
attack_strength = 1
defense_strength = 2
command_cost = 1
command_rating = 1
tech_level = 0
build_cost = 100
upkeep_cost = 2
special_capability = "ELI"

[raider]
name = "Raider"
class = "RR"
attack_strength = 4
defense_strength = 2
command_cost = 2
command_rating = 2
tech_level = 3
build_cost = 300
upkeep_cost = 5
special_capability = "CLK"

[fighter]
name = "Fighter Squadron"
class = "FS"
attack_strength = 1
defense_strength = 1
command_cost = 0
command_rating = 0
tech_level = 0
build_cost = 50
upkeep_cost = 1
special_capability = ""

[carrier]
name = "Carrier"
class = "CV"
attack_strength = 2
defense_strength = 4
command_cost = 4
command_rating = 6
tech_level = 2
build_cost = 800
upkeep_cost = 10
special_capability = "CAR3"

[supercarrier]
name = "Super Carrier"
class = "CX"
attack_strength = 3
defense_strength = 5
command_cost = 6
command_rating = 8
tech_level = 4
build_cost = 1500
upkeep_cost = 18
special_capability = "CAR5"

[starbase]
name = "Starbase"
class = "SB"
attack_strength = 12
defense_strength = 10
command_cost = 0
command_rating = 0
tech_level = 2
build_cost = 1200
upkeep_cost = 15
special_capability = "ELI+2"

[etac]
name = "ETAC"
class = "ETAC"
attack_strength = 0
defense_strength = 2
command_cost = 2
command_rating = 0
tech_level = 0
build_cost = 500
upkeep_cost = 5
special_capability = "COL"

[troop_transport]
name = "Troop Transport"
class = "TT"
attack_strength = 0
defense_strength = 3
command_cost = 2
command_rating = 0
tech_level = 0
build_cost = 400
upkeep_cost = 4
special_capability = "TRP"

[ground_battery]
name = "Ground Battery"
class = "GB"
attack_strength = 3
defense_strength = 2
command_cost = 0
command_rating = 0
tech_level = 0
build_cost = 100
upkeep_cost = 1
special_capability = ""

[planet_breaker]
name = "Planet-Breaker"
class = "PB"
attack_strength = 20
defense_strength = 6
command_cost = 8
command_rating = 10
tech_level = 7
build_cost = 5000
upkeep_cost = 50
special_capability = "SHP"
```

**data/combat_default.toml:**
```toml
[combat]
critical_hit_roll = 9           # Natural 9 = critical hit
retreat_after_round = 1          # Can retreat after round 1
starbase_critical_reroll = true  # Starbases reroll first critical
starbase_modifier = 2            # +2 die roll modifier

[cer_modifiers]
scouts = 1                       # +1 for scouts
surprise = 3                     # +3 first round (cloaked attack)
ambush = 4                       # +4 first round (cloaked defense)
```

**data/economy_default.toml:**
```toml
[economy]
starting_treasury = 1000
population_growth_rate = 0.02    # 2% natural growth
production_per_10_pop = 1        # 1 production per 10 population

[construction]
spaceport_turns = 1
spaceport_docks = 5
shipyard_turns = 2
shipyard_docks = 10
starbase_turns = 3
```

**data/tech_default.toml:**
```toml
[tech]
# Research cost formula: base * (level + 1)^2
research_cost_base = 1000

[fields]
ship_design = 0
weapons = 0
defense = 0
economics = 0
espionage = 0
```

## Game-Specific Overrides (Optional)

**games/my_game/game_config.toml:**
```toml
# Optional: Override defaults for this specific game
# If this file doesn't exist, uses data/*_default.toml

[ships.destroyer]
# Buff destroyers for this campaign
attack_strength = 5
build_cost = 180

[ships.raider]
# Make raiders cheaper but weaker
attack_strength = 3
build_cost = 250

[combat]
# More aggressive combat
critical_hit_roll = 8

# Can add completely new ship classes (future feature)
# [ships.super_dreadnought]
# attack_strength = 25
# ...
```

## Loading Algorithm

```nim
proc loadGameConfig*(gameDir: string): GameConfig =
  ## Layered config loading:
  ## 1. Load defaults from data/
  ## 2. Apply game-specific overrides if present

  var config = GameConfig()

  # Load all default files (required)
  config.ships = parseToml("data/ships_default.toml")
  config.combat = parseToml("data/combat_default.toml")
  config.economy = parseToml("data/economy_default.toml")
  config.tech = parseToml("data/tech_default.toml")

  # Apply game-specific overrides (optional)
  let overridePath = gameDir / "game_config.toml"
  if fileExists(overridePath):
    let overrides = parseToml(overridePath)
    config.applyOverrides(overrides)

  # Validate config
  let errors = config.validate()
  if errors.len > 0:
    raise newException(ConfigError, errors.join("\n"))

  return config
```

## Validation

```nim
proc validate*(config: GameConfig): seq[string] =
  ## Validate loaded configuration
  result = @[]

  for shipClass, stats in config.ships:
    if stats.attackStrength < 0:
      result.add(shipClass & ": attack_strength cannot be negative")

    if stats.defenseStrength <= 0:
      result.add(shipClass & ": defense_strength must be positive")

    if stats.commandCost < 0:
      result.add(shipClass & ": command_cost cannot be negative")

    if stats.buildCost <= 0:
      result.add(shipClass & ": build_cost must be positive")

  if config.combat.criticalHitRoll < 2 or config.combat.criticalHitRoll > 10:
    result.add("combat: critical_hit_roll must be 2-10")
```

## Moderator Commands

### View Current Config
```bash
$ moderator config my_game

Configuration for: my_game
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Ships:           data/ships_default.toml
Combat:          data/combat_default.toml
Economy:         data/economy_default.toml
Tech:            data/tech_default.toml

Overrides:       none

15 ship classes loaded
Combat: Standard rules (crit on 9)
Economy: 1000 starting treasury
```

### Validate Config
```bash
$ moderator config my_game --validate

✓ ships_default.toml: 15 classes loaded
✓ combat_default.toml: valid
✓ economy_default.toml: valid
✓ tech_default.toml: valid
✓ No overrides

Config valid!
```

### Export Current Config
```bash
# Export effective config (defaults + overrides merged)
$ moderator config my_game --export > my_game_config_snapshot.toml

# Useful for sharing game settings
```

## Implementation Timeline

### M2 (Current)
- ✅ Created `data/ships_default.toml`
- ✅ Implemented TOML parsing with std/parsecfg
- ✅ Replaced hardcoded `getShipStats()` with config loading
- ✅ Added caching for performance
- ✅ All 15 ship classes in config file

### M3 (Config Extensions)
- [ ] Support optional `game_config.toml` overrides
- [ ] Add validation with error messages
- [ ] Update `moderator new` to work with configs
- [ ] Add `moderator config` command
- [ ] Create additional config files (combat, economy, tech)

### M4 (Config Tools)
- [ ] Add `moderator config --validate`
- [ ] Add `moderator config --export`
- [ ] Better error messages for invalid configs
- [ ] Config documentation in help system

## Migration from M2

To generate default TOML files from M2 hardcoded values:

```nim
# One-time migration script
proc exportDefaultConfig*() =
  ## Generate data/ships_default.toml from hardcoded values

  var toml = """# EC4X Default Ship Stats
# Generated from M2 hardcoded values

"""

  for shipClass in ShipClass:
    let stats = getShipStats(shipClass, 0)
    toml.add(&"[{shipClass}]\n")
    toml.add(&"attack_strength = {stats.attackStrength}\n")
    toml.add(&"defense_strength = {stats.defenseStrength}\n")
    # ... etc
    toml.add("\n")

  writeFile("data/ships_default.toml", toml)
```

Run once:
```bash
$ moderator export-defaults
Generated data/ships_default.toml
Generated data/combat_default.toml
Generated data/economy_default.toml
Generated data/tech_default.toml
```

## Benefits

1. **No hardcoded values** - All stats in editable TOML files
2. **Easy to balance** - Edit text files, no recompilation
3. **Version controlled** - Track default changes over time
4. **Admin flexibility** - Override per-game without affecting defaults
5. **Simple** - No mod system complexity, just layered files
6. **Consistent** - All players see same config per game

## Non-Goals

- ❌ Player mods (too complex, breaks consistency)
- ❌ Multiple ruleset presets (can add later if needed)
- ❌ Hot reloading (just restart moderator)
- ❌ GUI config editor (text files are fine)

## Future Enhancements (Post-M4)

- Config diffs: `moderator config my_game --diff` shows what's overridden
- Ruleset presets: Multiple default sets to choose from
- Tech level modifiers: Stats scale with tech in config
- Formula support: `attack_strength = "base + tech * 2"` (stretch goal)
