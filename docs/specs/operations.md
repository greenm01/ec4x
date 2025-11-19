# 6.0 Movement

## 6.1 Jump Lanes

Fleets move between solar systems via jump lanes:
- If a player owns all systems along the travel path, fleets can jump two major lanes in one turn.
- Minor and restricted jump lanes enable a single jump per turn, regardless of the destination.
- If jumping into an unexplored or rival system, the maximum number of jumps is one.
- Fleets containing crippled ships or Spacelift Command ships can not jump across restricted lanes.

## 6.2 Fleet Orders

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

### 6.2.1 Hold Position (00):

Fleets are ordered to hold position and standby for new orders.

### 6.2.2 Move Fleet (01):

Move to a new solar system and hold position (00).

### 6.2.3 Seek home (02):

Order a fleet to seek the closest friendly solar system and hold position (00). Should that planet be taken over by an enemy, the fleet will move to the next closest planet you own.

### 6.2.4 Patrol a System (03):

Actively patrol a solar system, engaging hostile forces that enter the space.

**Engagement Rules:**

Patrol orders trigger combat engagement when:
- Entering systems controlled by houses with Enemy diplomatic status per [Section 8.1.3](diplomacy.md#813-enemy)
- Encountering Enemy-status forces in any territory (controlled, neutral, or contested)

Patrol does NOT trigger engagement with Neutral or Non-Aggression houses unless they execute threatening fleet orders (05-08, 12) in your controlled territory per [Section 7.3.2.1](operations.md#7321-diplomatic-filtering).

Patrol operations automatically gather intelligence on all foreign forces encountered per [Section 1.5.1](gameplay.md#151-fleet-encounters-and-intelligence).

### 6.2.5 Guard a Starbase (04):

Order a fleet to protect a Starbase, and join in a combined Task Force, when confronting hostile ships with orders 05 to 08.

### 6.2.6 Guard/Blockade a Planet (05):

Order a fleet to block hostile forces from approaching a planet.

**Guard**: Fleets on guard duty are held in rear guard to protect a colony and do not join Space Combat unless confronted by hostile ships with orders 05 to 08. Guarding fleets may contain Raiders and do not auto-join a Starbase's Task Force, which would compromise their cloaking ability. Not all planets will have a functional Starbase.

**Blockade**: Fleets are ordered to blockade an enemy planet and do not engage in Space Combat unless confronted by enemy ships under order 05.

Colonies under blockade reduce their GCO by 60%. Blockade effects apply immediately during the Income Phase per [Section 1.3.2](gameplay.md#132-income-phase). Blockades established during the Conflict Phase reduce GCO for that same turn's Income Phase calculation - there is no delay. Lifting a blockade immediately restores full GCO for the following turn's Income Phase.

**Prestige Penalty:** House Prestige is reduced by 2 points for each turn a colony begins under blockade. The prestige penalty applies even if the blockade is lifted before the Income Phase - establishing a blockade triggers the penalty for that turn regardless of duration.

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

**Strategic Note:**

Fleet Order 12 executed in systems containing another house's colony is considered a direct threat and triggers defensive engagement per [Section 7.3.2.1](#7321-diplomatic-filtering). During the expansion phase, territorial competition makes destruction of rival ETACs a strategic priority. Houses without Non-Aggression Pacts will engage colonization attempts in their controlled systems regardless of whether the colonization targets an empty planet or occurs by navigational error.

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

Squadron units and installations are either undamaged, crippled, or destroyed.

**Attack Strength (AS)** represents a unit's offensive firepower and is a mutable type.

**Defense Strength (DS)** represents a unit's defensive shielding and is an immutable type.

**Reduced**: This term is used to describe a transition of state, e.g. undamaged to crippled, crippled to destroyed.

**Undamaged**: A unit's life support systems, hull integrity, and weapons systems are fully operational.

**Crippled**: When an undamaged unit's DS is equaled in battle by hits, that unit's primary defensive shielding is compromised and the unit is reduced to a crippled combat state. AS is reduced by half (rounded up).

**Destroyed**: In a crippled combat state, hits equal to DS reduces a unit's state to destroyed. The unit is dead and unrecoverable.

**Fighter Exception:**

Fighter squadrons skip the crippled combat state due to their lightweight construction. Fighters transition directly from undamaged to destroyed when they take damage equal to or exceeding their DS. Fighters maintain full AS until destroyed. See [Section 2.4.1](assets.md#241-fighter-squadrons-carriers) for detailed fighter combat mechanics.

**Unit State Propagation:**
- If a squadron is crippled, all the ships under its command are crippled
- If a squadron is destroyed, all the ships are likewise destroyed
- Starbases follow the same state transitions as squadrons (undamaged → crippled → destroyed)
- Fighter squadrons follow binary state transition (undamaged → destroyed)

### 7.1.3 Cloaking

Undetected cloaked units strike first in combat initiative per [Section 7.3.1.1](#7311-phase-1-undetected-raiders-ambush-phase).

Scouts and Starbases present in opposing forces have the opportunity to counter for cloaking. Roll for detection in accordance with [Section 2.4.3](assets.md#243-raiders).

If cloaked fleets on all sides pass undetected from one another, the player defending their solar system wins initiative. If opposing forces are meeting in neutral territory and all pass undetected, they carry on with movement orders and combat is cancelled.

### 7.1.4 Morale

House prestige affects crew morale and combat effectiveness. At the start of each turn, the game rolls 1D20 to determine morale status for that turn.

**Morale Check Table:**

| Prestige Level    | Morale Threshold | Effect on Success                      |
|:------------------|:----------------:|:---------------------------------------|
| ≤ 0 (Crisis)      | Never succeeds   | -1 to all CER rolls this turn          |
| 1-20 (Low)        | > 18             | No effect                              |
| 21-40 (Average)   | > 15             | +1 to CER for one random squadron      |
| 41-60 (Good)      | > 12             | +1 to all CER rolls this turn          |
| 61-80 (High)      | > 9              | +1 CER + one critical auto-succeeds    |
| 81+ (Elite)       | > 6              | +2 to all CER rolls this turn          |

**Morale Effects:**

- CER bonuses/penalties apply to all CER die rolls before consulting the CER table.
- Critical auto-success (61-80 prestige): The first squadron to execute a valid attack during the turn's Conflict Phase per [Section 1.3.1](gameplay.md#131-conflict-phase) automatically achieves critical hit effects as if a natural 9 was rolled on the CER table, bypassing destruction protection and applying force reduction rules as defined in [Section 7.3.3](#733-combat-effectiveness-rating-cer). This applies to the first valid attack across all combats in the turn, regardless of system or initiative phase. If multiple combats occur, only the first attacking squadron in the earliest resolved combat receives this benefit.
- Morale effects last for the current turn only.
- Prestige ≤ 0 automatically triggers morale crisis without requiring a roll.

**Morale Crisis (Prestige ≤ 0):**

When a House's prestige drops to zero or below, morale collapses:
- All CER rolls receive -1 penalty (no morale check roll required).
- One random fleet refuses orders and holds position for the turn.
- Effects persist until prestige rises above 0.

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

**Spacelift Command Protection:**

Spacelift Command ships are screened behind the Task Force during combat operations and do not engage in combat. Spacelift ships are destroyed if all friendly escort fleets in their house's Task Force are destroyed or retreat while hostile forces remain in the system. The presence of non-hostile houses does not protect Spacelift ships belonging to a retreating or destroyed Task Force.

## 7.3 Space Combat

All fleets within a solar system are mandated to engage forces from houses with Enemy diplomatic status during their turn, with the following exceptions:

- Fleets under Fleet Order 04: Guard a Starbase
- Fleets under Fleet Order 05: Guard/Blockade a Planet

When multiple houses are present in a solar system, combat engagement is determined by diplomatic relationships as defined in Section 8.1. Each house forms an independent Task Force and engages only those houses identified as hostile according to diplomatic status and territorial context.

**Specific Engagement Rules:**

1. **Blockade Engagement**: Fleets assigned to Blockade an enemy planet (Fleet Order 05) will engage only with enemy fleets ordered to Guard that same planet.

2. **Guard Engagement**: Fleets assigned to Guard a planet (Fleet Order 05) will engage only enemy fleets with orders ranging from 05 to 08 and 12, focusing on defensive or blockading actions.

3. **Territorial Defense**: Regardless of diplomatic status, houses will defend their controlled colonies against direct threats. Fleet orders 05 through 08 and 12 directed at a colony constitute direct threats and trigger defensive engagement from the colony's controlling house.

Task Forces form according to [Section 7.2](#72-task-force-assignment). Each house forms an independent Task Force from its applicable fleets and installations. Houses do not combine forces into joint Task Forces, even under Non-Aggression Pacts.

Squadrons are not allowed to change assignments or restructure during combat engagements or retreats.

### 7.3.1 Combat Initiative and Phase Resolution

Space combat resolves in initiative phases based on unit tactical characteristics. Each phase resolves completely before proceeding to the next phase. When multiple houses are present, all houses participate simultaneously in each phase according to their unit types.

**Combat Initiative Order:**

1. **Undetected Raiders** (Ambush Phase)
2. **Fighter Squadrons** (Intercept Phase)
3. **Detected Raiders** (Stealth Phase)
4. **Capital Ships** (Main Engagement Phase)

Units destroyed in an earlier phase do not participate in later phases.

**Simultaneous Attack Resolution:**

Within each phase, when multiple units attack simultaneously (same initiative tier), use the following resolution sequence:

1. **Target Selection**: All attacking units select their targets using [Section 7.3.2](#732-target-priority-rules)
2. **Damage Application**: All damage is applied simultaneously after all selections are made
3. **Overkill Handling**: If multiple attackers independently selected the same target and combined damage exceeds destruction threshold, excess damage is lost

This creates natural variance in combat outcomes due to independent target selection.

#### 7.3.1.1 Phase 1: Undetected Raiders (Ambush Phase)

Cloaked Raider fleets that successfully evaded ELI detection during the pre-combat detection phase strike first with full ambush advantage.

**Pre-Combat Detection:**

Before combat begins, all ELI-equipped units (Scouts and Starbases) in the defending force attempt to detect cloaked Raiders using the detection mechanics defined in [Section 2.4.3](assets.md#243-raiders).

For each defending ELI unit:
- Calculate effective ELI level (weighted average, dominant tech penalty, mesh network modifier)
- Starbases receive +2 ELI modifier for detection rolls
- Roll detection against each attacking cloaked fleet's highest CLK rating
- If detected, the Raider fleet loses ambush advantage and attacks in Phase 3 instead

**Ambush Resolution:**

Undetected Raiders attack before any defending units can respond:
- Raiders receive +4 die roll modifier on CER roll (see [Section 7.3.3](#733-combat-effectiveness-rating-cer))
- Each Raider squadron independently selects targets using [Section 7.3.2](#732-target-priority-rules)
- All Raider squadrons select targets, then all damage is applied simultaneously
- Destroyed targets do not return fire
- Multiple undetected Raider squadrons attack simultaneously in this phase

#### 7.3.1.2 Phase 2: Fighter Squadrons (Intercept Phase)

All fighter squadrons in the system attack simultaneously, regardless of ownership or deployment status. Fighters attack before capital ships can engage, representing their speed and intercept capability.

**Fighter Participation:**

**Colony-Owned Fighters:**
- Permanently stationed at colony (planet-based assets)
- Always participate in system defense
- Fight until destroyed or enemy eliminated
- Never retreat independently from combat

**Carrier-Owned Fighters:**
- Automatically deploy when carrier enters combat
- Remain carrier-owned assets throughout engagement
- Fight alongside colony-owned fighters
- Retreat only when carrier retreats (not independent retreat)

**Fighter Attack Mechanics:**

All fighters (colony-owned and carrier-owned) attack using the target priority rules defined in [Section 7.3.2](#732-target-priority-rules).

**Fighter Attack Resolution:**
1. Each fighter squadron independently selects a target using weighted random selection
2. All fighter squadrons complete target selection
3. All damage is applied simultaneously
4. Each fighter squadron applies its full AS as damage to its selected target

Fighters follow the special fighter targeting rule: prioritize enemy fighters first, then apply bucket order if no enemy fighters present.

**Fighter Vulnerability:**

Fighters have low Defense Strength due to their lightweight construction. After dealing damage in Phase 2, fighters remain on the battlefield and are subject to return fire from surviving enemy units in subsequent phases. Fighters skip the crippled state and transition directly from undamaged to destroyed per [Section 7.1.2](#712-combat-state).

Colony-owned fighters never retreat from combat and fight until destroyed or the enemy is eliminated. Carrier-owned fighters retreat only when their carrier retreats.

**Fighter Independence During Combat:**

Fighter squadrons remain fully operational throughout combat regardless of:
- Starbase damage or destruction
- Population losses from orbital bombardment
- Infrastructure capacity violations

Capacity violations resulting from combat damage are evaluated at the end of combat resolution. The 2-turn grace period for resolving violations begins on the following turn (see [Section 2.4.1](assets.md#241-fighter-squadrons-carriers)).

**Carrier-Owned Fighter Post-Combat:**

**In Hostile/Neutral Systems:**
- After combat ends:
  - If carrier survives: fighters re-embark immediately or be destroyed
  - If carrier destroyed: all carrier-owned fighters destroyed
  - If carrier withdraws: carrier-owned fighters must withdraw with carrier or be destroyed
- No ownership transfer occurs

**In Friendly/Controlled Systems:**
- After combat: carrier-owned fighters re-embark immediately, remain carrier-owned
- No ownership transfer unless permanent deployment executed outside combat (see [Section 2.4.1](assets.md#241-fighter-squadrons-carriers))

#### 7.3.1.3 Phase 3: Detected Raiders (Stealth Phase)

Raiders that were successfully detected by ELI units during the pre-combat detection phase attack in this phase, having lost their ambush advantage.

Detected Raiders attack using normal combat mechanics (same as capital ships in Phase 4):
- Each Raider squadron rolls for CER independently (see [Section 7.3.3](#733-combat-effectiveness-rating-cer))
- Each Raider squadron selects target using [Section 7.3.2](#732-target-priority-rules)
- All Raider squadrons complete target selection, then all damage is applied simultaneously
- Apply damage to selected targets

Detected Raiders resolve their attacks before the main capital ship engagement. Multiple detected Raider squadrons attack simultaneously in this phase.

#### 7.3.1.4 Phase 4: Capital Ships (Main Engagement Phase)

All remaining capital ships attack by squadron in this phase. Squadron attack order is determined by flagship Command Rating (CR).

**Attack Order Resolution:**

1. Squadrons attack in descending order by flagship CR (highest CR attacks first)
2. Squadrons with equal CR attack simultaneously using simultaneous attack resolution
3. For each CR tier (attacking simultaneously):
   - Each squadron rolls for CER (see [Section 7.3.3](#733-combat-effectiveness-rating-cer))
   - Each squadron selects target using [Section 7.3.2](#732-target-priority-rules)
   - All squadrons in this CR tier complete selections
   - All damage is applied simultaneously
4. Destroyed squadrons do not return fire in subsequent CR tiers

**Squadron Damage Application:**

A squadron fights as a single unit. The squadron's total AS and DS values are the sum of all ships under the flagship's command.

When a squadron takes damage:
- Damage is applied to the squadron's total DS pool
- Individual ships within the squadron are destroyed when cumulative damage exceeds their individual DS
- Ships are removed from the squadron in order of lowest DS first (smallest ships destroyed first)
- The flagship is always the last ship destroyed in a squadron

**Squadron Composition During Combat:**

Command Capacity (CC) is a fleet formation constraint validated during fleet commissioning and reorganization in the Command Phase per [Section 1.3.3](gameplay.md#133-command-phase). Once combat begins, squadrons fight as integrated tactical units regardless of CC/CR ratios. As ships are destroyed, the squadron's CC may fall below the flagship's CR, but this does not affect combat operations. Players can reorganize squadrons to restore CC/CR compliance during the Command Phase after combat concludes.

### 7.3.2 Target Priority Rules

All attacking units (squadrons, fighters, and Starbases) select targets using the following priority system.

**Terminology:**
- **Fighter squadron**: A squadron consisting entirely of fighter craft with no capital ship flagship (bucket 4)
- **Capital ship squadron**: A squadron led by a capital ship flagship (buckets 1, 2, or 3)

#### 7.3.2.1 Diplomatic Filtering

Before applying target priority rules, attacking units must identify valid targets based on diplomatic relationships as defined in [Section 8.1](diplomacy.md#81-diplomacy).

**Hostile Force Identification:**

An attacking unit may only target Task Forces from houses considered hostile. A house is considered hostile if any of the following conditions apply:

1. The houses have Enemy diplomatic status per [Section 8.1.3](diplomacy.md#813-enemy)
2. The target Task Force contains fleets with orders 05 through 08 or 12 directed at the attacking house's controlled systems per [Section 8.1.5](diplomacy.md#815-territorial-control)
3. The target Task Force is executing patrol orders in territory controlled by the attacking house and the houses do not have a Non-Aggression Pact per [Section 8.1.2](diplomacy.md#812-non-aggression-pacts)
4. The target Task Force has engaged the attacking house's forces in previous rounds of the current engagement

**No Valid Targets:**

If an attacking squadron has no valid hostile targets available due to diplomatic filtering, that squadron does not attack during the current phase. The squadron remains in the engagement and may attack in subsequent combat rounds if hostile targets become available.

#### 7.3.2.2 Bucket Classification

Every squadron and installation is assigned to a bucket based on its type:

| Bucket (Priority Order) | Unit Type | Base Weight |
|------------------------|-----------|-------------|
| **1 – Raider**         | Squadron with Raider flagship | 1.0 |
| **2 – Capital**        | Squadron with Cruiser or Carrier flagship | 2.0 |
| **3 – Destroyer**      | Squadron with Destroyer flagship | 3.0 |
| **4 – Fighter**        | Fighter squadron (no capital ship flagship) | 4.0 |
| **5 – Starbase**       | Orbital installation | 5.0 |

**Notes:**
- Fighter squadrons consist entirely of fighter craft and have no capital ship flagship
- Starbases are orbital installations, not squadrons
- Lower bucket numbers indicate higher targeting priority

#### 7.3.2.3 Special Rule: Fighter Squadron Targeting

When a fighter squadron attacks:

1. **Check for enemy fighters:** If any enemy fighter squadrons (bucket 4) exist among hostile Task Forces, build candidate list from all enemy fighter squadrons only
2. **If enemy fighters exist:** Compute weights and select target using weighted random selection (see 7.3.2.5)
3. **If no enemy fighters exist:** Fall back to standard bucket order targeting (7.3.2.4)

This represents fighter squadrons establishing air superiority before engaging capital ships.

#### 7.3.2.4 Standard Bucket Order Targeting

For all non-fighter attackers (capital ship squadrons, Raiders, Starbases) and fighters when no enemy fighters exist:

1. **Walk bucket order:** Raider (1) → Capital (2) → Destroyer (3) → Fighter (4) → Starbase (5)
2. **Build candidate pool:** For each bucket in order, collect all enemy units from hostile Task Forces matching that bucket
3. **Select first non-empty bucket:** The first bucket containing at least one enemy unit becomes the candidate pool
4. **Apply weighted random selection:** Select target from candidate pool using weights (see 7.3.2.5)
5. **No valid targets:** If no enemy units exist in any bucket from hostile houses, the attacker does not fire this phase

#### 7.3.2.5 Weighted Random Target Selection

Once a candidate pool is determined from hostile Task Forces:

1. **Calculate weight for each candidate:**
   ```
   Weight = Base_Weight(bucket) × Unit_Size × Crippled_Modifier
   ```
   Where:
   - `Base_Weight(bucket)` is from the bucket classification table (7.3.2.2)
   - `Unit_Size` is the number of ships in the squadron (or 1 for Starbases)
   - `Crippled_Modifier` = 2.0 if unit is crippled, 1.0 if undamaged

2. **Perform weighted random draw:**
   - Use PRNG seeded with SHA-256 hash of string `"{gameId}-{turnNumber}"` modulo 2^32
   - Alternatively, custom seed can be specified for testing or alternate outcomes
   - Select target based on weighted probability distribution
   - Standard weighted random selection algorithm (available in most programming language standard libraries)

3. **Apply damage to selected target:**
   - Fighters: Apply full AS as damage
   - Other units: Apply CER × AS as damage (see [Section 7.3.3](#733-combat-effectiveness-rating-cer))

**Crippled Unit Priority:**

Crippled units (squadrons and Starbases) receive double weight in target selection, representing tactical doctrine to finish weakened enemies before engaging fresh forces. This creates natural "focus fire" behavior on damaged units while still allowing fresh large squadrons to draw fire.

**Deterministic Combat:**

The SHA-256 hash ensures combat resolution is deterministic and reproducible for the same game state, allowing for replay analysis and debugging. The same tactical situation on the same turn of the same game will always produce identical target selections.

#### 7.3.2.6 Interaction with Damage Restrictions

Target selection works in conjunction with damage application restrictions from [Section 7.3.3](#733-combat-effectiveness-rating-cer):

**First Combat Round:**
- Fresh squadrons targeted by size and bucket priority
- Damage typically cripples multiple squadrons (restriction #2 prevents immediate destruction)
- Task Force degraded but remains combat-effective

**Subsequent Rounds:**
- Crippled squadrons and Starbases receive 2x targeting weight
- Attackers naturally focus fire on crippled targets
- Once all enemy squadrons in a Task Force are crippled, destruction proceeds by weighted probability
- Larger crippled squadrons eliminated first (higher weight)

**Critical Hit Exception:**
- Critical hits allow destroying a squadron even if other squadrons in the Task Force remain undamaged
- See [Section 7.3.3](#733-combat-effectiveness-rating-cer) for critical hit mechanics

This creates attrition combat where:
1. Initial engagement cripples multiple squadrons (spread damage)
2. Follow-up attacks destroy crippled squadrons (focused fire)
3. Task Forces degrade systematically rather than through alpha strikes

#### 7.3.2.7 Target Priority Summary

**Fighter squadrons:**
1. Enemy fighter squadrons from hostile houses (if any exist) - weighted by size and crippled state
2. Raiders → Capital → Destroyer → Starbase from hostile houses (if no enemy fighters) - weighted by size and crippled state

**All other attackers:**
1. Raiders from hostile houses - weighted by size and crippled state
2. Capital ships (Cruisers, Carriers) from hostile houses - weighted by size and crippled state
3. Destroyers from hostile houses - weighted by size and crippled state
4. Fighter squadrons from hostile houses - weighted by size and crippled state
5. Starbases from hostile houses - weighted by crippled state (size = 1)

**Weighting Factors (applied multiplicatively):**
- **Bucket Base Weight:** 1.0 (Raider) to 5.0 (Starbase)
- **Unit Size:** Number of ships in squadron (or 1 for Starbases)
- **Crippled Modifier:** 2.0 if crippled, 1.0 if undamaged

This creates a threat-based targeting hierarchy where high-value units (Raiders) are prioritized, modified by squadron size (larger = more threatening) and damage state (crippled = easier kill).

### 7.3.3 Combat Effectiveness Rating (CER)

After determining combat initiative order and resolving detection checks, combat proceeds in rounds. At the beginning of each combat round (for phases that use CER), each attacking unit rolls independently for Combat Effectiveness Rating.

Each squadron rolls once for CER and applies CER × (sum of all ships' AS in squadron).

**CER Table:**

| **Modified 1D10 Die Roll** | **Space Combat CER**             |
| -------------------------- | -------------------------------- |
| Less than zero, 0, 1, 2    | One Quarter (0.25) (round up)    |
| 3, 4                       | One Half (0.50) (round up)       |
| 5, 6                       | Three Quarters (0.75) (round up) |
| 7, 8                       | One (1)                          |
| 9\*                        | One\* (1)                        |
| 9+                         | One (1)                          |

\*If the die roll is a natural nine before any required modification, then a critical hit is achieved

**Die Roll Modifiers:**

| Modifier | Value | Notes                                  | Applicable Phases |
| -------- |:-----:| -------------------------------------- | ----------------- |
| Scouts   | +1    | Maximum benefit for all Scouts in Task Force | All CER phases |
| Morale   | -1 to +2 | Per turn morale check (see [Section 7.1.4](#714-morale)) | All CER phases |
| Surprise | +3    | First round only                       | Phase 1 only      |
| Ambush   | +4    | First round only                       | Phase 1 only      |

**CER Application:**

**Phase 2 (Fighter Squadrons):**
- Fighters do NOT use CER
- Each fighter squadron independently selects a target using [Section 7.3.2](#732-target-priority-rules)
- Each fighter squadron applies its full AS as damage to its selected target
- All selections are made, then all damage is applied simultaneously

**Phases 1, 3, and 4 (Raiders and Capital Ships):**
- Each attacking squadron rolls independently for CER
- Calculate total hits: `Total Hits = CER × Squadron_AS`
- Squadron selects target using [Section 7.3.2](#732-target-priority-rules)
- All squadrons in the same initiative tier complete target selection
- All damage is applied simultaneously

**Damage Application Restrictions:**

After target selection and CER calculation, apply hits to selected target with the following restrictions:

1. **Reduction Threshold:** If hits equal or exceed the target's DS, the target is reduced (undamaged → crippled, or crippled → destroyed)
2. **Destruction Protection:** Squadrons are not destroyed until all other squadrons in the Task Force are crippled (does not apply to Starbases)
3. **Excess Hit Loss:** Excess hits beyond destruction threshold are lost if restrictions apply

**Crippled Unit Effects:**

Crippled squadrons and Starbases multiply their AS by 0.5, rounded up to the nearest whole number.

Destroyed squadrons are no longer a factor and the Task Force loses their associated die roll modifiers (e.g. Scouts).

**Critical Hits:**

Critical hits (natural 9 on die roll before modifiers) have special effects:

1. **Nullify Destruction Protection:** Restriction #2 above is nullified - the squadron can be destroyed even if other squadrons in the Task Force remain undamaged
2. **Force Reduction:** If the critical hit cannot reduce the selected target according to restriction #1 (insufficient damage), then the squadron with the lowest DS in the target Task Force is reduced instead

**Overkill Damage:**

When multiple attackers independently select the same target during simultaneous attack resolution:
- Combined damage from all attackers is applied to the target
- If combined damage exceeds destruction threshold and restriction #2 applies (other squadrons not yet crippled), the target is crippled but not destroyed
- Excess damage beyond crippling threshold is lost
- Once all squadrons are crippled, excess damage can destroy targets

### 7.3.4 Rounds

Combat continues in rounds until one side is completely destroyed or manages a retreat.

Combat action within each phase is simultaneous; all units have the opportunity to attack at least once in their designated phase, regardless of damage sustained during the round.

After all phases complete and hits are applied:

1. **Casualty Assessment:** Mark all crippled and destroyed units (colony-owned and carrier-owned fighters tracked separately)
2. **Capacity Violation Checks:** Evaluate colonies for fighter capacity violations (only colony-owned fighters count toward capacity)
3. **Recalculate AS:** Determine total AS of all surviving Task Forces
4. **ROE Check:** Each Task Force evaluates retreat conditions independently according to [Section 7.1.1](#711-rules-of-engagement-roe)

**Multi-Faction Retreat Evaluation:**

When multiple houses are present in combat, each Task Force independently evaluates retreat by comparing its total combat strength against the combined strength of all hostile Task Forces.

To evaluate retreat:
1. Sum the total AS of all Task Forces identified as hostile per [Section 7.3.2.1](#7321-diplomatic-filtering)
2. Compare this combined hostile strength against the evaluating house's own Task Force strength
3. Apply the ROE threshold from [Section 7.1.1](#711-rules-of-engagement-roe) to determine if retreat is warranted

One house retreating does not force other houses to retreat. Combat continues between remaining Task Forces.

**Combat Termination Conditions:**

Combat ends when any of the following conditions are met:

- Only one Task Force remains in the system
- All remaining Task Forces are non-hostile to each other per [Section 7.3.2.1](#7321-diplomatic-filtering)
- All Task Forces have retreated from the engagement

If combat reduces the engagement such that all remaining Task Forces are non-hostile to each other, combat immediately ceases even if multiple houses remain in the system. This occurs when all Enemy relationships have been eliminated through retreat or destruction, leaving only Neutral or Non-Aggression relationships.

If more than one hostile Task Force remains and no retreat occurs, proceed to the next combat round.

### 7.3.5 Retreat

A Task Force may retreat from combat after the first round, in accordance with their ROE, and between rounds thereafter.

**Retreat Mechanics:**

Squadrons in a retreating Task Force fall back to their original fleet formations and flee to the closest friendly star system via available jump lanes. Friendly systems are those controlled by the retreating house.

**No Retreat Sanctuary:**

Retreating fleets arriving in a new system do not receive sanctuary protection. If hostile forces are present at the retreat destination, the retreating fleet immediately engages in combat according to standard engagement rules. Fleets should plan retreat routes to avoid hostile territory.

**Retreat Restrictions:**

- Colony-owned fighters never retreat from combat
- If colony-owned fighters remain, they screen their retreating Task Force
- Combat continues until all colony-owned fighters are destroyed
- Spacelift Command ships are destroyed if their escort fleets are destroyed
- Crippled ships cannot retreat through restricted lanes

**Carrier-Owned Fighter Retreat:**

Carrier-owned fighters do not retreat independently. They retreat only when their carrier retreats.

**In Hostile/Neutral Systems:**
- Carrier-owned fighters withdraw with retreating carrier (emergency withdrawal, no re-embark time)
- Destroyed if carrier lost or left behind
- Crippled carriers can perform emergency withdrawal with carrier-owned fighters

**In Friendly Systems:**
- Carrier-owned fighters withdraw with carrier (emergency withdrawal, no re-embark time)
- Carrier-owned fighters remain carrier-owned, do not transfer to colony
- Crippled carriers can perform emergency withdrawal with carrier-owned fighters

**Colony-Owned Fighters:**
- Never retreat independently from combat
- Screen retreating friendly forces
- Fight until destroyed

### 7.3.6 End of Space Combat

After the last round of combat, surviving Task Forces disband and squadrons rejoin their original fleets.

**Post-Combat Resolution:**

1. **Repair Requirements:** Crippled ships require shipyard repairs (1 turn, 25% of PC)
2. **Carrier Fighter Re-embark:** Carrier-owned fighters temporarily deployed re-embark immediately after combat

Destroyed ships cannot be salvaged from battle wreckage. Salvage operations apply only to active fleets intentionally decommissioned via Fleet Order 15 per [Section 6.2.16](#6216-salvage-15).

**Fighter Ownership After Combat:**

- Colony-owned fighters remain colony-owned
- Carrier-owned fighters re-embark immediately and remain carrier-owned
- No automatic ownership transfers occur as result of combat
- Players must execute permanent deployment procedure to transfer carrier-owned fighters to colony ownership (see [Section 2.4.1](assets.md#241-fighter-squadrons-carriers))

## 7.4 Starbase Combat

Starbases serve as the primary defense if a hostile fleet aims to blockade, bombard, invade, or blitz a colony. They form a combined Task Force as per [Section 7.2](#72-task-force-assignment).

Fleets with orders to guard the Starbase (Fleet Orders 04) also join the Task Force.

Combat will proceed in a similar fashion to [Section 7.3](#73-space-combat), with the following special rules:

1. **Critical Hit Protection:** If a player rolls a critical hit against a Starbase on the first attempt, re-roll a second time. The second roll stands regardless of result.
2. **Starbase Bonus:** Starbases receive an extra +2 die roll modifier on all CER rolls.
3. **Starbase State Transitions:** Starbases follow the same state transitions as squadrons (undamaged → crippled → destroyed) as defined in [Section 7.1.2](#712-combat-state).
4. **Starbase Targeting:** Starbases are assigned to bucket 5 and can be targeted using the rules in [Section 7.3.2](#732-target-priority-rules). Crippled Starbases receive the 2x targeting weight modifier.

Starbases are fortified with superior AI and sensors, making them formidable defensive platforms with high defensive capabilities.

## 7.5 Planetary Bombardment

After orbital supremacy is achieved, planets are vulnerable to surface attack. Planetary shields, ground batteries, and ground forces are the last line of defense before invasion or blitz.

Like space combat, planetary bombardment is simultaneous. No more than three combat rounds are conducted per turn.

### 7.5.1 Determine Hits

The attacking player will total the AS value of their fleet's surviving squadrons and the defending player will total the AS strength of all remaining ground batteries. Both players roll on the Bombardment Table.

**Bombardment Table**:

| **1D10 Die Roll** | **Bombardment CER**           |
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
| SLD6      | 90       | > 2       | 50%               |

Reduce the attacking player's hits by the percentage, rounding up. This is the number of effective hits.

Example: A fleet with AS of 75 bombards a planet protected by a SLD3 shield, and the defending player rolls a 15.

```
Hits = 75 * (1 - .35) = 49
```

Note that shields can only be destroyed by Marines during planetary invasion.

**Planet-Breaker Shield Penetration:**

Planet-Breakers completely bypass planetary shields during bombardment per [Section 2.4.8](assets.md#248-planet-breaker). When calculating bombardment damage:

1. **Separate AS calculations:**
   - Planet-Breaker AS is calculated separately from other ships
   - Other ships' AS is subject to normal shield mechanics above

2. **Planet-Breaker bombardment:**
   - Roll CER for Planet-Breaker squadrons independently
   - Apply `CER × Planet-Breaker AS` directly to ground batteries (no shield roll)
   - Planet-Breaker damage bypasses all shield levels (SLD1-SLD6)

3. **Mixed fleet bombardment:**
   - If Task Force contains both Planet-Breakers and conventional ships, resolve separately:
     - Planet-Breaker hits: Apply directly to ground batteries
     - Conventional ship hits: Apply shield reduction, then apply to ground batteries
   - Defender allocates damage from both sources to ground batteries

This creates strategic choices for defenders: shields protect against conventional bombardment but are useless against Planet-Breakers, while ground batteries defend against both.

### 7.5.3 Ground Batteries

The player who rolled the die will determine where hits are applied. Because ground batteries are all the same, selecting which ground batteries to target is moot. Unlike ships in squadrons, ground batteries are reduced as individual units.

The following **restrictions** apply:
1. If the number of hits equal the opposing unit's DS, the unit is reduced.
2. Units are not destroyed until all other units are crippled.
3. Excess hits leftover against Ground Batteries are summed.
4. Excess hits are lost against squadrons if restrictions apply.

Crippled units multiply their AS by 0.5, rounded up to the nearest whole number.

**Critical Hits**:

Critical hits are a special case, and only apply against the attacking fleet. Restriction #2 in the list above is nullified.

Additionally, if a player takes a critical hit and is unable to reduce a unit according to restriction #1 above, then the squadron with the lowest DS is reduced.

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

Crippled units multiply their AS by 0.5, rounded up to the nearest whole number.

Repeat the process until one side is completely destroyed.

If the planet is conquered, loyal House citizens destroy 50% of the colony's remaining IU before order is restored.

### 7.6.2 Planetary Blitz

Fleets and Ground batteries conduct one round of combat in accordance with [Section 7.5](#75-planetary-bombardment), with the exception that ground units and civilian infrastructure are not targeted ([Section 7.5.4](#754-ground-units-civilian-infrastructure)). Troop transports are included as individual units within the attacking player's fleet and may be destroyed on their way down to the surface by Ground Batteries.

Because of quick insertion and Ground Battery evasion, surviving Marines that manage to land in their troop transports multiply AS by 0.5 (rounding up).

Ground battle occurs in a similar fashion to [Section 7.6.1](#761-planetary-invasion), with the exception that IUs are not destroyed if the planet is conquered. All remaining planet assets are seized by the invading House, including IU, shields, spaceports, and ground batteries.

