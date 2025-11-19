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
| FS    | Fighter Squadron  | 3   | 20  | 5%  | 4   | 3   | NA  | NA  | NA  |
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
| **Setbacks**      | High tax rate (51-65%)                         | -1 every 3 turns    |
|                   | Very high tax rate (> 65%)                     | -2 every 5 turns    |
|                   | Failure to meet maintenance costs (per turn)   | -5 (cumulative)     |

### Notes on Penalties:

1. **Tax Rate Penalties**:

   - High tax rate (51-65%): -1 prestige every 3 consecutive turns at this rate
   - Very high tax rate (>65%): -2 prestige every 5 consecutive turns at this rate
   - Penalties apply periodically, not cumulatively
   - See [Section 3.1.3](economy.md#313-tax-rate) for full tax mechanics

2. **Missed Maintenance Costs Penalty**:
   
   - Penalty escalates for consecutive turns of missed maintenance payments:
     - Turn 1: -5 points
     - Turn 2: -7 points (cumulative total: -12 points)
     - Turn 3: -9 points (cumulative total: -21 points)
     - Continues increasing by 2 additional points each turn.
