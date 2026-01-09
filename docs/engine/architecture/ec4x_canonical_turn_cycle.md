# EC4X Canonical Turn Sequence Specification

**Purpose:** Complete and definitive turn order specification for EC4X  
**Last Updated:** 2026-01-08
**Status:** Implementation Complete (Split Commissioning + Repair System)

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
TURN N - CONFLICT PHASE
├─ 1. Combat Resolution
│  ├─ Space combat (mobile fleets)
│  ├─ Orbital combat (guard fleets, starbases, reserves)
│  ├─ Planetary combat (bombardment, invasion, blitz)
│  └─ Generate combat events
│
└─ 2. Immediate Combat Effects
   ├─ Remove destroyed entities:
   │  ├─ Ships (CombatState.Destroyed)
   │  ├─ Neorias (Spaceport/Shipyard/Drydock)
   │  ├─ Kastras (Starbases)
   │  └─ Ground units (marines, armies, batteries, shields)
   │
   ├─ Clear destroyed Neoria queues:
   │  ├─ Spaceport constructionQueue
   │  ├─ Shipyard constructionQueue
   │  ├─ Drydock repairQueue
   │  └─ Ships/projects in destroyed docks = LOST
   │
   ├─ Clear crippled Neoria queues:
   │  ├─ Neoria.state = Crippled
   │  ├─ Neoria.effectiveDocks = 0
   │  ├─ Clear all queues (constructionQueue, repairQueue)
   │  ├─ Ships/projects in crippled docks = LOST
   │  └─ Facility can be repaired (25% build cost via colony queue)
   │
   ├─ Process colony conquest:
   │  ├─ Transfer ownership: colony.owner = attacker
   │  ├─ Clear colony.constructionQueue
   │  ├─ Clear colony.repairQueue
   │  ├─ Clear colony.underConstruction
   │  ├─ Cancel colony.activeTerraforming
   │  └─ Generate ColonyCaptured event (with projectsLost counts)
   │
   └─ Process severe bombardment (>50% infrastructure):
      ├─ If infrastructureDamaged > (colony.infrastructure * 0.5):
      ├─ Clear colony.constructionQueue
      ├─ Clear colony.repairQueue
      ├─ Clear colony.underConstruction
      ├─ Cancel colony.activeTerraforming
      └─ Generate ColonyProjectsLost event

State is now clean for Income Phase

TURN N - INCOME PHASE
├─ 0. Apply Ongoing Espionage Effects
├─ 1. Calculate Base Production (uses post-combat colony ownership)
├─ 2. Apply Blockades
├─ 3. Execute Salvage Commands
├─ 4. Calculate Maintenance Costs
│  └─ Only assets commissioned in previous turns pay
│  └─ Pending commissions do NOT pay maintenance
├─ 5. Capacity Enforcement (uses post-combat ownership/IU)
├─ 6. Collect Resources
├─ 7. Calculate Prestige (from Conflict Phase events)
├─ 8. House Elimination & Victory Checks
└─ 9. Advance Timers

TURN N - COMMAND PHASE
├─ A. Unified Commissioning
│  │
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
├─ B. Auto-Repair Submission (Before Player Window)
│  └─ For each colony where colony.autoRepair = true:
│     ├─ Priority 1: Damaged ships → Available Drydock queues
│     ├─ Priority 2: Damaged starbases → Colony repair queue
│     ├─ Priority 2: Damaged ground units → Colony repair queue
│     ├─ Priority 3: Damaged Neorias → Colony repair queue
│     └─ NOTE: Player can cancel/modify these in submission window
│
├─ C. Colony Automation
│  └─ For each colony:
│     ├─ If colony.autoJoinFleets = true:
│     │  └─ Auto-assign newly commissioned ships to fleets
│     │     └─ Includes: New ships + repaired ships
│     ├─ If colony.autoLoadMarines = true:
│     │  └─ Auto-load marines onto troop transports
│     ├─ If colony.autoLoadFighters = true:
│     └─ Auto-load fighters onto carriers (Active stationary only)
│
├─ D. Player Submission Window (24-hour window)
│  └─ Players see:
│     ├─ Commissioned assets (newly available)
│     ├─ Auto-repair submissions (can cancel/modify)
│     └─ Automated fleet/cargo assignments (result of Step C)
│
└─ E. Order Processing
   ├─ Manual repair orders (always allowed, overrides auto-repair)
   ├─ Build orders (pay PP upfront)
   │  ├─ Ships → Neoria construction queues
   │  ├─ Fighters/Ground units/Facilities → Colony queues
   │  └─ Validate budget, capacity before queuing
   └─ Fleet commands (validate, store in Fleet.command)

TURN N - PRODUCTION PHASE
├─ 1. Fleet Movement
│
├─ 2. Construction & Repair Advancement
│  │
│  ├─ 2a. Advance Spaceport/Shipyard construction queues:
│  │  └─ For each project: decrement turnsRemaining
│  │     └─ If turnsRemaining = 0: Mark AwaitingCommission
│  │
│  ├─ 2b. Advance Drydock repair queues:
│  │  ├─ For each repair: decrement turnsRemaining
│  │  ├─ If turnsRemaining = 0:
│  │  │  └─ Mark AwaitingCommission (treasury check deferred to Command A)
│  │  └─ Ship stays in queue (occupies dock until commissioned)
│  │
│  └─ 2c. Advance colony construction/repair queues:
│     └─ For each project: decrement turnsRemaining
│        └─ If turnsRemaining = 0: Mark AwaitingCommission
│
├─ 3. Research (tech advancement)
├─ 4. Diplomacy (treaty processing)
└─ 5. Terraforming (advance terraform projects)
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

### Submit (Command Phase Part B)
- Player submits commands via `CommandPacket`
- Commands queued for validation
- Phase: Command Phase Part B

### Store (Command Phase Part C)
- Engine validates commands (syntax, resources, permissions)
- Valid commands stored in `Fleet.command` field (entity-manager pattern)
- Fleet `missionState` set to `Traveling`
- Invalid commands rejected with error events
- Phase: Command Phase Part C

### Execute (Production/Conflict/Income Phase)
- **Production Phase**: Fleet travel (Step 1a), arrival detection (Step 1b), administrative completion (Step 1c)
- **Conflict Phase**: Combat, colonization, scout intelligence (filter: `missionState == Executing`)
- **Income Phase**: Economic operations (Salvage)
- Results generate events (`CommandCompleted`, `CommandFailed`, etc.)
- Phase: Depends on command type

**Key Insight:** All commands follow the SAME lifecycle:
- Submit (Command B) → Store (Command C) → Execute (Production/Conflict/Income)

---

## Phase 1: Conflict Phase

**Purpose:** Resolve all combat, colonization, and scout intelligence operations submitted previous turn.

**Timing:** Commands submitted Turn N-1 execute Turn N.

### Execution Order

**Note:** Commands are executed directly from `Fleet.command` field (entity-manager pattern).
No merge step needed - fleets with `missionState == Executing` have arrived at targets and execute their commands.

**Universal command lifecycle:**
- Command Phase Part C: Commands validated and stored in `Fleet.command`, `missionState` set to `Traveling`
- Production Phase Step 1a: Fleets move toward targets
- Production Phase Step 1b: Arrivals detected, `Fleet.missionState` set to `Executing`
- Conflict Phase Steps 1-6: Commands execute (filter: missionState == Executing)

**1. Space Combat** (simultaneous resolution)
- **1a. Raider Detection**: Perform detection checks for all engaging fleets containing Raiders to determine ambush advantage.
- **1b. Combat Resolution**: Collect all space combat intents, resolve conflicts, and execute the combat engine, applying any first-strike bonuses.
- Generate `GameEvents` (ShipDestroyed, FleetEliminated)

**2. Orbital Combat** (simultaneous resolution)
- **2a. Raider Detection**: Perform a new round of detection checks for fleets engaging in orbital combat.
- **2b. Combat Resolution**: Collect all orbital combat intents, resolve conflicts, and execute strikes sequentially, applying any first-strike bonuses.
- Generate `GameEvents` (StarbaseDestroyed, DefensesWeakened)

**3. Blockade Resolution** (simultaneous resolution)
- Collect all blockade intents
- Resolve conflicts (determine blockade controller)
- Establish blockade status (affects Income Phase)
- Generate `GameEvents` (BlockadeEstablished, BlockadeBroken)

**4. Planetary Combat** (sequential execution, simultaneous priority)
- Collect all planetary combat intents (Bombard/Invade/Blitz commands)
- Resolve conflicts (determine attack priority command)
- Execute attacks sequentially in priority command
- Weaker attackers benefit from prior battles weakening defenders
- Generate `GameEvents` (SystemCaptured, ColonyCaptured, PlanetBombarded)

**5. Colonization** (simultaneous resolution)
- ETAC fleets establish colonies
- Resolve conflicts (winner-takes-all)
- Fallback logic for losers (Fleet holds position)
- Generate `GameEvents` (ColonyEstablished)

**6. Scout Intelligence Operations**

**6a. Fleet-Based Scout Missions** (mission start & first detection)

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

**6a.5. Persistent Scout Mission Detection** (every turn for active missions)

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

**Note**: Newly-started missions (missionStartTurn == state.turn) already had their first detection check in Step 6a.
**Game Events**: IntelGathered (if undetected), ScoutDetected (if detected), DiplomaticStateChanged (on detection)

**6b. Space Guild Espionage** (EBP-based covert ops)
- Tech Theft, Sabotage, Assassination, Cyber Attack
- Economic Manipulation, Psyops, Counter-Intel
- Intelligence Theft, Plant Disinformation, Recruit Agent
- Generate `GameEvents` (EspionageSuccess, EspionageDetected)

**6c. Starbase Surveillance** (continuous monitoring)
- Automatic intelligence gathering from friendly starbases
- Monitors adjacent systems for fleet movements
- Updates intelligence tables with starbase sensor data
- No player action required (passive system)

**STEP 7: ADMINISTRATIVE COMPLETION (Conflict Commands)**

**Purpose:** Mark Conflict Phase commands complete after their effects have been resolved.

**Processing:** Uses `performCommandMaintenance()` with `isConflictCommand()` filter to handle administrative completion (marking done, generating events, cleanup).

**Commands Completed:**
- **Combat commands**: Patrol, GuardStarbase, GuardColony, Blockade, Bombard, Invade, Blitz
  - Combat behavior already handled in Steps 1-4 (combat resolution)
  - This step just marks them complete
- **Colonization**: Colonize (already established colony in Step 5, now mark complete)
- **Scout Intelligence**: ScoutColony, ScoutSystem, HackStarbase (already executed missions in Steps 6a/6b, now mark complete)

**Key Distinction:** This is NOT command execution - it's administrative completion. Command effects already happened:
- Combat commands determined fleet behavior DURING combat resolution (Steps 1-4)
- Colonization commands triggered colony establishment IN Step 5
- Espionage commands triggered missions IN Steps 6a/6b
- Step 7 just marks these commands complete and cleans up their lifecycle

**Why Needed:** Ensures commands transition to completed state, events fire, and fleet command slots free up for new orders.

**STEP 8: IMMEDIATE COMBAT EFFECTS**

**Purpose:** Process all immediate consequences of combat before turn boundary. Ensures game state is "clean" for Income Phase economic calculations.

**Timing:** After all combat resolution complete, before Income Phase

**What Gets Processed:**

**1. Entity Destruction (Already Implemented)**
- Remove destroyed entities from game state:
  - Ships (CombatState.Destroyed)
  - Neorias (Spaceports, Shipyards, Drydocks)
  - Kastras (Starbases)
  - Ground units (marines, armies, ground batteries, planetary shields)
- Handled by: `cleanup.cleanupPostCombat(systemId)` per system

**2. Crippled Facility Queue Clearing**
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

**3. Colony Conquest Effects**
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

**4. Severe Bombardment Effects (>50% Infrastructure Damage)**
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
- Salvage commands collect debris field resources when fleet arrives
- Administrative completion marks commands done after salvage operations finish

### Execution Order

**0. Apply Ongoing Espionage Effects**
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

**0b. Process EBP/CIP Investment**
- Purchase EBP (Espionage Budget Points) and CIP (Counter-Intelligence Points)
- Cost: 40 PP each (from `espionage.toml`)
- Add purchased points to `house.espionageBudget`
- Deduct PP cost from house treasury
- Check over-investment penalty:
  - Threshold: >5% of turn budget (configurable)
  - Penalty: -1 prestige per 1% over threshold
  - Apply prestige penalty if threshold exceeded
- Generate GameEvents (EspionageBudgetIncreased, PrestigePenalty)

**1. Calculate Base Production**
- For each colony: Base PP/RP from planet class and resource rating
- Apply improvements (Infrastructure, Manufactories, Labs)
- Apply espionage effects from Step 0 (sabotage modifiers, NCV/tax reductions)

**2. Apply Blockades** (from Conflict Phase)
- Blockaded colonies: 50% production penalty
- Update economic output

**3. Execute Salvage Commands** (Fleet Order 15, submitted previous turn)
- For each fleet with Salvage order:
  - Validate: Fleet survived Conflict Phase, at friendly colony, debris present
  - Execute salvage recovery (PP from destroyed ships)
  - Add recovered PP to house treasury
  - Generate GameEvents (ResourcesSalvaged)

**4. Calculate Maintenance Costs**
- Calculate maintenance for all commissioned assets (active in service)
- **Commissioned assets only:** Ships/facilities commissioned in previous turns
- **Pending commissions do NOT pay maintenance** (not yet in service)
- Uses clean post-combat state from Conflict Phase Step 8
- Damaged/crippled ships may have reduced maintenance (50% for crippled)
- Deduct total maintenance from house treasuries
- Generate GameEvents (MaintenancePaid)
- **Note:** Assets commissioned this turn (Command Phase A) will pay maintenance starting next turn

**5. Capacity Enforcement After IU Loss** (reference.md Table 10.5)

When IU drops (blockades, lost colonies), capacity limits may fall below current forces. Enforcement with grace periods or immediate seizure.

**Uses post-combat state:** Colony ownership and IU values updated in Conflict Phase Step 8 (conquest effects applied).

**5a. Capital Squadron Capacity (No Grace Period)**
- Calculate capacity: `max(8, floor(Total_House_IU ÷ 100) × 2 × mapMultiplier)`
- Total_House_IU includes blockade effects from Step 2 AND conquest effects from Conflict Phase
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
- Salvage executes BEFORE maintenance (don't pay maintenance on salvaged debris)
- Maintenance costs based on surviving forces after Conflict Phase
- Salvage orders execute if fleet survived Conflict Phase
- Capacity enforcement uses post-blockade IU values
- Capital squadrons: Immediate seizure (no grace period)
- Total squadrons/fighters: 2-turn grace period, then auto-disband
- Planet-Breakers: Instant scrap when colony lost
- Economic operations consolidated (production + salvage + maintenance + seizures)
- Prestige calculated from turn's events
- Victory conditions evaluated after prestige update
- Blockade effects applied immediately
- Sets treasury levels for Command Phase spending

---

## Phase 3: Command Phase

**Purpose:** Five-part phase - Order cleanup → Unified commissioning → Auto-repair → Colony automation → Player window → Order processing

**Critical Timing:** Server processing happens BEFORE player submission window. Players see clean, commissioned assets.

### Step 0: Order Cleanup

**Purpose:** Clean up completed/failed/aborted commands from previous turn.

- Process events from Conflict/Income phases
- Clear completed commands from `Fleet.command` field
- Remove failed commands (fleet destroyed, target lost)
- Remove aborted commands (conditions no longer valid)
- **Critical:** Runs FIRST to clean command slots for new orders
- Result: Clean slate for new turn's commands

### Part A: Unified Commissioning

**Purpose:** Commission ALL pending assets that survived Conflict Phase. No validation needed - entity existence = survival.

**Timing:** After Income Phase (maintenance already calculated), before player window

**What Gets Commissioned:**

**1. Ships from Neorias (Spaceports/Shipyards):**
- Iterate all Spaceports → commission pending ships from construction queues
- Iterate all Shipyards → commission pending ships from construction queues
- Ships enter service, free dock capacity
- **No validation needed:** If Neoria exists in game state, it survived Conflict Phase
- Destroyed/crippled Neorias had queues cleared in Conflict Phase Step 8

**2. Repaired Ships from Drydocks:**
- Iterate all Drydocks → check repair queues for completed repairs
- For each pending repair:
  - Check house treasury (once per turn, here at commissioning)
  - If sufficient funds: Pay repair cost (25% of ship build cost), commission ship, free dock
  - If insufficient funds: Mark repair Stalled (ship stays in queue, occupies dock)
  - Generate `RepairCompleted` or `RepairStalled` event
- **No validation needed:** If Drydock exists, it survived Conflict Phase
- Stalled repairs checked again next turn at this same step

**3. Assets from Colony Queues:**
- Iterate all colonies → commission pending assets:
  - Fighters (built via colony industrial capacity)
  - Ground units (marines, armies)
  - Defensive facilities (ground batteries, planetary shields)
  - Starbases (Kastras - orbital defense platforms)
  - Neorias (Spaceports, Shipyards, Drydocks - production facilities)
- **No validation needed:** If colony exists, it survived/remained owned
- Conquered colonies had queues cleared in Conflict Phase Step 8

**Result:** All surviving pending assets commissioned, dock capacity freed, assets ready for automation

### Part B: Auto-Repair Submission

**Purpose:** Convenience feature - auto-submit repair orders for crippled assets (before player window).

**Timing:** After commissioning, before colony automation

**Process:** For each colony where `colony.autoRepair = true`:
- Priority 1: Crippled ships → Find available Drydock, add to repair queue
- Priority 2: Crippled starbases → Add to colony repair queue
- Priority 2: Crippled ground units → Add to colony repair queue  
- Priority 3: Crippled Neorias → Add to colony repair queue (with prerequisites)

**Player Control:**
- Auto-repair is CONVENIENCE, not restriction
- Manual repairs ALWAYS available (Part D)
- Players can cancel auto-repairs during submission window (Part D)
- Both auto and manual repairs use same unified queue system

**Payment:** NO payment at submission (deferred until commissioning next turn)

### Part C: Colony Automation

**Purpose:** Automatically organize newly commissioned assets before player sees them.

**Timing:** After auto-repair, before player window

**Operations:** For each colony (player-configurable flags):

**1. Auto-Assign Ships to Fleets** (`colony.autoJoinFleets`, default: true)
- Newly commissioned ships (from Spaceports/Shipyards)
- Repaired ships (from Drydocks)
- Logic: Join existing fleet at colony OR create new fleet
- Applies to all ship types (combat ships, scouts, auxiliary vessels)

**2. Auto-Load Marines** (`colony.autoLoadMarines`, default: true)
- Newly commissioned marines → Load onto troop transports
- Only load to transports with available cargo capacity
- Transports at same colony

**3. Auto-Load Fighters** (`colony.autoLoadFighters`, default: true)
- Newly commissioned fighters → Load onto carriers
- Only load to Active stationary carriers (Hold/Guard orders or no orders)
- Skip moving carriers and Reserve/Mothballed fleets
- Respect carrier hangar capacity (ACO tech-based limits)

**4. Auto-Balance Fleets** (always enabled, not toggleable)
- Balance fleet compositions automatically
- Ensures optimal fleet organization

**Result:** Players see organized fleets and loaded cargo in submission window

### Part D: Player Submission Window (24-hour window)

**Purpose:** Players submit orders seeing clean, organized game state.

Players see:
- Commissioned assets (newly available from Part A)
- Auto-repair submissions (from Part B, can cancel/modify)
- Automated fleet/cargo assignments (from Part C)
- Freed dock capacity (from commissioning)

**Zero-Turn Administrative Commands** (execute immediately):
- Fleet reorganization: DetachShips, TransferShips, MergeFleets
- Cargo operations: LoadCargo, UnloadCargo, LoadFighters, UnloadFighters, TransferFighters
- Immediate fleet management operations

**Query Commands** (read-only):
- Intel reports, fleet status, economic reports

**Command Submission** (execute later):
- Fleet commands (Move, Patrol, Bombard, Invade, etc.)
- Build orders (construction, repair, research)
- Diplomatic actions
- **Manual repair orders** (always allowed, overrides auto-repair)

### Part E: Command Validation & Storage (AFTER Player Window)

**Universal Command Lifecycle:** Submit (Part B) → Store (Part C) → Execute (Production/Conflict/Income Phase)

**Command Processing:**
1. **Zero-turn commands** (logistics only): Execute immediately in Part B
   - DetachShips, TransferShips, MergeFleets
   - LoadCargo, UnloadCargo
   - LoadFighters, UnloadFighters, TransferFighters
   - **NOT included:** JoinFleet, Rendezvous, Reserve, Mothball, Reactivate (these are persistent)
2. **Persistent fleet commands**: Validate and store in `Fleet.command` field (entity-manager pattern)
   - ALL FleetCommandType entries follow lifecycle: Submit → Validate → Travel → Execute
   - Categorized by PRIMARY EFFECT (not by whether they encounter combat):
     - **Production Phase commands**: Travel completion (Move, Hold, SeekHome, JoinFleet, Rendezvous) + Admin (Reserve, Mothball, Reactivate, View)
     - **Conflict Phase commands**: Combat ops (Patrol, Guard*, Blockade, Bombard, Invade, Blitz) + Colonization + Scout Intelligence (ScoutColony, ScoutSystem, HackStarbase)
     - **Income Phase commands**: Economic (Salvage)

**Key Insight:** Combat is separate from command execution. Combat triggers by fleet presence + diplomatic state, not by fleet mission type. A fleet with Rendezvous mission can still fight if enemies are present.

**Simultaneous Resolution:** Colonize, Blockade, Invade, and Blitz support multiple houses targeting the same colony/planet in the same turn. Conflict resolution logic (collect intents → resolve conflicts → execute) determines outcomes in Conflict Phase Steps 3-5.
3.  **Build orders**: Add to construction queues
4.  **Repair orders** (manual repairs): Validate and add to repair queues
   - Validation checks: Entity exists, is crippled, prerequisites met (drydock/spaceport/etc.)
   - Ships assigned to specific drydock with available capacity
   - Ground units, facilities, starbases added to colony repair queue
   - Uses same unified repair queue system as auto-repairs
5.  **Tech research allocation** (detailed processing):
   - Calculate total PP cost for research allocation (ERP + SRP + TRP)
   - **Treasury scaling** (prevent negative treasury):
     - If treasury ≤ 0: Cancel all research (bankruptcy)
     - If cost > treasury: Scale allocations proportionally
     - Example: 80 PP treasury, 100 PP research → scale to 80% (80 PP total)
   - Deduct research cost from treasury (competes with builds)
   - Calculate GHO (Gross House Output) from colony production
   - **Convert PP → RP** using GHO and Science Level:
     - ERP (Economic Research Points): `PP * (1 + GHO/1000) * (1 + SL/10)`
     - SRP (Science Research Points): `PP * (1 + GHO/2000) * (1 + SL/5)`
     - TRP (Technology Research Points): `PP * (1 + GHO/1500)` per field
   - **Accumulate RP** in `house.techTree.accumulated`:
     - `accumulated.economic += earnedRP.economic`
     - `accumulated.science += earnedRP.science`
     - `accumulated.technology[field] += earnedRP.technology[field]`
   - Save earned RP to `house.lastTurnResearch*` for diagnostics
   - **Note:** RP accumulation happens here in Command Phase, advancement happens in Production Phase Step 7

**Key Principles:**
- All non-admin commands follow same path: submit → store → execute
- No separate queues or special handling (DRY design)
- Production Phase moves fleets toward targets (all command types)
- Appropriate phase executes mission when fleet arrives

### Command Architecture: Persistence and Categorization

**Zero-Turn Commands (ZeroTurnCommandType):**
- Execute **immediately** during command submission (Command Phase Part D)
- Do **NOT** persist across turns
- Do **NOT** enter turn cycle (no travel, no arrival detection)
- **Logistics only:** DetachShips, TransferShips, MergeFleets, LoadCargo, UnloadCargo, LoadFighters, UnloadFighters, TransferFighters
- Require fleet at friendly colony
- Return immediate success/failure result

**Persistent Fleet Commands (FleetCommandType):**
- Persist across turns in `Fleet.command` field
- Follow multi-turn lifecycle: Submit (Command Phase E) → Travel (Production Phase) → Execute (Production/Conflict/Income Phase)
- **ALL** FleetCommandType entries are persistent, including:
  - JoinFleet, Rendezvous (can require travel to target)
  - Reserve, Mothball, Reactivate (status changes, Reactivate takes 1 full turn)
  - Move, Hold, SeekHome (travel completion)
  - Patrol, Bombard, Invade, Colonize, Scout missions, Salvage

**Command Categorization by Effect Type:**

Commands categorized by their PRIMARY EFFECT, not by whether they encounter combat:

- **Production Phase**: Travel completion (Move, Hold, SeekHome, JoinFleet, Rendezvous) + Administrative (Reserve, Mothball, Reactivate, View)
- **Conflict Phase**: Combat operations (Patrol, Guard*, Blockade, Bombard, Invade, Blitz) + Colonization + Scout Intelligence (ScoutColony, ScoutSystem, HackStarbase)
- **Income Phase**: Economic operations (Salvage)

### Key Properties
- **Unified Commissioning:** All assets (ships, repairs, colony-built) commission in Part A
- **No Validation Needed:** Entity existence = survival (queues cleared in Conflict Phase if destroyed)
- **Maintenance Timing:** Assets commissioned Turn N pay maintenance starting Turn N+1 Income Phase
- **Proactive Defense Required:** 1-turn commissioning lag means defenses must be built ahead of threats
- **Repair System:**
  - Payment deferred until commissioning (Part A treasury check)
  - Stalled repairs occupy docks, vulnerable to next combat
  - Auto-repair before player window (Part B, players can cancel)
  - Manual repairs always allowed (Part E)
- **Automation Before Player:** Parts B-C organize assets before player submission window
- **Clean State for Players:** Commissioned assets, freed capacity, organized fleets all visible
- Zero-turn commands execute immediately (Part D)
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
- **Note:** This is administrative completion (marking done, merging fleets, status changes), not behavior execution. Fleet travel already happened in Step 1c

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
- **Timing:** Commission immediately in Production Phase Step 2b
- **Result:** Available for defense in NEXT turn's Conflict Phase ✓

*Military Units (Commission Next Turn):*
- **Ships:** All ship classes (Corvette → PlanetBreaker) and Auxiliary Ships (ETAC, TroopTransport)
- **Strategic Rationale:** Ships may be destroyed in docks during Conflict Phase
- **Timing:** Stored in pendingMilitaryCommissions, commission next turn's Command Phase Part A
- **Result:** Verified docks survived combat before commissioning

**2c. Repair Queue Advancement & Commissioning**

**Process:**
- Advance all repairs: `turnsRemaining -= 1`
- For completed repairs (turnsRemaining = 0):
  - Check treasury ≥ repair cost
  - If YES: Deduct PP, commission immediately, remove from queue, free dock
  - If NO: Mark Stalled, ship stays in queue, dock occupied
- Re-check stalled repairs every turn
- FIFO processing: First queued, first funded

**Payment:** Deferred to completion (NOT at submission). Enables "queue optimistically, cancel if unaffordable."

**Vulnerability:** Stalled repairs remain in docks → vulnerable to facility destruction next Conflict Phase

**Result:** Funded repairs commission immediately. Stalled repairs remain in queue.

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

**Result:** Houses advance tech levels using accumulated RP. Research accumulation happens in Command Phase Part C, advancement happens here in Production Phase.

### Key Properties
- Server processing time (no player interaction)
- Fleet movement positions for next turn's combat
- Construction and repair advance in parallel
- Completed construction commissioned next turn in Command Phase Part A
- Completed repairs immediately operational (no commissioning)
- Turn boundary: After Production, increment turn counter -> Conflict Phase

---

## Fleet Order Execution Reference

### Active Fleet Commands (20 types)

| Order | Order Name            | Execution Phase  | Notes                                        |
|-------|-----------------------|------------------|----------------------------------------------|
| 00    | Hold                  | N/A              | Defensive posture, affects combat behavior   |
| 01    | Move                  | Production Phase | Fleet movement (Step 1)                      |
| 02    | Seek Home             | Production Phase | Variant of Move (return to home colony)      |
| 03    | Patrol System         | Conflict Phase   | Travels in Production, Defends in Conflict   |
| 04    | Guard Starbase        | N/A              | Defensive posture, affects combat screening  |
| 05    | Guard/Blockade Planet | Conflict Phase   | Blockade: Step 3, Guard: defensive posture   |
| 06    | Bombard Planet        | Conflict Phase   | Planetary Combat (Step 4)                    |
| 07    | Invade Planet         | Conflict Phase   | Planetary Combat (Step 4)                    |
| 08    | Blitz Planet          | Conflict Phase   | Planetary Combat (Step 4)                    |
| 09    | Scout Colony          | Conflict Phase   | Fleet-Based Scout Intel (Step 6a)            |
| 10    | Hack Starbase         | Conflict Phase   | Fleet-Based Scout Intel (Step 6a)            |
| 11    | Scout System          | Conflict Phase   | Fleet-Based Scout Intel (Step 6a)            |
| 12    | Colonize Planet       | Conflict Phase   | Colonization (Step 5)                        |
| 13    | Join Another Fleet    | Production Phase | Fleet merging after movement                 |
| 14    | Rendezvous at System  | Production Phase | Movement + auto-merge on arrival             |
| 15    | Salvage               | Income Phase     | Resource recovery (Step 3)                   |
| 16    | Place on Reserve      | Production Phase | Fleet status change                          |
| 17    | Mothball Fleet        | Production Phase | Fleet status change                          |
| 18    | Reactivate Fleet      | Production Phase | Fleet status change                          |
| 19    | View a Planet         | Production Phase | Movement + reconnaissance                    |

### Zero-Turn Administrative Commands (7 types)

Execute immediately during Command Phase Part B player window:

| Command         | Execution Phase | Notes                                           |
| --------------- | --------------- | ----------------------------------------------- |
| DetachShips     | Command Phase B | Execute immediately during command submission   |
| TransferShips   | Command Phase B | Execute immediately during command submission   |
| MergeFleets     | Command Phase B | Execute immediately during command submission   |
| LoadCargo       | Command Phase B | Execute immediately during command submission   |
| UnloadCargo     | Command Phase B | Execute immediately during command submission   |
| PlaceOnReserve  | Command Phase B | Instant status change (reduces C2/Maint cost)   |
| MothballFleet   | Command Phase B | Instant status change (zero C2, minimal Maint)  |

**Key Property:** All zero-turn administrative commands execute BEFORE operational orders in same turn, allowing players to reorganize fleets, load cargo, and manage status before issuing movement/combat orders.

---

## Critical Timing Properties

1. **Combat orders submitted Turn N execute Turn N+1 Conflict Phase**
   - Bombard, Invade, Blitz, ScoutColony, ScoutSystem, HackStarbase, Colonize, Blockade orders
   - One full turn delay between submission and execution

2. **Movement orders submitted Turn N execute Turn N Production Phase**
   - Move, SeekHome, Patrol, Join, Rendezvous orders
   - Execute same turn as submission (at midnight server processing)

3. **Fleets move in Production Phase, position for next Conflict Phase**
   - Fleet locations updated during Maintenance
   - Combat uses these new positions in next Conflict Phase

4. **Combat always uses positions from previous turn's movement**
   - No instant movement + combat exploits
   - Fleet must be positioned one turn in advance

5. **Scout intelligence collects intel AFTER combat completes**
   - Fleet-based scouts: Reconnaissance after battles
   - Space Guild espionage: Covert ops exploit post-battle chaos

6. **Commissioning happens BEFORE player submission window**
   - Completed projects become operational before player orders
   - Dock space freed before player sees state
   - No perception delay

7. **Zero-turn commands execute DURING player submission window**
   - Immediate execution for administrative tasks
   - Players can reorganize before issuing operational orders

8. **Salvage Order Execution Check**
   - For a `Salvage` order to execute in the Income Phase, the fleet must meet two conditions:
     1.  **Survival:** The fleet must have survived the preceding Conflict Phase (i.e., not destroyed and removed from the game state).
     2.  **Location:** The fleet must be at the designated salvage mission objective location.
   - If a fleet is destroyed in the Conflict Phase, its pending orders (including `Salvage`) fail implicitly because the fleet entity no longer exists in the game state.
   - **Auxiliary Ships** (ETACs, TroopTransports) are screened during combat (do not participate directly), but are destroyed if their protecting combat fleets are eliminated or retreat.

9. **Capacity enforcement uses post-blockade IU values**
   - Blockades applied in Income Phase Step 2
   - Capacity calculated with reduced IU in Step 5

10. **Split Commissioning System (2025-12-09)**
     - **Planetary Defense:** Commission same turn in Production Phase Step 2b
       - Facilities, ground units, fighters available for next turn's defense
     - **Military Units:** Commission next turn in Command Phase Part A
       - Ships verified docks survived combat before commissioning
     - **Strategic Timing:** Defenders get immediate protection, ships wait for safety check

11. **Repair System (2026-01-08)**
     - **Auto-Repair Submission:** Command Phase Part A Step 2 (before player window)
       - Controlled by `colony.autoRepair` flag per colony
       - Submits repairs for all crippled units in priority order
       - Players can cancel during submission window
     - **Manual Repair Submission:** Command Phase Part B (player submission window)
       - Available when `colony.autoRepair = false`
       - Players submit specific repair orders with validation
     - **Repair Execution:** Production Phase Step 2c
       - Both auto and manual repairs execute together
       - Ships commission immediately after repair (same phase)
       - All other units restored to operational state
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

### Scenario 3: Salvage Recovery Sequence
1. Turn N Conflict: Fleet survives battle, debris present
2. Turn N Command: Submit Salvage order
3. Turn N+1 Conflict: Fleet survives again (or not)
4. Turn N+1 Income Step 3: Salvage executes if fleet survived
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
1. Turn N-1 Production: Construction completes, marked complete
2. Turn N Command Part A: Completed project commissioned
3. Turn N Command Part B: Player sees commissioned ship, can reorganize
4. Turn N Command Part B: Player submits orders for new ship
5. Turn N Production: New ship movement orders execute
6. **Validates:** Commissioning timing, no perception delay

---

## Architecture Principles

### Separation of Concerns
- **Conflict Phase:** Pure combat resolution (no economic calculations)
- **Income Phase:** Pure economic state (no combat, no movement)
- **Command Phase:** Pure player interaction (no server processing in Part B)
- **Production Phase:** Pure server processing (no player interaction)

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
║                Commands  from Turn N-1 Execute             ║
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
║  ║ Step 6: Scout Intelligence Operations                 ║ ║
║  ║  6a. Fleet-Based Mission Start (on arrival)           ║ ║
║  ║    • Scout fleet → ScoutLocked state                  ║ ║
║  ║    • Mission data stored on fleet entity              ║ ║
║  ║  6a.5. Persistent Scout Detection (each turn)         ║ ║
║  ║    • Check all fleets with missionState=ScoutLocked   ║ ║
║  ║    • Detected → destroy scouts, fail mission          ║ ║
║  ║    • Undetected → generate Perfect intel, continue    ║ ║
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
║  ║ Step 3: Execute Salvage Commands                      ║    ║
║  ║  • Validate fleet survived Conflict Phase             ║    ║
║  ║  • Recover PP from debris                             ║    ║
║  ║  • GameEvents: ResourcesSalvaged                      ║    ║
║  ╚═══════════════════════════════════════════════════════╝    ║
║                             |                                 ║
║                             v                                 ║
║  ╔═══════════════════════════════════════════════════════╗    ║
║  ║ Step 4: Calculate Maintenance Costs                   ║    ║
║  ║  • Maintenance for surviving ships/facilities         ║    ║
║  ║  • Deduct from house treasuries                       ║    ║
║  ║  • GameEvents: MaintenancePaid                        ║    ║
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
║  ║  Step 0: Clear Damaged Facility Queues                ║ ║
║  ║   • Clear queues from crippled/destroyed facilities   ║ ║
║  ║   • Generate ColonyProjectsLost events                ║ ║
║  ║                                                       ║ ║
║  ║  Step 1: Ship Commissioning                           ║ ║
║  ║   • Validate facility survived combat (neoriaId)      ║ ║
║  ║   • Commission ships from operational facilities      ║ ║
║  ║   • Free dock space                                   ║ ║
║  ║   • Auto-create squadrons, assign to fleets           ║ ║
║  ║   • Auto-load 1 PTU onto ETAC ships                   ║ ║
║  ║                                                       ║ ║
║  ║  Step 2: Colony Automation & Auto-Repair Submission   ║ ║
║  ║   • Auto-load fighters to carriers                    ║ ║
║  ║   • Auto-submit repair orders (if enabled):           ║ ║
║  ║     - Ships → Drydock queue (Priority 1)              ║ ║
║  ║     - Ground units → Colony queue (Priority 2)        ║ ║
║  ║     - Facilities → Colony queue (Priority 3)          ║ ║
║  ║     - Starbases → Colony queue (Priority 2)           ║ ║
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
║  ║   • Fleet orders -> Conflict/Production Phase         ║ ║
║  ║   • Build orders -> Construction queues               ║ ║
║  ║   • Repair orders -> Repair queues (manual mode)      ║ ║
║  ║   • Diplomatic actions -> Production Phase            ║ ║
║  ║                                                       ║ ║
║  ║  Players can cancel auto-repairs and submit manual    ║ ║
║  ╚═══════════════════════════════════════════════════════╝ ║
║                             |                              ║
║                             v                              ║
║  ╔═══════════════════════════════════════════════════════╗ ║
║  ║ PART C: Order Validation & Queueing (AFTER Window)    ║ ║
║  ║   • Validate all submitted orders                     ║ ║
║  ║   • Process build orders (add to queues)              ║ ║
║  ║   • Start tech research (allocate RP)                 ║ ║
║  ║   • Queue combat orders for Turn N+1 Conflict         ║ ║
║  ║   • Store movement orders for Production activation   ║ ║
║  ╚═══════════════════════════════════════════════════════╝ ║
║                                                            ║
╠════════════════════════════════════════════════════════════╣
║ OUTPUT: Validated orders queued, no execution              ║
╚════════════════════════════════════════════════════════════╝
```

### Phase 4: Production Phase

```
╔════════════════════════════════════════════════════════════╗
║                  Production PHASE (Turn N)                 ║
║              Server Batch Processing (Midnight)            ║
╠════════════════════════════════════════════════════════════╣
║                                                            ║
║  ╔═══════════════════════════════════════════════════════╗ ║
║  ║ Step 1: Fleet Movement                                ║ ║
║  ║                                                       ║ ║
║  ║  1a. Fleet Travel (fleets move to targets)            ║ ║
║  ║   • ALL persistent commands move toward targets       ║ ║
║  ║   • Validate paths (fog-of-war, jump lanes)           ║ ║
║  ║   • Update fleet locations (1-2 jumps/turn)           ║ ║
║  ║   • GameEvents: FleetMoved                            ║ ║
║  ║                                                       ║ ║
║  ║  1b. Fleet Arrival Detection                          ║ ║
║  ║   • Set missionState = Executing for arrived fleets   ║ ║
║  ║   • GameEvents: FleetArrived                          ║ ║
║  ║                                                       ║ ║
║  ║  1c. Administrative Completion (Production commands)  ║ ║
║  ║   • Move, JoinFleet, Reserve, Mothball, etc.          ║ ║
║  ║   • GameEvents: CommandCompleted, FleetMerged         ║ ║
║  ║                                                       ║ ║
║  ║  1d. Scout-on-Scout Detection                         ║ ║
║  ║   • Visual quality intel, asymmetric detection        ║ ║
║  ║   • GameEvents: ScoutDetected                         ║ ║
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
║  ║   • Advance all repairs (auto + manual, 1 turn, 25%)  ║ ║
║  ║   • Ships: Drydock queue (assigned to specific dock)  ║ ║
║  ║   • Ground/Facilities/Starbases: Colony queue         ║ ║
║  ║   • Commission repaired ships immediately to fleets   ║ ║
║  ║   • Other units -> Immediately operational            ║ ║
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
     ║ Part A: Commissioning (before player window)     ║
     ║ Part B: Player submission (24-hour window)       ║
     ║ Part C: Command validation (after player window) ║
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

**AS (Attack Strength):** Combat effectiveness rating for squadrons  
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
