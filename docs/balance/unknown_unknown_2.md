# Unknown-Unknown #2: Act 2 Defense Requirements Exceed Budget Capacity

**Status**: Resolved (CFO-Admiral Consultation System)
**Severity**: Medium → Low
**Discovered**: 2025-11-28
**Resolved**: 2025-11-28
**Test**: 50-turn comprehensive balance test

## Summary

The Act+Personality system correctly identifies that all AIs should establish colony defenses in Act 2 (Rising Tensions), but the budget allocation (15% Defense) is insufficient to fulfill these requirements. This creates a strategic mismatch: Admiral knows what needs to be built, but the budget prevents execution.

## Evidence

### Act 1 Behavior (Correct)
```
Turn 1-7 (Act1_LandGrab):
- Atreides (risk=0.80): 0 requirements ✓ (high risk, pure expansion)
- Ordos (risk=0.50): 0 requirements ✓ (medium risk, homeworld-only)
- Corrino (risk=0.30): 1-3 requirements ✓ (low risk, defends during expansion)
- Harkonnen (risk=0.30): 1-3 requirements ✓ (low risk, defends during expansion)
```

**Analysis**: Personality-driven Act 1 behavior working as designed. High/medium risk AIs expand aggressively, low risk AIs defend cautiously.

### Act 2 Transition (Budget Mismatch)
```
Turn 8 (Act2_RisingTensions transition):
- ALL AIs now generating 2-6 defense requirements per turn
- Typical budget: 300PP total
- Defense allocation (15%): 45PP
- Requirements: 2-6× Destroyers @ 40PP each = 80-240PP needed
- Result: 35-195PP shortage → unfulfilled requirements
```

**Example Log Output**:
```
[Turn 8] house-ordos Admiral generated 4 build requirements (Total=160PP)
[Turn 8] house-ordos Budget allocation (Act2_RisingTensions): total=345PP, Defense=51PP
[Turn 8] WARN: house-ordos Admiral requirement unfulfilled (insufficient Defense budget): 1× Destroyer (need 40PP)
[Turn 8] WARN: house-ordos Admiral requirement unfulfilled (insufficient Defense budget): 1× Destroyer (need 40PP)
[Turn 8] WARN: house-ordos Admiral requirement unfulfilled (insufficient Defense budget): 1× Destroyer (need 40PP)
```

### Persistent Problem
```
Turns 8-15 (Act 2 progression):
- Requirements continue unfulfilled every turn
- Total unfulfilled across all houses: ~40-60 Destroyers over 8 turns
- Pattern: All non-aggressive AIs want to defend, budget prevents it
```

## Root Cause Analysis

### Design Intent vs Reality

**Act 2 Strategic Objective**: "Establish defensive network before war"
**Personality Response**: "All AIs recognize colonies need defense (except high-risk aggressive)"
**Budget Reality**: 15% allocation = ~45PP, supports 1 Destroyer per turn
**Requirement Reality**: Admiral identifies 2-6 gaps per house = 80-240PP needed

### Why This Happens

1. **Colonies accumulate during Act 1**:
   - High-risk AIs claim 8-12 colonies (pure expansion)
   - Medium-risk AIs claim 6-10 colonies (fast expansion)
   - Low-risk AIs claim 4-8 colonies (cautious expansion)

2. **Act 2 transition triggers mass defense requirements**:
   - High-risk AIs: "Oh wait, I should probably defend SOMETHING"
   - Medium-risk AIs: "Time to secure all my colonies"
   - Low-risk AIs: "Need even MORE defenders now"

3. **Budget can't catch up**:
   - Building 1 Destroyer/turn takes 4-8 turns to cover all colonies
   - Meanwhile, Act 2 is only ~7-10 turns before Act 3 war starts
   - Result: Still under-defended when war begins

## Impact Assessment

### Gameplay Impact

**Strategic Realism**: ⚠️ Moderate concern
- AIs correctly identify defensive needs
- But can't execute strategy due to budget constraints
- Creates false sense of security (requirements logged but unfulfilled)

**Balance Impact**: ✅ Surprisingly OK
- All AIs equally affected (level playing field)
- High-risk AIs actually benefit (skipped defense, invested in offense)
- Low-risk AIs penalized for being cautious (wanted defense, couldn't afford it)

**Player Experience**: ⚠️ May notice AI vulnerability
- AI colonies remain undefended longer than they should
- Player can exploit this window with raids
- AI telegraph intentions but can't execute

### Code Health Impact

**Warning Spam**: ⚠️ Log pollution
- 3-6 unfulfilled warnings per house per turn in Act 2
- Over 50-turn game: ~500+ warning messages
- Makes real issues harder to spot

**Requirement System**: ✅ Working correctly
- Admiral correctly identifies gaps
- Budget system correctly enforces constraints
- Requirements carry forward appropriately

## Potential Solutions

### Option 1: Increase Act 2 Defense Budget
**Change**: 15% → 25-30%
**Trade-off**: Reduce Reconnaissance or Military
**Pros**:
- Simple config change
- Aligns budget with strategic objective
- All personalities can execute their strategies

**Cons**:
- May slow Act 2 offensive preparations
- Reduces reconnaissance investment (ELI mesh)
- One-size-fits-all solution

### Option 2: Personality-Scaled Defense Budgets
**Change**: Dynamic budget based on risk_tolerance
- Low risk (turtle): 30% Defense, 20% Recon, 30% Military
- Medium risk (balanced): 20% Defense, 25% Recon, 35% Military
- High risk (aggressive): 10% Defense, 25% Recon, 45% Military

**Pros**:
- Aligns budget with personality objectives
- Diverse strategic execution
- Emergent gameplay variety

**Cons**:
- More complex configuration
- Harder to balance
- Requires budget system refactoring

### Option 3: Multi-Turn Defense Planning
**Change**: Admiral spreads requirements across multiple turns
- Identify 6 defense gaps → prioritize top 2 per turn
- Rest marked "Deferred" until higher priorities fulfilled
- Gradual defense buildup over Act 2

**Pros**:
- Works within current budget constraints
- Realistic pacing (can't defend everything instantly)
- Reduces warning spam

**Cons**:
- More complex Admiral logic
- May still leave colonies vulnerable
- Doesn't address fundamental budget issue

### Option 4: Hybrid Approach
**Change**: Combine Options 1 & 3
- Modest budget increase (15% → 20%)
- Multi-turn prioritization for gradual buildup
- Accept some colonies remain undefended

**Pros**:
- Balanced solution
- Realistic constraints
- Personality diversity maintained

**Cons**:
- Still requires both code and config changes

## Recommendation

**Preferred Solution**: Option 4 (Hybrid)

**Rationale**:
1. Act 2 lasts ~10 turns - can't defend everything instantly anyway
2. Small budget bump (20%) + prioritization = realistic defense pace
3. Maintains strategic tension (some exposure acceptable)
4. Aligns with game progression (prepare for Act 3, not instant perfection)

**Implementation**:
1. Increase Act 2 Defense budget: 15% → 20% (in rba.toml)
2. Add requirement prioritization to Admiral (Phase 4 enhancement)
3. Only generate top-N requirements per turn based on budget capacity

## Test Results

### Requirements Generated (50-turn test)
```
Act 1 (Turns 1-7):
- Total requirements: ~15-20 across all houses
- Unfulfilled: ~10-15 (low-risk AIs only)
- Fulfillment rate: ~40-50%

Act 2 (Turns 8-15):
- Total requirements: ~150-200 across all houses
- Unfulfilled: ~120-160 (all AIs)
- Fulfillment rate: ~20-25%
```

### Personality Behavior (Verified)
```
✓ High risk (Atreides, risk=0.80): 0 requirements in Act 1, minimal in Act 2
✓ Medium risk (Ordos, risk=0.50): 0 requirements in Act 1, moderate in Act 2
✓ Low risk (Corrino/Harkonnen, risk=0.30): High requirements in both acts
```

## Related Issues

- **Unknown-Unknown #1**: Fixed - Admiral ordering and Act 1 personality behavior
- **Phase 3**: Build requirements system working correctly
- **Phase 4**: May need budget reforms or multi-turn planning

## Resolution: CFO-Admiral Consultation System

**Implementation Date**: 2025-11-28
**Solution Chosen**: Dynamic budget allocation with Admiral consultation (variant of Option 2)

### Architecture

Created new CFO module with clean separation of concerns:
- `src/ai/rba/cfo.nim`: Public API
- `src/ai/rba/cfo/allocation.nim`: Core allocation logic (baseline + personality + consultation)
- `src/ai/rba/cfo/consultation.nim`: Admiral consultation logic (requirements blending + strategic triage)

### How It Works

**Before CFO Consultation** (baseline):
```
Act 2 Budget Allocation:
- Defense: 15% (static from config)
- Military: 30% (static from config)
- Reconnaissance: 25% (static from config)
Result: Admiral needs 160PP Defense, gets 45PP (115PP shortage)
```

**After CFO Consultation** (dynamic):
```
1. CFO reads baseline from config (Defense=15%)
2. CFO calculates PP needed from Admiral requirements (160PP Defense)
3. CFO blends requirements with baseline:
   - Target = 160PP / 300PP = 53%
   - Blended = (53% × 0.7) + (15% × 0.3) = 37% + 4.5% = 41.5%
4. CFO normalizes to ensure total = 100%
Result: Admiral needs 160PP Defense, gets 124PP (36PP shortage vs 115PP before)
```

**Consultation Strategy**:
- **Requirements Blending** (normal case): 70% requirement-driven + 30% baseline config
  - Maintains strategic diversity while fulfilling tactical needs
  - Only considers Critical+High priority requirements
- **Strategic Triage** (oversubscribed case): Emergency allocation with minimum reserves
  - Maintains 10% minimum for reconnaissance (strategic awareness)
  - Maintains 5% minimum for expansion (economic growth)
  - Prevents strategic blindness

### Implementation Details

**Key Functions** (src/ai/rba/cfo/consultation.nim):
```nim
proc calculateRequiredPP*(requirements: BuildRequirements): Table[BuildObjective, int]
  - Sums estimated costs per objective for Critical+High priority requirements
  - Lower priorities deferred if budget tight

proc blendRequirementsWithBaseline*(allocation: var BudgetAllocation, ...)
  - Normal case: 70% requirement-driven, 30% baseline config
  - Adjusts Defense, Military, Reconnaissance based on Admiral needs

proc applyStrategicTriage*(allocation: var BudgetAllocation, ...)
  - Emergency case: When urgent requirements > available budget
  - Maintains minimum reserves for recon/expansion
  - Prevents strategic blindness

proc consultAdmiralRequirements*(allocation: var BudgetAllocation, ...)
  - Main entry point: Chooses blending vs triage strategy
```

**Integration Point** (src/ai/rba/budget.nim:1028-1034):
```nim
var allocation = cfo.allocateBudget(
  act,
  personality,
  isUnderThreat,
  admiralRequirements,  # NEW: CFO consults Admiral requirements
  availableBudget       # NEW: CFO needs total budget to calculate percentages
)
```

### Test Results

**Comprehensive 50-turn balance test**:
- **Baseline** (static allocation): 782 unfulfilled warnings
- **After CFO consultation**: 604 unfulfilled warnings
- **Improvement**: 22.8% reduction (178 fewer warnings)

**Analysis of Remaining Warnings**:
- Total requirements generated: 35,360PP
- Urgent requirements (Critical+High): 478PP (1.4%)
- Non-urgent requirements (Medium+Low): 34,882PP (98.6%)
- CFO correctly ignores non-urgent requirements (can be deferred)

**Dynamic Allocation Examples**:
```
Turn 8: Admiral needs 80PP Defense → CFO allocates 29% (up from 15%)
Turn 10: Admiral needs 120PP Defense → CFO allocates 33% (up from 15%)
Turn 12: Admiral needs 160PP Defense → CFO allocates 39% (up from 15%)
Turn 14: Admiral needs 0PP Defense → CFO allocates 15% (baseline)
```

### Why This Solution Works

1. **Dynamic Response**: Budget adapts to actual strategic needs rather than static percentages
2. **Priority-Aware**: Only urgent (Critical+High) requirements drive allocation changes
3. **Strategic Balance**: 70/30 blend maintains diversity while fulfilling tactical needs
4. **Safety Nets**: Strategic triage prevents blindness (minimum recon/expansion reserves)
5. **Backward Compatible**: Falls back to static config when no Admiral requirements
6. **Modular Architecture**: Clean separation prevents file bloat (budget.nim was getting large)

### Remaining Issues

While the CFO consultation system significantly improved budget allocation, unfulfilled warnings remain because:

1. **Priority Distribution**: Admiral generates mostly Medium/Low priority requirements (98.6%)
   - CFO correctly defers these to focus on urgent needs
   - This is expected behavior, not a bug

2. **Budget Constraints**: Even with dynamic allocation, budget still finite
   - Can't defend all 8-12 colonies simultaneously
   - Gradual defense buildup over Act 2 (realistic pacing)

3. **Warning System**: Logs ALL unfulfilled requirements regardless of priority
   - Future enhancement: Suppress warnings for deferred low-priority requirements
   - Or: Show as "Deferred" instead of "Unfulfilled"

### Future Enhancements

Potential Phase 4 improvements:
1. **Multi-Turn Planning**: Admiral spreads requirements across turns based on budget capacity
2. **Priority-Aware Warnings**: Suppress/reclassify warnings for non-urgent requirements
3. **Personality-Scaled Reserves**: Adjust minimum recon/expansion percentages by risk tolerance
4. **Carry-Forward System**: Track unfulfilled urgent requirements across turns

### Lessons Learned

**Unknown-Unknown Nature**:
- Initial symptom: 500+ unfulfilled warnings
- Initial hypothesis: Budget percentages wrong
- Actual problem: No communication between Admiral (requirements) and CFO (allocation)
- Solution required: New consultation system bridging strategic and fiscal planning

**Design Philosophy**:
- Admiral identifies WHAT is needed (requirements)
- CFO determines HOW MUCH budget to allocate (percentages)
- Consultation bridges strategic needs with fiscal reality

**Architecture Impact**:
- Extracted CFO logic to dedicated module (clean separation)
- Prevented budget.nim from growing to 1500+ lines
- Enabled future enhancements without file bloat

## Next Steps

1. ✅ Document Unknown-Unknown #2 findings
2. ✅ Implement CFO-Admiral consultation system
3. ✅ Test with 50-turn simulation
4. ✅ Validate dynamic allocation behavior
5. ✅ Document resolution and results
6. ⏳ Consider Phase 4 enhancements (multi-turn planning, priority-aware warnings)
