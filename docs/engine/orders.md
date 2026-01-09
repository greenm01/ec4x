# Fleet Orders & Ship Management Architecture

## Overview

This document describes the complete architecture for fleet orders, ship management, and the construction-to-deployment pipeline in the EC4X game engine. These systems work together to manage the lifecycle of military units from construction through operational deployment.

## Core Design Philosophy

**Fleets are the strategic unit. Ships are the tactical unit.**

Players make strategic decisions at the **fleet level** using fleet commands. Ships are individual vessels that belong to fleets. There is no intermediate "squadron" layer - ships are assigned directly to fleets.

This philosophy drives several key architectural decisions:
- **Auto-assignment is always enabled**: Newly commissioned ships automatically join fleets at their colony
- **Fleet commands drive strategy**: Players control where fleets go and what they do
- **Auto-balancing maintains readiness**: Ships automatically distribute across fleets for operational balance

---

## Construction & Commissioning Pipeline

### Architecture Decision: Economic → Operational Flow

The construction and commissioning system models the real-world pipeline from industrial production to operational readiness:

```
Treasury → Build Order → Construction → Commissioning → Fleet
   (PP)      (CMD6)       (PRD2)         (CMD2)       (strategic)
```

### Phase 1: Build Orders (Treasury → Construction)

**Location**: `resolution/construction.nim:resolveBuildOrders()`

Houses spend treasury (PP) to start construction projects. Each project:
- Deducts cost from treasury immediately
- Requires dock capacity at colony (spaceports or shipyards)
- Takes 1+ turns based on ship class and tech level
- Multiple projects can run in parallel (limited by dock capacity)

**Why this design?**
- Simulates industrial capacity (can't build infinite ships instantly)
- Creates strategic planning (commit resources turn X, get ships turn X+N)
- Dock capacity represents shipyard/spaceport infrastructure limits

### Phase 2: Ship Completion → Commissioning

**Location**: `resolution/commissioning.nim:unifiedCommissioning()`

When construction completes (PRD2), ships are marked `AwaitingCommission`. The next turn during CMD2 (Unified Commissioning), ships become operational:

```nim
# Ships commission and become available
for facility in state.allSpaceports():
  commissionCompletedShips(state, facility)

for facility in state.allShipyards():
  commissionCompletedShips(state, facility)
```

**Why unified commissioning?**
- Ships don't sit in "construction complete but not operational" limbo
- Simplifies state management (single commissioning point)
- 1-turn lag creates strategic depth (build ahead of threats)

### Phase 3: Auto-Assignment (Ship → Fleet)

**Location**: `resolution/automation.nim:autoAssignShipsToFleets()`

**ALWAYS ENABLED** - Newly commissioned ships automatically join fleets at their colony.

#### Why Auto-Assignment is Always Enabled

**Design Decision Date**: 2025-01-29

We removed the optional `colony.autoAssignFleets: bool` flag. Auto-assignment is now mandatory.

**Rationale:**

**From Player Perspective:**
- **Eliminates micromanagement trap**: Forgetting to assign ships = wasted production sitting idle
- **Simplifies mental model**: One less setting per colony to manage
- **Players retain strategic control**: Can still use fleet reorganization commands, Reserve/Mothballed status

**From Game Design Perspective:**
- Players make strategic decisions at **fleet level** (commands, composition)
- Reduces complexity without losing functionality
- Better solved by explicit fleet management tools (transfers, fleet status)

#### Auto-Assignment Logic

**Stationary Fleets Receive New Ships:**
- Fleets with **no commands** (default stationary)
- Fleets with **Hold** orders
- Fleets with **Guard** orders (GuardStarbase, GuardColony)
- Fleets with **Patrol** orders *at the same system*

**Moving Fleets Do NOT Receive Ships:**
- Fleets with **active movement orders** (Move, Colonize, etc.)
- Fleets with **Patrol** orders to *different system*
- **Reserve** or **Mothballed** fleets (intentional reduced-readiness status)

**Why these rules?**
- Ships only join fleets **intentionally stationary** at colony, not temporarily passing through
- Prevents disrupting fleets mid-mission (e.g., patrol route)
- Reserve/Mothballed fleets are in storage mode, not accepting reinforcements

### Phase 4: Fleet Operations (Strategic Commands)

Once ships are in fleets, players control them via **fleet commands**.

---

## Fleet Command Types

### Active Fleet Commands (FleetCommandType)

**Location**: `types/fleet.nim:FleetCommandType`

20 distinct mission types for fleet operations:

| Order | Name | Purpose | Execution Phase |
|-------|------|---------|-----------------|
| 00 | Hold | Stay at current location | N/A (defensive posture) |
| 01 | Move | Travel to target system | PRD1 |
| 02 | SeekHome | Return to nearest friendly colony | PRD1 |
| 03 | Patrol | Guard system, engage hostiles | CON1 |
| 04 | GuardStarbase | Protect orbital installation | N/A (defensive posture) |
| 05 | GuardColony | Colony defense | N/A (defensive posture) |
| 06 | Blockade | Siege a colony | CON1c |
| 07 | Bombard | Orbital bombardment | CON1d |
| 08 | Invade | Ground assault | CON1d |
| 09 | Blitz | Combined bombardment + invasion | CON1d |
| 10 | Colonize | Establish colony (requires ETAC) | CON1e |
| 11 | ScoutColony | Intelligence on colony | CON1f |
| 12 | ScoutSystem | Reconnaissance of system | CON1f |
| 13 | HackStarbase | Electronic warfare | CON1f |
| 14 | JoinFleet | Merge with another fleet | PRD1c |
| 15 | Rendezvous | Meet and join at location | PRD1c |
| 16 | Salvage | Disband fleet for 50% PP | INC5 |
| 17 | Reserve | 50% maintenance, reduced combat | PRD1c |
| 18 | Mothball | 0% maintenance, offline storage | PRD1c |
| 19 | Reactivate | Return to Active status | PRD1c |
| 20 | View | Long-range reconnaissance | PRD1c |

**Command Restrictions:**
- **Reserve/Mothballed fleets**: Cannot execute movement orders (stationed at colony)
- **Scout missions**: Require scout-only fleets
- **Explicit commands override** any previous commands

### Zero-Turn Administrative Commands

**Location**: `types/orders.nim:ZeroTurnCommandType`

Execute immediately during CMD5 (Player Submission Window):

| Command | Purpose |
|---------|---------|
| DetachShips | Extract ships from fleet into new fleet |
| TransferShips | Move ships between fleets |
| MergeFleets | Combine two fleets |
| LoadCargo | Load marines/colonists onto transports |
| UnloadCargo | Unload marines/colonists to colony |

**Why Zero-Turn Commands?**
- **Immediate preparation**: Reorganize before issuing operational commands
- **Reduces micromanagement**: Combine multiple admin actions in one turn
- **Strategic flexibility**: Load troops and launch invasion in same turn

---

## Rules of Engagement (ROE)

**Location**: `types/fleet.nim:Fleet.roe`

ROE (0-10 scale) affects combat decisions:

| ROE | Behavior |
|-----|----------|
| 0-2 | Extremely cautious - Retreat from any threat |
| 3-5 | Defensive - Fight only if superior |
| 6-8 | Aggressive - Fight unless clearly outnumbered |
| 9-10 | Suicidal - Fight to the death |

**Examples:**
- Patrol with ROE=2 → Retreat from stronger forces
- Guard with ROE=8 → Fight unless outnumbered 4:1

---

## Fleet Status System

**Location**: `types/fleet.nim:FleetStatus`

Fleets can be in one of three operational states:

### Active
- **Maintenance**: 100% cost
- **Combat**: Full effectiveness
- **Orders**: Can execute all order types
- **Auto-assignment**: Receives new ships if stationary

### Reserve
- **Maintenance**: 50% cost
- **CC Cost**: 50%
- **Combat**: 50% AS with auto-Blockade (participates in orbital defense)
- **Orders**: **Cannot move** (stationed at colony), can execute Reactivate
- **Auto-assignment**: Does NOT receive new ships
- **Purpose**: Budget management, defensive reserves

### Mothballed
- **Maintenance**: 0% cost (skeleton crews only, 10%)
- **Combat**: **Cannot fight** - must be screened during orbital combat
- **Orders**: **Cannot move** (stationed at colony), can execute Reactivate
- **Auto-assignment**: Does NOT receive new ships
- **Risk**: If not screened, risks destruction in orbital combat
- **Purpose**: Long-term storage, preserving fleet for future mobilization

**Transition Rules:**
- Active → Reserve: Issue `Reserve` order (instant)
- Active → Mothballed: Issue `Mothball` order (instant)
- Reserve → Active: Issue `Reactivate` order (1 turn)
- Mothballed → Active: Issue `Reactivate` order (1 turn)

---

## Command Lifecycle

All fleet commands follow the same lifecycle:

```
CMD5: Player submits command
  ↓
CMD6: Engine validates, stores in Fleet.command
  ↓
PRD1a: Fleet travels toward target
  ↓
PRD1b: Arrival detected → missionState = Executing
  ↓
CON/INC: Command executes based on type
  ↓
CON1g/PRD1c: Administrative completion
```

**Key Properties:**
- Commands persist in `Fleet.command` field until completion
- Travel happens in Production Phase for ALL commands
- Execution phase depends on command type (CON for combat, INC for economic)

---

## Implementation Files

| File | Responsibility |
|------|----------------|
| `types/fleet.nim` | Fleet and command type definitions |
| `types/orders.nim` | Order packet and command structures |
| `resolution/commissioning.nim` | Unified commissioning (CMD2) |
| `resolution/automation.nim` | Auto-assignment and colony automation |
| `resolution/construction.nim` | Build order processing |
| `systems/fleet/engine.nim` | Fleet operations |
| `entities/fleet_ops.nim` | Fleet creation/destruction |

---

## Integration with Turn Cycle

**Reference**: `docs/engine/ec4x_canonical_turn_cycle.md`

```
Command Phase (CMD):
  CMD1: Order Cleanup (clear completed commands)
  CMD2: Unified Commissioning (ships become operational)
  CMD3: Auto-Repair Submission
  CMD4: Colony Automation (auto-assign ships to fleets)
  CMD5: Player Submission Window (zero-turn + fleet commands)
  CMD6: Order Processing & Validation

Production Phase (PRD):
  PRD1a: Fleet Travel (all commands move toward targets)
  PRD1b: Arrival Detection (missionState → Executing)
  PRD1c: Administrative Completion (Move, JoinFleet, status changes)
  PRD2: Construction Advancement

Conflict Phase (CON):
  CON1a-d: Combat Resolution
  CON1e: Colonization
  CON1f: Scout Intelligence
  CON1g: Administrative Completion (combat commands)

Income Phase (INC):
  INC5: Salvage Execution
```

---

**Last Updated**: 2026-01-09
**Status**: Reflects current architecture (ships → fleets, no squadron layer)
