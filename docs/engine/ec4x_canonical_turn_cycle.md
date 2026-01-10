# EC4X Canonical Turn Sequence Specification

**Purpose:** Complete and definitive turn order specification for EC4X  
**Last Updated:** 2026-01-09
**Status:** Implementation Complete (Unified Commissioning + Repair System)

---

## Reference Notation

For unambiguous cross-references, steps use phase prefixes:

| Phase | Prefix | Example |
|-------|--------|---------|
| Conflict | CON | CON1a (Space combat) |
| Income | INC | INC7a (C2 Pool Logistical Strain) |
| Command | CMD | CMD2 (Unified Commissioning) |
| Production | PRD | PRD1a (Fleet Travel) |

Within each phase section, steps are numbered 1, 2, 3... with substeps a, b, c...

---

## Overview

EC4X uses a four-phase turn structure that separates combat resolution, economic calculation, player decision-making, and server processing. Each phase has distinct timing and execution properties.

**The Four Phases:**
1. **Conflict Phase** - Resolve all combat and espionage (commands from previous engine turn)
2. **Income Phase** - Calculate economics, enforce capacity limits, check victory conditions
3. **Command Phase** - Server commissioning, player submission of new commands, command validation
4. **Production Phase** - Server processing: movement, construction, diplomacy, and turn counter incrementation

**Key Timing Principle:** Combat commands submitted by the player in their turn N execute in the Conflict Phase of engine turn N+1. Fleet travel (derived from commands submitted in player turn N) executes in the Production Phase of engine turn N.

---

## Complete Turn Cycle Architecture (Hierarchical Overview)

```
TURN N - CONFLICT PHASE (CON)
├─ 1. Combat Resolution
│  ├─ 1a. Space combat (mobile fleets)
│  ├─ 1b. Orbital combat (guard fleets, starbases, reserves)
│  ├─ 1c. Blockade resolution
│  ├─ 1d. Planetary combat (bombardment, invasion, blitz)
│  ├─ 1e. Colonization
│  ├─ 1f. Scout Intelligence Operations
│  └─ 1g. Administrative Completion (mark commands done)
│
└─ 2. Immediate Combat Effects
   ├─ 2a. Remove destroyed entities:
   │  ├─ Ships (CombatState.Destroyed)
   │  ├─ Neorias (Spaceport/Shipyard/Drydock)
   │  ├─ Kastras (Starbases)
   │  └─ Ground units (marines, armies, batteries, shields)
   │
   ├─ 2b. Clear destroyed Neoria queues:
   │  ├─ Spaceport constructionQueue
   │  ├─ Shipyard constructionQueue
   │  ├─ Drydock repairQueue
   │  └─ Ships/projects in destroyed docks = LOST
   │
   ├─ 2c. Clear crippled Neoria queues:
   │  ├─ Neoria.state = Crippled
   │  ├─ Neoria.effectiveDocks = 0
   │  ├─ Clear all queues (constructionQueue, repairQueue)
   │  ├─ Ships/projects in crippled docks = LOST
   │  └─ Facility can be repaired (25% build cost via colony queue)
   │
   ├─ 2d. Process colony conquest:
   │  ├─ Transfer ownership: colony.owner = attacker
   │  ├─ Clear colony.constructionQueue
   │  ├─ Clear colony.repairQueue
   │  ├─ Clear colony.underConstruction
   │  ├─ Cancel colony.activeTerraforming
   │  └─ Generate ColonyCaptured event (with projectsLost counts)
   │
   └─ 2e. Process severe bombardment (>50% infrastructure):
      ├─ If infrastructureDamaged > (colony.infrastructure * 0.5):
      ├─ Clear colony.constructionQueue
      ├─ Clear colony.repairQueue
      ├─ Clear colony.underConstruction
      ├─ Cancel colony.activeTerraforming
      └─ Generate ColonyProjectsLost event

State is now clean for Income Phase

TURN N - INCOME PHASE (INC)
├─ 1. Apply Ongoing Espionage Effects
├─ 2. Process EBP/CIP Investment
├─ 3. Calculate Base Production (uses post-combat colony ownership)
├─ 4. Apply Blockades
├─ 5. Execute Salvage Commands
├─ 6. Maintenance Processing
│  ├─ 6a. Calculate Total Maintenance
│  ├─ 6b. Payment Processing (full/partial/none)
│  ├─ 6c. Shortfall Penalties (crippling, infrastructure, prestige)
│  └─ 6d. Auto-Salvage Check (maintenance-crippled ships)
├─ 7. Capacity Enforcement (uses post-combat ownership/IU)
│  ├─ 7a. C2 Pool Logistical Strain (soft cap, financial penalty)
│  ├─ 7b. Fighter Capacity (2-turn grace)
│  └─ 7c. Planet-Breaker Enforcement (immediate)
├─ 8. Collect Resources
├─ 9. Calculate Prestige (from Conflict Phase events)
├─ 10. House Elimination & Victory Checks
│   ├─ 10a. House Elimination
│   └─ 10b. Victory Conditions
└─ 11. Advance Timers

TURN N - COMMAND PHASE (CMD)
├─ 1. Order Cleanup
│  └─ Clear completed/failed/aborted commands from previous turn
│
├─ 2. Unified Commissioning
│  ├─ Commission ships from Neorias:
│  │  ├─ Iterate all Spaceports → commission pending ships
│  │  ├─ Iterate all Shipyards → commission pending ships
│  │  ├─ Free dock capacity
│  │  └─ No validation needed (Neoria exists = survived Conflict)
│  │
│  ├─ Commission repaired ships from Drydocks:
│  │  ├─ Iterate all Drydocks → check repairs
│  │  ├─ For each pending repair:
│  │  │  ├─ Check treasury (once per turn, here)
│  │  │  ├─ If sufficient: Pay repair cost, commission, free dock
│  │  │  ├─ If insufficient: Mark Stalled (stays in queue)
│  │  │  └─ Generate RepairCompleted or RepairStalled event
│  │  └─ No validation needed (Drydock exists = survived Conflict)
│  │
│  └─ Commission assets from colonies:
│     ├─ Iterate all colonies → commission pending assets:
│     │  ├─ Fighters
│     │  ├─ Ground units (marines, armies)
│     │  ├─ Defensive facilities (batteries, shields)
│     │  ├─ Starbases (Kastras)
│     │  └─ Neorias (Spaceports, Shipyards, Drydocks)
│     └─ No validation needed (Colony exists = survived Conflict)
│
├─ 3. Auto-Repair Submission (Before Player Window)
│  └─ For each colony where colony.autoRepair = true:
│     ├─ Priority 1: Crippled ships → Available Drydock queues
│     ├─ Priority 2: Crippled starbases → Colony repair queue
│     ├─ Priority 2: Crippled ground units → Colony repair queue
│     ├─ Priority 3: Crippled Neorias → Colony repair queue
│     └─ NOTE: Player can cancel/modify these in submission window
│
├─ 4. Colony Automation
│  └─ For each colony:
│     ├─ 4a. Auto-assign ships to fleets (always enabled, in CMD2)
│     │  └─ NOTE: Implemented in CMD2 commissioning, not here
│     ├─ 4b. If colony.autoLoadMarines = true:
│     │  └─ Auto-load marines onto troop transports
│     └─ 4c. Auto-load fighters onto carriers (in CMD2c)
│        └─ NOTE: Implemented in CMD2c commissioning, not here
│
├─ 5. Player Submission Window (24-hour window)
│  ├─ 5a. Zero-Turn Administrative Commands (immediate)
│  ├─ 5b. Query Commands (read-only)
│  └─ 5c. Command Submission (queued)
│     ├─ Commissioned assets (newly available)
│     ├─ Auto-repair submissions (can cancel/modify)
│     └─ Automated fleet/cargo assignments (result of CMD4)
│
└─ 6. Order Processing & Validation
   ├─ 6a. Validate fleet commands (store in Fleet.command)
   ├─ 6b. Process build orders (pay PP upfront)
   │  ├─ Ships → Neoria construction queues
   │  ├─ Fighters/Ground units/Facilities → Colony queues
   │  └─ Validate budget, capacity before queuing
   ├─ 6c. Process repair orders (manual, overrides auto-repair)
   └─ 6d. Process tech research allocation

TURN N - PRODUCTION PHASE (PRD)
├─ 1. Fleet Movement
│  ├─ 1a. Fleet Travel
│  ├─ 1b. Fleet Arrival Detection
│  ├─ 1c. Administrative Completion (Production commands)
│  └─ 1d. Scout-on-Scout Detection
│
├─ 2. Construction & Repair Advancement
│  ├─ 2a. Advance construction queues (Spaceport/Shipyard/Colony)
│  │  └─ For each project: decrement turnsRemaining
│  │     └─ If turnsRemaining = 0: Mark AwaitingCommission
│  └─ 2b. Advance repair queues (Drydock/Colony)
│     └─ For each repair: decrement turnsRemaining
│        └─ If turnsRemaining = 0: Mark AwaitingCommission
│     (Commissioning deferred to CMD2)
│
├─ 3. Diplomatic Actions
├─ 4. Population Transfers
├─ 5. Terraforming
├─ 6. Cleanup and Preparation
└─ 7. Research Advancement
   ├─ 7a. Breakthrough Rolls
   ├─ 7b. Economic Level Advancement
   ├─ 7c. Science Level Advancement
   └─ 7d. Technology Field Advancement
```

---

### Turn Progression (Engine vs. Player)

To avoid ambiguity, we distinguish between the **Engine's Turn Counter** (a continuous, internal value) and a **Player's Perceived Turn** (the cycle of action and outcome they experience).

- **Engine's Turn Counter:** This internal counter increments *once* at the end of the Production Phase, after all processing for the current engine turn is complete.

- **Player's Perceived Turn N:**
  - **Begins:** When the player first sees the game state and submits commands in the **Command Phase** (of a given engine turn, e.g., Engine Turn X).
  - **Player Actions:** Submits fleet commands, build commands, diplomatic changes, research allocations.
  - **Immediate Results:** Zero-turn administrative commands (e.g., Load Cargo, Fleet Reorganization) execute instantly within this Command Phase.
  - **Delayed Results:** Operational commands (movement, combat, espionage, colonization) are queued for later engine phases.

- **Engine Processing for Player's Perceived Turn N:**
  - **Production Phase (Engine Turn X):** Executes movement commands submitted by the player in the preceding Command Phase (of Engine Turn X). Also advances construction/repairs, and increments the **Engine's Turn Counter to X+1**.
  - **Conflict Phase:** Resolves combat, espionage, and colonization based on fleet positions and commands from the *previous* player turn (i.e., player commands submitted in Command Phase of Engine Turn N, whose travel resolved in Production Phase of Engine Turn N).
  - **Income Phase:** Calculates economic results, prestige, and victory conditions for the results of the Conflict Phase. This is where the *player sees the outcome* of their Player's Perceived Turn N, and often marks the *end* of that perceived turn.

**Simplified Flow for Player's Turn N:**
1.  **Player Acts:** Submits commands (Engine's Command Phase).
2.  **Server Processes Travel/Construction:** Player's fleets travel towards objectives (Engine's Production Phase).
3.  **Server Resolves Combat:** Actions from *previous* player turn commands resolve (Engine's Conflict Phase).
4.  **Server Calculates Economy/Presents Results:** Player sees outcomes (Engine's Income Phase).

This structure means that a player's submitted commands will often manifest their full impact across two engine turns, particularly for combat-related actions.

---

## Command Lifecycle (Universal for All Commands)

EC4X uses a simple three-phase command processing lifecycle:

### Submit (CMD5 - Player Submission Window)
- Player submits commands via `CommandPacket`
- Commands queued for validation
- Phase: CMD5

### Store (CMD6 - Order Processing & Validation)
- Engine validates commands (syntax, resources, permissions)
- Valid commands stored in `Fleet.command` field (entity-manager pattern)
- Fleet `missionState` set to `Traveling`
- Invalid commands rejected with error events
- Phase: CMD6

### Execute (Production/Conflict/Income Phase)
- **Production Phase**: Fleet travel (PRD1a), arrival detection (PRD1b), administrative completion (PRD1c)
- **Conflict Phase**: Combat, colonization, scout intelligence (filter: `missionState == Executing`)
- **Income Phase**: Economic operations (Salvage)
- Results generate events (`CommandCompleted`, `CommandFailed`, etc.)
- Phase: Depends on command type

**Key Insight:** All commands follow the SAME lifecycle:
- Submit (CMD5) → Store (CMD6) → Execute (PRD/CON/INC)

---

## Phase 1: Conflict Phase

**Purpose:** Resolve all combat, colonization, and scout intelligence operations submitted previous turn.

**Timing:** Commands submitted Turn N-1 execute Turn N.

### Execution Order

**Note:** Commands are executed directly from `Fleet.command` field (entity-manager pattern).
No merge step needed - fleets with `missionState == Executing` have arrived at targets and execute their commands.

**Universal command lifecycle:**
- CMD6: Commands validated and stored in `Fleet.command`, `missionState` set to `Traveling`
- PRD1a: Fleets move toward targets
- PRD1b: Arrivals detected, `Fleet.missionState` set to `Executing`
- CON1: Commands execute (filter: missionState == Executing)

### Combat Participant Determination

Before resolving combat, determine which fleets engage based on diplomatic status, mission threat level, territorial ownership, and mission phase. Uses `ThreatLevel` enum and `CommandThreatLevels` from `src/engine/types/fleet.nim`.

**Step 1: Identify Fleet Location and Mission Phase**
- `missionState == Executing`: Fleet is at mission target (destination)
- `missionState == Traveling`: Fleet is in transit, paused at intermediate system

**Step 2: Determine Territorial Ownership**
- **Own territory**: System contains your colony
- **Their territory**: System contains another house's colony
- **Neutral territory**: System has no colony (uncolonized)

**Step 3: Get Fleet ThreatLevel**
```nim
let threatLevel = CommandThreatLevels[fleet.command.commandType]
# Attack: Blockade, Bombard, Invade, Blitz (target: colony)
# Contest: Patrol, Hold, Rendezvous (target: system)
# Benign: All others
```

**Step 4: Determine Combat Eligibility**

Combat requires both houses to have fleets present at the same location. For each pair of houses with fleets in the same system, check:

**During Travel (Intermediate Systems):**

| Diplomatic Status | Result |
|-------------------|--------|
| **Enemy** | Combat (automatic, simultaneous) |
| **Hostile** | No combat (safe passage) |
| **Neutral** | No combat (safe passage) |

**Note:** Hold fleets and Guard fleets (GuardColony, GuardStarbase) do NOT participate in space combat. They only engage during orbital combat when their colony is directly targeted.

**At Destination - Their Colony (Tier 1 Attack Missions):**

| Diplomatic Status | Tier 1 (Attack) | Result |
|-------------------|-----------------|--------|
| **Enemy** | Blockade/Bombard/Invade/Blitz | Combat |
| **Hostile** | Blockade/Bombard/Invade/Blitz | Escalate→Enemy, combat |
| **Neutral** | Blockade/Bombard/Invade/Blitz | Escalate→Enemy, combat |

**At Destination - Their System (Tier 2 Contest Missions):**

| Diplomatic Status | Tier 2 (Contest) | Result |
|-------------------|------------------|--------|
| **Enemy** | Patrol/Hold/Rendezvous | Combat |
| **Hostile** | Patrol/Hold/Rendezvous | Combat |
| **Neutral** | Patrol/Hold/Rendezvous | Escalate→Hostile, NO combat |

**At Destination - Neutral System (Uncolonized):**

| Diplomatic Status | Any Mission | Result |
|-------------------|-------------|--------|
| **Enemy** | Any | Combat |
| **Hostile** | Any | No combat |
| **Neutral** | Any | No combat |

**At Destination - Own System:**

| Diplomatic Status | Any Mission | Result |
|-------------------|-------------|--------|
| **Enemy** | Any | Combat (if enemy fleet present) |
| **Hostile/Neutral** | Any | No combat (own territory, no threat) |

**Defender Engagement Rules:**
- Defenders do NOT intercept fleets traveling through unless Enemy status
- Defenders engage based on threat to their system/colony, not mere fleet presence
- At Enemy status: Both sides engage on sight (mutual, simultaneous combat)
- All combat is simultaneous - no attacker/defender initiative advantage

**Fleet Participation in Enemy Encounters:**
When Enemy fleets meet at any location, all Active fleets (except Hold and Guard) participate in space combat, regardless of their current mission. A fleet with a Move command paused at an intermediate system will fight if an Enemy fleet is present. Hold and Guard fleets only participate in orbital combat.

**Grace Period Logic:**
- The only "grace period" is the Neutral→Hostile transition itself
- Once at Hostile status, Tier 2 missions trigger combat immediately
- There is no additional waiting period for houses already at Hostile status

**Implementation Reference:** `docs/specs/08-diplomacy.md` Section 8.1.5-8.1.6

### 1. Combat Resolution

**1a. Space Combat** (simultaneous resolution)
- Filter participants: Patrol fleets, offensive missions (Bombard/Invade/Blitz/Blockade), fleets traveling through
- Exclude from combat: Hold fleets, Guard fleets, Reserve fleets, Mothballed fleets
- Scouts: Slip through combat undetected (stealthy, not present in combat)
- Screened (present but don't fight): Auxiliary vessels (ETACs, Troop Transports) - suffer proportional losses on retreat, destroyed if fleet eliminated
- Apply diplomatic filtering (see above) to determine which fleets engage
- Perform detection checks for all engaging fleets containing Raiders to determine ambush advantage
- Collect all space combat intents, resolve conflicts, and execute the combat engine, applying any first-strike bonuses

**Combat Resolution Details:** See `docs/specs/07-combat.md` for complete combat mechanics including ROE thresholds, detection/ambush, Combat Results Tables, and fighter superiority.
- Generate `GameEvents` (ShipDestroyed, FleetEliminated)

**1b. Orbital Combat** (simultaneous resolution)
- Filter participants: Hold fleets, Guard fleets, Reserve fleets (50% AS), Starbases, unassigned ships
- Exclude from combat: Mothballed fleets
- Scouts: Not present (stealthy, slip through to conduct missions)
- Screened (present but don't fight): Auxiliary vessels (ETACs, Troop Transports) - suffer proportional losses on retreat, destroyed if defenders eliminated
- Reserve fleets fight at 50% AS with auto-assigned GuardColony command
- Perform a new round of detection checks for fleets engaging in orbital combat
- Collect all orbital combat intents, resolve conflicts, and execute strikes sequentially, applying any first-strike bonuses
- Generate `GameEvents` (StarbaseDestroyed, DefensesWeakened)

**1c. Blockade Resolution** (simultaneous resolution)
- Collect all blockade intents
- Resolve conflicts (determine blockade controller)
- Establish blockade status (affects Income Phase)
- Generate `GameEvents` (BlockadeEstablished, BlockadeBroken)

**1d. Planetary Combat** (sequential execution, simultaneous priority)
- Collect all planetary combat intents (Bombard/Invade/Blitz commands)
- Resolve conflicts (determine attack priority command)
- Execute attacks sequentially in priority command
- Weaker attackers benefit from prior battles weakening defenders
- Generate `GameEvents` (SystemCaptured, ColonyCaptured, PlanetBombarded)

**1e. Colonization** (simultaneous resolution)
- ETAC fleets establish colonies
- Resolve conflicts (winner-takes-all)
- Fallback logic for losers (Fleet holds position)
- Generate `GameEvents` (ColonyEstablished)

**1f. Scout Intelligence Operations**

**1f.i. Fleet-Based Scout Missions** (mission start & first detection)

When scout fleet arrives at target (fleet.missionState == Executing):
- **State Transition**: Fleet.missionState: Executing → ScoutLocked
- **First Detection Check**: Run detection **before** mission registration
  - Detection check: 1d20 + ELI + starbaseBonus vs 15 + scoutCount
  - **If DETECTED**: All scouts destroyed immediately, mission fails, no intel gathered
  - **If UNDETECTED**: Continue to mission registration below

- **Mission Registration** (only if not detected):
  - Fleet.missionStartTurn = state.turn
  - Fleet.missionState = ScoutLocked
  - Mission data stored on fleet entity:
    - command.commandType = mission type (ScoutColony, ScoutSystem, HackStarbase)
    - missionTarget = target system
    - ships.len = scout count (scout-only fleets)
  - Generate Perfect quality intelligence (first turn)
  - Fleet locked (cannot accept new orders), scouts "consumed"
  - Generate `ScoutMissionStarted` event

**Game Events**: ScoutMissionStarted (if successful) or ScoutDetected (if failed)
**Critical**: First detection check gates mission registration

**1f.ii. Persistent Scout Mission Detection** (every turn for active missions)

**Every turn** while mission is active, detection check runs for missions registered in previous turns:

```nim
# Iterate fleets with active scout missions from previous turns
for fleet in state.allFleets():
  if fleet.missionState == ScoutLocked and fleet.missionStartTurn < state.turn:
    let scoutCount = fleet.ships.len  # Scout-only fleets
    let detectionResult = resolveScoutDetection(...)

    if detectionResult.detected:
      # DETECTED: Immediate destruction
      fleet.missionState = ScoutDetected
      fleet_ops.destroyFleet(state, fleetId)
      # Generate ScoutDetected event
      # Diplomatic escalation to Hostile
    else:
      # UNDETECTED: Generate Perfect intelligence
      generateScoutIntelligence(state, fleet)
      # Mission continues next turn
```

**Note**: Step CON1f.ii skips missions started this turn (missionStartTurn == state.turn) because they already passed their first detection check in CON1f.i above.
**Game Events**: IntelGathered (if undetected), ScoutDetected (if detected), DiplomaticStateChanged (on detection)

**1f.iii. Space Guild Espionage** (EBP-based covert ops)
- Tech Theft, Sabotage, Assassination, Cyber Attack
- Economic Manipulation, Psyops, Counter-Intel
- Intelligence Theft, Plant Disinformation, Recruit Agent
- Generate `GameEvents` (EspionageSuccess, EspionageDetected)

**1f.iv. Starbase Surveillance** (continuous monitoring)
- Automatic intelligence gathering from friendly starbases
- Monitors adjacent systems for fleet movements
- Updates intelligence tables with starbase sensor data
- No player action required (passive system)

**1g. Administrative Completion (Conflict Commands)**

**Purpose:** Mark Conflict Phase commands complete after their effects have been resolved.

**Processing:** Uses `performCommandMaintenance()` with `isConflictCommand()` filter to handle administrative completion (marking done, generating events, cleanup).

**Commands Completed:**
- **Combat commands**: Patrol, GuardStarbase, GuardColony, Blockade, Bombard, Invade, Blitz
  - Combat behavior already handled in CON1a-1d (combat resolution)
  - This step just marks them complete
- **Colonization**: Colonize (already established colony in CON1e, now mark complete)
- **Scout Intelligence**: ScoutColony, ScoutSystem, HackStarbase (already executed missions in CON1f, now mark complete)

**Key Distinction:** This is NOT command execution - it's administrative completion. Command effects already happened:
- Combat commands determined fleet behavior DURING combat resolution (CON1a-1d)
- Colonization commands triggered colony establishment IN CON1e
- Espionage commands triggered missions IN CON1f
- CON1g just marks these commands complete and cleans up their lifecycle

**Why Needed:** Ensures commands transition to completed state, events fire, and fleet command slots free up for new orders.

### 2. Immediate Combat Effects

**Purpose:** Process all immediate consequences of combat before turn boundary. Ensures game state is "clean" for Income Phase economic calculations.

**Timing:** After all combat resolution complete, before Income Phase

**What Gets Processed:**

**2a. Entity Destruction**
- Remove destroyed entities from game state:
  - Ships (CombatState.Destroyed)
  - Neorias (Spaceports, Shipyards, Drydocks)
  - Kastras (Starbases)
  - Ground units (marines, armies, ground batteries, planetary shields)
- Handled by: `cleanup.cleanupPostCombat(systemId)` per system

**2b. Destroyed Neoria Queue Clearing**
- Clear all construction queues (Spaceport/Shipyard)
- Clear all repair queues (Drydock)
- Ships/projects in destroyed docks = LOST
- Generate `ColonyProjectsLost` event (telemetry)

**2c. Crippled Facility Queue Clearing**
- **Crippled Neorias** (Spaceport/Shipyard/Drydock):
  - Facility.state = Crippled
  - Facility.effectiveDocks = 0 (non-functional until repaired)
  - Clear all construction queues (Spaceport/Shipyard)
  - Clear all repair queues (Drydock)
  - Ships/projects in crippled facility docks = LOST
  - Facility can be repaired (25% build cost via colony repair queue)
  - Generate `ColonyProjectsLost` event (telemetry)

- **Crippled Kastras** (Starbases):
  - Starbase.state = Crippled
  - AS/DS reduced to 50%
  - No queues to clear (Kastras don't have construction/repair queues)
  - Can be repaired via colony repair queue

**2d. Colony Conquest Effects**
- **Ownership Transfer:**
  - colony.owner = attackingHouse (immediate)
- **Queue Clearing:**
  - Clear colony.constructionQueue (all pending construction projects)
  - Clear colony.repairQueue (all pending repair projects)
  - Clear colony.underConstruction (active construction project)
  - Cancel colony.activeTerraforming (terraforming project)
- **Payment Implications:**
  - Construction: Paid upfront = sunk cost for previous owner
  - Repairs: Deferred payment = no refund (not yet paid)
  - Terraforming: Paid upfront = sunk cost
- **Facility Queues:** Also cleared by facility destruction during orbital combat
- Generate `ColonyCaptured` event (includes projectsLost counts for telemetry)

**2e. Severe Bombardment Effects (>50% Infrastructure Damage)**
- **Trigger:** infrastructureDamaged > (colony.infrastructure * 0.5)
- **Queue Clearing:**
  - Clear colony.constructionQueue
  - Clear colony.repairQueue
  - Clear colony.underConstruction
  - Cancel colony.activeTerraforming
- **Rationale:** Severe bombardment disrupts all colony operations
- Generate `InfrastructureDamaged` + `ColonyProjectsLost` events

**Strategic Impact:**
- Pending commissions vulnerable to combat (facilities/colonies can be destroyed/conquered)
- Ships in crippled/destroyed docks are LOST (not commissioned)
- Crippled facilities have 0 capacity (can be repaired, unlike destroyed)
- Colony conquest = all queues cleared (conqueror inherits empty colony)
- Stalled repairs especially vulnerable (may occupy docks for multiple turns)
- Proactive defense required (1-turn commissioning lag means defenses must be built ahead)

**Result:** Game state is now "clean" for Income Phase. All combat effects applied, all queues cleared, all ownership transferred.

### Key Properties
- All commands execute from previous turn's submission
- Simultaneous resolution prevents first-mover advantage
- Sequential execution after priority determination
- Intelligence gathering happens AFTER combat (collect after-action data)
- Combat effects applied immediately (queue clearing, ownership transfer)
- State is clean for economic calculations (no phantom queues, correct ownership)

---

## Phase 2: Income Phase

**Purpose:** Calculate economic output, apply modifiers, collect resources, enforce capacity constraints, evaluate victory.

**Income Phase Command Execution:**
- Execute commands that complete during Income Phase: Salvage
- Uses category filter: `isIncomeCommand()`
- Salvage commands execute when fleet arrives at mission objective
- Administrative completion marks commands done after salvage operations finish

### Execution Order

**1. Apply Ongoing Espionage Effects**
- Iterate `state.ongoingEffects`, decrement turn timers
- Apply active effects to affected houses:
  - **SRP Reduction:** Reduce research point generation (-10% to -50%)
  - **NCV Reduction:** Reduce colony net value (-10% to -30%)
  - **Tax Reduction:** Reduce tax income (-10% to -40%)
  - **Starbase Crippled:** Mark starbase as crippled (no combat/surveillance)
  - **Intel Blocked:** Counter-intelligence sweep blocks espionage this turn
  - **Intel Corrupted:** Disinformation adds ±20-40% variance to intelligence reports
- Remove expired effects (turnsRemaining = 0)
- Generate GameEvents for effect application

**2. Process EBP/CIP Investment**
- Purchase EBP (Espionage Budget Points) and CIP (Counter-Intelligence Points)
- Cost: 40 PP each (from `espionage.toml`)
- Add purchased points to `house.espionageBudget`
- Deduct PP cost from house treasury
- Check over-investment penalty:
  - Threshold: >5% of turn budget (configurable)
  - Penalty: -1 prestige per 1% over threshold
  - Apply prestige penalty if threshold exceeded
- Generate GameEvents (EspionageBudgetIncreased, PrestigePenalty)

**3. Calculate Base Production**
- For each colony: Base PP/RP from planet class and resource rating
- Apply improvements (Infrastructure, Manufactories, Labs)
- Apply espionage effects from INC1 (sabotage modifiers, NCV/tax reductions)

**4. Apply Blockades** (from Conflict Phase)
- Blockaded colonies: 60% production reduction (colony operates at 40% capacity)
- Update economic output

**5. Execute Salvage Commands** (Fleet Order 16)
- For each fleet with Salvage order that has arrived at mission objective:
  - Validate: Fleet survived Conflict Phase, at friendly colony with spaceport/shipyard
  - Disband fleet, recover 50% of ship build costs as PP
  - Add recovered PP to house treasury
  - Generate GameEvents (FleetSalvaged)

**6. Maintenance Processing** (03-economy.md Section 3.9)

**6a. Calculate Total Maintenance**
- Sum maintenance for all commissioned assets (ships, facilities, ground units)
- **Commissioned assets only:** Ships/facilities commissioned in previous turns
- **Pending commissions do NOT pay maintenance** (not yet in service)
- Uses clean post-combat state from CON2
- Rate modifiers:
  - Active fleets: 100% maintenance
  - Reserve fleets: 50% maintenance
  - Mothballed fleets: 10% maintenance
  - Crippled ships (combat): 50% maintenance
- **Note:** Assets commissioned this turn (CMD2) pay maintenance starting next turn

**6b. Payment Processing**
- **Full Payment** (treasury ≥ total maintenance):
  - Deduct full amount from treasury
  - Reset all maintenance-crippled ship shortfall counters to 0
  - Reset house consecutive shortfall counter to 0
  - Generate GameEvents (MaintenancePaid)

- **Partial Payment** (0 < treasury < total maintenance):
  - Deduct entire treasury (pay what you can)
  - Payment ratio = treasury / total maintenance
  - Reset shortfall counters proportionally (prioritize lower counters)
  - Increment house consecutive shortfall counter
  - Proceed to shortfall penalties (6c)

- **No Payment** (treasury = 0):
  - No ships restored
  - Increment house consecutive shortfall counter
  - Proceed to shortfall penalties (6c)

**6c. Shortfall Penalties** (only if partial/no payment)
- **Ship Crippling:**
  - Cripple oldest ships (lowest Ship IDs) until cumulative maintenance ≥ shortfall
  - Mark with CrippledReason: Maintenance
  - Set ship shortfallTurns = 1
  - Generate GameEvents (ShipCrippledMaintenance)

- **Infrastructure Degradation:**
  - Damage colony infrastructure proportional to shortfall amount
  - Reduces production capacity until repaired

- **Prestige Penalty** (config/prestige.kdl maintenanceShortfall):
  - Base: -5 prestige (turn 1 of shortfall)
  - Escalates: +2 per consecutive turn (-5, -7, -9, -11, ...)
  - Generate GameEvents (PrestigePenalty)

**6d. Auto-Salvage Check**
- For each ship with CrippledReason: Maintenance:
  - If shortfallTurns ≥ 2: Auto-salvage
    - Remove ship from game
    - Return 50% PP to treasury
    - Generate GameEvents (ShipAutoSalvaged)
  - Else: Increment shortfallTurns

**Note:** Combat-crippled ships (CrippledReason: Combat) are NEVER auto-salvaged.
They remain crippled until repaired at drydocks.

**7. Capacity Enforcement** (10-reference.md Section 10.5)

**Uses post-combat state:** Colony ownership and IU values updated in CON2.

**7a. C2 Pool Logistical Strain** (02-assets.md Section 2.3.3.2)
- Calculate C2 Pool: `Total_House_IU × 0.3`
- Calculate Total Fleet CC: Sum of CC for all active ships
- If Total Fleet CC > C2 Pool:
  - Calculate penalty: `(Total_Fleet_CC - C2_Pool) × 0.5` PP
  - Deduct penalty from treasury
  - Generate GameEvents (LogisticalStrainPenalty)
- **Note:** This is a SOFT cap with financial penalty only (no ship seizure)
- Reserve fleets: 50% CC cost
- Mothballed fleets: 0% CC cost
- Auxiliary ships (Scouts, ETACs, Transports): 0 CC

**7b. Fighter Capacity (2-Turn Grace Period)**
- Calculate per-colony capacity: `floor(Colony_IU ÷ 100) × FD_MULTIPLIER`
- If colony fighters > capacity (from over-building OR IU loss):
  - Initiate 2-turn grace period timer (if not already started)
  - If grace period expired: Auto-disband oldest fighters (no PP refund)
  - Generate GameEvents (FighterDisbanded)
- **Note:** Fighters are NOT blocked at submission (can intentionally over-build)

**7c. Planet-Breaker Enforcement (Immediate)**
- Maximum 1 Planet-Breaker per currently owned colony
- When colony lost (captured/destroyed) in Conflict Phase:
  - Instantly scrap associated Planet-Breaker (no salvage, no PP refund)
  - Generate GameEvents (PlanetBreakerScrapped)
- **Note:** PB build orders ARE blocked at submission (can't over-build intentionally)

**Capacity Enforcement Summary:**

| Limit | Blocked at CMD6? | Engine Enforces? | Grace? |
|-------|------------------|------------------|--------|
| FC (Ships/Fleet) | Yes | Yes (PRD1c) | No |
| SC (Fleet Count) | Yes | Yes (PRD1c) | No |
| Fighter Capacity | No | Yes (INC7b) | 2 turns |
| Planet-Breaker | Yes | Yes (INC7c) | No |
| Carrier Hangar | Yes | Yes (CMD4) | No |
| C2 Pool | No (soft cap) | Yes (INC7a) | N/A |

**Note:** FC/SC are tech-based limits that don't fluctuate, so no grace period needed.
Fighter capacity CAN drop unexpectedly (IU loss from blockade/conquest), hence the grace period.

**8. Collect Resources**
- Add PP/RP from production to house treasuries
- Add PP from salvage orders to house treasuries
- Generate GameEvents (ResourcesCollected)

**9. Calculate Prestige**
- Award prestige for events this turn (colonization, victories, tech advances)
- Update house prestige totals
- Generate GameEvents (PrestigeAwarded)

**10. House Elimination & Victory Checks**

**10a. House Elimination** (executed first)

Evaluate elimination conditions for each house in sequential order:

*Standard Elimination:*
- Condition: House has zero colonies AND no invasion capability
- Invasion capability check:
  - Scan all house fleets for Auxiliary Ships
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
- Defensive collapse evaluation requires prestige from INC9

**10b. Victory Conditions** (executed second)

Check victory conditions using non-eliminated houses:
- **Prestige Victory:** House prestige ≥ prestige threshold (from config)
- **Elimination Victory:** Only one non-eliminated house remains
- **Turn Limit Victory:** Maximum turns reached, highest prestige wins

On victory:
- Set game.phase = GamePhase.Completed
- Generate GameEvent(VictoryAchieved)
- Log victor and victory type

**11. Advance Timers**
- Espionage effect timers (sabotage recovery)
- Diplomatic effect timers (trade agreements)
- Total ship grace period timers (from INC7b)
- Fighter capacity grace period timers (from INC7c)

### Key Properties
- Salvage executes BEFORE maintenance (don't pay maintenance on salvaged fleet)
- Maintenance costs based on surviving forces after Conflict Phase
- Maintenance shortfall: ships crippled, infrastructure damaged, prestige penalties
- Salvage orders execute if fleet survived Conflict Phase and arrived at objective
- Capacity enforcement uses post-blockade IU values
- C2 Pool: Soft cap with Logistical Strain penalty (no ship seizure)
- Fighters: 2-turn grace period, then auto-disband
- Planet-Breakers: Instant scrap when colony lost
- Economic operations consolidated (production + salvage + maintenance)
- Prestige calculated from turn's events
- Victory conditions evaluated after prestige update
- Blockade effects applied immediately
- Sets treasury levels for Command Phase spending

---

## Phase 3: Command Phase

**Purpose:** Six-step phase - Order cleanup → Unified commissioning → Auto-repair → Colony automation → Player window → Order processing

**Critical Timing:** Server processing happens BEFORE player submission window. Players see clean, commissioned assets.

### 1. Order Cleanup

**Purpose:** Clean up completed/failed/aborted commands from previous turn.

- Process events from Conflict/Income phases
- Clear completed commands from `Fleet.command` field
- Remove failed commands (fleet destroyed, target lost)
- Remove aborted commands (conditions no longer valid)
- **Critical:** Runs FIRST to clean command slots for new orders
- Result: Clean slate for new turn's commands

### 2. Unified Commissioning

**Purpose:** Commission ALL pending assets that survived Conflict Phase. No validation needed - entity existence = survival.

**Timing:** After Income Phase (maintenance already calculated), before player window

**What Gets Commissioned:**

**2a. Ships from Neorias (Spaceports/Shipyards):**
- Iterate all Spaceports → commission pending ships from construction queues
- Iterate all Shipyards → commission pending ships from construction queues
- Ships enter service, free dock capacity
- **No validation needed:** If Neoria exists in game state, it survived Conflict Phase
- Destroyed/crippled Neorias had queues cleared in CON2

**2b. Repaired Ships from Drydocks:**
- Iterate all Drydocks → check repair queues for completed repairs
- For each pending repair:
  - Check house treasury (once per turn, here at commissioning)
  - If sufficient funds: Pay repair cost (25% of ship build cost), commission ship, free dock
  - If insufficient funds: Mark repair Stalled (ship stays in queue, occupies dock)
  - Generate `RepairCompleted` or `RepairStalled` event
- **No validation needed:** If Drydock exists, it survived Conflict Phase
- Stalled repairs checked again next turn at this same step

**2c. Assets from Colony Queues:**
- Iterate all colonies → commission pending assets:
  - Fighters (built via colony industrial capacity)
  - Ground units (marines, armies)
  - Defensive facilities (ground batteries, planetary shields)
  - Starbases (Kastras - orbital defense platforms)
  - Neorias (Spaceports, Shipyards, Drydocks - production facilities)
- **No validation needed:** If colony exists, it survived/remained owned
- Conquered colonies had queues cleared in CON2
- **Auto-load fighters:** After commissioning fighters, immediately load onto
  carriers with available hangar space (if `colony.autoLoadFighters = true`).
  This implements CMD4c at commissioning time for efficiency.

**Result:** All surviving pending assets commissioned, dock capacity freed, assets ready for automation

### 3. Auto-Repair Submission

**Purpose:** Convenience feature - auto-submit repair orders for crippled assets (before player window).

**Timing:** After commissioning, before colony automation

**Process:** For each colony where `colony.autoRepair = true`:
- Priority 1: Crippled ships → Find available Drydock, add to repair queue
- Priority 2: Crippled starbases → Add to colony repair queue
- Priority 2: Crippled ground units → Add to colony repair queue  
- Priority 3: Crippled Neorias → Add to colony repair queue (with prerequisites)

**Player Control:**
- Auto-repair is CONVENIENCE, not restriction
- Manual repairs ALWAYS available (CMD5)
- Players can cancel auto-repairs during submission window (CMD5)
- Both auto and manual repairs use same unified queue system

**Payment:** NO payment at submission (deferred until commissioning next turn)

### 4. Colony Automation

**Purpose:** Automatically organize newly commissioned assets before player sees them.

**Timing:** After auto-repair, before player window

**Operations:** For each colony (player-configurable flags):

**4a. Auto-Assign Ships to Fleets** (always enabled, implemented in CMD2)
- **NOTE:** This step is implemented during CMD2 Unified Commissioning, not CMD4.
- Ships are always auto-assigned to fleets during commissioning.
- Newly commissioned ships (from Spaceports/Shipyards)
- Repaired ships (from Drydocks)
- Logic: Join existing fleet at colony OR create new fleet
- Scouts join pure scout fleets (for mesh network bonuses)
- All other ships join combat fleets
- There is no toggle for this behavior.

**4b. Auto-Load Marines** (`colony.autoLoadMarines`, default: true)
- Newly commissioned marines → Load onto troop transports
- Only load to transports with available cargo capacity
- Transports at same colony

**4c. Auto-Load Fighters** (`colony.autoLoadFighters`, default: true)
- **NOTE:** This step is implemented during CMD2c commissioning, not CMD4.
- Fighters are auto-loaded immediately after commissioning, before CMD4 runs.
- This ensures fighters load onto carriers already present at the colony.
- Only load to Active stationary carriers (Hold/Guard orders or no orders)
- Skip moving carriers and Reserve/Mothballed fleets
- Respect carrier hangar capacity (ACO tech-based limits)

**Result:** Players see organized fleets and loaded cargo in submission window

### 5. Player Submission Window (24-hour window)

**Purpose:** Players submit orders seeing clean, organized game state.

Players see:
- Commissioned assets (newly available from CMD2)
- Auto-repair submissions (from CMD3, can cancel/modify)
- Automated fleet/cargo assignments (from CMD4)
- Freed dock capacity (from commissioning)

**5a. Zero-Turn Administrative Commands** (execute immediately):
- Fleet reorganization: DetachShips, TransferShips, MergeFleets
- Cargo operations: LoadCargo, UnloadCargo, LoadFighters, UnloadFighters, TransferFighters
- Immediate fleet management operations

**5b. Query Commands** (read-only):
- Intel reports, fleet status, economic reports

**5c. Command Submission** (execute later):
- Fleet commands (Move, Patrol, Bombard, Invade, etc.)
- Build orders (construction, repair, research)
- Diplomatic actions
- **Manual repair orders** (always allowed, overrides auto-repair)

### 6. Order Processing & Validation (AFTER Player Window)

**Universal Command Lifecycle:** Submit (CMD5) → Store (CMD6) → Execute (PRD/CON/INC)

**Command Processing:**

**6a. Zero-turn commands** (logistics only): Execute immediately in CMD5
- DetachShips, TransferShips, MergeFleets
- LoadCargo, UnloadCargo
- LoadFighters, UnloadFighters, TransferFighters
- **NOT included:** JoinFleet, Rendezvous, Reserve, Mothball, Reactivate (these are persistent)

**6b. Persistent fleet commands**: Validate and store in `Fleet.command` field (entity-manager pattern)
- ALL FleetCommandType entries follow lifecycle: Submit → Validate → Travel → Execute
- Categorized by PRIMARY EFFECT (not by whether they encounter combat):
  - **Production Phase commands**: Travel completion (Move, Hold, SeekHome, JoinFleet, Rendezvous) + Admin (Reserve, Mothball, Reactivate, View)
  - **Conflict Phase commands**: Combat ops (Patrol, Guard*, Blockade, Bombard, Invade, Blitz) + Colonization + Scout Intelligence (ScoutColony, ScoutSystem, HackStarbase)
  - **Income Phase commands**: Economic (Salvage)

**6b-i. Capacity Validation** (hard limits enforced at submission):
- **FC (Ships/Fleet)**: 
  - Zero-turn (MergeFleets, TransferShips): Reject if would exceed limit
  - JoinFleet/Rendezvous: Validated at PRD1c merge time (target may change during travel)
- **SC (Fleet Count)**: Reject fleet creation if at combat fleet limit
- **PB (Planet-Breaker)**: Reject build if colony already has one
- **Carrier Hangar**: Reject fighter loading beyond ACO-based capacity
- **Fighter Capacity**: NOT blocked (intentional over-build allowed, 2-turn grace)
- **C2 Pool**: NOT blocked (soft cap, financial penalty in INC7a)

**Key Insight:** Combat is separate from command execution. Combat triggers by fleet presence + diplomatic state, not by fleet mission type. A fleet with Rendezvous mission can still fight if enemies are present.

**Simultaneous Resolution:** Colonize, Blockade, Invade, and Blitz support multiple houses targeting the same colony/planet in the same turn. Conflict resolution logic (collect intents → resolve conflicts → execute) determines outcomes in CON1c-1e.

**6c. Build orders**: Add to construction queues

**6d. Repair orders** (manual repairs): Validate and add to repair queues
- Validation checks: Entity exists, is crippled, prerequisites met (drydock/spaceport/etc.)
- Ships assigned to specific drydock with available capacity
- Ground units, facilities, starbases added to colony repair queue
- Uses same unified repair queue system as auto-repairs

**6e. Tech research allocation** (detailed processing):
- Calculate total PP cost for research allocation (ERP + SRP + TRP)
- **Treasury scaling** (prevent negative treasury):
  - If treasury ≤ 0: Cancel all research (bankruptcy)
  - If cost > treasury: Scale allocations proportionally
  - Example: 80 PP treasury, 100 PP research → scale to 80% (80 PP total)
- Deduct research cost from treasury (competes with builds)
- Calculate GHO (Gross House Output) from colony production
- **Convert PP → RP** using GHO and Science Level (logarithmic scaling):
  - ERP (Economic Research Points): `PP * (1 + log₁₀(GHO)/3) * (1 + SL/10)`
  - SRP (Science Research Points): `PP * (1 + log₁₀(GHO)/4) * (1 + SL/5)`
  - TRP (Technology Research Points): `PP * (1 + log₁₀(GHO)/3.5) * (1 + SL/20)` per field
  - **Rationale**: Logarithmic GHO scaling provides diminishing returns, preventing runaway economic snowballing while still rewarding growth. TRP now scales with SL (modest 5% per level) to reflect advanced research infrastructure.
- **Accumulate RP** in `house.techTree.accumulated`:
  - `accumulated.economic += earnedRP.economic`
  - `accumulated.science += earnedRP.science`
  - `accumulated.technology[field] += earnedRP.technology[field]`
- Save earned RP to `house.lastTurnResearch*` for diagnostics
- **Note:** RP accumulation happens here in CMD6, advancement happens in PRD7

**Key Principles:**
- All non-admin commands follow same path: submit → store → execute
- No separate queues or special handling (DRY design)
- Production Phase moves fleets toward targets (all command types)
- Appropriate phase executes mission when fleet arrives

### Command Architecture: Persistence and Categorization

**Zero-Turn Commands (ZeroTurnCommandType):**
- Execute **immediately** during command submission (CMD5)
- Do **NOT** persist across turns
- Do **NOT** enter turn cycle (no travel, no arrival detection)
- **Logistics only:** DetachShips, TransferShips, MergeFleets, LoadCargo, UnloadCargo, LoadFighters, UnloadFighters, TransferFighters
- Require fleet at friendly colony
- Return immediate success/failure result

**Persistent Fleet Commands (FleetCommandType):**
- Persist across turns in `Fleet.command` field
- Follow multi-turn lifecycle: Submit (CMD6) → Travel (PRD1) → Execute (PRD/CON/INC)
- **ALL** FleetCommandType entries are persistent, including:
  - JoinFleet, Rendezvous (can require travel to target)
  - Reserve, Mothball, Reactivate (status changes, Reactivate default: 1 turn)
  - Move, Hold, SeekHome (travel completion)
  - Patrol, Bombard, Invade, Colonize, Scout missions, Salvage

**Command Categorization by Effect Type:**

Commands categorized by their PRIMARY EFFECT, not by whether they encounter combat:

- **Production Phase (PRD)**: Travel completion (Move, Hold, SeekHome, JoinFleet, Rendezvous) + Administrative (Reserve, Mothball, Reactivate, View)
- **Conflict Phase (CON)**: Combat operations (Patrol, Guard*, Blockade, Bombard, Invade, Blitz) + Colonization + Scout Intelligence (ScoutColony, ScoutSystem, HackStarbase)
- **Income Phase (INC)**: Economic operations (Salvage)

### Key Properties
- **Unified Commissioning:** All assets (ships, repairs, colony-built) commission in CMD2
- **No Validation Needed:** Entity existence = survival (queues cleared in CON2 if destroyed)
- **Maintenance Timing:** Assets commissioned Turn N pay maintenance starting Turn N+1 Income Phase
- **Proactive Defense Required:** 1-turn commissioning lag means defenses must be built ahead of threats
- **Repair System:**
  - Payment deferred until commissioning (CMD2 treasury check)
  - Stalled repairs occupy docks, vulnerable to next combat
  - Auto-repair before player window (CMD3, players can cancel)
  - Manual repairs always allowed (CMD6)
- **Automation Before Player:** CMD3-4 organize assets before player submission window
- **Clean State for Players:** Commissioned assets, freed capacity, organized fleets all visible
- Zero-turn commands execute immediately (CMD5)
- Persistent commands stored in `Fleet.command` field

---

## Phase 4: Production Phase

**Purpose:** Server batch processing (movement, construction, diplomatic actions).

**Timing:** Typically midnight server time (once per day).

### Execution Order

**1. Fleet Movement**

**1a. Fleet Travel** (fleets move toward targets)
- **ALL fleets with persistent commands** move autonomously toward target systems via pathfinding
- Includes ALL FleetCommandType: Move, Patrol, Colonize, Invade, ScoutColony, ScoutSystem, Salvage, etc.
- Validate paths (fog-of-war, jump lanes)
- Update fleet locations (1-2 jumps per turn based on lane control and class)
- Generate GameEvents (FleetMoved)
- **Key:** This step handles travel for ALL persistent commands
- **Note:** "Travel" is the general concept; "Move" is a specific fleet command

**1b. Fleet Arrival Detection** (detect commands ready for execution)
- Iterate all fleets with commands (Fleet.command.isSome)
- Check if fleet location matches command target system
- If arrived:
  - Generate `FleetArrived` event
  - Set `Fleet.missionState` to `Executing` (entity-manager pattern)
  - Mark command as ready for execution
- Result: Conflict/Income phases filter for `missionState == Executing` to determine which commands execute
- **Critical:** This is THE mechanism that determines when commands execute
- **Note for Scout Missions:** Scout mission fleets set to Executing state, then transition to ScoutLocked after first detection check

**1c. Administrative Completion (Production Commands)**
- Handle administrative completion for commands that finish during/after travel
- **Travel completion**: Move, Hold, SeekHome, Rendezvous (mark complete after arrival)
- **Fleet merging**: JoinFleet (merge fleets, mark complete)
- **Status changes**: Reserve, Mothball, Reactivate (apply status, mark complete)
- **Reconnaissance**: View (mark complete after edge-of-system scan)
- Uses category filter: `isProductionCommand()`
- Generate GameEvents (CommandCompleted, FleetMerged, StatusChanged, etc.)
- **Note:** This is administrative completion (marking done, merging fleets, status changes), not behavior execution. Fleet travel already happened in PRD1a

**Fleet Merge Capacity Enforcement:**
- JoinFleet/Rendezvous: If combined ships would exceed FC limit, reject merge
- Keep fleets separate, generate GameEvent (MergeRejectedCapacity)
- Fleet creation: If at SC limit, reject new fleet creation

**Fleet Status Rules** (02-assets.md Section 2.3.3.4):

| Status | CC Cost | Maintenance | Combat | Movement | Reactivation |
|--------|---------|-------------|--------|----------|--------------|
| Active | 100% | 100% | Full AS/DS | Yes | N/A |
| Reserve | 50% | 50% | 50% AS (GuardColony) | No | 1 turn (configurable) |
| Mothballed | 0% | 10% | None (screened) | No | 1 turn (configurable) |

**Reserve Status:**
- Auto-assigned GuardColony command (participates in orbital defense only)
- Fights at 50% AS (half attack strength) in orbital combat
- Immobile: Cannot move or accept movement orders until reactivated
- Requires friendly colony with starbase or shipyard

**Mothballed Status:**
- Cannot fight (screened during combat, not targetable)
- Immobile: Cannot move or accept orders until reactivated
- Requires friendly colony with spaceport

**Reactivation:**
- Default: 1 turn (configurable via gameConfig.ships.*.reactivationTurns)
- Fleet returns to Active status after reactivation period

**1d. Scout-on-Scout Detection** (reconnaissance encounters)
- Group all fleets by location (systemId)
- For each location with 2+ fleets:
  - Filter for scout-only fleets from different houses
  - For each pair of scout fleets from different houses:
    - Each side makes independent ELI-based detection roll
    - Detection formula: `1d20 vs (15 - observerScoutCount + targetELI)`
    - If detection succeeds:
      - Generate `ScoutDetected` event
      - Generate Visual quality `SystemIntelReport`
      - Add intel report to observer's intelligence database
- **Asymmetric detection:** Fleet A may detect Fleet B, but B may not detect A
- **No combat:** Scouts never fight each other (intelligence gathering only)
- **Intelligence Quality:** Visual (only observable data, not Perfect)
- Result: Houses gain intel on enemy scout presence at same location

**2. Construction and Repair Advancement** (parallel processing)

**2a. Construction Queue Advancement:**
- Advance build queues (ships, ground units, facilities)
- For each project: decrement `turnsRemaining`
- If `turnsRemaining = 0`: Mark `AwaitingCommission`
- Generate GameEvents (ConstructionProgress)
- **Note:** Commissioning happens in CMD2 (unified commissioning)

**2b. Repair Queue Advancement:**
- Advance all repairs: `turnsRemaining -= 1`
- If `turnsRemaining = 0`: Mark `AwaitingCommission`
- Ship stays in queue (occupies dock until commissioned in CMD2)
- **Note:** Treasury check and commissioning happen in CMD2

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

**7. Research Advancement** (process tech upgrades)

Process tech advancements using accumulated RP from Command Phase. Per economy.md:4.1, tech upgrades can be purchased EVERY TURN if RP is available.

**7a. Breakthrough Rolls** (every 5 turns):
- Calculate total RP invested in last 5 turns (ERP+SRP+TRP)
- Roll for breakthrough (1d100 vs threshold based on investment)
- Apply breakthrough effects:
  - Bonus RP (1-10% of investment)
  - Cost reduction (10-25% for next advancement)
  - Free level advancement (rare, <5% chance)
- Generate GameEvents for prestige awards

**7b. Economic Level (EL) Advancement:**
- Get current EL from `house.techTree.levels.economicLevel`
- Check if `accumulated.economic` ≥ cost for next level
- If sufficient: Deduct cost, increment EL, award prestige
- Generate `TechAdvance` event
- EL affects PP→ERP conversion rate

**7c. Science Level (SL) Advancement:**
- Get current SL from `house.techTree.levels.scienceLevel`
- Check if `accumulated.science` ≥ cost for next level
- If sufficient: Deduct cost, increment SL, award prestige
- Generate `TechAdvance` event
- SL affects PP→SRP conversion rate

**7d. Technology Field Advancement:**
- For each field (CST, WEP, TFM, ELI, CI):
  - Get current level from `house.techTree.levels.<field>`
  - Check if `accumulated.technology[field]` ≥ cost for next level
  - If sufficient: Deduct cost, increment level, award prestige
  - Generate `TechAdvance` event
- Multiple fields can advance in same turn
- CST affects ship build costs, WEP affects attack strength, etc.

**Result:** Houses advance tech levels using accumulated RP. Research accumulation happens in CMD6, advancement happens here in PRD7.

### Key Properties
- Server processing time (no player interaction)
- Fleet movement positions for next turn's combat
- Construction and repair queues advance in parallel
- Completed construction/repairs commission next turn in CMD2
- Turn boundary: After Production, increment turn counter -> Conflict Phase

---

## Fleet Order Execution Reference

### Active Fleet Commands (21 types)

| Order | Order Name       | Execution Phase | Notes                                   |
|-------|------------------|-----------------|------------------------------------------|
| 00    | Hold             | N/A             | Defensive posture, affects combat behavior |
| 01    | Move             | PRD1            | Fleet movement                           |
| 02    | Seek Home        | PRD1            | Return to nearest drydock colony         |
| 03    | Patrol System    | CON1            | Travels in PRD1, Defends in CON1         |
| 04    | Guard Starbase   | N/A             | Defensive posture, affects combat screening |
| 05    | Guard Colony     | N/A             | Defensive posture, orbital defense       |
| 06    | Blockade Colony  | CON1c           | Blockade resolution                      |
| 07    | Bombard Colony   | CON1d           | Planetary Combat                         |
| 08    | Invade Colony    | CON1d           | Planetary Combat                         |
| 09    | Blitz Colony     | CON1d           | Planetary Combat                         |
| 10    | Colonize Planet  | CON1e           | Colonization                             |
| 11    | Scout Colony     | CON1f           | Fleet-Based Scout Intel                  |
| 12    | Scout System     | CON1f           | Fleet-Based Scout Intel                  |
| 13    | Hack Starbase    | CON1f           | Fleet-Based Scout Intel                  |
| 14    | Join Fleet       | PRD1c           | Fleet merging after movement             |
| 15    | Rendezvous       | PRD1c           | Movement + auto-merge on arrival         |
| 16    | Salvage          | INC5            | Disband fleet for 50% PP                 |
| 17    | Place on Reserve | PRD1c           | Fleet status change                      |
| 18    | Mothball Fleet   | PRD1c           | Fleet status change                      |
| 19    | Reactivate Fleet | PRD1c           | Fleet status change                      |
| 20    | View Planet      | PRD1c           | Movement + reconnaissance                |

### Zero-Turn Administrative Commands (5 types)

Execute immediately during CMD5 player window:

| Command         | Execution Phase | Notes                                           |
| --------------- | --------------- | ----------------------------------------------- |
| DetachShips     | CMD5            | Execute immediately during command submission   |
| TransferShips   | CMD5            | Execute immediately during command submission   |
| MergeFleets     | CMD5            | Execute immediately during command submission   |
| LoadCargo       | CMD5            | Execute immediately during command submission   |
| UnloadCargo     | CMD5            | Execute immediately during command submission   |

**Key Property:** All zero-turn administrative commands execute BEFORE operational orders in same turn, allowing players to reorganize fleets and load cargo before issuing movement/combat orders.

---

## Critical Timing Properties

1. **Combat orders submitted Turn N execute Turn N+1 Conflict Phase**
   - Bombard, Invade, Blitz, ScoutColony, ScoutSystem, HackStarbase, Colonize, Blockade orders
   - One full turn delay between submission and execution

2. **Movement orders submitted Turn N execute Turn N Production Phase**
   - Move, SeekHome, Patrol, Join, Rendezvous orders
   - Execute same turn as submission (at midnight server processing)

3. **Fleets move in Production Phase, position for next Conflict Phase**
   - Fleet locations updated during PRD1
   - Combat uses these new positions in next Conflict Phase

4. **Combat always uses positions from previous turn's movement**
   - No instant movement + combat exploits
   - Fleet must be positioned one turn in advance

5. **Scout intelligence collects intel AFTER combat completes**
   - Fleet-based scouts: Reconnaissance after battles
   - Space Guild espionage: Covert ops exploit post-battle chaos

6. **Commissioning happens BEFORE player submission window**
   - Completed projects become operational before player orders (CMD2)
   - Dock space freed before player sees state
   - No perception delay

7. **Zero-turn commands execute DURING player submission window**
   - Immediate execution for administrative tasks (CMD5)
   - Players can reorganize before issuing operational orders

8. **Salvage Order Execution Check**
   - For a `Salvage` order to execute in INC5, the fleet must meet two conditions:
     1.  **Survival:** The fleet must have survived the preceding Conflict Phase
     2.  **Location:** The fleet must be at friendly colony with spaceport/shipyard
   - If a fleet is destroyed in the Conflict Phase, its pending orders fail implicitly
   - **Auxiliary Ships** (ETACs, TroopTransports) are screened during combat but destroyed if their fleet is eliminated

9. **Capacity enforcement uses post-blockade IU values**
   - Blockades applied in INC4
   - Capacity calculated with reduced IU in INC7

10. **Unified Commissioning System (2026-01-09)**
     - All assets (ships, repairs, colony-built) commission in CMD2
     - Treasury check for repairs happens at commissioning
     - Stalled repairs remain in queue until funded
     - **Strategic Timing:** 1-turn commissioning lag means defenses must be built ahead

11. **Repair System (2026-01-09)**
     - **Auto-Repair Submission:** CMD3 (before player window)
       - Controlled by `colony.autoRepair` flag per colony
       - Submits repairs for all crippled units in priority order
       - Players can cancel during submission window
     - **Manual Repair Submission:** CMD5 (player submission window)
       - Players submit specific repair orders with validation
     - **Repair Commissioning:** CMD2 (next turn)
       - Treasury check, pay cost, commission
       - Stalled repairs occupy docks until funded
     - **Unified Queue:** Auto and manual repairs use same queue system
     - **Architecture:**
       - Ships: Drydock pipeline (`neoria.repairQueue`)
       - Ground units, facilities, starbases: Colony pipeline (`colony.repairQueue`)

---

## Testing Scenarios

### Scenario 1: Fleet Movement -> Combat Sequence
1. Turn N Command: Submit Move order to enemy system
2. Turn N Production: Fleet moves to enemy system
3. Turn N+1 Conflict: Fleet participates in space combat at new location
4. **Validates:** Movement timing, combat positioning

### Scenario 2: Planetary Assault Sequence
1. Turn N Command: Submit Bombard order against enemy colony
2. Turn N Production: Fleet remains in position
3. Turn N+1 Conflict: Bombard executes after space/orbital combat
4. Turn N+1 Income: Production calculated with damaged infrastructure
5. **Validates:** Combat order timing, economic impact propagation

### Scenario 3: Salvage Sequence
1. Turn N Command: Submit Salvage order for fleet anywhere on map
2. Turn N Production: Fleet travels toward nearest friendly colony with spaceport/shipyard
3. Turn N+1: Fleet continues traveling if not arrived
4. Turn N+X Income INC5: Fleet arrives, disbands, 50% PP recovered
5. **Validates:** Salvage as persistent command, travel to objective, PP recovery

### Scenario 4: Capacity Enforcement Sequence
1. Turn N Conflict: Colony captured, IU drops
2. Turn N Income INC4: Blockade applied, IU drops further
3. Turn N Income INC7: Capacity calculated with reduced IU
4. Turn N Income INC7a: Ships seized immediately (no grace)
5. Turn N Income INC7b: Total ship grace period starts
6. Turn N+2 Income: Grace period expires, ships disbanded
7. **Validates:** Capacity enforcement timing, grace periods

### Scenario 5: Construction -> Commissioning Sequence
1. Turn N-1 Production PRD2: Construction completes, marked AwaitingCommission
2. Turn N Command CMD2: Completed project commissioned
3. Turn N Command CMD5: Player sees commissioned ship, can reorganize
4. Turn N Command CMD5: Player submits orders for new ship
5. Turn N Production PRD1: New ship movement orders execute
6. **Validates:** Commissioning timing, no perception delay

---

## Architecture Principles

### Separation of Concerns
- **Conflict Phase (CON):** Pure combat resolution (no economic calculations)
- **Income Phase (INC):** Pure economic state (no combat, no movement)
- **Command Phase (CMD):** Pure player interaction (no server processing in CMD5)
- **Production Phase (PRD):** Pure server processing (no player interaction)

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
Production Phase -> New positions, completed construction
-> Next Conflict Phase
```

### Timing Guarantees
- Combat orders: 1 turn delay (Turn N submission -> Turn N+1 execution)
- Movement orders: Same turn execution (Turn N submission -> Turn N PRD1)
- Zero-turn commands: Immediate execution (during CMD5)
- Commissioning: Before player sees state (CMD2, no perception delay)

### State Consistency
- Game state changes (commissioning) happen before player window
- Players always see accurate, up-to-date state
- No stale data from previous turn
- Destroyed entities immediately removed from data structures

---

## Phase Block Diagrams

### Phase 1: Conflict Phase (CON)

```
╔════════════════════════════════════════════════════════════╗
║                    CONFLICT PHASE (Turn N)                 ║
║                Commands from Turn N-1 Execute              ║
╠════════════════════════════════════════════════════════════╣
║                                                            ║
║  ╔═══════════════════════════════════════════════════════╗ ║
║  ║ 1. Combat Resolution                                  ║ ║
║  ║  1a. Space Combat (simultaneous)                      ║ ║
║  ║  1b. Orbital Combat (simultaneous)                    ║ ║
║  ║  1c. Blockade Resolution (simultaneous)               ║ ║
║  ║  1d. Planetary Combat (sequential priority)           ║ ║
║  ║  1e. Colonization (simultaneous)                      ║ ║
║  ║  1f. Scout Intelligence Operations                    ║ ║
║  ║  1g. Administrative Completion                        ║ ║
║  ╚═══════════════════════════════════════════════════════╝ ║
║                             |                              ║
║                             v                              ║
║  ╔═══════════════════════════════════════════════════════╗ ║
║  ║ 2. Immediate Combat Effects                           ║ ║
║  ║  2a. Remove destroyed entities                        ║ ║
║  ║  2b. Clear destroyed Neoria queues                    ║ ║
║  ║  2c. Clear crippled Neoria queues                     ║ ║
║  ║  2d. Process colony conquest                          ║ ║
║  ║  2e. Process severe bombardment                       ║ ║
║  ╚═══════════════════════════════════════════════════════╝ ║
║                                                            ║
╠════════════════════════════════════════════════════════════╣
║ OUTPUT: Combat results, destroyed entities, intel gathered ║
╚════════════════════════════════════════════════════════════╝
```

### Phase 2: Income Phase (INC)

```
╔═══════════════════════════════════════════════════════════════╗
║                      INCOME PHASE (Turn N)                    ║
║              Economic State & Capacity Enforcement            ║
╠═══════════════════════════════════════════════════════════════╣
║                                                               ║
║  ╔═══════════════════════════════════════════════════════╗    ║
║  ║ 1-4: Economic Calculations                            ║    ║
║  ║  1. Apply Ongoing Espionage Effects                   ║    ║
║  ║  2. Process EBP/CIP Investment                        ║    ║
║  ║  3. Calculate Base Production                         ║    ║
║  ║  4. Apply Blockades (from CON1c)                      ║    ║
║  ╚═══════════════════════════════════════════════════════╝    ║
║                             |                                 ║
║                             v                                 ║
║  ╔═══════════════════════════════════════════════════════╗    ║
║  ║ 5. Execute Salvage Commands                           ║    ║
║  ║  • Fleet arrived at friendly colony w/ spaceport      ║    ║
║  ║  • Disband fleet, recover 50% PP                      ║    ║
║  ╚═══════════════════════════════════════════════════════╝    ║
║                             |                                 ║
║                             v                                 ║
║  ╔═══════════════════════════════════════════════════════╗    ║
║  ║ 6. Calculate Maintenance Costs                        ║    ║
║  ║  • Maintenance for commissioned ships/facilities      ║    ║
║  ║  • Deduct from house treasuries                       ║    ║
║  ╚═══════════════════════════════════════════════════════╝    ║
║                             |                                 ║
║                             v                                 ║
║  ╔═════════════════════════════════════════════════════════╗  ║
║  ║ 7. Capacity Enforcement                                 ║  ║
║  ║  7a. C2 Pool -> Soft cap, Logistical Strain penalty     ║  ║
║  ║  7b. Fighter Capacity -> 2-turn grace, then disband     ║  ║
║  ║  7c. Planet-Breakers -> Instant scrap when colony lost  ║  ║
║  ╚═════════════════════════════════════════════════════════╝  ║
║                             |                                 ║
║                             v                                 ║
║  ╔═══════════════════════════════════════════════════════╗    ║
║  ║ 8-11: Finalization                                    ║    ║
║  ║  8. Collect resources                                 ║    ║
║  ║  9. Calculate prestige                                ║    ║
║  ║  10. House Elimination & Victory Checks               ║    ║
║  ║  11. Advance timers                                   ║    ║
║  ╚═══════════════════════════════════════════════════════╝    ║
║                                                               ║
╠═══════════════════════════════════════════════════════════════╣
║ OUTPUT: Updated treasuries, prestige, victory status          ║
╚═══════════════════════════════════════════════════════════════╝
```

### Phase 3: Command Phase (CMD)

```
╔════════════════════════════════════════════════════════════╗
║                    COMMAND PHASE (Turn N)                  ║
║          Server Processing -> Player Window -> Validation  ║
╠════════════════════════════════════════════════════════════╣
║                                                            ║
║  ╔═══════════════════════════════════════════════════════╗ ║
║  ║ 1-4: Server Processing (BEFORE Player Window)         ║ ║
║  ║                                                       ║ ║
║  ║  1. Order Cleanup                                     ║ ║
║  ║   • Clear completed/failed commands from prev turn    ║ ║
║  ║                                                       ║ ║
║  ║  2. Unified Commissioning                             ║ ║
║  ║   • Commission ships from Neorias (2a)                ║ ║
║  ║   • Commission repaired ships from Drydocks (2b)      ║ ║
║  ║   • Commission assets from colony queues (2c)         ║ ║
║  ║   • Free dock space                                   ║ ║
║  ║                                                       ║ ║
║  ║  3. Auto-Repair Submission                            ║ ║
║  ║   • Submit repairs for crippled units (if enabled)    ║ ║
║  ║                                                       ║ ║
║  ║  4. Colony Automation                                 ║ ║
║  ║   • Auto-assign ships to fleets (4a)                  ║ ║
║  ║   • Auto-load marines (4b)                            ║ ║
║  ║   • Auto-load fighters (4c)                           ║ ║
║  ║   • Auto-balance fleets (4d)                          ║ ║
║  ╚═══════════════════════════════════════════════════════╝ ║
║                             |                              ║
║                             v                              ║
║  ╔═══════════════════════════════════════════════════════╗ ║
║  ║ 5. Player Submission Window (24 hours)                ║ ║
║  ║                                                       ║ ║
║  ║  5a. Zero-Turn Commands (Execute Immediately)         ║ ║
║  ║   • DetachShips, TransferShips, MergeFleets           ║ ║
║  ║   • LoadCargo, UnloadCargo                            ║ ║
║  ║                                                       ║ ║
║  ║  5b. Query Commands (read-only)                       ║ ║
║  ║                                                       ║ ║
║  ║  5c. Command Submission (Execute Later)               ║ ║
║  ║   • Fleet orders -> CON/PRD/INC Phase                 ║ ║
║  ║   • Build orders -> Construction queues               ║ ║
║  ║   • Repair orders -> Repair queues                    ║ ║
║  ╚═══════════════════════════════════════════════════════╝ ║
║                             |                              ║
║                             v                              ║
║  ╔═══════════════════════════════════════════════════════╗ ║
║  ║ 6. Order Processing & Validation (AFTER Window)       ║ ║
║  ║   6a. Zero-turn commands (already executed)           ║ ║
║  ║   6b. Persistent fleet commands (validate & store)    ║ ║
║  ║   6c. Build orders (add to queues)                    ║ ║
║  ║   6d. Repair orders (add to queues)                   ║ ║
║  ║   6e. Tech research allocation                        ║ ║
║  ╚═══════════════════════════════════════════════════════╝ ║
║                                                            ║
╠════════════════════════════════════════════════════════════╣
║ OUTPUT: Validated orders queued, no execution              ║
╚════════════════════════════════════════════════════════════╝
```

### Phase 4: Production Phase (PRD)

```
╔════════════════════════════════════════════════════════════╗
║                  PRODUCTION PHASE (Turn N)                 ║
║              Server Batch Processing (Midnight)            ║
╠════════════════════════════════════════════════════════════╣
║                                                            ║
║  ╔═══════════════════════════════════════════════════════╗ ║
║  ║ 1. Fleet Movement                                     ║ ║
║  ║                                                       ║ ║
║  ║  1a. Fleet Travel (fleets move to targets)            ║ ║
║  ║   • ALL persistent commands move toward targets       ║ ║
║  ║   • Update fleet locations (1-2 jumps/turn)           ║ ║
║  ║                                                       ║ ║
║  ║  1b. Fleet Arrival Detection                          ║ ║
║  ║   • Set missionState = Executing for arrived fleets   ║ ║
║  ║                                                       ║ ║
║  ║  1c. Administrative Completion (Production commands)  ║ ║
║  ║   • Move, JoinFleet, Reserve, Mothball, etc.          ║ ║
║  ║                                                       ║ ║
║  ║  1d. Scout-on-Scout Detection                         ║ ║
║  ║   • Visual quality intel, asymmetric detection        ║ ║
║  ╚═══════════════════════════════════════════════════════╝ ║
║                             |                              ║
║                             v                              ║
║  ╔═══════════════════════════════════════════════════════╗ ║
║  ║ 2. Construction & Repair Advancement                  ║ ║
║  ║                                                       ║ ║
║  ║  2a. Construction Queue Advancement                   ║ ║
║  ║   • Advance build queues (ships, units, facilities)   ║ ║
║  ║   • Mark completed -> AwaitingCommission              ║ ║
║  ║   • Commission happens next turn in CMD2              ║ ║
║  ║                                                       ║ ║
║  ║  2b. Repair Queue Advancement                         ║ ║
║  ║   • Advance all repairs                               ║ ║
║  ║   • Mark completed -> AwaitingCommission              ║ ║
║  ║   • Commission happens next turn in CMD2              ║ ║
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
║  ║  4. Population transfers (Space Lift)                 ║ ║
║  ║  5. Terraforming advancement                          ║ ║
║  ║  6. Cleanup and preparation                           ║ ║
║  ║   • Cleanup destroyed entities                        ║ ║
║  ║   • Update fog-of-war visibility                      ║ ║
║  ║   • Prepare for next turn                             ║ ║
║  ╚═══════════════════════════════════════════════════════╝ ║
║                             |                              ║
║                             v                              ║
║  ╔═══════════════════════════════════════════════════════╗ ║
║  ║ 7. Research Advancement                               ║ ║
║  ║  7a. Breakthrough Rolls (every 5 turns)               ║ ║
║  ║  7b. Economic Level (EL) Advancement                  ║ ║
║  ║  7c. Science Level (SL) Advancement                   ║ ║
║  ║  7d. Technology Field Advancement                     ║ ║
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
     ║            (Commands  Submitted Here)            ║
     ╚══════════════════╦═══════════════════════════════╝
                        ║
                        ↓
     ╔══════════════════════════════════════════════════╗
     ║         PHASE 1: CONFLICT (Turn N)               ║
     ║    Execute commands from Turn N-1                ║
     ║    • Space -> Orbital -> Blockade -> Planetary   ║
     ║    • Colonization -> Scout Intelligence          ║
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
     ║ CMD1-4: Server processing (before player window) ║
     ║ CMD5: Player submission (24-hour window)         ║
     ║ CMD6: Order processing (after player window)     ║
     ╚══════════════════╦═══════════════════════════════╝
                        ║ Validated Commands 
                        ↓
     ╔══════════════════════════════════════════════════╗
     ║        PHASE 4: Production (Turn N)              ║
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

**AS (Attack Strength):** Combat effectiveness rating for ships  
**CR (Combat Rating):** Ship size class (≥7 for capital ships)  
**EBP (Espionage Budget Points):** Currency for Space Guild covert operations  
**ETAC (Explorer/Transport/Armed Colonizer):** Colony ship  
**FD_MULTIPLIER:** Fighter defense capacity multiplier per colony  
**IU (Industrial Units):** Colony economic output measure  
**NCV (Net Colony Value):** Total economic value of colony infrastructure  
**PP (Production Points):** Industrial manufacturing currency  
**PTU (Population Transport Units):** Population cargo units  
**RP (Research Points):** Scientific research currency  
**SRP (Science Research Points):** Alternative term for RP  

**Simultaneous Resolution:** All players' commands collected, conflicts resolved, then executed in priority order  
**Sequential Execution:** Commands execute one at a time in strict order  
**Grace Period:** Time buffer before capacity enforcement triggers  
**Commissioning:** Process of making completed construction operational  
**Zero-Turn Command:** Administrative command that executes immediately
