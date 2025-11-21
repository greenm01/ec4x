# Integration Tests

Tests for multi-system interactions and full game flows.

## Test Files

- **test_starmap_robust.nim** - Starmap generation robustness
- **test_starmap_validation.nim** - Starmap validation rules
- **test_offline_engine.nim** - Offline engine integration

## Running Integration Tests

```bash
# Run starmap tests
nim c -r tests/integration/test_starmap_robust.nim
nim c -r tests/integration/test_starmap_validation.nim

# Run offline engine test
nim c -r tests/integration/test_offline_engine.nim
```

## Test Focus

Integration tests verify:
- Multi-module interactions
- Data flow between systems
- End-to-end workflows
- System boundaries

## Future Integration Tests

Planned additions:
- **test_turn_resolution.nim** - Full turn cycle
- **test_fleet_movement.nim** - Movement + combat integration
- **test_economy_production.nim** - Economy + building
- **test_diplomacy_combat.nim** - Diplomatic states + combat

## Adding New Integration Tests

1. Identify multi-system interaction
2. Create minimal test scenario
3. Verify data flows correctly
4. Check boundary conditions
5. Test error handling
