# EC4X Specification v0.1

Written by Mason A. Green

In memory of Jonathan F. Pratt.

Contributors:

- Matthew Potter

# Introduction

EC4X is an asynchronous turn based wargame of the classic eXplore, eXpand, eXploit, and eXterminate (4X) variety.

Upstart Houses battle over a small region of space to dominate usurpers and seize the imperial throne. Your role is to serve as House Duke and lead your people to greatness. 

The game begins at the dawn of the third imperium in the year 2001. Each turn comprises one month of a thirteen month [Terran Computational Calendar](<https://www.terrancalendar.com/> "Terran Computational Calendar"). 

Turns cycle as soon as all players have completed their turns, or generally a maximum of one day In Real Life (IRL) time. EC4X is intentionally slow burn.

EC4X is intended to facilitate remote play between friends over email or local tabletop play. Future releases will be server/client based. EC4X is a flexible framework; adapt it to your own requirements.

EC4X pays homage and is influenced by the following great titles:

- Esterian Conquest (EC)
- Victory by Any Means (VBAM)
- Empire of The Sun (EOS)
- Space Empires 4X
- Solar Starfire
- Stellar Conquest
- Fractal, Beyond the Void

Although not required, it is highly recommended to purchase physical copies of these classics to fully appreciate the art. Dive deep.

Esterian Conquest was an obscure bulletin board system (BBS) door game from the early 1990's that inspired this project. EC is a gem, and great times were had battling friends, family, and anonymous players over the phone lines on slow noisy modems. Graphics were crude but the ANSI art was fantastic. The early 1990's was a simple time, just before the internet blew up and super computers landed in all of our pockets. EC turns progressed once a day and most of the strategic planning occurred in one's imagination offline. Players eagerly awaited each new day's battle reports, and games would last several weeks to several months. Maps and reports were printed on dot matrix printers and marked up with pencil to no end. The times were good. That era is long gone but tabletop wargaming is still alive and well in 2024. EC4X is an attempt to recapture some of that magic.

While not intended to be an accounting exercise, there is enough complexity in EC4X to allow for dynamic strategic decision making and surprising outcomes.

The background narrative of EC4X is wide open and only limited by the scope of your imagination.

## Table of Contents

1. [How to Play](#10-how-to-play)
2. [Game Assets](#20-game-assets)
3. [Economics](#30-economics)
4. [R&D](#40-research--development)
5. [Construction](#50-construction)
6. [Movement](#60-movement)
7. [Combat](#70-combat)
8. [Diplomacy](#80-diplomacy--espionage)
9. [Game Data Tables](#90-data-tables)

# 1.0 How to Play

## 1.1 Prestige

Victory in EC4X is achieved through the accumulation of prestige, which is the ultimate measure of a House's dominance. Here are some strategic pathways to ascend to the throne of Emperor:

- Engage in total warfare to annihilate the military assets of your rivals.
- Seize homeworlds and colonies through planetary conquest.
- Break the spirit of your adversaries, compelling them to surrender.
- Blend military might with espionage, subversion, and cunning to outfox your foes.
- Focus on economic growth and population expansion, using prosperity to dominate.
- Be the last man standing.
- Adopt a hybrid strategy, employing a mix of all the above.

Every action in the game influences your House's prestige. Military victories directly enhance it, a prosperous and growing economy strengthens it, and technological advancements demonstrate your House's cunning, all of which elevate your standing.

Poor colony management will tarnish your House's legacy, while over-exposure to covert operations by rivals can lead to public disgrace.

Flexibility and strategic foresight are your greatest tools in the quest for power. Use every resource and opportunity the game provides to crush your rivals and ensure the dominance of your House.

Players start the game with 50 prestige points.

If a House's prestige drops and stays below zero for three consecutive turns, the Duke is forced surrender to a rival House.

A table of prestige values is listed in [Section 9.4](#94-prestige).

## 1.2 Game Setup

At the start of a game, players will agree upon and designate a game moderator. The moderator's function is to collect player turn orders, update the master game database, and reissue updated game data back to players at the beginning of each turn. Software tools will be provided to make this a smooth process and maintain fog of war. The moderator would have to go out of their way to cheat, and deconstructing and analyzing the game data would not be an enjoyable task. Regardless, choose a game moderator with integrity. EC4X is intended to be played among friends.[^1]

[^1]: Future iterations of the game will allow for a server/client model, but not everyone will want to setup a dedicated server. Encrypting the game data is also a feature to be integrated.

Communicating with other players over email or in a dedicated chat room is recommended. There are plenty to choose from.

Generate a star-map as described in [Section 2.1](#21-star-map) for the selected number of players. Resources will be provided in the GitHub repo to spawn a map.

Players start the game with one homeworld (An Abundant Eden planet, Level V colony with 840 PU), 420 production points (PP) in the treasury, one spaceport, one shipyard, one fully loaded ETAC, a Light Cruiser, two Destroyers, and two Scouts. The tax rate is set to 50% by default.

Tech levels start at: EL1, SL1, CST1, WEP1, TER1, ELI1, and CIC1.

## 1.3 Turns

Each turn comprises four phases

1. Income phase
2. Command phase
3. Conflict phase
4. Maintenance phase

### 1.3.1 Income Phase

At the beginning of each turn, all economic factors ([Section 3](#30-economics)) are recalculated and production points deposited in house treasuries. This accounts for population growth for each colony, construction, maintenance costs, taxes, R&D, etc. House prestige points are recalculated and updated. This will be completed by the game moderator using blind software tools and maintained in a master game database.

Updated player databases, unique to each House, are reissued by the game moderator for the new turn. Various tools and database formats can be used to perform this step, including Excel or client game software.

Players receive new reports that reflect updated economics and the outcome of orders issued in the previous turn. This can be achieved through email, on a server, or locally on a laptop for tabletop play.

In the new turn, players decide which construction orders to place and where to invest production points in R&D, industry, terraforming, population movement, espionage, and savings ([Section 3.8](#38-expenditures)). The tax rate can be changed in this phase. Player local databases are updated accordingly.

### 1.3.2 Command Phase

In the command phase, players issue fleet orders ([Section 6.2](#62-fleet-orders)) and make strategic decisions around asset management. Players have the opportunity change diplomatic state ([Section 8.1](#81-diplomacy)) in relation to rival Houses.

Players send their locally updated game database back to the game moderator for turn processing.

### 1.3.3 Conflict Phase

In the conflict phase the game moderator will collect player databases and update the master database with player inputs, via software tools.

Game software will resolve new player orders including movement, colonization, exploration, and combat. Espionage activities will be conducted and outcomes determined.

### 1.3.4 Maintenance Phase

In the maintenance phase, the game software will update the master game database with the outcomes from the conflict phase. New construction orders will be processed, along with investments in R&D, terraforming, Space Guild services, industry, etc.

Player databases will be updated and customized reports issued for each player. Players have their own unique database, blind to the activities of other players.

# 2.0 Game Assets

## 2.1 Star Map

The star-map consists of a 2D hexagonal grid, each a flat-top hex that contains a solar system, interconnected throughout by procedural generated jump lanes. The map is sized by rings around the center hub, one per number of players.

The map takes inspiration from VBAM, and the 1st or 2nd edition campaign guides can be used to spawn a random map. The method is briefly explained below.

The center of the map is a special hub occupied by the last holdouts of the former imperial Empire. This system is heavily guarded by fighter squadrons and the home planet is fortified against invasion. The former Emperor has no offensive ships to speak of, which were scuttled by their crews at the height of the collapse. This is prime territory ripe for the taking. He who controls the hub holds great strategic power.

Solar systems have special traits and are procedural generated. They are filled with planets, moons, and gas giants that are variable in their suitability for colonization and production.

There are three classes of jump lanes: restricted, minor, and major. The hub is guaranteed to have six jump lanes connecting it to the first ring, making it an important strategic asset. Homeworlds on the outer ring will have three lanes. The number of lanes connecting the other hexes are randomly generated in accordance with VBAM. The class of all lanes are random.

Movement across the lanes is explained in [Section 6.1](#61-jump-lanes).

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

The base game includes a number of imperial classed space combatants listed in [Section 9.1](#91-space-force-WEP1).

Feel free to create your own ships and races for asymmetrical warfare or narrative purposes.

### 2.3.2 Spacelift Command

The Spacelift Command provides commerce and transportation services in support of the House's expansion efforts. Assets are owned by the House and commanded by senior Space Force officers. Units are crewed and operated by loyal House citizens.

Spacelift assets have no offensive weapons capability, and un-escorted units are easily destroyed by rival forces. 

Spacelift Command attributes are listed in [Section 9.3](#93-spacelift-command-WEP1).

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

There is no limit to the number of fighter squadrons deployed in a home system.

Because of their fast lightweight nature, fighters are considered to be in a crippled combat state, but without a reduction in attack strength (AS).

Carriers (CV) transport fighter squadrons between systems. Standard carriers hold up to three; Super Carriers (CX) hold up to five.

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

# 3.0 Economics

Reckless fiat monetary policy left the former Empire in ruins. Demagoguery, excessive money printing, deficit spending, out of control socialist entitlements, and simple greed by bureaucratic elites led directly to revolution and collapse. The Empire cannibalized itself from the inside out. As Duke your obligation is to rebuild from the ashes and lead your House to prosperity. 

The standard unit of account in EC4X the Production Point (PP).

The economic power of a House is fueled by productivity, industrial capacity, and technological growth. Strategic decisions around taxation, industrial investment, and research & development (R&D) will directly impact a player's economic output and military strength.

Production points settle near instantaneously on the inter-dimensional Phoenix network. (All comms and data transfers are instantaneous).

## 3.1 Principles

**Population Unit (PU)**: Represents a measure of economic production rather than raw population size.

**Population Transfer Unit (PTU)**: A quantity of people and their associated cost of cargo and equipment required to colonize a planet. One PTU is approximately 50k souls. 

The relationship between PTU and PU is exponential. As the population grows the laws of diminishing returns take effect and the amount of production generated per individual is reduced. People are doing less work while the colony continues to slowly gain wealth. Think of gains in efficiency, productivity, and quality of life. 

This model is dis-inflationary; inflation asymptotically approaches zero over time.

A high PTU to PU ratio is an advantage when transferring colonists from larger planets to smaller planets. The mother-colony is able to contribute a relatively large number of people to the new colony without a significant loss of production to itself. This incentives expanding population across newly acquired planets.

The equations (in Python) for converting PU to PTU:

```
  PTU = pu - 1 + np.exp(0.00657 * pu)
```

Code for converting PTU back to PU:

```
import numpy as np
from scipy.special import lambertw

PTU = 100000 #example

def logsumexp(x):
    c = x.max()
    return c + np.log(np.sum(np.exp(x - c)))

x = np.float64(657*(PTU + 1)/100000)

pu = -100000/657*lambertw((657*np.exp(x - logsumexp(x)))/100000) + PTU + 1
```

An Excel spreadsheet is included in the GitHub 'assets' folder to visualize the relationship. You need to have "Python in Excel" enabled for Excel. TODO: standalone Python scripts will be provided in the repo.

![Alt text](https://github.com/greenm01/ec4x/blob/main/assets/pu_to_ptu.png)
![Alt text](https://github.com/greenm01/ec4x/blob/main/assets/ptu_to_pu.png)

**Gross Colony Output (GCO)**: The total economic output of a colony, expressed in production points. GCO is determined by the productivity of the colony, industrial investments, resource availability, and technological enhancements.

```
GCO = (PU × RAW_INDEX) + (IU × EL_MOD × (1 + PROD_GROWTH))
```

Where:
- PU: Population Units of the colony
- RAW_INDEX: Resource quality index based on the solar system's mineral abundance. 
- IU: Industrial Units at the colony
- EL_MOD: Economic Level Modifier, based on the colony's EL tech level
- PROD_GROWTH: Productivity growth rate influenced by the tax rate

**RAW INDEX Table**

| RAW       | Eden | Lush | Benign | Harsh | Hostile | Desolate | Extreme |
| --------- |:----:|:----:|:------:|:-----:|:-------:|:--------:|:-------:|
| Very Poor | 60%  | 60%  | 60%    | 60%   | 60%     | 60%      | 60%     |
| Poor      | 80%  | 75%  | 70%    | 65%   | 64%     | 63%      | 62%     |
| Abundant  | 100% | 90%  | 80%    | 70%   | 68%     | 66%      | 64%     |
| Rich      | 120% | 105% | 90%    | 75%   | 72%     | 69%      | 66%     |
| Very Rich | 140% | 120% | 100%   | 80%   | 76%     | 72%      | 68%     |

Look up the Raw Material classification of your colony's system in the RAW column, and cross index with the planet's habitable conditions.

**Gross House Output (GHO)**: The sum total of all colony GCO.

## 3.2 Taxation and Productivity Growth

Tax policy is a critical lever for managing the economy. The Tiered Taxation System links the tax rate directly to productivity growth, impacting economic output and House prestige [Section 9.4](#94-prestige).

The baseline productivity growth (PROD_GROWTH) rate is 3%.

### Tiered Taxation Table

| Tax Rate | Effect on Productivity Growth | Effect on NCV (Tax Revenue) | Prestige Impact                     |
| -------- | ----------------------------- | --------------------------- | ----------------------------------- |
| < 30%    | +1.0% to PROD_GROWTH          | Low revenue                 | +1 prestige per turn (max +5 total) |
| 30%-50%  | No change (baseline)          | Normal revenue              | No prestige impact                  |
| 51%-65%  | -0.5% to PROD_GROWTH          | High revenue                | -1 prestige every 3 turns           |
| > 65%    | -1.0% to PROD_GROWTH          | Very high revenue           | -2 prestige every 5 turns           |

Explanation:
- Low Tax Rate (<30%): Encourages productivity growth, simulating a favorable economic environment. Provides lower immediate revenue but increases long-term economic output. Small prestige gain (+1 per turn, capped at +5 total).
- Moderate Tax Rate (30%-50%): Balanced approach with no changes to productivity growth. Provides steady revenue and avoids any prestige impact.
- High Tax Rate (51%-65%): Increases short-term revenue but slightly reduces productivity growth (-0.5%). Minor prestige penalty (-1 point every 3 turns) reflects mild discontent from heavier taxation.
- Very High Tax Rate (>65%): Maximizes short-term revenue at the cost of long-term productivity (-1.0% to growth). Moderate prestige penalty (-2 points every 5 turns), reflecting significant public discontent and potential economic strain.

## 3.3 Net Colony Value (NCV) and Treasury Management

Net Colony Value (NCV): Represents the net tax revenue collected from each colony.

```
NCV = GCO × tax rate
```

Net House Value (NHV): The sum total of all NCVs across the player's colonies. NHV is transferred to the House treasury at the beginning of each turn.

### **3.4 Industrial Investments and Productivity Growth**

Investing in Industrial Units (IU) increases the manufacturing capacity of a colony, directly boosting GCO. The cost of IU investments scales based on the percentage of IU relative to the colony's PU.

| IU Investment (% of PU) | Cost Multiplier | PP  |
| ----------------------- |:---------------:|:---:|
| Up to 50%               | 1.0             | 30  |
| 51% - 75%               | 1.2             | 36  |
| 76% - 100%              | 1.5             | 45  |
| 101% - 150%             | 2.0             | 60  |
| 151% and above          | 2.5             | 75  |

## 3.5 Economic Level Modifier

R&D investments allow players to increase their Economic Level Modifier (EL_MOD), boosting overall productivity. Advancing tech levels requires significant PP investment but provides exponential benefits to GCO.

Refer to [Section 4.2](#42-economic-level-el) for cost and modifiers.

## 3.6 Population Growth

Colonists are hard at work making babies for the House, and the PTU growth rate under normal conditions is 1.5% per turn.

A logistical growth function is used for the calculation. Each planet class has an upper bound on the population it can support. This gives a nice 's' curve distribution, and lends incentive to terraform less hospitable planets.

[The Logistic Equation](https://michaelneuper.com/posts/modelling-population-growth-in-python/)

![Alt text](https://github.com/greenm01/ec4x/blob/main/assets/logistic_population_growth.png)

## 3.7 Colonization

ETACs plant a flag in unoccupied Solar Systems and set the initial conditions for terraforming. Their capacity to move PTU is limited to one unit.

The Space Guilds are contracted to transfer larger populations between existing Colonies in civilian Starliners. Passengers are kept in status to minimize living space, and all of their supplies and equipment for their new destination are tightly packed into the cargo hold. 

The cost is expensive and dependent upon the livable conditions of the destination planet. The logistics are abstracted for game purposes; delivery time (turns) across jump lanes is in accordance with [Section 6.1](#61-jump-lanes).

| Conditions | PP/PTU |
| ---------- |:------:|
| Eden       | 4      |
| Lush       | 5      |
| Benign     | 6      |
| Harsh      | 8      |
| Hostile    | 10     |
| Desolate   | 12     |
| Extreme    | 15     |

Colonists do not start contributing to the colony's economic production for at least one full turn after arrival.

## 3.8 Expenditures

Each turn, the Duke can allocate Treasury funds as follows:

1. Military: Construction and recruiting.
2. Spacelift Command: Bases and ships
3. Research and Development: Investment in new technologies.
4. Industrial Units (IU): Investment in colony manufacturing.
5. Terraforming: Costs for planetary upgrade projects.
6. Space Guild Services:
    - Population Transfer: Moving citizens to new colonies.
    - Espionage: Covert operations and intelligence gathering.
7. Counter Intelligence: Defense against espionage.
8. Savings & Investment: Financial reserves and investments for future growth.

## 3.9 Maintenance Costs

At the beginning of each turn, players pay maintenance costs for everything they own: ships, ground units, yards, bases and anything else that can be constructed. All costs are listed in the data tables in [Section 9](#90-data-tables).

Players are able to reduce maintenance costs by placing active duty ships on either reserve status or mothballing them:

Maintenance costs for reserve ships is reduced by half, are auto-assigned into squadrons, and join a reserve fleet with orders 05 to guard the closest planet. Reserve ships have their AS and DS reduced by half, but do not change combat state. Reserve fleets can not be moved, and ships must already be located at a colony in order to place them in reserve. Colonies are allotted a single fleet for reserve duty.

The maintenance cost for mothballed ships is zero. Mothballed ships are placed in orbit around a colony and taken offline. They are screened during combat and are unable to join the fight. Mothballed ships are vulnerable to destruction if there is no Task Force present to screen them.

The payment of maintenance costs is not optional. If a player is unable to pay maintenance, random fleets will start going offline and ordered to hold position (00). Ships in these fleets do not accept new orders and will suffer a reduction of combat state every turn they are offline.

For every turn that a player misses payment for maintenance they loose prestige points; refer to [Section 9.4](#94-prestige).

## 3.10 Strategic Considerations

- Balancing Tax Rate: The tiered system encourages players to weigh the benefits of increased revenue against potential losses in productivity growth and prestige. A high tax rate can provide immediate revenue but may harm long-term economic stability.
- Investing in Infrastructure: Strategic investments in IU and R&D will enhance productivity growth, compensating for potential tax rate penalties.
- Adaptation to Game Phases: In the early game, players may prefer lower tax rates to boost productivity growth and build a strong economic base. In the mid and late game, shifting to a higher tax rate may be necessary to fund large-scale military operations or R&D projects.

# 4.0 Research & Development

## 4.1 Research Points (RP)

Each turn, players can invest production points in RP to further their R&D efforts.

R&D upgrades will be purchased in the first and seventh months of the Terran calendar, i.e. the first and seventh turns of each game year. Levels must be purchased in sequential order, and only one level per R&D area each upgrade cycle.

There are three areas of investment:
- Economic RP (ERP)
- Science RP (SRP)
- Technology RP (TRP)

Economic Levels (EL) are purchased with ERP and Science Levels (SL) are purchased with SRP. Science drives engineering, and new technologies are developed and purchased directly with TRP. EL and SL are correlated.

In standard EC4X games, Houses start at EL1 and SL1. Consider boosting these to expedite the game for impatient players, although the game year should be advanced from 2001 to match.

### 4.1.1 Research Breakthroughs

Technological progress can experience sudden leaps due to unexpected Research Breakthroughs. These moments of serendipity inject variability into the game, rewarding players for consistent investment in R&D and offering the chance for significant, game-altering advances.

**Research breakthroughs are triggered automatically twice per year**:

Bi-Annual Roll (Turn 1 and Turn 7):
- At the beginning of the year (Turn 1) and mid-year (Turn 7), the game system makes a 1d10 roll for each player.
- The base chance for a breakthrough is 10%.
- Players receive a +1% bonus for every 50 RP invested during the previous six turns (including ERP, SRP, and TRP combined).

**Breakthrough Types and Dice Roll**:

If the breakthrough is successful, a second 1d10 roll determines the type of breakthrough achieved. Each result on the die corresponds to a specific breakthrough type:

| Dice Roll | Breakthrough Type           | Effect Description                                         |
|:---------:| --------------------------- | ---------------------------------------------------------- |
| 0-4       | **Minor Breakthrough**      | +10 ERP, SRP, or TRP based on the current investment focus |
| 5-6       | **Moderate Breakthrough**   | 20% reduction in TRP cost for the next technology upgrade  |
| 7-8       | **Major Breakthrough**      | Automatically advance the next SL or EL by 1 level         |
| 9         | **Revolutionary Discovery** | Unlocks a unique technology or double-level advancement    |

**Minor Breakthrough (0-4)**:
   
The player gains an additional +10 points in ERP, SRP, or TRP, depending on their current investment focus (whichever has the highest allocation). This boosts research progress without direct cost.

**Moderate Breakthrough (5-6)**:
   
The player receives a 20% reduction in TRP cost for the next technology upgrade, reflecting streamlined research processes. This provides a cost advantage in the upcoming tech level advancement.

**Major Breakthrough (7-8)**:
   
The player automatically advances the next SL or EL by 1 level, skipping the usual SRP or ERP cost. This represents a significant leap in understanding, allowing rapid progression in core economic or scientific capabilities.

**Revolutionary Discovery (9)**:
- **Quantum Computing**: Permanently increases EL_MOD by 10%.
- **Advanced Stealth Systems**: Grants Raiders an additional +2 detection difficulty.
- **Terraforming Nexus**: Increases colony growth rate by an additional 2% per turn.
- **Experimental Propulsion**: Allows crippled military ships to jump across **restricted lanes**, enhancing fleet mobility.

Example:

During Turn 7, the game system performs a Research Breakthrough Roll for each player. Player A has invested a total of 150 RP over the previous six turns, providing a +3% bonus to their roll (10% base + 3% investment bonus).  The player is successful, and the second roll on the table is a 9, resulting in a "Revolutionary Discovery." Player A unlocks Experimental Propulsion, allowing their crippled military ships to traverse restricted jump lanes, providing a significant strategic advantage in maneuverability.

## 4.2 Economic Level (EL)

EL represents the entrepreneurial skills and general education level of House citizens.

EL is not a specific reflection of scientific or technological advancement, although they are correlated.

A House's GHO benefits from EL upgrades by 5% per level, for a maximum of 50% at EL10+. The economy is tied to entrepreneurial ambition and citizen education.

The formula for ERP in production points is:

```
1 ERP = (5 + log(GHO)) PP
```

Example: to purchase 10 ERPs with a GHO of 500, the cost in production points is:

```
10 ERP = 10(5 + log(500)) = 77 PP
```

For EL1 to EL5 The cost in ERP to advance one EL level is:

```
ERP = 40 + EL(10)
```

After EL5 the cost increases linearly by 15 points per EL level.

| EL  | ERP Cost | EL MOD |
|:---:|:--------:|:------:|
| 01  | 50       | 0.05   |
| 02  | 60       | 0.10   |
| 03  | 70       | 0.15   |
| 04  | 80       | 0.20   |
| 05  | 90       | 0.25   |
| 06  | 105      | 0.30   |
| 07  | 120      | 0.35   |
| 08  | 135      | 0.40   |
| 09  | 150      | 0.45   |
| 10  | 165      | 0.50   |
| 11+ | 180+     | 0.50   |

## 4.3 Science Level (SL)

Science explores new knowledge methodically through observation and experimentation, in alignment with nature. SL is dependent on the education and skill levels of citizens, and thus EL. 

Advancing to the next SL requires the House have previously developed an equivalent level of EL. For example, advancing from SL1 to SL2 requires the house to be at EL2 or greater.

The cost of SRP is dependent upon the current SL.

```
1 SRP = 2 + SL(0.5) PP
```

Example: To purchase 10 SRPs at SL2, the price in production points is:

```
10 SRP = 10(2 + 2(0.5)) = 30 PP
```

For SL1 to SL5, the cost in SRP to advance one SL level is:

```
SRP = 20 + SL(5)
```

After SL5, the cost increases linearly by 10 per level.

| SL  | SRP Cost |
|:---:|:--------:|
| 01  | 25       |
| 02  | 30       |
| 03  | 35       |
| 04  | 40       |
| 05  | 45       |
| 06  | 55       |
| 07  | 65       |
| 08+ | 75+      |

## 4.4 Technology Research Points (TRP)

Engineering is the practical application of science, and thus dependent upon advances in SL. Engineering advancements are made with direct investment in TRP.

In EC4X, advances in engineering are tied to the Military and Industrial complex, although development also carries over to commerce, mining, agriculture, industry, propulsion systems, computing, AI, robotics, services, medicine, and almost every other realm of material human flourishing.

The cost of TRP is dependent upon the required SL for the technology being developed [^2].

```
1 TRP = (5 + 4(SL))/10 + log(GHO) * 0.5 PP
```

For example, to purchase 5 TRPs towards the development TER3 with a GHO of 500, the price in production points is:

```
5 TRP = 5((5 + 4(3))/10 + log(500)(0.5)) = 15.25 PP
```

New engineering technologies are purchased directly with TRP.

\* Starting at Science Level 1 (SL1), each subsequent level of technology requires an additional 5 Technology Research Points (TRP) more than the previous level, with the initial cost being 25 TRP for the first level.

[^2]: **Game Designer Notes**:
As players expand their colonies, their NHV will grow. The logarithmic scaling with GHO allows for economic growth without making technology upgrades too cheap or too expensive, encouraging strategic planning around colonization and tech advancement.
If this formula results in too rapid or too slow of a tech progression, adjust the constant multiplier on the log term or change the base cost formula. The goal is to allow players to upgrade technologies in line with their economic growth while maintaining strategic depth.
For example, increasing the multiplier could make tech more expensive, encouraging slower but more impactful upgrades, whereas decreasing it could speed up tech progression, potentially making the game feel more dynamic but less strategic if not balanced correctly.
The TRP formula assumes a tax rate of 50% and a balanced budget of 40% Military, 30% R&D, 30% Other (Terraforming, Guild Services, CIC, 10% IU investment, etc..)
At 30% R&D EL,SL and every tech can be advanced every 1st and 7th month of the game as it becomes available. Excel file "ec4x_budget.xlsx" included in GitHub repo under "assets"
The formula will need testing and tweaking based on player feedback, especially concerning how it feels in terms of progression and economic strategy within the game.
Previously the formula used exp(GHO) * 0.0025 PP which grows the cost way too quickly in relation to GHO. Conversely, log(GHO) increases very slowly as GHO grows, and encourages a balanced economy where players can still feel the impact of economic growth on technology costs, but without the costs becoming too overwhelming. It allows for a more predictable and manageable progression.

## 4.5 Construction (CST)

Upgrades improve the construction capability and capacity of planet based factories, Spaceports, Shipyards. Existing units are upgraded at zero cost.

Construction capacity increases by 10% each level (round up).

CST will open up new, larger hulled classes of combat ships.

| CST Level | SL  | TRP Cost |
|:---------:|:---:| -------- |
| CST1      | 1   | 25       |
| CST2      | 2   | 30       |
| CST3      | 3   | 35       |
| CST4      | 4   | 40       |
| CST5+     | 5+  | \*45     |

The maximum construction level is CST10.

## 4.6 Weapons (WEP)

Upgrades improve the Attack Strength (AS) and Defense Strength (DS) of combat ships by 10% for each Weapons level (rounded down). 

For every WEP increase, Production Cost (PC) per unit increases by 10%.

Upgrades do not apply to preexisting ships; only new ships.

| WEP Level | SL  | TRP Cost |
|:---------:|:---:| -------- |
| WEP1      | 1   | 25       |
| WEP2      | 2   | 30       |
| WEP3      | 3   | 35       |
| WEP4      | 4   | 40       |
| WEP5+     | 5+  | 45       |

The maximum WEP level is WEP10.

## 4.7 Terraforming (TER)

Terraforming improve a planet's livable conditions, and thus the population limit. There are seven Terraforming levels that correspond directly with the planet classes.  

| TER Level | SL  | TRP Cost | Planet Class |
|:---------:|:---:| -------- | ------------ |
| TER1      | 1   | 25       | Extreme      |
| TER2      | 2   | 30       | Desolate     |
| TER3      | 3   | 35       | Hostile      |
| TER4      | 4   | 40       | Harsh        |
| TER5      | 5   | 45       | Benign       |
| TER6      | 6   | 50       | Lush         |
| TER7      | 7   | 55       | Eden         |

After the tech is achieved, the cost to upgrade a planet is as follows:

| Planet Class | Required TER | PU        | PP   |
|:------------ |:------------:|:---------:|:----:|
| Extreme      | TER1         | 1 - 20    | NA   |
| Desolate     | TER2         | 21 - 60   | 60   |
| Hostile      | TER3         | 61 - 180  | 180  |
| Harsh        | TER4         | 181 - 500 | 500  |
| Benign       | TER5         | 501- 1k   | 1000 |
| Lush         | TER6         | 1k - 2k   | 1500 |
| Eden         | TER7         | 2k+       | 2000 |

Example: Upgrading from TER3 to TER4 requires 91 PP.

Planets do not skip a class in their terraforming development.

## 4.8 Electronic Intelligence (ELI)

ELI technology enables the detection of cloaked Raiders and enemy Scouts, and the gathering of intelligence from rival assets.

Upgrades do not apply to preexisting Starbases and Scouts.

| ELI Level | SL  | TRP Cost |
|:---------:|:---:| -------- |
| ELI1      | 1   | 25       |
| ELI2      | 2   | 30       |
| ELI3      | 3   | 35       |
| ELI4      | 4   | 40       |
| ELI5      | 5   | 45       |

The maximum ELI level is ELI5.

## 4.9 Cloaking (CLK)

Cloaking enables Raiders to cloak their assigned fleets with increasing levels of probability.

Upgrades do not apply to preexisting Raiders.

| CLK Level | SL  | TRP Cost |
|:---------:|:---:| -------- |
| CLK1      | 3   | 35       |
| CLK2      | 4   | 40       |
| CLK3      | 5   | 45       |
| CLK4      | 6   | 50       |
| CLK5      | 7   | 55       |

The maximum CLK level is CLK5.

## 4.10 Planetary Shields (SLD)

Planetary Shields protect a colony from bombardment and invasion.

Upgrades do not apply to preexisting shields. Salvage and build a new one.

| SLD Level | SL  | TRP Cost |
|:---------:|:---:| -------- |
| SLD1      | 3   | 35       |
| SLD2      | 4   | 40       |
| SLD3      | 5   | 45       |
| SLD4      | 6   | 50       |
| SLD5      | 7   | 55       |

The maximum SLD level is SLD5.

## 4.11 Counter Intelligence Command (CIC)

The CIC enhances security measures to shield the House from espionage threats posed by rivals.

| CIC Level | SL  | TRP Cost |
|:---------:|:---:| -------- |
| CIC1      | 1   | 25       |
| CIC2      | 2   | 30       |
| CIC3      | 3   | 35       |
| CIC4      | 4   | 40       |
| CIC5      | 5   | 45       |

The maximum CIC level is CIC5.

## 4.12 Strategic Considerations

- Balancing R&D Investments: Players must balance investments across ERP, SRP, and TRP to maximize their economic output, technological advancements, and military strength.
- Economic Synergies: Increasing EL and SL together can provide synergistic benefits, enhancing overall productivity and unlocking powerful technologies.
- Adapting to Opponents: Flexibility in R&D strategy is key. Prioritizing weapons technology (WEP) during a military conflict or focusing on terraforming (TER) for long-term economic growth can be critical decisions based on the game state.

# 5.0 Construction

Construction and repair of House assets is accomplished planet-side or in orbit, with restrictions. 

The number of turns required to construct a Military ship is two turns. Spacelift Command ships require one turn.

The number of turns required to repair a crippled ship is one turn. The ship's squadron must be located at a colony equipped with a shipyard, and the ship remains decommissioned through the repair period.

Newly commissioned ships, and repaired ships, will remain in their existing docs until ordered to join a squadron.

Spaceport and Shipyard construction capacity is limited by their CST tech.

## 5.1 Planet-side Construction

Ground units and fighter squadrons are produced via colony industry, distributed across the surface or in underground factories.

Ships (excluding fighter squadrons) constructed planet-side incur a 100% PC increase due to the added cost of orbital launch, and require a spaceport to commission.

## 5.2 Planet-side Repair

Ground units and fighter squadrons are repaired and refitted planet-side.

## 5.3 Orbital Construction

Shipyard construction of a ship in orbit is the standard method of commissioning a vessel, and incurs no penalty.

## 5.4 Orbital Repair

Ship repairs require a Shipyard. The cost of repair equals one quarter (25%) of the unit's PC.

Example: A player wishes to repair a crippled WEP3 Light Cruiser. The cost is:

```
72.6 * 0.25 = 18.15 PP.
```

The logistics of repairing a ship planet-side and returning it to orbit make it economically infeasible. Ships are salvaged at colonies without restriction and earn 50% of the original PC back to the House treasury.

# 6.0 Movement

## 6.1 Jump Lanes

Fleets move between solar systems via jump lanes:
- If a player owns all systems along the travel path, fleets can jump two major lanes in one turn.
- Minor and restricted jump lanes enable a single jump per turn, regardless of the destination.
- If jumping into an unexplored or rival system, the maximum number of jumps is one.
- Fleets containing crippled ships or Spacelift Command ships can not jump across restricted lanes.

## 6.2 Fleet Orders

Possible fleet missions are listed in the table below. These are the classic fleet orders from Esterian Conquest, modified for EC4X.

| No.  | Mission                 | Requirements                             |
| ---- | ----------------------- | ---------------------------------------- |
| 00   | None (hold position)    | None                                     |
| 01   | Move Fleet (only)       | None                                     |
| 02   | Seek home               | None                                     |
| 03   | Patrol a System         | None                                     |
| 04   | Guard a Starbase        | Combat ship(s)                           |
| 05   | Guard/Blockade a Planet | Combat ship(s)                           |
| 06   | Bombard a Planet        | Combat ship(s)                           |
| 07   | Invade a Planet         | Combat ship(s) & loaded Troop Transports |
| 08   | Blitz a Planet          | Loaded Troop Transports                  |
| 09   | Spy on a Planet         | One Scout ship                           |
| 10\* | Hack a Starbase         | One Scout ship                           |
| 11   | Spy on a System         | One Scout ship                           |
| 12   | Colonize a Planet       | One ETAC                                 |
| 13   | Join another Fleet      | None                                     |
| 14   | Rendezvous at System    | None                                     |
| 15   | Salvage                 | Friendly Colony System                   |

\* New to EC4X

Movement orders command a fleet to jump across the necessary lanes to the destination solar system, in accordance with the rules specified in [Section 6.1](#61-jump-lanes). Depending upon the distance from the fleet's preexisting location and available lanes, movement may take multiple turns to complete.

### 6.2.1 Hold Position (00):

Fleets are ordered to hold position and standby for new orders.

### 6.2.2 Move Fleet (01):

Move to a new solar system and hold position (00).

### 6.2.3 Seek home (02):

Order a fleet to seek the closest friendly solar system and hold position (00). Should that planet be taken over by an enemy, the fleet will move to the next closest planet you own.

### 6.2.4 Patrol a System (03):

Actively patrol a solar system, engaging hostile forces that enter the space.

### 6.2.5 Guard a Starbase (04):

Order a fleet to protect a Starbase, and join in a combined Task Force, when confronting hostile ships with orders 05 to 08.

### 6.2.6 Guard/Blockade a Planet (05):

Order a fleet to block hostile forces from approaching a planet.

**Guard**: Fleets on guard duty are held in rear guard to protect a colony and do not join Space Combat unless confronted by hostile ships with orders 05 to 08. Guarding fleets may contain Raiders and do not auto-join a Starbase's Task Force, which would compromise their cloaking ability. Not all planets will have a functional Starbase.

**Blockade**: Fleets are ordered to blockade an enemy planet and do not engage in Space Combat unless confronted by enemy ships under order 05.

Colonies under blockaded reduce their GCO by 60%. Civilian transport, commerce, trade, and mining activities in the Solar System are severely restricted, which results in a critical negative impact on the economy and citizen morale. House Prestige is reduced by 2 points every turn a colony is under blockade.

### 6.2.7 Bombard a Planet (06):

Fleets are ordered to attack a planet's defensive ground assets, including shields, ground batteries, garrisoned Army units and Marines, and Spaceports. Bombardment has a detrimental effect on a colony's PTU and IUs.

### 6.2.8 Invade a Planet (07):

This is a three round battle:

1. Destroy all the planet's ground batteries.
2. Pound the population centers to soften resistance and take out enemy ground troops.
3. Send in troop transports to drop off Marines, but ONLY AFTER all ground batteries have been destroyed.

Bombardment damages the planet and gives the defenders time to sabotage industry before being overrun, but gives invading Marines a better chance of seizing the planet. The invasion succeeds if all the ground batteries are destroyed and ground forces defeated.

### 6.2.9 Blitz a Planet (08):

Quickly infiltrate Marines onto the planet by dodging ground batteries or distracting them. Ground units must be defeated for success.

Because this form of attack is so fast, there is less damage to the planet since the enemy does not have time to sabotage their factories and combat ships go light on surface bombardment.  However, Marines are at greater risk and require superior numbers (twice as many as the enemy or better) to insure victory.

### 6.2.10 Spy on a Planet (09):

This mission is reserved for solo operating Scouts. The Scout will attempt to hide itself in orbit as a civilian satellite and collect military intelligence from the surface.

### 6.2.11 Hack a Starbase (10):

This mission is reserved for solo operating Scouts. The Scout will disguise itself as a civilian satellite and hack into a rival's Starbase network for the purpose of collecting economic and R&D intelligence.

### 6.2.12 Spy on a System (11):

This mission is reserved for solo operating Scouts. The Scout will loiter in the solar system and collect military asset intelligence.

### 6.2.13 Colonize a Planet (12):

This mission is reserved for ETACs under fleet escort. The ETAC will land one PTU on an unoccupied planet and establish a colony. The colonists will break the ETAC down and start the long process of terraforming. New colonies start at Level I regardless of the hospitable conditions.

If the planet is already occupied, the fleet will hold position (Order 00) in the solar system until directed otherwise.

### 6.2.14 Join another Fleet (13):

Seek out the location of a fleet and merge. The old fleet will disband and squadrons will join the existing one. If the host fleet is destroyed, all joining fleets will abandon their mission and hold position (00).

### 6.2.15 Rendezvous at System (14):

Move to the specified system and merge with any other fleets ordered to rendezvous there. The fleet with the lowest ID Number becomes the host fleet.  This order is useful for assembling large fleets near enemy planets for later attack.

### 6.2.16 Salvage (15):

Salvage a fleet at the closest colony. The fleet will disband and all the ships are salvaged for 50% of their PC.

# 7.0 Combat

## 7.1 Principles

### 7.1.1 Rules of Engagement (ROE)

ROE dictates how aggressive your fleet will respond when engaging with the enemy from a scale of 0 to 10. The higher the ROE, the more aggressive your fleet will engage with enemy fleets of increasing relative strength to your own. With a low ROE, your fleet will attempt to retreat more readily when engaged in combat. A low ROE does not guarantee survival against a more powerful fleet. Once engaged, fleets have the opportunity to retreat only after the first round of combat.

| **ROE** | **ORDERS**                                             |
| ------- | ------------------------------------------------------ |
| 00      | Avoid all hostile forces. (Non-combat forces)          |
| 01      | Engage forces only if they are defenseless.            |
| 02      | Engage forces only if your advantage is 4:1 or better. |
| 03      | Engage forces only if your advantage is 3:1 or better. |
| 04      | Engage forces only if your advantage is 2:1 or better. |
| 05      | Engage forces only if your advantage is 3:2 or better. |
| 06      | Engage hostile forces of equal or inferior strength.   |
| 07      | Engage hostile forces even if outgunned 3:2.           |
| 08      | Engage hostile forces even if outgunned 2:1.           |
| 09      | Engage hostile forces even if outgunned 3:1.           |
| 10      | Engage hostile forces regardless of their size.        |

A fleet's ROE is defined when it's created, or changed any time before engaging in combat. The ROE can not be changed during combat.

### 7.1.2 Combat State

Squadron units are either undamaged, crippled, or destroyed.

**Attack Strength (AS)** represents a unit's offensive firepower and is a mutable type.

**Defense Strength (DS)** represents a unit's defensive shielding and is an immutable type.

**Reduced**: This term is used to describe a transition of state, e.g. undamaged to crippled, crippled to destroyed.

**Undamaged**: A unit’s life support systems, hull integrity, and weapons systems are fully operational.

**Crippled**: When an undamaged unit’s DS is equaled in battle by hits, that unit’s primary defensive shielding is compromised and the unit is reduced to a crippled combat state. AS is reduced by half.

**Destroyed**: In a crippled combat state, hits equal to DS reduces a unit's state to destroyed. The unit is dead and unrecoverable.

If a squadron is crippled, all the ships under its command are crippled. If a squadron is destroyed, all the ships are likewise destroyed.

### 7.1.3 Cloaking

Cloaking offers an advantage in the initial round of space combat, either on the defensive or offensive.

When defending a solar system, cloaked units are considered to be **in ambush** against invaders.

When attacking a solar system, cloaked units are considered to be **a surprise** to the defenders.

In neutral territory a cloaked fleet is considered to be a surprise.

Scouts and Starbases present in opposing forces have the opportunity to counter for cloaking. Roll for detection in accordance with [Section 2.4.3](#243-raiders).

If cloaked fleets on all sides pass undetected from one another, then the player defending his solar system wins in ambush. If opposing forces are meeting in neutral territory and all pass undetected, then they carry on with movement orders and combat is cancelled.

## 7.2 Task Force Assignment

All applicable fleets and Starbases relevant to the combat scenario will merge into a single Task Force.

Rules of Engagement (ROE):

- Task Forces adopt the highest ROE of any joining fleet.
- Starbases do not retreat; the Task Force's ROE is set to 10.

Cloaking:

- Task Forces including Starbases cannot cloak.
- All joining fleets must remain undetected for Task Force cloaking ([Section 7.1.3](#713-cloaking)).

Fleet Integration:

- Fleets disband, with their squadrons fighting individually under the Task Force.
- Fighter Squadrons deploy as independent units.

Cloaked fleets with movement orders can continue if they pass stealth checks; otherwise, they join combat.

Spacelift Command ships are screened behind the Task Force during combat operations and do not engage in combat.

## 7.3 Space Combat

All fleets within a solar system are mandated to engage enemy forces during their turn, with the following exceptions:

- Fleets under Fleet Order 04: Guard a Starbase 
- Fleets under Fleet Order 05: Guard/Blockade a Planet

Specific Engagement Rules:
1. Blockade Engagement:
    - Fleets assigned to Blockade an enemy planet (Fleet Order 05) will engage only with enemy fleets ordered to Guard that same planet.
2. Guard Engagement:
    - Fleets assigned to Guard a planet (Fleet Order 05) will engage only enemy fleets with orders ranging from 05 to 08 and 12, focusing on defensive or blockading actions.

Task Forces form according to [Section 7.2](#72-task-force-assignment).

Starbases and their guarding fleets, operating under Order 04, are maintained as rear guards. Their sole purpose is to defend against blockades or direct attacks on the House's colonies.

Squadrons are not allowed to change assignments or restructure during combat engagements or retreats.

### 7.3.1 Rounds

After Task Forces are aligned for battle, combat commences in a series of rounds until one side is completely destroyed or manages a retreat.

Combat action is simultaneous; all squadrons have the opportunity to fire on enemy forces at least once, regardless of damage sustained during a round.

At the beginning of each combat round, players add up the total AS of their surviving squadrons. The total value is then modified by the Combat Effectiveness Rating (CER).

Roll for CER on the table below, applying all applicable modifiers.

| **Modified 1D10 Die Roll** | **Space Combat CER**             |
| -------------------------- | -------------------------------- |
| Less than zero, 0, 1, 2    | One Quarter (0.25) (round up)    |
| 3, 4                       | One Half (0.50) (round up)       |
| 5, 6                       | Three Quarters (0.75) (round up) |
| 7, 8                       | One (1)                          |
| 9\*                        | One\* (1)                        |
| 9+                         | One (1)                          |

\*If the die roll is a natural nine before any required modification,
then a critical hit is achieved

**Die Roll Modifiers**

| Modifier | Value | Notes                                                |
| -------- |:-----:| ---------------------------------------------------- |
| Scouts   | +1    | Maximum benefit for all Scouts                       |
| Surprise | +3    | First round only; See [Section 7.1.3](#713-cloaking) |
| Ambush   | +4    | First round only; See [Section 7.1.3](#713-cloaking) |

**The CER multiplied by AS equals the number of total enemy hits.**

The player who rolled the die will determine where hits are applied.

The following **restrictions** apply:
1. If the number of hits equal the opposing squadron's DS, the unit is reduced.
2. Squadrons are not destroyed until all other squadrons in the Task Force are crippled.
3. Excess hits are lost if restrictions apply.

Crippled squadrons multiply their AS by 0.5, rounded up the nearest whole number.

Destroyed squadrons are no longer a factor and the Task Force loses their associated die roll modifiers (e.g. Scouts).

In computer moderated play, the algorithm will reduce opposing squadrons with the greatest AS, within restrictions.

**Critical Hits**:

Critical hits are a special case. Restriction \#2 in the list above is nullified.

Additionally, if a player takes a critical hit and is unable to reduce a unit according to restriction \#1 above, then the squadron with the lowest DS is reduced.

### 7.3.2 End of Round

After all hits are applied and squadrons are appropriately reduced (crippled or destroyed), recalculate the total AS of all surviving Task Forces.

Check each Task Force's ROE on the table in [Section 7.1.1](#711-rules-of-engagement-roe) by comparing AS strengths and determine if a retreat is warranted. If so, proceed to [Section 7.3.3](#733-retreat).

If more than one Task Force remains in the fight, the next round commences via the same procedure as described above.

Otherwise proceed to [Section 7.3.4](#734-end-of-space-combat).

### 7.3.3 Retreat

A Task Force is able retreat from combat after the first round, in accordance with their ROE, and between rounds thereafter.

Squadrons in a retreating Task Force will fall back to their original fleet formations and flee to the closest non-hostile star system.

Fighter squadrons never retreat from combat. If they remain in the fight, fighter squadrons will screen their retreating Task Force and combat resumes until they are completely destroyed. 

Spacelift Command ships are destroyed if their escort fleets were destroyed.

### 7.3.4 End of Space Combat

After the last round of combat the surviving Task Forces are disbanded and surviving squadrons rejoin their original fleets.

## 7.4 Starbase Combat

Starbases serve as the primary defense if a hostile fleet aims to blockade, bombard, invade, or blitz a colony. They form a combined Task Force as per [Section 7.2](#72-task-force-assignment).

Fleets with orders to guard the Starbase (Fleet Orders 04) also join the Task Force.

Combat will proceed in a similar fashion to [Section 7.3](#73-space-combat), with the following restrictions:

1. If a player rolls a critical hit against a starbase on the first try, re-roll a second time.
2. Starbases receive an extra +2 die roll modifier.

Starbases are fortified with superior AI and sensors, making them formidable, with high defensive capabilities.

## 7.5 Planetary Bombardment

After orbital supremacy is achieved, planets are vulnerable to surface attack. Planetary shields, ground batteries, and ground forces are the last line of defense before invasion or blitz.

Like space combat, planetary bombardment is simultaneous. No more than three combat rounds are conducted per turn.

### 7.5.1 Determine Hits

The attacking player will total the AS value of their fleet's surviving squadrons and the defending player will total the AS strength of all remaining ground batteries. Both players roll on the Bombardment Table.

**Bombardment Table**:

| **1D10 Die Roll** | ** Bombardment CER**          |
| ----------------- | ----------------------------- |
| 0, 1, 2           | One Quarter (0.25) (round up) |
| 3, 4, 5           | One Half (0.50) (round up)    |
| 6, 7, 8           | One (1)                       |
| 9\*               | One\* (1)                     |

\* Critical hits are only applied against attacking squadrons

The CER multiplied by AS equals the number of hits on the enemy.

### 7.5.2 Planetary Shields

If a planet is protected by shields, the defending player will roll on the table below to determine the number of hits blocked.

| SLD Level | % Chance | 1D20 Roll | % of Hits Blocked |
|:---------:|:--------:|:---------:|:-----------------:|
| SLD1      | 15       | > 17      | 25%               |
| SLD2      | 30       | > 14      | 30%               |
| SLD3      | 45       | > 11      | 35%               |
| SLD4      | 60       | > 8       | 40%               |
| SLD5      | 75       | > 5       | 45%               |
| SLD5      | 90       | > 2       | 50%               |

Reduce the attacking players hits by the percentage, rounding up. This is the number of effective hits.

Example: A fleet with AS of 75 bombards a planet protected by a SLD3 shield, and the defending player rolls a 15.

```
Hits = 75 * (1 - .35) = 49
```

Note that shields are only be destroyed by Marines during planetary invasion.

### 7.5.3 Ground Batteries

The player who rolled the die will determine where hits are applied. Because ground batteries are all the same, selecting which ground batteries to target is moot. Unlike ships in squadrons, ground batteries are reduced as individual units.

The following **restrictions** apply:
1. If the number of hits equal the opposing unit's DS, the unit is reduced.
2. Units are not destroyed until all other units are crippled.
3. Excess hits leftover against Ground Batteries are summed.
4. Excess hits are lost against squadrons if restrictions apply.

Crippled units multiply their AS by 0.5, rounded up the nearest whole number.

**Critical Hits**:

Critical hits are a special case, and only apply against the attacking fleet. Restriction \#2 in the list above is nullified.

Additionally, if a player takes a critical hit and is unable to reduce a unit according to restriction \#1 above, then the squadron with the lowest DS is reduced.

Proceed to the next section.

### 7.5.4 Ground Units & Civilian Infrastructure

The attacking player will apply unused hits towards ground forces (Armies or Marines):
1. If the number of hits equal the opposing unit's DS, the unit is reduced.
2. Units are not destroyed until all other units are crippled.
3. Excess hits are lost if restrictions apply.

Finally, if there are unused hits left over from ground batteries and ground forces, subtract the number of hits from the planet's IU. If there is no remaining IU, apply hits to the planet's PU instead.

If there are remaining rounds (max 3), return to [Section 7.5.1](#751-determine-hits) and repeat.

## 7.6 Planetary Invasion & Blitz

Combat is simultaneous, and the following table is used to determine the CER.

**Ground Combat Table**:

| **1D10 Die Roll** | **Ground Combat CER**           |
| ----------------- | ------------------------------- |
| 0, 1, 2           | One Half (0.5) (round up)       |
| 3, 4, 5, 6        | One (1)                         |
| 7, 8              | One and a half (1.5) (round up) |
| 9                 | Two (2)                         |

### 7.6.1 Planetary Invasion

To land Marines on a planet during ground invasion, all the surface Ground Batteries must be destroyed. First conduct *one round* of planetary bombardment from [Section 7.5](#75-planetary-bombardment). If there are remaining Ground Batteries, the mission fails.

If all ground batteries are destroyed, the Marines are dropped onto the surface. Planetary shields and Spaceports are immediately destroyed.

Both sides total the AS strength of their Armies and Marines, and roll on the Ground Combat Table for the CER. The CER multiplied by AS is the number of hits. Armies and Marines are treated as individual units for the purposes of combat reduction.

The player who rolled the die will determine where hits are applied, with the following restrictions:
1. If the number of hits equal the opposing unit's DS, the unit is reduced.
2. Units are not destroyed until all other units are crippled.
3. Excess hits are lost if restrictions apply.

Crippled units multiply their AS by 0.5, rounded up the nearest whole number.

Repeat the process until one side is completely destroyed.

If the planet is conquered, loyal House citizens destroy 50% of of the colony's remaining IU before order is restored.

### 7.6.2 Planetary Blitz

Fleets and Ground batteries conduct one round of combat in accordance with [Section 7.5](#75-planetary-bombardment), with the exception that ground units and civilian infrastructure are not targeted ([Sections 7.5.4](#754-ground-units--civilian-infrastructure)). Troop transports are included as individual units within the attacking player's fleet and may be destroyed on their way down to the surface by Ground Batteries.

Because of quick insertion and Ground Battery evasion, surviving Marines that manage to land in their troop transports multiply AS by 0.5 (rounding up).

Ground battle occurs in a similar fashion to [Section 7.6.1](#761-planetary-invasion), with the exception that IUs are not destroyed if the planet is conquered. All remaining planet assets are seized by the invading House, including IU, shields, spaceports, and ground batteries.

## 7.7 Custom Combat Modifications

If customizing your own ships or scenarios, the following list provides a jumping off point for custom modification. EC4X is flexible enough to enable the tailoring of the combat mechanics to your own ideas and requirements. Please report back to the project anything that works well for you and increases enjoyment of the game. 

- Additional modifiers to the CER roll, e.g. battle stations readiness, random chance events, etc.
- Apply the Starbase critical hit rule to special assets that are resistant to crippling.
- Add a modifier to protect a homeworld's solar system
- Add mines or moon bases
- Add defensive missile batteries
- Insert your imagination here.....

EC4X Space combat is adapted from Empire of the Sun (EOS). 

# 8.0 Diplomacy & Espionage

## 8.1 Diplomacy

In EC4X, diplomacy includes Neutral, Enemy, and Non-Aggression categories. As House Duke, your mandate is to lead your House to victory by strategic means, where diplomacy can play a pivotal role alongside the sword. Your primary directive remains to decisively manage your adversaries, leveraging both military might and diplomatic cunning.

### 8.1.1 Neutral

Fleets are instructed to avoid initiating hostilities with the designated neutral House outside of the player's controlled territory. This status allows for coexistence in neutral or contested spaces without immediate aggression.

### 8.1.2 Non-Aggression Pacts

Houses can enter into formal or informal agreements to not attack each other, allowing for cooperation or at least a mutual stance of non-hostility.

This can include:
- Joint Military Operations: Against common threats or for mutual defense without direct conflict between the signing parties.
- Territorial Recognition: Agreements to respect each others territories.
- Strategic Flexibility: While not allies, Houses in a non-aggression pact can share intelligence, coordinate against mutual enemies..
- Violation Consequences: Breaking a non-aggression pact can lead to a swift change to enemy status.

### 8.1.3 Enemy

Fleets are commanded to engage with the forces of the declared enemy House at every opportunity, both within and outside controlled territories.

This state leads to full-scale warfare where all encounters are treated as hostile, pushing for direct and aggressive confrontations.

### 8.1.4 Defense Protocol

Regardless of diplomatic status, all units will defend home planets against any foreign incursions with maximum aggression.

Fleets will retaliate against direct attacks regardless of diplomatic state, in accordance with ROE.

## 8.2 Subversion & Subterfuge

The Space Guilds are key players in the clandestine world of diplomacy and espionage. They dominate trade, technology sharing, and offer covert operations, wielding influence through subterfuge and strategic manipulation. While their partnerships can significantly enhance a House's capabilities, the Space Guilds remain neutral, their loyalties bought by the highest bidder or the most strategic offer.

Players can allocate Espionage Budget points (EBPs) towards various espionage actions every turn.

EBP points **cost 40 PP each**.

If a player invests more than 5% of their turn budget into EBP they lose Prestige points.

- Investments > 5% lose 1 Prestige point for each additional 1% invested over 5%.
- Example: If a player's turn budget is 100 points, and they invest 7 points in EBP, they lose 2 Prestige points.

**Restrictions**:

- Maximum of One Espionage Action Per Turn.

| Espionage Action       | Cost in EBPs | Description                                                          | Prestige Change for Player | Prestige Change for Target |
| ---------------------- |:------------:| -------------------------------------------------------------------- | -------------------------- | -------------------------- |
| Tech Theft             | 5            | Attempt to steal critical R&D tech.                                  | +2                         | -3                         |
| Sabotage (Low Impact)  | 2            | Small-scale sabotage to a colony's industry.                         | +1                         | -1                         |
| Sabotage (High Impact) | 7            | Major sabotage to a colony's industry.                               | +3                         | -5                         |
| Assassination          | 10           | Attempt to eliminate a key figures within the target House.          | +5                         | -7                         |
| Cyber Attack           | 6            | Attempt to hack into a Starbase's systems to cause damage and chaos. | +2                         | -3                         |
| Economic Manipulation  | 6            | Influence markets to harm the target's economy                       | +3                         | -4                         |
| Psyops Campaign        | 3            | Launch a misinformation campaign or demoralization effort.           | +1                         | -2                         |

### **8.2.1 Espionage Mechanics**

Espionage actions allow players to disrupt their rivals' operations and gain tactical advantages through covert maneuvers. Below is a detailed overview of each available action, including its effects and thematic narrative.

| Espionage Action         | Effect                                                  |
| ------------------------ | ------------------------------------------------------- |
| **Tech Theft**           | Steals **10 SRP** from the target’s research pool       |
| **Low Impact Sabotage**  | Reduces target’s **1d6 Industrial Units (IU)**          |
| **High Impact Sabotage** | Reduces target’s **1d20 Industrial Units (IU)**         |
| **Assassination**        | Reduces target’s **SRP gain by 50%** for one turn       |
| **Economic Disruption**  | Halves target’s **Net Colony Value (NCV)** for one turn |
| **Propaganda Campaign**  | Reduces target’s **tax revenue by 25%** for one turn    |
| **Cyber Attack**         | Cripples the target’s **Starbase**                      |

**Tech Theft**:
In the dead of night, a covert team of elite hackers infiltrates the rival House's research network, siphoning critical data and blueprints. By the time their intrusion is detected, valuable research progress has already been uploaded and integrated into your own laboratories, giving your scientists a sudden leap forward.

**Low Impact Sabotage**:
A series of small, untraceable explosions ripple through the industrial district of the target colony. Machines grind to a halt, assembly lines are disrupted, and productivity drops. While the damage is minimal, it forces costly repairs and creates a ripple effect of delays across the colony’s production schedule.

**High Impact Sabotage**:
Coordinated explosions rock the core industrial facilities of the enemy colony, sending plumes of smoke into the sky. Entire factories are leveled, leaving a twisted wreck of debris and fire. The sabotage is devastating, crippling the enemy’s manufacturing capabilities and resulting in the loss of up to **1d20 Industrial Units (IU)**.

**Assassination**:
A shadowy operative slips through the security perimeter and strikes at a key figure in the rival House’s R&D division. The death sends shock-waves through their research teams, causing chaos and demoralizing the scientists. The pace of research slows to a crawl as panic and distrust spread among the staff.

**Economic Disruption**:
Anonymous agents spread false rumors of an impending financial collapse, triggering a panic among investors and merchants in the enemy colony. Markets plunge, trade grinds to a halt, and the local economy falters. Revenues drop sharply as the effects of the disruption ripple through the entire colony’s financial system.

**Propaganda Campaign**:
A coordinated propaganda blitz floods the rival House’s communications networks with fake news and altered footage, painting their leadership as corrupt and ineffective. Citizens begin to protest, refusing to pay full taxes as public confidence crumbles. The unrest leaves the enemy Duke struggling to maintain control, with lower revenues compounding their problems.

**Cyber Attack**:
A powerful virus infiltrates the core systems of the enemy’s Starbase, shutting down its defenses and key operational modules. The Starbase is left crippled, its functions severely impaired until extensive repairs are completed. The colony's defensive posture and economic output suffer a significant blow, leaving it vulnerable to further attacks.

## 8.3 Counter Intelligence Command (CIC)

The mission of the Counter Intelligence Command (CIC) is to safeguard the House's interests by identifying and neutralizing espionage activities from rival Houses. This involves employing advanced surveillance technologies and running counter-espionage operations to ensure the security of House secrets.

**CIC Investment**:

Players can allocate a portion of their turn budget into Counter Intelligence Points (CIP).

- CIP points cost **40 PP each**.
- Each detection attempt (roll) costs **1 CIP point**. If a House has no CIP points, espionage attempts automatically succeed.
- When an espionage event occurs, a **detection modifier** is applied based on the player's total CIP points.

If a player invests more than 5% of their turn budget into CIP they lose Prestige points.

- Investments > 5% lose 1 Prestige point for each additional 1% invested over 5%.
- Example: If a player's turn budget is 100 points, and they invest 7 points in CIP, they lose 2 Prestige points.

### Detection Modifier:

The modifier is determined based on the total **CIP points** held by the player when an espionage event occurs:

| Total CIP Points | Automatic Detection Modifier          |
|:----------------:|:-------------------------------------:|
| 0                | +0 (espionage automatically succeeds) |
| 1-5              | +1                                    |
| 6-10             | +2                                    |
| 11-15            | +3                                    |
| 16-20            | +4                                    |
| 21+              | +5 (maximum)                          |

### Espionage Detection Table:

| CIC Level | Base 1D20 Roll | Detection Probability (with Automatic Modifier) |
|:---------:|:--------------:|:-----------------------------------------------:|
| CIC1      | > 15           | 25% → 30-50%                                    |
| CIC2      | > 12           | 40% → 45-65%                                    |
| CIC3      | > 10           | 55% → 60-80%                                    |
| CIC4      | > 7            | 65% → 70-90%                                    |
| CIC5      | > 4            | 80% → 85-95%                                    |

**Example**:

1. A player with **CIC3** and **8 CIP points** faces an espionage event.
2. The game deducts **1 CIP point** for the detection roll and applies a +2 modifier (based on having 6-10 CIP points).
3. The detection roll threshold for CIC3 is **10+**. With the +2 modifier, the roll only needs to meet or exceed **8**.
4. The roll result is **8**, so the espionage attempt is successfully detected.

**Outcome of Successful Detection**:

- If the roll (including the modifier) meets or exceeds the required threshold, the espionage action is detected and prevented.
- The attacking player loses **2 prestige points** for the failed attempt.

## 8.4 Risks of Over-Investing in Espionage

While espionage is a powerful tool for undermining rival Houses, over-reliance on covert actions comes with significant risks. In the volatile political landscape of EC4X, the perception of your House can be as important as its actual strength. An overly aggressive espionage strategy can backfire, tarnishing your reputation and eroding the trust of allies, subjects, and even neutral factions. The path to the throne is narrow, and using shadow tactics too liberally can leave a House vulnerable to unforeseen consequences.

### Reputation Damage

A House known for excessive use of espionage becomes synonymous with treachery. Other Houses may become wary of forming alliances or trading agreements, fearing betrayal. This distrust can isolate a House diplomatically, limiting options for cooperation or joint military efforts against common threats.

The citizens of the Empire prize strength, honor, and open warfare over deceit. A Duke who leans too heavily on spies and saboteurs may be seen as weak or dishonorable, risking a loss of public support. This can manifest in reduced prestige, lower tax compliance, and even increased civil unrest across your colonies.

### Diminished Strategic Impact

The more frequently espionage tactics are used, the more likely rivals are to bolster their counter-intelligence efforts. As other Houses ramp up their CIP investments, the effectiveness of your espionage actions diminishes, resulting in wasted resources and fewer successful missions.

Excessive espionage may trigger rival Houses to adopt aggressive countermeasures, such as initiating economic sanctions, launching retaliatory cyber attacks, or coordinating with other players to mount a joint military response. The risks of provoking a coalition against your House increase with every detected espionage action.

### Prestige Penalties

Investing too much in espionage can erode the prestige of your House over time, creating a long-term disadvantage. The aristocracy views shadowy tactics as a sign of desperation rather than strength, leading to the perception that your House is incapable of achieving its goals through legitimate means.

Each turn that espionage investments exceed 5% of your budget, your House loses 1 prestige point for every additional 1% invested over the 5% threshold. This penalty reflects the growing skepticism of your peers and the erosion of your House’s noble reputation.

Repeated over-investment in espionage actions compounds the loss of prestige, as the Empire’s nobility becomes increasingly suspicious of your methods. Over time, this can severely impact your standing, making it difficult to assert dominance and achieve key diplomatic or military objectives.

### Increased Vulnerability to Espionage

Ironically, focusing heavily on offensive espionage often means neglecting your own defenses. Houses that pour resources into EBP at the expense of CIP may find themselves exposed to enemy spies, suffering from stolen technologies, sabotage, and propaganda campaigns. A House that gains a reputation for aggressive espionage is likely to attract more counter-espionage efforts from its rivals, creating a dangerous cycle of escalating spy wars.

Rivals who detect your espionage efforts are likely to respond in kind, targeting your colonies with sabotage, tech theft, or even assassination attempts. The cost of countering these actions can quickly exceed the initial benefits of your own espionage investments.

### Finding the Balance

In EC4X, effective use of espionage is about balance. Strategic investments in covert operations can provide decisive advantages, but overextending your reach can be disastrous. Successful Dukes must weigh the immediate gains of espionage against the long-term costs to prestige, diplomatic relations, and overall stability. In the quest for the imperial throne, it is often the House that combines subtlety with strength, and deception with diplomacy, that emerges victorious.

# 9.0 Data Tables

## 9.1 Space Force (WEP1)

CST = Minimum CST Level
PC = Production Cost
MC = Maintenance Cost (% of PC)
AS = Attack Strength
DS = Defensive Strength
CC= Command Cost
CR = Command Rating
CL = Carry Limit

| Class | Name              | CST | PC  | MC  | AS  | DS  | CC  | CR  | CL  |
|:-----:| ----------------- |:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| CT    | Corvette          | 1   | 20  | 3%  | 2   | 3   | 1   | 2   | NA  |
| FG    | Frigate           | 1   | 30  | 3%  | 3   | 4   | 2   | 3   | NA  |
| DD    | Destroyer         | 1   | 40  | 3%  | 5   | 6   | 2   | 4   | NA  |
| CL    | Light Cruiser     | 1   | 60  | 3%  | 8   | 9   | 3   | 6   | NA  |
| CA    | Heavy Cruiser     | 2   | 80  | 4%  | 12  | 13  | 3   | 7   | NA  |
| BC    | Battle Cruiser    | 3   | 100 | 4%  | 16  | 18  | 3   | 8   | NA  |
| BB    | Battleship        | 4   | 150 | 4%  | 20  | 25  | 3   | 10  | NA  |
| DN    | Dreadnought       | 5   | 200 | 5%  | 28  | 30  | 4   | 12  | NA  |
| SD    | Super Dreadnought | 6   | 250 | 5%  | 35  | 40  | 5   | 14  | NA  |
| PB    | Planet-Breaker    | 10  | 400 | 5%  | 50  | 20  | 6   | 6   | NA  |
| CV    | Carrier           | 3   | 120 | 3%  | 5   | 18  | 3   | 8   | 3   |
| CX    | Super Carrier     | 5   | 200 | 5%  | 8   | 25  | 4   | 10  | 5   |
| FS    | Fighter Squadron  | 3   | 20  | 3%  | 4   | 3   | NA  | NA  | NA  |
| RR    | Raider            | 3   | 150 | 4%  | 12  | 10  | 3   | 4   | NA  |
| SC    | Scout             | 1   | 50  | 1%  | 1   | 2   | 1   | NA  | NA  |
| SB    | Starbase          | 3   | 300 | 5%  | 45  | 50  | NA  | NA  | NA  |

## 9.2 Ground Units (WEP1)

| **Class** | **Name**         | CST | PC  | MC  | AS  | DS  |
| --------- | ---------------- |:---:| --- | --- |:---:|:---:|
| PS        | Planetary Shield | 5   | 100 | 5%  | 0   | 100 |
| GB        | Ground Batteries | 1   | 20  | 3%  | 10  | 8   |
| AA        | Armies           | 1   | 15  | 2%  | 3   | 5   |
| MD        | Space Marines    | 1   | 25  | 2%  | 6   | 6   |

## 9.3 Spacelift Command (WEP1)

| **Class** | **Name**         | CST | PC  | MC  | CL  | DS  |
|:---------:| ---------------- |:---:|:---:|:---:|:---:|:---:|
| SP        | Spaceport        | 1   | 100 | 5%  | 5   | 50  |
| SY        | Shipyard         | 1   | 150 | 5%  | 10  | 70  |
| ET        | ETAC             | 1   | 50  | 3%  | 1   | 10  |
| TT        | Troop Transports | 1   | 30  | 3%  | 1   | 15  |

## 9.4 Prestige

| **Category**      | **Action/Event**                               | **Prestige Change** |
| ----------------- | ---------------------------------------------- |:-------------------:|
| **Economic**      | Establish a new colony                         | +5                  |
|                   | Max out the population of a colony             | +3                  |
|                   | Reach 50% IU of PU (per colony)                | +1                  |
|                   | Reach 75% IU of PU (per colony)                | +2                  |
|                   | Reach 100% IU of PU (per colony)               | +3                  |
|                   | Reach 150% IU of PU (per colony)               | +5                  |
|                   | Increase a planet’s class via terraforming     | +5                  |
|                   | Achieve a new tech level                       | +2                  |
| **Military**      | Destroy an enemy Task Force                    | +3                  |
|                   | Force an enemy Task Force to retreat           | +2                  |
|                   | Invade or blitz a planet successfully          | +10                 |
|                   | Lose a planet to an enemy                      | -10                 |
|                   | Get ambushed by a cloaked fleet                | -1                  |
|                   | Lose a Starbase                                | -5                  |
|                   | Destroy an enemy Starbase                      | +5                  |
| **Espionage**     | Successful Tech Theft                          | +2                  |
|                   | Successful Low-Impact Sabotage                 | +1                  |
|                   | Successful High-Impact Sabotage                | +3                  |
|                   | Successful Assassination                       | +5                  |
|                   | Successful Cyber Attack                        | +2                  |
|                   | Successful Economic Manipulation               | +3                  |
|                   | Successful Psyops Campaign                     | +1                  |
|                   | Failed espionage action (detected)             | -2                  |
|                   | Over-investment in Espionage Budget (> 5%)     | -1 per excess 1%    |
|                   | Over-investment in Counter-Intelligence (> 5%) | -1 per excess 1%    |
| **Scout Actions** | Successful Spy on a Planet                     | +1                  |
|                   | Successful Hack of a Starbase                  | +2                  |
|                   | Successful Spy on a System                     | +1                  |
|                   | Scout detected and destroyed                   | -3                  |
| **Setbacks**      | Excessive tax rate (> 65%) per turn            | -2 (cumulative)     |
|                   | Failure to meet maintenance costs (per turn)   | -5 (cumulative)     |

### Notes on Cumulative Penalties:

1. **Excessive Tax Rate Penalty**:
   
   - Penalty escalates for consecutive turns above the 65% tax rate:
     - Turn 1: -2 points
     - Turn 2: -3 points (cumulative total: -5 points)
     - Turn 3: -4 points (cumulative total: -9 points)
     - Continues increasing by 1 additional point each turn.

2. **Missed Maintenance Costs Penalty**:
   
   - Penalty escalates for consecutive turns of missed maintenance payments:
     - Turn 1: -5 points
     - Turn 2: -7 points (cumulative total: -12 points)
     - Turn 3: -9 points (cumulative total: -21 points)
     - Continues increasing by 2 additional points each turn.
