# Invasion Planning System - Root Cause Identified

**Date:** 2025-12-11
**Issue:** Zero conquests in all games despite complete 3-phase invasion planning implementation
**Status:** Root cause identified, fix ready for implementation

---

## Implementation Completed

Successfully implemented all three phases of the multi-step invasion planning system:

### ✅ Phase 1: Quick Wins (Commit 17f6003)
- Relaxed vulnerability thresholds (defense ratio 0.3 → 0.5, value 50 → 30)
- Added diagnostic logging to colony analyzer
- Improved fallback visibility targeting
- Added 7 invasion metrics to diagnostics

### ✅ Phase 2: RBA Multi-Turn Campaigns (Commit 06e086c)
- Implemented 4-phase campaign state machine (Scouting → Bombardment → Invasion → Consolidation)
- Added campaign tracking to AIController
- Integrated campaigns with priority-based order generation
- Added campaign configuration to rba.toml
- Added 8 campaign lifecycle metrics

### ✅ Phase 3: GOAP Integration (Commits 6321c5b + de61649)
- Added 3 GOAP invasion action types (BombardPlanet, BlitzPlanet, InvadePlanet)
- Implemented defense-based tactic selection in planInvasionActions()
- **Completed critical GOAP→RBA conversion bridge** (was stubbed at line 187)
- Added plan execution framework (executePlanStep, executeAllPlans)
- Wired GOAP into main AI loop (Phase 6.5)
- Updated GOAP configuration with invasion parameters
- Added 4 GOAP invasion metrics

---

## Testing Results: Zero Conquests

Despite all implementation work, test games showed:
- **Colonized systems:** 26 (all via ETAC)
- **Conquered systems:** 0 (zero invasions)
- **Military readiness:** Houses have 4-10 TroopTransports, 3-7 Marines, 48-55 total ships
- **Hoarding:** 14k-38k PP unspent treasury

---

## Diagnostic Investigation

### Metrics Analysis

**Phase 1 Results:**
```
vulnerable_targets_count: 0 (EVERY TURN)
invasion_orders_generated: 2-3 per house
invasion_orders_bombard: 2-3
invasion_orders_invade: 0
invasion_orders_blitz: 0-1
```

**Phase 2 Results:**
```
active_campaigns_total: 0 (EVERY TURN)
```

**Phase 3 Results:**
```
goap_enabled: 1
goap_invasion_goals: 2-5
goap_invasion_plans: 0
goap_actions_executed: 0
```

**Espionage Activity:**
```
spy_planet: 0 (EVERY TURN)
total_espionage: 1 per turn
espionage_success: 0-1 total
```

### Log Analysis

```
[INFO] [AI] house-corrino Colony Analyzer: Processing 0 colony intel reports
[INFO] [AI] house-corrino Drungarius: Enhanced intelligence - 0 enemy fleets, 0 threats, 0 vulnerable targets, 0 high-value targets
[INFO] [AI] house-corrino Drungarius: Recommending 36 reconnaissance missions
[INFO] [AI] house-corrino GOAP: Extracted 0 goals
[INFO] [AI] house-corrino GOAP: Generated 0 plans
```

**Critical Pattern:**
- ✅ Drungarius recommends 36 reconnaissance missions
- ❌ Colony Analyzer processes **0 colony intel reports**
- ❌ Zero vulnerable targets identified
- ❌ Zero GOAP plans generated
- ❌ Zero campaigns activated

### Fleet Composition
```
House            Scouts   Total Ships  Spy Orders  Hack Orders
house-corrino    16       54           0           0
house-atreides   4        48           0           0
house-harkonnen  1        50           0           0
house-ordos      10       55           0           0
```

**Observation:** Houses have 4-16 scouts but generate zero SpyPlanet orders.

---

## Root Cause: Wrong Order Type

### Bug Location
**File:** `src/ai/rba/domestikos/exploration_ops.nim`
**Function:** `generateReconnaissanceOrders()`
**Line:** 174

### The Bug

```nim
result.add(FleetOrder(
  fleetId: scout.fleetId,
  orderType: FleetOrderType.ViewWorld,  # ❌ BUG: Deep space scan
  targetSystem: some(target.systemId),
  priority: 75
))
```

### Why This Breaks Everything

**ViewWorld:**
- Provides basic system visibility
- Does NOT populate `intelligence.colonyReports` table
- Cannot gather defense/economic details

**SpyPlanet (required):**
- Gathers detailed colony intelligence
- Populates `intelligence.colonyReports` with defenses, economy, starbases
- Enables vulnerability assessment in colony_analyzer.nim

### Cascade Failure

```
ViewWorld orders
    ↓
Zero colony intelligence reports
    ↓
Colony Analyzer: 0 vulnerable targets (lines 82-84 check fails)
    ↓
Phase 2: No campaign creation (line 746 needs vulnerableTargets)
    ↓
Phase 3: No invasion goals extracted (needs vulnerableTargets)
    ↓
Result: Zero conquests
```

### Why Fallback Targeting Fails

Lines 536-597 in offensive_ops.nim implement visibility-based fallback, but:
- Only generates Bombard orders (no Invade/Blitz)
- Priority conflicts with other orders
- No multi-turn sequencing
- Cannot identify "actually vulnerable" vs "just visible"

---

## The Fix

### Change Required

**File:** `src/ai/rba/domestikos/exploration_ops.nim`
**Line:** 174

```nim
# OLD (wrong):
orderType: FleetOrderType.ViewWorld,  # Deep space scan - safer, no orbital approach

# NEW (correct):
orderType: FleetOrderType.SpyPlanet,  # Detailed colony scan - required for invasion planning
```

### Expected Impact

✅ Colony intelligence reports populate
✅ `vulnerableTargets_count > 0` in 50%+ of games
✅ Phase 2 campaigns activate
✅ GOAP invasion goals extracted
✅ Invasions begin occurring

---

## Success Criteria (Post-Fix)

### Phase 1
- [ ] `vulnerableTargets_count > 0` in 50%+ of games
- [ ] At least 1 conquest in 20-game test batch
- [ ] Diagnostic logs show "TARGET IDENTIFIED" messages

### Phase 2
- [ ] `activeCampaigns_total > 0` in 60%+ of games
- [ ] Bombardment → Invasion transitions in logs
- [ ] `campaigns_completed_success > 0` in 20%+ of games

### Phase 3
- [ ] `goap_invasion_plans > 0` in 50%+ of games
- [ ] Plan execution logs show action conversion
- [ ] Conquest rate: 50-70% of games

### Overall
- [ ] Increase conquest rate from 0% to 50-70% in Act 3-4 games
- [ ] Reduce hoarding (treasury deficit → productive military spending)

---

## Additional Notes

### Why This Bug Wasn't Caught Earlier

1. **ViewWorld exists for a reason:** Early-game safe exploration without orbital approach risk
2. **Function name ambiguity:** `generateReconnaissanceOrders()` sounds generic
3. **Comment was misleading:** "safer, no orbital approach" made sense for reconnaissance
4. **Logs didn't show order type:** Only showed "Reconnaissance - fleet X → system Y"
5. **No direct SpyPlanet metric:** CSV only tracks spy_planet/hack_starbase totals

### Historical Context

Looking at exploration_ops.nim:
- Line 174 uses ViewWorld for reconnaissance (Acts 2-4)
- Line 52 uses Move for exploration (Act 1)
- Neither generates SpyPlanet orders

The intelligence_distribution.nim (lines 264-290) identifies SpyPlanet targets and recommends them, but Domestikos execution uses ViewWorld instead.

**Design intent vs. implementation mismatch.**

---

## Testing Plan (Post-Fix)

```bash
# 1. Apply fix
# Edit exploration_ops.nim line 174

# 2. Rebuild
nimble buildSimulation

# 3. Quick test - single game with logging
./bin/run_simulation -s 99999 -t 35 --fixed-turns --log-level INFO 2>&1 | \
  grep -E "(Colony Analyzer|TARGET IDENTIFIED|vulnerable)" > invasion_test.log

# 4. Check metrics
python3 << 'EOF'
import csv
with open('balance_results/diagnostics/game_99999.csv', 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        if int(row['vulnerable_targets_count']) > 0:
            print(f"Turn {row['turn']}, {row['house']}: {row['vulnerable_targets_count']} vulnerable targets")
EOF

# 5. Batch test
python3 scripts/run_balance_test_parallel.py --workers 8 --games 20 --turns 35

# 6. Analyze conquest rate
python3 << 'EOF'
import csv
import glob
conquests = 0
games = 0
for f in glob.glob('balance_results/diagnostics/game_*.csv'):
    with open(f) as csvfile:
        reader = csv.DictReader(csvfile)
        rows = list(reader)
        final_turn = max(int(r['turn']) for r in rows)
        for row in rows:
            if int(row['turn']) == final_turn:
                games += 1
                if int(row['colonies_gained_via_conquest']) > 0:
                    conquests += 1
                    break
print(f"Conquest rate: {conquests}/{games//4} games = {conquests/(games//4)*100:.1f}%")
EOF
```

---

## Commit Message (When Fix Applied)

```
fix: Use SpyPlanet for reconnaissance to enable invasion planning

Problem: Zero conquests despite complete 3-phase invasion system
Root cause: generateReconnaissanceOrders() used ViewWorld instead of SpyPlanet

ViewWorld provides basic visibility but doesn't populate colonyReports table.
Without detailed intelligence, vulnerableTargets stays empty, blocking:
- Phase 1 threshold targeting
- Phase 2 campaign creation
- Phase 3 GOAP invasion goals

Fix: Change exploration_ops.nim:174 to use FleetOrderType.SpyPlanet

This enables:
- Colony intelligence gathering
- Vulnerable target identification
- Multi-turn invasion campaigns
- GOAP strategic invasion planning

Expected impact: Conquest rate 0% → 50-70% in Act 3-4 games

See: docs/ai/dev-log/2025-12-11-invasion-planning-breakthrough.md
```

---

## References

- **Plan file:** `/home/mag/.claude/plans/sequential-hatching-graham.md`
- **Phase 1 commit:** 17f6003
- **Phase 2 commit:** 06e086c
- **Phase 3 commits:** 6321c5b, de61649
- **Bug file:** `src/ai/rba/domestikos/exploration_ops.nim:174`
- **Intelligence system:** `src/ai/rba/drungarius/intelligence_distribution.nim:264-290`
- **Colony analyzer:** `src/ai/rba/drungarius/analyzers/colony_analyzer.nim:42-104`

---

**Status:** Ready for implementation when user returns to task.
