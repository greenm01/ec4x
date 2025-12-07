# Treasurer Budget Submodules

**Status:** Phase 0.2 In Progress - Refactoring from budget.nim (1363 lines)

## Module Structure

```
budget/
├── README.md                    # This file
├── types.nim                    # TODO - BudgetTracker, BudgetReport types (lines 21-49, 865-873)
├── execution.nim                # TODO - Main generateBuildOrdersWithBudget() (lines 960+)
├── feedback.nim                 # NEW (Phase 1.2) - Rich feedback generation (Gap 6)
└── splitting.nim                # NEW (Phase 1.3) - Strategic vs filler budget split
```

## TODO: Extractions from budget.nim

### types.nim (TODO - ~100 lines)
Extract from budget.nim:
- BudgetTracker type (line 25-28)
- initBudgetTracker() (line 28-45)
- BudgetReport types (line 865-873)
- generateBudgetReport() (line 876-913)
- logBudgetReport() (line 915-952)

### execution.nim (TODO - ~600 lines)
Extract from budget.nim lines 960+:
- generateBuildOrdersWithBudget() entry point
- All build order generation functions:
  - buildExpansionOrders()
  - buildFacilityOrders()
  - buildDefenseOrders()
  - buildMilitaryOrders()
  - buildReconnaissanceOrders()
  - buildSpecialUnitsOrders()
  - buildSiegeOrders()

## New Modules (Phase 1)

### feedback.nim (Phase 1.2 - Gap 6)
NEW module for rich feedback generation:
- generateRequirementFeedback() - Track WHY requirements unfulfilled
- generateSubstitutionSuggestion() - Suggest cheaper alternatives
- getCheaperAlternatives() - Find substitute ships/units
- Extends TreasurerFeedback with detailedFeedback field

### splitting.nim (Phase 1.3 - Unit Construction Fixes)
NEW module for budget splitting:
- splitStrategicAndFillerBudgets() - Reserve 15-20% for fillers
- Separate budget allocation logic
- Prevents capacity fillers from burying high-priority requirements

## Wrapper Pattern

The original `budget.nim` will become a thin wrapper (~300 lines) that:
1. Imports all submodules
2. Re-exports public symbols for backward compatibility
3. Retains high-level coordination logic

## Next Steps

1. Create types.nim (extract BudgetTracker, BudgetReport)
2. Create execution.nim (extract generateBuildOrdersWithBudget)
3. Move to Phase 1 - implement new features in feedback.nim and splitting.nim
4. Verify no regressions with existing tests
