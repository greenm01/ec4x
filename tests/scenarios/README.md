# Test Scenarios

Hand-crafted scenarios for specific testing purposes.

## Directory Structure

```
scenarios/
├── historical/   - Reproduce known bugs and edge cases
├── balance/      - Game balance verification
└── regression/   - Prevent regressions from past fixes
```

## Historical Scenarios

Document and reproduce known issues:

```nim
## Reproduce issue #42 - Desperation round infinite loop
proc historical_DesperationLoop*() =
  # Exact fleet compositions that triggered the bug
  # Expected: Resolves in <10 rounds after fix
```

## Balance Scenarios

Test game balance assumptions:

```nim
## Verify tech level advantage
proc balance_TechAdvantage*() =
  # Tech 3 fleet should beat Tech 0 fleet of equal size
  # Expected: Tech 3 wins 80%+ of the time
```

## Regression Scenarios

Lock down past fixes:

```nim
## Ensure fix for issue #15 still works
proc regression_ShieldPenetration*() =
  # Planet-Breaker should bypass shields
  # Expected: Full damage regardless of SLD level
```

## Adding Scenarios

1. Create descriptive procedure name
2. Add detailed comments explaining purpose
3. Include expected outcome
4. Reference issue numbers if applicable
5. Keep scenarios focused on one concept

## Future Organization

As scenarios grow, organize by:
- Game phase (early/mid/late game)
- Mechanic (combat/economy/diplomacy)
- Severity (critical/important/nice-to-have)
