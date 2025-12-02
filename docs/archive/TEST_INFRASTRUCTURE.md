# EC4X Test Infrastructure

## Overview

EC4X has a comprehensive test infrastructure with Python-based test runners that provide detailed analysis and reporting using Polars.

## Test Categories

### 1. Unit Tests
- **Location**: `tests/test_*.nim` (root level)
- **Purpose**: Test individual functions and modules
- **Run**: `nimble testUnit` or `python3 tests/run_all_tests.py --types unit`

### 2. Integration Tests
- **Location**: `tests/integration/test_*.nim`
- **Count**: 36 test files
- **Coverage**: 200+ test cases
- **Purpose**: Test system integration and end-to-end workflows
- **Run**: `nimble testIntegrationPython` or `python3 tests/run_all_tests.py --types integration`

**Key Integration Tests**:
- `test_all_units_commissioning.nim` - 20 tests for all 19 ship types
- `test_all_units_comprehensive.nim` - 30 tests validating all units against specs
- `test_combat_comprehensive.nim` - 81 tests for combat engine
- `test_starmap_validation.nim` - 12 tests for starmap generation
- `test_repair_system.nim` - 13 tests for repair system (NEW)

### 3. Stress Tests
- **Location**: `tests/stress/test_*.nim`
- **Purpose**: Long-running simulations and edge case testing
- **Run**: `nimble testStressPython` or `python3 tests/run_all_tests.py --types stress`

### 4. Balance Tests
- **Location**: `tests/balance/`
- **Purpose**: Game balance validation across multiple acts
- **Run**: `nimble testBalancePython` or `python3 tests/run_all_tests.py --types balance`

## Python Test Runners

### Comprehensive Test Runner

**File**: `tests/run_all_tests.py`

**Features**:
- ✅ Runs all test types (unit, integration, stress, balance)
- ✅ Parallel execution with timeouts
- ✅ Polars-based data analysis
- ✅ CSV report generation
- ✅ Colored terminal output
- ✅ Progress tracking
- ✅ Detailed failure reporting

**Usage**:
```bash
# Run all tests
python3 tests/run_all_tests.py --types all

# Run specific test types
python3 tests/run_all_tests.py --types integration stress

# Generate CSV report
python3 tests/run_all_tests.py --types all --report test_report.csv

# Custom timeout
python3 tests/run_all_tests.py --types all --timeout 180
```

**Example Output**:
```
╔════════════════════════════════════════════════╗
║  EC4X Comprehensive Test Suite Runner         ║
╚════════════════════════════════════════════════╝

Found   3 unit tests
Found  36 integration tests
Found   4 stress tests
Found   8 balance tests

Total: 51 test files

Running INTEGRATION tests:
[INTEGRATION ] [ 1/36] test_all_units_commissioning.nim       ✓ PASS  20 tests,   1.2s
[INTEGRATION ] [ 2/36] test_all_units_comprehensive.nim       ✓ PASS  30 tests,   0.8s
...

╔════════════════════════════════════════════════╗
║  Comprehensive Test Summary                    ║
╚════════════════════════════════════════════════╝

Overall Results:
  Test Files:    51 total
                 48 passed
                  3 failed

  Test Cases:   256 total
                252 passed
                  4 failed

  Duration:     42.5s total
                 0.2s avg per test case

Detailed Analysis (via Polars):
  Slowest tests:
    [integration   ] test_combat_comprehensive.nim               8.2s
    [integration   ] test_economy_comprehensive.nim              6.7s
    [integration   ] test_resolution_comprehensive.nim           5.3s

  Most comprehensive tests:
    [integration   ] test_combat_comprehensive.nim              81 cases
    [integration   ] test_all_units_comprehensive.nim           30 cases
    [integration   ] test_all_units_commissioning.nim           20 cases

✓ All tests passed!

Detailed report saved to: test_report.csv
```

### Integration-Only Runner

**File**: `tests/run_integration_tests.py`

**Features**:
- ✅ Focused on integration tests only
- ✅ Same polars analysis and reporting
- ✅ Faster for integration-only testing

**Usage**:
```bash
python3 tests/run_integration_tests.py
```

## Nimble Tasks

### Primary Tasks

```bash
# Run complete test suite (via Python)
nimble test

# Run with polars analysis and CSV report
nimble testPython

# Run specific test types
nimble testUnit
nimble testIntegrationPython
nimble testStressPython
nimble testBalancePython
```

### Legacy Tasks (Direct Nim)

```bash
# Core tests
nimble testCore

# Integration tests (old runner)
nimble testIntegration

# Comprehensive test suites
nimble testComprehensive

# Specific test suites
nimble testUnits
nimble testEconomy
nimble testCombat
nimble testTechnology
```

## Test Report Format

When using `--report` flag, generates a CSV file with columns:
- `test_type`: unit, integration, stress, balance
- `test_file`: filename
- `status`: passed, failed, error, timeout
- `passed`: number of passed test cases
- `failed`: number of failed test cases
- `total_tests`: total test cases
- `duration_ms`: execution time in milliseconds
- `duration_s`: execution time in seconds

**Polars Analysis Example**:
```python
import polars as pl

df = pl.read_csv('test_report.csv')

# Top 5 slowest tests
slowest = df.sort('duration_s', descending=True).head(5)

# Tests by status
status_summary = df.group_by('status').agg(pl.count())

# Integration test statistics
integration_stats = df.filter(pl.col('test_type') == 'integration').select([
    pl.sum('total_tests').alias('total_cases'),
    pl.sum('passed').alias('passed_cases'),
    pl.sum('failed').alias('failed_cases'),
    pl.mean('duration_s').alias('avg_duration_s'),
])
```

## Recent Achievements

### 1. Commissioning System
- ✅ Fixed all three commissioning paths
- ✅ Construction queue → auto-assign
- ✅ Repair queue → recommission → auto-assign
- ✅ Maintenance phase → commission → auto-assign

### 2. Spacelift Ships
- ✅ ETAC and TroopTransport commission correctly
- ✅ Auto-load PTU onto ETAC at commissioning
- ✅ Auto-assign to fleets (create new if needed)
- ✅ Fleet.isEmpty() checks both squadrons AND spacelift ships

### 3. Repair System
- ✅ **NEW**: Comprehensive test suite created
- ✅ 13 tests covering all repair scenarios
- ✅ Flagship promotion logic tested
- ✅ Squadron/fleet dissolution verified
- ✅ Starbase repairs validated
- ✅ Priority system (construction=0, ships=1, starbases=2)

### 4. Starmap Validation
- ✅ Hub lanes use mixed types (not all Major)
- ✅ Homeworlds have exactly 3 Major lanes
- ✅ No dead systems (all reachable from hub)
- ✅ Validation enforced at generation time

### 5. Turn-End Validation
- ✅ Prevents orphaned units in unassigned pools
- ✅ All commissioned units must be assigned before turn advances
- ✅ Catches bugs early in development

## Test Coverage Summary

| Test Type | Files | Test Cases | Status |
|-----------|-------|------------|--------|
| Unit | 3 | ~50 | ✅ |
| Integration | 36 | 200+ | ✅ |
| Stress | 4 | varies | ⚠️ |
| Balance | 8 | varies | ⚠️ |

### Verified Passing Tests

1. **test_all_units_commissioning.nim** - 20/20 ✓
2. **test_all_units_comprehensive.nim** - 30/30 ✓
3. **test_combat_comprehensive.nim** - 81/81 ✓
4. **test_starmap_validation.nim** - 12/12 ✓
5. **test_repair_system.nim** - 13/13 ✓

## Dependencies

### Required
- Python 3.7+
- Nim 2.0+

### Optional (for enhanced reporting)
- `polars` - Data analysis and aggregation
  ```bash
  pip install polars
  ```

Without polars, tests still run but without advanced analytics.

## CI/CD Integration

The Python test runners are designed for CI/CD:

**GitHub Actions Example**:
```yaml
- name: Run Test Suite
  run: |
    python3 tests/run_all_tests.py --types all --report test_report.csv

- name: Upload Test Report
  uses: actions/upload-artifact@v3
  with:
    name: test-report
    path: test_report.csv
```

**GitLab CI Example**:
```yaml
test:
  script:
    - python3 tests/run_all_tests.py --types all --report test_report.csv
  artifacts:
    reports:
      junit: test_report.csv
    when: always
```

## Troubleshooting

### Test Timeouts
Default timeout is 120 seconds. Increase for slow tests:
```bash
python3 tests/run_all_tests.py --timeout 300
```

### Missing Polars
Install polars for enhanced reporting:
```bash
pip install polars
```

Tests run without polars but provide basic reporting only.

### Compilation Errors
Check hints/warnings:
```bash
nim c -r --hints:on --warnings:on tests/integration/test_name.nim
```

## Future Enhancements

- [ ] JUnit XML output for CI/CD dashboards
- [ ] HTML report generation
- [ ] Test coverage metrics
- [ ] Performance regression detection
- [ ] Parallel test execution
- [ ] Test result comparison across commits

## Space Guild Note

The Space Guild provides civilian Starliner services for population transfers. **The Space Guild does NOT commission ships for houses** - they operate their own abstracted fleet. Houses pay for transport services, not ship ownership.

For details see:
- `src/engine/population/transfers.nim`
- `docs/specs/economy.md` Section 3.7

## Contact

For test infrastructure questions or improvements, see the test runner source code or project documentation.
