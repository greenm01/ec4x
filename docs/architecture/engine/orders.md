# Fleet Order & Squadron Management Architecture

## Overview

This document describes the complete architecture for fleet orders, squadron management, and construction-to-deployment pipeline in the EC4X game engine. These systems work together to manage the lifecycle of military units from construction through operational deployment.

## Core Design Philosophy

**Squadrons are tactical, not strategic.**

Squadrons represent combat units (ships grouped for battle). They are tactical-level abstractions for combat resolution, NOT strategic decision-making tools. Players and AI make strategic decisions at the **fleet level** using orders and standing orders.

This philosophy drives several key architectural decisions:
- **Auto-assignment is always enabled**: Squadrons automatically join fleets, eliminating tactical micromanagement
- **Fleet orders drive strategy**: Players control where fleets go and what they do, not individual squadrons
- **Auto-balancing maintains readiness**: Squadrons automatically distribute across fleets for operational balance

---

## Construction & Commissioning Pipeline

### Architecture Decision: Economic → Operational Flow

The construction and commissioning system models the real-world pipeline from industrial production to operational readiness:

```
Treasury → Build Order → Construction → Commissioning → Squadron → Fleet
   (PP)      (1 turn)     (1+ turns)     (instant)      (tactical)  (strategic)
```

### Phase 1: Build Orders (Treasury → Construction)

**Location**: `economy_resolution.nim:resolveBuildOrders()`

Houses spend treasury (PP) to start construction projects. Each project:
- Deducts cost from treasury immediately
- Requires dock capacity at colony (spaceports for small ships, shipyards for capital ships)
- Takes 1+ turns based on ship class and tech level
- Multiple projects can run in parallel (limited by dock capacity)

**Why this design?**
- Simulates industrial capacity (can't build infinite ships instantly)
- Creates strategic planning (commit resources turn X, get ships turn X+N)
- Dock capacity represents shipyard/spaceport infrastructure limits

### Phase 2: Ship Completion → Commissioning

**Location**: `economy_resolution.nim:resolveConstruction()`

When construction completes, ships are **immediately commissioned** into squadrons:

```nim
# Combat ships → Squadrons
colony.unassignedSquadrons.add(newSquadron)

# Spacelift ships → Unassigned pool
colony.unassignedSpaceLiftShips.add(spaceLiftShip)
```

**Squadron Formation Rules:**
1. **Capital ships** (BB, DN, SD, CA, CL) → Always create new squadron (they're flagships)
2. **Escorts** (DD, FF, CT) → Try to join existing unassigned capital squadrons (wingmen)
3. **Scouts/Fighters** → Create new single-ship squadrons

**Why immediate commissioning?**
- Ships don't sit in "construction complete but not operational" limbo
- Simplifies state management (no "ready to commission" queue)
- Matches real-world: ship completes sea trials → immediately joins fleet

### Phase 3: Auto-Assignment (Squadron → Fleet)

**Location**: `resolve.nim:AUTO-ASSIGN phase`, `economy_resolution.nim:autoBalanceSquadronsToFleets()`

**ALWAYS ENABLED** - Newly commissioned squadrons automatically join fleets at their colony.

#### Why Auto-Assignment is Always Enabled

**Design Decision Date**: 2025-01-29

We removed the optional `colony.autoAssignFleets: bool` flag. Auto-assignment is now mandatory.

**Rationale:**

**From Player Perspective:**
- **Eliminates micromanagement trap**: Forgetting to assign squadrons = wasted production sitting idle
- **Simplifies mental model**: One less setting per colony to manage
- **Players retain strategic control**: Can still create "staging fleets", use squadron transfer orders, or assign Reserve/Mothballed status to prevent auto-assignment

**From AI Perspective (RBA):**
- AI would **always enable** this setting anyway
- Eliminates need for squadron management micromanagement code
- Ensures newly built units immediately become operational

**From Game Design Perspective:**
- **Aligns with core philosophy**: Squadrons are tactical (combat), NOT strategic (decision-making)
- Players make strategic decisions at **fleet level** (orders, standing orders, composition)
- Reduces complexity without losing functionality
- Better solved by explicit fleet management tools (staging fleets, transfers, fleet status)

**Alternative Considered (Rejected):**
- Optional boolean with default `true`: Adds complexity for no benefit, creates AI implementation burden

#### Auto-Assignment Logic

**Stationary Fleets Receive New Squadrons:**
- Fleets with **no orders** (default stationary)
- Fleets with **Hold** orders
- Fleets with **Guard/Defend** orders (GuardStarbase, GuardPlanet, DefendSystem)
- Fleets with **Patrol** orders *at the same system*
- Fleets with **stationary standing orders**: DefendSystem, GuardColony, AutoEvade, BlockadeTarget (at target)

**Moving Fleets Do NOT Receive Squadrons:**
- Fleets with **active movement orders** (Move, Colonize, etc.)
- Fleets with **Patrol** orders to *different system*
- Fleets with **movement-based standing orders**: PatrolRoute, AutoColonize, AutoReinforce, AutoRepair
- **Reserve** or **Mothballed** fleets (intentional reduced-readiness status)

**Why these rules?**
- Squadrons only join fleets **intentionally stationary** at colony, not temporarily passing through
- Prevents disrupting fleets mid-mission (e.g., patrol route)
- Reserve/Mothballed fleets are in storage mode, not accepting reinforcements

### Phase 4: Fleet Operations (Strategic Orders)

Once squadrons are in fleets, players control them via **fleet orders** (one-time) and **standing orders** (persistent).

---

## Fleet Order Types

### One-Time Fleet Orders (FleetOrderType)

**Location**: `order_types.nim:FleetOrderType`, execution in `resolution/fleet_orders.nim`

Explicit orders that execute once, then complete:

| Order | Purpose | Example |
|-------|---------|---------|
| `Hold` | Stay at current location | Defensive positioning |
| `Move` | Travel to target system | Strategic repositioning |
| `Colonize` | Establish colony (ETAC) | Expansion |
| `GuardStarbase` | Protect starbase | Orbital defense |
| `GuardPlanet` | Protect planet surface | Ground support |
| `Patrol` | Guard system or route | Border security |
| `BlockadePlanet` | Cut off colony | Economic warfare |
| `BombardPlanet` | Destroy infrastructure | Siege operations |
| `InvadePlanet` | Land ground forces | Conquest |
| `Reserve` | 50% maintenance, station-keeping | Budget management |
| `Mothball` | 0% maintenance, offline storage | Long-term storage |
| `Reactivate` | Return to Active status | Mobilization |
| `SpyOnPlanet` | Intelligence gathering | Recon mission |
| `HackStarbase` | Economic/R&D intel | Espionage |
| `SpyOnSystem` | Fleet detection | Surveillance |

**Order Restrictions:**
- **Reserve/Mothballed fleets**: Cannot execute movement orders (permanently stationed at colony)
- **Multi-ship squadrons**: Cannot execute spy orders (stealth requirement)
- **Explicit orders override standing orders** for one turn

### Standing Orders (StandingOrderType)

**Location**: `order_types.nim:StandingOrderType`, execution in `standing_orders.nim`

Persistent behaviors that execute automatically when no explicit order is given:

| Order | Type | Purpose |
|-------|------|---------|
| `PatrolRoute` | Movement | Cycle through patrol path indefinitely |
| `DefendSystem` | Stationary | Guard system, engage hostiles per ROE |
| `GuardColony` | Stationary | Defend specific colony (alias for DefendSystem) |
| `AutoColonize` | Movement | ETACs auto-colonize nearest suitable system |
| `AutoReinforce` | Movement | Join nearest damaged friendly fleet |
| `AutoRepair` | Movement | Return to shipyard when crippled |
| `AutoEvade` | Stationary | Retreat if outnumbered per ROE |
| `BlockadeTarget` | Stationary | Maintain blockade on enemy colony |

**Standing Order Activation:**
1. Check if fleet has explicit order → Skip if yes
2. Activate standing order behavior (check conditions)
3. Generate appropriate FleetOrder for this turn
4. Update standing order state (e.g., patrol index)
5. Write FleetOrder to state.fleetOrders table

**Why Standing Orders?**
- **Reduces micromanagement**: Set once, executes automatically
- **AI-friendly**: RBA can assign defensive postures without per-turn orders
- **Player QoL**: Patrol routes, auto-repair, auto-colonize handle routine tasks

---

## Fleet Auto-Balancing

**Location**: `resolve.nim:AUTO-BALANCE phase`

Fleets with `fleet.autoBalanceSquadrons = true` automatically redistribute squadrons for optimal composition.

**Balancing Logic:**
- Triggered when fleet size deviates from target
- Target size based on squadron count and fleet role
- Only applies to **Active fleets** (not Reserve/Mothballed)

**Why Auto-Balancing?**
- **Maintains operational readiness**: Fleets stay at target strength
- **Handles attrition**: Losses automatically replaced from unassigned pool
- **Optional per-fleet**: Players can disable for specialized fleets

---

## Rules of Engagement (ROE)

**Location**: `order_types.nim:StandingOrder.roe`

ROE (0-10 scale) affects combat decisions during standing order activation:

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

**Location**: `fleet.nim:FleetStatus`

Fleets can be in one of three operational states:

### Active
- **Maintenance**: 100% cost
- **Combat**: Full effectiveness
- **Orders**: Can execute all order types
- **Auto-assignment**: Receives new squadrons if stationary

### Reserve
- **Maintenance**: 50% cost
- **Combat**: Reduced effectiveness (penalty TBD)
- **Orders**: **Cannot move** (permanently stationed at colony), can execute Reactivate
- **Auto-assignment**: Does NOT receive new squadrons
- **Purpose**: Budget management, defensive reserves

### Mothballed
- **Maintenance**: 0% cost
- **Combat**: **Cannot fight** - must be screened during orbital combat
- **Orders**: **Cannot move** (permanently stationed at colony), can execute Reactivate
- **Auto-assignment**: Does NOT receive new squadrons
- **Risk**: If not screened, risks destruction in orbital combat
- **Purpose**: Long-term storage, preserving fleet for future mobilization

**Transition Rules:**
- Active → Reserve: Issue `Reserve` order
- Active → Mothballed: Issue `Mothball` order
- Reserve/Mothballed → Active: Issue `Reactivate` order

---

## Order Priority & Conflict Resolution

### Explicit vs. Standing Orders

1. **Explicit orders always override** standing orders for one turn
2. After explicit order completes, fleet resumes standing order
3. Standing orders execute only when `fleetId not in state.fleetOrders`

### Order Lock for Reserve/Mothballed Fleets

**Location**: `resolve.nim:ORDER PROCESSING phase`

Reserve/Mothballed fleets have **locked orders**:
- All orders rejected EXCEPT `Reactivate`
- Movement orders explicitly rejected in `fleet_orders.nim:resolveMovementOrder()`
- Prevents accidental movement of permanently-stationed fleets

---

## Implementation Files

| File | Responsibility |
|------|----------------|
| `order_types.nim` | Type definitions for all order types |
| `orders.nim` | Order packet and validation |
| `resolve.nim` | Main turn resolution orchestrator |
| `resolution/fleet_orders.nim` | One-time fleet order execution |
| `standing_orders.nim` | Standing order activation engine |
| `resolution/economy_resolution.nim` | Construction, commissioning, auto-assignment |
| `fleet.nim` | Fleet data structures and status |
| `squadron.nim` | Squadron formation and management |

---

## Future Extensions

- **Trade routes**: Automatic resource transport standing orders
- **Conditional triggers**: "Patrol until enemy detected"
- **Complex patrol patterns**: Weighted systems, timing-based routes
- **Standing diplomatic orders**: Auto-accept certain proposals
- **Fleet templates**: Pre-defined compositions for rapid fleet creation

---

**Last Updated**: 2025-01-29
**Status**: Implemented and tested (246/246 integration tests passing)
