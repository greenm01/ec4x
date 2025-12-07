# Domestikos Requirements Submodules

**Status:** Phase 2.3 Complete - Gap 5 Standing Order Integration

## Module Structure

```
requirements/
├── README.md                    # This file
├── types.nim                    # ✓ DONE - DefenseGap, ColonyDefenseHistory types
├── defense_gaps.nim             # ✓ DONE - Defense gap analysis functions
├── reprioritization.nim         # ✓ DONE - Budget-aware reprioritization
├── standing_order_support.nim   # ✓ DONE (Phase 2.3) - Gap 5 integration
├── capacity_filler.nim          # TODO - 20-slot rotation logic (lines 1543-1820)
└── generator.nim                # TODO - Main generateBuildRequirements() entry point
```

## Completed Modules

### types.nim (~30 lines)
- DefenseGap type
- ColonyDefenseHistory type
- Pure data structures (DoD principle)

### defense_gaps.nim (~280 lines)
- escalateSeverity()
- countDefendersAtColony()
- getColonyDefenseHistory()
- calculateColonyDefensePriority()
- findNearestAvailableDefender()
- calculateGapSeverity()
- assessDefenseGaps()

### reprioritization.nim (~150 lines)
- reprioritizeRequirements()
- Budget-aware 3-tier downgrading
- Will be enhanced in Phase 2.4 with quantity adjustment + substitution

### standing_order_support.nim (~250 lines, Phase 2.3)
- updateDefenseHistory() - Track turnsUndefended for escalation
- generateStandingOrderSupportRequirements() - Requirements for systems with active defense orders
- biasFillerTowardsDefenders() - Bias capacity fillers toward defender types
- Integrates with standing_orders_manager.nim query API (Gap 5)

## TODO: Remaining Extractions

### capacity_filler.nim (TODO - ~400 lines)
Extract from build_requirements.nim lines 1543-1820:
- 20-slot rotation logic
- selectBestUnit() integration
- Act-aware per-slot budgets

### generator.nim (TODO - ~400 lines)
Extract from build_requirements.nim lines 1406-1542:
- generateBuildRequirements() entry point
- assessReconnaissanceGaps()
- assessExpansionNeeds()
- assessOffensiveReadiness()
- Helper functions

## Wrapper Pattern

The original `build_requirements.nim` will become a thin wrapper (~200 lines) that:
1. Imports all submodules
2. Re-exports public symbols for backward compatibility
3. Retains shared helper functions (calculateAffordabilityFactor, etc.)

## Next Steps

1. Extract capacity_filler.nim
2. Extract generator.nim
3. Create wrapper build_requirements.nim with re-exports
4. Verify no regressions with existing tests
5. Move to Phase 0.2 (treasurer/budget/ refactoring)
