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

EC4X is intended to facilitate remote play between friends over email or local tabletop play. Future releases will be server/client based and written in Rust. EC4X is a flexible framework; adapt it to your own requirements.

EC4X pays homage and is influenced by the following great titles:

- Esterian Conquest (EC)
- Victory by Any Means (VBAM)
- Empire of The Sun (EOS)
- Space Empires 4X
- Solar Starfire
- Stellar Conquest
- Fractal, Beyond the Void

Although not required, it is highly recommended to purchase physical copies of these classics to fully appreciate the art. Dive deep.

Esterian Conquest was an obscure bulletin board system (BBS) door game from the early 1990's that inspired this project. EC is a gem, and great times were had battling friends, family, and anonymous players over the phone lines on slow noisy modems. Graphics were crude but the ANSI art was fantastic. The early 1990's was a simple time, just before the internet blew up and super computers landed in all of our pockets. EC turns progressed once a day and most of the strategic planning occurred in one's imagination offline. Players eagerly awaited each new day's battle reports, and games would last several weeks to several months. Maps and reports were printed on dot matrix printers and marked up with pencil to no end. The times were good. That era is long gone but tabletop wargaming is still alive and well in 2024. EC4X is an attempt to recapture the magic.

While not intended to be an accounting exercise, there is enough complexity in EC4X to allow for dynamic strategic decision making and surprising outcomes.

The background narrative of EC4X is wide open and only limited by the scope of your imagination.

# 1.0 How to Play

## 1.1 Prestige

Prestige is the key to victory. Crush your rivals and take the title of Emperor.

There are several paths to the throne:

1. Destroy all of your rival's assets.
2. Capture every homeworld.
3. Crush your opponent's will and force them to capitulate.
4. Employ a combination of tactical prowess and subversion to outfox your opponents.
5. Focus on economic development and population growth to outperform everyone else.
6. Let your rivals destroy one another, then clean house afterwards.
7. All of the above.

This list is not exhaustive. Use whatever means the game allows to win.

Prestige points are won through a combination of military victory, population growth, production, subversion, technological development, and various other factors.
Performing poorly, mismanaging your colonies, acts of sabotage, and acts of subterfuge by other Houses will lower your prestige.

The goal of EC4X is to provide enough asymmetry to prevent a stalemate. **(work in progress..... need help play-testing and regression analysis)**

A table of Prestige values is listed in Section 9.

## 1.2 Turns

Each turn comprises four phases

1. Income phase
2. Command phase
3. Conflict phase
4. End of turn phase

### 1.3 TODO: Explain actions during eash phase

# 2\.0 Game Assets

## 2\.1 Starmap

The starmap consists of a 2D hexagonal grid, each a flat-top hex that contains a solar system, interconnected throughout by procedural generated jump lanes. The map is sized by rings around the center hub, one per number of players.

The map takes inspiration from VBAM, and the 1st or 2nd edition campaign guides may be used to spawn a random map. The method is briefly explained below.

The center of the map is a special hub occupied by the last holdouts of the former imperial Empire. This system is heavily guarded by fighter squadrons and the home planet is fortified against invasion. The former Emperor has no offensive ships to speak of, which were scuttled by their crews at the height of the collapse. This is prime territory ripe for the taking. He who controls the hub holds great strategic power.

Solar systems have special traits and are procedural generated. They are filled with planets, moons, and gas giants that are variable in their suitability for colonization and production.

There are three classes of jump lanes: restricted, minor, and major. The hub is guaranteed to have six jump lanes connecting it to the first ring, making it an important strategic asset. Homeworlds on the outer ring will have three lanes. The number of lanes connecting the other hexes are randomly generated in accordance with VBAM. The class of all lanes are random.

Movement across the lanes is explained in Section 4.

Players start the game with one homeworld (An Abundant Eden planet, Level IV colony with 420 PU), 210 Monero (XMR) in the treasury, one spaceport, one shipyard, one fully loaded ETAC, a Cruiser, two Destroyers, and two Scouts. All tech levels start at zero.

Each player's homeworld should be placed on the outer ring, as far as strategically possible from rival home system(s).

## 2\.2 Solar Systems

Solar systems contain various F, G, K, and M class stars that are orbited by at least one terrestrial planet, suitable for colonization and terraforming. Otherwise systems are not charted and of no consequence to the task at hand.

Roll on the planet class and system resources tables below to determine the attributes for each hex on the starmap, excluding homeworlds.

Note that each newly established colony begins as Level I and has potential to develop into the max Population Unit (PU) for that planet. Move colonists from larger colonies to smaller colonies to increase population growth over the natural birth rate.

Advances in terraforming tech will allow planets to upgrade class and living conditions.

**Planet Class Table**

| Roll 1D10 | Class    | Colony Potential | PUs       |
|:---------:| -------- | ---------------- |:---------:|
| 0         | Extreme  | Level I          | 1 - 20    |
| 1         | Desolate | Level II         | 21 - 60   |
| 2, 3      | Hostile  | Level III        | 61 - 180  |
| 4, 5      | Harsh    | Level IV         | 181 - 500 |
| 6, 7      | Benign   | Level V          | 501- 1k   |
| 8*        | Lush     | Level VI         | 1k - 2k   |
| 9*        | Eden     | Level VII        | 2k+       |

\*Note: if the roll above is a natural eight (8), add a +1 modifier to your roll on the raw materials table. If the roll is a natural nine (9) add a +2 modifier.

**System Resources Table**

| Modified Roll 1D10 | Raw Materials |
|:------------------:| ------------- |
| 0                  | Very Poor     |
| 2, 3               | Poor          |
| 4 - 7              | Abundant      |
| 8, 9               | Rich          |
| 10+                | Very Rich     |

## 2.3 Military

### 2\.3.1 Space Force Ships

The base game includes a number of imperial classed space combatants listed in Section 9.

Feel free to create your own ships and races for asymmetrical warfare or narrative purposes.

### 2\.3.2 Spacelift Command

The Spacelift Command provides commerce and transportation services in support of the House's expansion efforts. Assets are owned by the House and commanded by senior Space Force officers. Units are crewed and operated by loyal House citizens.

Spacelift assets have no offensive weapons capability, and un-escorted units are easily destroyed by rival forces. 

Spacelift Command attributes are listed in Section 9.

#### 2.3.2.1 Spaceports

Spaceports are large ground based facilities that launch heavy-lift ships and equipment into orbit. They require two months (two turns) to build and have five docks available for planetside ship construction.

#### 2.3.2.2 Shipyards

Shipyards are gateways to the stars. They are large bases constructed in orbit and require a spaceport to build over a period of three months (three turns).

The majority of ship construction and repair will occur at these important facilities.

Shipyards are equipped with 10 docks for construction and repair, and are fixed in orbit. Built multiple yards to increate colony ship construction capacity.

#### 2.3.2.3 Environmental Transformation And Colonization (ETAC)

ETACs plant a seed by establishing colonies on uninhabited planets. After use they are scrapped and used by the colony to begin the long terraforming process. 

ETACS have a Carry Limit (CL) of one Population Transfer Unit (PTU) and must be loaded with colonists.

#### 2.3.2.4 Troop Transports

Troop Transports are specialized ships that taxi Space Marine divisions between solar systems, along with their required combat gear, armored vehicles, and ammunition. They have a CL of one Marine Division (MD).

### 2\.3.3 Squadrons

The Space Force is organized by squadrons. Each squadron is commanded by a flagship with a Command Rating (CR) that will accommodate ships with a Command Cost (CC) that sum to less than or equal to the CR. This enables players to tactically group various classes of ships to balance combat effectiveness.

Squadrons fight as a unit and die as a unit. A squadron's total AS and DS values constitute a sum of all the ships under a flagship's command (including itself).

In non-hostile systems, ships in a squadron may be reassigned to an already existing squadron if the new flagship's CR allows. Squadrons may constitute a solo flagship.

Squadrons are only commissioned in systems with a functioning shipyard.

### 2\.3.4 Fleets

Squadrons are grouped together into fleets for the purpose of traversing jump lanes. Fleets may be joined or split off (creating new fleets) for strategic purposes in any non-hostile system. There is no limit to the number of squadrons assigned to a fleet.

### 2\.3.5 Task Force

A Task Force is temporary grouping of squadrons organized for combat. After the cessation of hostilities the task force is disbanded and surviving squadrons return to their originally assigned fleets.

## 2\.4 Special Units

### 2\.4.1 Fighter Squadrons & Carriers

Fighters are small ships commissioned in Fighter Squadrons (FS) that freely patrol a system. They are based planetside and never retreat from combat.

There is no limit to the number of fighter squadrons deployed in a home system.

Because of their fast lightweight nature, fighters are considered to be in a crippled combat state, but without a reduction in attack strength (AS).

Carriers (CV) transport fighter squadrons between systems. Standard carriers hold up to three; Super Carriers (CX) hold up to five.

### 2\.4.2 Scouts

Scouts (SC) are small drones outfitted with advanced sensors that assist with electronic warfare and information gathering. They are masters of Electronic Intelligence (ELI).

Fleets containing Scouts are the only units capable of countering Raiders (Refer to Section 2.4.3). Multiple Scouts assigned to the same fleet operate as a mesh network, and their ELI capability is merged and magnified. 

Scouts maintain an element of stealth when performing solo missions for information gathering (spy) purposes in enemy solar systems. Scouts are *not* equipped with cloaking tech. They can only hide by themselves and no other ships.

For every turn that a spy Scout operates in enemy territory occupied by rival fleets, the rival will roll on the Spy Detection Table below (for each fleet) to determine if the spy Scout is detected. If the Scout is detected, it is destroyed. Rival fleets must contain at least one Scout to detect.

Detection Roll Process:

1. Identify the ELI for the defending player's fleet along the top row.
2. Find the rival Spy Scout's ELI in the first column.
3. Roll a 1D20 and add the calculated modifier (explained below).
4. If the total is greater than the number indexed, the spy is detected and destroyed.

Crippled Scouts lose their ELI sensors until repaired.

**Spy Detection Table**

| \*Fleet -> | ELI1 | ELI2 | ELI3 | ELI4 | ELI5 |
| ----------:|:----:|:----:|:----:|:----:|:----:|
| Spy ELI1   | > 12 | > 7  | > 3  | > 1  | > 1  |
| Spy ELI2   | > 16 | > 12 | > 7  | > 3  | > 1  |
| Spy ELI3   | > 18 | > 16 | > 12 | > 7  | > 3  |
| Spy ELI4   | > 19 | > 18 | > 16 | > 12 | > 7  |
| Spy ELI5   | NA   | > 19 | > 18 | > 16 | > 12 |

\*Total the number of Scouts within the same fleet and subtract one. This is the die roll modifier.

\*The maximum modifier is +2

Example:

```
A detecting fleet contains three ELI4 Scouts:
3 - 1 = 2. The die roll modifier is +2
```

**If the fleet has Scouts with different ELI levels, use this method:**

First calcualte the ELI Integration Index (EII):

- ELI_Min = the lowest ELI level present in the fleet.
- ELI_Max = the highest ELI level present in the fleet.

```
EII = (ELI_Max + ELI_Min) / 2
```

Use the EII as the base Tech Level in the Detection Table (round down).

Update the die roll modifier as follows:

1. Base: subtract 1 from the ***total number of Scouts***
2. Penalty: subtract 1 from the ***number of different tech levels***
3. Modifier = base - penalty

Example:

```
Fleet Composition:

1 ELI2 Scout
2 ELI3 Scouts
1 ELI4 Scout

We have four(4) scouts with three(3) different tech levels.

ELI Range Calculation:

ELI_Min = 2 (the lowest level available [ELI2])
ELI_Max = 4 (the highest level available [ELI4])

EII Calculation:

EII = (ELI_Max + ELI_Min) / 2
EII = (4 + 2) / 2 = 3

Use ELI3 in the Detection Table (top row).

Now calculate the die roll modifier:
1) Base = 4 - 1 = 3
2) Penalty = 3 - 1 = 2
3) Modifier = 3 - 2 = +1
```

### 2\.4.3 Raiders

The Raider (RR) is the most advanced ship in the arsenal, outfitted with cloaking technology. They are expensive but have the firepower of a Heavy Cruiser (CA).

Fleets containing Raiders are cloaked, and roll for a chance to pass undetected against opposing forces on the Stealth Table below.

Crippled Raiders lose their cloaking ability until repaired.

**Stealth Table**

| Tech Level | % Chance | 1D20 Roll |
|:----------:|:--------:|:---------:|
| CLK1       | 30       | > 14      |
| CLK2       | 40       | > 12      |
| CLK3       | 50       | > 10      |
| CLK4       | 60       | > 8       |
| CLK5       | 70       | > 6       |
| CLK6       | 80       | > 4       |
| CLK7       | 90       | > 2       |

When encountering rival fleets **without Scouts**:

Roll a 1D20 for the highest rated CLK Raider in the fleet, indexing by tech level. Multiple cloaked fleets converging on a Task Force roll individually for stealth. 

If a fleet fails for stealth, then the fleet is detected. 

## **TODO: Not finished working this out**

Opposing fleets with Scouts have the opportunity to counter for stealth. 

Select the fleet from the stealth player's Task Force with the highest rated CLK.  

Select the highest rated ELI from the opposing player's fleet and detect for stealth as described below:

1. Identify the fleet's ELI along the top row.
2. Find the Raider's CLK tech level in the first column.
3. Roll a 1D20 and add the calculated modifier (explained below).
4. If the total is greater than the number indexed, the cloaked fleet is detected.

**Raider Detection Table**

| \*Scout Fleet -> | ELI1 | ELI2 | ELI3 | ELI4 | ELI5 |
| ---------------- |:----:|:----:|:----:|:----:|:----:|
| CLK1             | > 14 | > 9  | > 5  | > 2  | > 1  |
| CLK2             | > 17 | > 14 | > 9  | > 5  | > 2  |
| CLK3             | > 19 | > 17 | > 14 | > 9  | > 5  |
| CLK4             | NA   | > 19 | > 17 | > 14 | > 9  |
| CLK5             | NA   | NA   | > 19 | > 17 | > 14 |
| CLK6             | NA   | NA   | NA   | > 19 | > 17 |
| CLK7             | NA   | NA   | NA   | NA   | > 19 |

*Total the number of Scouts within the same fleet and subtract one. This is the die roll modifier.

*The maximum modifier is +4

**If Scouts in the opposing fleet have mixed ELI tech, use same EII method described in section 2.4.3 to find the adjusted ELI and die roll modifier.**

### 2\.4.4 Starbases

Starbases (SB) are powerful orbital fortresses that facilitate planetary defense and economic development via ground weather modification and advanced telecommunications.

Starbases require five months (five turns) to construct require a shipyard. They remain in orbit and do not move out of their home solar systems.

Starbases boost the population growth-rate and Industrial Units (IU) of a colony by 5% each, every turn (preliminary). 

Example: under normal conditions the natural birthrate of a colony is 2%. With three Starbases, the rate is:

```
2% * (1 + (0.05 * 3)) = 2.3% 
```

Crippled Starbases do not yield benefits until they are repaired.  

### 2\.4.7 Planetary Shields & Ground Batteries

Planetary Shields (PS) and Ground Batteries (GB) are planet based assets that provide an extra layer of defense to a player's colonies.

Planetary Shields protect your colonies from orbital bombardment. With increasing SLD levels they have a higher probability of absorbing direct hits, and also become more powerful.

| SLD Level | % Chance | 1D20 Roll | % of Hits Blocked |
|:---------:|:--------:|:---------:| ----------------- |
| SLD1      | 15       | 18 - 20   | 25%               |
| SLD2      | 30       | 15 - 20   | 30%               |
| SLD3      | 45       | 12 - 20   | 35%               |
| SLD4      | 60       | 8 - 20    | 40%               |
| SLD5      | 75       | 5 - 20    | 45%               |
| SLD5      | 90       | 2 - 20    | 50%               |

Upgrading a Planetary Shield to a new SLD level requires salvaging the old shield and replacing it with a new one. A Planet may not have more than one shield.

Ground Batteries are immobile, low-tech, land based units that have the firepower of a Battleship at half the cost. They lob kinetic shells into orbit and are not upgraded by technology and research.

Ground Batteries are the only units that are constructed in the span of a single turn, and colonies may build them to no limit.

### 2.4.8 Planet-Breaker

Planet-Breakers (PB) are high technology, late-game ships that penetrate planetary shields.

TODO: Develop this further. Do we need a specific tech or just a ship, or both?

### 2\.4.9 Space Marines & Armies

Space Marines are ferocious devil dogs that capture rival planets. They deploy in division sized units (MD) and will never surrender or abandon one of their own.

Marines are dropped on rival planets by troop transports during an invasion or blitz.

Armies (AA) garrison your colonies and eradicate invaders. Their orders are to take no prisoners and protect the colony at all cost.

Marines fight alongside the Army if garrisoned planetside.

## 2.5 Space Guilds

A vast decentralized network of trade, commerce, transport, industry, tech, and mining activities occur between and within House colonies. Most of this activity is abstracted away and occurs in the background of EC4X's strategic focus. Commercial civilian ships freely ply the jump lanes between colonies.

Numerous Space Guilds compete for business in unregulated, private capital markets.

The Guilds may be contracted to provide various critical services to the House, most notably the transport of PTU and goods between colonies. Space Guilds are also known to deal in the black arts of subversion and subterfuge, for a price.

# XY\.0 Economics

The standard unit of account in EC4X is Monero (XMR), i.e. money. 

The power of a House is fueled by economic might, which in turn is a function of population growth and gains in science and technology.

XMR settle near instantaneously on the inter-dimensional Phoenix network. (All comms and data transfers are instantaneous. Don't question; it's magic).

## XY\.1 Principles

**Population Unit (PU)**: A unit of population that provides 1 XMR of productivity to the House.   

**Population Transfer Unit (PTU)**: A quantity of people and their associated cost of cargo and equipment required to colonize a planet. One PTU is approximately 50k souls. 

The relationship between PSU and PU is exponential. As the population grows the laws of diminishing returns take effect and the amount of production generated per individual is reduced. People are doing less work while the colony continues to slowly gain wealth. Think of gains in efficiency, productivity, and quality of life. 

This model is disinflationary; inflation asymptotically approaches zero over time, i.e. Monero.

Reckless fiat monetary policy left the former Empire in ruins. Demagoguery, excessive money printing, deficit spending, out of control socialist entitlements, and simple greed by bureaucratic elites led directly to revolution and collapse. The Empire cannibalized itself from the inside out. As Duke your obligation is to rebuild from the ashes and lead your House to prosperity.  

A high PSU to PU ratio is an advantage when transferring colonists from larger planets to smaller planets. The mother-colony is able to contribute a relatively large number of people to the new colony without a significant loss of production to itself. This incentives expanding population across newly acquired planets.

The equations (in Python) for converting PU to PSU:

```
  psu = pu - 1 + np.exp(0.00657 * pu)
```

Code for converting PSU back to PU:

```
import numpy as np
from scipy.special import lambertw

psu = 100000 #example

def logsumexp(x):
    c = x.max()
    return c + np.log(np.sum(np.exp(x - c)))

x = np.float64(657*(psu + 1)/100000)

pu = -100000/657*lambertw((657*np.exp(x - logsumexp(x)))/100000) + psu + 1
```

An Excel spreadsheet is included in the GitHub 'assets' folder to visualize the relationship. You need to have "Python in Excel" enabled for Excel. TODO: standalone Python scripts will be provided in the repo.

![Alt text](https://github.com/greenm01/ec4x/blob/main/assets/pu_to_ptu.png)
![Alt text](https://github.com/greenm01/ec4x/blob/main/assets/ptu_to_pu.png)

**Gross Colony Product (GCP)**: A monetary measure of the market value of all the final goods and services produced and rendered in a turn for each of your colonies, measured in XMR.

```
GCP = (PU * raw_index + IU) * el_mod
```

**RAW INDEX Table**

| RAW       | Eden | Lush | Benign | Harsh | Hostile | Desolate | Extreme |
| --------- |:----:|:----:|:------:|:-----:|:-------:|:--------:|:-------:|
| Very Poor | 60%  | 60%  | 60%    | 60%   | 60%     | 60%      | 60%     |
| Poor      | 80%  | 75%  | 70%    | 65%   | 64%     | 63%      | 62%     |
| Abundant  | 100% | 90%  | 80%    | 70%   | 68%     | 66%      | 64%     |
| Rich      | 120% | 105% | 90%    | 75%   | 72%     | 69%      | 66%     |
| Very Rich | 140% | 120% | 100%   | 80%   | 76%     | 72%      | 68%     |

Look up the Raw Material classification of your colony's system in the RAW column, and cross index with the planet's habitable conditions.

**Net Colony Value (NCV)**: The net value of taxes collected from each of your colonies.

```
NCV = GCP * tax_rate
```

**Tax Rate**: The tax rate that applies to all of your colonies. Setting the tax rate above 65% will result in a negative impact to your prestige as a ruler, and stall population growth.

**House Treasury**: The total sum of NCV collected from colonies is transferred to the House treasury at the beginning of each month (turn). Unspent XMR from each turn rollover and earn 2% interest on loans to the Space Guild.

**Industrial Units (IU)**: The house may invest in the planetary industry of each colony. IUs may be placed on Level III+ colonies. IU invested above 50% of the colony's PU will be directed to civilian infrastructure projects that increase House prestige.

## XY\.2 Population Growth

Colonists are hard at work making babies for the House, and the population growth rate under normal conditions is 2% (preliminary) per turn.

A logistical growth function is used for the calculation. Each planet class has an upper bound on the population it can support. This gives a nice 's' curve distribution, and lends incentive to terraform less hospitable planets.

[The Logistic Equation](https://michaelneuper.com/posts/modelling-population-growth-in-python/)

![Alt text](https://github.com/greenm01/ec4x/blob/main/assets/logistic_population_growth.png)

## XY.3 Colonization

ETACs plant a flag in unoccupied Solar Systems and set the initial conditions for terraforming. Their capacity to move PTU is limited to one unit.

The Space Guilds are contracted to transfer larger populations between existing Colonies in civilian Starliners. Passengers are kept in status to minimize living space, and all of their supplies and equipment for their new destination are tightly packed into the cargo hold. 

The cost is expensive and dependent upon the livable conditions of the destination planet. The logistics are abstracted for game purposes; delivery time (turns) across jump lanes is in accordance with Section 4.0.

| Conditions | XMR/PTU |
| ---------- |:-------:|
| Eden       | 5       |
| Lush       | 6       |
| Benign     | 8       |
| Harsh      | 11      |
| Hostile    | 14      |
| Desolate   | 18      |
| Extreme    | 25      |

Colonists do not start contributing to the colony's economic production for at least one full turn after arrival.

## XX\.4 TODO: Maintenance Costs

# XYZ\.0 Research & Development

## XYZ.1 Research Points (RP)

Each turn, players may invest XMR in RP to further their R&D efforts. 

R&D upgrades may be purchased in the first and sixth months of the Terran calendar, i.e. the first and sixth turns of each game year. Levels must be purchased in sequential order, and only one level per R&D area each upgrade cycle.

There are three areas of investment:

- Economic RP (ERP)
- Science RP (SRP)
- Technology RP (TRP)

Economic Levels (EL) are purchased with ERP and Science Levels (SL) are purchased with SRP. Science drives engineering, and new technologies are developed and purchased directly with TRP. EL and SL are correlated.

In standard EC4X games, Houses start at EL1 and SL1. Consider boosting these to expedite the game for impatient players, although the game year should be advanced from 2001 to match.

**TODO: Add a roll for "research breakthrough" for every first and sixth month.**

## XYZ.2 Economic Level (EL)

EL represents the entrepreneurial skills and general education level of House citizens.

EL is not a specific reflection of scientific or technological advancement, although they are correlated.

A House's GCP benefits from EL upgrades by 5% per level. The economy is tied to entrepreneurial ambition and citizen education.

The formula for ERP in XMR is:

```
1 ERP = (10 + 0.015(GCP)) XMR
```

Example: to purchase 10 ERPs with a GCP of 500, the cost in XMR is:

```
10 ERP = 10(10 + 0.015(500)) = 175 XMR   
```

The cost in ERP to advance one EL level is:

```
ERP = 40 + EL(10) (maxing at 140 ERP)
```

| EL  | ERP Cost | EL MOD |
|:---:|:--------:|:------:|
| 01  | 50       | 0.05   |
| 02  | 60       | 0.10   |
| 03  | 70       | 0.15   |
| 04  | 80       | 0.20   |
| 05  | 90       | 0.25   |
| 06  | 100      | 0.30   |
| 07  | 110      | 0.35   |
| 08  | 120      | 0.40   |
| 09  | 130      | 0.45   |
| 10  | 140      | 0.50   |
| 11+ | 140      | 0.55   |

## XYZ.3 Science Level (SL)

Science explores new knowledge methodically through observation and experimentation, in alignment with nature. SL is dependent on the education and skill levels of citizens, and thus EL. 

Advancing to the next SL requires the House have previously developed an equivalent level of EL. For example, advancing from SL1 to SL2 requires the house to be at EL2 or greater.

The cost of SRP is dependent upon the current SL.

```
1 SRP = 2 + SL(0.5) XMR
```

Example: To purchase 10 SRPs at SL2, the price in XMR is:

```
10 SRP = 10(2 + 2(0.5)) = 30 XMR
```

The cost in SRP to advance one SL level is:

```
SRP = 20 + SL(5) (Maxing at 55 SRP)
```

| SL  | SRP Cost |
|:---:|:--------:|
| 01  | 25       |
| 02  | 30       |
| 03  | 35       |
| 04  | 40       |
| 05  | 45       |
| 06  | 50       |
| 07+ | 55       |

## XYZ.4 Engineering R&D

Engineering is the practical application of science, and thus dependent upon advances in SL. Engineering advancements are made with direct investment in TRP.

In VB4X, advances in engineering are tied to the Military and Industrial complex, although development also carries over to commerce, mining, agriculture, industry, propulsion systems, computing, AI, robotics, services, medicine, and almost every other realm of material human flourishing.

The cost of TRP is dependent upon the required SL for the technology being developed.

```
1 TRP = (50 + 20(SL))/10 + 0.001(GCP) XMR
```

For example, to purchase 5 TRPs towards the development TER3 with a GCP of 500, the price in XMR is:

```
5 TRP = 5((50 + 20(3))/10 + 0.001(500)) = 57.5 XMR
```

New engineering technologies are purchased directly with TRP.

**TODO: work out TRP cost for each tech level below.**

## XYZ\.5 Construction (CST)

Upgrades improve the construction capability and capacity of planet based factories, Spaceports, Shipyards. Upgrades to existing units are automatic and zero cost.

CST will open up new, larger hulled classes of combat ships.

Round up to the nearest whole number when recalculating a capacity increase.

| CST Level | SL  | TRP Cost | Capacity Increase |
|:---------:|:---:| -------- |:-----------------:|
| CST1      | 1   |          | 10%               |
| CST2      | 2   |          | 10%               |
| CST3+     | 3+  |          | 10%               |

The maxium construction level is CST10.

## XYZ\.6 Weapons (WEP)

Upgrades improve the Attack Strength (AS) and Defense Strength (DS) of combat ships by 10% for each Weapons level (rounded down). 

For every WEP increase, Production Cost (PC) per unit increases by 10%.

Upgrades do not apply to preexisting ships.

| Weapons Level | SL  | TRP Cost |
|:-------------:|:---:| -------- |
| WEP1          | 1   |          |
| WEP2          | 2   |          |
| WEP3+         | 3+  |          |

The maximum weapons level is WEP10.

## XYZ\.7 Terraforming (TER)

Terraforming improve a planet's livable conditions, and thus the population limit. There are seven Terraforming levels that correspond directly with the planet classes.  

| TER Level | SL  | TRP Cost | Planet Class | PU        | PTU             |
|:---------:|:---:| -------- | ------------ |:---------:|:---------------:|
| TER1      | 1   |          | Extreme      | 1 - 20    | 1 - 20          |
| TER2      | 2   |          | Desolate     | 21 - 60   | 21 - 60         |
| TER3      | 3   |          | Hostile      | 61 - 180  | 61 - 182        |
| TER4      | 4   |          | Harsh        | 181 - 500 | 183 - 526       |
| TER5      | 5   |          | Benign       | 501 - 1k  | 527 - 1,712     |
| TER6      | 6   |          | Lush         | 1k - 2k   | 1,713 - 510,896 |
| TER7      | 7   |          | Eden         | 2k+       | 510,896+        |

Planets may not skip a class in their terraforming development.

## XYZ.8 Electronic Intelligence (ELI)

ELI technology enables the detection of cloaked Raiders and enemy Scouts, and the gathering of intelligence from rival assets.

Upgrades do not apply to preexisting Scouts.

| ELI Level | SL  | TRP Cost |
|:---------:|:---:| -------- |
| ELI1      | 1   |          |
| ELI2      | 2   |          |
| ELI3+     | 3+  |          |

The maximum ELI level is ELI5.

## XYZ\.9 Cloaking (CLK)

Cloaking enables Raiders to cloak their assigned fleets with increasing levels of probability.

Upgrades do not apply to preexisting Raiders.

| CLK Level | SL  | TRP Cost |
|:---------:|:---:| -------- |
| CLK1      | 3   |          |
| CLK2      | 4   |          |
| CLK3+     | 5+  |          |

The maximum CLK level is CLK7.

## XYZ\.10 Planetary Shields (SLD)

Planetary Shields protect a colony from bombardment and invasion.

Upgrades do not apply to preexisting shields. Salvage and build a new one.

| SLD Level | SL  | TRP Cost |
|:---------:|:---:| -------- |
| SLD1      | 5   |          |
| SLD2      | 6   |          |
| SLD3+     | 7+  |          |

The maximum SLD level is SLD5.

# 3.0 Construction

Construction and repair of House assets is accomplished planetside or in orbit, with restrictions. 

The number of turns required to newly construct an asset, unless otherwise specified, is equal to the PC times 0.5 (rounded down). Assets remain decommissioned through the activity period.

TODO: Explain construction capacity and rate

## 3.1 Planetside Construction

Ground units and fighter squadrons are produced via colony industry, distributed across the surface or in underground factories.

Ships (excluding fighter squadrons) constructed planetside incur a 100% PC increase due to the added cost of orbital launch, and require a spaceport to commission.

## 3.2 Planetside Repair

Ground units and fighter squadrons are repaired and refitted planetside.

## 3.3 Orbital Construction

Shipyard construction of a ship in orbit is the standard method of commissioning a vessel, and incurs no penalty.

## 3.4 Orbital Repair

Ship repairs require a Shipyard. The cost of repair equals one quarter (25%) of the unit's PC.

Example: A player wishes to repair a crippled tech-level III Cruiser. The cost is:

```
7 * 0.25 = 1.75 XMR.
```

The logistics of repairing a ship planetside and returning it to orbit make it economically infeasible. Ships may be salvaged at a colony without restriction and earn 50% of the original PC back to the House treasury.

# 4\.0 Movement

## 4.1 Fleet Orders

Possible fleet missions are listed in the table below. These are the classic fleet orders from Esterian Conquest, modified for EC4X.

| No.  | Mission                 | Requirements                             |
| ---- | ----------------------- | ---------------------------------------- |
| 00   | None (hold position)    | None                                     |
| 01   | Move fleet (only)       | None                                     |
| 02   | Seek home               | None                                     |
| 03   | Patrol a system         | None                                     |
| 04   | Guard a Starbase        | Combat ship(s)                           |
| 05   | Guard/Blockade a planet | Combat ship(s)                           |
| 06   | Bombard a planet        | Combat ship(s)                           |
| 07   | Invade a planet         | Combat ship(s) & loaded Troop Transports |
| 08   | Blitz a Planet          | Loaded Troop Transports                  |
| 09   | Spy on a planet         | At least one Scout ship                  |
| 10\* | Hack a Starbase         | At least one Scout ship                  |
| 11   | Spy on a system         | At least one Scout ship                  |
| 12   | Colonize a planet       | At least one ETAC                        |
| 13   | Join another fleet      | None                                     |
| 14   | Rendezvous at system    | None                                     |
| 15   | Salvage                 | None                                     |

\* New to EC4X

## 4.2 TODO: Jump Lanes

# 5\.0 Combat

## 5\.1 Principles

### 5\.1.1 Rules of Engagement (ROE)

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

A fleet's ROE is defined when it's created, or changed any time before engaging in combat. The ROE may not be changed during combat.

### 5\.1.2 Combat State

Squadron units are either undamaged, crippled, or destroyed.

**Attack Strength (AS)** represents a unit's offensive firepower and is a mutable type.

**Defense Strength (DS)** represents a unit's defensive shielding and is an immutable type.

**Reduced**: This term is used to describe a transition of state, e.g. undamaged to crippled, crippled to destroyed.

**Undamaged**: A unit’s life support systems, hull integrity, and weapons systems are fully operational.

**Crippled**: When an undamaged unit’s DS is equaled in battle by hits, that unit’s primary defensive shielding is compromised and the unit is reduced to a crippled combat state. AS is reduced by half.

**Destroyed**: In a crippled combat state, hits equal to DS reduces a unit's state to destroyed. The unit is dead and unrecoverable.

If a squadron is crippled, all the ships under its command are crippled. If a squadron is destroyed, all the ships are likewise destroyed.

### 5\.1.3 Cloaking

Cloaking offers an advantage in the initial round of space combat, both on the defensive and offensive.

When defending a solar system, cloaked units are considered to be in ambush against invaders.

When attacking a solar system, cloaked units are considered to be a surprise to the defenders.

Roll for stealth in accordance with Section 2.4.3. Scouts present in opposing forces have an opportunity to counter.

**Important**: *Every fleet joining a Task Force must pass a stealth roll for the entire Task Force to be considered cloaked*.

## 5\.2 Task Force Assignment

All applicable fleets and Starbases relevant to the combat scenario will merge into a single Task Force.

Rules of Engagement (ROE):

- Task Forces adopt the highest ROE of any joining fleet.
- Starbases do not retreat; the Task Force's ROE is set to 10.

Cloaking:

- Task Forces including Starbases cannot cloak.
- All fleets must pass a stealth roll for the Task Force to be cloaked (Section 5.1.3).

Fleet Integration:

- Fleets disband, with their squadrons fighting individually under the Task Force.
- Fighter Squadrons deploy as independent squadrons.

Cloaked fleets with movement orders can continue if they pass stealth checks; otherwise, they join combat.

Spacelift Command ships are screened behind the Task Force during combat operations and do not engage in combat.

## 5\.3 Space Combat

All fleets within a solar system are mandated to engage enemy forces during their turn, with the following exceptions:

- Fleets under Fleet Order 04: Guard a Starbase 
- Fleets under Fleet Order 05: Guard/Blockade a Planet

Specific Engagement Rules:

- Blockade Engagement:
  - Fleets assigned to Blockade an enemy planet (Fleet Order 05) will engage only with enemy fleets ordered to Guard that same planet.
- Guard Engagement:
  - Fleets assigned to Guard a planet without a Starbase (Fleet Order 05) will engage only enemy fleets with orders ranging from 05 to 08, focusing on defensive or blockading actions.

Task Forces form according to Section 5.2.

Starbases and fleets assigned to Guard Starbases (Order 04) or Guard Planets (Order 05) are held in reserve. These forces are exclusively designated to counter blockades or direct assaults on planets.

Squadrons are not allowed to change assignments or restructure during combat engagements or retreats.

### 5.3.1 Rounds

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

| Modifier | Value | Notes                               |
| -------- |:-----:| ----------------------------------- |
| Scouts   | +1    | Maximum benefit for all Scouts      |
| Surprise | +3    | First round only; See Section 5.1.4 |
| Ambush   | +4    | First round only; See Section 5.1.4 |

**The CER multiplied by AS equals the number of total enemy hits.**

The player who rolled the die will determine where hits are applied.

The following **restrictions** apply:

1. If the number of hits equal the opposing squadron's DS, the unit is reduced.
2. Squadrons are not destroyed until all other squadrons in the Task Force are crippled.
3. Excess hits may be lost if restrictions apply.

Crippled squadrons multiply their AS by 0.5, rounded up the nearest whole number.

Destroyed squadrons are no longer a factor and the Task Force loses their associated die roll modifiers (e.g. Scouts).

In computer moderated play, the algorithm will reduce opposing squadrons with the greatest AS, within restrictions.

**Critical Hits**:

Critical hits are a special case. Restriction \#2 in the list above is nullified.

Additionally, if a player takes a critical hit and is unable to reduce a unit according to restriction \#1 above, then the squadron with the lowest DS is reduced.

### 5\.3.2 End of Round

After all hits are applied and squadrons are appropriately reduced (crippled or destroyed), recalculate the total AS of all surviving Task Forces.

Check each Task Force's ROE on the table in Section 5.1.1 by comparing AS strengths and determine if a retreat is warranted. If so, proceed to Section 5.3.3.

If more than one Task Force remains in the fight, the next round commences via the same procedure as described above.

Otherwise proceed to Section 5.3.4.

### 5\.3.3 Retreat

A Task Force may retreat from combat after the first round, in accordance with their ROE, and between rounds thereafter. 

Squadrons in a retreating Task Force will fall back to their original fleet formations and flee to the closest non-hostile star system.

Fighter squadrons never retreat from combat. If they remain in the fight, fighter squadrons will screen their retreating Task Force and combat resumes until they are completely destroyed. 

Spacelift Command ships are destroyed if their escort fleets were destroyed.

### 5\.3.4 End of Space Combat

After the last round of combat the surviving Task Forces are disbanded and surviving squadrons rejoin their original fleets.

## 5\.4 Starbase Combat

Starbases act as the primary defense if a hostile fleet aims to blockade, bombard, invade, or blitz a colony. They form a combined Task Force as per Section 5.2.

Fleets with orders to guard the Starbase (Fleet Orders 04) or to guard the planet (Fleet Orders 05) also join the Task Force.

Combat will proceed in a similar fashion to Section 5.3, with the following restrictions:

1. If a player rolls a critical hit against a starbase on the first try, re-roll a second time.
2. Starbases receive an extra +2 die roll modifier.

Starbases are fortified with superior AI and sensors, making them formidable, with high defensive capabilities.

## 5\.5 TODO: Planetary Bombardment

## 5\.6 TODO: Planetary Invasion & Blitz

| **Modified 1D10 Die Roll** | **Ground Combat CER**           |
| -------------------------- | ------------------------------- |
| Less than zero, 0, 1, 2    | One Half (0.5) (round up)       |
| 3, 4, 5, 6                 | One (1)                         |
| 7, 8                       | One and a half (1.5) (round up) |
| 9 or more                  | Two (2)                         |

## 5\.7 Custom Combat Modifications

If customizing your own ships or scenarios, the following list provides a jumping off point for custom modification. EC4X is flexible enough to enable the tailoring of the combat mechanics to your own ideas and requirements. Please report back to the project anything that works well for you and increases enjoyment of the game. 

- Additional modifiers to the CER roll, e.g. battle stations readiness, random chance events, etc.
- Apply the Starbase critical hit rule to special assets that are resistant to crippling.
- Add a modifier to protect a homeworld's solar system
- Add mines or moon bases
- Add defensive missile batteries
- Insert your imagination here.....

EC4X Space combat is adapted from Empire of the Sun (EOS). 

# 8\.0 TODO: Diplomacy & Subversion

# 9\.0 Data Tables

All tables and attributes are place holders.

## 9\.1 Space Force (Weapons Level 0)

CST = Minimum CST Level
HS = Hull Size
PC = Production Cost
MC = Maintenance Cost
AS = Attack Strength
DS = Defensive Strength
CC= Command Cost
CR = Command Rating
CL = Carry Limit

| Class | Name              | CST | HS  | PC  | MC    | AS  | DS  | CC  | CR  | CL  |
|:-----:| ----------------- |:---:|:---:|:---:|:-----:|:---:|:---:|:---:|:---:|:---:|
| CT    | Corvette          | 1   | 1   | 2   | 0\.1  | 1   | 2   | 1   | 2   | NA  |
| FG    | Frigate           | 1   | 1   | 3   | 0\.2  | 2   | 3   | 2   | 3   | NA  |
| DD    | Destroyer         | 1   | 1   | 4   | 0\.3  | 3   | 4   | 2   | 4   | NA  |
| CL    | Light Cruiser     | 1   | 2   | 5   | 0\.4  | 4   | 5   | 3   | 6   | NA  |
| CA    | Heavy Cruiser     | 2   |     |     |       |     |     |     |     |     |
| BC    | Battle Cruiser    | 3   | 2   | 6   | 0\.5  | 4   | 6   | 3   | 8   | NA  |
| BB    | Battleship        | 4   | 3   | 8   | 1\.0  | 6   | 8   | 3   | 9   | NA  |
| DN    | Dreadnought       | 5   | 3   | 10  | 1\.25 | 9   | 9   | 4   | 10  | NA  |
| SD    | Super Dreadnought | 6   |     |     |       |     |     |     |     |     |
| PB    | Planet-Breaker    | 10  |     |     |       |     |     |     |     |     |
| CV    | Carrier           | 3   | 1   | 8   | 1\.0  | 2   | 6   | 3   | 8   | 3   |
| CX    | Super Carrier     | 5   | 2   | 10  | 1\.5  | 3   | 9   | 4   | 10  | 5   |
| FS    | Fighter Squadron  | 3   | 1   | 3   | 0\.2  | 3   | 2   | NA  | NA  | NA  |
| RR    | Raider            | 3   | 2   | 25  | 0\.5  | 4   | 6   | 3   | 4   | 0   |
| SC    | Scout             | 1   | 1   | 15  | 0\.1  | 0   | 1   | 1   | NA  | NA  |
| SB    | Starbase          | 3   | 3   | 50  | 2.5   | 45  | 50  | NA  | NA  | NA  |

## 9.3 Ground Units

| **Class** | **Name**         | CST | PC  | MC  | AS  | DS  |
| --------- | ---------------- |:---:| --- | --- |:---:|:---:|
| PS        | Planetary Shield | 5   | 35  | 2.0 | 0   | 50  |
| GB        | Ground Batteries | 1   | 4   | 0.1 | 6   | 2   |
| AA        | Armies           | 1   | 2   | 0.2 | 2   | 3   |
| MD        | Space Marines    | 1   | 3   | 0.2 | 3   | 2   |

## 9\.2 Spacelift Command

| **Class** | **Name**         | CST | PC  | MC  | CL  |
|:---------:| ---------------- |:---:|:---:|:---:|:---:|
| SP        | Spaceport        | 1   | 20  | 1.0 | 5   |
| SY        | Shipyard         | 1   | 30  | 2.0 | 10  |
| ET        | ETAC             | 1   | 15  | 0.3 | 1   |
| TT        | Troop Transports | 1   | 5   | 0.2 | 1   |

## 9\.3 Prestige

TODO: Provide a prestige table showing the various factors, both positive and negative.

- Completely destroy a Task Force (+)
- Force a task force to retreat (+)
- Invade or blitz a planet (++)
- Lose a planet (--)
- Get surprised by a rogue fleet (-)
- Get ambushed by a rogue fleet (-)
- Lose a Starbase (-)
- Destroy a Starbase (+)
- Establish a new colony (+)
- Max out the population of a colony (+)
- Increase a planet's class via terraforming (+)
- Excessive tax rate (-)
- Invest IU above 50% of a colony's PU (+)
- Achieve a new tech level (+)
- Sabotage a rival Shipyard (+)
- Spy on an rival's colony (+)
- And so on.... get creative

# 10\.0 Play By Excel
