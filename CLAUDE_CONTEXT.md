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
Fixed 43 critical bugs across the entire engine (commit 8314e0d):
- Intelligence system: 30 bugs - ALL intel reports were being lost
- Economy/Diplomacy: 13 bugs - Treasury, elimination, prestige, fleet status

### When Writing New Code
1. **NEVER** write `state.table[key].field = value`
2. **ALWAYS** use: `var x = state.table[key]; x.field = value; state.table[key] = x`
3. Batch multiple modifications to the same table entry together
4. Add comment: `# CRITICAL: Get, modify, write back to persist`

## Always Use Nimble for Build and Test

Use `nimble` commands for all builds and tests, not direct compilation:
```bash
nimble build              # Build all targets
nimble test               # Run test suite
nimble testBalanceAct2    # Run Act 2 balance tests
```

Direct compilation may skip important build steps and configuration.
