# EC4X Engine API Documentation

## Quick Links

- **[Engine Quick-Start Guide](ENGINE_QUICKSTART.md)** ⭐ **START HERE**
- [Full API Reference](engine/index.html) - Auto-generated from code
- [Development Context](../CLAUDE_CONTEXT.md) - Critical patterns & gotchas

## Documentation Structure

### 1. Quick-Start Guide
**[ENGINE_QUICKSTART.md](ENGINE_QUICKSTART.md)** - Essential patterns for engine development:
- Table copy semantics (get-modify-write pattern)
- RNG integration for deterministic resolution
- Combat system patterns
- Economy system patterns
- Logging and error handling

### 2. API Reference
**[engine/index.html](engine/index.html)** - Auto-generated API docs:
- `gamestate.nim` - Core game state types and queries
- `resolve.nim` - Turn resolution orchestrator
- `combat/` - Combat resolution system
- `economy/` - Economy and construction
- `squadron.nim`, `fleet.nim` - Military unit management

### 3. Architecture Documentation
**[../architecture/](../architecture/)** - System design docs:
- `engine_architecture.md` - Engine structure and data flow
- `resolution_pipeline.md` - Turn resolution phases
- `combat_system.md` - Combat mechanics

### 4. Specifications
**[../specs/](../specs/)** - Game mechanics specifications:
- `economy.md` - Economic system rules
- `operations.md` - Military operations
- `assets.md` - Unit types and stats
- `gameplay.md` - Core gameplay rules

## Getting Started

### For New Developers
1. Read **[ENGINE_QUICKSTART.md](ENGINE_QUICKSTART.md)** first
2. Review **[CLAUDE_CONTEXT.md](../CLAUDE_CONTEXT.md)** for critical patterns
3. Browse the API reference for specific modules
4. Check architecture docs for system design

### For RBA/AI Development
1. Study `resolve.nim` for turn resolution flow
2. Understand `gamestate.nim` queries for state access
3. Review economy system for production/tech
4. Check combat system for military operations

### For Engine Development
1. Follow patterns in ENGINE_QUICKSTART.md
2. Use structured logging (logger.nim)
3. Apply get-modify-write for table changes
4. Pass RNG through resolution chain
5. Write back seq modifications to state

## Regenerating Documentation

Run the generation script to update API docs:
```bash
cd docs/api
./generate_docs.sh
```

This regenerates all HTML documentation from source code docstrings.

## Recent Improvements (Engine Audit 2025-11-27)

- ✅ Fixed table copy semantics throughout engine
- ✅ Added comprehensive logging system
- ✅ Integrated deterministic RNG for replay
- ✅ Fixed squadron/battery destruction tracking
- ✅ Config integration with tech level modifiers
- ✅ Population growth persistence fix
- ✅ Created ENGINE_QUICKSTART guide
- ✅ Updated CLAUDE_CONTEXT to reference docs (saves tokens!)

See commit history for detailed changes.

## Why This Saves Tokens

Instead of repeating patterns in conversation:
- **Link to ENGINE_QUICKSTART.md** for detailed examples
- **Link to API docs** for type information
- **Keep CLAUDE_CONTEXT.md concise** with just quick references

This approach:
- Reduces token usage in context
- Keeps documentation updated in one place
- Makes patterns discoverable for human developers
- Provides authoritative reference for both AI and humans
