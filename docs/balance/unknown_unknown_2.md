# Unknown-Unknown #2: Act 2 Defense Requirements Exceed Budget Capacity

**Status**: Identified
**Severity**: Medium
**Discovered**: 2025-11-28
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

## Next Steps

1. ✅ Document Unknown-Unknown #2 findings
2. ⏳ Decide on solution approach (Options 1-4)
3. ⏳ Implement chosen solution
4. ⏳ Re-test with 50-turn simulation
5. ⏳ Validate Act 2 defense buildup pacing
