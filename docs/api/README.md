# EC4X Engine API Documentation

## Quick Links

- **[Engine Quick-Start Guide](ENGINE_QUICKSTART.md)** ⭐ **START HERE**
- **[RBA Quick-Start Guide](RBA_QUICKSTART.md)** - Testing & AI automation
- **[Analytics CLI Reference](ANALYTICS_CLI.md)** - Balance analysis tools
- [Full API Reference](engine/index.html) - Auto-generated from code
- [Development Context](../CLAUDE_CONTEXT.md) - Critical patterns & gotchas

## Documentation Structure

### 1. Quick-Start Guides

**[ENGINE_QUICKSTART.md](ENGINE_QUICKSTART.md)** - Essential patterns for engine development:
- Table copy semantics (get-modify-write pattern)
- RNG integration for deterministic resolution
- Combat system patterns
- Economy system patterns
- Logging and error handling
- RBA integration
- Definition of Done checklist

**[RBA_QUICKSTART.md](RBA_QUICKSTART.md)** - Rules-Based AI testing guide:
- Running balance simulations
- Interpreting test results
- AI profile configuration
- Balance analysis workflows
- Integration with analytics

**[ANALYTICS_CLI.md](ANALYTICS_CLI.md)** - Analytics CLI reference:
- Command reference
- Data export formats
- Statistical analysis
- Outlier detection
- Common workflows

### 2. Configuration References

**[RBA_CONFIG_REFERENCE.md](RBA_CONFIG_REFERENCE.md)** - RBA configuration:
- AI profiles and personalities
- Decision weights and priorities
- Rule configuration
- Custom profile creation

### 3. API Reference
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
1. Read **[RBA_QUICKSTART.md](RBA_QUICKSTART.md)** for testing basics
2. Study **[RBA_CONFIG_REFERENCE.md](RBA_CONFIG_REFERENCE.md)** for AI configuration
3. Use **[ANALYTICS_CLI.md](ANALYTICS_CLI.md)** for result analysis
4. Review `resolve.nim` for turn resolution flow
5. Check `gamestate.nim` for state queries

### For Balance Testing
1. Start with **[RBA_QUICKSTART.md](RBA_QUICKSTART.md)** for test workflows
2. Run `nimble testBalanceQuick` for quick validation
3. Use **[ANALYTICS_CLI.md](ANALYTICS_CLI.md)** for analysis
4. Export results with `python3 analysis/cli.py export-for-claude`
5. Follow Definition of Done checklist in ENGINE_QUICKSTART.md

### For Engine Development
1. Follow patterns in **[ENGINE_QUICKSTART.md](ENGINE_QUICKSTART.md)**
2. Use structured logging (`logger.nim`)
3. Apply get-modify-write for table changes
4. Pass RNG through resolution chain
5. Write back seq modifications to state
6. Run `nimble testBalanceQuick` before committing
7. Follow Definition of Done checklist

## Regenerating Documentation

Run the generation script to update API docs:
```bash
cd docs/api
./generate_docs.sh
```

This regenerates all HTML documentation from source code docstrings.

## Recent Improvements (Engine Audit 2025-11-27)

### Phase 1-2: Engine Audit
- ✅ Fixed table copy semantics throughout engine
- ✅ Added comprehensive logging system (340+ statements)
- ✅ Integrated deterministic RNG for replay
- ✅ Fixed squadron/battery destruction tracking
- ✅ Config integration with tech level modifiers
- ✅ Population growth persistence fix
- ✅ Fleet transport capacity validation

### Documentation Updates
- ✅ Created **[ENGINE_QUICKSTART.md](ENGINE_QUICKSTART.md)** with DoD checklist
- ✅ Created **[RBA_QUICKSTART.md](RBA_QUICKSTART.md)** for testing workflows
- ✅ Created **[RBA_CONFIG_REFERENCE.md](RBA_CONFIG_REFERENCE.md)** for AI configuration
- ✅ Created **[ANALYTICS_CLI.md](ANALYTICS_CLI.md)** for analysis tools
- ✅ Updated **[CLAUDE_CONTEXT.md](../CLAUDE_CONTEXT.md)** to reference docs (saves tokens!)

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
