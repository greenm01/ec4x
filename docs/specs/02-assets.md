# 2.0 Game Assets

## 2.1 Star Map

The star-map consists of a 2D hexagonal grid, each a flat-top hex that
contains a solar system, interconnected throughout by procedurally generated
jump lanes. Map size is configurable via the `numRings` parameter (2-12
rings), independent of player count, allowing flexible scenario design. The
center hub is guaranteed to have six lanes of travel.

Solar systems have special traits and are procedurally generated. They each
contain a single planet that is suitable for colonization.

**Jump Lane Classes**

There are three classes of jump lanes that determine which ship types can traverse them:

<!-- LANE_DISTRIBUTION_START -->

- **Major lanes** (50% of all lanes): Allow all ship types

- **Minor lanes** (35% of all lanes): Allow all ship types

- **Restricted lanes** (15% of all lanes): Block crippled ships only
  
  <!-- LANE_DISTRIBUTION_END -->

This distribution affects pathfinding costs (Major=1, Minor=2, Restricted=3) while allowing all ship types to traverse all lanes (except crippled ships on restricted lanes). Movement across the lanes is explained in [Section 6.1](06-operations.md#61-jump-lanes).

**Hub Connectivity**

The hub is guaranteed to have six jump lanes connecting it to the first ring, making it an important strategic asset. Hub lanes use the same distribution as the rest of the map (mixed lane types), preventing predictable "rush-to-center" gameplay. Controlling the hub grants significant strategic power but requires careful fleet composition.

**Homeworld Placement**

<!-- HOMEWORLD_PLACEMENT_START -->

Player homeworlds are placed throughout the map using distance maximization algorithms. The generator ensures each homeworld is as far as strategically possible from rival home systems, creating balanced starting positions while introducing natural asymmetry in the tactical landscape. This distribution allows homeworlds on any ring for unpredictable, varied starting scenarios.

Each homeworld is guaranteed to have exactly 3 **Major lanes** connecting it to adjacent systems, ensuring reliable colonization paths and fleet movement from the start.

<!-- HOMEWORLD_PLACEMENT_END -->

### Variable Map Sizes

The `numRings` parameter (2-12 range) controls map size independently of
player count, providing flexible scenario design:

- **Small maps (2-4 rings):** Quick games, limited strategic space
- **Medium maps (5-8 rings):** Standard games, balanced expansion
- **Large maps (9-12 rings):** Epic games, extensive strategic depth

Total systems = 3n² + 3n + 1, where n = numRings. See
`docs/guides/map-sizing-guide.md` for systems-per-player ratios and design
guidance.

Homeworld placement uses distance maximization to spread players across
available systems, working effectively when systems-per-player > 5:

| Rings | Players | Systems/Player | Effect                                |
|-------|---------|----------------|---------------------------------------|
| 2     | 4       | 4.8            | Too cramped - homeworlds will cluster |
| 4     | 4       | 15.3           | Good spacing - algorithm works well   |
| 6     | 12      | 10.6           | Decent spacing despite 12 players     |

**Configuration**: Map size is set in `game_setup/*.kdl` files via the
`mapGeneration` section. Game administrators are responsible for choosing an
appropriate `numRings` value based on their intended player count and desired
game length.

## 2.2 Solar Systems

Solar systems contain various F, G, K, and M class stars orbited by at least one terrestrial planet, suitable for colonization and terraforming. Systems without terrestrial planets are not charted and of no consequence to your task.

Roll on the planet class and system resources tables below to determine the attributes for each hex on the star-map, excluding homeworlds.

Each newly established colony begins as Level I and has potential to develop into the max Population Unit (PU) for that planet. Move colonists from larger colonies to smaller colonies to increase population growth over the natural birth rate.

Advances in terraforming tech allow your planets to upgrade class and living conditions. For terraforming research and costs, see [Section 4.6](04-research_development.md#46-terraforming-ter).

**Planet Class Table**

| Roll 1D10 | Class    | Colony Potential | PU        | PTU             |
|:---------:| -------- | ---------------- |:---------:|:---------------:|
| 0         | Extreme  | Level I          | 1 - 20    | 1 - 20          |
| 1         | Desolate | Level II         | 21 - 60   | 21 - 60         |
| 2, 3      | Hostile  | Level III        | 61 - 180  | 61 - 182        |
| 4, 5      | Harsh    | Level IV         | 181 - 500 | 183 - 526       |
| 6, 7      | Benign   | Level V          | 501- 1k   | 527 - 1,712     |
| 8\*       | Lush     | Level VI         | 1k - 2k   | 1,713 - 510,896 |
| 9\*\*     | Eden     | Level VII        | 2k+       | 510,896+        |

\*If the roll above is a natural eight (8), add a +1 modifier to your roll on the System Resources Table.
\*\*If the roll is a natural nine (9) add a +2 modifier.

For the relationship between PU and PTU, including economic implications and formulas, see [Section 3.1](03-economy.md#31-principles).

**System Resources Table**

| Modified Roll 1D10 | Raw Materials |
|:------------------:| ------------- |
| 0                  | Very Poor     |
| 2, 3               | Poor          |
| 4 - 7              | Abundant      |
| 8, 9               | Rich          |
| 10+                | Very Rich     |

For how Raw Materials affect colony economic output, see the RAW INDEX table in [Section 3.1](03-economy.md#31-principles).

## 2.3 Military

### 2.3.1 Space Force Ships

The base game includes a number of imperial classed space combatants listed in [Section 10.1](10-reference.md#101-space-force-wep1).

### 2.3.2 Spacelift Command

Spacelift Command provides commerce and transportation services supporting your House's expansion efforts. You own these assets, and senior Space Force officers command them. Loyal House citizens crew and operate the units.

Spacelift assets have no offensive weapons capability—unescorted units are easily destroyed by rival forces.

Spacelift Command attributes are listed in [Section 10.3](10-reference.md#103-spacelift-command-wep1).

#### 2.3.2.1 Spaceports

Spaceports are large ground based facilities that launch heavy-lift ships and equipment into orbit. They require one month (one turn) to build and have five construction docks at base capacity, allowing up to five simultaneous ship construction projects planet-side.

**Construction Cost**: 20 PP  
**Construction Time**: 1 turn  
**Base Capacity**: 5 docks  
**Capacity Scaling**: Dock capacity increases with CST tech (see [Section 4.5](04-research_development.md#45-construction-cst))

**Planet-side Ship Construction**: Ships built at spaceports incur a **100% PP cost penalty** due to orbital launch requirements. See [Section 5.2](05-construction.md#52-planet-side-construction) for construction rules.

**Facility Repair**: Spaceports handle repairs for facility-class units (Starbases). These repairs do NOT consume dock capacity, allowing simultaneous facility repair and ship construction.

**Ship Repair**: Spaceports cannot repair ships - only Drydocks can repair ship-class units.

#### 2.3.2.2 Shipyards

Shipyards are gateways to the stars—large bases constructed in orbit that require a spaceport to build over a period of two turns.

The majority of your ship construction occurs at these important facilities.

**Construction Cost**: 60 PP
**Construction Time**: 2 turns
**Prerequisite**: Requires operational Spaceport
**Base Capacity**: 10 docks
**Capacity Scaling**: Dock count increases with Construction (CST) technology (see [Section 4.5](04-research_development.md#45-construction-cst))

Shipyards are equipped with construction docks and are fixed in orbit. Build multiple yards to increase your construction capacity at the colony.

**Orbital Ship Construction**: Ships built at shipyards use standard PP costs with no penalties. See [Section 5.4](05-construction.md#54-orbital-construction).

**Ship Repairs**: Shipyards cannot repair ships - ship repairs require Drydocks (see [Section 2.3.2.3](#23223-drydocks)).

#### 2.3.2.3 Drydocks

Drydocks are specialized orbital facilities dedicated to ship repair operations. These massive maintenance stations are constructed in orbit and require a spaceport to build over a period of two turns.

**Construction Cost**: 150 PP
**Construction Time**: 2 turns
**Prerequisite**: Requires operational Spaceport
**Base Capacity**: 10 docks
**Capacity Scaling**: Dock count increases with Construction (CST) technology (see [Section 4.5](04-research_development.md#45-construction-cst))

Drydocks are repair-only facilities and cannot construct ships. They are fixed in orbit alongside shipyards. Build multiple drydocks to increase your repair capacity at the colony.

**Ship Repairs**: Only drydocks can repair ships. Repair costs 25% of ship's original PP cost and completes in 1 turn. See [Section 5.5](05-construction.md#55-orbital-repair).

**Construction**: Drydocks cannot construct ships - ship construction requires Shipyards or Spaceports.

#### 2.3.2.4 Environmental Transformation And Colonization (ETAC)

ETACs are self-sufficient generation ships employing cryostasis technology to transport colonists across the void. Each ETAC carries 3 PTU of frozen colonists, sufficient to establish a single "foundation colony" with a robust 3 PU starter population (~3M souls). This larger initial population enables rapid economic development—foundation colonies can construct spaceports and build additional ETACs to continue the expansion wave.

ETACs are one-time consumable assets—after depositing their colonists, the vessel itself is cannibalized to establish the colony's starting infrastructure (IU). The ship's advanced systems, power cores, and manufacturing facilities form the foundation of the new settlement. Players begin with 2 ETAC fleets (each containing 1 ETAC and 1 Cruiser escort) to seed their initial expansion.

**Carry Limit (CL)**: 3 PTU (deposits all on single colony)
**Starter Population**: 3 PU foundation colony (vs 1 PU previously)
**Construction Cost**: 15 PP base (30 PP at spaceport with 2× penalty)
**Consumption**: Ship cannibalized for colony infrastructure (no refund)
**Starting Forces**: 2 ETAC fleets per house (per Esterian Conquest v1.5)
**Lane Restrictions**: Blocked by Restricted lanes (15% of lanes)
**Combat**: Zero offensive/defensive capability

#### 2.3.2.5 Troop Transports

Troop Transports are specialized ships that taxi Space Marine divisions between solar systems, along with their required combat gear, armored vehicles, and ammunition.

**Carry Limit (CL)**: 1 Marine Division (MD) at STL I, scales with Strategic Lift (STL) technology  
**Lane Restrictions**: Blocked by Restricted lanes (15% of lanes)  
**Combat**: Zero offensive/defensive capability

For STL capacity progression, see [Section 4.9](04-research_development.md#49-strategic-lift-stl).

### 2.3.3 Naval Command Structure

Your House's military forces are organized into a clear command hierarchy. Understanding this structure is critical to effective strategic management.

#### 2.3.3.1 Squadrons (Tactical Level)

The smallest tactical unit in your navy is the **Squadron**.
- Each squadron is commanded by a single **flagship**.
- The flagship's **Command Rating (CR)** determines the maximum size of the squadron.
- Other ships in the squadron have a **Command Cost (CC)**. The sum of all CCs in a squadron (excluding the flagship) cannot exceed the flagship's CR.
- Squadrons fight and move as a single entity.
- A squadron can consist of a solo flagship.

Improving the size and capability of your squadrons is done by researching **Flagship Command (FC)** technology, which increases the CR of your flagships. See [Section 4.10](04-research_development.md#410-flagship-command-fc).

#### 2.3.3.2 Fleets (Strategic Level)

Squadrons are grouped together into **Fleets**. A Fleet is the primary strategic unit you will manage on the starmap.
- A Fleet can contain any number of squadrons.
- You can create, name, merge, and split fleets at any time in a non-hostile system.
- Fleets are the units that receive movement and operational orders.

#### 2.3.3.3 Command & Control (C2) Pool

While you can organize your squadrons into as many fleets as you wish, the total size of your navy is governed by your **Command & Control (C2) Pool**. This is a soft cap representing your empire's ability to command and support its military assets.

- Every combat ship has a **Command Cost (CC)**.
- Your C2 Pool is the total CC your House can support without penalty.
- The C2 Pool is determined by your industrial might and your investment in command technology.

**C2 Pool Formula:**
`Total C2 Pool = (Total House IU * 0.5) + [C2 Pool Bonus from SC Tech]`

- **Auxiliary ships** (Scouts, ETACs, Transports) and **Facilities** (Starbases) do not have a CC and do not count against your C2 Pool.

#### 2.3.3.4 Logistical Strain (Exceeding the C2 Pool)

The C2 Pool is a soft limit. If the total CC of all your active ships exceeds your C2 Pool, your empire incurs a direct financial penalty each turn called **Logistical Strain**.

**Logistical Strain Formula:**
`Cost per Turn = (Total Fleet CC - C2 Pool) × 0.5`

This flat PP cost is deducted from your treasury each turn. It represents the mounting inefficiency of an over-extended command structure. A player who loses industrial capacity (and thus C2 Pool) will face a painful but predictable economic challenge they can solve through strategic action.

For the technology to increase your C2 Pool, see **Strategic Command (SC)** in [Section 4.11](04-research_development.md#411-strategic-command-sc).

#### 2.3.3.5 Ship Status Management

To effectively manage your C2 Pool and maintenance costs, you can assign different operational statuses to your fleets.

**Active Duty:**
- **CC Cost:** 100%
- **Maintenance Cost:** 100%
- **Status:** Fully operational. Can move and fight.

**Reserve Status:**
- **CC Cost:** 50%
- **Maintenance Cost:** 50%
- **Rules:**
    - A fleet must be at a friendly starbase or shipyard to be placed in Reserve.
    - Placing a fleet in Reserve is **instant** during the Command Phase.
    - Reactivating it takes **1 full turn**.
    - While in Reserve, a fleet is immobile and cannot fight.
- **Strategic Use:** Ideal for reducing C2 and maintenance load during peacetime while keeping fleets ready for rapid deployment.

**Mothballed Status:**
- **CC Cost:** 0%
- **Maintenance Cost:** 10% (for skeleton crews and basic system integrity)
- **Rules:**
    - A fleet must be at a friendly starbase or shipyard to be Mothballed.
    - Mothballing a fleet is **instant** during the Command Phase.
    - Reactivating a mothballed fleet takes **3 full turns**.
- **Strategic Use:** For long-term storage of valuable but currently unneeded assets, completely freeing up their C2 Pool allocation for a minimal maintenance fee.

#### 2.3.3.6 Task Force

A Task Force is a temporary grouping of squadrons from one or more fleets, organized for a specific combat engagement. After hostilities cease, the task force is automatically disbanded and surviving squadrons return to their originally assigned fleets.

## 2.4 Special Units

### 2.4.1 Fighter Squadrons & Carriers

Fighters are small ships you commission in Fighter Squadrons (FS) that freely patrol a system. They're based planet-side and never retreat from combat. Fighters are glass cannons—cheap to build but pack a punch.

**Construction Cost**: 5 PP per squadron  
**Maintenance Cost**: Zero

**Capacity Limits**:

Fighter Squadron capacity per colony is determined by industrial capacity and Fighter Doctrine (FD) research:

```
Max FS per Colony = floor(IU / 100) × FD_MULTIPLIER
```

Where:
- **IU** = Industrial Units at the colony
- **FD_MULTIPLIER** = Fighter Doctrine tech multiplier (FD I: 1.0×, FD II: 1.5×, FD III: 2.0×)

**No Infrastructure Required**: Fighters are built planet-side via distributed manufacturing. No spaceports, shipyards, or starbases required.

**Enforcement**: Colonies exceeding capacity receive 2-turn grace period, then oldest squadrons auto-disband.

For FD research progression and capacity multipliers, see [Section 4.12](04-research_development.md#412-fighter-doctrine-fd). For economic and strategic considerations, see [Section 3.6](03-economy.md#36-fighter-squadron-economics).

**Carrier Operations**:

Fighter Squadrons can be loaded onto carriers for mobility:

**Standard Carrier (CV)**:

- ACO I: 3 FS capacity
- ACO II: 4 FS capacity
- ACO III: 5 FS capacity

**Super Carrier (CX)**:

- ACO I: 5 FS capacity
- ACO II: 6 FS capacity
- ACO III: 8 FS capacity

For Advanced Carrier Operations (ACO) research, see [Section 4.13](04-research_development.md#413-advanced-carrier-operations-aco).

**Combat Mechanics**:

Fighter squadrons based at your colony automatically participate in orbital defense (see [Section 7.4](07-combat.md#74-orbital-combat)). Carrier-based fighters participate in space combat with their carrier's task force.

Each FS contributes:

- **Attack Strength (AS)**: 3
- **Defense Strength (DS)**: 1

Fighters are fragile but cost-effective. A mature colony can field dozens of squadrons, making direct assault prohibitively expensive.

### 2.4.2 Scouts

Scouts are autonmous auxiliary ships that specialize in espionage and reconnaissance. They are non-combat units that operate in **Scout-only fleets**. This allows you to move them to strategic locations and group them together before a mission.

They have two primary functions:
1.  **Reconnaissance (Non-Consumable)**: Using the `View a World` order, a Scout can gather basic intelligence on a system from a safe distance without being consumed.
2.  **Espionage (Consumable)**: When you issue a spy order (`Spy on Planet`, `Spy on System`, `Hack a Starbase`), the Scout fleet travels to the target system and establishes a persistent intelligence-gathering mission. All Scouts in the fleet are consumed (committed to the mission) and cannot be recalled.

**Mission Lifecycle**:

When you issue a spy order, the mission progresses through multiple phases:

1. **Travel Phase**: Scout fleet moves toward the target system using normal fleet movement. During this phase, you can cancel the mission by issuing new orders.
2. **Mission Start**: When the fleet arrives at the target system, the mission begins. The scouts are now "consumed" (committed to the mission), the fleet is locked, and you cannot issue new orders to this fleet.
3. **Persistent Operation**: Scouts remain at the target system gathering intelligence over multiple turns. Each turn, the defending house attempts to detect them.
4. **Termination**: The mission ends when scouts are detected (and destroyed) or the target colony is captured/destroyed.

**Detection Mechanics**:

Each turn while scouts are on an active mission, the defending house automatically attempts to detect them. Detection is a 1d20 roll by the defender that occurs **every turn** until the mission ends.

**Detection Formula**:

`Target Number = 15 - (Number of Scouts) + (Defender's ELI Level + Starbase Bonus)`

- A roll **greater than or equal to** the Target Number detects the Scouts.
- **Number of Scouts**: More scouts are harder to detect, lowering the target number.
- **Defender's ELI Level**: The defending house's researched ELI tech level. Higher ELI makes detection easier.
- **Starbase Bonus**: A starbase in the system adds **+2** to the defender's effective ELI level.

**Detection Outcome (Each Turn)**:
- **Success (Roll >= Target)**: All Scouts on the mission are detected and immediately destroyed. The mission fails, and no intelligence is gathered that turn. Diplomatic stance escalates to Hostile.
- **Failure (Roll < Target)**: The Scouts remain undetected and successfully gather **Perfect Quality** intelligence for that turn. The mission continues, and detection will be attempted again next turn.

**Example**:
Three of your Scouts establish a mission in a system with a starbase, owned by a house with ELI III.
- Target Number = `15 - 3 (scouts) + 3 (ELI III) + 2 (starbase) = 17`
- The defender must roll 17 or higher on a 1d20 to detect your scouts.
- Each turn, a new roll is made. Your scouts gather intelligence every turn they remain undetected.
- Over a 3-turn mission, the defender has three separate chances to detect and destroy your scouts.

**Strategic Implications**:
- Sending Scouts in larger groups is safer per turn, but detection risk accumulates over multiple turns.
- Short missions (1-2 turns) in well-defended systems are risky but may succeed before detection.
- Long missions (3+ turns) face high cumulative detection risk. Against prepared defenses, most long missions will eventually fail.
- Attacking systems with high ELI tech and starbases is extremely risky, especially for multi-turn operations.
- Neglecting your own ELI research makes your empire vulnerable to persistent enemy intelligence gathering.
- Once scouts arrive and the mission starts, you cannot recall them. They are committed until detected or the target is lost.

### 2.4.3 Raiders

Raiders are specialized combat vessels equipped with advanced cloaking systems. Their presence grants stealth to an entire fleet, providing two primary advantages:
1.  **Stealth Movement**: Move across the starmap undetected by enemies with inferior sensor technology.
2.  **Combat Advantage**: Initiate combat with a devastating first strike.

**Cloaking Technology**:

A Raider's effectiveness is determined by its house's Cloaking (CLK) research level. Higher CLK provides better stealth.

**Detection Mechanics**:

When a fleet containing one or more Raiders engages in combat (both Space and Orbital), a detection check is made at the start of that combat phase. Detection is an opposed roll pitting the attacker's CLK against the defender's ELI.

**Detection Roll**:
- **Attacker Rolls**: `1d10 + CLK Level`
- **Defender Rolls**: `1d10 + ELI Level + Starbase Bonus`

- **ELI Level**: The defending house's researched ELI tech level.
- **Starbase Bonus**: A starbase in the system adds **+2** to the defender's roll.

**Combat Advantage: Ambush & Surprise**

If a Raider fleet wins the detection roll at the start of combat, it gains a first-strike advantage that grants a **+4 CER bonus** in the first round.
- **Ambush**: Achieved by a defending Raider fleet in its own or a neutral system.
- **Surprise**: Achieved by an attacking Raider fleet initiating combat.

**Detection Outcome**:
- **Attacker Roll > Defender Roll**: The Raider fleet remains cloaked. It gains the first-strike advantage.
- **Defender Roll ≥ Attacker Roll**: The Raider fleet is detected. It fights as a normal fleet with no bonus.

**Strategic Implications**:
The CLK vs. ELI technology race is central to late-game warfare.
- A house with high CLK can ambush fleets from houses with poor ELI.
- A house with high ELI can neutralize the Raider threat.
- Starbases are critical for defending key systems against ambushes.

### 2.4.4 Starbases

Starbases (SB) are powerful orbital fortresses that facilitate planetary defense and economic development via ground weather modification and advanced telecommunications.

**Architecture**: Starbases are **facilities** (not ships). They are built and stored at colonies, never assigned to fleets or squadrons. In combat, they participate as facility units with their own combat statistics.

**Construction**:

**Cost**: 300 PP (fixed, does not scale with WEP)
**Construction Time**: 3 turns
**Prerequisite**: Requires operational Spaceport
**Construction Location**: Built at colonies using Spaceport infrastructure
**Mobility**: Fixed in orbit, cannot move out of home system

**Detection Capabilities**:

Starbases are equipped with powerful sensor arrays that enhance a system's defensive capabilities against stealth units.

- **Against Spy Scouts**: A Starbase provides a **+2 bonus** to the defending house's ELI Level for detection rolls.
- **Against Raiders**: A Starbase provides a **+2 bonus** to the defending house's detection roll.

This makes starbases critical for protecting high-value systems from both espionage and surprise attacks.

**Combat Statistics**:

Starbases have fixed combat statistics that scale with Weapons (WEP) technology:

- **Attack Strength (AS)**: 45 (base) + WEP scaling (10% per level)
- **Defense Strength (DS)**: 50 (base) + WEP scaling (10% per level)
- **Command Cost (CC)**: 0 (facilities don't consume command)
- **Command Rating (CR)**: 0 (facilities can't lead squadrons)

**Combat Participation**:

Starbases participate in detection for ALL combat phases occurring in their system:

- **Space Combat** ([Section 7.3](07-combat.md#73-space-combat)): Starbases contribute detection capability but are screened from combat (cannot fight or be targeted)
- **Orbital Combat** ([Section 7.4](07-combat.md#74-orbital-combat)): Starbases detect AND fight as primary orbital defenders using their full AS/DS values

**Rationale**: Advanced sensors provide system-wide detection support; physical weapons only engage threats to your colony itself.

**Combat Architecture**: Starbases participate in combat as `CombatFacility` units (parallel to squadron-based ships), enabling future expansion of defensive facilities (ground batteries as combat units, orbital defense platforms, etc.).

**Economic Benefits**:

Starbases boost both **population growth rate** and **industrial production output** by 5% per operational starbase, with each benefit capped at 15% maximum (three starbases).

**Population Growth Bonus**:

- +5% per operational starbase, max +15% (3 starbases)
- Example: Natural birthrate 2% → With 3 starbases: 2% × (1 + 0.15) = 2.3%
- Applied in population growth formula in [Section 3.5](03-economy.md#35-population-growth)

**Industrial Production Bonus**:

- +5% per operational starbase, max +15% (3 starbases)
- Applied to IU component of GCO formula: `IU × EL_MOD × CST_MOD × (1 + PROD_GROWTH + STARBASE_BONUS)`
- Example: 100 IU base output → With 3 starbases: 100 × (1 + 0.15) = 115 output
- See [Section 3.1](03-economy.md#31-principles) for complete GCO formula

**Repair**:

Crippled starbases yield no benefits until you repair them. Repair costs 25% of original PP cost (75 PP) and requires 1 turn at a **Spaceport**.

**Important**: Starbase repairs use Spaceport infrastructure (not Shipyards) and **do NOT consume dock capacity**. This allows simultaneous starbase repair alongside ship construction without competition for dock space.

**Repair Mechanics**:
- **Facility**: Spaceport (facilities repair facilities)
- **Cost**: 75 PP (25% of 300 PP base cost)
- **Time**: 1 turn
- **Dock Usage**: None (does not compete with ship construction/repair)

### 2.4.7 Planetary Shields & Ground Batteries

Planetary Shields (PS) and Ground Batteries (GB) are planet based assets that provide an extra layer of defense to a player's colonies.

**Planetary Shields**:

Planetary Shields protect your colonies from orbital bombardment. With increasing Shield (SLD) levels, they have a higher probability of absorbing direct hits and become more powerful.

**Construction**: Requires SLD research (see [Section 4.4](04-research_development.md#44-shields-sld))  
**Cost**: Varies by SLD level  
**Limit**: One shield per colony  
**Upgrading**: Requires salvaging old shield (50% refund) and building new shield at higher SLD tier

For SLD research progression, absorption percentages, and shield DS values, see [Section 4.4](04-research_development.md#44-shields-sld).

You can rebuild shields within one turn if destroyed.

**Ground Batteries**:

Ground Batteries are static defense units positioned on your planet's surface. They serve as a deterrent against enemy fleets and support planetary defense during bombardment and invasion. They lob kinetic shells into orbit—technology and are low-tech cannons that are not upgraded by tech.

**Construction Time**: 1 turn  
**Quantity Limit**: No limit—you can build as many as you can afford  
**Technology**: Static stats, no WEP scaling

For bombardment mechanics and how shields/batteries interact, see [Section 7.5](07-combat.md#75-planetary-bombardment).

### 2.4.8 Planet-Breaker

Planet-Breakers (PB) are high-technology, late-game siege superweapons designed to shatter even the most heavily fortified colonies. These colossal warships mount weapons that completely bypass conventional planetary shield matrices—the ultimate answer to defensive stalemates.

**Technology & Construction Requirement**:

**Prerequisite**: CST 10 (see [Section 4.5](04-research_development.md#45-construction-cst))  
**Construction Cost**: 400 PP  
**Construction Time**: 1 turn  
**Construction Location**: Requires Shipyard

No additional research is required beyond the shipyard tech itself.

**Ownership Limit**:

You may construct and operate **no more than one Planet-Breaker per currently owned colony** (your homeworld counts as one colony).

If you lose a colony (conquered, abandoned, or destroyed), any Planet-Breaker assigned to it is immediately and permanently scrapped with no salvage value.

**Shield Penetration Mechanics**:

Planet-Breakers completely ignore planetary shields during bombardment (SLD 1–6 offer no protection). Their firepower is applied directly to ground batteries and other surface targets.

**Bombardment Operations**:

During planetary bombardment ([Section 7.5](07-combat.md#75-planetary-bombardment)):

- Resolve Planet-Breaker AS separately from conventional ships
- Planet-Breaker hits bypass shields entirely and strike ground batteries directly
- Conventional ships in the same Task Force are still subject to normal shield rolls

**Space Combat**:

Planet-Breakers use their normal combat statistics (AS 50, DS 20) in fleet battles. They are fragile for their cost and require strong escorts.

**Strategic Considerations**:

Planet-Breakers force defenders into a classic dilemma: invest in shields (useless vs. PBs) or mass ground batteries (effective vs. everything). They are the ultimate prize of late-game conquest and terraforming—the larger your empire, the more of these terrifying weapons you can field.

**Defensive Counters**:

- Destroy them in space before they reach orbit
- Focus fire—crippled Planet-Breakers lose their bombardment advantage and become priority targets (×2 weight when crippled)
- Conquer the enemy's core worlds to permanently strip their PB count

### 2.4.9 Space Marines & Armies

Space Marines are ferocious devil dogs that capture rival planets. They deploy in division sized units (MD) and never surrender or abandon one of their own.

You drop Marines on rival planets by troop transports during an invasion or blitz.

Armies (AA) garrison your colonies and eradicate invaders. Their orders are to take no prisoners and protect your colony at all cost.

Marines fight alongside your Army if garrisoned planet-side.

For ground combat mechanics, see [Section 7.6](07-combat.md#76-planetary-invasion-and-blitz).

## 2.5 Space Guilds

A vast decentralized network of trade, commerce, transport, industry, tech, and mining activities occur between and within your House colonies, facilitated by the Space Guilds. Most of this activity is abstracted away and occurs in the background of EC4X's strategic focus. Guild ships stealthily ply the jump lanes between colonies without interaction or communication with your military assets.

Numerous Space Guilds compete for business in unregulated, private capital markets. The Space Guilds are neutral non-player-characters (NPC) with zero loyalty to any House.

You contract the Guilds to provide various critical services to your House, most notably the transport of PTU and goods between colonies. Space Guilds are also known to deal in the black arts of subversion and subterfuge, for a price. They will not freely leak intelligence.


