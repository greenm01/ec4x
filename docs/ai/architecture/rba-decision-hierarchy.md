# RBA Decision Hierarchy & Information Flow Architecture

**Last Updated:** 2025-12-06 (Gap Analysis added)
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

#### 4. Weak Reprioritization Logic

**Gap:** Phase 4 reprioritization is simplistic (just downgrade priorities).

**Current Logic:**
```nim
if unfulfilled and expensive:
  priority = High → Medium
  or Medium → Low
```

**Missing Capabilities:**
- Cost-benefit analysis (which requirement gives best ROI?)
- Substitution logic (can't afford Battleship → build 2 Cruisers instead)
- Quantity adjustment (need 10 Marines, afford 5 → build 5)
- Value assessment (is this requirement still relevant?)

**Note:** Partial fulfillment EXISTS in `budget.nim` but Phase 4 doesn't leverage it:
```nim
// src/ai/rba/budget.nim line 1135
let affordableQuantity = min(req.quantity, availableBudget div unitCost)
```

**Improvement Needed:** Smarter reprioritization using cost-effectiveness metrics

---

#### 5. Standing Orders Disconnected from Requirements

**Gap:** Standing orders (patrol, defend) don't inform requirement generation.

**Example:**
```
Fleet 42: Standing order "Defend System 15"
Domestikos: Generates defensive units for System 7 (homeworld)
Result:     Wrong system defended
```

**Current State:** Standing orders and requirements are parallel systems
- Standing orders managed in `standing_orders_manager.nim`
- Requirements generated in `domestikos/build_requirements.nim`
- No information flow between them

**Better Solution:**
```nim
proc generateBuildRequirements(...):
  for fleet, order in standingOrders:
    if order.orderType == Defend:
      generateDefenseRequirements(order.targetSystem)
```

---

#### 6. Limited Feedback Information

**Gap:** Treasurer only reports "unfulfilled" but not WHY.

**Current Feedback:**
```nim
TreasurerFeedback(
  unfulfilledRequirements: [req1, req2, req3]
)
```

**Missing Information:**
- Why unfulfilled? (insufficient budget, invalid requirement, capacity exhausted, strategically rejected)
- How much short? (need 500 PP, have 200 PP)
- What would make it affordable? (need 300 PP more, or downgrade from Battleship to Cruiser)

**Better Feedback:**
```nim
UnfulfilledRequirement(
  requirement: req,
  reason: UnfulfillmentReason.InsufficientBudget,
  costNeeded: 500,
  budgetAvailable: 200,
  suggestion: "Reduce quantity from 5 to 2"
)
```

**Impact:**
- Phase 4 reprioritization is blind (doesn't know why unfulfilled)
- Cannot make informed adjustments
- Repeated failures for same requirements

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
4. Weak reprioritization logic → Suboptimal budget adjustments
5. Standing orders disconnected → Wrong defensive positioning
6. Limited feedback information → Blind reprioritization
7. No resource reservations → Unreliable multi-turn operations

**Nice-to-Have (Quality of Life):**
8. No risk assessment → Cannot weigh risk vs reward
9. ✅ ~~No diagnostic visibility~~ → **RESOLVED** (2025-12-06)
10. ✅ ~~Facility tracking gap~~ → **RESOLVED** (2025-12-06)

---

### Resolution Plan

**GOAP Will Address:**
- ✅ Gap 1: Multi-turn planning (GOAP's core capability)
- ✅ Gap 2: Emergency override (GOAP goal reprioritization)
- ✅ Gap 3: Cross-advisor coordination (GOAP strategic plans coordinate requirements)
- ✅ Gap 7: Resource reservations (GOAP multi-turn budgets)
- ✅ Gap 8: Risk assessment (GOAP confidence scores)

**Should Fix Before GOAP (Strengthen RBA Foundation):**
- 🔧 Gap 4: Enhance Phase 4 reprioritization with cost-benefit analysis
- 🔧 Gap 5: Connect standing orders to requirement generation
- 🔧 Gap 6: Add detailed unfulfillment reasons to feedback

**✅ Completed (2025-12-06):**
- ✅ Gap 9: Advisor reasoning logs (CSV field + orchestrator)
- ✅ Gap 10: Facility tracking (spaceports + shipyards)

---

**Maintained by:** AI Development Team
**Related Documentation:**
- [Unit Progression](../mechanics/unit-progression.md)
- [Budget Allocation](../balance/RBA_BUDGET_ALLOCATION_FIX.md)
- [GOAP System](../GOAP_COMPLETE.md)
