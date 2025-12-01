# 6.0 Fleet Operations and Movement

Command your fleets across the stars. Direct them with explicit orders for immediate missions or standing orders for persistent behaviors. Your strategic decisions at the fleet level drive military success—squadrons handle the tactical execution.

This section covers jump lane travel, ship commissioning pipelines, fleet orders, standing orders, and repair operations. Master these systems to project power effectively across your empire.

---

## 6.1 Jump Lanes

Your fleets travel between star systems via **jump lanes**—pre-calculated routes through hyperspace connecting adjacent systems. Jump lanes define your strategic map: systems without lanes remain unreachable, while densely connected systems become strategic crossroads.

For complete details on jump lane classes, distribution, and the starmap structure, see [Section 2.1 Star Map](assets.md#21-star-map).

### 6.1.2 Jump Lane Movement Rules

**Movement capacity depends on lane control and lane class:**

- **Controlled major lanes**: If you own all systems along the travel path, your fleets can jump two major lanes in one turn
- **Minor and restricted lanes**: Enable a single jump per turn, regardless of the destination
- **Unexplored or rival systems**: Limit movement to one jump maximum
- **Lane restrictions**: Fleets containing crippled ships or Spacelift Command ships cannot traverse restricted lanes

### 6.1.3 Strategic Implications

**Chokepoints control empires**: Systems with few connecting lanes become natural defensive positions. Control the chokepoint and you control the region.

**Connectivity determines value**: Well-connected systems with major lanes serve as staging areas and logistics hubs. Isolated systems connected only by restricted lanes require specialized defense forces without ETACs or damaged ships.

**Patrol routes follow lanes**: Standing patrol orders automatically follow jump lane networks. Your fleets defend multiple systems using established lanes.

**Lane class matters for expansion**: Restricted lanes prevent ETAC passage, creating natural expansion barriers. Plan colonization routes around major and minor lanes for reliable access.

---

## 6.2 Ship Commissioning and Fleet Organization

Your industrial might produces warships and spacelift vessels. Ships move from treasury expenditure through construction yards to commissioned squadrons and finally into operational fleets. This four-stage pipeline transforms economic investment into military power.

### 6.2.1 The Commissioning Pipeline

**Stage One: Build Orders**

Allocate treasury (production points) to construction projects at your colonies. Each project requires available dock capacity at either spaceports or shipyards:

**Spaceports** (Planet-side Construction):
- Built in 1 turn, provides 5 construction docks
- Can build any ship type
- **100% commission penalty**: Ships (except fighters) cost double production points due to orbital launch costs
- Fighter squadrons exempt from penalty (distributed planetary manufacturing)
- Required prerequisite for building shipyards

**Shipyards** (Orbital Construction):
- Built in 2 turns, requires existing spaceport, provides 10 construction docks
- Can build any ship type at standard cost (no penalty)
- **ONLY facility that can repair ships** - spaceports cannot repair
- Repairs any ship class at 25% of build cost (1 turn)
- Also repairs starbases
- Economically superior for all non-fighter construction

**Ship Repair Requirements:**
- **All ship repairs require shipyards** - spaceports cannot repair ships
- Repair cost: 25% of build cost
- Repair time: 1 turn for all ship classes
- Starbase repairs also require shipyards
- Colonies without shipyards cannot repair crippled ships (must salvage or transfer to shipyard colony)

**Build Order Mechanics:**
- **Upfront payment**: Full construction cost (including spaceport penalties) deducted immediately from treasury
- **Construction time**: 1+ turns based on ship class and technology level
- **Simultaneous projects**: Limited only by available dock capacity across all facilities

**Strategic Priority:** Build shipyards early at all major colonies. The 100% spaceport penalty makes planet-side construction economically devastating for anything except fighters. Plan ahead—commit resources turn X, receive operational ships turn X+N.

**Stage Two: Construction Completion**

When construction completes, your ships **immediately commission** into squadrons:
- **Capital ships** (BB, DN, SD, CA, CL) create new squadrons as flagships
- **Escorts** (DD, FF, CT) join existing unassigned capital squadrons based on command capacity
- **Scouts and fighters** form single-ship squadrons for specialized missions
- **Spacelift ships** enter the unassigned pool, ready for colonization or transport missions

No intermediate "ready to commission" state—your ships transition directly from construction to operational status, just like vessels completing sea trials immediately join the active fleet.

**Stage Three: Fleet Assignment**

Squadrons automatically join fleets at their construction colony, eliminating tactical micromanagement while keeping your forces operationally ready. Your newly-commissioned squadrons organize into existing stationary fleets or form new fleets automatically.

**Stationary fleets receive reinforcements:**
- Fleets with **Hold, Guard, or Patrol** orders (at same system)
- Fleets with **defensive standing orders** (DefendSystem, GuardColony, AutoEvade)
- Fleets with **no orders** (default stationary posture)

**Moving fleets do not receive reinforcements:**
- Fleets executing **movement orders** or on patrol routes
- Fleets with **movement-based standing orders** (PatrolRoute, AutoColonize, AutoRepair)
- **Reserve or Mothballed** fleets (intentional reduced-readiness status)

This system ensures squadrons join fleets **intentionally stationary** at your colony, not temporarily passing through. Your fleets maintain operational readiness without interrupting ongoing missions.

**Why automatic assignment?** Squadrons are **tactical assets for combat**, not strategic decision points. You command at the fleet level—issuing orders, setting patrol routes, managing fleet composition. Automatic assignment eliminates the micromanagement trap of forgetting to deploy newly-built units while preserving your strategic control through fleet orders and standing orders.

**Stage Four: Fleet Operations**

Once in fleets, control your forces through **fleet orders** (one-time missions) and **standing orders** (persistent behaviors). Transfer squadrons between fleets, adjust compositions, or place fleets in Reserve/Mothballed status to control operational costs.

### 6.2.2 Squadron Formation Rules

Your ships organize into squadrons based on command structure:

**Capital ships become flagships**: Battleships, Dreadnoughts, Super Dreadnoughts, Heavy Cruisers, and Light Cruisers create new squadrons. Each capital ship commands its own squadron.

**Escorts serve as wingmen**: Destroyers, Frigates, and Corvettes join capital squadrons based on the flagship's command capacity. A Battleship commands more escorts than a Light Cruiser.

**Scouts operate independently**: Scout ships form single-ship squadrons for reconnaissance missions, intelligence gathering, and espionage operations.

**Fighters defend colonies**: Fighter squadrons remain assigned to colonies for orbital defense, separate from fleet operations.

### 6.2.3 Fleet Composition Strategy

Design your fleets for their mission profile:

**Battle fleets** combine capital ships with escort screens. Your Dreadnoughts and Battleships provide firepower; Destroyers and Frigates screen against threats.

**Patrol fleets** use Light Cruisers with Destroyer escorts for patrol routes and border security. Balance firepower with operational cost.

**Scout fleets** deploy single-scout squadrons for intelligence gathering, system reconnaissance, and espionage missions. Small footprint, high stealth.

**Reserve fleets** store mothballed squadrons at major colonies for emergency mobilization. Zero maintenance cost, immediate reactivation when needed.

---

## 6.3 Fleet Orders

Command your fleets with 19 distinct mission types—from peaceful exploration to devastating orbital bombardment. Issue orders once; your fleets execute them persistently across turns until mission completion or your new orders override them.

### 6.3.1 Active Fleet Orders

Explicit orders that execute until completed or overridden:

| No. | Mission                 | Requirements                             |
| --- | ----------------------- | ---------------------------------------- |
| 00  | None (hold position)    | None                                     |
| 01  | Move Fleet (only)       | None                                     |
| 02  | Seek home               | None                                     |
| 03  | Patrol a System         | None                                     |
| 04  | Guard a Starbase        | Combat ship(s)                           |
| 05  | Guard/Blockade a Planet | Combat ship(s)                           |
| 06  | Bombard a Planet        | Combat ship(s)                           |
| 07  | Invade a Planet         | Combat ship(s) & loaded Troop Transports |
| 08  | Blitz a Planet          | Loaded Troop Transports                  |
| 09  | Spy on a Planet         | Scout squadron                           |
| 10  | Hack a Starbase         | Scout squadron                           |
| 11  | Spy on a System         | Scout squadron                           |
| 12  | Colonize a Planet       | One ETAC                                 |
| 13  | Join another Fleet      | None                                     |
| 14  | Rendezvous at System    | None                                     |
| 15  | Salvage                 | Friendly Colony System                   |
| 16  | Place on Reserve        | At friendly colony                       |
| 17  | Mothball Fleet          | At friendly colony with Spaceport        |
| 18  | Reactivate Fleet        | Reserve or Mothballed fleet              |
| 19  | View a World            | Any ship type                            |

### 6.3.2 Hold Position (00)

Command your fleet to hold position and await new orders. Your fleet maintains station at its current location, providing defensive presence or staging position for future operations.

**Use Hold to:**
- Establish defensive positions at strategic locations
- Stage fleets for coordinated offensives
- Maintain presence without specific mission parameters

### 6.3.3 Move Fleet (01)

Move your fleet to a new solar system and hold position. Your fleet travels to the destination system, establishes presence, then awaits further orders. Use Move for strategic repositioning without immediate combat intent.

**Use Move to:**
- Reposition forces to emerging threat sectors
- Establish presence at newly-colonized systems
- Concentrate forces before major offensives

### 6.3.4 Seek Home (02)

Order your fleet to return to the nearest friendly colony with repair facilities. Your damaged forces automatically navigate to safe harbor for repairs and resupply.

**Use Seek Home to:**
- Evacuate damaged fleets from combat zones
- Return forces for strategic redeployment
- Consolidate scattered forces at major bases

### 6.3.5 Patrol a System (03)

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

### 6.3.7 Guard/Blockade Planet (05)

Deploy your fleet for planetary operations—either defending friendly colonies or blockading enemy planets. Your fleet maintains low orbit, participating in orbital combat or economic warfare.

**Use Guard/Blockade to:**
- Defend high-value colonies from bombardment
- Establish orbital blockades cutting enemy production
- Support ground forces during invasion attempts

### 6.3.8 Bombard Planet (06)

Order devastating orbital bombardment of enemy colonies. Your fleet systematically destroys infrastructure, reducing the colony's industrial capacity and effectiveness.

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

### 6.3.9 Invade Planet (07)

Launch ground invasion of enemy colonies. Your fleet deploys marines and army units to seize control, conducting ground combat against defending forces.

**Requirements:**
- Fleet must contain spacelift ships with embarked ground forces
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

### 6.3.10 Blitz Planet (08)

Execute rapid planetary assault combining orbital bombardment with immediate ground invasion. Your forces strike simultaneously, overwhelming defenders before they can coordinate defense.

**Requirements:**
- Loaded troop transports
- Sufficient orbital superiority

**Use Blitz to:**
- Capture lightly-defended colonies rapidly
- Exploit tactical windows before reinforcements arrive
- Reduce siege time for strategic operations

### 6.3.11 Spy on Planet (09)

Deploy intelligence operatives to gather colony-level intelligence. Your scout ships conduct covert reconnaissance, gathering data on infrastructure, defenses, and economic output.

**Requirements:**
- Fleet must contain single-ship squadrons (multi-ship squadrons too conspicuous)
- Scout ships preferred (stealth capabilities)

**Intelligence Gathered:**
- Colony infrastructure level
- Industrial capacity
- Military facilities (spaceports, shipyards)
- Defensive installations (shields, batteries)
- Economic output

**Use Spy on Planet to:**
- Assess target defenses before invasion
- Track enemy economic development
- Identify strategic targets for strikes

### 6.3.12 Hack Starbase (10)

Conduct cyber warfare operations against enemy starbases. Your intelligence units penetrate starbase networks, extracting economic data, research information, and operational intelligence.

**Requirements:**
- Fleet must contain single-ship squadrons
- Target system must have enemy starbase

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

### 6.3.13 Spy on System (11)

Deploy surveillance operations to detect hostile fleet movements. Your scout ships monitor jump lane traffic, track enemy fleet positions, and provide early warning of invasions.

**Intelligence Gathered:**
- All fleets present in system
- Fleet compositions
- Fleet orders (if detectable)
- Recent fleet movements

**Use Spy on System to:**
- Provide early warning of enemy attacks
- Track hostile fleet movements
- Identify enemy patrol patterns
- Support strategic planning

### 6.3.14 Colonize Planet (12)

Order ETACs (Enhanced Terrestrial Administrative Carriers) with Population Transfer Units to establish new colonies. Your fleet travels to the target system, deploys the PTUs, and establishes colonial infrastructure.

**Requirements:**
- Fleet must contain at least one ETAC ship
- ETAC must carry PTUs (Population Transfer Units)
- Target system cannot already have a colony (one colony per system)

**Results:**
- New colony established at infrastructure Level I
- PTUs consumed (ETAC cargo emptied)
- Awards prestige for expansion
- **ETAC behavior after colonization:**
  - With AutoColonize standing order: Automatically returns home for PTU reload, then resumes colonization
  - Without standing orders: Remains at new colony (requires manual orders)

### 6.3.15 Join Another Fleet (13)

Transfer your fleet to merge with another fleet at the same location. Consolidate forces, reinforce battle groups, or reorganize for strategic operations.

**Use Join Fleet to:**
- Reinforce damaged fleets with fresh squadrons
- Consolidate scattered forces after combat
- Create combined task forces for major operations

### 6.3.16 Rendezvous at System (14)

Order your fleet to travel to a designated system and await further instructions. Coordinate multi-fleet operations by designating rendezvous points.

**Use Rendezvous to:**
- Coordinate multi-fleet invasions
- Establish staging areas for offensives
- Organize defensive concentrations

### 6.3.17 Salvage (15)

Recover resources from destroyed ships and derelict facilities in friendly systems. Your fleet conducts salvage operations, recovering production points from battle debris.

**Requirements:**
- Must be at friendly colony system
- Recent battle debris present

**Use Salvage to:**
- Recover resources after defensive battles
- Maximize economic efficiency
- Clean up post-battle debris

### 6.3.18 Place on Reserve (16)

Place your fleet in Reserve status—reduced readiness with lower maintenance costs. Reserve fleets remain stationed at their colony with 50% maintenance cost and reduced combat effectiveness.

**Reserve Status Effects:**
- Maintenance cost reduced to 50%
- Combat effectiveness reduced (penalty TBD)
- **Cannot move** (permanently stationed at colony)
- Does NOT receive auto-assigned squadrons
- Can issue Reactivate order to return to Active status

**Use Reserve Status to:**
- Reduce military budget during peacetime
- Maintain defensive reserves at major colonies
- Store second-line forces for emergency mobilization

### 6.3.19 Mothball Fleet (17)

Mothball your fleet for long-term storage—zero maintenance cost but defenseless. Mothballed fleets remain at their colony with no maintenance cost and cannot participate in combat.

**Mothball Status Effects:**
- Maintenance cost reduced to 0%
- **Cannot fight** - defenseless if attacked
- **Cannot move** (permanently stationed at colony)
- Does NOT receive auto-assigned squadrons
- Must be screened by Active fleets during orbital combat or risks destruction
- Can issue Reactivate order to return to Active status

**Use Mothball to:**
- Store reserve forces during peacetime
- Preserve ships for future conflicts
- Maintain strategic reserve with minimal budget impact
- **WARNING**: Mothballed fleets MUST be screened during combat

### 6.3.20 Reactivate Fleet (18)

Reactivate Reserve or Mothballed fleets to Active status. Your fleet returns to full operational readiness with 100% maintenance cost and combat effectiveness.

**Reactivation Effects:**
- Fleet status changes from Reserve/Mothballed to Active
- Full maintenance cost resumes
- Full combat effectiveness restored
- Fleet can now move and execute all orders
- Receives auto-assigned squadrons if stationary

**Use Reactivate to:**
- Mobilize reserves during wartime
- Respond to emerging threats
- Return mothballed fleets to operational status

### 6.3.21 View a World (19)

Send a fleet to perform long-range planetary reconnaissance from the edge of a solar system. Your ship approaches the system edge, conducts a long-range scan of the planet, then backs off into deep space—gathering intelligence without orbital approach or detection risk.

**Intelligence Gathered:**
- **Planet Owner**: Which house controls the colony (if colonized)
- **Planet Class**: Production potential (Barren, Arid, Terran, etc.)
- **Strategic Value**: Assess colonization priority for ETACs

**Tactical Advantages:**
- **Deep Space Approach**: Ship remains in deep space, avoiding orbital combat
- **Any Ship Type**: No specialized equipment required
- **Early Intelligence**: Identify valuable targets before committing ETACs
- **Diplomatic Safety**: No hostile act, safe for gathering intel on neutrals

**Use View a World to:**
- Scout uncolonized systems before ETAC deployment
- Identify high-value planets (Terran, Ocean) for priority colonization
- Map enemy territory and production capacity
- Gather intelligence on neutral/hostile colonies without triggering combat

**Early Game Strategy:**
- Act 1 AI sends combat fleets to View uncolonized systems
- Intelligence informs ETAC targeting decisions
- Enables "land grab" strategy based on planet quality
- Allows bumping into other houses for diplomatic contact

---

## 6.4 Standing Orders

Establish persistent fleet behaviors that execute automatically when no explicit order is given. Standing orders reduce micromanagement by codifying routine behaviors—your fleets patrol routes, defend systems, and reinforce damaged units without constant supervision.

### 6.4.1 Standing Order Types

Persistent behaviors that execute when fleet has no active mission:

| Type             | Purpose                                      | Movement |
| ---------------- | -------------------------------------------- | -------- |
| None             | No standing order (default)                  | No       |
| PatrolRoute      | Follow patrol path indefinitely              | Yes      |
| DefendSystem     | Guard system, engage hostiles per ROE        | No       |
| GuardColony      | Defend specific colony                       | No       |
| AutoColonize     | ETACs auto-colonize nearest suitable system  | Yes      |
| AutoReinforce    | Join nearest damaged friendly fleet          | Yes      |
| AutoRepair       | Return to shipyard when crippled             | Yes      |
| AutoEvade        | Retreat if outnumbered per ROE               | Yes      |
| BlockadeTarget   | Maintain blockade on enemy colony            | No       |

### 6.4.2 Standing Order Execution

**Standing orders are persistent**: Once assigned, your fleet executes the standing order every turn unless you issue an explicit order.

**Explicit orders override temporarily**: Issue a one-time order to interrupt standing order behavior. Your fleet executes the explicit order this turn, then automatically resumes its standing order next turn.

**Standing orders support Rules of Engagement**: Most defensive standing orders respect your ROE settings, determining when to fight and when to retreat.

### 6.4.3 Patrol Route Standing Order

Establish indefinite patrol routes through multiple systems. Your fleet automatically travels the route system-by-system, engaging hostiles per ROE, providing continuous defensive coverage.

**Configuration:**
- Define patrol path: ordered list of systems
- Set Rules of Engagement (0-10 scale)
- Fleet automatically cycles through route

**Behavior:**
- Fleet travels to next system in route
- Engages hostiles per ROE
- Continues to next system
- Cycles back to start when route completes

**Use Patrol Route to:**
- Defend border regions spanning multiple systems
- Maintain continuous presence in contested zones
- Automate routine security operations

### 6.4.4 Defend System Standing Order

Station your fleet for permanent system defense. Your fleet remains at the system, engages hostiles per ROE, and protects colonies without requiring repeated orders.

**Configuration:**
- Target system (usually current location)
- Rules of Engagement (0-10 scale)

**Behavior:**
- Fleet remains at target system
- Engages hostile fleets per ROE
- Protects colonies and starbases
- Automatically screens mothballed fleets during combat

**Use Defend System to:**
- Create permanent defensive garrisons
- Protect strategic colonies
- Maintain defensive presence without micromanagement

### 6.4.5 Guard Colony Standing Order

Defend a specific colony within a system. Functionally identical to Defend System but explicitly designates which colony to prioritize during combat.

**Use Guard Colony to:**
- Prioritize specific colony defense in multi-colony systems
- Designate which infrastructure to protect
- Create colony-specific defensive postures

### 6.4.6 Auto-Colonize Standing Order

Order ETAC fleets to autonomously identify and colonize nearest suitable systems. Your colonization fleets automatically expand your empire without explicit orders for each colony.

**Requirements:**
- Fleet must contain ETACs with PTUs

**Behavior:**
- Fleet identifies nearest uncolonized system
- Travels to system automatically
- Establishes colony
- Resumes search for next target

**Use Auto-Colonize to:**
- Automate expansion waves
- Reduce colonization micromanagement
- Ensure rapid territory acquisition during land grabs

### 6.4.7 Auto-Reinforce Standing Order

Order your fleet to automatically reinforce the nearest damaged friendly fleet. Your fleet identifies allies in need, travels to their location, and transfers squadrons to restore combat effectiveness.

**Behavior:**
- Fleet scans for damaged friendly fleets
- Calculates nearest target
- Travels to target location
- Transfers squadrons as appropriate
- Resumes scanning for next target

**Use Auto-Reinforce to:**
- Maintain frontline fleet strength
- Automate battle damage replacement
- Create mobile reinforcement fleets

### 6.4.8 Auto-Repair Standing Order

Order damaged fleets to automatically return to shipyards when crippled. Your fleet recognizes critical damage, calculates nearest repair facility, and travels there automatically.

**Behavior:**
- Fleet monitors squadron damage status
- When crippled (threshold TBD), seeks repair
- Identifies nearest colony with shipyard
- Travels to repair facility
- Conducts repairs
- Resumes previous standing order or awaits orders

**Use Auto-Repair to:**
- Preserve damaged units
- Reduce fleet management micromanagement
- Ensure damaged forces return to operational status

### 6.4.9 Auto-Evade Standing Order

Order your fleet to automatically retreat when outnumbered per ROE settings. Your fleet continuously assesses threat levels and withdraws to safety when engagement becomes unfavorable.

**Configuration:**
- Rules of Engagement (0-10 scale) determines retreat threshold

**Behavior:**
- Fleet monitors hostile forces in system
- Calculates force ratio
- If outmatched per ROE, retreats to safe system
- Resumes mission when threat clears

**Use Auto-Evade to:**
- Protect valuable scouts and intelligence units
- Preserve outnumbered forces
- Avoid unfavorable engagements

### 6.4.10 Blockade Target Standing Order

Maintain continuous blockade of enemy colony. Your fleet establishes orbital blockade and maintains it indefinitely, strangling enemy economy.

**Configuration:**
- Target colony system
- Rules of Engagement (determines when to fight defending fleets)

**Behavior:**
- Fleet travels to target system if not present
- Establishes orbital blockade
- Engages defending forces per ROE
- Maintains blockade continuously

**Use Blockade Target to:**
- Maintain long-term economic pressure
- Weaken enemy colonies before invasion
- Automate blockade operations

### 6.4.11 Rules of Engagement (ROE)

Configure standing order combat behavior with Rules of Engagement—a 0-10 scale determining when to fight and when to retreat.

| ROE  | Behavior                                        |
| ---- | ----------------------------------------------- |
| 0-2  | Extremely cautious - Retreat from any threat    |
| 3-5  | Defensive - Fight only if superior              |
| 6-8  | Aggressive - Fight unless clearly outnumbered   |
| 9-10 | Suicidal - Fight to the death                   |

**Examples:**
- **Patrol Route with ROE=2**: Fleet patrols border but retreats from any hostile contact
- **Defend System with ROE=8**: Fleet defends aggressively, fighting unless outnumbered 4:1
- **Auto-Evade with ROE=5**: Fleet retreats if enemy force equal or superior

---

## 6.5 Ship Repairs and Repair Queues

Damaged ships require shipyard facilities for repairs. Manage your repair priorities through explicit repair orders or automated repair queues. Balance repair capacity against construction demands to maintain fleet readiness.

### 6.5.1 Damage and Repair Mechanics

**Ships accumulate damage during combat**: Hull damage, system damage, and critical hits degrade combat effectiveness. Heavily damaged ships risk destruction.

**Shipyards conduct repairs**: Colonies with shipyard facilities repair damaged ships. Repair speed depends on shipyard capacity and damage severity.

**Repairs compete with construction**: Shipyard capacity serves both repair and construction operations. Prioritize based on strategic needs—replace losses or repair existing forces.

### 6.5.2 Repair Queues

**Automatic repair prioritization**: Your shipyards automatically queue damaged ships for repair. Ships with critical damage receive priority; light damage repairs later.

**Manual queue adjustment**: Override automatic prioritization by explicitly ordering specific ships to front of queue. Prioritize capital ships or critical escorts.

**Repair time scales with damage**: Lightly damaged ships repair quickly; heavily damaged ships require multiple turns. Monitor repair progress in colony management screens.

### 6.5.3 Repair Strategy

**Dedicated repair colonies**: Establish rear-area colonies with extensive shipyard capacity for major repairs. Damaged fleets return to repair bases.

**Forward repair facilities**: Build shipyards at frontline colonies for rapid turnaround. Maintain fleet readiness near combat zones.

**Emergency repairs**: Lightly damaged ships remain operational. Save shipyard capacity for critically damaged units requiring immediate attention.

**Auto-Repair standing orders**: Configure damaged fleets to automatically return to designated repair facilities when crippled. Reduces micromanagement of battle-damaged forces.

---

**End of Section 6**

# 7.0 Combat

Destroy your enemies across three distinct combat theaters. Your fleets fight through space battles, orbital sieges, and planetary invasions to seize enemy colonies. Each theater demands different tactics, unit compositions, and strategic decisions.

This section covers combat mechanics, engagement rules, and the progressive nature of planetary conquest. Master these systems to project power effectively and defend your empire against invasion.

---

## 7.1 The Three Combat Theaters

Planetary conquest requires methodical progression through three combat phases. Your attacking fleets must win each theater before advancing to the next—no shortcuts, no bypassing defenses.

### 7.1.1 Theater Progression

**Space Combat** (First Theater)

Fight enemy mobile fleets in deep space before reaching orbit. Your task forces engage defending fleets with full tactical mobility. Both sides maneuver, concentrate fire, and attempt to break enemy formations.

**Who fights:**
- Your attacking fleets
- Enemy mobile defenders (fleets with no Guard orders, active movement orders)
- Undetected Raiders can ambush with combat bonuses

**Outcome determines:**
- If attackers win: Proceed to orbital combat
- If defenders win: Attackers retreat or are destroyed
- If no mobile defenders present: Attackers proceed directly to orbital combat

**Orbital Combat** (Second Theater)

Assault fortified orbital defenses after achieving space superiority. Your fleets engage stationary defenders protecting the planet—guard fleets, reserve forces, starbases, and unassigned squadrons fight as a unified defensive position.

**Who fights:**
- Your surviving attack fleets (if you won space combat)
- Enemy guard fleets (fleets with Guard/Defend orders)
- Enemy reserve and mothballed fleets
- Enemy starbases (orbital installations with heavy firepower)
- Enemy unassigned squadrons at colony
- **Screened units protected**: Mothballed ships, spacelift vessels remain behind battle lines

**Outcome determines:**
- If attackers win: Achieve orbital supremacy, proceed to planetary operations
- If defenders win: Attackers retreat without reaching planet surface
- If no orbital defenders: Attackers achieve supremacy unopposed

**Planetary Combat** (Third Theater)

Bombard planetary defenses and invade the surface after securing orbit. Your fleets destroy shields, neutralize ground batteries, and deploy invasion forces. The final phase before colony capture.

**Who fights:**
- Your bombardment fleets (any combat squadrons)
- Your invasion forces (marines from troop transports)
- Enemy planetary shields (reduce bombardment damage)
- Enemy ground batteries (fire on orbiting ships and landing forces)
- Enemy ground forces (armies and marines defend against invasion)

**Outcome determines:**
- Successful bombardment: Infrastructure destroyed, defenses weakened
- Successful invasion: Colony captured, ownership transfers
- Failed invasion: Your invasion forces destroyed, defenders retain control

### 7.1.2 Why Progressive Combat Matters

**No theater skipping**: Your fleets cannot bypass defenses. Guard orders mean enemy fleets defend in orbital combat only—they don't participate in deep space battles. This creates strategic depth: defending admirals choose which fleets defend which theater.

**Resource allocation**: Attackers must maintain overwhelming force through all three phases. Winning space combat with 80% losses means facing orbital defenses with a crippled fleet. Plan for attrition.

**Defender advantages**: Each theater provides natural defensive advantages. Starbases add firepower in orbital combat. Planetary shields negate bombardment. Ground batteries threaten invasion forces. Defenders fight from prepared positions.

---

## 7.2 Combat Fundamentals

Every engagement follows consistent rules governing targeting, effectiveness, and resolution. Master these fundamentals to predict combat outcomes and design effective fleet compositions.

### 7.2.1 Rules of Engagement (ROE)

Set your fleet's aggression level with Rules of Engagement—a 0-10 scale determining when to retreat during combat. ROE compares your total AS to enemy total AS.

**ROE Retreat Thresholds:**

| ROE | Threshold | Meaning | Use Case |
|-----|-----------|---------|----------|
| 0 | 0.0 | Avoid all hostile forces | Pure scouts, intel gathering |
| 1 | 999.0 | Engage only defenseless | Extreme caution |
| 2 | 4.0 | Need 4:1 advantage | Scout fleets, recon forces |
| 3 | 3.0 | Need 3:1 advantage | Cautious patrols |
| 4 | 2.0 | Need 2:1 advantage | Conservative operations |
| 5 | 1.5 | Need 3:2 advantage | Defensive posture |
| 6 | 1.0 | Fight if equal or superior | Standard combat fleets |
| 7 | 0.67 | Fight even at 2:3 disadvantage | Aggressive fleets |
| 8 | 0.5 | Fight even at 1:2 disadvantage | Battle fleets |
| 9 | 0.33 | Fight even at 1:3 disadvantage | Desperate defense |
| 10 | 0.0 | Fight regardless of odds | Suicidal last stands, homeworld defense |

**Morale Modifies Effective ROE:**

Your house's prestige affects fleet morale, modifying effective ROE during combat:

| Prestige | Morale Modifier | Effect on ROE |
|----------|-----------------|---------------|
| 0 or less | -2 | Fleets retreat much earlier (ROE 8 becomes ROE 6) |
| 1-20 | -1 | Fleets retreat earlier (ROE 8 becomes ROE 7) |
| 21-60 | 0 | No change |
| 61-80 | +1 | Fleets fight longer (ROE 6 becomes ROE 7) |
| 81+ | +2 | Fleets fight much longer (ROE 6 becomes ROE 8) |

**Homeworld Defense Exception**: Fleets defending their homeworld NEVER retreat regardless of ROE or losses.

**ROE affects standing orders**: PatrolRoute with ROE=2 patrols but retreats unless 4:1 advantage. DefendSystem with ROE=8 fights even at 1:2 disadvantage.

**ROE does NOT affect explicit orders**: When you issue Bombard, Invade, or Attack orders, your fleet executes regardless of ROE. ROE only matters for automated retreat decisions during combat.

### 7.2.2 Combat State and Damage

Squadrons exist in three combat states determining effectiveness:

**Undamaged** (Full Effectiveness)
- Squadron operates at full Attack Strength (AS) and Defense Strength (DS)
- Contributes full combat power to task force
- Can execute all missions

**Crippled** (Severely Degraded)
- Squadron suffers major damage reducing combat effectiveness
- Squadron flagship is crippled; escort ships may be destroyed
- Cannot traverse restricted jump lanes
- Requires shipyard repairs (1 turn, 25% of flagship build cost)
- Still operational but at reduced capability

**Destroyed** (Eliminated)
- Squadron eliminated from combat
- Flagship and all escort ships destroyed
- Provides salvage value (50% of build cost at friendly colony)
- Permanent loss unless rebuilt

**Damage accumulation**: Squadrons take damage during combat rounds. Sufficient damage cripples squadrons (flagship crippled, escorts may be lost). Additional damage beyond crippled destroys the entire squadron. Heavy firepower can destroy squadrons directly without crippling them first.

**Destruction Protection:**
- Squadrons cannot go Undamaged → Crippled → Destroyed in the **same combat round**
- If a squadron takes enough damage to cripple AND destroy it in one round, it stays Crippled
- Next round, additional damage can destroy it
- **Critical hits bypass protection**: Natural 9 on CER roll destroys immediately
- Prevents instant-kill cheese, ensures multi-round engagements

**Note**: Combat targets squadrons as tactical units. Each squadron contains one flagship plus escort ships. When a squadron is destroyed, all ships in it are lost.

### 7.2.3 Task Force Formation

Fleets combine into **task forces** during combat—unified battle groups that concentrate firepower and share detection.

**Task force composition**:
- All squadrons from participating fleets
- Starbases at system (orbital combat only)
- Fighter squadrons at colony (if carriers present)
- Unassigned squadrons at colony (orbital combat only)

**Task force benefits**:
- Shared detection: ELI-equipped scouts detect cloaked enemies for entire task force
- Concentrated firepower: All squadrons engage simultaneously
- Screened units protected: Mothballed fleets and spacelift vessels stay behind combat squadrons

**Multiple houses in combat**: Three-way or four-way battles resolve with each house forming separate task forces. All hostile task forces engage each other based on diplomatic status (Enemy or Neutral).

### 7.2.4 Cloaking and Detection

Raiders can cloak, becoming invisible until detected. Detection determines initiative and targeting.

**Cloaking Mechanics:**
- **Raiders** can activate cloaking (stealth mode)
- Cloaked Raiders invisible until detected
- **Detection range**: 1 jump lane (adjacent systems)
- **Detection sources**: ELI-equipped scouts, starbases (orbital combat only)

**Detection is Probabilistic:**
- Detection is NOT automatic—it's a dice roll based on tech levels
- ELI (Electronic Intelligence) tech level vs CLK (Cloaking) tech level
- Multiple scouts improve detection through mesh network bonuses
- See assets.md Section 2.4.2 for full ELI mesh network calculation
- Starbases get +2 ELI bonus for detection

**Ambush Advantage (Space Combat Only):**
- Undetected Raiders strike first
- **+4 Combat Effectiveness Rating (CER)** bonus
- Attacks before enemy capital squadrons can respond
- Ambush advantage ONLY in space combat

**Detection Effects (All Combat):**
- Detected Raiders lose ambush bonus
- Detection shared across entire task force
- Once detected in space combat, remain detected in orbital combat
- Newly encountered Raiders in orbital combat get no ambush bonus (orbital defenses detect approaching threats)

**Strategic Implications:**
- Scout fleets with ELI detect cloaked Raiders, negating ambush
- Raider fleets without ELI opposition devastate unprepared enemies
- Starbases provide detection in orbital combat (can't be surprised at home)

---

## 7.3 Space Combat

Engage enemy mobile fleets in deep space. Your task forces clash with full tactical freedom—the first theater of planetary conquest.

### 7.3.1 Space Combat Participants

**Mobile Fleets Engage When They Meet:**

Space combat occurs when mobile fleets encounter each other in the same system. Combat engagement depends on **diplomatic status**:

**Diplomatic Status Determines Combat:**
- **Enemy Status**: Combat occurs automatically (always hostile)
- **Neutral Status**: Combat occurs if Neutral fleets have **threatening orders** (Invade, Bombard, Blitz, Blockade) in system you control
- **Neutral + Non-Threatening**: No combat (peaceful coexistence)
- **Non-Aggression Pact**: Combat does NOT occur (pact prevents hostilities, even with threatening orders)

**Rules of Engagement (ROE 0-10):**

ROE determines when your fleets **retreat** during combat, not whether combat starts. Set higher ROE for aggressive stands, lower ROE for cautious retreats when outmatched.

**Mobile Fleet Types** (Fight in Space Combat):
- Fleets with **no orders** (default mobile posture)
- Fleets with **Hold orders** (stationary but mobile-capable)
- Fleets with **Patrol orders** (active patrol duty)
- Fleets with **movement-based standing orders** (PatrolRoute, AutoReinforce, AutoRepair)
- Fleets with **offensive mission orders** (Move, Invade, Bombard, Blockade)
- **Active status fleets** without guard-specific orders

**Who Does NOT Fight in Space Combat:**
- **Guard fleets**: GuardStarbase, GuardPlanet, DefendSystem orders - they defend in orbital combat only
- **Reserve fleets**: Stationed at colony, fight in orbital combat only
- **Mothballed fleets**: Offline, screened in orbital combat, cannot fight
- **Starbases**: Fixed installations, orbital combat only

**Multi-Faction Combat:**

When three or more houses have mobile fleets in the same system:
- **Single unified battle** with all houses present
- Each house forms separate task force
- Each squadron targets hostile houses based on diplomatic status
- Enemy status: Always hostile
- Neutral status: Hostile if they have threatening orders in your controlled system
- Non-Aggression Pact: Never hostile
- All combat phases (Raiders, Fighters, Capitals) resolve simultaneously with multi-faction targeting

### 7.3.2 Combat Initiative and Phases

Space combat resolves in three phases determining strike order:

**Phase 1: Undetected Raiders (Ambush)**

Cloaked Raiders without ELI opposition strike first with +4 CER bonus. Devastating alpha strike before enemy responds.

**Conditions:**
- Raiders present in task force
- No enemy ELI-equipped scouts to detect them
- Raiders get ambush bonus (+4 CER)

**Phase 2: Fighter Squadrons (Intercept)**

Carrier-launched fighters engage after Raiders but before capital ships. Fast interceptors screen the main fleet.

**Conditions:**
- Carriers present with loaded fighter squadrons
- Fighters launch and engage enemy formations
- **Fighters do NOT roll CER**—they deal full AS as damage (100% effectiveness always)

**Fighter Tactical Employment:**

Fighters excel as force multipliers and screening units. Use them strategically:

**The Carrier/Fighter Dynamic:**

Carriers and fighters form a symbiotic combat relationship with unique vulnerabilities:

- **Fighters protect carriers**: Fighters engage in Phase 2, eliminating enemy fighters and carriers before your carriers face fire in Phase 3
- **Carriers enable fighters**: Embarked fighters deploy anywhere without colony infrastructure
- **Mutual dependence**: If your carrier dies, all embarked fighters die with it—no survival, no re-embarkment
- **Strategic implication**: Lose your carriers early and your fighters deploy but become stranded; lose your fighters and your carriers become priority targets

**Carrier Strike Groups:**
- Carriers with embarked fighters project power without colony infrastructure
- 5-10 embarked fighters deploy instantly when carrier enters combat
- **Critical**: Protect carriers at all costs—carrier destruction means fighter destruction
- Fighters re-embark after combat (remain carrier-owned)
- Use fighters to screen carriers from enemy fire

**Colony Defense:**
- Planet-based fighters never retreat (fight to the death)
- Ideal for fortress colonies and chokepoints
- Colony fighters + carrier fighters stack for overwhelming local superiority
- Example: 8 colony fighters + 5 carrier fighters = 13 FS in battle

**Fighter vs Fighter Combat:**
- Fighters prioritize enemy fighters first (counter-air mission)
- Winning fighter superiority protects capital squadrons
- Losing fighter superiority exposes your fleet to enemy fighter strikes

**Anti-Carrier Operations:**
- Fighters target carriers (Bucket 2) after enemy fighters eliminated
- Stripping enemy carriers eliminates their fighter advantage
- Concentrate fighters to overwhelm carrier defenses

**Screening Role:**
- Fighters absorb enemy fire before capital squadrons engage
- Low DS means fighters die quickly but buy time
- Sacrificial screening protects high-value battleships and dreadnoughts

**Fighter Fragility:**
- Fighters skip crippled state: Undamaged → Destroyed
- No retreat, no repairs—fighters are expendable
- Replace losses through colony production (requires capacity)

**Phase 3: Capital Squadrons (Main Engagement)**

Battleship, Dreadnought, Cruiser, and Destroyer squadrons exchange fire. The decisive engagement phase.

**Conditions:**
- All capital squadrons and escorts engage
- Standard CER calculations
- Majority of combat damage occurs here

### 7.3.3 Combat Effectiveness Rating (CER)

CER determines strike effectiveness—how much damage your squadrons inflict. Each attacking squadron rolls for CER independently.

**CER Calculation Process:**

1. **Roll 1d10** (result 0-9, treat 10 as 0)
2. **Add modifiers**:
   - Scouts in task force: +1
   - Morale modifier (see table below): -1 to +2
   - Surprise (first round only): +3
   - Ambush (Raiders, space combat, first round): +4
3. **Look up effectiveness multiplier**:

**Morale Check CER Bonuses:**

At the start of each turn, roll 1d20 to determine morale effects for that turn:

| Morale Level | Morale Threshold | Effect on Success |
|:-------------|:----------------:|:------------------|
| Collapsing   | Never succeeds   | -1 to all CER rolls this turn |
| VeryLow      | > 18             | No effect |
| Low          | > 15             | +1 to CER for one random squadron |
| Normal       | > 12             | +1 to all CER rolls this turn |
| High         | > 9              | +1 CER + one critical auto-succeeds |
| VeryHigh/Exceptional | > 6      | +2 to all CER rolls this turn |

*Note: Morale levels and thresholds defined by house prestige—see reference.md for current configuration*

**CER Table:**

| **Modified 1D10 Die Roll** | **Space Combat CER**             |
| -------------------------- | -------------------------------- |
| Less than zero, 0, 1, 2    | One Quarter (0.25) (round up)    |
| 3, 4                       | One Half (0.50) (round up)       |
| 5, 6                       | Three Quarters (0.75) (round up) |
| 7, 8                       | One (1)                          |
| 9*                         | One* (1)                         |
| 9+                         | One (1)                          |

*If the die roll is a natural nine before any required modification, then a critical hit is achieved

4. **Calculate damage**: Total Hits = Squadron AS × CER Multiplier (round up)

**Critical Hits:**
- **Natural roll of 9** (before modifiers) = Critical Hit
- Bypasses destruction protection (can destroy Undamaged → Destroyed in one round)
- **Force Reduction**: If critical hit damage insufficient to reduce target (damage < target DS), the **weakest squadron** in enemy task force is reduced instead (lowest DS squadron takes the hit)

**Overkill Damage:**

When multiple squadrons independently target the same enemy squadron:
- **Combined damage** from all attackers applies to target
- If combined damage would destroy squadron in same round it's crippled:
  - **If ANY attacker rolled critical**: Destruction protection bypassed, squadron destroyed
  - **If NO critical hit**: Destruction protection applies, squadron stays crippled, excess damage lost
- Prevents multiple attackers from wasting firepower on already-dead targets

**Example:**
- Battleship squadron: AS 50
- Roll: 5 (natural)
- Modifiers: +1 (scouts) +1 (high morale) = +2
- Modified roll: 7 → CER 1.00×
- Damage: 50 × 1.00 = 50 hits

### 7.3.4 Target Selection

Squadrons target enemies using priority buckets—categories determining which enemies to shoot first.

**Targeting Priority Buckets:**

| Bucket | Unit Type | Base Weight | Priority |
|--------|-----------|-------------|----------|
| **1 – Raider** | Squadron with Raider flagship | 1.0 | Highest |
| **2 – Capital** | Squadron with Cruiser or Carrier flagship | 2.0 | High |
| **3 – Destroyer** | Squadron with Destroyer flagship | 3.0 | Medium |
| **4 – Fighter** | Fighter squadron (no capital flagship) | 4.0 | Low |
| **5 – Starbase** | Orbital installation | 5.0 | Lowest |

**Notes:**
- Lower bucket numbers = higher targeting priority
- Fighter squadrons consist entirely of fighter craft (no capital ship flagship)
- Starbases are orbital installations, not squadrons
- Targeting walks buckets in order: Raider → Capital → Destroyer → Fighter → Starbase

**Special Rule: Fighter Squadron Targeting**

Fighter squadrons launched from carriers target enemy fighters first (fighter-vs-fighter combat), then proceed to standard bucket priority if no enemy fighters remain.

**Weighted Random Selection**

Within each bucket, targets selected randomly weighted by Defense Strength—tougher squadrons (higher DS) more likely to be targeted. This represents fire concentration on the biggest threats.

**Crippled Squadron Targeting:**
- Crippled squadrons get **2× targeting weight**
- Makes them more likely to be finished off
- Represents opportunistic fire on damaged enemies
- Example: Crippled Battleship (DS 40) has targeting weight of 80

### 7.3.5 Combat Rounds

Combat resolves in rounds—simultaneous exchanges of fire continuing until one side retreats or is destroyed.

**Round Sequence:**

1. **Target Selection**: Both sides assign targets per priority buckets
2. **Damage Calculation**: Calculate damage based on AS, CER, and target DS
3. **Apply Damage**: Squadrons crippled or destroyed
4. **Update Combat State**: Remove destroyed squadrons, update crippled squadrons
5. **Retreat Check**: Losing side checks morale and ROE for retreat decision
6. **Repeat**: Continue until combat ends

**Maximum Rounds**: 20 rounds per combat (prevents infinite combat)

**Round Duration**: Each round represents approximately 30-60 minutes of engagement time

**Desperation Mechanics:**

If combat stalls (5 consecutive rounds without any squadron state changes):
- Both sides get **+2 CER bonus** for one "desperation round"
- Represents desperate all-out attacks to break the stalemate
- After desperation round, combat continues normally
- If still no progress after desperation, moves toward 20-round stalemate

### 7.3.6 Retreat Mechanics

Losing fleets can retreat before total destruction. Retreat saves surviving squadrons but concedes the battlefield.

**Retreat Triggers:**
- CER disadvantage exceeds threshold (significantly outmatched)
- Losses exceed acceptable percentage per ROE settings
- Morale collapse (excessive casualties break formation)
- Commander discretion (standing orders respect ROE retreat thresholds)

**Retreat Consequences:**
- Retreating fleet moves to nearest friendly system via jump lanes
- Attackers who retreat fail their mission (invasion aborted, bombardment incomplete)
- Defenders who retreat cede space superiority (attackers proceed to orbital combat)
- Crippled squadrons may be lost during retreat if cannot traverse restricted lanes

**Pursuit**: Victorious fleet does NOT automatically pursue retreating enemies. Pursuit requires explicit orders (Move to follow) or standing orders (PatrolRoute, AutoReinforce).

**Multi-House Retreat Priority:**

When 3+ houses attempt to retreat simultaneously:
1. **Weakest retreats first**: Houses retreat in ascending order of total AS (weakest first)
2. **Ties broken by house ID**: If equal AS, alphanumeric house ID order
3. **Re-evaluation**: After each retreat, remaining houses re-check ROE against new enemy strength
4. **Cancel option**: Re-evaluation may cause house to cancel retreat and continue fighting
5. **One retreats**: Other houses continue battling until their own ROE triggers

### 7.3.7 Victory Conditions

Space combat ends when:

**Attacker Victory:**
- All mobile defenders destroyed or retreated
- Attackers achieve space superiority
- **Result**: Proceed to orbital combat phase

**Defender Victory:**
- All attackers destroyed or retreated
- Defenders maintain space control
- **Result**: Attackers repelled, mission failed

**Mutual Withdrawal:**
- Both sides retreat simultaneously
- Rare but possible with evenly matched forces
- **Result**: Status quo maintained, no territorial change

**Multi-House Prestige Attribution:**

When 3+ houses participate in combat, prestige for kills is awarded based on who dealt the crippling blow:
- **Squadron destroyed**: House that dealt crippling blow gets prestige
- **Already-crippled squadron finished off**: All attacking houses share prestige equally (minimum 1 per house)
- **Fleet retreats**: All houses engaged with retreating fleet share prestige equally
- **Critical**: Track damage sources to determine crippling blow attribution

---

## 7.4 Orbital Combat

Assault fortified colony defenses after winning space superiority. Your fleets engage guard forces, reserve fleets, starbases, and orbital squadrons in a unified defensive position.

### 7.4.1 Orbital Combat Participants

**Attackers** (If They Won Space Combat):
- All surviving attack fleets from space combat
- Any fleets that bypassed space combat (if no mobile defenders present)

**Orbital Defenders** (All Fight Simultaneously):
- **Guard fleets**: Fleets with GuardStarbase, GuardPlanet, DefendSystem orders
- **Reserve fleets**: 50% maintenance fleets stationed at colony (reduced combat effectiveness)
- **Mothballed fleets**: 0% maintenance fleets (CANNOT FIGHT - must be screened)
- **Starbases**: Orbital installations with heavy firepower and detection capability
- **Unassigned squadrons**: Combat squadrons at colony not assigned to fleets
- **Fighter squadrons**: Colony-based fighters (if not already loaded on carriers)

**Screened Units (Protected, Do Not Fight):**
- Mothballed ships (offline, defenseless)
- Spacelift vessels (no combat capability)
- These units hide behind defending task force; destroyed if defenders eliminated

### 7.4.2 Orbital Combat Differences from Space Combat

**No Ambush Bonus:**
- Orbital defenses detect all approaching threats
- Raiders get NO +4 CER bonus in orbital combat
- Detection sharing still works (starbases provide detection)

**Starbases Participate:**
- Starbases add significant AS/DS to defender task force
- Fixed installations with heavy firepower
- Cannot retreat—fight to destruction or victory

**Reduced Mobility:**
- Defenders fight from fortified positions
- Attackers cannot maneuver as freely (planetary gravity well)
- Retreat harder for attackers (must break orbit under fire)

**Screened Unit Vulnerability:**
- If defenders eliminated, screened units exposed
- Mothballed ships destroyed if not protected
- Spacelift vessels destroyed if defenders fail

### 7.4.3 Reserve Fleet Combat Penalty

Reserve fleets fight at reduced effectiveness:
- **Reduced AS/DS**: Half combat strength (maintenance savings = readiness trade-off)
- Still better than no defense
- Can be reactivated to full strength (Reactivate order, returns to Active status)

### 7.4.4 Victory Conditions

**Attacker Victory:**
- All orbital defenders destroyed or retreated
- Attackers achieve orbital supremacy
- **Result**: Proceed to planetary bombardment/invasion phase

**Defender Victory:**
- All attackers destroyed or retreated
- Orbital defenses hold
- **Result**: Colony remains secure, invasion repelled

**Screened Unit Loss:**
- If attackers win, mothballed/spacelift units destroyed
- Significant economic and strategic loss
- Defenders should activate mothballed fleets before combat if threatened

---

## 7.5 Planetary Bombardment

Destroy enemy infrastructure and defenses from orbit after achieving orbital supremacy. Your fleets systematically dismantle planetary shields, neutralize ground batteries, and reduce industrial capacity.

### 7.5.1 Bombardment Execution

**Requirements:**
- Orbital supremacy achieved (won orbital combat)
- Combat-capable squadrons present (AS > 0)
- Bombard order issued to fleet

**Bombardment Process:**

Each turn of bombardment (up to 3 rounds), your fleet attacks planetary defenses. Shields reduce incoming damage, but hits penetrate to damage batteries, ground forces, and infrastructure simultaneously:

**Bombardment Damage Flow:**

1. **Calculate Bombardment Hits** (AS × CER)
   - Your fleet's total Attack Strength
   - Roll 1d10 on Bombardment CER table (see below)
   - Planet-Breaker AS counted separately (bypasses shields)

**Bombardment CER Table:**

| **1D10 Die Roll** | **Bombardment CER** |
| ----------------- | ------------------- |
| 0, 1, 2           | One Quarter (0.25) (round up) |
| 3, 4, 5           | One Half (0.50) (round up) |
| 6, 7, 8           | One (1) |
| 9*                | One* (1) |

*Critical hits apply only against attacking squadrons (ground batteries firing back), not against ground targets

2. **Shields Reduce Conventional Hits**
   - Planetary shields reduce conventional ship damage by percentage (20%-70% based on SLD level)
   - Planet-Breaker hits bypass shields entirely
   - Total effective hits = Planet-Breaker hits + (reduced conventional hits)

3. **Hits Flow Through Defenses in Order:**
   - **First**: Ground batteries absorb hits (crippled, then destroyed)
   - **Excess hits**: Damage ground forces (armies and marines)
   - **Remaining excess**: Destroy infrastructure (IU loss)

**Key Mechanics:**
- Shields slow damage but don't prevent it—batteries, forces, and infrastructure can be damaged in the same turn
- Ground batteries fire back each round (can cripple/destroy bombarding squadrons)
- Multiple bombardment turns gradually overwhelm defenses
- Higher shield levels reduce more damage, prolonging defensive survival

### 7.5.2 Planetary Shields

Shields reduce bombardment damage from conventional ships. Higher shield levels block larger percentages of incoming hits.

**Shield Levels and Damage Reduction:**

| SLD Level | % Chance | 1D20 Roll | % of Hits Blocked |
|:---------:|:--------:|:---------:|:-----------------:|
| SLD1      | 15%      | > 17      | 25%               |
| SLD2      | 30%      | > 14      | 30%               |
| SLD3      | 45%      | > 11      | 35%               |
| SLD4      | 60%      | > 8       | 40%               |
| SLD5      | 75%      | > 5       | 45%               |
| SLD6      | 90%      | > 2       | 50%               |

**Shield Mechanics:**
- Each bombardment round, roll 1d20 to see if shields activate
- If roll meets or exceeds threshold, shield blocks percentage of conventional hits
- Shields reduce hits, they don't prevent them—damage still penetrates to batteries/infrastructure
- Planet-Breaker hits bypass shields entirely (no reduction)
- Shields remain active throughout bombardment (don't "degrade" or "get destroyed")
- Shields only destroyed when Marines land during invasion

**Planet-Breaker Advantage:**

Planet-Breaker ships bypass ALL shield levels:
- Planet-Breaker AS ignores shield reduction completely
- Mixed fleets: Planet-Breaker AS + (reduced conventional AS) = total hits
- Expensive (400 PP) but essential for high-shield fortress worlds
- Strategic siege weapon for heavily defended targets

### 7.5.3 Ground Batteries

Ground-based defensive installations fire on orbiting ships. Batteries threaten bombarding fleets and invasion forces.

**Ground Battery Mechanics:**
- Each battery has attack strength
- Targets orbiting ships randomly
- Can cripple or destroy bombarding vessels
- Battery fire continues until batteries destroyed
- Multiple batteries = sustained defensive fire

**Neutralizing Batteries:**
- Bombardment hits damage batteries first (before ground forces or infrastructure)
- Shields reduce conventional hits but don't prevent battery damage
- Each battery can be crippled (reduced AS) then destroyed
- All batteries must be destroyed before invasion can proceed

**Strategic Considerations:**
- High battery count = dangerous bombardment
- Weak bombarding fleet risks losses to battery fire
- Alternative: Starve colony via blockade instead of bombardment

### 7.5.4 Infrastructure Damage

Excess bombardment hits (after damaging batteries and ground forces) destroy colony infrastructure:

**Infrastructure Damage Effects:**
- **Production loss**: Each percentage point reduces GDP
- **Facility destruction**: Spaceports, shipyards can be destroyed
- **Population casualties**: Souls lost to bombardment
- **Morale impact**: Defender prestige loss, attacker diplomatic penalties

**Damage Accumulation:**
- Infrastructure damage percentage increases each bombardment turn
- 10% damage = 10% production loss
- 50% damage = colony crippled
- 100% damage = colony ruins (remains colonized but devastated)

**Repair Costs:**
- Damaged infrastructure requires PP investment to repair
- Repair time scales with damage percentage
- Captured colonies often require extensive rebuilding

### 7.5.5 Bombardment Strategy

**Prolonged Siege:**
- Bombard over multiple turns to systematically destroy defenses
- Reduces invasion risk by eliminating batteries and shields
- Expensive in time and fleet commitment
- Generates diplomatic penalties

**Quick Assault:**
- Minimal bombardment, immediate invasion
- Risks heavy invasion casualties
- Captures infrastructure intact
- Faster conquest but higher military cost

**Blockade Alternative:**
- Blockade colony instead of bombardment (GuardPlanet/BlockadePlanet orders)
- Cuts production 50% without destruction
- Starves defenders over time
- Less diplomatic penalty than bombardment

---

## 7.6 Planetary Invasion and Blitz

Seize enemy colonies by landing ground forces after achieving orbital supremacy. Your marines and armies fight defending ground forces for control of the planet surface.

### 7.6.1 Planetary Invasion

Land ground forces to conquer enemy colonies. Invasion requires orbital supremacy, loaded troop transports, and overwhelming ground superiority.

**Invasion Requirements:**
- Orbital supremacy achieved (won orbital combat)
- **ALL ground batteries destroyed** (mandatory—batteries fire on landing transports)
- Troop Transports with loaded Marines (MD = Marine Division)
- Invade order issued to fleet

**Invasion Process:**

1. **Bombardment Round**
   - Conduct ONE round of bombardment first (Section 7.5)
   - Ground batteries must be destroyed before landing
   - If batteries remain after bombardment round, invasion fails (cannot land)
   - If all batteries destroyed, proceed to landing

2. **Landing Phase**
   - Marines land—shields and spaceports immediately destroyed upon landing
   - Transports unload marines (troops committed to battle)

3. **Ground Combat Phase**
   - **Both sides roll 1d10 on Ground Combat Table**
   - Calculate hits: AS × Ground CER → damage to enemy forces
   - Apply hits to ground units (cripple, then destroy)
   - Repeat rounds until one side eliminated

**Ground Combat Table:**

| 1d10 Roll | Ground CER Multiplier |
|-----------|-----------------------|
| 0-2 | 0.5× (round up) |
| 3-6 | 1.0× |
| 7-8 | 1.5× (round up) |
| 9 | 2.0× |

**Ground Forces:**

**Attackers:**
- Marines from Troop Transports (1 MD per transport)
- Each MD: AS 10, DS 10 (from config)
- Marines fight at full strength

**Defenders:**
- Ground Armies (garrison forces): AS 8, DS 8 each
- Defending Marines (colony-based): AS 10, DS 10 each
- Combined ground strength

**Combat Resolution:**

Both sides roll each round, exchange fire, until one side eliminated:
- Units crippled: AS reduced to 50%
- Crippled units destroyed if all others crippled
- Battle continues until total elimination
- **If attackers win**: Colony captured, **50% IU destroyed** by loyal citizens before order restored
- **If defenders win**: Invasion repelled, attacker marines destroyed

### 7.6.2 Planetary Blitz

Conduct rapid combined bombardment + invasion operations. Blitz sacrifices safety for speed—marines land under fire from ground batteries.

**Blitz Requirements:**
- Orbital supremacy achieved
- Loaded Troop Transports present
- Blitz order issued to fleet
- **No requirement for weak defenses**—blitz works against any target (risky against strong defenses)

**Blitz Mechanics:**

Blitz combines bombardment and ground combat in compressed sequence:

1. **Bombardment Round (Transports Vulnerable)**
   - Conduct ONE round of bombardment (Section 7.5)
   - **Ground batteries fire at Troop Transports** (included as units in fleet)
   - Transports can be destroyed before landing marines
   - No civilian infrastructure targeted (avoid damage to assets)

2. **Landing Phase (If Transports Survive)**
   - Marines land immediately (don't wait for batteries eliminated)
   - **Marines fight at 0.5× AS** (quick insertion penalty, evading batteries)
   - Shields, spaceports, batteries seized intact if successful

3. **Ground Combat**
   - Same Ground Combat Table as invasion (1d10 roll)
   - Marines at half AS disadvantage
   - Repeat rounds until one side eliminated
   - **If attackers win**: All assets seized intact (**0% IU destroyed**)
   - **If defenders win**: Invasion repelled, attacker marines destroyed

**When to Use Blitz:**

**Advantages:**
- Seizes colony infrastructure intact (no IU loss on victory)
- Captures shields, batteries, spaceports
- Faster than methodical bombardment + invasion
- Good against weak defenses

**Risks:**
- Transports vulnerable during bombardment round (can be destroyed)
- Marines fight at half AS (quick insertion penalty)
- High casualty risk against strong ground batteries
- Dangerous against heavily fortified colonies (high shields, many batteries, large garrison)

### 7.6.3 Invasion Strategy

**Overwhelming Force:**
- Bring 2:1 marine superiority minimum
- Reduces casualties, ensures victory
- Expensive but decisive

**Bombardment Preparation:**
- Destroy shields and batteries before invasion
- Reduces marine casualties during landing
- Preserves marine strength for ground combat
- Takes more time but safer

**Blockade + Starvation:**
- Blockade colony for multiple turns
- Production halved, garrison weakens over time
- Invade after defenders weakened
- Minimizes military losses, maximizes time cost

**Blitz Expansion:**
- Use blitz against weak frontier colonies during land grabs
- Speed captures territory before rivals
- Accept higher casualties for strategic advantage
- Effective early-game expansion tool

---

## 7.7 Combat Examples

Practical scenarios demonstrating combat theater progression and strategic decision-making.

### 7.7.1 Example: Standard Planetary Invasion

**Scenario**: House Atreides invades House Harkonnen colony at Giedi Prime.

**Turn 1 - Space Combat:**
- Atreides fleet (3 Battleships, 6 Destroyers) enters Giedi Prime
- Harkonnen mobile defender (2 Cruisers, 4 Frigates) intercepts
- Space combat: Atreides wins (superior firepower), 1 Battleship crippled
- Harkonnen fleet retreats to adjacent system
- **Result**: Atreides achieves space superiority, advances to orbital combat

**Turn 2 - Orbital Combat:**
- Atreides surviving fleet (2 Battleships, 1 crippled, 6 Destroyers) engages orbital defenses
- Harkonnen orbital defense: 1 Guard fleet (Light Cruiser + 3 Destroyers), 2 Starbases, 5 unassigned squadrons
- Orbital combat: Atreides wins (overwhelming numbers), 2 Destroyers destroyed
- Harkonnen starbases destroyed, guard fleet eliminated
- **Result**: Atreides achieves orbital supremacy, proceeds to bombardment

**Turn 3-5 - Bombardment:**
- Atreides bombards SLD-4 shield (4 turns to destroy)
- Ground batteries fire back, cripple 1 Destroyer
- Turn 5: Shield destroyed, batteries neutralized
- **Result**: Planet defenses eliminated, ready for invasion

**Turn 6 - Invasion:**
- Atreides lands 6 Marine Divisions
- Harkonnen garrison: 3 Armies + 2 Marine Divisions
- Ground combat: Atreides 6 MD vs. Harkonnen 5 ground units
- Atreides wins (slight superiority), 2 MD lost
- **Result**: Colony captured, ownership transfers to Atreides

**Total Cost**: 6 turns, 1 Battleship crippled, 2 Destroyers destroyed, 2 Marine Divisions lost, 1 Destroyer crippled by batteries

### 7.7.2 Example: Blitz Operation

**Scenario**: House Corrino blitzes weakly defended rebel colony.

**Turn 1 - Space Combat:**
- Corrino fleet (1 Battle Cruiser, 4 Destroyers, 2 Troop Transports) enters system
- No mobile defenders present
- **Result**: Automatic space superiority, proceed to orbital combat

**Turn 1 - Orbital Combat (Same Turn):**
- Rebel defense: 1 unassigned squadron (Light Cruiser), no starbases
- Corrino wins easily, Light Cruiser destroyed
- **Result**: Orbital supremacy achieved

**Turn 1 - Blitz Operation (Same Turn):**
- Corrino issues Blitz order
- Fleet bombards while transports land simultaneously
- Minimal shield (SLD-1), few batteries
- 2 Marine Divisions land and engage
- Rebel garrison: 1 Army
- Blitz successful: Colony captured
- **Result**: Colony captured in single turn

**Total Cost**: 1 turn, no ship losses, minor marine casualties

**Comparison**: Standard invasion would take 4-5 turns (bombardment + invasion). Blitz sacrificed methodical approach for speed, accepting slightly higher marine casualties.

### 7.7.3 Example: Failed Invasion

**Scenario**: House Ordos attempts invasion of heavily fortified Ix.

**Turn 1 - Space Combat:**
- Ordos fleet (2 Dreadnoughts, 4 Cruisers) enters Ix
- Ix mobile defense (3 Battle Cruisers, 8 Destroyers, ELI scout)
- ELI scout detects Ordos Raider (no ambush bonus)
- Space combat: Ordos loses (outnumbered, no ambush advantage)
- 1 Dreadnought destroyed, 2 Cruisers crippled
- **Result**: Ordos fleet retreats to friendly system, invasion fails before reaching orbit

**Lessons**:
- Space superiority crucial—cannot skip theater
- ELI detection negated Raider ambush advantage
- Ordos should have brought overwhelming force or reconnoitered first

---

**End of Section 7**
