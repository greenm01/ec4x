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
- **[overview.md](architecture/overview.md)** - System architecture overview (Updated 2025-11-26: AI & QoL systems)
- **[combat-engine.md](architecture/combat-engine.md)** - Combat system design
- **[dataflow.md](architecture/dataflow.md)** - Data flow diagrams
- **[transport.md](architecture/transport.md)** - Network transport layer
- **[storage.md](architecture/storage.md)** - Data persistence
- **[daemon.md](architecture/daemon.md)** - Server daemon architecture
- **[intel.md](architecture/intel.md)** - Intelligence system
- **[standing-orders.md](architecture/standing-orders.md)** - Standing orders specification
- **[tea-implementation.md](architecture/tea-implementation.md)** - TEA implementation

### AI & Balance Testing

Located in `ai/`:
- **[README.md](ai/README.md)** - AI analysis overview (Updated 2025-11-26: QoL integration)
- **[QOL_INTEGRATION_STATUS.md](ai/QOL_INTEGRATION_STATUS.md)** - RBA QoL integration status
- **[RBA_OPTIMIZATION_GUIDE.md](ai/RBA_OPTIMIZATION_GUIDE.md)** - AI optimization guide
- **[TOKEN_EFFICIENT_WORKFLOW.md](ai/TOKEN_EFFICIENT_WORKFLOW.md)** - Data analysis workflow
- **[ARCHITECTURE.md](ai/ARCHITECTURE.md)** - RBA architecture details
- **[DECISION_FRAMEWORK.md](ai/DECISION_FRAMEWORK.md)** - 4-act decision framework

Located in `testing/`:
- **[BALANCE_TESTING_2025-11-26.md](testing/BALANCE_TESTING_2025-11-26.md)** - Latest balance test report
- **[BALANCE_METHODOLOGY.md](testing/BALANCE_METHODOLOGY.md)** - Testing methodology

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

**✅ AI & QoL Systems (2025-11-26):**
- Rule-Based AI (RBA) with 9 modules
- Budget tracking (0% overspending)
- Standing orders (8 types)
- Fleet validation (100% security)

**🔴 Known Issues (2025-11-26):**
- Espionage system not executing (0% usage)
- Scout production not triggering (0 scouts)
- Mothballing logic not activating (0% usage)
- Resource hoarding (55% games affected)

See:
- [Known Issues](KNOWN_ISSUES.md) for bug details
- [Open Issues](OPEN_ISSUES.md) for investigation tasks
- [QoL Roadmap](QOL_FEATURES_ROADMAP.md) for feature status
- [Balance Testing Report](testing/BALANCE_TESTING_2025-11-26.md) for test results

**🚧 Incomplete Systems:**
- Blockade mechanics
- Diplomatic action orders
- UI (deferred)

---

## 🎯 Project Goals

**Current Phase:** AI subsystem debugging and QoL refinement

**Immediate Goals (Week 1):**
- Debug espionage system integration
- Fix scout production logic
- Fix mothballing system
- Investigate resource hoarding patterns
- Run balance testing round 2

**Near-Term Goals (Month 1):**
- Complete AI subsystem integration
- Achieve >80% espionage usage
- Achieve 5-7 scouts per house
- Movement range calculator (QoL)
- Construction queue preview (QoL)

**Long-Term Goals:**
- Complete diplomacy AI integration
- TUI interface (Terminal UI)
- Multiplayer server infrastructure
- Advanced standing orders (conditional triggers)

---

## 📝 Contributing

**Code Standards:**
- Follow [STYLE_GUIDE.md](STYLE_GUIDE.md)
- All enums `{.pure.}`
- TOML configs for game values
- NEP-1 naming conventions
- Comprehensive logging at all levels

**Development Workflow:**
1. Load session context (`@docs/CLAUDE_CONTEXT.md`)
2. Make changes following style guide
3. Run tests (`nimble test` or `nimble testBalanceDiagnostics`)
4. Update docs if system changes
5. Commit with descriptive message
6. Push to main branch

**For AI/Balance Work:**
1. Run diagnostics (`nimble testBalanceDiagnostics`)
2. Generate summary (`nimble summarizeDiagnostics`)
3. Share summary with Claude Code (not raw CSVs!)
4. Make targeted changes based on analysis
5. Re-test and iterate

See [Token Efficient Workflow](ai/TOKEN_EFFICIENT_WORKFLOW.md) for details.

---

## 📖 Additional Resources

- [Nim Language](https://nim-lang.org/)
- [NEP-1 Style Guide](https://nim-lang.org/docs/nep1.html)
- [Nim Manual](https://nim-lang.org/docs/manual.html)
- [EC Style Guide](../assets/ec-style-guide.md) - Esterian Conquest writing style

---

**Last Updated:** 2025-11-26
**Maintained By:** Claude Code + Human Developer
