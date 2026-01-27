# EC4X Development Tools

This directory contains utilities for EC4X development.

## clean_dev.nim

Automates the complete development workflow for quick iteration when making engine changes.

### Quick Start

**Full workflow (clean + create game + show invites):**
```bash
nim c -o:bin/clean_dev tools/clean_dev.nim  # Compile once
bin/clean_dev                                # Run workflow
```

Or use directly:
```bash
nim r tools/clean_dev.nim
```

### What It Does

1. Clears player cache (`~/.local/share/ec4x/cache.db`)
2. Clears all game data (`data/games/*`)
3. Clears all player data (`data/players/*`)
4. Creates a new game from scenario
5. Displays invite codes with relay URL

### Options

```bash
bin/clean_dev                        # Full workflow (default)
bin/clean_dev --clean                # Clean only, no game creation
bin/clean_dev --dry-run              # Preview what will be deleted
bin/clean_dev --scenario=my.kdl      # Use custom scenario
bin/clean_dev --cache                # Clear cache only
bin/clean_dev --data                 # Clear game/player data only
bin/clean_dev --logs                 # Also clear log files
bin/clean_dev --help                 # Show help
```

### Example Output

```
EC4X Development Workflow
===================================================

Cleaning everything...

✓ Deleted cache: /home/user/.local/share/ec4x/cache.db
✓ Deleted 2 item(s) from data/games
• Directory already empty: data/players

===================================================
Creating new game from scenarios/standard-4-player.kdl...
✓ Game created: nuns-jogger-gesture

Invite codes:
===================================================
Game: nuns-jogger-gesture (nuns-jogger-gesture)
Relay: localhost:8080

  Stratos (1): usher-odds@localhost:8080 [PENDING]
  Delos (2): segments-fidget@localhost:8080 [PENDING]
  Zenos (3): swept-sushi@localhost:8080 [PENDING]
  Thelon (4): dehydrate-bomb@localhost:8080 [PENDING]

Workflow complete! You can now start testing.
```

## api_docs.nim

Simple API documentation extractor (legacy tool).

---

**Tip:** Compile `clean_dev` once to `bin/clean_dev` for faster execution during development.
