# Unit Tests

Tests for individual EC4X modules and components.

## Test Files

### Core Game Components
- **test_hex.nim** - Hex coordinate system tests
- **test_system.nim** - Star system tests
- **test_ship.nim** - Ship types and capabilities
- **test_fleet.nim** - Fleet composition and operations
- **test_config.nim** - Configuration loading and validation

## Running Unit Tests

```bash
# Run all unit tests
nim c -r tests/unit/test_hex.nim
nim c -r tests/unit/test_ship.nim
nim c -r tests/unit/test_fleet.nim
nim c -r tests/unit/test_system.nim
nim c -r tests/unit/test_config.nim
```

## Test Coverage

Unit tests focus on:
- Pure function behavior
- Data structure integrity
- Edge case handling
- Error conditions
- API contracts

## Adding New Unit Tests

1. Create new test file: `test_<module>.nim`
2. Import only the module being tested
3. Use `unittest` framework
4. Test one concept per test case
5. Keep tests fast (<100ms each)
