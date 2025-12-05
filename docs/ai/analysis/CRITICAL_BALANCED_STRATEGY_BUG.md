# CRITICAL BUG: Balanced Strategy Builds Zero Defenses

**Date:** 2025-12-05
**Severity:** 🚨 CRITICAL
**Status:** Under Investigation

## Executive Summary

The "Balanced" AI strategy **systematically fails to build ANY ground batteries** across all games tested, despite having healthy treasuries (800-1600 PP) and growing economies (1500-2400 PP/turn). This is a critical unknown-unknown that invalidates the Act-aware defense system for 1 out of 4 test strategies.

## Evidence

### Defense Construction by Strategy (Turn 20)

| Strategy     | Games | Zero Defense Rate | Avg Batteries | Avg Treasury |
|--------------|-------|-------------------|---------------|--------------|
| **Balanced** | **8** | **75.0%**         | **0.0**       | **1281 PP**  |
| Aggressive   | 8     | 0.0%              | 9.9           | 1446 PP      |
| Economic     | 8     | 0.0%              | 2.0           | 1091 PP      |
| Turtle       | 8     | 0.0%              | 2.1           | 1144 PP      |

**Finding:** Balanced strategy has **0.0 avg batteries** despite having MORE treasury than Economic/Turtle strategies which DO build defenses.

### Detailed Game Progression

**Example: Game 2016, house-ordos (Balanced)**
```
Turn  Treasury  Production  Batteries  Colonies  Ships
----  --------  ----------  ---------  --------  -----
5     830       1517        0          4         14
10    1075      1762        0          5         23
15    1322      2097        0          7         33
20    1280      2342        0          7         44
```

**Pattern Across All Balanced Games (2016-2023):**
- ✅ Economy growing: 1500 → 2400 PP/turn
- ✅ Treasury healthy: 800-1600 PP
- ✅ Ships being built: 14 → 36-45 ships
- ⚠️ **Batteries: 0 across ALL turns, ALL games**

## Root Cause Hypotheses

### Hypothesis 1: Build Requirements Not Generated
**Test:** Check if Domestikos generates defense requirements for Balanced strategy
**Evidence Needed:** Log output from `build_requirements.nim` for Balanced games

### Hypothesis 2: Budget Allocation Starves Defense
**Test:** Check Treasurer budget allocation for Balanced strategy
**Evidence Needed:** Defense budget percentage for Balanced vs. other strategies

### Hypothesis 3: Order Execution Skips Defense Orders
**Test:** Check if CFO receives and executes defense orders
**Evidence Needed:** Order queue logs for Balanced strategy

### Hypothesis 4: Strategy Configuration Issue
**Test:** Check if Balanced strategy has special configuration that disables defenses
**Current Finding:** Budget allocations are ACT-based, not STRATEGY-based
**Status:** Budget configuration looks normal

### Hypothesis 5: Personality Traits Block Defense Building
**Test:** Check if `economic_focus=0.7` or `aggression=0.4` somehow prevents defense construction
**Evidence Needed:** Trace how personality traits influence build requirements

## Impact Assessment

### Immediate Impact
- **Balanced strategy non-functional** - Cannot defend colonies
- **Balance test results invalid** - 25% of test data is corrupted
- **1.3% win rate for Balanced** - Likely due to zero defenses (vs. 49% for Economic/Turtle)

### Cascade Effects
- Act-aware defense validation is **partially invalid** - only validated for 3/4 strategies
- Unknown if other strategies have similar but less severe issues
- May indicate deeper systematic problem in RBA pipeline

## Investigation Priority

**CRITICAL:** This is a systematic failure affecting 25% of AI strategies. Must be resolved before:
1. Adding GOAP integration
2. Running comprehensive 30-turn tests
3. Declaring Act-aware system "production-ready"

## Next Steps

1. ✅ Document bug with evidence
2. 🔄 Trace Domestikos requirement generation for Balanced strategy
3. 🔄 Check Treasurer budget allocation logs
4. 🔄 Verify CFO order execution
5. 🔄 Add debug logging to identify where defense orders are lost
6. 🔄 Fix root cause
7. 🔄 Re-run balance tests to validate fix
8. 🔄 Check if other strategies have similar issues

## User's Goal Validated

> "my goal was first to ensure the the RBA was using all game units and test that they actually work. look for loopholes and unknown-unknonws in the engine"

**Result:** ✅ Found critical unknown-unknown!
- RBA is NOT using defense units correctly for Balanced strategy
- This is exactly the kind of systematic loophole testing should find
- Must fix before proceeding to GOAP integration

---

**Status:** Investigation in progress. Do not merge Act-aware defense system until this is resolved.
