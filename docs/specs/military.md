# 2.0 Game Assets

## 2.1 Star Map

The star-map consists of a 2D hexagonal grid, each a flat-top hex that contains a solar system, interconnected throughout by procedural generated jump lanes. The map is sized by rings around the center hub, one per number of players.

The map takes inspiration from VBAM, and the 1st or 2nd edition campaign guides can be used to spawn a random map. The method is briefly explained below.

The center of the map is a special hub occupied by the last holdouts of the former imperial Empire. This system is heavily guarded by fighter squadrons and the home planet is fortified against invasion. The former Emperor has no offensive ships to speak of, which were scuttled by their crews at the height of the collapse. This is prime territory ripe for the taking. He who controls the hub holds great strategic power.

Solar systems have special traits and are procedural generated. They are filled with planets, moons, and gas giants that are variable in their suitability for colonization and production.

There are three classes of jump lanes: restricted, minor, and major. The hub is guaranteed to have six jump lanes connecting it to the first ring, making it an important strategic asset. Homeworlds on the outer ring will have three lanes. The number of lanes connecting the other hexes are randomly generated in accordance with VBAM. The class of all lanes are random.

Movement across the lanes is explained in [Section 6.1](operations.md#61-jump-lanes).

Each player's homeworld should be placed on the outer ring, as far as strategically possible from rival home system(s).

## 2.2 Solar Systems

Solar systems contain various F, G, K, and M class stars that are orbited by at least one terrestrial planet, suitable for colonization and terraforming. Otherwise systems are not charted and of no consequence to the task at hand.

Roll on the planet class and system resources tables below to determine the attributes for each hex on the star-map, excluding homeworlds.

Note that each newly established colony begins as Level I and has potential to develop into the max Population Unit (PU) for that planet. Move colonists from larger colonies to smaller colonies to increase population growth over the natural birth rate.

Advances in terraforming tech will allow planets to upgrade class and living conditions.

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

**System Resources Table**

| Modified Roll 1D10 | Raw Materials |
|:------------------:| ------------- |
| 0                  | Very Poor     |
| 2, 3               | Poor          |
| 4 - 7              | Abundant      |
| 8, 9               | Rich          |
| 10+                | Very Rich     |

## 2.3 Military

### 2.3.1 Space Force Ships

The base game includes a number of imperial classed space combatants listed in [Section 9.1](reference.md#91-space-force-wep1).

Feel free to create your own ships and races for asymmetrical warfare or narrative purposes.

### 2.3.2 Spacelift Command

The Spacelift Command provides commerce and transportation services in support of the House's expansion efforts. Assets are owned by the House and commanded by senior Space Force officers. Units are crewed and operated by loyal House citizens.

Spacelift assets have no offensive weapons capability, and un-escorted units are easily destroyed by rival forces. 

Spacelift Command attributes are listed in [Section 9.3](reference.md#93-spacelift-command-wep1).

#### 2.3.2.1 Spaceports

Spaceports are large ground based facilities that launch heavy-lift ships and equipment into orbit. They require one month (one turn) to build and have five docks available for planet-side ship construction.

#### 2.3.2.2 Shipyards

Shipyards are gateways to the stars. They are large bases constructed in orbit and require a spaceport to build over a period of two months (two turns).

The majority of ship construction and repair will occur at these important facilities.

Shipyards are equipped with 10 docks for construction and repair, and are fixed in orbit. Built multiple yards to increase construction capacity at the colony.

#### 2.3.2.3 Environmental Transformation And Colonization (ETAC)

ETACs plant a seed by establishing colonies on uninhabited planets. After use they are scrapped and used by the colony to begin the long terraforming process. 

ETACS have a Carry Limit (CL) of one Population Transfer Unit (PTU) and must be loaded with colonists.

#### 2.3.2.4 Troop Transports

Troop Transports are specialized ships that taxi Space Marine divisions between solar systems, along with their required combat gear, armored vehicles, and ammunition. They have a CL of one Marine Division (MD).

### 2.3.3 Squadrons

The Space Force is organized by squadrons. Each squadron is commanded by a flagship with a Command Rating (CR) that will accommodate ships with a Command Cost (CC) that sum to less than or equal to the CR. This enables players to tactically group various classes of ships to balance combat effectiveness.

Squadrons fight as a unit and die as a unit. A squadron's total AS and DS values constitute a sum of all the ships under a flagship's command (including itself).

In non-hostile systems, ships in a squadron can be reassigned to an already existing squadron if the new flagship's CR allows. Squadrons can constitute a solo flagship.

Squadrons are only commissioned in systems with a functioning shipyard.

### 2.3.4 Fleets

Squadrons are grouped together into fleets for the purpose of traversing jump lanes. Fleets are be joined or split off (creating new fleets) for strategic purposes in any non-hostile system. There is no limit to the number of squadrons assigned to a fleet.

### 2.3.5 Task Force

A Task Force is temporary grouping of squadrons organized for combat. After the cessation of hostilities the task force is disbanded and surviving squadrons return to their originally assigned fleets.

## 2.4 Special Units

### 2.4.1 Fighter Squadrons & Carriers

Fighters are small ships commissioned in Fighter Squadrons (FS) that freely patrol a system. They are based planet-side and never retreat from combat.

**Fighter Squadron Capacity:**

The maximum number of fighter squadrons a colony can support is determined by:

```
Max FS = floor(PU / 100) × FD Tech Level Multiplier
```

Where Fighter Doctrine (FD) Tech Level Multiplier is:
- FD I (base): 1.0x
- FD II: 1.5x  
- FD III: 2.0x

**Infrastructure Requirement:**

Colonies must have at least one operational Starbase per 5 fighter squadrons (round up) to commission and maintain fighter squadron capacity. Crippled Starbases do not count toward this requirement.

Starbases provide the logistical coordination, advanced maintenance facilities, and strategic communications necessary to field large fighter wings. However, once commissioned, fighter squadrons operate independently from distributed planetary bases and remain combat-effective even if Starbases are crippled or destroyed.

**Capacity Violations:**

A colony enters capacity violation when:
- Operational Starbase count falls below `ceil(Current FS / 5)`, OR
- Population loss reduces maximum capacity below current fighter squadron count

Common causes of capacity violations:
- Starbases destroyed or crippled in combat
- Population loss due to orbital bombardment
- Population transfer reducing colony PU below threshold
- Fighter Doctrine tech loss (rare, only via certain game events)

**Violation Grace Period:**

When a capacity violation occurs, existing fighter squadrons remain fully operational and combat-effective. The player has 2 turns to resolve the violation by:

**For Infrastructure Violations:**
- Repairing crippled Starbases
- Constructing new Starbases
- Disbanding excess fighter squadrons
- Relocating excess squadrons via carrier to another colony with available capacity

**For Population Capacity Violations:**
- Transferring population to the colony to increase PU
- Disbanding excess fighter squadrons
- Relocating excess squadrons via carrier to another colony with available capacity

If the violation is not resolved within 2 turns, the player must disband excess squadrons (oldest squadrons first) until capacity requirements are met. Disbanded squadrons provide no salvage value.

**Multiple Simultaneous Violations:**

A colony can suffer both infrastructure and population capacity violations simultaneously (e.g., Starbases destroyed AND population bombarded in the same engagement). The grace period applies to the total violation:

- Calculate required Starbase count: `ceil(Current FS / 5)`
- Calculate population capacity: `floor(PU / 100) × FD multiplier`
- Effective capacity = minimum of (Starbase capacity, population capacity)
- Excess squadrons = Current FS - Effective capacity
- Player has 2 turns to resolve regardless of violation type

**Capacity Calculation Examples:**

**Example 1: Infrastructure Violation**

A colony with 850 PU and Fighter Doctrine Level II can support:
```
floor(850 / 100) × 1.5 = 8 × 1.5 = 12 fighter squadrons
```
This requires 3 operational Starbases (12 FS / 5 = 2.4, rounded up).

If 2 of the 3 Starbases are crippled in combat:
- All 12 fighter squadrons remain operational and fight at full effectiveness
- The colony can only maintain 5 FS with 1 operational Starbase (5 FS / 5 = 1)
- The colony is in violation with 7 excess squadrons
- Player has 2 turns to repair Starbases or disband/relocate 7 squadrons

**Example 2: Population Capacity Violation**

A colony with 12 fighter squadrons, 3 operational Starbases, 850 PU, and FD II suffers orbital bombardment reducing population to 450 PU:
```
New capacity: floor(450 / 100) × 1.5 = 4 × 1.5 = 6 fighter squadrons
```

Infrastructure supports: 3 Starbases × 5 = 15 FS  
Population supports: 6 FS  
Effective capacity: min(15, 6) = 6 FS

- All 12 fighter squadrons remain operational during and after bombardment
- Colony is in violation with 6 excess squadrons (12 current - 6 capacity)
- Player has 2 turns to transfer population, disband, or relocate 6 squadrons
- Infrastructure is adequate (3 Starbases), so repairing Starbases won't help

**Example 3: Combined Violation**

A colony with 12 fighter squadrons, 3 operational Starbases, 850 PU, and FD II suffers severe bombardment:
- 2 Starbases crippled
- Population reduced to 450 PU

```
Infrastructure capacity: 1 Starbase × 5 = 5 FS
Population capacity: floor(450 / 100) × 1.5 = 6 FS
Effective capacity: min(5, 6) = 5 FS
```

- All 12 fighter squadrons remain operational
- Colony is in violation with 7 excess squadrons (12 current - 5 capacity)
- Player has 2 turns to address BOTH infrastructure and population issues
- Must repair/build Starbases AND/OR transfer population AND/OR disband/relocate squadrons

**Fighter Squadron Economics:**

- **Production Cost (PC)**: 15 PP per squadron
- **Construction Time**: 1 turn (planet-side only, requires colony industry)
- **Maintenance Cost**: 1 PP per turn per squadron
- **Construction Capacity**: Not limited by Spaceport docks; produced via distributed colony factories

Fighter squadrons cannot be constructed in orbit and do not benefit from CST tech levels for construction speed. However, colonies with higher IU can produce more fighters simultaneously based on available production points.

**Commissioning Requirements:**

To commission new fighter squadrons, a colony must:
1. Have available capacity: `Current FS < Max FS`
2. Meet infrastructure requirement: `Operational Starbases ≥ ceil((Current FS + New FS) / 5)`
3. Have sufficient population capacity: `floor(PU / 100) × FD ≥ (Current FS + New FS)`
4. Have sufficient treasury: `Available PP ≥ 15 × New FS`

Colonies in capacity violation cannot commission new fighter squadrons until the violation is resolved.

**Combat Characteristics:**

Fighter squadrons attack first in combat resolution, before capital ships engage. This represents their speed advantage and defensive intercept capability.

**Combat Initiative Order:**
1. Undetected Raiders (ambush advantage)
2. Fighter Squadrons (all fighters attack simultaneously)
3. Detected Raiders
4. Capital Ships (by squadron)

Because of their fast lightweight nature, fighters are considered to be in a permanent crippled combat state, but without a reduction in attack strength (AS). Fighter squadrons have reduced Defense Strength (DS) as reflected in their combat statistics.

Fighter squadrons based in a system never retreat from combat and fight to the last pilot.

**Carriers:**

Carriers transport fighter squadrons between systems and enable offensive fighter deployment beyond home colonies.

**Carrier Types and Capacity:**

| Carrier Type | Base Capacity | ACO II Capacity | ACO III Capacity |
|:------------:|:-------------:|:---------------:|:----------------:|
| CV           | 3 FS          | 4 FS            | 5 FS             |
| CX           | 5 FS          | 6 FS            | 8 FS             |

Carrier capacity is determined by the House's Advanced Carrier Operations (ACO) tech level. All carriers in the House fleet are upgraded immediately when ACO tech is researched.

**Carrier Deployment:**

Fighters aboard carriers do not participate in combat until deployed to a system. Deployment occurs during the fleet movement phase and requires the carrier to be in a non-hostile system or during the first round of combat in a hostile system.

Once deployed, fighters become planet-based assets and remain in the system when the carrier fleet departs. Deployed fighters count against the colony's maximum fighter squadron capacity and require the colony to meet infrastructure requirements.

If deploying fighters would violate the destination colony's capacity or infrastructure requirements, deployment is not permitted. Carriers must find an alternative colony with available capacity or the fighter squadrons remain aboard.

To retrieve fighters, carriers must return to the system and spend one full turn loading them. Fighters cannot be loaded while the system is under attack or contested.

Fighters destroyed in combat cannot be replaced except through normal construction at a colony with available capacity.

### 2.4.2 Scouts

Scouts (SC) are small drones outfitted with advanced sensors that assist with electronic warfare and information gathering. They are masters of Electronic Intelligence (ELI).

Scouts are able to counter Raiders ([Section 2.4.3](#243-raiders)) and rival spy Scouts.  Multiple ELI assigned to the same unit operate as a mesh network, and their ELI capability is merged and magnified.

Scouts and Starbases are responsible for detecting rival Scouts performing espionage activities. The effectiveness of detection is influenced by the composition of the detecting units(s), which may include mixed ELI levels.

For every turn that a spy Scout operates in unfriendly system occupied by rival ELI, the rival will roll on the Spy Detection Table below to determine if the spy Scout is detected *by each* fleet or Starbase(s). If the Scout is detected, it is destroyed. Rival units must contain at least one Scout or Starbase to detect.

**Step 1: Determine Effective ELI Level**

For a fleet with Scouts of different ELI tech levels:

1. Calculate the Weighted Average:
    - Sum the ELI tech levels of all Scouts in the fleet.
    - Divide by the total number of Scouts.
    - Round up to determine the initial effective ELI level.
2. Apply Dominant Tech Level Penalty:
    - If more than 50% of the Scouts are of a lower ELI tech level than the average (round up), reduce the effective ELI level by 1.
3. Mesh Network Modifier:
    - Multiple ELI Scouts form a mesh network, enhancing detection capabilities. Apply a modifier based on the number of Scouts from the table below:

| Number of Scouts | Mesh Network Modifier |
|:----------------:| --------------------- |
| 1                | NA                    |
| 2-3              | +1                    |
| 4-5              | +2                    |
| 6+               | +3 (maximum)          |

4. Final Effective ELI Level:
    - Combine the effective ELI level with the tech penalty and mesh network modifier to determine the final effective ELI level for the detection roll. The max is ELI5.

**Starbases operate as independent ELI units and receive a +2 ELI modifier against spy scouts.**

**Step 2: Randomized Detection Roll Process**

1. Compare the final effective ELI level of the detecting fleet or Starbase with the ELI level of the spy Scout.
2. Determine the base detection range from the table below.

**Spy Detection Table**

| \*Detect -> | ELI1   | ELI2   | ELI3   | ELI4   | ELI5  |
| -----------:|:------:|:------:|:------:|:------:|:-----:|
| Spy ELI1    | >11-13 | >6-8   | >2-4   | >0-2   | >0-1  |
| Spy ELI2    | >15-17 | >11-13 | >6-8   | >2-4   | >0-2  |
| Spy ELI3    | >17-19 | >15-17 | >11-13 | >6-8   | >2-4  |
| Spy ELI4    | >18-20 | >17-19 | >15-17 | >11-13 | >6-8  |
| Spy ELI5    | NA     | >18-20 | >17-19 | >15-17 | >11-3 |

3. Random Threshold Determination:
    - Roll 1D3 to randomly select a value within the range (e.g., for a range of >11-13, the roll could be 11, 12, or 13).
    - This introduces slight variability to the detection roll, adding an element of unpredictability.
4. Roll 1D20 for the detection attempt:
    - If the roll meets or exceeds the chosen threshold, the spy Scout is detected.

**Example 1: Fleet with Mixed ELI Tech**

```
Detecting Fleet:
    2 Scouts with ELI2
    3 Scouts with ELI4

Total Tech Levels: 2 + 2 + 4 + 4 + 4 = 16
Number of units: 5
Weighted Average: 16 / 5 = 3.2 (Round up) → ELI4

Dominant Tech Level Penalty: 
More than 50% of Scouts are ELI2 (lower tech, rounded up), so  reduce by 1 → ELI3

Mesh Network Modifier: +2 (for 4-5 Scouts)
Final Effective ELI Level: ELI3 + 2 = ELI5 (capped at ELI5)

Spy Scout:
    ELI3

Comparison: ELI5 vs. ELI3
Detection Range: From the table, use >11-13.
Random Threshold Roll (1D3): Result is 2, so the threshold is 12.
Detection Roll (1D20): If the roll is 12 or higher, the spy is detected.
```

**Example 2: Balanced Fleet**

```
Detecting Fleet:
    1 Scout with ELI1
    1 Scout with ELI3

Total Tech Levels: 1 + 3 = 4
Number of Scouts: 2
Weighted Average: 4 / 2 = 2 (Round up) → ELI2
Mesh Network Modifier: +1 (for 2-3 Scouts)
Final Effective ELI Level: ELI2 + 1 = ELI3

Spy Scout:
    ELI4

Comparison: ELI3 vs. ELI4
Detection Range: From the table, use >15-17.
Random Threshold Roll (1D3): Result is 1, so the threshold is 15.
Detection Roll (1D20): If the roll is 15 or higher, the spy is detected.
```

### 2.4.3 Raiders

The Raider (RR) is the most advanced ship in the arsenal, outfitted with cloaking technology. They are expensive to R&D and commission, but are a significant factor on the first round of space combat against enemy fleets where they gain a surprise or ambush advantage.

Fleets that include Raiders are fully cloaked.

Crippled Raiders lose their cloaking ability until repaired.

**Raider Detection:**

Starbases and Scouts have a chance to counter against cloaked fleets. Within this context "units" refer to either fleets containing Scouts or Starbases.

Before combat, every ELI enabled unit joining the battle space will detect for Raiders. The simplified pseudo-code looks like this:

```
for each eli_unit in player1_units:
    for each clk_fleet in player2_fleets:
            rogue = highest rated CLK in clk_fleet
            eli_unit rolls for detection on rogue
            if success then break
    end
end
```

**Step 1: Determine Effective ELI Level**

Determine the effective ELI level following the same method from Step 1 in [Section 2.4.2](#242-scouts).

**Step 2: Determine Detection Threshold**

Compare the final effective ELI level with the CLK level of the Raider unit:
- If the ELI level is 2+ levels higher than the CLK level, use the lower bound detection threshold from the table below.
- If the ELI level is equal to or only 1 level higher than the CLK level, introduce the Random Threshold Roll (1D3) to add unpredictability.
- If the ELI level is lower than the CLK level, use the higher bound threshold, reflecting the difficulty of detection.

**Detection Table (With Random Threshold Roll)**

| Detect | CLK1   | CLK2   | CLK3   | CLK4   | CLK5   |
| ------ |:------:|:------:|:------:|:------:|:------:|
| ELI1   | >14-16 | >17-19 | NA     | NA     | NA     |
| ELI2   | >10-12 | >14-16 | >17-19 | NA     | NA     |
| ELI3   | >6-8   | >10-12 | >14-16 | >17-19 | NA     |
| ELI4   | >3-5   | >6-8   | >10-12 | >14-16 | >17-19 |
| ELI5   | >1-3   | >3-5   | >6-8   | >10-12 | >14-16 |

**Random Threshold Roll (1D3) Application**:

1. If the detection scenario uses a range (e.g., >10-12), roll 1D3 to determine the exact threshold value within the range.
    - For example, if the range is >10-12, roll 1D3:
    - Result 1: Threshold is 10
    - Result 2: Threshold is 11
    - Result 3: Threshold is 12
2. This random element only applies when the ELI level is equal to or one level higher than the CLK level, introducing variability in uncertain detection scenarios.

**Step 3: Make the Detection Roll**

1. Roll 1D20 for the detection attempt.
2. If the roll meets or exceeds the chosen threshold (from the fixed value or random roll), the Raider is detected.
3. If the roll is below the threshold, the Raider remains undetected and retains its stealth.

**Example 1: High-Tech ELI Fleet Detecting a Low-Tech Raider**

```
Detecting Fleet:
  3 Scouts with ELI5

Final Effective ELI Level: ELI5 (after applying mesh network and no penalties)

Raider:
CLK2

Comparison: ELI5 vs. CLK2
Detection Threshold: From the table, the fixed threshold is >3-5.
Random Roll Not Applied (since ELI5 is significantly higher).
Detection Roll (1D20): If the roll is 3 or higher, the Raider is detected.
```

**Example 2: Uncertain Detection Scenario with Random Threshold Roll**

```
Detecting Fleet:
  1 Scout with ELI3
  1 Scout with ELI4

Total Tech Levels: 3 + 4 = 7
Number of Scouts: 2
Weighted Average: 7 / 2 = 3.5 (Round up) → ELI4
Mesh Network Modifier: +1 (2 Scouts)
Final Effective ELI Level: ELI4 + 1 = ELI5

Raider:
  CLK4

Comparison: ELI5 vs. CLK4
Detection Threshold: From the table, use >10-12.
Random Threshold Roll (1D3): Result is 2, so the threshold is 11.
Detection Roll (1D20): If the roll is 11 or higher, the Raider is detected.
```

### 2.4.4 Starbases

Starbases (SB) are powerful orbital fortresses that facilitate planetary defense and economic development via ground weather modification and advanced telecommunications.

Starbases require three months (three turns) to construct and require a shipyard. They remain in orbit and do not move out of their home solar systems.

Units are equipped with ELI to counter spy Scouts and Raiders. Refer to the Spy Detection Table in [Section 2.4.2](#242-scouts) and Raider Detection Table in [Section 2.4.3](#243-raiders) respectively.

Starbases boost the population growth-rate and Industrial Units (IU) of a colony by 5% every turn, up to a max of 15% (three Starbases).

Example: under normal conditions the natural birthrate of a colony is 2%. With three Starbases, the rate is:

```
2% * (1 + (0.05 * 3)) = 2.3% 
```

Crippled Starbases do not yield benefits until they are repaired.

### 2.4.7 Planetary Shields & Ground Batteries

Planetary Shields (PS) and Ground Batteries (GB) are planet based assets that provide an extra layer of defense to a player's colonies.

Planetary Shields protect your colonies from orbital bombardment. With increasing SLD levels they have a higher probability of absorbing direct hits, and also become more powerful.

Upgrading a Planetary Shield to a new SLD level requires salvaging the old shield and replacing it with a new one. A Planet shall not have more than one shield, and shields can be rebuilt within one turn.

Ground Batteries are static defense units positioned on the planet’s surface. They serve as a deterrent against enemy fleets and support planetary defense during bombardment and invasion. They lob kinetic shells into orbit and are not upgraded by technology and research.

Ground Batteries are the only units that are constructed in the span of a single turn, and colonies can build them to no limit.

### 2.4.8 Planet-Breaker

Planet-Breakers (PB) are high technology, late-game ships that penetrate planetary shields.

TODO: Develop this further. Do we need a specific tech or just a ship, or both?

### 2.4.9 Space Marines & Armies

Space Marines are ferocious devil dogs that capture rival planets. They deploy in division sized units (MD) and will never surrender or abandon one of their own.

Marines are dropped on rival planets by troop transports during an invasion or blitz.

Armies (AA) garrison your colonies and eradicate invaders. Their orders are to take no prisoners and protect the colony at all cost.

Marines fight alongside the Army if garrisoned planet-side.

## 2.5 Space Guilds

A vast decentralized network of trade, commerce, transport, industry, tech, and mining activities occur between and within House colonies. Most of this activity is abstracted away and occurs in the background of EC4X's strategic focus. Commercial civilian ships freely ply the jump lanes between colonies.

Numerous Space Guilds compete for business in unregulated, private capital markets.

The Guilds are contracted to provide various critical services to the House, most notably the transport of PTU and goods between colonies. Space Guilds are also known to deal in the black arts of subversion and subterfuge, for a price.


