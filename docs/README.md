# EC4X Documentation

**Project:** EC4X - Turn-based 4X Space Strategy Game
**Language:** Nim
**Status:** Core Engine Development

---

## 📚 Documentation Structure

### Getting Started

- **[CLAUDE_CONTEXT.md](CLAUDE_CONTEXT.md)** - Essential session context (load at session start)
- **[STYLE_GUIDE.md](STYLE_GUIDE.md)** - NEP-1 code standards and conventions
- **[STATUS.md](STATUS.md)** - Current implementation status

### Game Specifications

Located in `specs/`:
- **[reference.md](specs/reference.md)** - Complete game mechanics reference
- **[gameplay.md](specs/gameplay.md)** - Gameplay overview
- **[economy.md](specs/economy.md)** - Economic system
- **[diplomacy.md](specs/diplomacy.md)** - Diplomatic mechanics
- **[operations.md](specs/operations.md)** - Fleet operations
- **[assets.md](specs/assets.md)** - Game assets
- **[glossary.md](specs/glossary.md)** - Game terminology
- **[index.md](specs/index.md)** - Specification index

### Technical Architecture

Located in `architecture/`:
- **[overview.md](architecture/overview.md)** - System architecture overview
- **[combat-engine.md](architecture/combat-engine.md)** - Combat system design
- **[dataflow.md](architecture/dataflow.md)** - Data flow diagrams
- **[transport.md](architecture/transport.md)** - Network transport layer
- **[storage.md](architecture/storage.md)** - Data persistence
- **[daemon.md](architecture/daemon.md)** - Server daemon architecture
- **[intel.md](architecture/intel.md)** - Intelligence system
- **[tea-implementation.md](architecture/tea-implementation.md)** - TEA implementation

### Implementation Guides

Located in `guides/`:
- **[IMPLEMENTATION_ROADMAP.md](guides/IMPLEMENTATION_ROADMAP.md)** - Development roadmap
- **[INCREMENTAL_ROADMAP.md](guides/INCREMENTAL_ROADMAP.md)** - Incremental development plan
- **[AI_CONTINUATION_GUIDE.md](guides/AI_CONTINUATION_GUIDE.md)** - Guide for AI-assisted development
- **[IMPLEMENTATION_PROGRESS.md](guides/IMPLEMENTATION_PROGRESS.md)** - Progress tracking
- **[PRESTIGE_INTEGRATION_PLAN.md](guides/PRESTIGE_INTEGRATION_PLAN.md)** - Prestige system integration plan

### Milestone Reports

Located in `milestones/`:
- **[PRESTIGE_IMPLEMENTATION_COMPLETE.md](milestones/PRESTIGE_IMPLEMENTATION_COMPLETE.md)** - Prestige system completion
- **[ESPIONAGE_COMPLETE.md](milestones/ESPIONAGE_COMPLETE.md)** - Espionage system completion
- **[TURN_RESOLUTION_COMPLETE.md](milestones/TURN_RESOLUTION_COMPLETE.md)** - Turn resolution integration
- **[M5_PHASE_B_COMPLETION_REPORT.md](milestones/M5_PHASE_B_COMPLETION_REPORT.md)** - Milestone 5 Phase B
- **[M5_BALANCE_FINDINGS.md](milestones/M5_BALANCE_FINDINGS.md)** - Balance testing results

### Design Documents

Located in `design/`:
- **[CONFIG_SYSTEM.md](design/CONFIG_SYSTEM.md)** - Configuration system design
- **[FLEET_MANAGEMENT_TUI.md](design/FLEET_MANAGEMENT_TUI.md)** - Fleet management UI
- **[FLEET_TUI_QUICKREF.md](design/FLEET_TUI_QUICKREF.md)** - Fleet UI quick reference
- **[FLEET_MANAGEMENT_SUMMARY.md](design/FLEET_MANAGEMENT_SUMMARY.md)** - Fleet management summary

### Deployment

- **[EC4X-Deployment.md](EC4X-Deployment.md)** - Deployment guide
- **[EC4X-VPS-Deployment.md](EC4X-VPS-Deployment.md)** - VPS deployment
- **[EC4X-Nostr-Implementation.md](EC4X-Nostr-Implementation.md)** - Nostr integration
- **[EC4X-Nostr-Events.md](EC4X-Nostr-Events.md)** - Nostr event specification

### Archive

Located in `archive/`:
- Historical documents and deprecated specifications
- Old project structure documentation
- Migration guides

---

## 🚀 Quick Start for AI Sessions

**At the start of EVERY Claude Code session, load:**

```
@docs/STYLE_GUIDE.md
@docs/STATUS.md
```

This ensures:
- NEP-1 conventions are followed
- Pure enum requirement is enforced
- Current implementation status is known
- TOML configuration pattern is used

---

## 📋 Key Project Rules

1. **All enums MUST be `{.pure.}`**
2. **No hardcoded game balance values** - use TOML config files
3. **Follow NEP-1 Nim conventions** - see STYLE_GUIDE.md
4. **Update STATUS.md** after completing milestones
5. **Run tests before committing** - all tests must pass

---

## 🧪 Testing

**Test Coverage:** 76+ integration tests passing

**Test Structure:**
```
tests/
├── unit/            # Unit tests for individual modules
├── integration/     # Integration tests for system interactions
├── balance/         # Balance testing and validation
└── scenarios/       # Complex gameplay scenarios
```

**Run Tests:**
```bash
# All integration tests
nim c -r tests/integration/test_*.nim

# Specific test suite
nim c -r tests/integration/test_espionage.nim

# Verify build
nimble build
```

---

## 🔧 Configuration System

**Location:** `config/`

All game balance values are externalized to TOML configuration files:
- `prestige.toml` - Prestige event values
- `espionage.toml` - Espionage costs, effects, detection

**Pattern:**
```nim
let config = globalPrestigeConfig  # Auto-loads from TOML
result.prestige = config.techAdvancement  # NOT hardcoded
```

---

## 📊 Implementation Status

**✅ Complete Systems:**
- Combat (space, ground, starbase)
- Research (6 tech levels)
- Economy (production, income, construction)
- Prestige (18 sources)
- Espionage (7 actions, CIC system)
- Diplomacy (pacts, violations)
- Colonization (prestige integration)
- Victory Conditions (3 types)
- Morale (7 levels)
- Turn Resolution (4 phases)
- Fleet Management
- Star Map

**🚧 Incomplete Systems:**
- Blockade mechanics
- Espionage order execution
- Diplomatic action orders
- UI (deferred)
- AI (deferred)

See [STATUS.md](STATUS.md) for detailed status.

---

## 🎯 Project Goals

**Current Phase:** Code health and documentation cleanup

**Near-Term Goals:**
- Enforce NEP-1 conventions (pure enums, camelCase constants)
- Migrate all game values to TOML configs
- Create spec-code sync tooling
- Implement remaining order systems

**Long-Term Goals:**
- Complete core engine with all game systems
- Comprehensive balance testing
- TUI interface (Terminal UI)
- AI opponent implementation
- Multiplayer server infrastructure

---

## 📝 Contributing

**Code Standards:**
- Follow [STYLE_GUIDE.md](STYLE_GUIDE.md)
- All enums `{.pure.}`
- TOML configs for game values
- NEP-1 naming conventions

**Development Workflow:**
1. Load session context (`@docs/STYLE_GUIDE.md`, `@docs/STATUS.md`)
2. Make changes following style guide
3. Run tests (`nim c -r tests/integration/test_*.nim`)
4. Update STATUS.md if milestone complete
5. Commit with descriptive message
6. Push to main branch

---

## 📖 Additional Resources

- [Nim Language](https://nim-lang.org/)
- [NEP-1 Style Guide](https://nim-lang.org/docs/nep1.html)
- [Nim Manual](https://nim-lang.org/docs/manual.html)

---

**Last Updated:** 2025-11-21
**Maintained By:** Claude Code + Human Developer
