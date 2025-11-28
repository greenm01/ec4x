# 10.0 Data Tables

## 10.1 Space Force (WEP1)

<!-- SPACE_FORCE_TABLE_START -->
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
| DD    | Destroyer         | 1   | 40  | 5%  | 5   | 6   | 2   | 4   | NA  |
| CL    | Light Cruiser     | 1   | 60  | 3%  | 8   | 9   | 3   | 6   | NA  |
| CA    | Heavy Cruiser     | 2   | 80  | 5%  | 12  | 13  | 3   | 7   | NA  |
| BC    | Battle Cruiser    | 3   | 100 | 4%  | 16  | 18  | 3   | 8   | NA  |
| BB    | Battleship        | 4   | 150 | 4%  | 20  | 25  | 3   | 10  | NA  |
| DN    | Dreadnought       | 5   | 200 | 5%  | 28  | 30  | 4   | 12  | NA  |
| SD    | Super Dreadnought | 6   | 250 | 5%  | 35  | 40  | 5   | 14  | NA  |
| PB    | Planet-Breaker    | 10  | 400 | 5%  | 50  | 20  | 6   | 6   | NA  |
| CV    | Carrier           | 3   | 120 | 3%  | 5   | 18  | 3   | 8   | 3   |
| CX    | Super Carrier     | 5   | 200 | 5%  | 8   | 25  | 4   | 10  | 5   |
| FS    | Fighter Squadron  | 3   | 20  | 5%  | 4   | 3   | NA  | NA  | NA  |
| RR    | Raider            | 3   | 150 | 4%  | 12  | 10  | 3   | 4   | NA  |
| SC    | Scout             | 1   | 50  | 2%  | 1   | 2   | 1   | NA  | NA  |
| SB    | Starbase          | 3   | 300 | 5%  | 45  | 50  | NA  | NA  | NA  |

*Source: config/ships.toml*
<!-- SPACE_FORCE_TABLE_END -->

## 10.1.1 Ship Construction Times

**All ship construction completes instantly (1 turn)** regardless of hull class or CST tech level.

This reflects the game's time narrative where turns represent variable time periods (1-15 years depending on map size). Multi-turn construction would cause severe balance issues across different map sizes.

**CST Tech Effects:**
- CST unlocks ship classes (see CST column in Space Force table above)
- CST increases industrial production capacity by 10% per level (affects GCO)
- CST does NOT affect construction time (all ships build in 1 turn)

<!-- CONSTRUCTION_TIMES_TABLE_START -->
| Hull Class | Ships | Construction Time |
|------------|-------|-------------------|
| All Classes | All Ships | 1 turn (instant) |

*Source: config/ships.toml [construction] section*
<!-- CONSTRUCTION_TIMES_TABLE_END -->

## 10.2 Ground Units (WEP1)

<!-- GROUND_UNITS_TABLE_START -->
| **Class** | **Name**         | CST | PC  | MC  | AS  | DS  |
| --------- | ---------------- |:---:| --- | --- |:---:|:---:|
| PS        | Planetary Shield | 5   | 100 | 5%  | 0   | 100 |
| GB        | Ground Batteries | 1   | 20  | 3%  | 10  | 8   |
| AA        | Armies           | 1   | 15  | 2%  | 3   | 5   |
| MD        | Space Marines    | 1   | 25  | 2%  | 6   | 6   |

*Source: config/ground_units.toml*
<!-- GROUND_UNITS_TABLE_END -->

## 10.3 Spacelift Command (WEP1)

<!-- SPACELIFT_TABLE_START -->
| **Class** | **Name**         | CST | PC  | MC  | CL  | DS  |
|:---------:| ---------------- |:---:|:---:|:---:|:---:|:---:|
| SP        | Spaceport        | 1   | 100 | 5%  | 5   | 50  |
| SY        | Shipyard         | 1   | 150 | 3%  | 10  | 70  |
| ET        | ETAC             | 1   | 25  | 3%  | 1   | 10  |
| TT        | Troop Transports | 1   | 30  | 3%  | 1   | 15  |

*Source: config/facilities.toml and config/ships.toml*
<!-- SPACELIFT_TABLE_END -->

## 10.4 Prestige

**IMPORTANT: Dynamic Prestige Scaling**

All prestige values in this section are **BASE** values. The actual prestige awarded in-game is calculated as:

```
actual_prestige = base_value × dynamic_multiplier
```

The dynamic multiplier is calculated at game start based on map size and player count:

```
systems_per_player = total_systems / num_players
target_turns = baseline_turns + (systems_per_player - baseline_ratio) × turn_scaling_factor
dynamic_multiplier = base_multiplier × (baseline_turns / target_turns)
```

Small maps (8-10 systems/player) use the baseline multiplier. Larger maps scale DOWN to extend game length:
- **Small maps** (8-10 systems/player): 5.0x multiplier (baseline) → ~30 turn games
- **Medium maps** (15-20 systems/player): 3.0-4.0x multiplier (scaled down) → ~40-50 turn games
- **Large maps** (30+ systems/player): 2.0-2.5x multiplier (scaled down) → ~60-80 turn games

*Configuration: config/prestige.toml [dynamic_scaling] section*

### Base Prestige Values

<!-- PRESTIGE_TABLE_START -->
| Prestige Source | Enum Name | Value |
|-----------------|-----------|-------|
| Tech Advancement | `TechAdvancement` | +20 |
| Colony Establishment | `ColonyEstablishment` | +50 |
| System Capture | `SystemCapture` | +100 |
| Diplomatic Pact Formation | `DiplomaticPact` | +50 |
| Pact Violation (penalty) | `PactViolation` | -100 |
| Repeat Violation (penalty) | `RepeatViolation` | -100 |
| Attack Dishonored House | `DishonoredBonus` | +10 |
| Tech Theft Success | `TechTheftSuccess` | +20 |
| Tech Theft Detected (penalty) | `TechTheftDetected` | +20 |
| Assassination Success | `AssassinationSuccess` | +50 |
| Assassination Detected (penalty) | `AssassinationDetected` | +50 |
| Espionage Attempt Failed (penalty) | `EspionageFailure` | +10 |
| Major Ship Destroyed (per ship) | `ShipDestroyed` | +10 |
| Starbase Destroyed | `StarbaseDestroyed` | +50 |
| Fleet Victory (per battle) | `FleetVictory` | +30 |
| Planet Conquered | `PlanetConquered` | +100 |
| House Eliminated | `HouseEliminated` | +30 |
| Victory Achieved | `VictoryAchieved` | +50 |

*Source: config/prestige.toml [economic], [military], and [espionage] sections*
<!-- PRESTIGE_TABLE_END -->

### Prestige Penalty Mechanics

Penalty mechanics describe how prestige is deducted based on player actions and game state. Unlike prestige sources (discrete events in Table 9.4), these are recurring penalties triggered by conditions.

<!-- PENALTY_MECHANICS_START -->
| Penalty Type | Condition | Prestige Impact | Frequency | Config Keys |
|--------------|-----------|-----------------|-----------|-------------|
| High Tax Rate | Rolling 6-turn avg 51-65% | -2 prestige | Every 3 consecutive turns | `high_tax_*` |
| Very High Tax Rate | Rolling 6-turn avg >66% | -2 prestige | Every 5 consecutive turns | `very_high_tax_*` |
| Maintenance Shortfall | Missed maintenance payment | -8 turn 1, escalates by -3/turn | Per turn missed | `maintenance_shortfall_*` |
| Blockade | Colony under blockade at Income Phase | -3 prestige | Per turn per colony | `blockade_penalty` |
| Espionage Over-Investment | EBP spending >5% of budget | -2 prestige per 1% over threshold | Per turn | `over_invest_espionage` |
| Counter-Intel Over-Investment | CIP spending >5% of budget | -2 prestige per 1% over threshold | Per turn | `over_invest_counter_intel` |

*Source: config/prestige.toml [penalties] section*
<!-- PENALTY_MECHANICS_END -->

**Additional Notes:**
- Tax penalties apply periodically based on rolling 6-turn average, not instantaneously
- Maintenance shortfall escalates: Turn 1 (-5), Turn 2 (-7), Turn 3 (-9), continues +2/turn
- See [Section 3.1.3](economy.md#313-tax-rate) for full tax mechanics
- See [Section 3.2](economy.md#32-maintenance-costs) for maintenance mechanics

## 10.5 Game Limits Summary (Anti-Spam / Anti-Cheese Caps)

| Limit Description                              | Rule Details                                                                                 | Source Section |
|------------------------------------------------|----------------------------------------------------------------------------------------------|----------------|
| Capital-Ship Squadrons + Carriers              | Maximum = Total House PU ÷ 100 (round down, minimum 8). Every capital-ship squadron (including Raiders as flagships) and every carrier (solo or flagship) costs 1 slot. Scouts, fighters, starbases, Spacelift exempt. | [3.12](economy.md#312-house-combat-squadron-limit)           |
| Planet-Breakers                                | Maximum 1 per currently owned colony (homeworld counts). Loss of colony instantly scraps its PB (no salvage). | [2.4.8](assets.md#248-planet-breaker)          |
| Fighter Squadrons (per colony)                 | Max FS = floor(Colony PU ÷ 100) × Fighter Doctrine multiplier (FD I = 1.0×, FD II = 1.5×, FD III = 2.0×). Also requires 1 operational Starbase per 5 FS (ceil). 2-turn grace on violation → auto-disband excess. | [2.4.1](assets.md#241-fighter-squadrons-carriers)          |
| Carrier Hangar Capacity                        | CV = 3–5 FS, CX = 5–8 FS depending on Advanced Carrier Operations (ACO) tech level (house-wide instant upgrade). Hard physical limit. | [2.4.1](assets.md#241-fighter-squadrons-carriers)          |
| Scout CER Bonus                                | Maximum +1 total to CER for the entire Task Force, regardless of number of scouts present.   | [7.3.3](operations.md#733-combat-effectiveness-rating-cer)          |
| Squadron Destruction Protection (anti-fodder)  | A squadron may not be destroyed in the same combat round it is crippled. Excess hits that would destroy a freshly crippled squadron are lost (critical hits bypass). | [7.3.3](operations.md#733-combat-effectiveness-rating-cer)          |
| Blockade Prestige Penalty                     | See [Prestige Penalty Mechanics](#prestige-penalty-mechanics) for blockade penalty details. | [6.2.6](operations.md#626-guardblockade-a-planet-05)          |
| Tax Rate Prestige Penalty                     | See [Prestige Penalty Mechanics](#prestige-penalty-mechanics) for tax rate penalty details. | [3.2](economy.md#32-tax-rate)            |
