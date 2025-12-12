# 2.0 Game Assets

## 2.1 Star Map

The star-map consists of a 2D hexagonal grid, each a flat-top hex that contains a solar system, interconnected throughout by procedurally generated jump lanes. The map is sized by rings around the center hub: one ring per player plus the center hub system at ring 0. For example, a 4-player game has 4 rings (rings 1-4) plus the center hub at ring 0. The center hub is guaranteed to have six lanes of travel.

Solar systems have special traits and are procedurally generated. They are filled with planets, moons, and gas giants that are variable in their suitability for colonization and production.

**Jump Lane Classes**

There are three classes of jump lanes that determine which ship types can traverse them:

<!-- LANE_DISTRIBUTION_START -->

- **Major lanes** (50% of all lanes): Allow all ship types including crippled ships, ETACs, and troop transports

- **Minor lanes** (35% of all lanes): Block crippled ships only; all other ships may pass

- **Restricted lanes** (15% of all lanes): Block crippled ships, ETACs, and troop transports
  
  <!-- LANE_DISTRIBUTION_END -->

This distribution ensures 85% of lanes allow colonization ships through, reducing strategic bottlenecks while maintaining tactical complexity. Movement across the lanes is explained in [Section 6.1](operations.md#61-jump-lanes).

**Hub Connectivity**

The hub is guaranteed to have six jump lanes connecting it to the first ring, making it an important strategic asset. Hub lanes use the same distribution as the rest of the map (mixed lane types), preventing predictable "rush-to-center" gameplay. Controlling the hub grants significant strategic power but requires careful fleet composition.

**Homeworld Placement**

<!-- HOMEWORLD_PLACEMENT_START -->

Player homeworlds are placed throughout the map using distance maximization algorithms. The generator ensures each homeworld is as far as strategically possible from rival home systems, creating balanced starting positions while introducing natural asymmetry in the tactical landscape. Unlike traditional hex-ring maps where homeworlds are predictably on the outer edge, this system allows homeworlds on any ring for unpredictable, varied starting scenarios.

Each homeworld is guaranteed to have exactly 3 **Major lanes** connecting it to adjacent systems, ensuring reliable colonization paths and fleet movement from the start.

<!-- HOMEWORLD_PLACEMENT_END -->

## 2.2 Solar Systems

Solar systems contain various F, G, K, and M class stars orbited by at least one terrestrial planet, suitable for colonization and terraforming. Systems without terrestrial planets are not charted and of no consequence to your task.

Roll on the planet class and system resources tables below to determine the attributes for each hex on the star-map, excluding homeworlds.

Each newly established colony begins as Level I and has potential to develop into the max Population Unit (PU) for that planet. Move colonists from larger colonies to smaller colonies to increase population growth over the natural birth rate.

Advances in terraforming tech allow your planets to upgrade class and living conditions. For terraforming research and costs, see [Section 4.6](research_development.md#46-terraforming-ter).

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

For the relationship between PU and PTU, including economic implications and formulas, see [Section 3.1](economy.md#31-principles).

**System Resources Table**

| Modified Roll 1D10 | Raw Materials |
|:------------------:| ------------- |
| 0                  | Very Poor     |
| 2, 3               | Poor          |
| 4 - 7              | Abundant      |
| 8, 9               | Rich          |
| 10+                | Very Rich     |

For how Raw Materials affect colony economic output, see the RAW INDEX table in [Section 3.1](economy.md#31-principles).

## 2.3 Military

### 2.3.1 Space Force Ships

The base game includes a number of imperial classed space combatants listed in [Section 10.1](reference.md#101-space-force-wep1).

### 2.3.2 Spacelift Command

Spacelift Command provides commerce and transportation services supporting your House's expansion efforts. You own these assets, and senior Space Force officers command them. Loyal House citizens crew and operate the units.

Spacelift assets have no offensive weapons capability—unescorted units are easily destroyed by rival forces.

Spacelift Command attributes are listed in [Section 10.3](reference.md#103-spacelift-command-wep1).

#### 2.3.2.1 Spaceports

Spaceports are large ground based facilities that launch heavy-lift ships and equipment into orbit. They require one month (one turn) to build and have five construction docks at base capacity, allowing up to five simultaneous ship construction projects planet-side.

**Construction Cost**: 20 PP  
**Construction Time**: 1 turn  
**Base Capacity**: 5 docks  
**Capacity Scaling**: Dock capacity increases with CST tech (see [Section 4.5](research_development.md#45-construction-cst))

**Planet-side Ship Construction**: Ships built at spaceports incur a **100% PP cost penalty** due to orbital launch requirements. See [Section 5.2](economy.md#52-planet-side-construction) for construction rules.

**Facility Repair**: Spaceports handle repairs for facility-class units (Starbases). These repairs do NOT consume dock capacity, allowing simultaneous facility repair and ship construction.

**Ship Repair**: Spaceports cannot repair ships - only Drydocks can repair ship-class units.

#### 2.3.2.2 Shipyards

Shipyards are gateways to the stars—large bases constructed in orbit that require a spaceport to build over a period of two turns.

The majority of your ship construction occurs at these important facilities.

**Construction Cost**: 60 PP
**Construction Time**: 2 turns
**Prerequisite**: Requires operational Spaceport
**Base Capacity**: 10 docks
**Capacity Scaling**: Dock count increases with Construction (CST) technology (see [Section 4.5](research_development.md#45-construction-cst))

Shipyards are equipped with construction docks and are fixed in orbit. Build multiple yards to increase your construction capacity at the colony.

**Orbital Ship Construction**: Ships built at shipyards use standard PP costs with no penalties. See [Section 5.4](economy.md#54-orbital-construction).

**Ship Repairs**: Shipyards cannot repair ships - ship repairs require Drydocks (see [Section 2.3.2.3](#23223-drydocks)).

#### 2.3.2.3 Drydocks

Drydocks are specialized orbital facilities dedicated to ship repair operations. These massive maintenance stations are constructed in orbit and require a spaceport to build over a period of two turns.

**Construction Cost**: 150 PP
**Construction Time**: 2 turns
**Prerequisite**: Requires operational Spaceport
**Base Capacity**: 10 docks
**Capacity Scaling**: Dock count increases with Construction (CST) technology (see [Section 4.5](research_development.md#45-construction-cst))

Drydocks are repair-only facilities and cannot construct ships. They are fixed in orbit alongside shipyards. Build multiple drydocks to increase your repair capacity at the colony.

**Ship Repairs**: Only drydocks can repair ships. Repair costs 25% of ship's original PP cost and completes in 1 turn. See [Section 5.5](economy.md#55-orbital-repair).

**Construction**: Drydocks cannot construct ships - ship construction requires Shipyards or Spaceports.

#### 2.3.2.4 Environmental Transformation And Colonization (ETAC)

ETACs plant a seed by establishing colonies on uninhabited planets. They may be reused but require PTU reload. Empty ETACs are auto-reloaded when positioned at House owned colonies.

**Carry Limit (CL)**: 1 PTU at STL I, scales with Strategic Lift (STL) technology  
**Lane Restrictions**: Blocked by Restricted lanes (15% of lanes)  
**Combat**: Zero offensive/defensive capability

You must load ETACs with colonists before departure. For STL capacity progression, see [Section 4.9](research_development.md#49-strategic-lift-stl).

#### 2.3.2.5 Troop Transports

Troop Transports are specialized ships that taxi Space Marine divisions between solar systems, along with their required combat gear, armored vehicles, and ammunition.

**Carry Limit (CL)**: 1 Marine Division (MD) at STL I, scales with Strategic Lift (STL) technology  
**Lane Restrictions**: Blocked by Restricted lanes (15% of lanes)  
**Combat**: Zero offensive/defensive capability

For STL capacity progression, see [Section 4.9](research_development.md#49-strategic-lift-stl).

### 2.3.3 Squadrons

Your Space Force is organized by squadrons. Each squadron is commanded by a flagship with a Command Rating (CR) that accommodates ships with a Command Cost (CC) summing to less than or equal to the CR. This enables you to tactically group various classes of ships to balance combat effectiveness.

Squadrons fight as a unit and die as a unit. A squadron's total AS and DS values constitute a sum of all the ships under a flagship's command (including itself).

In non-hostile systems, you can reassign ships in a squadron to an already existing squadron if the new flagship's CR allows. Squadrons can constitute a solo flagship.

You can only commission squadrons in systems with a functioning shipyard.

**Command Rating Enhancement**: CR can be increased through Command (CMD) research. See [Section 4.10](research_development.md#410-command-cmd) for CMD progression.

### 2.3.4 Fleets

You group squadrons together into fleets for traversing jump lanes. You can join or split fleets (creating new fleets) for strategic purposes in any non-hostile system. There is no limit to the number of squadrons you assign to a fleet.

### 2.3.5 Task Force

A Task Force is temporary grouping of squadrons organized for combat. After hostilities cease, the task force is disbanded and surviving squadrons return to their originally assigned fleets.

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

For FD research progression and capacity multipliers, see [Section 4.12](research_development.md#412-fighter-doctrine-fd). For economic and strategic considerations, see [Section 3.6](economy.md#36-fighter-squadron-economics).

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

For Advanced Carrier Operations (ACO) research, see [Section 4.13](research_development.md#413-advanced-carrier-operations-aco).

**Combat Mechanics**:

Fighter squadrons based at your colony automatically participate in orbital defense (see [Section 7.4](operations.md#74-orbital-combat)). Carrier-based fighters participate in space combat with their carrier's task force.

Each FS contributes:

- **Attack Strength (AS)**: 3
- **Defense Strength (DS)**: 1

Fighters are fragile but cost-effective. A mature colony can field dozens of squadrons, making direct assault prohibitively expensive.

### 2.4.2 Scouts

Scouts are fast, stealthy reconnaissance ships that gather intelligence on enemy fleet compositions, colony defenses, and strategic positions.

**Detection Mechanics**:

Enemy colonies equipped with Electronic Intelligence (ELI) technology can detect Scouts. Detection probability depends on:

- Defender's ELI level
- Number of Scouts in system (mesh network effect)
- Presence of Starbases (+2 ELI modifier)

**Scout Detection Table**

<!-- SCOUT_DETECTION_TABLE_START -->

Detection compares total effective ELI (including modifiers) against number of Scouts present:

| Defender ELI | 1 Scout | 2 Scouts | 3+ Scouts |
|:------------:|:-------:|:--------:|:---------:|
| ELI 1        | 1-2     | 1-3      | 1-4       |
| ELI 2        | 1-3     | 1-4      | 1-5       |
| ELI 3        | 1-4     | 1-6      | 1-8       |
| ELI 4        | 1-6     | 1-8      | 1-10      |
| ELI 5        | 1-8     | 1-10     | 1-12      |

*Table shows detection threshold on 1D20. Roll equal or higher to detect.*

<!-- SCOUT_DETECTION_TABLE_END -->

**Mesh Network Effect**: Multiple Scouts in the same system improve detection resistance. The defender's effective ELI decreases as Scout count increases—Scout swarms are harder to detect than individual Scouts.

**Starbase Modifier**: Starbases add +2 to effective ELI level for detection rolls, representing superior sensor arrays and dedicated detection systems.

For ELI research progression, see [Section 4.8](research_development.md#48-electronic-intelligence-eli).

**Intelligence Gathering**:

Successfully undetected Scouts reveal:

- Fleet composition and squadron organization
- Colony defense strength (fighters, batteries, shields)
- Industrial capacity (IU count)
- Construction projects in progress

Detected Scouts are immediately destroyed.

### 2.4.3 Raiders

Raiders are specialized covert warfare vessels equipped with advanced cloaking systems. They conduct sabotage, intelligence gathering, and disruptive operations deep behind enemy lines.

**Cloaking Technology**:

Raider stealth capability is determined by Cloaking (CLK) research level. Higher CLK tiers significantly reduce detection probability.

**Detection Mechanics**:

Enemy colonies equipped with Electronic Intelligence (ELI) technology can detect Raiders. Detection rolls compare the Raider's CLK level against the defender's ELI level.

**Raider Detection Table**

<!-- RAIDER_DETECTION_TABLE_START -->

Detection compares Raider CLK vs. Defender ELI:

| ELI \ CLK Advantage | >10-12 | 7-9 | 4-6 | 1-3 | Equal | -1 to -3 | -4 to -6 | -7 to -9 | <-10 to -12 |
|:-------------------:|:------:|:---:|:---:|:---:|:-----:|:--------:|:--------:|:--------:|:-----------:|
| **Detection Roll**  | 1D3    | 1D4 | 1D6 | 1D8 | 1D10  | 1D12     | 1D16     | 1D20     | Auto-Fail   |

*Roll type determines detection threshold on 1D20. Example: 1D3 result is random number 1-3; if detection roll ≥ threshold, Raider is detected.*

<!-- RAIDER_DETECTION_TABLE_END -->

**Starbase Modifier**: Starbases add +2 to effective ELI level for detection rolls against Raiders.

**Example Detection Scenario**:

```
Defender Colony:
  ELI 3
  2 operational Starbases
  Starbase Modifier: +2
  Total Effective ELI: ELI 3 + 2 = ELI 5

Raider:
  CLK 4

ELI Advantage: ELI 5 - CLK 4 = +1
Detection Threshold: From table, use 1-3 range, so roll 1D8
Random Threshold Roll (1D8): Result is 5
Detection Roll (1D20): If the roll is 5 or higher, the Raider is detected
```

For CLK research progression, see [Section 4.7](research_development.md#47-cloaking-clk). For ELI research, see [Section 4.8](research_development.md#48-electronic-intelligence-eli).

**Mission Capabilities**:

Successfully undetected Raiders can:

- **Sabotage**: Destroy Industrial Units, reducing GCO
- **Infrastructure Damage**: Target spaceports, shipyards, or starbases
- **Intelligence**: Reveal detailed colony information beyond Scout capability
- **Assassination**: Eliminate colony governors or military commanders (advanced missions)

Detected Raiders are immediately destroyed.

**Strategic Considerations**:

Raiders are expensive, fragile, and require sustained CLK investment to remain effective. However, they create asymmetric advantages—a single successful Raider mission can cripple an enemy industrial world, potentially shifting strategic balance. The CLK vs. ELI arms race becomes critical in peer conflicts.

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

Starbases are equipped with ELI to counter spy Scouts and Raiders. Refer to the Scout Detection Table in [Section 2.4.2](#242-scouts) and Raider Detection Table in [Section 2.4.3](#243-raiders) respectively.

Starbases receive a **+2 ELI modifier** for all detection rolls, reflecting their superior sensor arrays and dedicated detection systems.

**Combat Statistics**:

Starbases have fixed combat statistics that scale with Weapons (WEP) technology:

- **Attack Strength (AS)**: 45 (base) + WEP scaling (10% per level)
- **Defense Strength (DS)**: 50 (base) + WEP scaling (10% per level)
- **Command Cost (CC)**: 0 (facilities don't consume command)
- **Command Rating (CR)**: 0 (facilities can't lead squadrons)

**Combat Participation**:

Starbases participate in detection for ALL combat phases occurring in their system:

- **Space Combat** ([Section 7.3](combat.md#73-space-combat)): Starbases contribute detection capability but are screened from combat (cannot fight or be targeted)
- **Orbital Combat** ([Section 7.4](combat.md#74-orbital-combat)): Starbases detect AND fight as primary orbital defenders using their full AS/DS values

**Rationale**: Advanced sensors provide system-wide detection support; physical weapons only engage threats to your colony itself.

**Combat Architecture**: Starbases participate in combat as `CombatFacility` units (parallel to squadron-based ships), enabling future expansion of defensive facilities (ground batteries as combat units, orbital defense platforms, etc.).

**Economic Benefits**:

Starbases boost both **population growth rate** and **industrial production output** by 5% per operational starbase, with each benefit capped at 15% maximum (three starbases).

**Population Growth Bonus**:

- +5% per operational starbase, max +15% (3 starbases)
- Example: Natural birthrate 2% → With 3 starbases: 2% × (1 + 0.15) = 2.3%
- Applied in population growth formula in [Section 3.5](economy.md#35-population-growth)

**Industrial Production Bonus**:

- +5% per operational starbase, max +15% (3 starbases)
- Applied to IU component of GCO formula: `IU × EL_MOD × CST_MOD × (1 + PROD_GROWTH + STARBASE_BONUS)`
- Example: 100 IU base output → With 3 starbases: 100 × (1 + 0.15) = 115 output
- See [Section 3.1](economy.md#31-principles) for complete GCO formula

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

**Construction**: Requires SLD research (see [Section 4.4](economy.md#44-shields-sld))  
**Cost**: Varies by SLD level  
**Limit**: One shield per colony  
**Upgrading**: Requires salvaging old shield (50% refund) and building new shield at higher SLD tier

For SLD research progression, absorption percentages, and shield DS values, see [Section 4.4](research_development.md#44-shields-sld).

You can rebuild shields within one turn if destroyed.

**Ground Batteries**:

Ground Batteries are static defense units positioned on your planet's surface. They serve as a deterrent against enemy fleets and support planetary defense during bombardment and invasion. They lob kinetic shells into orbit—technology and are low-tech cannons that are not upgraded by tech.

**Construction Time**: 1 turn  
**Quantity Limit**: No limit—you can build as many as you can afford  
**Technology**: Static stats, no WEP scaling

For bombardment mechanics and how shields/batteries interact, see [Section 7.5](combat.md#75-planetary-bombardment).

### 2.4.8 Planet-Breaker

Planet-Breakers (PB) are high-technology, late-game siege superweapons designed to shatter even the most heavily fortified colonies. These colossal warships mount weapons that completely bypass conventional planetary shield matrices—the ultimate answer to defensive stalemates.

**Technology & Construction Requirement**:

**Prerequisite**: CST 10 (see [Section 4.5](economy.md#45-construction-cst))  
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

During planetary bombardment ([Section 7.5](combat.md#75-planetary-bombardment)):

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

For ground combat mechanics, see [Section 7.6](combat.md#76-ground-combat).

## 2.5 Space Guilds

A vast decentralized network of trade, commerce, transport, industry, tech, and mining activities occur between and within your House colonies, facilitated by the Space Guilds. Most of this activity is abstracted away and occurs in the background of EC4X's strategic focus. Guild ships stealthily ply the jump lanes between colonies without interaction or communication with your military assets.

Numerous Space Guilds compete for business in unregulated, private capital markets. The Space Guilds are neutral non-player-characters (NPC) with zero loyalty to any House.

You contract the Guilds to provide various critical services to your House, most notably the transport of PTU and goods between colonies. Space Guilds are also known to deal in the black arts of subversion and subterfuge, for a price. They will not freely leak intelligence.

### 2.5.1 Capital Ship Salvage Operations

When a Great House loses industrial capacity and can no longer support its capital fleet, the Space Guilds step in to claim excess warships. The Guilds pay 50% of the original build cost in immediate currency, then refurbish and resell these vessels on the open market for profit.

**Capacity Formula**: Each house can maintain `max(8, floor(Total_House_IU ÷ 100) × 2)` capital squadrons. Capital ships are defined as vessels with Command Rating (CR) ≥ 7.

For detailed capacity rules and economic implications, see [Section 4.11](research_development.md#411-capital-ship-capacity).

**Enforcement**: When a house exceeds its capital squadron capacity (typically due to IU loss from colony damage, blockades, or territory loss), excess squadrons are immediately claimed by the Space Guilds. Priority for removal:

1. **Crippled flagships first** - Damaged vessels are easiest to claim
2. **Lowest Attack Strength (AS) second** - Among non-crippled ships, weakest vessels removed first

The house receives 50% of each ship's original build cost as salvage payment, credited to the house treasury.

**Strategic Implications**:

- You must maintain industrial capacity to support large fleets
- Losing colonies means losing fleet capacity
- Salvage payments soften the blow but don't fully compensate for ship loss
- Crippled ships are vulnerable to involuntary salvage
- Repair your crippled flagships quickly to avoid losing them

**Reference**: See [Table 10.5](reference.md#105-game-limits-summary) for complete squadron limit details.
