# GameEvents Guide for EC4X

## Core Principle

**GameEvents represent things that happened.** They capture temporal occurrences during turn resolution - actions taken, outcomes determined, state changes completed. They are *not* queries of current state.

## Three Distinct Uses

### 1. AI Observation & Reaction (Events Only)

**Purpose**: Let AI players observe the game world and react to events they can detect.

**How it works**:
- Events fire during turn resolution as orders execute
- Filter events to each AI based on fog of war / sensor capabilities
- AI receives only events for things it can observe
- AI uses events to update threat assessments, revise strategy, plan reactions

**Examples**:
- `FleetMovementBeganEvent` - AI sees enemy fleet leaving port (if in sensor range)
- `ColonyBombardedEvent` - AI learns its colony took damage
- `FleetOrderAbortedEvent` - AI notices enemy retreat, can exploit opening
- `ShipDestroyedEvent` - AI updates fleet strength estimates
- `EspionageOperationDetectedEvent` - AI knows it's being spied on

**Key points**:
- Events are *reactive input* for AI decision-making
- Filter aggressively - AI only gets what its intelligence capabilities allow
- Events drive immediate reassessment, not primary planning
- AI doesn't reconstruct world state from events - it queries state when planning

### 2. Developer Metadata & Balance Analysis

**Purpose**: Collect detailed data about game mechanics performance for balance tuning and debugging.

**How it works**:
- Log events to structured format (JSON, database, or parseable text)
- Events capture granular details that don't persist in state
- Analyze event logs across many games to find patterns
- Use for balance adjustments, performance profiling, regression testing

**Battle event examples**:
```nim
type
  WeaponFiredEvent = object
    turn: int
    battle_id: string
    phase: CombatPhase  # Space, Orbital, Planetary
    attacker_ship: ShipID
    weapon_type: WeaponType
    target_ship: ShipID
    damage_dealt: int
    hit: bool
    
  ShipDestroyedInCombatEvent = object
    turn: int
    battle_id: string
    phase: CombatPhase
    ship: ShipID
    ship_class: ShipClass
    destroyed_by: ShipID
    overkill_damage: int
    
  CombatPhaseCompletedEvent = object
    turn: int
    battle_id: string
    phase: CombatPhase
    rounds_elapsed: int
    attacker_ships_remaining: int
    defender_ships_remaining: int
    victor: Option[PlayerID]
```

**Analysis queries you can run**:
- "What's the average time-to-kill for cruisers vs destroyers?"
- "Do missile weapons overperform against shields?"
- "How often does space superiority lead to orbital victory?"
- "Which ship classes have highest survival rates?"
- "Are planetary invasions balanced or too attacker-favored?"

**Performance event examples**:
```nim
type
  TurnResolutionStartedEvent = object
    turn: int
    timestamp: Time
    total_orders: int
    
  TurnResolutionCompletedEvent = object
    turn: int
    timestamp: Time
    duration_ms: int
    orders_processed: int
    
  AIThinkingCompletedEvent = object
    turn: int
    player: PlayerID
    duration_ms: int
    orders_generated: int
```

**What to track**:
- Turn resolution time (identify bottlenecks)
- AI thinking time (catch performance regressions)
- Event volume per turn (memory/performance implications)
- Order execution patterns (which orders dominate gameplay?)

### 3. Player Reports & Turn History (Hybrid: Events + State)

**Purpose**: Give players detailed narrative of what happened, not just current aftermath.

**The problem with state-only reports**:
- State after battle: "Fleet damaged, 2 ships destroyed, won battle"
- Missing: *How* did you win? What weapons were effective? When did losses occur?
- Players want the story, not just the outcome

**The hybrid solution**:
Combine GameState (current situation) with recent GameEvents (what happened) for player-facing reports.

**How it works**:
- Preserve recent events (last 1-2 turns) for report generation
- When player requests combat report, pull both state and events
- State provides context (current fleet status, casualties)
- Events provide narrative (weapon hits, kill sequence, tactical flow)

**Examples**:

*After-Action Report (hybrid)*:
```
Battle of Rigel IV - Turn 47
Outcome: Victory (from state)
Your Fleet Status: 8 ships, 3 damaged (from state)
Enemy Fleet Status: Destroyed (from state)

Combat Log (from events):
Space Phase:
- Round 1: Your Cruiser 'Defiant' hit enemy Destroyer with railguns (42 dmg)
- Round 2: Enemy Frigate destroyed by missile barrage from 'Retribution'
- Round 3: Your Destroyer 'Vigilant' destroyed by enemy Cruiser railgun fire
- Round 4: Enemy Cruiser 'Predator' destroyed by combined fire

Orbital Phase:
- Round 1: Bombardment platforms neutralized
- Round 2: Orbital superiority achieved
```

*Turn Summary (hybrid)*:
```
Turn 47 Summary
Colonies (from state): 
- Alpha IV: Factory construction 75% complete
- Beta Station: Population 4.2M

Fleet Movements (from events):
- Battle Fleet Sigma: Engaged and defeated enemy at Rigel IV
- Scout Fleet Delta: Began movement toward Tau Ceti (4 turns)

Espionage (from events):
- Operation "Nightfall" in Centauri system: Detected by enemy
```

**Report Types**:

*Combat Reports*: Always hybrid
- State: casualties, current status, victor
- Events: round-by-round action, weapon effectiveness, kill attribution

*Intelligence Reports*: State only (covered in next section)
- Current enemy positions, fleet compositions, visible threats
- No historical detail needed

*Turn Summaries*: Hybrid
- State: current colony status, tech progress, resource levels  
- Events: what orders executed, battles fought, diplomacy actions

*Replay/Debug*: Events only
- Step through turn resolution chronologically
- See exact event sequence for debugging

**Retention strategy**:
- Keep last 2-3 turns of events in memory for quick report access
- Archive older events to disk for post-game analysis
- Discard ancient events unless needed for saves/replay

## What GameEvents Are NOT

### Not State Queries

**Wrong**: Generate `IntelligenceReportRequestedEvent` to get current fleet positions

**Right**: Query game state directly, apply fog of war filter, return data

Intelligence reports are reads of current information, not events. Events represent changes that occurred.

### Not Tight Coupling

**Wrong**: Combat system fires `UpdatePlayerUIEvent` with damage details

**Right**: Combat system fires `ShipDamagedEvent`, UI system subscribes and updates itself

Events decouple systems. Publishers don't know who's listening.

### Not Internal Implementation

**Wrong**: Fire events for every intermediate calculation in combat resolution

**Right**: Fire events for observable outcomes - hits, kills, phase completions

Only create events for things that matter externally, not internal algorithms.

## GameEvents vs Intelligence Reports

| Aspect | GameEvents | Intelligence Reports |
|--------|-----------|---------------------|
| **Nature** | Things that happened | Current situation |
| **Timing** | During turn resolution | During planning phase |
| **Source** | Actions/outcomes | Game state |
| **Purpose** | Reaction, history, analysis | Decision-making input |
| **Filtering** | What AI could observe | What AI can currently see |
| **Temporal** | Past occurrences | Present status |
| **User** | AI (filtered), You (unfiltered), Players (narrative) | AI planning, Player planning |

## Hybrid Usage: When to Combine Events + State

### Player-Facing Reports: Always Hybrid

Players need both **what happened** (events) and **current situation** (state).

**Bad - State only**:
```
Battle Report:
Result: Victory
Casualties: 2 ships destroyed
Current Status: 8 ships remaining, 3 damaged
```

**Good - Hybrid**:
```
Battle Report:
Result: Victory (state)
Your losses: Destroyer 'Vigilant', Frigate 'Swift' (state)
Enemy losses: 5 ships destroyed (state)

What happened: (events)
Round 1: 'Vigilant' critically damaged by railgun barrage
Round 2: Enemy frigate destroyed by your missiles  
Round 3: 'Vigilant' destroyed, 'Swift' killed covering retreat
Round 4-6: Your cruisers overwhelmed remaining enemy ships
```

Players understand *why* they won/lost and can learn from tactics.

### AI Planning: State Only

AI doesn't need narrative during planning phase. It queries current state:

```nim
proc planTurn(ai: AI, gameState: GameState) =
  # Query filtered state
  let visibleFleets = gameState.getVisibleFleets(ai.player)
  let threatLevel = ai.assessThreats(visibleFleets)
  
  # Make decisions from current situation
  if threatLevel > THRESHOLD:
    ai.orderDefensivePosture()
  
  # No events involved - just reading "what is"
```

AI *receives* events during turn resolution (for reactive assessment), but doesn't query them during planning.

### Developer Analysis: Events Only (Unfiltered)

You analyze raw event logs without state:

```nim
proc analyzeWeaponBalance(eventLog: string) =
  # Parse all combat events
  let events = parseEvents(eventLog)
  
  # Count kills by weapon type
  for event in events:
    if event of ShipDestroyedEvent:
      weaponKills[event.weaponType] += 1
  
  # Pure event analysis - state not needed
  echo "Missiles: ", weaponKills[Missile]
  echo "Railguns: ", weaponKills[Railgun]
```

### Implementation Pattern

```nim
type
  CombatReport = object
    # From state
    victor: PlayerID
    yourCasualties: seq[ShipID]
    enemyCasualties: seq[ShipID]
    fleetStatus: FleetStatus
    
    # From events
    combatLog: seq[CombatEvent]
    roundCount: int
    keyMoments: seq[string]

proc generateCombatReport(battleId: string, 
                          gameState: GameState,
                          eventHistory: EventHistory): CombatReport =
  # Query current state for aftermath
  let battle = gameState.getBattle(battleId)
  result.victor = battle.victor
  result.yourCasualties = battle.yourLosses
  result.enemyCasualties = battle.enemyLosses
  result.fleetStatus = gameState.getFleet(battle.yourFleet)
  
  # Pull events for narrative
  result.combatLog = eventHistory.getCombatEvents(battleId)
  result.roundCount = result.combatLog.maxRound()
  result.keyMoments = extractKeyMoments(result.combatLog)
  
  return result

# AI planning uses state only
proc planDefense(ai: AI, gameState: GameState) =
  let threats = gameState.getVisibleThreats(ai.player)  # State query
  # No events needed - just current situation

# Player views hybrid report
proc showCombatReport(player: Player, battleId: string) =
  let report = generateCombatReport(battleId, gameState, eventHistory)
  displayReport(report)  # Shows state + events combined
```

### When Each Approach Applies

**State Only** (Intelligence Reports):
- "What enemy fleets can I see right now?"
- "What's my current resource production?"  
- "Which colonies are vulnerable?"
- AI making strategic decisions

**Events Only**:
- Developer weapon balance analysis
- Performance profiling turn resolution
- Debugging why something happened
- Replay/step-through debugging

**Hybrid** (After-Action Reports):
- Combat reports for players
- Turn summaries (state + what happened)
- "Last turn review" UI
- Teaching players game mechanics through examples

### Example: Fleet Intelligence

**GameEvent flow (during resolution)**:
1. Enemy fleet begins movement → `FleetMovementBeganEvent`
2. Your sensor detects it → Event delivered to your AI (filtered by sensor range)
3. Your AI logs "enemy fleet moving toward border" for next turn consideration
4. Fleet completes movement → `FleetMovementCompletedEvent`
5. Event updates fog of war state with new fleet position

**Intelligence Report flow (planning phase)**:
1. Your AI needs to plan turn → queries game state
2. Game state returns: "3 enemy fleets visible, positions X/Y/Z" (fog of war filtered)
3. AI uses this for strategic planning
4. No events involved - just reading current state

### Example: Battle Intelligence

**GameEvents capture (during combat)**:
- Weapons fired, hits/misses, damage amounts
- Ships destroyed, phases completed
- Tactical decisions, retreat triggers
- All logged for your balance analysis

**After battle, state shows**:
- Fleet composition changed (ships destroyed)
- Remaining ships have damage
- Colony infrastructure reduced (if orbital/planetary)

**Intelligence report from state**:
- "Enemy fleet in sector X has 5 ships, appears damaged"
- "Colony Alpha infrastructure at 73%"
- No detail about *how* battle went - that's only in events

**Your analysis of events reveals**:
- Missile cruisers killed 14 ships, beam cruisers killed 3 → missiles overpowered
- Orbital phase lasted 1 round 80% of time → too short, not interesting
- Planetary invasions fail 88% without orbital superiority → working as intended

## Implementation Pattern

```nim
type
  GameEvent = ref object of RootObj
    turn: int
    timestamp: Time
    
  EventBus = object
    subscribers: Table[string, seq[EventHandler]]
    log_file: File  # For your analysis
    
proc fire(bus: var EventBus, event: GameEvent, visibility: set[PlayerID]) =
  # Log for developer analysis (unfiltered)
  bus.log_file.writeLine(event.toJson())
  
  # Deliver to AI players (filtered by visibility)
  for player in visibility:
    let handlers = bus.subscribers.getOrDefault($player)
    for handler in handlers:
      handler(event)

# During turn resolution
proc executeFleetOrder(order: FleetOrder, bus: var EventBus) =
  let event = FleetMovementBeganEvent(
    turn: currentTurn,
    fleet: order.fleet,
    destination: order.target
  )
  
  # Who can see this?
  let visible_to = calculateVisibility(order.fleet.position)
  
  bus.fire(event, visible_to)
  
  # ... actually move fleet ...
  
  bus.fire(FleetMovementCompletedEvent(...), visible_to)

# AI receives filtered events
proc onFleetMovement(ai: AI, event: FleetMovementBeganEvent) =
  # React to enemy movement
  if event.fleet.owner != ai.player:
    ai.threatsNearBorder.add(event.fleet)

# You analyze logged events after games
proc analyzeWeaponBalance(log_file: string) =
  let events = parseEventLog(log_file)
  let weapon_kills = initCountTable[WeaponType]()
  
  for event in events:
    if event of ShipDestroyedInCombatEvent:
      let e = ShipDestroyedInCombatEvent(event)
      weapon_kills.inc(e.destroyed_by.weapon_type)
  
  echo weapon_kills  # missiles: 847, beams: 213 → missiles too strong
```

## Guidelines

### When to Create Events

✅ **Do create events for**:
- Order execution milestones (begin/complete/abort/fail)
- Combat outcomes (hits, kills, phase completions)
- State changes multiple systems care about
- Things AI players need to observe
- Data you need for balance analysis

❌ **Don't create events for**:
- Querying current state (use direct queries)
- Internal calculations (pathfinding steps, damage formulas)
- Data only one system cares about (just call it directly)
- Things no one will react to or analyze

### Event Granularity

**Too coarse**: `BattleCompletedEvent` with winner only
- Can't analyze weapon balance
- Can't see phase-by-phase flow
- AI can't learn from tactics

**Too fine**: `ProjectileMovedEvent` for every frame of missile travel
- Massive event volume
- No one cares about intermediate physics
- Performance cost

**Right level**: `WeaponFiredEvent`, `ShipDamagedEvent`, `CombatPhaseCompletedEvent`
- Captures meaningful outcomes
- Analyzable for balance
- Observable by AI
- Reasonable volume

### Fog of War Filtering

Events should respect information warfare:

```nim
proc calculateVisibility(position: Position): set[PlayerID] =
  result = {}
  for player in allPlayers:
    if player.hasSensorCoverage(position):
      result.incl(player.id)

# Stealth events might only be visible to player who conducted them
proc executeEspionageOperation(op: EspionageOp, bus: var EventBus) =
  # Operation succeeds
  let event = EspionageSuccessEvent(...)
  bus.fire(event, {op.player})  # Only spy knows it worked
  
  # But maybe detected
  if detectRoll() > op.stealthRating:
    let detected = EspionageDetectedEvent(...)
    bus.fire(detected, {targetPlayer})  # Target knows they were spied on
```

### Event Visibility & Fairness: AI vs Human Players

**Question**: If AI receives GameEvents during resolution but players only see reports after, isn't that cheating?

**Answer**: No, because both receive the **same filtered information** - just at different times in the processing cycle.

**How visibility filtering works**:

```nim
proc executeFleetOrder(order: FleetOrder, bus: var EventBus) =
  let event = FleetMovementBeganEvent(
    fleet: order.fleet,
    destination: order.target
  )
  
  # Calculate who can observe this movement
  let visible_to = calculateVisibility(order.fleet.position)
  
  # Only deliver to players with sensor coverage
  bus.fire(event, visible_to)
```

AI players only receive events they can legitimately observe:
- Events in sectors with sensor coverage
- Events detected by espionage operations  
- Events about their own assets
- Events visible through diplomatic channels

**Same rules as human players.**

**The difference is presentation, not information**:

| Aspect | AI Player | Human Player |
|--------|-----------|--------------|
| **Information** | Fleet moved toward border | Fleet moved toward border |
| **Filtering** | Sensor coverage required | Sensor coverage required |
| **Timing** | During turn resolution | After resolution complete |
| **Format** | `FleetMovementBeganEvent` object | "Enemy fleet detected moving toward Sector 7" |
| **Processing** | Immediate programmatic reaction | Reviews report, plans response |

**Example scenario**:

Turn 47 resolution:
1. Enemy fleet begins movement in Sector 12
2. Your sensors cover Sector 12 → event is visible to you
3. AI player: Receives `FleetMovementBeganEvent`, logs threat for next turn planning
4. Human player: After resolution, sees combat report "Turn 47: Enemy fleet detected moving in Sector 12"

Both players have identical information. AI processes it programmatically during resolution. Human reviews it in formatted report afterward.

**What would be cheating**:

❌ AI receives all events regardless of sensor coverage
❌ AI gets events about hidden enemy movements
❌ AI sees precise damage calculations human doesn't see
❌ AI queries event history beyond what reports show

**What's fair**:

✅ AI receives only observable events (same fog of war)
✅ AI processes events programmatically (that's its nature)
✅ Human gets same info in readable format
✅ Both query state with same visibility rules

**Ensuring fairness**:

The key question: Does `calculateVisibility()` apply the same rules to AI and human players?

```nim
proc calculateVisibility(position: Position): set[PlayerID] =
  result = {}
  for player in allPlayers:
    if player.hasSensorCoverage(position):
      result.incl(player.id)  # Same check for AI and human
```

If your visibility calculation is symmetric, the system is fair. AI's advantage is processing speed and consistency, not access to privileged information.

**Best practices**:

1. **Always filter events by visibility** - never send unfiltered events to AI
2. **Use same sensor/intelligence rules** - don't give AI special detection
3. **Show players what AI sees** - if AI gets an event, player report should mention it
4. **Test with observer mode** - watch AI receive events, verify it matches player reports
5. **Log violations** - if AI receives event it shouldn't see, that's a bug

**Example of proper filtering**:

```nim
# Fleet movement in deep space
let event = FleetMovementBeganEvent(fleet: enemyFleet)
let visible_to = calculateVisibility(enemyFleet.position)

if visible_to.len == 0:
  # No one can see this movement
  # AI doesn't get event, player doesn't get report
  discard
else:
  # Someone has sensors here
  bus.fire(event, visible_to)
  # Both AI and human players (in visible_to set) will know about this
  # AI gets event object, human gets "Enemy fleet detected" in report
```

The timing difference (AI during resolution, player after) is not unfair - it's just the nature of programmatic vs human decision-making. The human player doesn't need real-time events because they only plan during planning phase anyway. What matters is both players have access to the same information when making decisions.

### Performance Considerations

Events have costs:
- Object allocation
- Serialization (for logging)
- Delivery to subscribers
- Log file I/O

Mitigate by:
- Batch event delivery when possible
- Use efficient serialization (binary for saves, JSON for analysis logs)
- Archive old events aggressively
- Don't create events no one will use

Monitor event volume per turn - if it's huge, you're probably too granular.

## Developer Analysis Workflows

### Collecting Data for Balance & Performance Analysis

You need structured data collection to tune game balance and identify bugs. The question is: how do you organize GameEvents and GameState for effective analysis?

**Recommendation: Start with unified diagnostics, split later if needed**

### Initial Approach: Fold Everything Into Diagnostics

Combine GameState snapshots with GameEvent logs in single turn diagnostics:

```nim
type
  TurnDiagnostics = object
    turn: int
    timestamp: Time
    
    # State snapshot (what the world looks like now)
    gameState: GameStateSnapshot
    playerStates: seq[PlayerSnapshot]
    
    # Events (what happened this turn)
    events: seq[GameEvent]
    
    # Derived statistics
    combatStats: CombatStatistics
    economicStats: EconomicStatistics
    performanceMetrics: PerformanceMetrics
    
  CombatStatistics = object
    totalBattles: int
    avgBattleDuration: float
    killsByWeaponType: CountTable[WeaponType]
    killsByShipClass: CountTable[ShipClass]
    survivalRates: Table[ShipClass, float]
    phaseDistribution: array[CombatPhase, int]
    
  PerformanceMetrics = object
    turnResolutionMs: int
    aiThinkingMs: Table[PlayerID, int]
    eventCount: int
    combatResolutionMs: int

proc generateTurnDiagnostics(turn: int, 
                              state: GameState, 
                              events: seq[GameEvent]): TurnDiagnostics =
  result.turn = turn
  result.timestamp = now()
  result.gameState = state.snapshot()
  result.playerStates = state.getPlayerSnapshots()
  result.events = events
  
  # Analyze events for statistics
  result.combatStats = analyzeCombatEvents(events)
  result.economicStats = analyzeEconomicEvents(events)
  result.performanceMetrics = analyzePerformance(events)
  
proc saveDiagnostics(diag: TurnDiagnostics, outputDir: string) =
  # Save as JSON for human readability and tool parsing
  let filename = outputDir / fmt"turn_{diag.turn:04d}.json"
  writeFile(filename, diag.toJson())
```

**Why start unified**:
- See correlations: "AI had resource advantage (state) but made poor tactical choices (events)"
- One file per turn - easy to locate specific scenarios
- Simple to implement - just extend existing diagnostics
- Natural chronological organization

### What to Track

**Combat Balance**:
```nim
proc analyzeCombatEvents(events: seq[GameEvent]): CombatStatistics =
  var stats: CombatStatistics
  
  for event in events:
    case event.kind:
    of WeaponFiredEvent:
      let e = WeaponFiredEvent(event)
      if e.hit:
        stats.hitsByWeapon[e.weaponType] += 1
      stats.totalShots += 1
      
    of ShipDestroyedEvent:
      let e = ShipDestroyedEvent(event)
      stats.killsByWeaponType.inc(e.killedBy.weaponType)
      stats.killsByShipClass.inc(e.shipClass)
      
    of CombatPhaseCompletedEvent:
      let e = CombatPhaseCompletedEvent(event)
      stats.phaseDistribution[e.phase] += 1
      stats.avgRoundsPerPhase[e.phase] += e.rounds
  
  return stats
```

**AI Decision Quality**:
```nim
type
  AIDecisionStats = object
    ordersIssued: int
    ordersCompleted: int
    ordersFailed: int
    ordersAborted: int
    avgThinkingTime: float
    resourceEfficiency: float
    
proc analyzeAIPerformance(events: seq[GameEvent], 
                          state: GameState,
                          player: PlayerID): AIDecisionStats =
  # Compare AI intentions (from events) to outcomes (from state)
  # Did AI make sensible moves given information available?
```

**Performance Bottlenecks**:
```nim
type
  PerformanceBreakdown = object
    totalTurnMs: int
    breakdown: Table[string, int]  # phase -> milliseconds
    
proc trackPerformance(events: seq[GameEvent]): PerformanceBreakdown =
  var perf: PerformanceBreakdown
  var phaseStarts: Table[string, Time]
  
  for event in events:
    case event.kind:
    of TurnPhaseStartedEvent:
      phaseStarts[event.phase] = event.timestamp
    of TurnPhaseCompletedEvent:
      let duration = (event.timestamp - phaseStarts[event.phase]).inMilliseconds
      perf.breakdown[event.phase] = duration
      
  return perf
```

### Analysis Queries

After collecting diagnostics over many games, run analysis:

**Balance Analysis**:
```bash
# Find weapon imbalances
jq '[.combatStats.killsByWeaponType] | add' turn_*.json | \
  jq 'to_entries | sort_by(.value) | reverse'

# Output: {"Missiles": 847, "Railguns": 213, "Beams": 156}
# Conclusion: Missiles way too strong

# Ship class survival rates
jq '.combatStats.survivalRates' turn_*.json | \
  jq -s 'group_by(keys[0]) | map({class: .[0] | keys[0], avg: (map(values[0]) | add / length)})'

# Output: Destroyers 23% survival, Cruisers 67% survival
# Conclusion: Destroyers too fragile or too aggressive
```

**AI Behavior Patterns**:
```bash
# How often does AI retreat vs fight to death?
jq '[.events[] | select(.type == "FleetOrderAbortedEvent") | .reason] | group_by(.) | map({reason: .[0], count: length})' turn_*.json

# AI resource management efficiency
jq '.playerStates[] | select(.isAI) | {turn: .turn, resources: .resources, fleetSize: .totalShips}' turn_*.json > ai_economy.json
```

**Performance Regression Detection**:
```bash
# Track turn resolution time over game
jq '{turn: .turn, resolutionMs: .performanceMetrics.turnResolutionMs}' turn_*.json

# Identify slowest turns for profiling
jq 'select(.performanceMetrics.turnResolutionMs > 5000) | {turn: .turn, ms: .performanceMetrics.turnResolutionMs, eventCount: .performanceMetrics.eventCount}' turn_*.json
```

### When to Split Diagnostics

Split into separate files when:

**1. File size becomes problematic**
- Single turn diagnostic > 10MB → separate state snapshot from event log
- Need to process thousands of turns → events and state in different directories

**2. Different retention needs**
```nim
# Keep balance data indefinitely
saveEventLog(events, "balance_data/game_{id}_turn_{turn}.jsonl")

# Keep state snapshots only for recent turns (debugging)
if turn > currentTurn - 10:
  saveStateSnapshot(state, "debug_snapshots/turn_{turn}.json")
```

**3. Different analysis workflows**

Balance analysis pipeline:
```bash
# Only needs events
cat balance_data/*.jsonl | jq -s '[.[] | .combatStats]' | analysis.py
```

Bug reproduction:
```bash
# Needs full state
cp debug_snapshots/turn_0047.json bug_reports/fleet_stuck_issue.json
```

**4. Processing performance matters**
```nim
# Streaming event log for live analysis
for event in eventStream:
  logFile.writeLine(event.toJson())  # Append-only, fast

# State snapshot saved separately, less frequently  
if turn mod 10 == 0:
  saveStateSnapshot(state, ...)
```

### Recommended Structure After Split

```
diagnostics/
  game_12345/
    events/
      turn_0001.jsonl    # Line-delimited JSON, one event per line
      turn_0002.jsonl
      ...
    snapshots/
      turn_0001.json     # Full state snapshot (large)
      turn_0010.json     # Only keep every 10th
      turn_0020.json
    analysis/
      combat_balance.json    # Aggregated statistics
      performance.json       # Performance metrics summary
      ai_decisions.json      # AI behavior analysis
```

### Analysis Workflow Example

**1. Generate diagnostics during game**:
```nim
proc processTurn(game: Game) =
  let events = resolveTurn(game)
  let diag = generateTurnDiagnostics(game.turn, game.state, events)
  saveDiagnostics(diag, fmt"diagnostics/game_{game.id}")
```

**2. Run analysis after game**:
```nim
proc analyzeGame(gameId: string) =
  let diagDir = fmt"diagnostics/game_{gameId}"
  
  # Load all turn diagnostics
  var allStats: seq[CombatStatistics]
  for file in walkFiles(diagDir / "turn_*.json"):
    let diag = parseJson(readFile(file)).to(TurnDiagnostics)
    allStats.add(diag.combatStats)
  
  # Aggregate and report
  let weaponBalance = aggregateWeaponKills(allStats)
  let phaseBalance = aggregatePhaseStats(allStats)
  
  echo "Weapon Balance:"
  for weapon, kills in weaponBalance:
    echo fmt"  {weapon}: {kills} kills"
  
  echo "\nPhase Duration:"
  for phase, avgRounds in phaseBalance:
    echo fmt"  {phase}: {avgRounds:.1f} rounds avg"
```

**3. Compare across many games**:
```nim
proc compareBalanceAcrossGames(gameIds: seq[string]) =
  var aggregateStats: CountTable[WeaponType]
  
  for gameId in gameIds:
    let gameStats = loadGameStatistics(gameId)
    for weapon, kills in gameStats.weaponKills:
      aggregateStats.inc(weapon, kills)
  
  # Now see patterns across 100 games instead of 1
  echo "Aggregate weapon performance (100 games):"
  for weapon, kills in aggregateStats.pairs:
    echo fmt"  {weapon}: {kills} total kills"
```

### What NOT to Log

Don't create events or log data for:
- Intermediate calculations (damage formulas, pathfinding steps)
- Data you can reconstruct from other logs
- Information you'll never analyze
- Excessive detail (every frame of animation)

**Example - Too much detail**:
```nim
# DON'T DO THIS
type
  ProjectilePositionEvent = object  # Fired every frame
    projectile: ProjectileID
    x, y, z: float
    velocity: Vector3
```

**Example - Right level**:
```nim
# DO THIS INSTEAD
type
  WeaponFiredEvent = object
    weapon: WeaponType
    attacker, target: ShipID
    
  WeaponHitEvent = object
    weapon: WeaponType
    target: ShipID
    damage: int
```

### Tools & Utilities

**Quick grep patterns**:
```bash
# Find all battles where player lost
jq 'select(.combatStats.victorPlayer != "PLAYER_ID")' turn_*.json

# Battles lasting > 10 rounds
jq 'select(.combatStats.totalRounds > 10)' turn_*.json

# AI players who went bankrupt
jq '.playerStates[] | select(.isAI and .resources.credits < 0)' turn_*.json
```

**Plotting time series**:
```python
import json
import matplotlib.pyplot as plt

turns = []
resolution_times = []

for file in sorted(glob.glob('turn_*.json')):
    with open(file) as f:
        data = json.load(f)
        turns.append(data['turn'])
        resolution_times.append(data['performanceMetrics']['turnResolutionMs'])

plt.plot(turns, resolution_times)
plt.xlabel('Turn')
plt.ylabel('Resolution Time (ms)')
plt.title('Performance Over Game')
plt.show()
```

### Summary: Data Collection Strategy

**Phase 1 (Now)**: Unified diagnostics
- Combine GameState + GameEvents in single turn file
- Easy correlation, simple to implement
- Start collecting data, learn what patterns matter

**Phase 2 (Later)**: Split when needed
- Separate event logs from state snapshots
- Different retention policies
- Optimized for analysis tools

**Phase 3 (Much later)**: Structured analytics
- Database instead of JSON files
- Automated regression detection
- Dashboard for live monitoring

Start simple. Add complexity only when you need it.

## Summary

**GameEvents are your temporal chronicle** of what happened during turn resolution. They serve three masters with different usage patterns:

1. **AI players** - Events only (filtered) during resolution for reactive behavior; State only (filtered) during planning
2. **You** - Events only (unfiltered) for balance and performance analysis  
3. **Players** - Hybrid (events + state) for combat reports and turn summaries

**Usage patterns**:

- **Intelligence Reports** (State only): Current situation for decision-making
- **After-Action Reports** (Hybrid): What happened + current aftermath for player understanding
- **Developer Analysis** (Events only): Raw data for balance tuning
- **AI Planning** (State only): Current threats/opportunities for strategy
- **AI Reaction** (Events only): Observable occurrences during resolution

Keep events focused on **observable occurrences** that either:
- Multiple systems need to react to (AI observation)
- You need to analyze for game design (balance data)
- Players need to understand outcomes (narrative context)

Everything else is just noise.
