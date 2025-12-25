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

### Escort Ships (CR < 7)

Combat-capable ships that can join squadrons as escorts. Count toward total squadron limit.

| Class | Name          | CST | PC | MC  | AS | DS | CC | CR |
|:-----:| ------------- |:---:|:--:|:---:|:--:|:--:|:--:|:--:|
| CT    | Corvette      | 1   | 20 | 3%  | 2  | 3  | 1  | 2  |
| FG    | Frigate       | 1   | 30 | 3%  | 3  | 4  | 2  | 3  |
| DD    | Destroyer     | 1   | 40 | 4%  | 5  | 6  | 2  | 4  |
| CL    | Light Cruiser | 1   | 60 | 4%  | 8  | 9  | 3  | 6  |

### Capital Ships (CR >= 7)

Flagship-capable ships that lead squadrons. Subject to both capital squadron limits AND total squadron limits.

| Class | Name              | CST | PC  | MC  | AS | DS | CC | CR | CL |
|:-----:| ----------------- |:---:|:---:|:---:|:--:|:--:|:--:|:--:|:--:|
| CA    | Heavy Cruiser     | 2   | 80  | 5%  | 12 | 13 | 3  | 7  | —  |
| BC    | Battle Cruiser    | 3   | 100 | 5%  | 16 | 18 | 3  | 8  | —  |
| BB    | Battleship        | 4   | 150 | 5%  | 20 | 25 | 3  | 10 | —  |
| DN    | Dreadnought       | 5   | 200 | 5%  | 28 | 30 | 4  | 12 | —  |
| SD    | Super Dreadnought | 6   | 250 | 8%  | 35 | 40 | 5  | 14 | —  |
| CV    | Carrier           | 3   | 120 | 5%  | 5  | 18 | 3  | 8  | 3  |
| CX    | Super Carrier     | 6   | 225 | 7%  | 8  | 25 | 4  | 10 | 5  |
| RR    | Raider            | 5   | 200 | 5%  | 20 | 25 | 2  | 6  | —  |

### Auxiliary Ships

Non-combat support ships. Do not count toward squadron limits. Form Intel/Expansion/Auxiliary squadrons.

| Class | Name            | CST | PC | MC  | AS | DS | Notes                                      |
|:-----:| --------------- |:---:|:--:|:---:|:--:|:--:| ------------------------------------------ |
| SC    | Scout           | 1   | 25 | 1%  | -  | -  | Intel operations, never joins combat       |
| ET    | ETAC            | 1   | 50 | 5%  | —  | -  | Colonization (CL=1), starts with 3 PTU     |
| TT    | Troop Transport | 1   | 30 | 3%  | —  | -  | Planetary invasion (CL=1), carries marines |

### Fighter Squadrons

Embarked strike squadron craft with per-colony capacity limits. Cannot join fleets, based at colonies for system defense or loaded onto carriers for offensive operations.

| Class | Name    | CST | PC | MC  | AS | DS | CC |Notes                            |
|:-----:| ------- |:---:|:--:|:---:|:--:|:--:|:--:| -------------------------------- |
| FS    | Fighter | 1   | 25 | 3%  | 5  | 2  | 1  | Colony-based or carrier-embarked |

### Special Weapons

Unique strategic units with special capacity rules.

| Class | Name           | CST | PC  | MC  | AS | DS | CC | CR | Notes                        |
|:-----:| -------------- |:---:|:---:|:---:|:--:|:--:|:--:|:--:| ---------------------------- |
| PB    | Planet Breaker | 10  | 400 | 10% | 50 | 20 | 6  | 6  | Max 1 per owned colony       |

*Source: config/ships.toml*

**Note:** Starbases are **facilities** (not ships) and are documented in [Section 2.4.4](02-assets.md#244-starbases). They are built via the Colony pipeline and stored at colonies, never assigned to fleets or squadrons.

**Squadron Type Mapping:**
- **Combat Squadrons**: Escort + Capital ships (participate in combat)
- **Intel Squadrons**: Scout only (intelligence operations, never mix with combat)
- **Auxiliary Squadrons**: Troop Transports (invasion support, screened in combat)
- **Expansion Squadrons**: ETACs (colonization, screened in combat)
- **Fighter Squadrons**: Fighters (planetary defense, carrier-based)

<!-- SPACE_FORCE_TABLE_END -->

## 10.1.1 Ship Construction Times

**All ship construction completes in 1 turn** regardless of hull class or CST tech level.

This reflects the game's time narrative where turns represent variable time periods (1-15 years depending on map size). Multi-turn construction would cause severe balance issues across different map sizes.

**CST Tech Effects:**

- CST unlocks ship classes (see CST column in Space Force table above)
- CST increases industrial production capacity by 10% per level (affects GCO)
- CST does NOT affect construction time (all ships build in 1 turn)

<!-- CONSTRUCTION_TIMES_TABLE_START -->

| Hull Class  | Ships     | Construction Time |
| ----------- | --------- | ----------------- |
| All Classes | All Ships | 1 turn            |

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

## 10.3 Orbital Facilities (WEP1)

Orbital facilities are infrastructure built at colonies that provide combat, economic, and detection capabilities. Unlike ships, they cannot move and are fixed to their construction location.

<!-- ORBITAL_FACILITIES_TABLE_START -->

| **Class** | **Name** | CST | PC  | MC  | AS  | DS  | Build Time |
| --------- | -------- |:---:|:---:|:---:|:---:|:---:|:----------:|
| SB        | Starbase | 3   | 300 | 5%  | 45  | 50  | 3 turns    |

*Source: config/facilities.toml*

**Notes:**

- Built via Colony pipeline; requires operational Spaceport
- Repairs use Spaceport (not Shipyard), cost 75 PP (25%), take 1 turn, no dock consumption
- AS/DS scale with WEP technology (+10% per level above WEP I)
- Economic bonuses: +5% growth/production per Starbase (max 3 per colony)
- Detection: +2 ELI bonus for Scout/Raider detection

<!-- ORBITAL_FACILITIES_TABLE_END -->

## 10.4 Construction & Repair Facilities (WEP1)

<!-- CONSTRUCTION_FACILITIES_TABLE_START -->

| **Class** | **Name**  | CST | PC  | MC  | Docks | DS  | Purpose                    |
|:---------:| --------- |:---:|:---:|:---:|:-----:|:---:| -------------------------- |
| SP        | Spaceport | 1   | 20  | 5%  | 5     | 50  | Construction only          |
| SY        | Shipyard  | 1   | 60  | 3%  | 10    | 70  | Construction only          |
| DD        | Drydock   | 1   | 150 | 5%  | 10    | 70  | Ship repair only           |

**Notes:**
- Spaceports: 5 construction docks, cannot repair ships, +100% PP penalty for ship construction
- Shipyards: 10 construction docks, cannot repair ships, standard PP costs
- Drydocks: 10 repair docks, cannot construct ships, 25% PP repair cost (1 turn)
- All dock counts scale with CST technology (+10% per level)
- Starbase repairs use Spaceports (not Drydocks) and don't consume dock capacity

*Source: config/facilities.toml*

<!-- CONSTRUCTION_FACILITIES_TABLE_END -->

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

### Zero-Sum Competition Mechanics

**Competitive Events (Zero-Sum):** When one house gains prestige, the opponent loses an equal amount. These represent direct competition where one side's victory is the other's defeat:

- **Combat**: Victor gains prestige, defeated loses equal amount
- **Squadron Destruction**: Victor gains per ship destroyed, defeated loses equal amount
- **Invasions/Blitz**: Attacker gains for planet seized, defender loses equal amount
- **Espionage**: Attacker gains for successful operation, victim loses equal amount

**Non-Competitive Events (Absolute Gains):** These represent achievements that don't directly harm opponents:

- **Colony Establishment**: Building a new colony (+5 base)
- **Tech Advancement**: Research breakthroughs (+2 base)
- **Low Tax Bonuses**: Good governance (+3/colony)

**Pure Penalties (No Transfer):** These represent dishonor or failure:

- **Pact Violations**: Breaking diplomatic agreements (-10 base)
- **Maintenance Shortfalls**: Failed upkeep payments

The zero-sum system ensures **losers actively decline** rather than merely slowing down. Military dominance creates a competitive spiral: winners gain resources and prestige, losers lose both.

### Base Prestige Values

<!-- PRESTIGE_TABLE_START -->

| Prestige Source                    | Enum Name              | Value | Type         |
| ---------------------------------- | ---------------------- | ----- | ------------ |
| Tech Advancement                   | `TechAdvancement`      | +2    | Absolute     |
| Colony Establishment               | `ColonyEstablishment`  | +5    | Absolute     |
| System Capture                     | `SystemCapture`        | +10   | Zero-Sum     |
| Tech Theft Success                 | `TechTheftSuccess`     | +2    | Zero-Sum     |
| Assassination Success              | `AssassinationSuccess` | +5    | Zero-Sum     |
| Espionage Attempt Failed (penalty) | `EspionageFailure`     | -2    | Pure Penalty |
| Major Ship Destroyed (per ship)    | `ShipDestroyed`        | +1    | Zero-Sum     |
| Starbase Destroyed                 | `StarbaseDestroyed`    | +5    | Zero-Sum     |
| Fleet Victory (per battle)         | `FleetVictory`         | +3    | Zero-Sum     |
| Planet Conquered (Invasion)        | `PlanetConquered`      | +10   | Zero-Sum     |
| Planet Lost (Invasion)             | `PlanetLost`           | -10   | Zero-Sum     |
| Planet Lost (Undefended)           | `PlanetLost`           | -15   | Zero-Sum*    |
| House Eliminated                   | `HouseEliminated`      | +3    | Zero-Sum     |
| Victory Achieved                   | `VictoryAchieved`      | +5    | Absolute     |

*Source: config/prestige.toml [economic], [military], and [espionage] sections*

**Notes:**

- *Zero-Sum*: The asterisk indicates the undefended colony penalty intentionally breaks zero-sum. The attacker gains the base amount (+10), but the defender loses 1.5× the base amount (-15). This is punishment for poor defensive strategy.

<!-- PRESTIGE_TABLE_END -->

### Prestige Penalty Mechanics

Penalty mechanics describe how prestige is deducted based on player actions and game state. Unlike prestige sources (discrete events in Table 9.4), these are recurring penalties triggered by conditions.

<!-- PENALTY_MECHANICS_START -->

| Penalty Type                  | Condition                             | Prestige Impact                   | Frequency                 | Config Keys                 |
| ----------------------------- | ------------------------------------- | --------------------------------- | ------------------------- | --------------------------- |
| High Tax Rate                 | Rolling 6-turn avg 51-65%             | -2 prestige                       | Every 3 consecutive turns | `high_tax_*`                |
| Very High Tax Rate            | Rolling 6-turn avg >66%               | -2 prestige                       | Every 5 consecutive turns | `very_high_tax_*`           |
| Maintenance Shortfall         | Missed maintenance payment            | -8 turn 1, escalates by -3/turn   | Per turn missed           | `maintenance_shortfall_*`   |
| Blockade                      | Colony under blockade at Income Phase | -3 prestige                       | Per turn per colony       | `blockade_penalty`          |
| Espionage Over-Investment     | EBP spending >5% of budget            | -2 prestige per 1% over threshold | Per turn                  | `over_invest_espionage`     |
| Counter-Intel Over-Investment | CIP spending >5% of budget            | -2 prestige per 1% over threshold | Per turn                  | `over_invest_counter_intel` |

*Source: config/prestige.toml [penalties] section*

<!-- PENALTY_MECHANICS_END -->

**Additional Notes:**

- Tax penalties apply periodically based on rolling 6-turn average, not instantaneously
- Maintenance shortfall escalates: Turn 1 (-5), Turn 2 (-7), Turn 3 (-9), continues +2/turn
- See [Section 3.2](03-economy.md#32-tax-rate) for full tax mechanics
- See [Section 3.9.1](03-economy.md#391-maintenance-tax-shortfall-consequences) for maintenance mechanics

### Undefended Colony Penalty

Colonies without ground defense incur additional prestige penalties when lost to invasion or blitz operations:

- **Check**: Colony has 0 armies AND 0 marines AND 0 ground batteries
- **Penalty**: Base prestige loss × 1.5 (configured in prestige.toml as `undefended_colony_penalty_multiplier`)
- **Example**: Losing undefended colony = -10 (base) × 1.5 = -15 prestige (before dynamic multiplier)
- **Rationale**: Represents the dishonor of leaving citizens defenseless

**Important:**

- Planetary shields do NOT count as defense for this check. Shields are passive and only slow invasions.
- At least one army, marine, or ground battery is required to avoid the penalty.
- The additional penalty breaks zero-sum: attacker gains base amount, defender loses 1.5× base amount.
- This is intentional punishment for poor defensive strategy.

**Ground Unit Costs (Phase F Balance):**
Ground units received 33% cost reductions to make defensive investments more accessible:

- **Armies**: 10 PP (was 15)
- **Marines**: 17 PP (was 25)
- **Ground Batteries**: 13 PP (was 20)
- **Planetary Shields**: 50 PP (was 100, then 67)

*Configuration: config/prestige.toml [military].undefended_colony_penalty_multiplier*
*Configuration: config/ground_units.toml [*].build_cost*

## 10.5 Game Limits Summary (Anti-Spam / Anti-Cheese Caps)

| Limit Description                             | Rule Details                                                                                                                                                                                                                   | Source Section                                             |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------- |
| Total Squadrons (per house)                   | Maximum = Total House (IU ÷ 50) × mapMultiplier (round down, minimum 20). Includes ALL military squadrons (escorts + capitals). Excludes fighters and auxiliary ships. 2-turn grace period, then auto-disband weakest escorts. | [3.12](03-economy.md#312-house-combat-squadron-limit)         |
| Capital Squadrons (per house)                 | Maximum = Total House (IU ÷ 100) × 2 × mapMultiplier (round down, minimum 8). Squadrons with capital ships. Subset of total squadron limit. No grace period, immediate enforcement with 50% salvage.                           | [3.12](03-economy.md#312-house-combat-squadron-limit)         |
| Planet-Breakers (per colony)                  | Maximum 1 per currently owned colony (homeworld counts). Loss of colony instantly scraps its PB (no salvage).                                                                                                                  | [2.4.8](02-assets.md#248-planet-breaker)                      |
| Fighter Squadrons (per colony)                | Max FS = floor(Colony IU ÷ 100) × Fighter Doctrine multiplier (FD I = 1.0×, FD II = 1.5×, FD III = 2.0×). Based on industrial capacity, not population. 2-turn grace on capacity violation → auto-disband excess.              | [2.4.1](02-assets.md#241-fighter-squadrons-carriers)          |
| Carrier Hangar Capacity                       | CV = 3–5 FS, CX = 5–8 FS depending on Advanced Carrier Operations (ACO) tech level (house-wide instant upgrade). Hard physical limit.                                                                                          | [2.4.1](02-assets.md#241-fighter-squadrons-carriers)          |
| Squadron Destruction Protection (anti-fodder) | A squadron may not be destroyed in the same combat round it is crippled. Excess hits that would destroy a freshly crippled squadron are lost (critical hits bypass).                                                           | [7.3.3](07-combat.md#733-combat-effectiveness-rating-cer) |
| Blockade Prestige Penalty                     | See [Prestige Penalty Mechanics](#prestige-penalty-mechanics) for blockade penalty details.                                                                                                                                    | [6.2.6](06-operations.md#626-guardblockade-a-planet-05)       |
| Tax Rate Prestige Penalty                     | See [Prestige Penalty Mechanics](#prestige-penalty-mechanics) for tax rate penalty details.                                                                                                                                    | [3.2](03-economy.md#32-tax-rate)                              |

**Map Size Multipliers** (affects both total and capital squadron limits):

- **Small maps** (< 8 systems/player): 0.8× (encourages concentration)
- **Medium maps** (8-12 systems/player): 1.0× (baseline)
- **Large maps** (13-16 systems/player): 1.3× (more territory = more ships needed)
- **Huge maps** (> 16 systems/player): 1.6× (vast empires need larger fleets)

**Squadron Limit Relationship:**
Capital squadron limit is a SUBSET of total squadron limit (not additive). Example with 1000 IU on medium map:

- Total limit: floor(1000 ÷ 50) × 1.0 = 20 squadrons (ALL military ships)
- Capital limit: floor(1000 ÷ 100) × 2 × 1.0 = 20 capital squadrons
- Valid fleet: 20 capitals + 0 escorts = 20 total ✓
- Valid fleet: 15 capitals + 5 escorts = 20 total ✓
- Invalid: 25 capitals (violates capital limit) ✗
- Invalid: 10 capitals + 15 escorts = 25 total (violates total limit) ✗
