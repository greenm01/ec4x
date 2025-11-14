# EC4X Data Directory

This directory contains game templates and runtime data.

## Structure

```
data/
├── templates/          # Template files for new games
│   └── game_config.toml.template
└── games/             # Runtime game directories (gitignored)
    └── (created by daemon/moderator)
```

## Templates

### game_config.toml.template

Template configuration file for new games. When creating a new game, copy this to your game directory as `game_config.toml` and customize:

```bash
cp data/templates/game_config.toml.template /path/to/game/game_config.toml
```

Or use the moderator tool:

```bash
./bin/moderator new <game-dir>
# Automatically creates game with template config
```

## Runtime Data

Game directories are created at runtime by the daemon or moderator and are **not committed to git**. Typical structure:

```
data/games/<game-id>/
├── game_config.toml        # Game-specific configuration
├── state.json              # Current game state
├── packets/                # Player order submissions
│   └── <house>.json
├── players/                # Player filtered views
│   └── <house>_view.json
├── archive/                # Turn history
│   └── turn_<n>/
└── maps/                   # Generated hex maps (if using hybrid tabletop)
    └── turn_<n>_<house>.pdf
```

Note: The actual game storage location is configurable in the daemon config (default: `/opt/ec4x/games/` for production).
