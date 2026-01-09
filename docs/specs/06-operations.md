# 6.0 Fleet Operations and Movement

Command your fleets across the stars. Direct them with explicit commands for immediate missions. Your strategic decisions at the fleet level drive military success—individual ships work together as unified task forces.

This section covers jump lane travel, ship commissioning pipelines, fleet commands, and repair operations. Master these systems to project power effectively across your empire.

---

## 6.1 Jump Lanes

Your fleets travel between star systems via **jump lanes**—pre-calculated routes through hyperspace connecting adjacent systems. Jump lanes define your strategic map: systems without lanes remain unreachable, while densely connected systems become strategic crossroads.

For complete details on jump lane classes, distribution, and the starmap structure, see [Section 2.1 Star Map](02-assets.md#21-star-map).

### 6.1.2 Jump Lane Movement Rules

**Movement capacity depends on lane control and lane class:**

- **Controlled major lanes**: If you own all systems along the travel path, your fleets can jump two major lanes in one turn
- **Minor and restricted lanes**: Enable a single jump per turn, regardless of the destination
- **Unexplored or rival systems**: Limit movement to one jump maximum
- **Lane restrictions**: Fleets containing crippled ships cannot traverse restricted lanes

### 6.1.3 Strategic Implications

**Chokepoints control empires**: Systems with few connecting lanes become natural defensive positions. Control the chokepoint and you control the region.

**Connectivity determines value**: Well-connected systems with major lanes serve as staging areas and logistics hubs. Isolated systems connected only by restricted lanes remain accessible but incur higher pathfinding costs.

**Patrol routes follow lanes**: Standing patrol commands automatically follow jump lane networks. Your fleets defend multiple systems using established lanes.

**Lane class matters for expansion**: Restricted lanes cost more movement points (weight 3 vs major weight 1), creating natural pathfinding preferences. ETACs can traverse all lane types when not crippled.

---

## 6.2 Ship Commissioning and Fleet Organization

Your industrial might produces warships and auxiliary vessels. Ships move from treasury expenditure through construction yards to commissioned status and finally into operational fleets. This three-stage pipeline transforms economic investment into military power.

### 6.2.1 The Commissioning Pipeline

**Stage One: Build Commands**

Allocate treasury (production points) to construction projects at your colonies. Each project requires available dock capacity at either spaceports or shipyards:

**Spaceports** (Planet-side Construction):
- Built in 1 turn, provides 5 construction docks
- Can build any ship type
- **100% commission penalty**: Ships (except fighters) cost double production points due to orbital launch costs
- Fighters exempt from penalty (distributed planetary manufacturing)
- Required prerequisite for building shipyards, spaceports, and starbases.

**Shipyards** (Orbital Construction):
- Built in 2 turns, requires existing spaceport, provides 10 construction docks
- Can build any ship type at standard cost (no penalty)
- **Construction only** - shipyards cannot repair ships (requires drydocks)
- Economically superior for all non-fighter construction

**Drydocks** (Orbital Repair):
- Built in 2 turns, requires existing spaceport, provides 10 repair docks
- **ONLY facility that can repair ships** - spaceports and shipyards cannot repair ships
- Repairs any ship class at 25% of build cost (1 turn)
- Dedicated repair infrastructure for fleet maintenance

**Ship Repair Requirements:**
- **All ship repairs require drydocks** - spaceports and shipyards cannot repair ships
- Repair cost: 25% of build cost
- Repair time: 1 turn for all ship classes
- Colonies without drydocks cannot repair crippled ships (must salvage or transfer to drydock colony)

**Facility Repair Requirements:**
- **Starbase repairs require spaceports** (not shipyards)
- Repair cost: 75 PP (25% of 300 PP base cost)
- Repair time: 1 turn
- **Important:** Starbase repairs do NOT consume dock capacity (separate repair queue from ships)

**Build Command Mechanics:**
- **Upfront payment**: Full construction cost (including spaceport penalties) deducted immediately from treasury
- **Construction time**: 1+ turns based on ship class and technology level
- **Simultaneous projects**: Limited only by available dock capacity across all facilities

**Strategic Priority:** Build shipyards early at all major colonies. The 100% spaceport penalty makes planet-side construction economically devastating for anything except fighters. Plan ahead—commit resources turn X, receive operational ships turn X+N.

**Stage Two: Construction Completion & Fleet Assignment**

When construction completes, your ships **immediately commission** and join fleets at their construction colony. No intermediate "ready to commission" state—your ships transition directly from construction to operational status.

**Ship Assignment Rules:**

**Combat ships** automatically join existing stationary fleets:
- Fleets with **Hold, Guard, or Patrol** commands (at same system)
- Fleets with **no commands** (default stationary posture)
- If no suitable fleet exists, creates new fleet automatically

**Scouts** form scout-only fleets for reconnaissance and scout intelligence missions

**Fighters** remain colony-assigned for orbital defense (not assigned to fleets)

**ETACs and Transports** join appropriate fleets based on operational needs

**Moving fleets do not receive reinforcements:**
- Fleets executing **movement commands** or on patrol routes
- **Reserve or Mothballed** fleets (intentional reduced-readiness status)

This system ensures ships join fleets **intentionally stationary** at your colony, not temporarily passing through. Your fleets maintain operational readiness without interrupting ongoing missions.

**Why automatic assignment?** Ships are organized into fleets for strategic control. You command at the fleet level—issuing fleet commands and managing fleet composition. Automatic assignment eliminates the micromanagement trap of forgetting to deploy newly-built units while preserving your strategic control.

**Stage Three: Fleet Operations**

Once in fleets, control your forces through **fleet commands**. Active fleets consume Command Cost (CC) from your House's C2 Pool. Transfer ships between fleets, adjust compositions, or place fleets in Reserve/Mothballed status to control operational costs.

### 6.2.2 Fleet Composition Strategy

Design your fleets for their mission profile:

**Battle fleets** combine capital ships with escort screens. Your Dreadnoughts and Battleships provide firepower; Destroyers and Frigates screen against threats.

**Patrol fleets** use Light Cruisers with Destroyer escorts for patrol routes and border security. Balance firepower with operational cost.

**Scout fleets** deploy scouts for intelligence gathering, system reconnaissance, and scout intelligence missions. Small footprint, high stealth.

**Mothball fleets** store mothballed ships at colonies for emergency mobilization. Zero CC cost, 10% maintenance. Ships are offline, defenseless, and screened during combat.

**Reserve fleets** are stationary colony defense forces. Ships operate at 50% combat effectiveness (Crippled state) but incur only 50% maintenance and CC costs. They are automatically assigned the **Blockade** command to participate in orbital defense but cannot move until reactivated.  

### 6.2.3 Rules of Engagement (ROE)

Configure fleet combat behavior with Rules of Engagement—a 0-10 scale determining when to fight and when to retreat.

**See [Section 7.2.3 Rules of Engagement](07-combat.md#723-rules-of-engagement-roe) for the complete table of retreat thresholds.**

| ROE  | Behavior                                        |
| ---- | ----------------------------------------------- |
| 0-2  | Extremely cautious - Retreat from any threat    |
| 3-5  | Defensive - Fight only if superior              |
| 6-8  | Aggressive - Fight unless clearly outnumbered   |
| 9-10 | Suicidal - Fight to the death                   |

**Usage:**
- Assign ROE when creating fleets or issuing commands.
- **Patrol/Guard with ROE 2**: Fleet patrols but retreats from any hostile contact.
- **Defend System with ROE 8**: Fleet defends aggressively, fighting unless outnumbered.

---

## 6.3 Fleet Commands

Command your fleets with 20 distinct mission types—from peaceful exploration to devastating orbital bombardment. Issue commands once; your fleets execute them persistently across turns until mission completion or your new commands override them.

### 6.3.1 Active Fleet Commands

Explicit commands that execute until completed or overridden:

| No. | Mission        | Requirements                             |
| --- | -------------- | ---------------------------------------- |
| 00  | Hold           | None                                     |
| 01  | Move           | None                                     |
| 02  | Seek Home      | None                                     |
| 03  | Patrol         | None                                     |
| 04  | Guard Starbase | Combat ship(s)                           |
| 05  | Guard Colony   | Combat ship(s)                           |
| 06  | Blockade       | Combat ship(s)                           |
| 07  | Bombard        | Combat ship(s)                           |
| 08  | Invade         | Combat ship(s) & loaded Troop Transports |
| 09  | Blitz          | Loaded Troop Transports                  |
| 10  | Colonize       | One ETAC                                 |
| 11  | Scout Colony   | Scout-only fleet (1+ scouts)             |
| 12  | Scout System   | Scout-only fleet (1+ scouts)             |
| 13  | Hack Starbase  | Scout-only fleet (1+ scouts)             |
| 14  | Join Fleet     | None                                     |
| 15  | Rendezvous     | None                                     |
| 16  | Salvage        | Friendly colony system                   |
| 17  | Reserve        | At friendly colony                       |
| 18  | Mothball       | At friendly colony with Spaceport        |
| 19  | Reactivate     | Reserve or Mothballed fleet              |
| 20  | View           | Any ship type                            |

**Command Defaults and Lifecycle:**

Every fleet **always has a command**—there is no "commandless" state. When a fleet completes its mission (e.g., arrives at Move destination, completes Salvage), it automatically reverts to **Hold Position (00)** if no new command has been queued.

- **New fleets**: Created with Hold Position (00) by default
- **Mission completion**: Fleet reverts to Hold Position (00)
- **Player override**: New commands replace current command immediately

This ensures fleets always have defined behavior for combat participant determination. Hold Position is the "awaiting orders" state from the player's perspective.

**Travel and Combat During Transit:**

Fleets travel across jump lanes at a rate determined by lane class and control (see Section 6.1.2). When traveling multi-hop routes, fleets **pause at each intermediate system** between jumps.

At each intermediate system during travel:
- Fleet `missionState` remains `Traveling` (not yet at destination)
- Combat eligibility is checked based on diplomatic status:
  - **Enemy status**: Combat occurs (automatic, simultaneous)
  - **Hostile/Neutral status**: No combat (safe passage)
- If combat occurs, the fleet may be delayed or destroyed before reaching destination

This creates strategic chokepoints where Enemy fleets can be intercepted during transit, while Hostile and Neutral fleets enjoy safe passage until they reach their mission destination and reveal hostile intent.

### 6.3.2 Hold (00)

Command your fleet to hold position and await new commands. Your fleet maintains station at its current location, providing defensive presence or staging position for future operations.

**Use Hold to:**
- Establish defensive positions at strategic locations
- Stage fleets for coordinated offensives
- Maintain presence without specific mission parameters

### 6.3.3 Move (01)

Move your fleet to a new solar system and hold position. Your fleet travels to the destination system, establishes presence, and is auto assigned order (00) to hold position to await further commands. Use Move for strategic repositioning without immediate combat intent.

**Use Move to:**
- Reposition forces to emerging threat sectors
- Establish presence at newly-colonized systems
- Concentrate forces before major offensives

### 6.3.4 Seek Home (02)

Command your fleet to return to the nearest friendly colony with drydock facilities. Your damaged forces automatically navigate to safe harbor for repairs and resupply.

**Use Seek Home to:**
- Evacuate damaged fleets from combat zones
- Return forces for strategic redeployment
- Consolidate scattered forces at major bases

### 6.3.5 Patrol (03)

Command your fleet to patrol a single solar system, maintaining defensive presence and engaging hostiles per your Rules of Engagement settings.

**Use Patrol Single System to:**
- Defend border systems from incursions
- Maintain presence in contested regions
- Screen friendly colonies from raiders

### 6.3.6 Guard Starbase (04)

Station your fleet at an orbiting starbase for defensive operations. Your fleet protects the starbase from attack, screens it during combat, and intercepts hostile forces.

**Use Guard Starbase to:**
- Protect critical infrastructure investments
- Create fortified defensive positions
- Support starbase fire during orbital combat

### 6.3.7 Guard Colony (05)

Deploy your fleet to defend a friendly colony. Your fleet maintains low orbit, participating in orbital combat to protect the colony.

**Use Guard Planet to:**
- Defend high-value colonies from bombardment
- Support ground forces during invasion attempts

### 6.3.8 Blockade (06)

Deploy your fleet to blockade a planet. Your fleet establishes orbital control, preventing colonization of uncolonized planets and disrupting economic activity at colonies.

**Against Colonies (Colonized Planets):**

A successful blockade severely disrupts colony operations:
- **Production Penalty**: Colony operates at 40% capacity (60% reduction to Gross Colonial Output)
- **Prestige Loss**: -2 prestige per turn per blockaded colony
- **Trade Disruption**: Guild transport vessels cannot reach blockaded system

The blockade continues as long as your fleet remains in orbit with hostile or enemy diplomatic status toward the colony owner.

**Against Uncolonized Planets:**

- **Colonization Prevention**: Enemy ETACs cannot establish colonies while blockade is active
- **No economic penalty** (no colony to penalize)

**Diplomatic Effect:** Blockade is a Tier 1 (Attack) mission—escalates to Enemy status with immediate combat regardless of whether the target is colonized.

**Tactical Considerations:**

- Blockades require maintaining orbital superiority—if defeated in orbital combat, your blockade fails
- Multiple planets can be blockaded simultaneously by different fleets
- Prolonged blockades can starve enemy production without the prestige penalties of bombardment
- Blockades are less destructive than bombardment but achieve similar strategic effects over time
- Blockading uncolonized planets denies expansion opportunities to rivals

**Use Blockade to:**
- Strangle enemy production capacity without bombardment penalties
- Deny enemy access to critical resource systems
- Prevent rivals from colonizing strategic planets
- Force enemy fleets to engage on unfavorable terms
- Pressure enemies economically while minimizing diplomatic fallout

### 6.3.9 Bombard (07)

Command devastating orbital bombardment of enemy colonies. Your fleet systematically destroys infrastructure, reducing the colony's industrial capacity and effectiveness.

**Destruction Effects:**
- Infrastructure damage accumulates per turn
- Reduces production capacity
- Can destroy facilities (spaceports, shipyards)
- May cause population casualties

**Use Bombardment to:**
- Prepare targets for invasion
- Destroy enemy production capacity
- Punish enemy aggression
- **WARNING**: Bombardment generates massive diplomatic penalties

### 6.3.10 Invade (08)

Launch ground invasion of enemy colonies. Your fleet deploys marines and army units to seize control, conducting ground combat against defending forces.

**Requirements:**
- Fleet must contain troop transports with embarked Marines
- Target colony must have reduced defenses (planetary shields destroyed, garrison weakened)

**Combat Resolution:**
- Ground forces fight defending armies
- Orbital support from your fleet
- Infrastructure damage during combat
- Successful invasion transfers colony ownership

**Use Invasion to:**
- Conquer enemy systems
- Capture strategic colonies intact
- Expand your empire through force

### 6.3.11 Blitz (09)

Execute rapid planetary assault combining orbital bombardment with immediate ground invasion. Your forces strike simultaneously, overwhelming defenders before they can coordinate defense.

**Requirements:**
- Loaded troop transports
- Sufficient orbital superiority

**Use Blitz to:**
- Capture lightly-defended colonies rapidly
- Exploit tactical windows before reinforcements arrive
- Reduce siege time for strategic operations

### 6.3.12 Colonize (10)

Command ETACs (Enhanced Terrestrial Administrative Carriers) with Population Transfer Units to establish new colonies. Your fleet travels to the target system, deploys the PTUs, and establishes colonial infrastructure. Once a planet is colonized, it may not be colonized again and must be conquored to change ownership.

**Requirements:**
- Fleet must contain at least one ETAC ship
- ETAC must carry PTUs (Population Transfer Units)
- Target system cannot already have a colony (one colony per system)

**Results:**
- New colony established at infrastructure Level I (3 PU foundation colony)
- All 3 PTU deposited on single colony
- ETAC ship cannibalized for colony infrastructure (no refund)
- Awards prestige for expansion
- **ETAC behavior after colonization:**
  - Ship is removed from game (one-time consumable)
  - Build new ETACs at established colonies to continue expansion

### 6.3.13 Scout Colony (11)

Deploy a Scout fleet on a one-way mission to gather detailed intelligence on an enemy colony. All Scouts in the fleet are consumed in the attempt, regardless of outcome.

**Requirements:**
- Fleet must contain **only Scouts**.

**Detection & Mission Success**:
Upon arrival, the defending house makes a detection roll to find your Scouts.
- **If detected**: The mission fails, the Scout is destroyed, and no intelligence is gathered.
- **If undetected**: The mission succeeds, and you receive a **Perfect Quality** intelligence report.

For the complete detection mechanic, see [Section 2.4.2](02-assets.md#242-scouts). Sending more scouts on the same mission makes them harder to detect.

**Intelligence Gathered:**
- Colony infrastructure level
- Industrial capacity (IU)
- Military facilities (spaceports, shipyards, etc.)
- Defensive installations (shields, batteries)
- Economic output (GCO, NCV)
- Construction queues

**Use Scout Colony to:**
- Assess target defenses before invasion
- Track enemy economic development
- Identify strategic targets for strikes

### 6.3.14 Scout System (12)

Deploy a Scout fleet on a one-way mission to gather intelligence on all fleet activity in a system. All Scouts in the fleet are consumed in the attempt.

**Requirements:**
- Fleet must contain **only Scouts**.

**Detection & Mission Success**: See Command 11 (Scout Colony) for detection mechanics.

**Intelligence Gathered:**
- All fleets present in system
- Fleet compositions
- Fleet commands (if detectable)
- Recent fleet movements

**Use Scout System to:**
- Provide early warning of enemy attacks
- Track hostile fleet movements
- Identify enemy patrol patterns
- Support strategic planning

### 6.3.15 Hack Starbase (13)

Conduct a cyber warfare operation against an enemy starbase. All Scouts in the fleet are consumed in the attempt.

**Requirements:**
- Fleet must contain **only Scouts**.
- Target system must have an enemy starbase.

**Detection & Mission Success**: See Command 11 (Scout Colony) for detection mechanics.

**Intelligence Gathered:**
- Research progress
- Economic production data
- Fleet movements
- Strategic plans

**Use Hack Starbase to:**
- Steal research advances
- Identify enemy fleet deployments
- Discover enemy strategic intentions
- Gain economic intelligence

### 6.3.16 Join Fleet (14)

Merge this fleet with another fleet. The source fleet will autonomously find and travel to the target fleet and consolidate forces for strategic operations. All ships from the source fleet are transferred to the target fleet, and the source fleet is disbanded.

**Use Join Fleet to:**
- Reinforce damaged fleets with fresh ships.
- Consolidate scattered forces after combat.
- Create combined forces for major operations.
- Group multiple Scouts into a single fleet to improve their stealth for an scout intelligence mission.

### 6.3.17 Rendezvous (15)

Command your fleet to travel to a designated system and await further commands. Coordinate multi-fleet operations by designating rendezvous points. Multiple fleets with Rendezvous commands to the same system automatically merge when they arrive, with all forces consolidating into the fleet with the lowest ID.

**Use Rendezvous to:**
- Coordinate multi-fleet invasions.
- Establish staging areas for offensives.
- Organize defensive concentrations.
- Consolidate multiple Scout fleets at a staging point before an scout intelligence mission.

### 6.3.18 Salvage (16)

Disband your own fleet at a friendly colony to recover production points. Your fleet travels to the nearest friendly colony with spaceport or shipyard facilities, where ships are decommissioned and scrapped for materials.

**Requirements:**
- Fleet must travel to friendly colony with spaceport or shipyard
- Fleet survives travel (vulnerable to interception)

**Recovery:**
- **50% PP recovery**: Receive half the original build cost of all ships in the fleet
- Ships are permanently removed from the game
- PP added to house treasury during Income Phase (INC5)

**Use Salvage to:**
- Recover value from obsolete or damaged ships
- Free up ship capacity limits
- Convert excess military assets back to economic resources
- Scrap crippled ships that aren't worth repairing

### 6.3.19 Reserve (17)

Instantly places a fleet into **Reserve** status during the Command Phase.

**Reserve Status Effects:**
- **CC Cost**: Reduced to 50% of base.
- **Maintenance Cost**: Reduced to 50% of base.
- **Combat Effectiveness**: Ships fight at 50% AS (Crippled state).
- **Command Assignment**: Automatically assigned **Blockade (06)** command to participate in orbital defense.
- **Mobility**: Immobile. Cannot execute movement commands.
- **Requirements**: Fleet must be at a friendly starbase or shipyard.

**Use Reserve Status to:**
- Reduce C2/Maintenance costs while maintaining a credible defensive deterrent.
- Garrison colonies with lower-readiness forces.

### 6.3.20 Mothball (18)

Instantly places a fleet into **Mothballed** status during the Command Phase.

**Mothball Status Effects:**
- **CC Cost**: Reduced to 0 (free).
- **Maintenance Cost**: Reduced to 10% of base (skeleton crews).
- **Combat Effectiveness**: None. Ships are offline and defenseless.
- **Defense**: Must be screened by active/reserve fleets or starbases. Vulnerable to destruction if defenders lost.
- **Mobility**: Immobile.
- **Requirements**: Fleet must be at a friendly starbase or shipyard.

**Use Mothball to:**
- Store valuable ships at minimal cost during peacetime.
- Preserve hull assets for future mobilization (requires Reactivate command).

### 6.3.21 Reactivate (19)

Issues an order to reactivate a fleet from Reserve or Mothballed status, returning it to full operational readiness.

**Reactivation Effects:**
- **From Reserve**: Takes **1 full turn**. After completion, fleet is Active.
- **From Mothball**: Takes **3 full turns**. After completion, fleet is Active.
- Upon reactivation, the fleet returns to 100% CC and 100% Maintenance Cost.
- The fleet can once again move, fight, and receive auto-assigned ships.

**Use Reactivate to:**
- Mobilize reserves in response to a threat.
- Bring stored fleets back into service for a major offensive.

### 6.3.22 View (20)

Send a fleet to perform long-range reconnaissance on a planet from the edge of a solar system. This is a primary, non-consumable mission for Scouts, allowing them to gather basic intelligence without being detected or destroyed.

**Intelligence Gathered:**
- **Planet Owner**: Which house controls the colony (if colonized).
- **Planet Class**: Production potential (Hostile, Benign, Lush, etc.).
- **Strategic Value**: Assess colonization priority for ETACs.

**Tactical Advantages:**
- **Safe Reconnaissance**: The fleet remains at the edge of the system, avoiding detection and combat.
- **Any Ship Type**: While ideal for Scouts, any ship can perform this action.
- **Early Intelligence**: Identify valuable targets before committing ETACs or Scouts.
- **Diplomatic Safety**: Not a hostile act; safe for gathering intel on neutrals.

**Use View a World to:**
- Explore the map safely with Scouts in the early game.
- Identify high-value planets (Eden, Lush) for priority colonization.
- Gather basic intelligence on enemy territory before committing to a risky scout intelligence mission.

---

## 6.4 Zero-Turn Administrative Commands

Reorganize your forces instantly during command submission. Zero-turn administrative commands execute immediately—before turn resolution begins—enabling you to prepare forces precisely for the upcoming turn without consuming time.

### 6.4.1 Concept: Administrative vs Operational Commands

**Administrative Commands (0 turns):**
- Fleet reorganization (detach ships, transfer ships, merge fleets)
- Cargo operations (load/unload troops and colonists)
- Ship status changes (Reserve/Mothball)
- Execute **immediately** during command submission
- No turn cost—prepare forces and execute strategy in the same turn

**Operational Commands (1+ turns):**
- Fleet movement, combat, espionage, colonization
- Execute during turn resolution
- Consume turns based on action complexity

**Key Benefit:** Combine multiple administrative commands with operational commands in a single turn. Load troops, reorganize fleets, and launch invasions—all in one coordinated action.

### 6.4.2 Fleet Reorganization Commands

Reconfigure your fleet composition at friendly colonies without consuming turns.

**Requirements:**
- Fleet must be at **friendly colony** (own colony under your control)
- Colony cannot be under siege or blockade
- All ships involved must be owned by your house

#### DetachShips

Extract specific ships from a fleet into a new fleet.

**Use cases:**
- Split battle fleet into multiple patrol groups
- Detach damaged ships for repair while healthy ships continue operations
- Create specialized task forces from general-purpose fleets
- Separate auxiliary ships (ETACs, Troop Transports) from combat ships

**Mechanics:**
- Select ships by index from fleet's total ship roster
- New fleet created automatically with selected ships
- Source fleet retains unselected ships
- If all ships detached, source fleet deleted and commands cleared

**Example:** Battle fleet at home system with 3 capitals + 5 destroyers. Detach 1 capital + 2 destroyers → creates new patrol fleet while main battle fleet continues with remaining forces.

#### TransferShips

Move ships between two existing fleets.

**Use cases:**
- Reinforce weakened patrol fleet from reserve fleet
- Consolidate scattered forces before major offensive
- Balance fleet compositions for optimal combat effectiveness
- Transfer specialized assets (scouts, ETACs) between task forces

**Mechanics:**
- Both fleets must be at same friendly colony
- Select ships from source fleet to transfer to target fleet
- If source fleet emptied, automatically deleted

**Example:** Patrol fleet returns damaged (2 ships). Transfer 3 fresh ships from reserve fleet → patrol fleet reinforced and ready for immediate redeployment.

#### MergeFleets

Combine two fleets into a single unified force.

**Use cases:**
- Consolidate multiple small fleets into battle group
- Merge returning damaged fleet with fresh reinforcements
- Combine specialized fleets for joint operations
- Simplify fleet management by reducing total fleet count

**Mechanics:**
- Source fleet merges entirely into target fleet
- All ships transfer to target
- Source fleet deleted after merge
- Target fleet retains its commands
- Fleet composition limits still apply

**Example:** 3 cruiser fleets return to home system. Merge all into single battle fleet → one unified command, simplified management, ready for coordinated offensive.

### 6.4.3 Cargo Operations

Load and unload Marines and colonists instantly during order submission.

**Requirements:**
- Fleet at friendly colony
- Compatible ships in fleet (Troop Transports for marines, ETACs for colonists)
- Cargo available at colony (marines from garrison, colonists from population)

#### LoadCargo

Load marines or colonists from colony onto fleet auxiliary ships.

**Use cases:**
- Load invasion forces immediately before launching offensive
- Embark colonists for same-turn colonization mission
- Prepare garrison reinforcements for allied colonies

**Mechanics:**
- **Marines**: Loaded onto Troop Transports from colony garrison
- **Colonists**: Loaded onto ETACs from colony population (souls-based accounting)
- Respects ship cargo capacity limits
- Skips crippled ships (cannot carry cargo while damaged)
- Colony retains minimum population threshold (cannot load last colonist)

**Strategic Value:** Load invasion forces and execute Command 07 (Invade) in same turn—immediate operational readiness.

**Example:** Prepare invasion of enemy colony. Load 10 marine divisions onto 5 Troop Transports, attach escorts, issue Command 07 (Invade target system) → invasion launches immediately. Total: 1 turn.

#### UnloadCargo

Unload marines or colonists from fleet auxiliary ships to colony.

**Use cases:**
- Deliver garrison reinforcements to border colonies
- Evacuate colonists from threatened systems
- Consolidate forces at strategic staging bases

**Mechanics:**
- All cargo on fleet auxiliary ships unloaded to colony
- Marines added to colony garrison
- Colonists added to colony population (souls + population units)
- Instant transfer, no turn cost

**Example:** Evacuate colony threatened by superior enemy fleet. Load colonists, move fleet to safe system, unload colonists → population preserved, enemy gains empty colony.

### 6.4.4 Workflow: Prepare Forces → Execute Strategy

Execute complex operations in a single turn by combining zero-turn commands with operational commands.

**Example: Invasion Operation**

Turn N submission:
1. **LoadCargo** marines onto transports (0 turns)
2. **Command 07: Invade Planet** (1 turn for transit + combat)

Turn N resolution: Fleet moves and invades. Total: 1 turn.

**Example: Major Offensive**

Launching 3-fleet offensive. Turn submission:

1. **MergeFleets** - Combine cruiser fleets into battle group
2. **DetachShips** - Split off scouts for recon
3. **LoadCargo** - Load 15 marine divisions
4. **Issue Commands**:
   - Battle fleet: Command 07 (Invade)
   - Scout fleet: Command 11 (Scout System)

All preparation complete, offensive launches immediately. Total: 1 turn.

### 6.4.5 Limitations and Restrictions

**Location Requirements:**
- Fleet operations require friendly colony presence
- Cannot reorganize fleets in deep space or at enemy systems
- Cannot load cargo at neutral systems

**Combat Restrictions:**
- No zero-turn commands during active combat
- Cannot reorganize while under siege or blockade
- Damaged ships (crippled) cannot load cargo

**Command Precedence:**
- Zero-turn commands execute before operational commands
- Administrative commands processed in submission order
- Auto-assignment runs after manual ship assignments

**Validation:**
- All commands validated before execution
- Failed commands return error immediately (no partial execution)
- State changes atomic (all-or-nothing per command)

---

## 6.5 Ship Repairs and Repair Queues

Damaged ships require drydock facilities for repairs. Manage your repair priorities through explicit repair commands or automated repair queues. Drydocks are specialized repair-only facilities separate from construction infrastructure.

### 6.5.1 Damage and Repair Mechanics

**Ships accumulate damage during combat**: Hull damage, system damage, and critical hits degrade combat effectiveness. Heavily damaged ships risk destruction.

**Drydocks conduct repairs**: Colonies with drydock facilities repair damaged ships. Repair speed depends on drydock capacity and damage severity.

**Repairs are separate from construction**: Drydock capacity is dedicated to repairs only. Shipyard construction operations do not interfere with repair operations.

### 6.5.2 Repair Queues

**Automatic repair prioritization**: Your drydocks automatically queue damaged ships for repair. Ships with critical damage receive priority; light damage repairs later.

**Manual queue adjustment**: Override automatic prioritization by explicitly ordering specific ships to front of queue. Prioritize capital ships or critical escorts.

**Repair time**: All ship repairs complete in 1 turn at 25% of original build cost. Monitor repair progress in colony management screens.

### 6.5.3 Repair Strategy

**Dedicated repair colonies**: Establish rear-area colonies with extensive drydock capacity for major repairs. Damaged fleets return to repair bases.

**Forward repair facilities**: Build drydocks at frontline colonies for rapid turnaround. Maintain fleet readiness near combat zones.

**Emergency repairs**: Lightly damaged ships remain operational. Save drydock capacity for critically damaged units requiring immediate attention.

---

**End of Section 6**
