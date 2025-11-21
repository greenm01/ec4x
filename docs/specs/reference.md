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

<!-- PRESTIGE_TABLE_START -->
| Prestige Source | Enum Name | Value |
|-----------------|-----------|-------|
| Tech Advancement | `TechAdvancement` | +2 |
| Colony Establishment | `ColonyEstablishment` | +5 |
| System Capture | `SystemCapture` | +10 |
| Diplomatic Pact Formation | `DiplomaticPact` | +5 |
| Pact Violation (penalty) | `PactViolation` | -10 |
| Repeat Violation (penalty) | `RepeatViolation` | -10 |
| Dishonor Status Expires | `DishonoredExpires` | -1 |
| Tech Theft Success | `TechTheftSuccess` | +2 |
| Tech Theft Detected (penalty) | `TechTheftDetected` | -2 |
| Assassination Success | `AssassinationSuccess` | +5 |
| Assassination Detected (penalty) | `AssassinationDetected` | -2 |
| Espionage Attempt Failed (penalty) | `EspionageFailure` | -2 |
| Major Ship Destroyed (per ship) | `ShipDestroyed` | +1 |
| Starbase Destroyed | `StarbaseDestroyed` | +5 |
| Fleet Victory (per battle) | `FleetVictory` | +3 |
| Planet Conquered | `PlanetConquered` | +10 |
| House Eliminated | `HouseEliminated` | +3 |
| Victory Achieved | `VictoryAchieved` | +5 |
<!-- PRESTIGE_TABLE_END -->

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

## 9.5 Game Limits Summary (Anti-Spam / Anti-Cheese Caps)

| Limit Description                              | Rule Details                                                                                 | Source Section |
|------------------------------------------------|----------------------------------------------------------------------------------------------|----------------|
| Capital-Ship Squadrons + Carriers              | Maximum = Total House PU ÷ 100 (round down, minimum 8). Every capital-ship squadron (including Raiders as flagships) and every carrier (solo or flagship) costs 1 slot. Scouts, fighters, starbases, Spacelift exempt. | [3.12](economy.md#312-house-combat-squadron-limit)           |
| Planet-Breakers                                | Maximum 1 per currently owned colony (homeworld counts). Loss of colony instantly scraps its PB (no salvage). | [2.4.8](assets.md#248-planet-breaker)          |
| Fighter Squadrons (per colony)                 | Max FS = floor(Colony PU ÷ 100) × Fighter Doctrine multiplier (FD I = 1.0×, FD II = 1.5×, FD III = 2.0×). Also requires 1 operational Starbase per 5 FS (ceil). 2-turn grace on violation → auto-disband excess. | [2.4.1](assets.md#241-fighter-squadrons-carriers)          |
| Carrier Hangar Capacity                        | CV = 3–5 FS, CX = 5–8 FS depending on Advanced Carrier Operations (ACO) tech level (house-wide instant upgrade). Hard physical limit. | [2.4.1](assets.md#241-fighter-squadrons-carriers)          |
| Scout CER Bonus                                | Maximum +1 total to CER for the entire Task Force, regardless of number of scouts present.   | [7.3.3](operations.md#733-combat-effectiveness-rating-cer)          |
| Squadron Destruction Protection (anti-fodder)  | A squadron may not be destroyed in the same combat round it is crippled. Excess hits that would destroy a freshly crippled squadron are lost (critical hits bypass). | [7.3.3](operations.md#733-combat-effectiveness-rating-cer)          |
| Blockade Prestige Penalty                     | –2 prestige only if colony begins the Income Phase still under blockade (drive-by blockades not effective). | [6.2.6](operations.md#626-guardblockade-a-planet-05)          |
| Tax Rate Prestige Penalty                     | Rolling 6-turn average tax rate >50 % triggers escalating prestige bleed (51–60 % = –1, up to 91–100 % = –11 per turn). Low-tax incentives also apply. | [3.2](economy.md#32-tax-rate)            |
