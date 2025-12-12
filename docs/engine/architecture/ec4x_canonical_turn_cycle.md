# EC4X Canonical Turn Sequence Specification

**Purpose:** Complete and definitive turn order specification for EC4X  
**Last Updated:** 2025-12-09
**Status:** Implementation Complete (Split Commissioning System)

---

## Overview

EC4X uses a four-phase turn structure that separates combat resolution, economic calculation, player decision-making, and server processing. Each phase has distinct timing and execution properties.

**The Four Phases:**
1. **Conflict Phase** - Resolve all combat and espionage (orders from Turn N-1)
2. **Income Phase** - Calculate economics, enforce capacity limits, check victory. End of turn.
3. **Command Phase** - Server commissioning, player submission, order validation. Start turn.
4. **Maintenance Phase** - Server processing (movement, construction, diplomacy)

**Key Timing Principle:** Combat orders submitted Turn N execute Turn N+1 Conflict Phase. Movement orders submitted Turn N execute Turn N Maintenance Phase.

---

## Order Lifecycle Terminology (Universal for All Orders)

EC4X uses precise terminology for the three stages of order processing. **This applies to BOTH active orders AND standing orders:**

### Initiate (Command Phase Part B)
- **Active orders:** Player submits explicit orders via OrderPacket
- **Standing orders:** Player configures standing order rules
- Orders queued for future processing
- Phase: Command Phase Part B

### Validate (Command Phase Part C)
- **Both order types:** Engine validates orders and configurations
- Active orders stored in `state.fleetOrders` for later activation
- Standing order configs validated (conditions, targets, parameters)
- Phase: Command Phase Part C

### Activate (Maintenance Phase Step 1a)
- **Active orders:** Order becomes active, fleet starts moving toward target
- **Standing orders:** System checks conditions and generates fleet orders
- **Both:** Fleets begin traveling, orders written to state
- Events: `StandingOrderActivated`, `StandingOrderSuspended`
- Phase: Maintenance Phase Step 1a

### Execute (Conflict/Income Phase)
- **Both order types:** Fleet orders conduct their missions at target locations
- Bombard, Colonize, Trade, Blockade, etc. actually happen
- Results generate events (`OrderCompleted`, `OrderFailed`, etc.)
- Phase: Depends on order type (Conflict for combat, Income for trade)

**Key Insight:** Active and standing orders follow the SAME four-tier lifecycle:
- Active order: Initiate (Command B) → Validate (Command C) → Activate (Maintenance 1a) → Execute (Conflict/Income)
- Standing order: Initiate (Command B) → Validate (Command C) → Activate (Maintenance 1a) → Execute (Conflict/Income)

---

## Phase 1: Conflict Phase

**Purpose:** Resolve all combat and espionage operations submitted previous turn.

**Timing:** Orders submitted Turn N-1 execute Turn N.

### Execution Order

**1. Space Combat** (simultaneous resolution)
- Collect all space combat intents
- Resolve conflicts (determine winners)
- Execute combat engine for all battles
- Generate GameEvents (ShipDestroyed, FleetEliminated)

**2. Orbital Combat** (simultaneous resolution)
- Collect all orbital bombardment intents
- Resolve conflicts (determine priority order)
- Execute orbital strikes sequentially
- Generate GameEvents (StarbaseDestroyed, DefensesWeakened)

**3. Blockade Resolution** (simultaneous resolution)
- Collect all blockade intents
- Resolve conflicts (determine blockade controller)
- Establish blockade status (affects Income Phase)
- Generate GameEvents (BlockadeEstablished, BlockadeBroken)

**4. Planetary Combat** (sequential execution, simultaneous priority)
- Collect all planetary combat intents (Bombard/Invade/Blitz)
- Resolve conflicts (determine attack priority order)
- Execute attacks sequentially in priority order
- Weaker attackers benefit from prior battles weakening defenders
- Generate GameEvents (SystemCaptured, ColonyCaptured, PlanetBombarded)

**5. Colonization** (simultaneous resolution)
- ETAC fleets establish colonies
- Resolve conflicts (winner-takes-all)
- Fallback logic for losers (AutoColonize standing orders)
- Generate GameEvents (ColonyEstablished)

**6. Espionage Operations** (simultaneous resolution)

**6a. Spy Scout Detection** (pre-combat preparation)
- Execute BEFORE combat resolution (Step 1-2)
- Check detection for all active spy scouts
- Detected scouts excluded from combat participation
- Generate GameEvents (SpyScoutDetected)
- Implementation: Executes at beginning of Conflict Phase

**6b. Fleet-Based Espionage**
- SpyPlanet: Gather colony economic/military intel
- SpySystem: Map system defenses and fleet presence
- HackStarbase: Infiltrate starbase systems
- Update intelligence tables
- Generate GameEvents (IntelGathered)

**6c. Space Guild Espionage** (EBP-based covert ops)
- Tech Theft, Sabotage, Assassination, Cyber Attack
- Economic Manipulation, Psyops, Counter-Intel
- Intelligence Theft, Plant Disinformation, Recruit Agent
- Generate GameEvents (EspionageSuccess, EspionageDetected)

**6d. Starbase Surveillance** (continuous monitoring)
- Automatic intelligence gathering from friendly starbases
- Monitors adjacent systems for fleet movements
- Updates intelligence tables with starbase sensor data
- No player action required (passive system)

**7. Spy Scout Travel**
- Move traveling spy scouts through jump lanes
- Travel speed: 1-2 jumps per turn based on lane control
- Detection checks occur at intermediate systems
- Scouts may be detected and eliminated during travel
- Generate GameEvents (SpyScoutMoved, SpyScoutDetected)

### Key Properties
- All orders execute from previous turn's submission
- Simultaneous resolution prevents first-mover advantage
- Sequential execution after priority determination
- Intelligence gathering happens AFTER combat (collect after-action data)
- Destroyed ships are deleted from ship lists (orders become unreachable)

---

## Phase 2: Income Phase

**Purpose:** Calculate economic output, apply modifiers, collect resources, enforce capacity constraints, evaluate victory.

### Execution Order

**1. Calculate Base Production**
- For each colony: Base PP/RP from planet class and resource rating
- Apply improvements (Infrastructure, Manufactories, Labs)
- Apply espionage effects (economic sabotage, cyber attacks)

**2. Apply Blockades** (from Conflict Phase)
- Blockaded colonies: 50% production penalty
- Update economic output

**3. Calculate Maintenance Costs**
- Calculate maintenance for all surviving ships/facilities (after Conflict Phase)
- Damaged/crippled ships may have reduced maintenance
- Deduct total maintenance from house treasuries
- Generate GameEvents (MaintenancePaid)

**4. Execute Salvage Orders** (Fleet Order 15, submitted previous turn)
- For each fleet with Salvage order:
  - Validate: Fleet survived Conflict Phase, at friendly colony, debris present
  - Execute salvage recovery (PP from destroyed ships)
  - Add recovered PP to house treasury
  - Generate GameEvents (ResourcesSalvaged)

**5. Capacity Enforcement After IU Loss** (reference.md Table 10.5)

When IU drops (blockades, lost colonies), capacity limits may fall below current forces. Enforcement with grace periods or immediate seizure.

**5a. Capital Squadron Capacity (No Grace Period)**
- Calculate capacity: `max(8, floor(Total_House_IU ÷ 100) × 2 × mapMultiplier)`
- Total_House_IU includes blockade effects from Step 2
- If current capital squadrons > capacity:
  - Identify excess squadrons (CR ≥ 7)
  - Priority: Crippled flagships first, then lowest AS
  - **Immediate enforcement** (no grace period)
  - Space Guilds claim excess squadrons
  - House receives 50% original PP cost as salvage payment
  - Generate GameEvents (CapitalShipSeized)

**5b. Total Squadron Limit (2-Turn Grace Period)**
- Calculate capacity: `max(20, floor(Total_House_IU ÷ 50) × mapMultiplier)`
- Includes ALL military squadrons (escorts + capitals)
- If current total squadrons > capacity:
  - Initiate 2-turn grace period timer (if not already started)
  - If grace period expired: Auto-disband weakest escort squadrons (no PP refund)
  - Priority: Lowest AS escorts first
  - Generate GameEvents (SquadronDisbanded)

**5c. Fighter Squadron Capacity (2-Turn Grace Period)**
- Calculate per-colony capacity: `floor(Colony_IU ÷ 100) × FD_MULTIPLIER`
- If colony fighters > capacity (from over-building OR IU loss):
  - Initiate 2-turn grace period timer (if not already started)
  - If grace period expired: Auto-disband oldest squadrons (no PP refund)
  - Generate GameEvents (FighterSquadronDisbanded)
- **Note:** Fighters are NOT blocked at submission (can intentionally over-build)

**5d. Planet-Breaker Enforcement (Immediate)**
- Maximum 1 Planet-Breaker per currently owned colony
- When colony lost (captured/destroyed) in Conflict Phase:
  - Instantly scrap associated Planet-Breaker (no salvage, no PP refund)
  - Generate GameEvents (PlanetBreakerScrapped)
- **Note:** PB build orders ARE blocked at submission (can't over-build intentionally)

**6. Collect Resources**
- Add PP/RP from production to house treasuries
- Add PP from salvage orders to house treasuries
- Add PP from Space Guild capital ship seizure payments to house treasuries
- Generate GameEvents (ResourcesCollected)

**7. Calculate Prestige**
- Award prestige for events this turn (colonization, victories, tech advances)
- Update house prestige totals
- Generate GameEvents (PrestigeAwarded)

**8. House Elimination & Victory Checks**

**8a. House Elimination** (executed first)

Evaluate elimination conditions for each house in sequential order:

*Standard Elimination:*
- Condition: House has zero colonies AND no invasion capability
- Invasion capability check:
  - Scan all house fleets for spacelift ships
  - Check if any transport has CargoType.Marines with quantity > 0
  - If found: House has invasion capability
- Elimination triggers if:
  - Zero colonies AND zero fleets, OR
  - Zero colonies AND no marines on transports
- On elimination:
  - Set house.eliminated = true
  - Generate GameEvent(HouseEliminated)
  - Log reason: "no remaining forces" or "no marines for reconquest"

*Defensive Collapse:*
- Condition: House prestige below threshold for consecutive turns
- Prestige threshold: From config.gameplay.elimination.defensive_collapse_threshold
- Turn requirement: From config.gameplay.elimination.defensive_collapse_turns
- Logic per house:
  - If prestige < threshold:
    - Increment house.negativePrestigeTurns
    - If negativePrestigeTurns ≥ required turns:
      - Set house.eliminated = true
      - Set house.status = HouseStatus.DefensiveCollapse
      - Generate GameEvent(HouseEliminated, "collapsed from negative prestige")
  - If prestige ≥ threshold:
    - Reset house.negativePrestigeTurns = 0
- Defensive collapse evaluation requires prestige from Step 7

**8b. Victory Conditions** (executed second)

Check victory conditions using non-eliminated houses:
- **Prestige Victory:** House prestige ≥ prestige threshold (from config)
- **Elimination Victory:** Only one non-eliminated house remains
- **Turn Limit Victory:** Maximum turns reached, highest prestige wins

On victory:
- Set game.phase = GamePhase.Completed
- Generate GameEvent(VictoryAchieved)
- Log victor and victory type

**9. Advance Timers**
- Espionage effect timers (sabotage recovery)
- Diplomatic effect timers (trade agreements)
- Total squadron grace period timers (from Step 5b)
- Fighter capacity grace period timers (from Step 5c)

### Key Properties
- Maintenance costs based on surviving forces after Conflict Phase
- Salvage orders execute if fleet survived Conflict Phase
- Capacity enforcement uses post-blockade IU values
- Capital squadrons: Immediate seizure (no grace period)
- Total squadrons/fighters: 2-turn grace period, then auto-disband
- Planet-Breakers: Instant scrap when colony lost
- Economic operations consolidated (production + maintenance + salvage + seizures)
- Prestige calculated from turn's events
- Victory conditions evaluated after prestige update
- Blockade effects applied immediately
- Sets treasury levels for Command Phase spending

---

## Phase 3: Command Phase

**Purpose:** Three-part phase - Server processing (establish new state) -> Player window -> Order processing

**Critical Timing:** Game state changes happen BEFORE player submission window.

### Part A: Server Processing (BEFORE Player Window)

**1. Military Unit Commissioning**
- Commission military units completed in previous turn's Maintenance Phase
- **Military units only:** Capital ships, spacelift ships (ETAC, TroopTransport)
- Frees dock space at shipyards/spaceports
- Auto-create squadrons, auto-assign to fleets
- Auto-load 1 PTU onto ETAC ships
- **Note:** Planetary defense (facilities, fighters, ground units) already commissioned in Maintenance Phase

**2. Colony Automation**
- Auto-load fighters to carriers (uses newly-freed hangar capacity)
- Auto-submit repair orders (uses newly-freed dock capacity)
- Auto-balance squadrons across fleets

**Result:** New game state exists (commissioned ships, repaired ships queued, new colonies)

### Part B: Player Submission Window (24-hour window)

Players see new game state (freed dock capacity, commissioned ships, established colonies).

**Zero-Turn Administrative Commands** (execute immediately, 0 turns):
- Fleet reorganization: DetachShips, TransferShips, MergeFleets
- Cargo operations: LoadCargo, UnloadCargo
- Squadron management: TransferShipBetweenSquadrons, AssignSquadronToFleet

**Query Commands** (read-only):
- Intel reports, fleet status, economic reports

**Order Submission** (execute later):
- Fleet orders, build orders, diplomatic actions

Players can immediately interact with newly-commissioned ships and colonies.

### Part C: Order Validation & Storage (AFTER Player Window)

**Universal Order Lifecycle:** Initiate (Part B) → Validate (Part C) → Activate (Maintenance Phase) → Execute (Conflict/Income Phase)

**Order Processing:**
1. **Administrative orders** (zero-turn): Execute immediately
   - JoinFleet, Rendezvous, Reserve, Mothball, Reactivate, ViewWorld
2. **All other orders**: Validate and store in `state.fleetOrders`
   - Movement orders (Move, Patrol, SeekHome, Hold)
   - Combat orders (Bombard, Invade, Blitz, Guard*)
   - Simultaneous orders (Colonize, SpyPlanet, SpySystem, HackStarbase)
   - Income orders (Salvage)
3. **Standing order configs**: Validated and stored in `state.standingOrders`
   - Activate in Maintenance Phase Step 1a (only if no active order exists)
4. **Build orders**: Add to construction queues
5. **Tech research**: Allocate RP

**Key Principles:**
- All non-admin orders follow same path: stored → activated → executed
- No separate queues or special handling (DRY design)
- Maintenance Phase moves fleets toward targets (all order types)
- Appropriate phase executes mission when fleet arrives

### Key Properties
- Commissioning -> Auto-repair -> Player sees accurate state
- No 1-turn perception delay (colonies established before player submission)
- Dock capacity visible includes freed space from commissioning
- Zero-turn commands execute BEFORE operational orders
- Universal lifecycle: All orders stored in `state.fleetOrders` (except admin)

---

## Phase 4: Maintenance Phase

**Purpose:** Server batch processing (movement, construction, diplomatic actions).

**Timing:** Typically midnight server time (once per day).

### Execution Order

**1. Fleet Movement and Order Activation**

**1a. Order Activation** (activate ALL orders - both active and standing)
- **Active orders:** Already validated in Command Phase Part C, now become active and ready for processing
- **Standing orders:** Check activation conditions, generate new fleet orders
- Standing orders write to `state.fleetOrders` table (same as active orders)
- Generate GameEvents (StandingOrderActivated, StandingOrderSuspended)

**1b. Order Maintenance** (lifecycle management)
- Check order completions and validate conditions
- Process order state transitions
- Not execution - just lifecycle management

**1c. Fleet Movement** (fleets move toward targets)
- Process all Move orders (Move, SeekHome, Patrol)
- Validate paths (fog-of-war, jump lanes)
- Update fleet locations (1-2 jumps per turn)
- Generate GameEvents (FleetMoved, FleetArrived)
- **Positions fleets for next turn's Conflict Phase**

**2. Construction and Repair Advancement** (parallel processing)

**2a. Construction Queue Advancement:**
- Advance build queues (ships, ground units, facilities)
- Mark projects as completed
- Consume PP/RP from treasuries
- Generate GameEvents (ConstructionProgress)

**2b. Split Commissioning (NEW - 2025-12-09):**

Completed projects split into two commissioning paths:

*Planetary Defense Assets (Commission Immediately - Same Turn):*
- **Facilities:** Starbases, Spaceports, Shipyards, Drydocks
- **Ground Defense:** Ground Batteries, Planetary Shields (SLD1-6)
- **Ground Forces:** Marines, Armies
- **Fighters:** Built planetside, commission with planetary defense
- **Strategic Rationale:** Defenders need immediate defenses against threats arriving next turn
- **Timing:** Commission immediately in Maintenance Phase Step 2b
- **Result:** Available for defense in NEXT turn's Conflict Phase ✓

*Military Units (Commission Next Turn):*
- **Capital Ships:** All ship classes (Corvette → PlanetBreaker)
- **Spacelift Ships:** ETAC, TroopTransport
- **Strategic Rationale:** Ships may be destroyed in docks during Conflict Phase
- **Timing:** Stored in pendingMilitaryCommissions, commission next turn's Command Phase Part A
- **Result:** Verified docks survived combat before commissioning

**2c. Repair Queue:**
- Advance ship repairs (1 turn at shipyards, 25% cost)
- Advance facility repairs (1 turn at spaceports, 25% cost)
- Mark repairs as completed
- Generate GameEvents (RepairCompleted)
- **Note:** Repaired units immediately operational (no commissioning delay)

**3. Diplomatic Actions**
- Process alliance proposals (accept/reject)
- Execute trade agreements (resource transfers)
- Update diplomatic statuses (Peace, War, Alliance)
- Generate GameEvents (AllianceFormed, WarDeclared, TradeCompleted)

**4. Population Transfers**
- Execute PopulationTransfer orders (via Space Lift)
- Update colony populations (PTU counts)
- Generate GameEvents (PopulationTransferred)

**5. Terraforming**
- Advance terraforming projects (turn counters)
- Complete terraforming (upgrade planet class)
- Generate GameEvents (TerraformingComplete)

**6. Cleanup and Preparation**
- Remove destroyed entities (fleets, colonies)
- Update fog-of-war visibility
- Prepare for next turn's Conflict Phase

### Key Properties
- Server processing time (no player interaction)
- Fleet movement positions for next turn's combat
- Construction and repair advance in parallel
- Completed construction commissioned next turn in Command Phase Part A
- Completed repairs immediately operational (no commissioning)
- Turn boundary: After Maintenance, increment turn counter -> Conflict Phase

---

## Fleet Order Execution Reference

### Active Fleet Orders (20 types)

| Order | Order Name            | Execution Phase   | Notes                                        |
|-------|-----------------------|-------------------|----------------------------------------------|
| 00    | Hold                  | N/A               | Defensive posture, affects combat behavior   |
| 01    | Move                  | Maintenance Phase | Fleet movement (Step 1)                      |
| 02    | Seek Home             | Maintenance Phase | Variant of Move (return to home colony)      |
| 03    | Patrol System         | Maintenance Phase | Variant of Move (patrol specific system)     |
| 04    | Guard Starbase        | N/A               | Defensive posture, affects combat screening  |
| 05    | Guard/Blockade Planet | Conflict Phase    | Blockade: Step 3, Guard: defensive posture   |
| 06    | Bombard Planet        | Conflict Phase    | Planetary Combat (Step 4)                    |
| 07    | Invade Planet         | Conflict Phase    | Planetary Combat (Step 4)                    |
| 08    | Blitz Planet          | Conflict Phase    | Planetary Combat (Step 4)                    |
| 09    | Spy on Planet         | Conflict Phase    | Fleet-Based Espionage (Step 6a)              |
| 10    | Hack Starbase         | Conflict Phase    | Fleet-Based Espionage (Step 6a)              |
| 11    | Spy on System         | Conflict Phase    | Fleet-Based Espionage (Step 6a)              |
| 12    | Colonize Planet       | Conflict Phase    | Colonization (Step 5)                        |
| 13    | Join Another Fleet    | Maintenance Phase | Fleet merging after movement                 |
| 14    | Rendezvous at System  | Maintenance Phase | Movement + auto-merge on arrival             |
| 15    | Salvage               | Income Phase      | Resource recovery (Step 4)                   |
| 16    | Place on Reserve      | Maintenance Phase | Fleet status change                          |
| 17    | Mothball Fleet        | Maintenance Phase | Fleet status change                          |
| 18    | Reactivate Fleet      | Maintenance Phase | Fleet status change                          |
| 19    | View a World          | Maintenance Phase | Movement + reconnaissance                    |

### Zero-Turn Administrative Commands (7 types)

Execute immediately during Command Phase Part B player window:

| Command                      | Execution Phase   | Notes                                        |
|------------------------------|-------------------|----------------------------------------------|
| DetachShips                  | Command Phase B   | Execute immediately during order submission  |
| TransferShips                | Command Phase B   | Execute immediately during order submission  |
| MergeFleets                  | Command Phase B   | Execute immediately during order submission  |
| LoadCargo                    | Command Phase B   | Execute immediately during order submission  |
| UnloadCargo                  | Command Phase B   | Execute immediately during order submission  |
| TransferShipBetweenSquadrons | Command Phase B   | Execute immediately during order submission  |
| AssignSquadronToFleet        | Command Phase B   | Execute immediately during order submission  |

**Key Property:** All zero-turn administrative commands execute BEFORE operational orders in same turn, allowing players to reorganize fleets and load cargo before issuing movement/combat orders.

### Standing Orders (9 types)

| Standing Order | Behavior                             | Generated Order Execution            |
|----------------|--------------------------------------|--------------------------------------|
| None           | No standing order (default)          | N/A                                  |
| PatrolRoute    | Follow patrol path indefinitely      | Move orders -> Maintenance Phase     |
| DefendSystem   | Guard system, engage per ROE         | Defensive posture (affects combat)   |
| GuardColony    | Defend specific colony               | Defensive posture (affects combat)   |
| AutoColonize   | ETACs auto-colonize nearest system   | Colonize orders -> Conflict Phase    |
| AutoReinforce  | Join nearest damaged friendly fleet  | Move/Join orders -> Maintenance      |
| AutoRepair     | Return to shipyard when crippled     | Move orders -> Maintenance Phase     |
| AutoEvade      | Retreat if outnumbered per ROE       | Move orders -> Maintenance Phase     |
| BlockadeTarget | Maintain blockade on enemy colony    | Blockade orders -> Conflict Phase    |

**Generation Timing:** Standing orders are CONFIGURED in Command Phase Part C (validated, stored in `state.standingOrders`). They GENERATE actual fleet orders during Maintenance Phase Step 1a (only if fleet has no active order). Generated orders then follow universal lifecycle: activate (move) → execute (at arrival).

---

## Critical Timing Properties

1. **Combat orders submitted Turn N execute Turn N+1 Conflict Phase**
   - Bombard, Invade, Blitz, Spy, Hack, Colonize, Blockade orders
   - One full turn delay between submission and execution

2. **Movement orders submitted Turn N execute Turn N Maintenance Phase**
   - Move, SeekHome, Patrol, Join, Rendezvous orders
   - Execute same turn as submission (at midnight server processing)

3. **Fleets move in Maintenance Phase, position for next Conflict Phase**
   - Fleet locations updated during Maintenance
   - Combat uses these new positions in next Conflict Phase

4. **Combat always uses positions from previous turn's movement**
   - No instant movement + combat exploits
   - Fleet must be positioned one turn in advance

5. **Espionage collects intel AFTER combat completes**
   - Fleet espionage: Scout reconnaissance after battles
   - Space Guild espionage: Covert ops exploit post-battle chaos

6. **Commissioning happens BEFORE player submission window**
   - Completed projects become operational before player orders
   - Dock space freed before player sees state
   - No perception delay

7. **Zero-turn commands execute DURING player submission window**
   - Immediate execution for administrative tasks
   - Players can reorganize before issuing operational orders

8. **Salvage validation: fleet must have survived Conflict Phase**
   - Destroyed ships deleted from ship lists
   - Orders from destroyed fleets become unreachable
   - No special validation needed

9. **Capacity enforcement uses post-blockade IU values**
   - Blockades applied in Income Phase Step 2
   - Capacity calculated with reduced IU in Step 5

10. **Split Commissioning System (2025-12-09)**
    - **Planetary Defense:** Commission same turn in Maintenance Phase Step 2b
      - Facilities, ground units, fighters available for next turn's defense
    - **Military Units:** Commission next turn in Command Phase Part A
      - Ships verified docks survived combat before commissioning
    - **Strategic Timing:** Defenders get immediate protection, ships wait for safety check

---

## Testing Scenarios

### Scenario 1: Fleet Movement -> Combat Sequence
1. Turn N Command: Submit Move order to enemy system
2. Turn N Maintenance: Fleet moves to enemy system
3. Turn N+1 Conflict: Fleet participates in space combat at new location
4. **Validates:** Movement timing, combat positioning

### Scenario 2: Planetary Assault Sequence
1. Turn N Command: Submit Bombard order against enemy colony
2. Turn N Maintenance: Fleet remains in position
3. Turn N+1 Conflict: Bombard executes after space/orbital combat
4. Turn N+1 Income: Production calculated with damaged infrastructure
5. **Validates:** Combat order timing, economic impact propagation

### Scenario 3: Salvage Recovery Sequence
1. Turn N Conflict: Fleet survives battle, debris present
2. Turn N Command: Submit Salvage order
3. Turn N+1 Conflict: Fleet survives again (or not)
4. Turn N+1 Income Step 4: Salvage executes if fleet survived
5. **Validates:** Salvage survival validation, destroyed ship cleanup

### Scenario 4: Capacity Enforcement Sequence
1. Turn N Conflict: Colony captured, IU drops
2. Turn N Income Step 2: Blockade applied, IU drops further
3. Turn N Income Step 5: Capacity calculated with reduced IU
4. Turn N Income Step 5a: Capital squadrons seized immediately
5. Turn N Income Step 5b: Total squadron grace period starts
6. Turn N+2 Income: Grace period expires, escorts disbanded
7. **Validates:** Capacity enforcement timing, grace periods

### Scenario 5: Construction -> Commissioning Sequence
1. Turn N-1 Maintenance: Construction completes, marked complete
2. Turn N Command Part A: Completed project commissioned
3. Turn N Command Part B: Player sees commissioned ship, can reorganize
4. Turn N Command Part B: Player submits orders for new ship
5. Turn N Maintenance: New ship movement orders execute
6. **Validates:** Commissioning timing, no perception delay

---

## Architecture Principles

### Separation of Concerns
- **Conflict Phase:** Pure combat resolution (no economic calculations)
- **Income Phase:** Pure economic state (no combat, no movement)
- **Command Phase:** Pure player interaction (no server processing in Part B)
- **Maintenance Phase:** Pure server processing (no player interaction)

### Deterministic Execution
- All phases execute in strict order
- No phase can skip or reorder
- All steps within phases execute in strict order
- Simultaneous resolution where appropriate (prevents first-mover advantage)

### Data Flow
```
Conflict Phase -> Combat results
Income Phase -> Economic state, treasury levels
Command Phase -> Validated orders, build queues
Maintenance Phase -> New positions, completed construction
-> Next Conflict Phase
```

### Timing Guarantees
- Combat orders: 1 turn delay (Turn N submission -> Turn N+1 execution)
- Movement orders: Same turn execution (Turn N submission -> Turn N Maintenance)
- Zero-turn commands: Immediate execution (during submission window)
- Commissioning: Before player sees state (no perception delay)

### State Consistency
- Game state changes (commissioning) happen before player window
- Players always see accurate, up-to-date state
- No stale data from previous turn
- Destroyed entities immediately removed from data structures

---

## Phase Block Diagrams

### Phase 1: Conflict Phase

```
╔════════════════════════════════════════════════════════════╗
║                    CONFLICT PHASE (Turn N)                 ║
║                Orders from Turn N-1 Execute                ║
╠════════════════════════════════════════════════════════════╣
║                                                            ║
║  ╔═══════════════════════════════════════════════════════╗ ║
║  ║ Step 1: Space Combat (Simultaneous)                   ║ ║
║  ║  • Collect all space combat intents                   ║ ║
║  ║  • Resolve conflicts (determine winners)              ║ ║
║  ║  • Execute combat engine for all battles              ║ ║
║  ║  • GameEvents: ShipDestroyed, FleetEliminated         ║ ║
║  ╚═══════════════════════════════════════════════════════╝ ║
║                             |                              ║
║                             v                              ║
║  ╔═══════════════════════════════════════════════════════╗ ║
║  ║ Step 2: Orbital Combat (Simultaneous)                 ║ ║
║  ║  • Collect orbital bombardment intents                ║ ║
║  ║  • Execute orbital strikes sequentially               ║ ║
║  ║  • GameEvents: StarbaseDestroyed, DefensesWeakened    ║ ║
║  ╚═══════════════════════════════════════════════════════╝ ║
║                             |                              ║
║                             v                              ║
║  ╔═══════════════════════════════════════════════════════╗ ║
║  ║ Step 3: Blockade Resolution (Simultaneous)            ║ ║
║  ║  • Collect blockade intents                           ║ ║
║  ║  • Determine blockade controller                      ║ ║
║  ║  • Establish blockade status -> Income Phase          ║ ║
║  ║  • GameEvents: BlockadeEstablished, BlockadeBroken    ║ ║
║  ╚═══════════════════════════════════════════════════════╝ ║
║                             |                              ║
║                             v                              ║
║  ╔═══════════════════════════════════════════════════════╗ ║
║  ║ Step 4: Planetary Combat (Sequential Priority)        ║ ║
║  ║  • Bombard/Invade/Blitz orders execute                ║ ║
║  ║  • Weaker attackers benefit from prior damage         ║ ║
║  ║  • GameEvents: SystemCaptured, ColonyCaptured         ║ ║
║  ╚═══════════════════════════════════════════════════════╝ ║
║                             |                              ║
║                             v                              ║
║  ╔═══════════════════════════════════════════════════════╗ ║
║  ║ Step 5: Colonization (Simultaneous)                   ║ ║
║  ║  • ETAC fleets establish colonies                     ║ ║
║  ║  • Resolve conflicts (winner-takes-all)               ║ ║
║  ║  • GameEvents: ColonyEstablished                      ║ ║
║  ╚═══════════════════════════════════════════════════════╝ ║
║                             |                              ║
║                             v                              ║
║  ╔═══════════════════════════════════════════════════════╗ ║
║  ║ Step 6: Espionage Operations (Simultaneous)           ║ ║
║  ║  6a. Fleet-Based: SpyPlanet, SpySystem, HackStarbase  ║ ║
║  ║  6b. Space Guild: Tech Theft, Sabotage, etc.          ║ ║
║  ║  • GameEvents: IntelGathered, EspionageSuccess        ║ ║
║  ╚═══════════════════════════════════════════════════════╝ ║
║                                                            ║
╠════════════════════════════════════════════════════════════╣
║ OUTPUT: Combat results, destroyed entities, intel gathered ║
╚════════════════════════════════════════════════════════════╝
```

### Phase 2: Income Phase

```
╔═══════════════════════════════════════════════════════════════╗
║                      INCOME PHASE (Turn N)                    ║
║              Economic State & Capacity Enforcement            ║
╠═══════════════════════════════════════════════════════════════╣
║                                                               ║
║  ╔═══════════════════════════════════════════════════════╗    ║
║  ║ Step 1: Calculate Base Production                     ║    ║
║  ║  • PP/RP from colonies (planet class + resources)     ║    ║
║  ║  • Apply improvements (Infrastructure, Labs)          ║    ║
║  ║  • Apply espionage effects (sabotage, cyber)          ║    ║
║  ╚═══════════════════════════════════════════════════════╝    ║
║                             |                                 ║
║                             v                                 ║
║  ╔═══════════════════════════════════════════════════════╗    ║
║  ║ Step 2: Apply Blockades (from Conflict Phase)         ║    ║
║  ║  • Blockaded colonies: 50% production penalty         ║    ║
║  ║  • Update economic output                             ║    ║
║  ╚═══════════════════════════════════════════════════════╝    ║
║                             |                                 ║
║                             v                                 ║
║  ╔═══════════════════════════════════════════════════════╗    ║
║  ║ Step 3: Calculate Maintenance Costs                   ║    ║
║  ║  • Maintenance for surviving ships/facilities         ║    ║
║  ║  • Deduct from house treasuries                       ║    ║
║  ║  • GameEvents: MaintenancePaid                        ║    ║
║  ╚═══════════════════════════════════════════════════════╝    ║
║                             |                                 ║
║                             v                                 ║
║  ╔═══════════════════════════════════════════════════════╗    ║
║  ║ Step 4: Execute Salvage Orders                        ║    ║
║  ║  • Validate fleet survived Conflict Phase             ║    ║
║  ║  • Recover PP from debris                             ║    ║
║  ║  • GameEvents: ResourcesSalvaged                      ║    ║
║  ╚═══════════════════════════════════════════════════════╝    ║
║                             |                                 ║
║                             v                                 ║
║  ╔═════════════════════════════════════════════════════════╗  ║
║  ║ Step 5: Capacity Enforcement (Table 10.5)               ║  ║
║  ║  5a. Capital Squadrons -> Immediate Space Guild seizure ║  ║
║  ║  5b. Total Squadrons -> 2-turn grace, then disband      ║  ║
║  ║  5c. Fighter Squadrons -> 2-turn grace, then disband    ║  ║
║  ║  5d. Planet-Breakers -> Instant scrap when colony lost  ║  ║
║  ╚═════════════════════════════════════════════════════════╝  ║
║                             |                                 ║
║                             v                                 ║
║  ╔═══════════════════════════════════════════════════════╗    ║
║  ║ Steps 6-9: Finalization                               ║    ║
║  ║  • Collect resources (PP/RP + salvage + seizures)     ║    ║
║  ║  • Calculate prestige                                 ║    ║
║  ║  • Check victory conditions                           ║    ║
║  ║  • Advance timers                                     ║    ║
║  ╚═══════════════════════════════════════════════════════╝    ║
║                                                               ║
╠═══════════════════════════════════════════════════════════════╣
║ OUTPUT: Updated treasuries, prestige, victory status          ║
╚═══════════════════════════════════════════════════════════════╝
```

### Phase 3: Command Phase

```
╔════════════════════════════════════════════════════════════╗
║                    COMMAND PHASE (Turn N)                  ║
║          Server Processing -> Player Window -> Validation  ║
╠════════════════════════════════════════════════════════════╣
║                                                            ║
║  ╔═══════════════════════════════════════════════════════╗ ║
║  ║ PART A: Server Processing (BEFORE Player Window)      ║ ║
║  ║                                                       ║ ║
║  ║  Step 1: Commissioning                                ║ ║
║  ║   • Commission completed projects                     ║ ║
║  ║   • Free dock space                                   ║ ║
║  ║   • Auto-create squadrons, assign to fleets           ║ ║
║  ║   • Auto-load 1 PTU onto ETAC ships                   ║ ║
║  ║                                                       ║ ║
║  ║  Step 2: Colony Automation                            ║ ║
║  ║   • Auto-load fighters to carriers                    ║ ║
║  ║   • Auto-submit repair orders                         ║ ║
║  ║   • Auto-balance squadrons                            ║ ║
║  ╚═══════════════════════════════════════════════════════╝ ║
║                             |                              ║
║                             v                              ║
║  ╔═══════════════════════════════════════════════════════╗ ║
║  ║ PART B: Player Submission Window (24 hours)           ║ ║
║  ║                                                       ║ ║
║  ║  Players see accurate game state:                     ║ ║
║  ║   • Commissioned ships operational                    ║ ║
║  ║   • Freed dock space visible                          ║ ║
║  ║   • Established colonies accessible                   ║ ║
║  ║                                                       ║ ║
║  ║  Zero-Turn Commands (Execute Immediately):            ║ ║
║  ║   • DetachShips, TransferShips, MergeFleets           ║ ║
║  ║   • LoadCargo, UnloadCargo                            ║ ║
║  ║   • TransferShipBetweenSquadrons                      ║ ║
║  ║                                                       ║ ║
║  ║  Order Submission (Execute Later):                    ║ ║
║  ║   • Fleet orders -> Conflict/Maintenance Phase        ║ ║
║  ║   • Build orders -> Construction queues               ║ ║
║  ║   • Diplomatic actions -> Maintenance Phase           ║ ║
║  ╚═══════════════════════════════════════════════════════╝ ║
║                             |                              ║
║                             v                              ║
║  ╔═══════════════════════════════════════════════════════╗ ║
║  ║ PART C: Order Validation & Queueing (AFTER Window)   ║ ║
║  ║   • Validate all submitted orders                     ║ ║
║  ║   • Process build orders (add to queues)              ║ ║
║  ║   • Start tech research (allocate RP)                 ║ ║
║  ║   • Queue combat orders for Turn N+1 Conflict         ║ ║
║  ║   • Store movement orders for Maintenance activation  ║ ║
║  ║   • Note: Standing orders validated, not activated    ║ ║
║  ╚═══════════════════════════════════════════════════════╝ ║
║                                                            ║
╠════════════════════════════════════════════════════════════╣
║ OUTPUT: Validated orders queued, no execution              ║
╚════════════════════════════════════════════════════════════╝
```

### Phase 4: Maintenance Phase

```
╔════════════════════════════════════════════════════════════╗
║                  MAINTENANCE PHASE (Turn N)                ║
║              Server Batch Processing (Midnight)            ║
╠════════════════════════════════════════════════════════════╣
║                                                            ║
║  ╔═══════════════════════════════════════════════════════╗ ║
║  ║ Step 1: Fleet Movement & Order Activation            ║ ║
║  ║                                                       ║ ║
║  ║  1a. Order Activation (active + standing)            ║ ║
║  ║   • Active orders: validated → active (ready)        ║ ║
║  ║   • Standing orders: check conditions → generate     ║ ║
║  ║   • GameEvents: StandingOrderActivated               ║ ║
║  ║                                                       ║ ║
║  ║  1b. Order Maintenance (lifecycle management)        ║ ║
║  ║   • Check completions, validate conditions           ║ ║
║  ║   • Process order state transitions                  ║ ║
║  ║                                                       ║ ║
║  ║  1c. Fleet Movement (fleets move to targets)         ║ ║
║  ║   • Process Move, SeekHome, Patrol orders            ║ ║
║  ║   • Validate paths (fog-of-war, jump lanes)          ║ ║
║  ║   • Update fleet locations (1-2 jumps/turn)          ║ ║
║  ║   • GameEvents: FleetMoved, FleetArrived             ║ ║
║  ╚═══════════════════════════════════════════════════════╝ ║
║                             |                              ║
║                             v                              ║
║  ╔═══════════════════════════════════════════════════════╗ ║
║  ║ Step 2: Construction & Repair (Parallel Processing)   ║ ║
║  ║                                                       ║ ║
║  ║  Construction Queue:                                  ║ ║
║  ║   • Advance build queues (ships, units, facilities)   ║ ║
║  ║   • Mark projects as completed                        ║ ║
║  ║   • Consume PP/RP from treasuries                     ║ ║
║  ║   • Completed -> Commission next Command Phase        ║ ║
║  ║                                                       ║ ║
║  ║  Repair Queue:                                        ║ ║
║  ║   • Advance ship/facility repairs (1 turn, 25% cost)  ║ ║
║  ║   • Mark repairs as completed                         ║ ║
║  ║   • Repaired -> Immediately operational               ║ ║
║  ╚═══════════════════════════════════════════════════════╝ ║
║                             |                              ║
║                             v                              ║
║  ╔═══════════════════════════════════════════════════════╗ ║
║  ║ Step 3: Diplomatic Actions                            ║ ║
║  ║  • Process alliance proposals                         ║ ║
║  ║  • Execute trade agreements                           ║ ║
║  ║  • Update diplomatic statuses                         ║ ║
║  ║  • GameEvents: AllianceFormed, WarDeclared            ║ ║
║  ╚═══════════════════════════════════════════════════════╝ ║
║                             |                              ║
║                             v                              ║
║  ╔═══════════════════════════════════════════════════════╗ ║
║  ║ Steps 4-6: Additional Processing                      ║ ║
║  ║  • Population transfers (Space Lift)                  ║ ║
║  ║  • Terraforming advancement                           ║ ║
║  ║  • Cleanup destroyed entities                         ║ ║
║  ║  • Update fog-of-war visibility                       ║ ║
║  ║  • Prepare for next turn                              ║ ║
║  ╚═══════════════════════════════════════════════════════╝ ║
║                             |                              ║
║                             v                              ║
║                  Increment Turn Counter                    ║
║                             |                              ║
║                             v                              ║
║              -> Next Turn Conflict Phase                   ║
║                                                            ║
╠════════════════════════════════════════════════════════════╣
║ OUTPUT: New positions, completed construction, turn N+1    ║
╚════════════════════════════════════════════════════════════╝
```

### Complete Turn Cycle Flow

```
     ╔══════════════════════════════════════════════════╗
     ║                   Turn N-1                       ║
     ║            (Orders Submitted Here)               ║
     ╚══════════════════╦═══════════════════════════════╝
                        ║
                        ↓
     ╔══════════════════════════════════════════════════╗
     ║         PHASE 1: CONFLICT (Turn N)               ║
     ║    Execute orders from Turn N-1                  ║
     ║    • Space -> Orbital -> Blockade -> Planetary   ║
     ║    • Colonization -> Espionage                   ║
     ╚══════════════════╦═══════════════════════════════╝
                        ║ Combat Results
                        ↓
     ╔══════════════════════════════════════════════════╗
     ║          PHASE 2: INCOME (Turn N)                ║
     ║    Economic calculations & capacity enforcement  ║
     ║    • Production -> Blockades -> Maintenance      ║
     ║    • Salvage -> Capacity -> Resources            ║
     ╚══════════════════╦═══════════════════════════════╝
                        ║ Economic State
                        ↓
     ╔══════════════════════════════════════════════════╗
     ║         PHASE 3: COMMAND (Turn N)                ║
     ║    Part A: Commissioning (before player window)  ║
     ║    Part B: Player submission (24-hour window)    ║
     ║    Part C: Order validation (after player window)║
     ╚══════════════════╦═══════════════════════════════╝
                        ║ Validated Orders
                        ↓
     ╔══════════════════════════════════════════════════╗
     ║        PHASE 4: MAINTENANCE (Turn N)             ║
     ║    Server processing at midnight                 ║
     ║    • Movement -> Construction -> Diplomacy       ║
     ║    • Increment turn counter                      ║
     ╚══════════════════╦═══════════════════════════════╝
                        ║
                        ↓
     ╔══════════════════════════════════════════════════╗
     ║              Turn N+1 Begins                     ║
     ║         -> PHASE 1: CONFLICT                     ║
     ╚══════════════════════════════════════════════════╝
```

---

## Glossary

**AS (Attack Strength):** Combat effectiveness rating for squadrons  
**CR (Combat Rating):** Ship size class (≥7 for capital ships)  
**EBP (Espionage Budget Points):** Currency for Space Guild covert operations  
**ETAC (Explorer/Transport/Armed Colonizer):** Colony ship type  
**FD_MULTIPLIER:** Fighter defense capacity multiplier per colony  
**IU (Industrial Units):** Colony economic output measure  
**NCV (Net Colony Value):** Total economic value of colony infrastructure  
**PP (Production Points):** Industrial manufacturing currency  
**PTU (Population Transport Units):** Population cargo units  
**RP (Research Points):** Scientific research currency  
**SRP (Science Research Points):** Alternative term for RP  

**Simultaneous Resolution:** All players' orders collected, conflicts resolved, then executed in priority order  
**Sequential Execution:** Orders execute one at a time in strict order  
**Grace Period:** Time buffer before capacity enforcement triggers  
**Commissioning:** Process of making completed construction operational  
**Zero-Turn Command:** Administrative order that executes immediately