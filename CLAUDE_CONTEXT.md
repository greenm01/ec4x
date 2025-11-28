# EC4X Development Context

This file contains critical patterns and gotchas for working with the EC4X codebase.

## CRITICAL: Nim Table Copy Semantics

**IMPORTANT**: Nim's `Table[K, V]` type returns **copies** when accessed via `table[key]`.

### The Problem
```nim
# BROKEN - Modifies a copy that is immediately discarded:
state.houses[houseId].treasury = 1000  # CHANGES ARE LOST!
state.fleets[fleetId].status = FleetStatus.Reserve  # CHANGES ARE LOST!
state.colonies[systemId].production = 100  # CHANGES ARE LOST!
```

### The Solution
Always use the get-modify-write pattern:
```nim
# CORRECT - Get, modify, write back:
var house = state.houses[houseId]
house.treasury = 1000
state.houses[houseId] = house  # Persists changes
```

### GameState Tables to Watch
- `state.houses: Table[HouseId, House]`
- `state.colonies: Table[SystemId, Colony]`
- `state.fleets: Table[FleetId, Fleet]`
- `state.diplomacy: Table[(HouseId, HouseId), DiplomaticState]`
- `state.fleetOrders: Table[FleetId, FleetOrder]`
- `state.spyScouts: Table[string, SpyScout]`

### Historical Context
Fixed 46 critical bugs across the entire engine:
- **Commit 8314e0d** (2025-11-25): 43 bugs - Intelligence (30), Economy/Diplomacy (13)
- **Commit cdbbde5** (2025-11-25): 3 bugs - Transport/fighter commissioning persistence
  - All intel reports were being lost
  - Treasury, elimination, prestige, fleet status changes were lost
  - Newly commissioned transports and fighters were lost

### When Writing New Code
1. **NEVER** write `state.table[key].field = value`
2. **ALWAYS** use: `var x = state.table[key]; x.field = value; state.table[key] = x`
3. Batch multiple modifications to the same table entry together
4. Add comment: `# CRITICAL: Get, modify, write back to persist`

### Known Remaining Issues
**Test Files:** ~74 Table copy bugs remain in integration tests (tests/integration/*.nim)
- These bugs don't affect gameplay since tests setup initial state with direct writes
- Need fixing before tests can properly verify state mutations
- See docs/OPEN_ISSUES.md for details

## Engine API Documentation

**For detailed engine patterns and examples, see:**
- **[Engine API Quick-Start Guide](/docs/api/ENGINE_QUICKSTART.md)** - Complete patterns reference
- **[API Documentation](/docs/api/README.md)** - Full API reference with examples

### Quick Reference

**Key Patterns** (detailed in Quick-Start):
- **Logging**: Use `logger.nim` with `logCombat()`, `logInfo()`, `logRNG()` etc.
- **RNG**: Turn-seeded `initRand(state.turn)`, pass through resolution chain
- **Config**: Load stats with `getShipStats(class, techLevel)`, apply WEP/CST
- **Destruction**: Mark `entity.destroyed = true` before removal, log it
- **Table-to-Seq**: Copy → modify via mpairs → write back to `state.table[id]`

See [ENGINE_QUICKSTART.md](/docs/api/ENGINE_QUICKSTART.md) for complete code examples.

## Always Use Nimble for Build and Test

Use `nimble` commands for all builds and tests, not direct compilation:
```bash
nimble build              # Build all targets
nimble test               # Run test suite
nimble testBalanceAct2    # Run Act 2 balance tests
```

Direct compilation may skip important build steps and configuration.

## Claude-Optimized Analysis Tools

**For detailed workflow and examples, see:**
- **[Claude Workflow Guide](/docs/analysis/claude-workflow.md)** - Complete usage patterns
- **[Analytics System Architecture](/docs/architecture/analytics-system.md)** - Technical details

### Quick Reference

EC4X provides token-efficient data export tools optimized for Claude analysis. These tools reduce 2-5M token CSV files to <12K tokens while preserving essential information.

**Export Formats:**
- **Markdown** (recommended): Token-efficient tables, Claude's native format
- **JSON**: Aggregated statistics with automatic anomaly detection
- **Summary**: Ultra-compact overview (<1K tokens)

**Basic Usage:**
```bash
# Quick summary for Claude (< 1K tokens)
python -m analysis.cli export-for-claude summary.txt --format=summary

# Markdown table for specific analysis (1-3K tokens)
python -m analysis.cli export-for-claude analysis.md \\
    --turns=10,20 \\
    --metrics=total_fighters,total_destroyers,tech_wep \\
    --format=markdown

# JSON with statistics and anomalies (1-2K tokens)
python -m analysis.cli export-for-claude stats.json \\
    --format=json \\
    --houses=alpha
```

**Filtering Options:**
- `--houses=HOUSE` - Filter by house name (can specify multiple)
- `--turns=START,END` - Filter by turn range (e.g., `--turns=10,20`)
- `--metrics=M1,M2,...` - Select specific metrics (default: important ones)
- `--format={markdown,json,summary}` - Output format (default: markdown)

**Token Optimization Tips:**
1. Start with `--format=summary` for initial assessment
2. Use `--turns` to focus on specific periods
3. Use `--metrics` to limit to relevant metrics
4. Combine filters for smallest output (e.g., `--houses=alpha --turns=10,15`)

**Common Patterns:**
```bash
# Pattern 1: "What went wrong in Turn X?"
python -m analysis.cli export-for-claude turn15.md --turns=13,17

# Pattern 2: "Is House Alpha's strategy working?"
python -m analysis.cli export-for-claude alpha.json --houses=alpha --format=json

# Pattern 3: "Are Destroyers too strong?" (balance check)
python -m analysis.cli export-for-claude ships.md \\
    --metrics=total_destroyers,total_cruisers,space_combat_wins
```

**File Size Targets:**
- < 5K tokens: Perfect ✅
- 5K-12K tokens: Good ✅
- > 12K tokens: Too large, add more filters ⚠️

The CLI automatically displays estimated token counts and warns if files are too large.

### Architecture Notes

**Implementation:** Currently Python-based (Polars + Click) for rapid development. Nim modules exist in `src/engine/analytics/` for future integration.

**Data Flow:**
1. Run balance tests: `nimble testBalance`
2. Diagnostics collected: `tests/balance/diagnostics.nim`
3. Parquet file generated: `balance_results/diagnostics_combined.parquet`
4. Export for Claude: `python -m analysis.cli export-for-claude ...`

**Performance:** Export completes in ~100-500ms using parallel processing (Polars).
