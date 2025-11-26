# EC4X Rule-Based AI Bootstrap & Gap Analysis Guide
(How to find everything you’re missing before training the neural net)

## Why Bootstrapping Exposes Gaps
Running thousands of games with your current rule-based AI is the fastest, most reliable way to surface hidden flaws in a complex 4X engine. Every unresolved capacity violation, every failed Raider ambush, every unused mothballed fleet is a direct signal of a missing strategic rule.

The goal is not perfection — it is to eliminate systematic, repeatable stupidity before the neural network learns to copy it.

## Core Diagnostic Simulation Harness
Enhance `tests/balance/run_simulation.nim` → `run_diagnostics.nim`

### Key Metrics to Track (log per house, per turn, per game)
| Category          | Metric                                      | Red-Flag Threshold          |
|-------------------|---------------------------------------------|-----------------------------|
| Economy           | PU growth stagnation                        | < 5 PU/turn after turn 30   |
|                   | Treasury hoarding / zero-treasury stalls    | > 30 % turns with 0 spend   |
| Military          | Space-phase failure rate (no scouts)        | > 25 %                      |
|                   | Orbital/planetary failure despite space win| > 40 %                      |
|                   | Raider ambush success rate                  | < 35 % when CLK > ELI       |
| Logistics         | Capacity violations unresolved after grace  | Any                         |
|                   | Fighter disband rate due to over-capacity   | > 5 % of total fighters     |
|                   | Idle carriers (0 fighters loaded)           | > 20 % of carrier fleet     |
| Intel / Tech      | ELI mesh < 3 scouts on invasion fleets     | > 50 % of major attacks     |
|                   | CLK researched but no Raider production    | Ever                        |
|                   | SpyPlanet / HackStarbase missions issued    | 0 in entire game            |
| Defense           | Colonies with no guard/reserve layer        | > 30 % of owned colonies   |
|                   | Mothballed fleets never used                | 0 mothballs in winning games|
| Orders            | Invalid / ignored orders per turn           | > 2 %                       |

## Targeted Stress-Test Scenarios
Force the AI into corners it normally avoids.

| Scenario                     | Setup                                      | Expected Correct Behavior                     |
|------------------------------|--------------------------------------------|-----------------------------------------------|
| Capacity Crisis              | Turn 15: halve all PU on owned colonies    | Immediate starbase + carrier load + transfers |
| Raider Trap                  | Enemy has max ELI + starbases              | Switch to conventional fleets or heavy scouts |
| Fighter Overproduction       | Give max FD/ACO early                      | Proactive starbases + carrier shuffling       |
| Scoutless Invasion           | Send fleet with 0 scouts vs guarded planet | Abort or delay until scouts available         |
| Grace-Period Destruction     | Destroy starbases turn 1 of war            | Resolve within 2 turns (any method)           |
| Blockade War                 | High-value enemy trade lanes visible       | Patrol + blockade orders issued               |

## Likely Missing Strategic Rules (Beyond Your Phase 2 List)
| Gap                                 | Symptom in Simulations                          | Fix Priority |
|-------------------------------------|--------------------------------------------------|--------------|
| Espionage mission selection         | Zero SpyPlanet/HackStarbase ever used           | High         |
| Role-based ROE (patrol vs guard)    | All fleets have same aggression                 | High         |
| Tech synergy chains (FD → ACO)      | FD researched but ACO delayed/indefinite        | High         |
| Blockade & economic warfare         | Ignores enemy supply lanes                      | Medium       |
| Prestige victory path               | Never builds monuments or pursues prestige      | Medium       |
| Late-game fleet mothballing logic  | Keeps full maintenance on 50+ ship fleets       | High         |
| Multi-player threat assessment      | Attacks strongest player instead of weakest    | Medium       |
| Fallback system designation        | Fleets fight to death with no retreat target    | High         |

## Milestones Before Full Bootstrap Generation

### Milestone 1 — Diagnostic Infrastructure
- [ ] Add per-house, per-turn metric logging
- [ ] Run 2,000 diagnostic games (small maps, 50-turn limit)
- [ ] Generate summary dashboard (Python/Pandas or simple CSV → Excel)

### Milestone 2 — First Gap Sweep
- [ ] Fix top 3 red-flag metrics from diagnostics
- [ ] Implement 5 stress-test scenarios
- [ ] Re-run diagnostics → confirm improvement

### Milestone 3 — Strategic Rule Completion
- [ ] Close all High-priority gaps above
- [ ] Verify every stress scenario now passes
- [ ] Manual playtest 20 full games → note remaining “dumb” moments

### Milestone 4 — Final Validation
- [ ] Run 500 full-length games
- [ ] Target thresholds:
    - < 2 % unresolved capacity violations
    - > 60 % successful Raider ambushes when CLK advantage exists
    - Mothballing used in > 70 % of winning late-game positions
    - Espionage missions in > 80 % of games
- [ ] If all green → proceed to 10,000-game bootstrap dataset

### Milestone 5 — Generate Production Bootstrap
- [ ] Run final 10,000+ games with enhanced rule-based AI
- [ ] Export 1.5M+ high-quality state-action-outcome examples
- [ ] Split train/validation, store in `training_data/bootstrap/`

## Final Note
Your current 2,800-line rule-based AI is already far above average. These diagnostics will turn it from “very good” to “excellent teacher” for the neural network. Every flaw you fix now compounds through every self-play iteration later.

Run the diagnostics. Let the numbers tell you exactly what’s missing. Then fix it.

The neural net will thank you.

— Updated November 24, 2025 