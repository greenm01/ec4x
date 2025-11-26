# 9. Intelligence System

The intelligence system provides detailed reporting on enemy forces, infrastructure, and economic capabilities gathered through scouts, espionage, and fleet encounters. Intelligence forms the foundation of strategic decision-making in EC4X's fog-of-war environment.

## 9.1 Intelligence Sources

Intelligence can be gathered through multiple sources, each providing different quality and scope of information.

### 9.1.1 Scout Reconnaissance (Perfect Quality)

**Scout Squadrons** operating under espionage orders (SpyOnPlanet, SpyOnSystem, HackStarbase) gather the most comprehensive intelligence available. Scouts provide:

- **Perfect accuracy** - All reported data is current and exact
- **Complete fleet composition** - Ship types, tech levels, hull integrity, cargo contents
- **Full economic data** - Colony output, tax revenue, construction queues
- **Strategic intelligence** - Fleet orders, standing orders, patrol routes

**Scout Advantages:**
- See everything: fleets, colonies, combat, bombardment, blockades, construction
- Detailed fleet composition including tech levels and hull integrity
- Construction progress tracking over time
- Fleet movement pattern detection
- Patrol route analysis
- Witness and report all events in system

Scouts can be corrupted by Disinformation (espionage) or Dishonored status (diplomacy), reducing intelligence reliability. See [Section 9.4](#94-intelligence-corruption).

### 9.1.2 Regular Fleet Encounters (Visual Quality)

When any friendly fleet occupies the same system as foreign forces, **visual intelligence** is automatically gathered:

- **Squadron composition** - Ship types and counts (e.g., "3 Destroyers, 2 Cruisers")
- **Transport count** - Number of spacelift ships present
- **Standing orders** - Observable fleet behavior (Patrol, Guard, Blockade, etc.)
- **Fleet location** - Current system position

**Visual Limitations:**
- ❌ No tech level information (shows as 0)
- ❌ No hull integrity data (cannot assess damage)
- ❌ No cargo contents (transport ships show count only)

This reflects tactical observation - you can see what ships are present, but not their technological sophistication or strategic cargo.

### 9.1.3 Spy Operations (Spy Quality)

**Espionage missions** (SpyOnPlanet, SpyOnSystem, HackStarbase) conducted by scout squadrons provide high-quality intelligence with some economic visibility:

**SpyOnPlanet** reveals:
- Colony population, industry (IU), defenses
- Starbase level
- Construction queue (all queued projects)
- **Economic data**: Gross Colonial Output (GCO), Net Colonial Value (NCV)
- Orbital defenses: unassigned squadrons, reserve/mothballed fleets, shipyards

**SpyOnSystem** reveals:
- All fleets in system with full composition
- Squadron details: ship classes, counts, tech levels, hull integrity
- Spacelift cargo manifests

**HackStarbase** reveals:
- Treasury balance, gross/net income, tax rate
- Tech levels across all research fields (Economic, Science, Technology)
- Research allocations (ERP, SRP, TRP)
- Current research focus

See [Section 6.2.9-6.2.11](operations.md#629-spy-on-a-planet-09) for operational details.

### 9.1.4 Starbase Surveillance (Scan Quality)

**Starbases with Advanced Sensors** automatically monitor their sector (system + adjacent systems):

- Detect all non-stealthed fleet movements
- Track fleet transit between systems
- Identify combat and bombardment activity
- Provide threat assessment

**Detection Evasion:**
- Scouts and cloaked Raiders can evade detection with successful stealth rolls
- See [Section 7.1.3](operations.md#713-cloaking-and-detection) for detection mechanics

## 9.2 Intelligence Report Types

The game generates detailed intelligence reports from various sources, stored in each house's intelligence database.

### 9.2.1 Scout Encounter Reports

Generated whenever scouts observe activity in a system. Types include:

**Fleet Sighting**
- Detailed fleet composition
- Squadron breakdown with tech levels
- Spacelift cargo details (type, quantity, damage status)
- Standing orders
- Significance: 7/10

**Colony Discovered**
- Complete colony statistics
- Economic data (if Spy+ quality)
- Construction queue
- Orbital defenses inventory
- Significance: 8/10

**Combat Witnessed**
- Pre-combat force compositions (both sides)
- Observed losses
- Retreats and outcomes
- Significance: Variable (5-10)

**Construction Activity**
- Infrastructure changes
- Completed projects
- Active construction queue
- Facility counts (shipyards, spaceports, starbases)
- Significance: 5/10

### 9.2.2 Fleet Movement History

The intelligence system tracks enemy fleet movements over time:

- **Chronological sightings**: Turn and system for each observation
- **Last known location**: Most recent confirmed position
- **Patrol pattern detection**: Identifies repeated routes
- **Staleness indicator**: Turns since last sighting

This enables strategic prediction of enemy fleet positions and patrol routes.

### 9.2.3 Combat Encounter Reports

Generated automatically during combat for all participating and observing forces:

**Pre-Combat Intelligence** (always available):
- Allied force composition: Complete squadron breakdown
- Enemy force composition: Complete squadron breakdown
- Spacelift cargo details for both sides
- Fleet orders and standing orders
- Combat phase type (Space, Orbital, Planetary)

**Post-Combat Intelligence** (only if survivors):
- Battle outcome from reporter's perspective
- Allied losses (squadron IDs)
- Enemy losses (ship classes observed)
- Retreated fleets (both sides if observed)
- Survival status

### 9.2.4 Diplomatic Intelligence

All houses automatically receive intelligence on major diplomatic events:

**Pact Formations**
- Non-Aggression pacts between any houses
- Public visibility (all houses notified)

**Pact Violations**
- Pact breaks and resulting war declarations
- Public shame and dishonor status
- Violation history tracking

**War Declarations**
- Direct enemy declarations
- Public visibility

**Peace Treaties**
- Return to neutral status
- Cessation of hostilities

See [Section 8.1](diplomacy.md#81-diplomacy) for diplomatic mechanics.

### 9.2.5 Espionage Activity Reports

Houses receive reports when espionage is detected against them:

- **Turn**: When activity occurred
- **Perpetrator**: Attacker house (if identified)
- **Action type**: What was attempted
- **Target system**: If system-specific
- **Detection status**: Whether perpetrator was identified
- **Description**: Human-readable summary

Failed espionage attempts that are detected provide valuable counter-intelligence.

## 9.3 Intelligence Quality Levels

Intelligence has four quality levels indicating reliability and detail:

### None
- No intelligence available
- System never visited or scouted
- Complete fog of war

### Visual (Regular Fleets)
- Basic tactical observation
- Ship types and counts visible
- Cannot assess tech levels (shows 0)
- Cannot see hull damage
- Cannot see cargo contents
- Transport count visible but not cargo

### Spy (Espionage Operations)
- High-quality intelligence
- Full fleet composition with tech levels
- Hull integrity assessment
- Economic data (GCO, NCV)
- Construction queues visible
- Research allocations revealed

### Perfect (Scouts & Owned Assets)
- Complete and current intelligence
- All details available
- No uncertainty
- Real-time updates
- Used for scout reports and own assets

## 9.4 Intelligence Corruption

Intelligence can be compromised through espionage or diplomatic dishonor, introducing false data into reports.

### 9.4.1 Disinformation (Espionage)

The **Plant Disinformation** espionage action corrupts target house's intelligence gathering:

**Effect**:
- **Duration**: 2 turns
- **Corruption magnitude**: 20-40% variance in reported values
- **Scope**: All intelligence reports (scouts, spies, visual)

**Corrupted Data:**
- Fleet compositions: Ship counts inflated/deflated
- Colony statistics: Population, industry, defenses randomized
- Economic data: Income, output, treasury altered
- Tech levels: Research levels misreported

**Cost**: 6 EBP
**Detection**: Can be blocked by Counter-Intelligence Sweep

See [Section 8.2.9](#829-plant-disinformation) for mechanics.

### 9.4.2 Dishonored Intelligence

Houses under **Dishonored status** (from pact violations) suffer intelligence corruption:

**Effect**:
- **Duration**: 3 turns (same as dishonor)
- **Corruption magnitude**: 50% variance (more severe than disinformation)
- **Cause**: Disorganized and demoralized forces provide unreliable reports

**Exception**: Final two houses are exempt from dishonor (and its intelligence corruption).

See [Section 8.1.2](diplomacy.md#812-non-aggression-pacts) for dishonor mechanics.

### 9.4.3 Corruption Detection

Corrupted intelligence is not marked as such - players receive false data that appears legitimate. The deterministic corruption system ensures consistency:

- Same turn/house/system always produces same corrupted values
- Prevents "flickering" intelligence between turns
- Multiple reports from corrupted source remain consistent
- Only renewed intelligence gathering provides truth

**Strategic Implications:**
- Counter-intelligence investment becomes critical
- Multiple intelligence sources provide verification
- Scout reports can be compromised (not always perfect)
- Dishonor penalties extend beyond prestige/diplomacy

## 9.5 Intelligence Staleness

Intelligence reports include timestamps showing when data was gathered. Stale intelligence remains visible but may no longer reflect reality.

### Staleness Display

- **Current (Turn N)**: Real-time data, perfect accuracy
- **Recent (1-2 turns old)**: Likely still accurate, minor changes possible
- **Stale (3-5 turns old)**: Moderate uncertainty, significant changes likely
- **Ancient (6+ turns old)**: High uncertainty, situation may have changed dramatically

### Strategic Implications

- Fleet positions become unreliable after 2-3 turns
- Colony data degrades as construction completes
- Economic intelligence becomes outdated quickly
- Tech levels change slowly (more reliable over time)

**UI Recommendation**: Show "Last updated: Turn X" on all intelligence displays.

## 9.6 Intelligence Database Storage

Each house maintains a separate intelligence database containing:

### Colony Intelligence
- **Storage**: Table indexed by SystemId
- **Data**: Population, industry, defenses, starbase, construction, economics
- **Updates**: Overwrite on new intelligence (keeps most recent)

### System Intelligence
- **Storage**: Table indexed by SystemId
- **Data**: Detected fleets with composition
- **Updates**: Overwrite on new intelligence

### Starbase Intelligence
- **Storage**: Table indexed by SystemId
- **Data**: Economic and R&D data
- **Updates**: Overwrite on new intelligence

### Scout Encounter Log
- **Storage**: Chronological append-only log
- **Data**: All scout observations with full context
- **Retention**: Permanent (provides historical intelligence)

### Fleet Movement History
- **Storage**: Table indexed by FleetId
- **Data**: Sightings chronology, patrol patterns, last known position
- **Updates**: Append new sightings, detect patterns

### Construction Activity Tracking
- **Storage**: Table indexed by SystemId
- **Data**: Infrastructure history, active projects, completed projects
- **Updates**: Append observations, detect completions

### Combat Reports
- **Storage**: Chronological append-only log
- **Data**: Pre-combat intel, outcomes, losses, survivors
- **Retention**: Permanent

### Starbase Surveillance
- **Storage**: Chronological append-only log
- **Data**: Automated sensor reports from starbases
- **Retention**: Recent turns only (configurable)

### Espionage Activity Log
- **Storage**: Chronological append-only log
- **Data**: Detected espionage attempts against this house
- **Retention**: Permanent (counter-intelligence value)

## 9.7 Strategic Use of Intelligence

### Reconnaissance Priority

**High-Value Targets:**
- Enemy home systems (full force assessment)
- Border systems (detect invasions early)
- Known fleet staging areas (track mobilization)
- Enemy research colonies (assess tech advantage)

### Intelligence Sharing

**Diplomatic Value:**
- Share scout reports with allies
- Trade intelligence for favors
- Reveal enemy movements to threatened neutrals
- Withhold intelligence as leverage

*Note: Intelligence sharing mechanics not yet implemented.*

### Counter-Intelligence Strategy

**Defensive Measures:**
- Invest in Counter-Intelligence Sweep to block disinformation
- Multiple intelligence sources for verification
- Scout own borders to detect enemy scouts
- Track intelligence staleness carefully

### Deception Tactics

**Offensive Use:**
- Plant disinformation to mislead enemy decisions
- Use cloaked raiders to avoid starbase detection
- Single-scout spy missions for stealth
- Hide fleet compositions until combat

## 9.8 Intelligence in Combat

### Pre-Combat Intelligence

Before combat begins, both sides receive complete intelligence on enemy forces through automatic observation. This represents the moment of engagement when stealth is no longer possible.

**Revealed Information:**
- All enemy squadrons with exact composition
- Tech levels of all enemy ships
- Hull integrity of enemy units
- Spacelift cargo (troops, colonists, supplies)

### Post-Combat Updates

Combat generates automatic intelligence reports for all participants:

- **Survivors**: Full post-combat report with outcomes
- **Observers** (scouts in system): Complete combat witness report
- **Destroyed forces**: No report generated (obviously)

This intelligence persists in the database for strategic analysis.

## 9.9 Future Enhancements

Potential intelligence system expansions:

### Intelligence Sharing
- Ally intel pooling
- Trade intel reports for PP
- Diplomatic intel exchanges

### Enhanced Analysis
- Automated threat assessment
- Fleet strength predictions
- Economic trajectory forecasting
- Tech level gap warnings

### Counter-Intelligence Operations
- Feed false intel to enemy spies
- Detect enemy scouts in territory
- Encryption tech (reduce intel quality)
- Decryption tech (improve intel quality)

### Long-Range Sensors
- Detect fleets 2+ jumps away
- Early warning systems
- Trade sensor range for detail

---

**Related Sections:**
- [Operations: Scout Missions](operations.md#629-spy-on-a-planet-09)
- [Diplomacy: Espionage](diplomacy.md#82-subversion--subterfuge)
- [Gameplay: Fog of War](gameplay.md#152-fog-of-war)
- [Architecture: Intel System](../architecture/intel.md)
