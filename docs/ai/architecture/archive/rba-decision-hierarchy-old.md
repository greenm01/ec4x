# RBA Decision Hierarchy & Information Flow Architecture

**Last Updated:** 2025-12-06 (Gaps 4, 5, 6 + Unit Construction RESOLVED)
**System:** Rule-Based Advisor (RBA) - Byzantine Imperial Government
**Location:** `src/ai/rba/`

---

## Table of Contents

1. [System Overview](#system-overview)
2. [Byzantine Imperial Government Structure](#byzantine-imperial-government-structure)
3. [Advisor Hierarchy & Roles](#advisor-hierarchy--roles)
4. [Information Flow Architecture](#information-flow-architecture)
5. [Decision Making Process](#decision-making-process)
6. [Feedback Loops](#feedback-loops)
7. [Cross-Advisor Interactions](#cross-advisor-interactions)
8. [GOAP Integration (Future)](#goap-integration-future)

---

## System Overview

The RBA system implements a **Byzantine Imperial Government** structure with 6 specialized advisors coordinated by a Basileus (Emperor). The system uses a **5-phase process** with **iterative feedback loops** for budget-constrained decision making.

### Core Design Principles

1. **Separation of Concerns** - Each advisor specializes in one domain
2. **Centralized Mediation** - Basileus resolves competing priorities
3. **Budget Constraints** - Treasurer enforces fiscal discipline
4. **Negative Feedback Control** - Iterative reprioritization until convergence
5. **Intelligence-Driven** - All decisions informed by unified intelligence

### Key Files

```
src/ai/rba/
├── controller.nim              # Strategy profiles & initialization
├── controller_types.nim        # Type definitions (advisors, requirements)
├── orders.nim                  # Main orchestrator (5-phase process)
├── budget.nim                  # Treasurer (CFO) - budget allocation & fulfillment
├── orders/
│   ├── phase0_intelligence.nim # Intelligence gathering & distribution
│   ├── phase1_requirements.nim # Multi-advisor requirement generation
│   ├── phase1_5_goap.nim       # GOAP strategic planning (future)
│   ├── phase2_mediation.nim    # Basileus mediation & budget allocation
│   ├── phase3_execution.nim    # Order execution
│   └── phase4_feedback.nim     # Feedback loop & reprioritization
├── domestikos/                 # Military advisor
├── logothete/                  # Research advisor
├── drungarius/                 # Intelligence advisor
├── eparch/                     # Economic advisor
├── protostrator/               # Diplomacy advisor
└── treasurer/                  # Budget advisor (CFO)
```

---

## Byzantine Imperial Government Structure

### Organizational Hierarchy

```
                           ┌─────────────────┐
                           │    BASILEUS     │
                           │   (Emperor)     │
                           │  [Orchestrator] │
                           └────────┬────────┘
                                    │
                  ┌─────────────────┼─────────────────┐
                  │                 │                 │
            [Intelligence]    [Mediation]      [Execution]
                  │                 │                 │
                  ▼                 ▼                 ▼
         ┌────────────────┐ ┌──────────────┐ ┌──────────────┐
         │  DRUNGARIUS    │ │  TREASURER   │ │  DOMESTIKOS  │
         │ (Intelligence) │ │    (CFO)     │ │  (Military)  │
         └────────────────┘ └──────────────┘ └──────────────┘
                                    │                 │
                  ┌─────────────────┼─────────────────┤
                  │                 │                 │
         ┌────────▼────────┐ ┌──────▼──────┐ ┌───────▼──────┐
         │   LOGOTHETE     │ │   EPARCH    │ │ PROTOSTRATOR │
         │   (Research)    │ │  (Economy)  │ │  (Diplomacy) │
         └─────────────────┘ └─────────────┘ └──────────────┘
```

### Power Structure

- **Basileus** - Strategic coordinator, does not make decisions directly
- **Drungarius** - Intelligence hub, informs all advisors
- **Treasurer** - Budget gatekeeper, approves/denies spending
- **Domain Advisors** - Generate requirements, execute orders

---

## Advisor Hierarchy & Roles

### Advisor Roles Table

| Advisor | Type | Primary Role | Inputs | Outputs | Budget Authority |
|---------|------|--------------|--------|---------|------------------|
| **Basileus** | Coordinator | Orchestrates 5-phase process | Game state, all advisor requirements | Order packet, feedback signals | Delegates to Treasurer |
| **Drungarius** | Intelligence | Gathers & distributes intelligence | Fog-of-war view, house history | IntelligenceSnapshot | Requests EBP/CIP funding |
| **Treasurer** | Budget | Allocates budgets, fulfills requirements | Requirements from all advisors, treasury | Per-advisor budgets, feedback | **Full authority** |
| **Domestikos** | Military | Fleet operations, military production | Intelligence, threats, fleet status | BuildRequirements, FleetOrders | Requests PP from Treasurer |
| **Logothete** | Research | Technology advancement | Tech tree, intelligence, Act | ResearchRequirements | Requests RP from Treasurer |
| **Eparch** | Economy | Infrastructure, terraforming | Colonies, production capacity | EconomicRequirements | Requests PP from Treasurer |
| **Protostrator** | Diplomacy | Treaties, proposals, relations | House standings, war status | DiplomaticActions | No budget (free actions) |

### Requirement Priority Levels

```nim
RequirementPriority = enum
  Critical,  # Essential for survival (undefended homeworld)
  High,      # Important for strategy (expansion, key defense)
  Medium,    # Useful but not urgent (infrastructure, balanced builds)
  Low,       # Nice-to-have (capacity fillers, opportunistic)
  Deferred   # Previously unfulfilled, downgraded
```

**Priority Semantics:**
- **Critical** - Always funded if treasury > 0 (emergency defense)
- **High** - Funded after Critical, before Medium (strategic needs)
- **Medium** - Balanced allocation (standard operations)
- **Low** - Funded if budget remains (capacity utilization)
- **Deferred** - Reprioritized from unfulfilled requirements (feedback loop)

---

## Information Flow Architecture

### Vertical Information Flow (Hierarchy)

```
UPWARD FLOW (Requirements & Feedback)
=======================================

Turn N:
  Drungarius → Intelligence Snapshot
       ↓
  All Advisors → Requirements (prioritized)
       ↓
  Basileus → Aggregate requirements
       ↓
  Treasurer → Budget allocation (per-advisor)
       ↓
  Treasurer → Fulfillment feedback (fulfilled/unfulfilled)
       ↓
  Basileus → Reprioritization signal (if unfulfilled Critical/High)
       ↓
  All Advisors → Adjust priorities
       ↓
  [Loop 2-3 iterations until convergence]


DOWNWARD FLOW (Budgets & Orders)
=======================================

Turn N:
  Treasurer → Per-advisor budget allocations
       ↓
  Domestikos → BuildOrders (ships, ground units, facilities)
       ↓
  Logothete → ResearchAllocation (ERP/SRP/TRP)
       ↓
  Drungarius → EspionageAction (operations, EBP/CIP)
       ↓
  Eparch → TerraformOrders, population transfers
       ↓
  Protostrator → DiplomaticActions (treaties, proposals)
       ↓
  Engine → Execute orders (turn resolution)
```

### Horizontal Information Flow (Cross-Advisor)

```
INTELLIGENCE DISTRIBUTION (Phase 0)
======================================

        ┌──────────────────────────────────────┐
        │         DRUNGARIUS HUB               │
        │  Collects: Threats, Opportunities,   │
        │  Systems, Fleets, Construction       │
        └──────────────┬───────────────────────┘
                       │
         ┌─────────────┼─────────────┐
         │             │             │
         ▼             ▼             ▼
   [Domestikos]  [Logothete]   [Eparch]
   - Threats     - Tech gaps   - Production
   - Fleets      - Research    - Colonies
                   priorities


BUDGET MEDIATION (Phase 2)
======================================

   Domestikos ──┐
                │
   Logothete ──→│  TREASURER (Basileus delegate)
                │  - Weighs priorities
   Drungarius ──│  - Allocates by personality
                │  - Enforces constraints
   Eparch ──────┘
                │
                └──→ Per-advisor budgets


FEEDBACK COORDINATION (Phase 4)
======================================

   Treasurer → Unfulfilled list
                │
                ├──→ Domestikos (reprioritize builds)
                ├──→ Logothete (reprioritize research)
                ├──→ Drungarius (reprioritize espionage)
                └──→ Eparch (reprioritize infrastructure)
```

---

## Decision Making Process

### 5-Phase Cycle (Per Turn)

```
┌──────────────────────────────────────────────────────────────┐
│  TURN N - BYZANTINE IMPERIAL GOVERNMENT CYCLE                │
└──────────────────────────────────────────────────────────────┘

PHASE 0: INTELLIGENCE DISTRIBUTION
┌────────────────────────────────────────────────────────────┐
│ Drungarius collects intelligence from fog-of-war view     │
│                                                            │
│ Inputs:  FilteredGameState, house history                 │
│ Process: - Threat assessment (enemy fleets, colonies)     │
│          - Opportunity detection (undefended systems)     │
│          - Construction tracking (enemy builds)           │
│          - Diplomatic events                              │
│ Output:  IntelligenceSnapshot                             │
│                                                            │
│ Distribution: Shared with all advisors                    │
└────────────────────────────────────────────────────────────┘
                            ↓

PHASE 1: MULTI-ADVISOR REQUIREMENT GENERATION
┌────────────────────────────────────────────────────────────┐
│ All 6 advisors generate prioritized requirements          │
│                                                            │
│ DOMESTIKOS:                                                │
│   - BuildRequirements (ships, ground units, facilities)   │
│   - Priority based on: threats, fleet capacity, Act       │
│                                                            │
│ LOGOTHETE:                                                 │
│   - ResearchRequirements (tech fields, ERP/SRP)           │
│   - Priority based on: tech gaps, military needs          │
│                                                            │
│ DRUNGARIUS:                                                │
│   - EspionageRequirements (operations, EBP/CIP)           │
│   - Priority based on: intel gaps, threat level           │
│                                                            │
│ EPARCH:                                                    │
│   - EconomicRequirements (facilities, terraforming)       │
│   - Priority based on: production capacity, colonies      │
│                                                            │
│ PROTOSTRATOR:                                              │
│   - DiplomaticActions (treaties, proposals)               │
│   - Priority based on: relations, strategic position      │
│                                                            │
│ Output: Requirements stored in controller.{advisor}Reqs   │
└────────────────────────────────────────────────────────────┘
                            ↓

[PHASE 1.5: GOAP STRATEGIC PLANNING] - Future
┌────────────────────────────────────────────────────────────┐
│ GOAP extracts strategic goals and generates multi-turn    │
│ plans to inform budget allocation (see GOAP section)       │
└────────────────────────────────────────────────────────────┘
                            ↓

PHASE 2: BASILEUS MEDIATION & BUDGET ALLOCATION
┌────────────────────────────────────────────────────────────┐
│ Treasurer allocates PP budget across advisors              │
│                                                            │
│ Process:                                                   │
│ 1. Calculate projected treasury (current + next turn PP)  │
│ 2. Count Critical/High/Medium requirements per advisor    │
│ 3. Weight by personality (aggression, economicFocus, etc) │
│ 4. Weight by Act (Act 1 = expansion, Act 4 = military)    │
│ 5. Allocate PP proportionally                             │
│                                                            │
│ Formula:                                                   │
│   advisorBudget = treasury × personalityWeight × actWeight│
│                   × (advisorCritical + advisorHigh×0.7    │
│                      + advisorMedium×0.4) / totalWeighted │
│                                                            │
│ Output: MultiAdvisorAllocation                             │
│   - budgets: Table[AdvisorType, int]                      │
│   - treasurerFeedback, scienceFeedback, etc.              │
└────────────────────────────────────────────────────────────┘
                            ↓

PHASE 3/4: EXECUTION & FEEDBACK LOOP (Unified)
┌────────────────────────────────────────────────────────────┐
│ Iterative fulfillment with reprioritization               │
│                                                            │
│ ITERATION 1 (Initial):                                    │
│ ┌────────────────────────────────────────────────────────┐│
│ │ 1. Treasurer processes requirements with budgets       ││
│ │    - Domestikos → BuildOrders (ships, ground units)    ││
│ │    - Logothete → ResearchAllocation                    ││
│ │    - Drungarius → EspionageAction                      ││
│ │    - Eparch → TerraformOrders                          ││
│ │    - Protostrator → DiplomaticActions                  ││
│ │                                                         ││
│ │ 2. Track fulfilled/unfulfilled for each advisor        ││
│ │                                                         ││
│ │ 3. Check convergence:                                  ││
│ │    - IF no unfulfilled Critical/High → DONE            ││
│ │    - ELSE → Continue to Iteration 2                    ││
│ └────────────────────────────────────────────────────────┘│
│                            ↓                               │
│ ITERATION 2-3 (Reprioritization):                         │
│ ┌────────────────────────────────────────────────────────┐│
│ │ 1. Reprioritize unfulfilled requirements:              ││
│ │    - Domestikos: Downgrade expensive/unaffordable      ││
│ │    - Logothete: Defer low-priority research            ││
│ │    - Drungarius: Defer espionage operations            ││
│ │    - Eparch: Defer infrastructure expansion            ││
│ │                                                         ││
│ │ 2. Re-run budget allocation with adjusted priorities   ││
│ │                                                         ││
│ │ 3. Re-execute requirements                             ││
│ │                                                         ││
│ │ 4. Check convergence (max 3 iterations)                ││
│ └────────────────────────────────────────────────────────┘│
│                                                            │
│ Output: OrderPacket with all advisor orders               │
└────────────────────────────────────────────────────────────┘
                            ↓

PHASE 5+: TACTICAL OPERATIONS
┌────────────────────────────────────────────────────────────┐
│ Fleet operations, standing orders, logistics              │
│                                                            │
│ - Strategic operations planning (invasions)               │
│ - Tactical fleet orders (movement, combat)                │
│ - Standing orders execution (patrol, defend)              │
│ - Logistics (fleet composition, repairs)                  │
│                                                            │
│ Output: FleetOrders appended to OrderPacket               │
└────────────────────────────────────────────────────────────┘
                            ↓
                    ┌───────────────┐
                    │ Submit Orders │
                    └───────────────┘
```

### Decision Flowchart: Requirement Fulfillment

```
START: Treasurer processes requirement
         │
         ▼
    ┌─────────────────┐
    │ Check priority  │
    └────────┬────────┘
             │
    ┌────────▼─────────┐
    │ Critical/High?   │
    └────┬─────────┬───┘
         │ Yes     │ No
         │         └──→ [Skip if budget exhausted]
         │                         │
         ▼                         ▼
    ┌──────────────────┐    ┌──────────────┐
    │ Check budget     │    │ Mark deferred│
    └────┬────────┬────┘    └──────────────┘
         │        │
    Yes  │        │ No
         │        └──→ Mark unfulfilled
         │                  │
         ▼                  ▼
    ┌──────────────────┐  [Add to feedback]
    │ Create order     │
    │ Deduct from      │
    │ budget           │
    └────┬─────────────┘
         │
         ▼
    ┌──────────────────┐
    │ Mark fulfilled   │
    └────┬─────────────┘
         │
         ▼
    [Next requirement]


FEEDBACK LOOP DECISION:
========================

    ┌─────────────────────────────┐
    │ After Iteration N           │
    └──────────────┬──────────────┘
                   │
                   ▼
    ┌──────────────────────────────┐
    │ Any Critical/High unfulfilled?│
    └────────┬──────────────┬──────┘
             │ Yes          │ No
             │              └──→ CONVERGED (done)
             │
             ▼
    ┌──────────────────────────┐
    │ Iteration < 3?           │
    └────────┬──────────┬──────┘
             │ Yes      │ No
             │          └──→ MAX ITERATIONS (done)
             │
             ▼
    ┌──────────────────────────┐
    │ Reprioritize:            │
    │ - Downgrade expensive    │
    │ - Mark Low → Deferred    │
    │ - Adjust quantities      │
    └──────────┬───────────────┘
               │
               ▼
    ┌──────────────────────────┐
    │ Re-run budget allocation │
    └──────────┬───────────────┘
               │
               ▼
    [Execute Iteration N+1]
```

---

## Feedback Loops

### Negative Feedback Control System

The RBA implements a **negative feedback control system** to converge on affordable requirements:

```
NEGATIVE FEEDBACK LOOP ARCHITECTURE
====================================

┌────────────────────────────────────────────────────────────┐
│                    CONTROL LOOP                            │
│                                                            │
│  Setpoint: Fulfill all Critical & High requirements       │
│  Measured: Unfulfilled Critical & High requirements        │
│  Error: Number of unfulfilled Critical/High                │
│  Control Action: Reprioritize & reallocate budget          │
└────────────────────────────────────────────────────────────┘

         ┌──────────────────────────────────────┐
         │  ADVISORS (Generate Requirements)    │
         │  - Domestikos, Logothete, etc.       │
         └──────────────┬───────────────────────┘
                        │ Requirements
                        ▼
         ┌──────────────────────────────────────┐
         │  TREASURER (Allocate & Fulfill)      │
         │  Input: Requirements + Budget        │
         │  Output: Fulfilled/Unfulfilled       │
         └──────────────┬───────────────────────┘
                        │ Feedback
                        ▼
         ┌──────────────────────────────────────┐
         │  FEEDBACK COMPARATOR                 │
         │  Check: Any Critical/High unfulfilled?│
         └──────────┬───────────────────────────┘
                    │
         ┌──────────┴──────────┐
         │ Yes                 │ No
         ▼                     ▼
┌───────────────────┐   ┌────────────┐
│ REPRIORITIZATION  │   │ CONVERGED  │
│ (Control Action)  │   │ (Success)  │
│ - Downgrade       │   └────────────┘
│ - Defer           │
│ - Adjust qty      │
└────────┬──────────┘
         │
         └──→ [Loop back to Treasurer]
                (Max 3 iterations)
```

### Feedback Types

| Feedback Type | Source | Target | Information | Action Taken |
|---------------|--------|--------|-------------|--------------|
| **Treasurer Feedback** | Treasurer | Domestikos | Unfulfilled BuildRequirements | Reprioritize builds, reduce quantities |
| **Science Feedback** | Treasurer | Logothete | Unfulfilled ResearchRequirements | Defer low-priority research |
| **Drungarius Feedback** | Treasurer | Drungarius | Unfulfilled EspionageRequirements | Defer operations, reduce EBP/CIP |
| **Eparch Feedback** | Treasurer | Eparch | Unfulfilled EconomicRequirements | Defer infrastructure, terraforming |
| **Intelligence Feedback** | Drungarius | All Advisors | Threat changes, opportunities | Adjust priorities next turn |
| **Fleet Status** | Domestikos | Domestikos | Ship losses, construction completion | Update build requirements |

### Convergence Criteria

```nim
proc hasUnfulfilledCriticalOrHigh(controller: AIController): bool =
  ## Returns true if ANY advisor has unfulfilled Critical or High requirements
  ##
  ## Checked after each feedback iteration to determine if loop continues

  if treasurerFeedback has Critical/High unfulfilled → return true
  if scienceFeedback has Critical/High unfulfilled → return true
  if drungariusFeedback has Critical/High unfulfilled → return true
  if eparchFeedback has Critical/High unfulfilled → return true

  return false  # CONVERGED
```

**Loop Termination:**
- ✅ No Critical/High unfulfilled (success)
- ✅ Max 3 iterations reached (partial success)

---

## Cross-Advisor Interactions

### Lateral Communication Patterns

```
INFORMATION SHARING (Phase 0 → Phase 1)
========================================

Drungarius → All Advisors:
  - IntelligenceSnapshot
    ├─→ Threats (fleet positions, strength)
    ├─→ Opportunities (undefended systems, weak fleets)
    ├─→ Construction (enemy builds in progress)
    ├─→ Diplomatic events
    └─→ System visibility


BUDGET COMPETITION (Phase 2)
========================================

All Advisors → Treasurer:
  - Competing requirements
  - Prioritized by personality & Act
  - Mediated by Basileus logic

         Domestikos: "Need 500 PP for Battleships"
                ↓
         Logothete: "Need 300 PP for Tech VI"
                ↓
         Drungarius: "Need 200 PP for spy ops"
                ↓
         Eparch: "Need 400 PP for Shipyards"
                ↓
         Treasurer mediates → Allocates by priority


COORDINATION (Implicit)
========================================

Domestikos ←→ Eparch:
  - Domestikos requests ships
  - Eparch builds Shipyards/Spaceports
  - Coordination: Domestikos checks dock capacity

Domestikos ←→ Logothete:
  - Domestikos wants advanced ships (Dreadnoughts)
  - Logothete researches CST (Construction Tech)
  - Coordination: Domestikos checks tech requirements

Drungarius ←→ Domestikos:
  - Drungarius identifies invasion opportunities
  - Domestikos plans invasion fleets
  - Coordination: Shared IntelligenceSnapshot
```

### Dependency Matrix

| Advisor | Depends On | Provides To | Conflict With |
|---------|------------|-------------|---------------|
| **Drungarius** | (none) | Intelligence → All | Treasurer (budget) |
| **Domestikos** | Intel, Tech, Facilities | Fleet status → Drungarius | Logothete, Eparch (budget) |
| **Logothete** | Intel | Tech level → Domestikos | Domestikos, Eparch (budget) |
| **Eparch** | Intel, Production | Facilities → Domestikos | Domestikos, Logothete (budget) |
| **Protostrator** | Intel, Relations | Diplomatic state → All | (no budget conflict) |
| **Treasurer** | All requirements | Budgets → All | (mediates conflicts) |

---

## GOAP Integration (Future)

### Hybrid GOAP/RBA Architecture

**Vision:** GOAP handles **strategic planning** (long-term goals), RBA handles **tactical execution** (turn-by-turn operations).

```
GOAP STRATEGIC LAYER (Phase 1.5)
=================================

         ┌──────────────────────────────────────┐
         │  GOAP PLANNER                        │
         │  Input: World state, Requirements    │
         │  Output: Multi-turn plans            │
         └──────────────┬───────────────────────┘
                        │
         ┌──────────────▼───────────────────────┐
         │  Strategic Goals:                    │
         │  - "Conquer System 42" (5 turns)     │
         │  - "Tech to CST VI" (3 turns)        │
         │  - "Build 10 Battleships" (4 turns)  │
         └──────────────┬───────────────────────┘
                        │ Cost estimates
                        ▼
         ┌──────────────────────────────────────┐
         │  PHASE 2: MEDIATION (Enhanced)       │
         │  - Treasurer weighs GOAP estimates   │
         │  - Prioritizes aligned requirements  │
         └──────────────┬───────────────────────┘
                        │
                        ▼
         ┌──────────────────────────────────────┐
         │  RBA EXECUTION (Phases 3-5)          │
         │  - Fulfills requirements per plan    │
         │  - Provides feedback to GOAP         │
         └──────────────────────────────────────┘
```

### GOAP Integration Points

| Phase | Current Behavior | With GOAP Enhancement |
|-------|------------------|----------------------|
| **Phase 0** | Drungarius gathers intel | **+GOAP**: Track goal progress, update world state |
| **Phase 1** | Advisors generate requirements | **+GOAP**: Requirements aligned with active goals |
| **Phase 1.5** | (not implemented) | **GOAP**: Extract goals, generate multi-turn plans, estimate costs |
| **Phase 2** | Treasurer allocates by personality/Act | **+GOAP**: Weight by goal priority, use cost estimates |
| **Phase 3/4** | Execute & feedback loop | **+GOAP**: Track plan execution, update goal states |
| **Phase 5** | Tactical operations | **+GOAP**: Fleet movements aligned with strategic goals |

### Decision Authority Split

```
GOAP (STRATEGIC)               RBA (TACTICAL)
==================             ==================
✓ Long-term goals              ✓ Turn-by-turn orders
✓ Multi-turn plans             ✓ Budget allocation
✓ Goal prioritization          ✓ Requirement fulfillment
✓ Resource allocation          ✓ Fleet operations
  (strategic)                    (immediate)
✓ Plan tracking                ✓ Standing orders
✓ Goal success/failure         ✓ Emergency response


DECISION FLOW WITH GOAP:
=========================

GOAP: "To conquer System 42, need:"
  - Turn 1: Build 5 Destroyers (200 PP)
  - Turn 2: Build 2 Carriers (240 PP)
  - Turn 3: Build 10 Marines (500 PP)
  - Turn 4: Move fleet to System 42
  - Turn 5: Invade with Marines

         ↓

RBA Phase 1.5: GOAP provides cost estimates
         ↓
RBA Phase 2: Treasurer allocates 200 PP to Domestikos (Turn 1)
         ↓
RBA Phase 3: Domestikos builds 5 Destroyers
         ↓
[Next turn]
         ↓
RBA Phase 2: Treasurer allocates 240 PP (Turn 2)
         ↓
...continues until goal complete
```

### Information Flow Changes

**Current (RBA Only):**
```
Intel → Requirements → Allocation → Execution → Feedback → Reprioritize
```

**Future (GOAP + RBA):**
```
Intel → GOAP Goals → Multi-turn Plan → Cost Estimates
                          ↓
                    Requirements (goal-aligned)
                          ↓
                    Allocation (goal-weighted)
                          ↓
                    Execution → Feedback
                          ↓
                    GOAP: Update goal progress
                          ↓
                    GOAP: Replan if needed
```

### Cross-System Feedback

| Feedback Type | Direction | Purpose |
|---------------|-----------|---------|
| **Goal Progress** | RBA → GOAP | "Built 5/10 Battleships for Goal X" |
| **Plan Failure** | RBA → GOAP | "Couldn't afford Marines, replan" |
| **Opportunity** | RBA → GOAP | "Enemy fleet destroyed, update goal priority" |
| **Cost Estimate** | GOAP → RBA | "Invasion needs 500 PP over 3 turns" |
| **Goal Alignment** | GOAP → RBA | "Requirement R aligns with Goal G (priority boost)" |
| **Emergency Override** | RBA → GOAP | "Homeworld attacked, suspend offensive goals" |

---

## Summary

### Key Takeaways

1. **Hierarchical Structure** - Basileus coordinates 6 specialized advisors
2. **Intelligence-Driven** - Drungarius provides unified intelligence to all
3. **Budget-Constrained** - Treasurer enforces fiscal discipline
4. **Iterative Feedback** - 3-iteration loop converges on affordable requirements
5. **Priority-Based** - Critical > High > Medium > Low > Deferred
6. **GOAP Ready** - Architecture supports future strategic planning layer

### Strengths

- ✅ Clear separation of concerns
- ✅ Robust feedback loops for budget constraints
- ✅ Extensible (easy to add new advisor capabilities)
- ✅ Intelligence-driven decision making
- ✅ Configurable via personality weights

### Future Enhancements

- 🔄 **GOAP Integration** - Strategic goal planning (Phase 1.5)
- 🔄 **Cross-Advisor Coordination** - Explicit dependencies (e.g., Domestikos waits for Eparch Shipyards)
- 🔄 **Multi-Turn Planning** - Requirements can span multiple turns
- 🔄 **Risk Assessment** - Confidence scores for decisions
- 🔄 **Diagnostic Tracking** - Better visibility into advisor decision making

---

## Gap Analysis

**Analysis Date:** 2025-12-06
**Identified During:** Architecture documentation review

### Critical Gaps (Block Progress)

#### 1. No Multi-Turn Planning ⚠️

**Gap:** All requirements are single-turn only. Cannot express "I need X in 3 turns, start now."

**Example:**
```
Current: "Build Dreadnought NOW" (requires 200 PP this turn)
Needed:  "Start Dreadnought, pay 50 PP/turn over 4 turns"
```

**Impact:**
- Expensive ships (Battleships, Dreadnoughts, SuperDreadnoughts) rarely built
- Treasury hoarding to accumulate full cost
- Inefficient budget utilization (all-or-nothing spending)
- Production capacity underutilized

**Resolution:** GOAP Phase 1.5 will provide multi-turn plans with incremental costs

---

#### 2. No Emergency Response System ⚠️

**Gap:** Cannot CANCEL all requirements and divert to crisis response.

**Example:**
```
Turn 10: Homeworld under attack by 20 Battleships
Current: Domestikos still has expansion requirements (ETACs, Scouts)
Needed:  "DROP EVERYTHING, BUILD DEFENSE NOW"
```

**Impact:**
- Cannot respond to existential threats mid-turn
- Requirements from Phase 1 are fixed for entire turn
- AI continues peaceful expansion while homeworld burns

**Current Workaround:** Next turn will generate defensive requirements (too late?)

**Resolution:** Emergency mode that regenerates requirements:
```nim
if homeworld.isCriticallyThreatened:
  cancelAllRequirements()
  generateEmergencyDefenseRequirements()
  allocation = allocateFullTreasuryToDefense()
```

---

#### 3. No Explicit Cross-Advisor Coordination ⚠️

**Gap:** Advisors cannot REQUEST things from each other, only compete for budget.

**Example:**
```
Domestikos: Wants to build Dreadnoughts → requires CST V
Logothete: No idea Domestikos urgently needs CST V
Result:     Independent requirements, no coordination
```

**Current State:**
- Implicit coordination through personality weights
- Aggressive AI → higher Domestikos budget → more ships → Logothete eventually researches CST
- No explicit dependency declarations

**Better Solution:**
```nim
BuildRequirement(
  shipClass: Dreadnought,
  dependencies: @[TechRequirement(field: CST, level: 5)],
  reason: "Cannot build without CST V (currently CST III)"
)
```

**Impact:**
- Inefficient resource allocation
- Tech research doesn't align with military needs
- Domestikos builds ships it can't use yet

---

### Important Gaps (Reduce Effectiveness)

#### 4. ✅ Weak Reprioritization Logic (RESOLVED)

**Status:** ✅ **COMPLETED** (2025-12-06)

**Gap:** Phase 4 reprioritization was simplistic (just downgrade priorities).

**Solution Implemented:**
- **Iteration-aware strategy:** Quantity adjustment (Iteration 1) → Substitution (Iterations 2-3)
- **Quantity adjustment:** Reduce requirement quantities by 50% (min 1 unit)
- **Substitution logic:** Find cheaper ship alternatives with 60% cost threshold
- **CST-aware:** Respects tech requirements when suggesting alternatives
- **Act-appropriate:** Substitutions maintain role appropriateness (Capital → Capital, Escort → Escort)

**Implementation:**
- `src/ai/rba/domestikos/requirements/reprioritization.nim` - Enhanced reprioritization
  - `tryQuantityAdjustment()` - 50% reduction with configurable minimum
  - `trySubstitution()` - Cheaper alternatives with cost threshold
  - `reprioritizeRequirements()` - Iteration-aware strategy
- `src/ai/rba/eparch/requirements.nim` - Real Eparch reprioritization
  - Escalation: Medium (10 turns) → High → Critical (20 turns)
  - Downgrade expensive unfulfilled High → Medium (>30% treasury)
  - Exception: Never downgrade Spaceport requirements below High

**Configuration:**
```toml
[reprioritization]
enable_quantity_adjustment = true
min_quantity_reduction = 1
enable_substitution = true
max_cost_reduction_factor = 0.6  # 60% threshold
facility_critical_to_high_turns = 10
facility_high_to_medium_turns = 20
```

**Validation Results:**
- Convergence rate: 100.0% (96/96 games completed without unfulfilled Critical/High)
- 38 unit tests passing (13 reprioritization-specific tests)

**Files Modified:**
- `src/ai/rba/domestikos/requirements/reprioritization.nim` - Enhanced logic
- `src/ai/rba/eparch/requirements.nim` - Implemented real reprioritization
- `src/ai/rba/orders/phase4_feedback.nim` - Added CST parameter
- `src/ai/rba/orders.nim` - Pass CST level to reprioritization
- `config/rba.toml` - Added reprioritization config section
- `src/ai/rba/config.nim` - Added ReprioritizationConfig type

**Impact:**
- ✅ Smarter budget adjustments using iteration-aware strategy
- ✅ Substitution prevents complete failure (build something affordable)
- ✅ Quantity adjustment enables partial fulfillment
- ✅ 100% convergence rate in validation tests

---

#### 5. ✅ Standing Orders Disconnected from Requirements (RESOLVED)

**Status:** ✅ **COMPLETED** (2025-12-06)

**Gap:** Standing orders (patrol, defend) didn't inform requirement generation.

**Solution Implemented:**
- **Defense history persistence:** Track `turnsUndefended` per colony
- **Standing order query API:** Expose active defense assignments
- **Standing order support requirements:** Generate High-priority builds for undefended systems with DefendSystem orders
- **Priority escalation:** 5 turns undefended → High, 10 turns → Critical
- **Capacity filler biasing:** Add defender ships to 20-slot rotation based on undefended systems

**Implementation:**
- `src/ai/rba/controller_types.nim` - Added ColonyDefenseHistory type
  - `turnsUndefended: int` - Incremented each turn colony undefended
  - `lastDefenderAssigned: int` - Reset when defender present
  - Stored in `AIController.defenseHistory: Table[SystemId, ColonyDefenseHistory]`
- `src/ai/rba/standing_orders_manager.nim` - Added query procs
  - `getActiveDefenseOrders()` - Returns DefenseAssignment seq
  - `getUndefendedSystemsWithOrders()` - Systems with orders but no defenders
- `src/ai/rba/domestikos/requirements/standing_order_support.nim` - NEW MODULE
  - `updateDefenseHistory()` - Track defense status per turn
  - `generateStandingOrderSupportRequirements()` - Build defenders for undefended systems
  - `biasFillerTowardsDefenders()` - Adjust 20-slot rotation for defense needs
  - `getDefenderClassForAct()` - Act-appropriate defender selection

**Configuration:**
```toml
[standing_orders_integration]
generate_support_requirements = true
defense_gap_priority_boost = 1
filler_standing_order_bias = 0.3  # 30% of fillers = defenders
track_colony_defense_history = true
max_history_entries = 50
```

**Validation Results:**
- Standing order compliance: 69.3% (target 70%, near-miss)
- Average undefended colony rate: 30.7%
- 38 unit tests passing (integration tests included)

**Files Modified:**
- `src/ai/rba/controller_types.nim` - Added ColonyDefenseHistory, DefenseAssignment
- `src/ai/rba/standing_orders_manager.nim` - Added query API
- `src/ai/rba/domestikos/requirements/standing_order_support.nim` - NEW (250 lines)
- `config/rba.toml` - Added standing_orders_integration section
- `src/ai/rba/config.nim` - Added StandingOrdersIntegrationConfig type

**Impact:**
- ✅ Defense requirements now aligned with standing orders
- ✅ Colony defense history persistence enables priority escalation
- ✅ Capacity fillers biased towards defenders when needed
- ✅ 69.3% defended colony rate (just 0.7% below 70% target)

---

#### 6. ✅ Limited Feedback Information (RESOLVED)

**Status:** ✅ **COMPLETED** (2025-12-06)

**Gap:** Treasurer only reported "unfulfilled" but not WHY.

**Solution Implemented:**
- **Unfulfillment reason tracking:** 7 reason types (InsufficientBudget, PartialBudget, ColonyCapacityFull, TechNotAvailable, NoValidColony, BudgetReserved, SubstitutionFailed)
- **Cost gap analysis:** Track budget shortfall per requirement
- **Substitution suggestions:** Generate human-readable suggestions for cheaper alternatives
- **Quantity built tracking:** Record partial fulfillment progress

**Implementation:**
- `src/ai/rba/controller_types.nim` - Added feedback types
  - `UnfulfillmentReason` - Enum with 7 reason types
  - `RequirementFeedback` - Detailed per-requirement feedback
  - Extended `TreasurerFeedback.detailedFeedback: seq[RequirementFeedback]`
- `src/ai/rba/treasurer/budget/feedback.nim` - NEW MODULE
  - `getCheaperAlternatives()` - Find affordable ship substitutes
  - `generateSubstitutionSuggestion()` - Human-readable suggestions
  - `generateRequirementFeedback()` - Full diagnostic per requirement
  - Role-based substitution (Capital → Capital, Escort → Escort)
  - CST-aware filtering (only suggest tech-available ships)

**Configuration:**
```toml
[feedback_system]
enabled = true
suggest_cheaper_alternatives = true
min_partial_fulfillment_ratio = 0.25
```

**Example Feedback:**
```nim
RequirementFeedback(
  requirement: BuildRequirement(shipClass: Battleship, quantity: 2),
  reason: InsufficientBudget,
  budgetShortfall: 300,  # Need 500 PP, have 200 PP
  quantityBuilt: 0,
  suggestion: "Consider Cruiser (150 PP) or reduce quantity to 1"
)
```

**Validation Results:**
- Feedback generation score: 75.0%
- 38 unit tests passing (17 feedback-specific tests)
- All 7 unfulfillment reasons tested

**Files Modified:**
- `src/ai/rba/controller_types.nim` - Added UnfulfillmentReason, RequirementFeedback
- `src/ai/rba/treasurer/budget/feedback.nim` - NEW (235 lines)
- `config/rba.toml` - Added feedback_system section
- `src/ai/rba/config.nim` - Added FeedbackSystemConfig type

**Impact:**
- ✅ Phase 4 reprioritization now has actionable diagnostic data
- ✅ Substitution suggestions enable smart fallbacks
- ✅ Cost gap tracking enables precise budget adjustments
- ✅ 17 unit tests validate all feedback scenarios

---

#### 7. No Resource Reservations

**Gap:** Cannot reserve budget for future turns.

**Example:**
```
Turn 5: "I'll need 500 PP on Turn 6 for critical invasion"
Turn 6: Eparch spent 400 PP on terraforming
Result:  Only 100 PP left, invasion cancelled
```

**Current State:** Each turn is independent, no memory of future needs

**Impact:**
- Multi-turn operations unreliable
- Cannot commit to plans spanning turns
- Budget competition is myopic (single-turn horizon)

**Workaround Until GOAP:** High priority requirements tend to get funded first

---

---

### Unit Construction Issues

#### ✅ Capacity Fillers Burying Strategic Requirements (RESOLVED)

**Status:** ✅ **COMPLETED** (2025-12-06)

**Problem:** Capacity fillers (20 Medium priority) buried high-priority requirements (1-5 Critical/High) in budget allocation.

**Root Cause:**
- Domestikos generates 1-5 strategic requirements (Critical/High priority)
- Capacity filler generates 20 filler requirements (Medium/Low priority)
- Treasurer mediation weighs by quantity: 20 Medium > 5 High in aggregate
- Result: Wrong ships built despite correct act-aware scoring

**Solution Implemented:**
- **Strategic budget:** 80-85% reserved for Critical/High requirements
- **Filler budget:** 15-20% reserved for capacity utilization (20-slot rotation)
- **Act-specific reservations:** Act 1 = 20% filler, Acts 2-4 = 15% filler
- **Execution order:** Process Critical/High first with strategic budget, then fillers with filler budget

**Implementation:**
- `src/ai/rba/treasurer/budget/splitting.nim` - NEW MODULE
  - `splitStrategicAndFillerBudgets()` - Separate budget pools by Act
  - `getStrategicBudgetForObjective()` - Query strategic allocation
  - `hasFillerBudgetRemaining()` - Check filler budget availability
  - `getFillerBudgetRemaining()` - Query remaining filler budget
- `config/rba.toml` - Added filler_budget_reserved to all 4 Act sections
  - Act 1: `filler_budget_reserved = 0.20` (20% reserved for capacity utilization)
  - Acts 2-4: `filler_budget_reserved = 0.15` (15% reserved)

**Configuration:**
```toml
[budget_act1_land_grab]
filler_budget_reserved = 0.20  # 20% for capacity fillers

[budget_act2_rising_tensions]
filler_budget_reserved = 0.15  # 15% for capacity fillers

[budget_act3_open_war]
filler_budget_reserved = 0.15

[budget_act4_end_game]
filler_budget_reserved = 0.15
```

**Validation Results:**
- Unit mix accuracy: 100.0% (9,087 ships built across 96 games)
- Act-appropriate distribution validated:
  - Act 1: 3,589 ships (37.4 per game)
  - Act 2: 5,498 ships (57.3 per game)
- Budget utilization: 47.1% (proxy metric, good throughput)

**Files Modified:**
- `src/ai/rba/treasurer/budget/splitting.nim` - NEW (93 lines)
- `config/rba.toml` - Added filler_budget_reserved to 4 Act sections
- `src/ai/rba/config.nim` - Added field to BudgetAllocationConfig

**Impact:**
- ✅ Strategic requirements no longer buried by capacity fillers
- ✅ Act-appropriate unit progression validated (100% accuracy)
- ✅ High-priority builds funded before Medium fillers
- ✅ 8 unit tests validate budget splitting logic

---

### Nice-to-Have Gaps (Quality of Life)

#### 8. No Risk Assessment

**Gap:** Requirements have no confidence or risk scores.

**Example:**
```
"Build 10 Battleships" (high risk: expensive, long build time, may not complete)
"Build 10 Destroyers" (low risk: cheap, fast, reliable)
Both treated equally by Treasurer
```

**Better Solution:**
```nim
BuildRequirement(
  priority: High,
  confidence: 0.8,  # 80% confident this is optimal move
  risk: 0.3         # 30% risk of failure/waste
)
```

**Use Cases:**
- Budget allocation weighs risk vs reward
- High-risk requirements get funded only if high confidence
- Risk-averse personalities prefer low-risk requirements

---

#### 9. ✅ No Diagnostic Visibility into Advisor Reasoning (RESOLVED)

**Status:** ✅ **COMPLETED** (2025-12-06)

**Gap:** Cannot see WHY advisors made specific decisions.

**Solution Implemented:**
- Added `advisorReasoning: string` field to DiagnosticMetrics
- CSV now includes `advisor_reasoning` column (153 total columns)
- Orchestrator builds structured reasoning log from order packets
- Future: Advisors will emit reasoning directly (currently post-hoc extraction)

**Example CSV Output:**
```csv
advisor_reasoning
"DOMESTIKOS: 2 ships, 1 ground, 0 facilities..."
```

**Files Modified:**
- `src/ai/analysis/diagnostics/types.nim` - Added field
- `src/ai/analysis/diagnostics/orchestrator.nim` - buildReasoningLog()
- `src/ai/analysis/diagnostics/csv_writer.nim` - CSV column

**Impact:**
- ✅ Can now track advisor decision rationales per turn
- ✅ Balance testing has visibility into AI reasoning
- ✅ Debugging AI behavior is easier

---

#### 10. ✅ Facility Tracking Gap (RESOLVED)

**Status:** ✅ **COMPLETED** (2025-12-06)

**Gap:** Diagnostics reported 0 Shipyards/Spaceports despite homeworlds starting with them.

**Root Cause:** `src/ai/analysis/diagnostics.nim` didn't track facilities (only ships and ground units)

**Solution Implemented:**
- Added `totalSpaceports: int` and `totalShipyards: int` fields
- Tracking implemented in Domestikos collector (military assets domain)
- CSV columns: `total_spaceports`, `total_shipyards`
- Python analysis scripts updated to use correct column names

**Verification:**
```bash
# Homeworld facilities confirmed (seed 99999, turn 10)
total_spaceports,total_shipyards
1,1  # Correct: Each house has 1 of each at homeworld
```

**Files Modified:**
- `src/ai/analysis/diagnostics/types.nim` - Added fields
- `src/ai/analysis/diagnostics/domestikos_collector.nim` - Tracking logic
- `src/ai/analysis/diagnostics/csv_writer.nim` - CSV columns
- `scripts/analysis/analyze_single_game.py` - Column name fixes

**Impact:**
- ✅ 100% asset coverage: 18 ships + 4 ground + 2 facilities = 24 types
- ✅ Can analyze Eparch facility construction decisions
- ✅ CSV diagnostics complete for all unit types

---

### Priority-Ordered Gaps

**Critical (Block Progress):**
1. ⚠️ Multi-turn planning → Limits expensive ship production
2. ⚠️ Emergency response → Cannot react to crises
3. ⚠️ Cross-advisor coordination → Inefficient resource use

**Important (Reduce Effectiveness):**
4. ✅ ~~Weak reprioritization logic~~ → **RESOLVED** (2025-12-06)
5. ✅ ~~Standing orders disconnected~~ → **RESOLVED** (2025-12-06)
6. ✅ ~~Limited feedback information~~ → **RESOLVED** (2025-12-06)
7. ⚠️ No resource reservations → Unreliable multi-turn operations

**Unit Construction:**
- ✅ ~~Capacity fillers burying strategic requirements~~ → **RESOLVED** (2025-12-06)

**Nice-to-Have (Quality of Life):**
8. No risk assessment → Cannot weigh risk vs reward
9. ✅ ~~No diagnostic visibility~~ → **RESOLVED** (2025-12-06)
10. ✅ ~~Facility tracking gap~~ → **RESOLVED** (2025-12-06)

---

### Resolution Plan

**GOAP Will Address:**
- ⚠️ Gap 1: Multi-turn planning (GOAP's core capability)
- ⚠️ Gap 2: Emergency override (GOAP goal reprioritization)
- ⚠️ Gap 3: Cross-advisor coordination (GOAP strategic plans coordinate requirements)
- ⚠️ Gap 7: Resource reservations (GOAP multi-turn budgets)
- ⚠️ Gap 8: Risk assessment (GOAP confidence scores)

**✅ Completed (2025-12-06) - RBA Foundation Strengthening:**
- ✅ Gap 4: Enhanced Phase 4 reprioritization with quantity adjustment + substitution
- ✅ Gap 5: Connected standing orders to requirement generation (defense history + support reqs)
- ✅ Gap 6: Added rich feedback with 7 unfulfillment reasons + substitution suggestions
- ✅ Unit Construction: Strategic vs filler budget separation (80-85% / 15-20%)
- ✅ Gap 9: Advisor reasoning logs (CSV field + orchestrator)
- ✅ Gap 10: Facility tracking (spaceports + shipyards)

**Validation Results (96 games, Act 2, 15 turns):**
- Overall Score: 78.3%
- Gap 4 - Convergence Rate: 100.0% ✅ (target >80%)
- Gap 5 - Standing Order Compliance: 69.3% ⚠️ (target >70%, near-miss)
- Gap 6 - Feedback Generation: 75.0% ✅
- Unit Mix - Act Appropriateness: 100.0% ✅
- Budget Utilization: 47.1% ✅

**Test Artifacts:**
- 38 unit tests created (budget splitting, feedback, reprioritization)
- 9 new modules/submodules (DoD refactoring)
- 4 new config sections (TOML)
- Validation script: `scripts/analysis/validate_rba_fixes.py`

---

**Maintained by:** AI Development Team
**Related Documentation:**
- [Unit Progression](../mechanics/unit-progression.md)
- [Budget Allocation](../balance/RBA_BUDGET_ALLOCATION_FIX.md)
- [GOAP System](../GOAP_COMPLETE.md)
