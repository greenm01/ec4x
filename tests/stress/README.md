# EC4X Stress Testing Framework

Real stress tests for the EC4X engine - designed to find bugs, edge cases, and unknown-unknowns.

## What This Is

These are **NOT** validation tests. These are **stress tests** that:

- Run 1000+ turn simulations looking for state corruption
- Fuzz the engine with pathological inputs
- Detect performance regression and O(n²) algorithms
- Use statistical analysis to find unknown bugs
- Monitor for memory leaks and degradation

## Test Suites

### 1. `test_state_corruption.nim` - State Integrity Tests

Runs long-duration simulations checking for gradual state corruption:

- **1000-turn simulation**: No-op orders, check invariants every 100 turns
- **Repeated initialization**: 100 games to detect state leakage
- **Maximum scale**: 12 houses, 100 turns
- **Edge cases**: Zero-population colonies, negative treasury
- **Boundary conditions**: Maximum tech levels, extreme prestige

**What it detects:**
- Invalid game states (negative PU, invalid system IDs)
- Duplicate entity IDs (squadrons in multiple fleets)
- Ownership mismatches (fleet contains enemy squadrons)
- Boundary violations (tech > 20, infrastructure > 10)
- State degradation over time

**Run time:** ~5-10 minutes

```bash
nimble testStateCorruption
```

### 2. `test_pathological_inputs.nim` - Input Fuzzing

Tests engine resilience to invalid/malformed inputs:

- **Invalid system IDs**: Negative, zero, extremely large, max int
- **Non-existent fleets**: Empty strings, special characters, very long IDs
- **Invalid build orders**: Non-existent colonies, invalid ship classes
- **Bad research allocations**: Negative percentages, > 100% total
- **Extreme values**: 1000+ fleet orders, 100+ build queue

**What it detects:**
- Crashes from unvalidated inputs
- State corruption from malformed data
- Array bounds violations
- Integer overflows
- Type mismatches

**Run time:** ~30-60 seconds

```bash
nimble testPathologicalInputs
```

### 3. `test_performance_regression.nim` - Performance Monitoring

Measures turn resolution times to detect algorithmic problems:

- **Baseline**: 2-house game, 100 turns
- **Max scale**: 12-house game, 50 turns
- **Scaling analysis**: 10, 50, 100, 200 turn games
- **Variance detection**: Find occasional slow turns (3σ outliers)
- **Sustained operation**: 500 turns, monitor state growth

**What it detects:**
- O(n²) or worse algorithms (non-linear scaling)
- Performance degradation over time
- Intermittent slowdowns (GC pauses, cache misses)
- Unbounded state growth (memory leaks)

**Run time:** ~2-3 minutes

```bash
nimble testPerformanceRegression
```

### 4. `test_unknown_unknowns.nim` - Statistical Anomaly Detection

Runs many simulations and uses statistics to find hidden bugs:

- **100 games × 50 turns**: Full anomaly detection
- **1000 games × 10 turns**: Rare event detection
- **Statistical analysis**: Detect outliers, impossible values
- **Crash detection**: Track crash rate across games
- **Invariant violations**: Aggregate violations across all runs

**What it detects:**
- Bugs that only occur 1% of the time
- Statistical impossibilities (prestige 3σ from mean)
- Rare edge cases (zero colonies, duplicate IDs)
- System interactions causing emergent bugs
- Unknown invariant violations

**Run time:** ~5-10 minutes

```bash
nimble testUnknownUnknowns
```

## Infrastructure: `stress_framework.nim`

Core framework providing:

### State Invariant Checking

Validates 9 categories of invariants:

1. **Treasury**: No extremely negative values (< -10K PP)
2. **Fighter Capacity**: Reasonable fighter counts (< 1000 per colony)
3. **Squadron Limits**: Within PU-based limits
4. **Fleet Locations**: All fleets at valid system IDs
5. **Ownership**: All entities owned by valid houses
6. **Unique IDs**: No duplicate fleet/squadron IDs
7. **Orphaned Squadrons**: Squadrons in exactly one fleet
8. **Prestige Range**: Bounded prestige values
9. **Tech Level Range**: Tech levels in valid ranges (0-20)

### Violation Reporting

Three severity levels:
- **Warning**: Suspicious but maybe valid
- **Error**: Clear bug, invalid state
- **Critical**: Game-breaking corruption

### Usage Example

```nim
import stress_framework

let violations = checkStateInvariants(game, currentTurn)

if violations.len > 0:
  reportViolations(violations)

  let critical = violations.filterIt(it.severity == ViolationSeverity.Critical)
  if critical.len > 0:
    fail("Critical violations detected")
```

## Running the Tests

### Quick Test (< 2 minutes)

```bash
nimble testStressQuick
```

Runs:
- State corruption (abbreviated)
- Pathological inputs (full)

### Full Stress Test Suite (10-30 minutes)

```bash
nimble testStress
```

Runs all 4 test suites with full coverage.

### Individual Tests

```bash
nimble testStateCorruption      # State integrity
nimble testPathologicalInputs   # Input fuzzing
nimble testPerformanceRegression # Performance
nimble testUnknownUnknowns      # Anomaly detection
```

## What These Tests Find

### Real Bugs (Examples)

1. **State Corruption**
   - Squadron appears in 2 fleets simultaneously
   - Fleet at system ID 999999 (doesn't exist)
   - Negative PU after population transfer
   - Tech level 255 (integer overflow)

2. **Pathological Inputs**
   - Engine crashes on empty fleet ID
   - State corrupted by system ID -1
   - Array bounds violation with 1000+ orders
   - Integer overflow in build cost calculation

3. **Performance Issues**
   - Turn time grows O(n²) with game length
   - Occasional 10x slow turns (GC pressure)
   - State size grows unbounded (memory leak)
   - 12-house games take 10x longer than expected

4. **Unknown-Unknowns**
   - 2% of games end with negative prestige (bug!)
   - 0.1% crash rate (rare race condition)
   - Treasury averages -5000 PP (economy broken)
   - Some games have 0 colonies at turn 50 (conquest bug)

## Comparison to Other Test Suites

| Test Suite | Purpose | What It Finds | Run Time |
|------------|---------|---------------|----------|
| **Integration Tests** (`tests/integration/`) | Validate correct behavior | Feature works as designed | ~30s |
| **Balance Tests** (`tests/balance/`) | Test AI competence | AI plays well, game balanced | ~5-30min |
| **Stress Tests** (`tests/stress/`) | Find hidden bugs | State corruption, edge cases, unknown-unknowns | ~10-30min |

## CI/CD Integration

### Recommended Test Schedule

```yaml
# Run on every commit
- Integration tests (fast, < 1min)

# Run on PR
- Integration tests
- Stress tests (quick mode, ~2min)

# Run nightly
- Full stress test suite (~30min)
- Balance tests (AI validation)

# Run weekly
- Extended stress (1000+ turn simulations)
- Memory profiling
- Performance benchmarking
```

### Test Failure Thresholds

**Critical** (block merge):
- Any crash in stress tests
- State corruption violations
- Data integrity failures

**Warning** (investigate):
- Performance regression > 20%
- Anomaly rate > 5%
- Rare event rate > 1%

## Future Enhancements

1. **Concurrency Testing**: True race condition detection (requires threading)
2. **Memory Profiling**: Actual memory usage tracking (not just proxy metrics)
3. **Mutation Testing**: Inject bugs to verify tests catch them
4. **Property-Based Testing**: QuickCheck-style generative testing
5. **Chaos Engineering**: Random state mutations to test recovery

## When to Run These Tests

- **Before release**: Always run full suite
- **After engine changes**: Run relevant stress tests
- **Performance tuning**: Run performance regression tests
- **Bug investigation**: Run unknown-unknowns detection
- **Weekly**: Full suite as part of CI

## Interpreting Results

### All Tests Pass ✅

Great! No obvious bugs detected. But remember:
- Tests can't find every bug
- Rare bugs (< 0.1%) might be missed
- New code paths need new tests

### Warnings ⚠️

Investigate but don't block:
- Performance variance
- Suspicious (but possibly valid) states
- Statistical outliers

### Errors/Critical 🔴

**DO NOT MERGE**. Fix before proceeding:
- State corruption
- Crashes
- Data integrity violations
- Critical performance regression

## Contributing New Stress Tests

When adding new tests:

1. **Target specific failure modes** - don't just repeat existing coverage
2. **Use statistical analysis** - look for patterns, not just binary pass/fail
3. **Test at scale** - 100+ games, 1000+ turns
4. **Document what you're looking for** - explain the failure mode
5. **Set appropriate thresholds** - when should the test fail?

## Questions?

See also:
- `tests/integration/README.md` - Integration test documentation
- `tests/balance/README.md` - Balance/AI test documentation
- `docs/testing-strategy.md` - Overall testing philosophy
