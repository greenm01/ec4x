# 7.0 Combat

Destroy your enemies across three distinct combat theaters. Your fleets fight through space battles, orbital sieges, and planetary invasions to seize enemy colonies. Each theater demands different tactics, unit compositions, and strategic decisions.

This section covers combat mechanics, engagement rules, and the progressive nature of planetary conquest. Master these systems to project power effectively and defend your empire against invasion.

---

## 7.1 The Three Combat Theaters

Planetary conquest requires methodical progression through three combat phases. Your attacking fleets must win each theater before advancing to the next—no shortcuts, no bypassing defenses.

### 7.1.1 Theater Progression

**Space Combat** (First Theater)

Fight enemy mobile fleets in deep space before reaching orbit. Your task forces engage defending fleets with full tactical mobility. Both sides maneuver, concentrate fire, and attempt to break enemy formations.

**Who fights:**
- Your attacking fleets
- Enemy mobile defenders (fleets without Guard commands)
- Undetected Raiders can ambush with combat bonuses

**Outcome determines:**
- If attackers win: Proceed to orbital combat
- If defenders win: Attackers retreat or are destroyed
- If no mobile defenders present: Attackers proceed directly to orbital combat

**Orbital Combat** (Second Theater)

Assault fortified orbital defenses after achieving space superiority. Your fleets engage stationary defenders protecting the planet—guard fleets, reserve forces, starbases, and unassigned ships fight as a unified defensive position.

**Who fights:**
- Your surviving attack fleets (if you won space combat)
- Enemy guard fleets (fleets with Guard commands)
- Enemy reserve fleets
- Enemy starbases 
- Enemy unassigned ships at colony

**Outcome determines:**
- If attackers win: Achieve orbital supremacy, proceed to planetary operations
- If defenders win: Attackers retreat without reaching planet surface
- If no orbital defenders: Attackers achieve supremacy unopposed

**Planetary Combat** (Third Theater)

Bombard planetary defenses and invade the surface after securing orbit. Your fleets destroy shields, neutralize ground batteries, and deploy invasion forces. The final phase before colony capture.

**Who fights:**
- Your bombardment fleets (any combat ships)
- Your invasion forces (marines from troop transports)
- Enemy planetary shields (reduce bombardment damage)
- Enemy ground batteries (fire on orbiting ships during bombardment)
- Enemy ground forces (armies and marines defend against invading marines)

**Outcome determines:**
- Successful bombardment: Infrastructure destroyed, defenses weakened
- Successful invasion: Colony captured, ownership transfers
- Failed invasion: Your invasion forces destroyed, defenders retain control

### 7.1.2 Why Progressive Combat Matters

**No theater skipping**: Your fleets cannot bypass defenses. Guard commands mean enemy fleets defend in orbital combat only—they don't participate in deep space battles. This creates strategic depth: defending admirals choose which fleets defend which theater.

**Resource allocation**: Attackers must maintain overwhelming force through all three phases. Winning space combat with 80% losses means facing orbital defenses with a crippled fleet. Plan for attrition.

**Defender advantages**: Each theater provides natural defensive advantages. Starbases add firepower in orbital combat. Planetary shields negate bombardment. Ground batteries threaten invasion forces. Defenders fight from prepared positions.

---

## 7.2 Combat Fundamentals

Every engagement follows consistent rules governing combat resolution, damage application, and retreat mechanics. Master these fundamentals to predict combat outcomes and design effective fleet compositions.

### 7.2.1 Ship Status

Ships exist in three combat states determining effectiveness:

**Undamaged** (Full Effectiveness)
- Ship operates at full Attack Strength (AS) and Defense Strength (DS)
- Contributes full combat power to task force
- Can execute all missions

**Crippled** (Severely Degraded)
- Ship suffers major damage reducing combat effectiveness
- Attack Strength (AS) reduced to 50%
- Defense Strength (DS) reduced to 50%
- Maintenance cost reduced to 50% of normal
- Cannot traverse restricted jump lanes
- Requires drydock repairs (1 turn, 25% of build cost)
- Still operational but at reduced capability

**Destroyed** (Eliminated)
- Ship eliminated from combat
- Permanent loss

**Fighter Exception (Glass Cannons):**

Fighter ships skip the Crippled state entirely:
- Undamaged (100% AS/DS) → Destroyed
- Represents their fragility in combat
- Cannot be repaired once damaged
- Must be replaced through production

### 7.2.2 Hit Application Rules

Combat generates hits that damage or destroy ships. Hits apply following these strict rules:

**Rule 1: Must Cripple All Before Destroying Any**

All full-strength ships must be crippled before any crippled ships can be destroyed. This prevents instant-kill scenarios and ensures multi-round engagements.

Example:
```
Task force: 3 Battleships (Undamaged), 2 Cruisers (Crippled)
Receives: 120 hits

Hit application:
1. Battleship 1: 40 DS → Crippled (80 hits remaining)
2. Battleship 2: 40 DS → Crippled (40 hits remaining)
3. Battleship 3: 40 DS → Cannot cripple (insufficient hits)

Remaining 40 hits lost (cannot destroy Cruisers while Battleship 3 undamaged)

Result: 3 Battleships (all Crippled), 2 Cruisers (still Crippled)
```

**Rule 2: Critical Hits Bypass Protection**

Natural roll of 9 (before modifiers) = Critical Hit
- Can destroy crippled ships even with full-strength ships present
- Represents catastrophic damage (magazine explosion, reactor breach)
- If insufficient hits for normal damage, still inflicts 1 ship crippled/destroyed

**Rule 3: Excess Hits Lost**

If hits cannot be applied due to protection rules, they are lost. No "overkill" carry-over between rounds.

### 7.2.3 Rules of Engagement (ROE)

Set your fleet's aggression level with Rules of Engagement—a 0-10 scale determining when to retreat during combat. ROE compares your total AS to enemy total AS.

**ROE Retreat Thresholds:**

| ROE | Threshold | Meaning                        | Use Case                                |
|-----|-----------|--------------------------------|-----------------------------------------|
| 0   | 0.0       | Avoid all hostile forces       | Pure scouts, intel gathering            |
| 1   | 999.0     | Engage only defenseless        | Extreme caution                         |
| 2   | 4.0       | Need 4:1 advantage             | Scout fleets, recon forces              |
| 3   | 3.0       | Need 3:1 advantage             | Cautious patrols                        |
| 4   | 2.0       | Need 2:1 advantage             | Conservative operations                 |
| 5   | 1.5       | Need 3:2 advantage             | Defensive posture                       |
| 6   | 1.0       | Fight if equal or superior     | Standard combat fleets                  |
| 7   | 0.67      | Fight even at 2:3 disadvantage | Aggressive fleets                       |
| 8   | 0.5       | Fight even at 1:2 disadvantage | Battle fleets                           |
| 9   | 0.33      | Fight even at 1:3 disadvantage | Desperate defense                       |
| 10  | 0.0       | Fight regardless of odds       | Suicidal last stands, homeworld defense |

**Morale Modifies Effective ROE:**

Your house's prestige affects fleet morale, modifying effective ROE during combat:

| Prestige  | Morale Modifier | Effect on ROE                                     |
|-----------|-----------------|---------------------------------------------------|
| 0 or less | -2              | Fleets retreat much earlier (ROE 8 becomes ROE 6) |
| 1-20      | -1              | Fleets retreat earlier (ROE 8 becomes ROE 7)      |
| 21-60     | 0               | No change                                         |
| 61-80     | +1              | Fleets fight longer (ROE 6 becomes ROE 7)         |
| 81+       | +2              | Fleets fight much longer (ROE 6 becomes ROE 8)    |

**Homeworld Defense Exception**: Fleets defending their homeworld NEVER retreat regardless of ROE or losses.

**ROE does NOT affect explicit commands**: When you issue Bombard, Invade, or Attack commands, your fleet executes regardless of ROE. ROE only matters for automated retreat decisions during combat.

### 7.2.4 Task Force Formation

Fleets combine into **task forces** during combat—unified battle groups that concentrate firepower and share detection.

**Task force composition**:
- All ships from participating fleets
- Starbases at system (orbital combat only)
- Colony-assigned fighters (if applicable)
- Unassigned ships at colony (orbital combat only)

**Task force benefits**:
- Concentrated firepower: All ships engage simultaneously
- Screened units protected: Mothballed ships, auxiliary vessels (ETACS, Troop Transports), and facilities (shipyards, drydocks, spaceports) stay behind combat ships

**Multiple fleets in combat**: Friendly fleets fight alongside each other but remain organizationally distinct. Each fleet checks its own ROE independently and can retreat separately based on its own threshold. This creates emergent tactics where cautious fleets "screen" aggressive fleets then bug out when odds worsen.

**Multiple houses in combat**: Three-way or four-way battles resolve with each house forming separate task forces. All hostile task forces engage each other based on diplomatic status (Enemy, Hostile, or Neutral with threatening commands).

---

## 7.3 Detection & Intelligence

Raiders are specialized ships that can cloak entire fleets, making them invisible to enemy sensors. An undetected fleet gains a powerful **first-strike advantage** in combat.

### 7.3.1 Detection Mechanics

When fleets with Raiders engage in combat, a detection check determines if they remain hidden:

**Both Sides Have Raiders (Detection Roll-Off):**

Both sides roll to detect each other:
- Side A: 1d10 + CLK_A + ELI_A (+ Starbase +2)
- Side B: 1d10 + CLK_B + ELI_B (+ Starbase +2)

Compare results:
- Winner by 5+: Winner achieves **Ambush** (undetected, +4 DRM first round)
- Winner by 1-4: Winner achieves **Surprise** (detected late, +3 DRM first round)
- Tie: **Intercept** (both detected, no bonus)

**One Side Has Raiders (Detection Roll):**

Defender attempts to detect attacker:
- Attacker: 1d10 + CLK
- Defender: 1d10 + ELI (+ Starbase +2)

Compare results:
- Attacker wins by 5+: **Ambush** (+4 DRM first round)
- Attacker wins by 1-4: **Surprise** (+3 DRM first round)
- Defender wins: **Intercept** (Raiders detected, no bonus)

**Neither Has Raiders:**

No detection roll. **Intercept** condition (normal combat).

**Tie Detection Roll:**

If both sides have Raiders and the detection roll results in a tie, combat occurs under **Intercept** condition (simultaneous combat, no DRM bonuses). Neither side gains detection advantage—both fleets engage normally.

### 7.3.2 Intelligence Conditions

Detection determines the intelligence condition for the first combat round:

**Ambush** (Undetected by 5+)
- Winner applies hits FIRST
- Winner gets +4 DRM to combat roll
- Loser's survivors strike back (if any remain)
- First round only (subsequent rounds normal)
- Devastating advantage

**Surprise** (Detected Late, 1-4)
- Winner applies hits FIRST
- Winner gets +3 DRM to combat roll
- Loser's survivors strike back (if any remain)
- First round only (subsequent rounds normal)
- Significant advantage

**Intercept** (Normal Detection)
- SIMULTANEOUS hit application
- No first-strike bonus
- Both sides apply hits at same time
- Standard combat

**Detection only applies to first round.** Subsequent rounds always use Intercept condition (simultaneous combat).

### 7.3.3 Starbase Detection Support

Starbases provide advanced sensor support even in space combat (before they directly participate in orbital combat):

**Detection Bonus (Space AND Orbital):**
- +2 to detection roll (if starbase undamaged)
- Makes Raiders much harder to hide from fortified colonies
- Represents massive sensor arrays and tracking systems

**If Starbase Crippled:**
- No detection bonus (sensors damaged)
- No sensor coordination bonus (see below)

**If Starbase Destroyed:**
- All bonuses lost

---

## 7.4 Combat Resolution System

All combat—space, orbital, and planetary—uses a unified resolution system based on Attack Strength × Combat Effectiveness Rating.

### 7.4.1 Combat Round Sequence

**1. Calculate Attack Strength (Both Sides)**

Sum the Attack Strength (AS) of all participating ships:
- Space/Orbital: All combat ships (Raiders, Fighters, Capitals, Starbases in orbital)
- Bombardment: Fleet bombardment strength vs Ground Battery AS
- Invasion: Marine AS vs Ground Forces AS

**2. Apply Die Roll Modifiers (Both Sides)**

Calculate applicable modifiers (see sections below for specific DRMs per theater).

**3. Roll Combat Effectiveness Rating (Both Sides)**

Each side rolls: 1d10 + Die Roll Modifiers (DRM)

Look up modified roll on appropriate Combat Results Table:

**Space/Orbital Combat CRT:**
| Modified Roll | Combat Effectiveness Rating (CER) |
|---------------|-----------------------------------|
| 0, 1, 2       | 0.25× (one quarter, round up)     |
| 3, 4, 5       | 0.50× (one half, round up)        |
| 6, 7, 8       | 1.00× (full strength)             |
| 9 (natural)*  | 1.00× + Critical Hit              |
| 9+            | 1.00×                             |

*Natural 9 (before modifiers) triggers Critical Hit

**Ground Combat CRT (Bombardment/Invasion/Blitz):**
| Modified Roll | Combat Effectiveness Rating (CER) |
|---------------|-----------------------------------|
| ≤2            | 0.5× (half, round up)             |
| 3, 4, 5, 6    | 1.0× (full strength)              |
| 7, 8          | 1.5× (one and a half, round up)   |
| 9+            | 2.0× (double)                     |

Ground combat is more lethal—can achieve up to 2.0× effectiveness vs 1.0× maximum in space combat.

**4. Calculate Hits (Both Sides)**

Total Hits = Attack Strength × CER (round up)

Example:
```
Fleet AS: 200
Roll: 1d10 = 4, DRM = +2, Modified = 6
CER: 1.00×
Hits: 200 × 1.00 = 200 hits
```

**5. Apply Hits**

Apply hits based on intelligence condition:
- **Ambush/Surprise**: Winner applies hits first, survivors strike back
- **Intercept**: SIMULTANEOUS hit application

Follow hit application rules (Section 7.2.2):
- Must cripple all before destroying any
- Critical Hits bypass this rule
- Excess hits lost

**6. Check Retreat (Per Fleet)**

Each fleet independently checks current AS ratio vs enemy AS:
- Calculate: Fleet current AS / Enemy total AS
- Compare to fleet ROE threshold
- If below threshold: Fleet retreats (unless explicit command or homeworld defense)
- Retreating fleet moves to nearest friendly system
- Auxiliary vessels (ETACS, Troop Transports) assigned to fleet retreat with it
- If fleet destroyed, auxiliary vessels assigned to that fleet are also destroyed

**7. Determine Winner**

After all hits applied and retreats resolved:
- Calculate surviving Attack Strength (both sides)
- Higher surviving AS wins
- Tie: Defender wins
- Winner proceeds to next theater (if attacker) or repels attack (if defender)

### 7.4.2 Die Roll Modifiers Summary

**Space Combat:**
- Ambush (first round): +4 (Raider undetected by 5+)
- Surprise (first round): +3 (Raider undetected by 1-4)
- Fighter Superiority (all rounds): +1 (2:1 advantage) or +2 (3:1+ advantage)
- Starbase Sensors (all rounds): +1 (if starbase undamaged at colony)
- Morale (all rounds): ±1 or ±2 (based on house prestige)
- ELI Advantage (all rounds): +1 (if your ELI tech > enemy ELI)
- Homeworld Defense (all rounds): +1 (defending house homeworld only)

**Orbital Combat:**
- Same as Space Combat
- Starbases participate directly (contribute AS/DS to defender)

**Bombardment:**
- Planet-Breaker (all rounds): +4 (attacker, if Planet-Breaker ships present)
- Morale (all rounds): ±1 or ±2 (both sides)

**Invasion (Standard):**
- Prepared Defenses (all rounds): +2 (defender, entrenched colony)
- Homeworld Defense (all rounds): +1 (defender, if house homeworld)
- Morale (all rounds): ±1 or ±2 (both sides)

**Blitz:**
- Landing Under Fire (all rounds): +3 (defender, marines landing under battery fire)
- Homeworld Defense (all rounds): +1 (defender, if house homeworld)
- Morale (all rounds): ±1 or ±2 (both sides)

### 7.4.3 Fighter Superiority

Fighters provide a die roll modifier based on numerical advantage. Calculate each round (can change as fighters destroyed):

**Calculate Fighter Strength Ratio:**
- Your Fighter Strength (FS) = Sum of all Fighter ship AS
- Enemy Fighter Strength (FS) = Sum of all enemy Fighter ship AS
- Ratio = Your FS / Enemy FS

**Apply Modifier:**
- 3:1+ advantage: +2 DRM
- 2:1+ advantage: +1 DRM
- 1:1 to 2:1: +0 DRM
- 1:2 disadvantage: -1 DRM (enemy gets +1)
- 1:3 disadvantage: -2 DRM (enemy gets +2)

**Fighter Types:**

Fighters come in two assignments:
- **Colony-assigned**: Stationed at colony, defend location, cannot travel. Participate in space/orbital combat at their colony.
- **Carrier-assigned**: Housed in carriers, travel with fleet, deploy in combat anywhere. Lost if carrier destroyed while embarked.

Both types contribute to Fighter Superiority calculation during combat.

**Dynamic Advantage:**

As fighters are destroyed, superiority shifts. Losing fighters hurts twice:
1. Direct AS loss (less total damage inflicted)
2. DRM loss (worse combat rolls, compounding losses)

### 7.4.4 Morale Effects

House prestige affects combat morale, providing die roll modifiers:

**Morale Die Roll Modifier:**
| Prestige Level | Morale DRM | Effect |
|----------------|------------|--------|
| 0 or less | -2 | Poor morale, worse combat rolls |
| 1-20 | -1 | Low morale |
| 21-60 | 0 | Normal morale |
| 61-80 | +1 | High morale, better combat rolls |
| 81+ | +2 | Exceptional morale |

Morale applies to ALL combat rounds (not just first round like detection bonuses).

High prestige houses fight more effectively AND retreat less often (morale modifies ROE too).

---

## 7.5 Space Combat

Engage enemy mobile fleets in deep space. Your task forces clash with full tactical freedom—the first theater of planetary conquest.

### 7.5.1 Space Combat Participants

**Mobile Fleets Engage Based on Diplomatic Status and Mission Phase:**

Space combat follows the diplomatic escalation ladder defined in [Section 8.1 Diplomacy](08-diplomacy.md#81-diplomacy). Combat depends on whether fleets are **traveling through systems** or **executing missions at destinations**.

**During Travel (Moving Through Systems):**
- **Enemy Status**: Combat occurs automatically when fleets encounter each other
- **Hostile Status**: No combat during travel (safe passage)
- **Neutral Status**: No combat during travel (safe passage)

**At Mission Destination (Executing Fleet Commands):**

Combat and escalation follow a grace period system:

**Tier 1 Missions (Direct Colony Attacks):**
- Blockade, Bombard, Invade, Blitz targeting colony
- Neutral/Hostile → Escalate to Enemy, **immediate combat** (no grace period)

**Tier 2 Missions (System Control Contestation):**
- Patrol a System, Hold Position, Rendezvous in their controlled system
- Turn X: Neutral → Escalate to Hostile, **no combat** (grace period warning)
- Turn X+1: Hostile → **Combat occurs** (warning ignored)

**Tier 3 Missions (Non-Threatening):**
- Move, Seek Home, Guard own assets, Spy if undetected, etc.
- No escalation, no combat

**Key Principle**: Space combat over system control (Patrol, Hold) escalates to Hostile, NOT Enemy. Only direct colony attacks escalate to Enemy.

For complete escalation timing and threat categories, see [Section 8.1.6 Escalation Ladder](08-diplomacy.md#816-escalation-ladder-summary).

**Mobile Fleet Types** (Fight in Space Combat):
- Fleets with **Patrol commands** (active patrol duty)
- Fleets with **offensive mission commands** (Bombard, Invade, Blitz, Blockade)
- Fleets traveling through (missionState == Traveling)

**Who Does NOT Fight in Space Combat:**
- **Hold fleets**: Passive orbital posture, defend in orbital combat only
- **Orbital Guard fleets**: GuardStarbase, GuardColony commands - they defend in orbital combat only
- **Reserve fleets**: Stationed at colony, fight in orbital combat only
- **Mothballed fleets**: Offline, cannot fight
- **Starbases**: Fixed installations, orbital combat only (but provide sensor bonuses in space combat)
- **Scouts**: Stealthy vessels that slip through combat undetected to reach their mission target (detected only when on station conducting intelligence operations)

**Screened Units (Present in Space Combat, Do Not Fight):**
- **Auxiliary vessels**: ETACs and Troop Transports are screened by escorts, destroyed if their fleet loses (an unescorted auxiliary fleet would be immediately destroyed)

### 7.5.2 Space Combat Resolution

**Round 1:**

**Step 1: Detection Phase (If Raiders Present)**

Conduct detection roll (Section 7.3) to determine intelligence condition:
- Ambush: Winner gets +4 DRM, applies hits first
- Surprise: Winner gets +3 DRM, applies hits first
- Intercept: No bonus, simultaneous combat

**Step 2: Calculate Attack Strength**

Both sides sum total AS:
- All mobile fleet ships (Raiders, Fighters, Capitals)
- Colony-assigned fighters at location (if defending colony)
- Reduce crippled ships to 50% AS

**Step 3: Calculate Die Roll Modifiers**

Attacker DRM:
- Detection bonus (first round): +4 Ambush or +3 Surprise (if applicable)
- Fighter Superiority: +0, +1, or +2 (if advantage)
- Morale: ±1 or ±2
- ELI Advantage: +1 (if your ELI > enemy ELI)

Defender DRM:
- Detection bonus (first round): +4 Ambush or +3 Surprise (if applicable)
- Fighter Superiority: +0, +1, or +2 (if advantage)
- Starbase Sensors: +1 (if undamaged starbase at colony)
- Morale: ±1 or ±2
- ELI Advantage: +1 (if your ELI > enemy ELI)
- Homeworld: +1 (if defending house homeworld)

**Step 4: Roll CER**

Both sides: 1d10 + DRM → Space/Orbital Combat CRT

**Step 5: Calculate Hits**

Both sides: Total AS × CER = Total Hits (round up)

**Step 6: Apply Hits**

Based on intelligence condition:
- Ambush/Surprise: Winner applies hits first, survivors strike back
- Intercept: Simultaneous application

Follow hit application rules (must cripple all before destroying any).

**Step 7: Check Retreat**

Each fleet independently:
- Calculate current AS / enemy total AS
- Compare to ROE threshold
- Retreat if below threshold (unless explicit command or homeworld)
- Auxiliary vessels (ETACS, Troop Transports) retreat with their assigned fleet
- If fleet destroyed, auxiliary vessels assigned to that fleet are also destroyed

**Round 2+:**

Repeat steps 2-7, but:
- NO detection bonus (first round only)
- Fighter Superiority still applies (recalculate each round)
- Always Intercept condition (simultaneous)

Continue until: one side destroyed, one side retreated, or maximum 20 rounds.

**Desperation Mechanic:**

If 5 consecutive rounds occur with no ship state changes (stalemate):
- Both sides get +2 DRM next round (desperation attack)
- Represents all-out effort to break deadlock
- After desperation round, combat continues normally

### 7.5.3 Victory Conditions

**Attacker Victory:**
- All mobile defenders destroyed or retreated
- Attackers achieve space superiority
- **Result**: Proceed to orbital combat phase

**Defender Victory:**
- All attackers destroyed or retreated
- Defenders maintain space control
- **Result**: Attackers repelled, mission failed

**Mutual Withdrawal:**
- Both sides retreat simultaneously
- Rare but possible with evenly matched forces
- **Result**: Status quo maintained, no territorial change

---

## 7.6 Orbital Combat

Assault fortified colony defenses after winning space superiority. Your fleets engage guard forces, reserve fleets, starbases, and orbital ships in a unified defensive position.

### 7.6.1 Orbital Combat Participants

**Attackers** (If They Won Space Combat):
- All surviving attack fleets from space combat
- Any fleets that bypassed space combat (if no mobile defenders present)

**Orbital Defenders** (All Fight Simultaneously):
- **Guard fleets**: Fleets with GuardStarbase, GuardColony commands
- **Reserve fleets**: 50% maintenance fleets stationed at colony, fight at 50% AS with auto-assigned GuardColony command (orbital defense only)
- **Mothballed fleets**: 0% maintenance fleets (CANNOT FIGHT - must be screened)
- **Starbases**: Orbital installations with heavy firepower and detection capability
- **Unassigned ships**: Combat ships at colony not assigned to fleets
- **Colony-assigned fighters**: Fighters stationed at colony for defense

**Screened Units (Protected, Do Not Fight):**
- **Mothballed ships** (offline, defenseless)
- **Auxiliary vessels** (ETAC, Troop Transports - no combat capability in space/orbital)
- **Orbital neoria facilities** (shipyards, drydocks - orbital construction/repair facilities)
- **Spaceports** are planet-based and NOT auto-destroyed (only bombardment/invasion can destroy)
- **Note:** Starbases (Kastras) are NOT screened - they fight directly
- Screened units hide behind defending task force; destroyed if defenders eliminated (except spaceports)

### 7.6.2 Orbital Combat Differences from Space Combat

**New Detection Check:**

A new detection check is performed at the start of Orbital Combat:
- Raider fleets that were detected in Space Combat have a chance to re-cloak and gain the ambush bonus again
- Starbases, with their powerful sensors, add +2 bonus to the defender's detection roll, making it much harder to achieve an ambush in Orbital Combat

**Starbases Participate Directly:**

Starbases add significant AS/DS to defender task force:
- Fixed installations with heavy firepower
- Cannot retreat—fight to destruction or victory
- Provide detection bonus (+2) and sensor coordination (+1 DRM)
- If destroyed, all bonuses lost

**Reduced Mobility:**

- Defenders fight from fortified positions
- Attackers cannot maneuver as freely (planetary gravity well)
- Retreat harder for attackers (must break orbit under fire)

**Screened Unit Vulnerability:**

If defenders eliminated in orbital combat, screened units are destroyed:
- **Mothballed ships** destroyed
- **Auxiliary vessels** (ETAC, Troop Transports) destroyed
- **Orbital neoria facilities** (shipyards, drydocks) destroyed
- **Spaceports survive** (planet-based, protected by planet itself)

**Spaceport Destruction:**
Spaceports can only be destroyed by:
- **Bombardment**: Excess hits (after batteries destroyed) can destroy spaceports
- **Invasion**: Spaceports automatically destroyed when marines land (Section 7.8.1)

### 7.6.3 Starbase Combat Bonuses

Starbases provide significant defensive advantages:

**Detection Support (Already covered in Section 7.3.3):**
- +2 Detection bonus (helps detect Raiders)
- Only if starbase undamaged

**Sensor Coordination:**
- +1 DRM to defender combat rolls (all rounds)
- Represents superior fire control, targeting computers, defensive coordination
- Maximum +1 regardless of number of starbases
- Only if at least one starbase undamaged

**Direct Combat Participation:**
- Starbase contributes AS/DS to defender task force
- Multiple starbases = cumulative AS/DS (significant firepower)
- Each starbase can be crippled (50% AS/DS) then destroyed
- Difficult targets (high DS)

**If Starbase Crippled:**
- No detection bonus (sensors damaged)
- No sensor coordination (+1 DRM lost)
- Still fights at 50% AS/DS

**If All Starbases Destroyed:**
- All bonuses lost
- Orbital defense significantly weakened

**Strategic Implications:**

Starbases make orbital assaults extremely costly. Late-game sieges against multiple starbases require overwhelming force or Planet-Breaker superweapons to crack fortress colonies.

### 7.6.4 Orbital Combat Resolution

Same as Space Combat (Section 7.5.2), with these differences:

**Die Roll Modifiers (Orbital Combat):**

Attacker DRM:
- Detection bonus (first round): +4 Ambush or +3 Surprise (if applicable)
- Fighter Superiority: +0, +1, or +2 (if advantage)
- Morale: ±1 or ±2
- ELI Advantage: +1 (if your ELI > enemy ELI)

Defender DRM:
- Detection bonus (first round): +4 Ambush or +3 Surprise (if applicable)
- Fighter Superiority: +0, +1, or +2 (if advantage)
- **Starbase Sensors: +1 (if at least one starbase undamaged)** ← Key difference
- Morale: ±1 or ±2
- ELI Advantage: +1 (if your ELI > enemy ELI)
- Homeworld: +1 (if defending house homeworld)

**Starbase AS/DS Contribution:**

Defender total AS includes starbase AS (direct combat participation).
Defender total DS includes starbase DS (targets for attacker hits).

### 7.6.5 Victory Conditions

**Attacker Victory:**
- All orbital defenders destroyed or retreated
- Attackers achieve orbital supremacy
- **Result**: Proceed to planetary bombardment/invasion phase

**Defender Victory:**
- All attackers destroyed or retreated
- Orbital defenses hold
- **Result**: Colony remains secure, invasion repelled

**Screened Unit Loss:**
- If attackers win, all screened units destroyed: mothballed ships, auxiliary vessels (ETACS, Troop Transports), and facilities (shipyards, drydocks, spaceports)
- Significant economic and strategic loss (especially facilities)
- Defenders should activate mothballed fleets and evacuate auxiliary vessels before combat if threatened

---

## 7.7 Planetary Bombardment

Destroy enemy infrastructure and defenses from orbit after achieving orbital supremacy. Your fleets systematically dismantle planetary shields, neutralize ground batteries, and reduce industrial capacity.

### 7.7.1 Bombardment Requirements

**Prerequisites:**
- Orbital supremacy achieved (won orbital combat)
- Combat-capable ships present (AS > 0)
- Bombard command issued to fleet

**Note:** Starbases have already been destroyed in orbital combat. They do not participate in bombardment phase.

### 7.7.2 Bombardment Participants

**Attacker:**
- All surviving fleet ships with bombardment capability (all combat ships)
- Planet-Breaker ships (if present) provide +4 DRM and bypass shields

**Defender:**
- Ground Batteries (fire back at orbiting ships)
- Planetary Shields (reduce incoming damage)
- Infrastructure (damaged by excess hits)

### 7.7.3 Bombardment Resolution

**Step 1: Calculate Attack Strength**

Attacker AS = Fleet total bombardment AS (all combat ships)
Defender AS = Ground Batteries total AS

**Step 2: Calculate Die Roll Modifiers**

Attacker DRM:
- **Planet-Breaker: +4 (if Planet-Breaker ships present)** ← Late-game stalemate breaker
- Morale: ±1 or ±2

Defender DRM:
- Morale: ±1 or ±2

**No starbase bonuses** (already destroyed in orbital combat).
**No air superiority bonuses** (not applicable to bombardment).

**Step 3: Roll CER**

Both sides: 1d10 + DRM → Space/Orbital Combat CRT

Note: Bombardment uses Space/Orbital CRT (not Ground Combat CRT). Maximum 1.0× CER.

**Step 4: Calculate Base Hits**

Attacker base hits = Fleet AS × Attacker CER (round up)
Defender base hits = Battery AS × Defender CER (round up)

**Step 5: Apply Shield Reduction (Attacker Hits Only)**

Planetary shields reduce bombardment damage before hits applied:

**Shield Reduction Table:**
| Shield Level | Damage Reduction |
|--------------|------------------|
| SLD 1        | 25%              |
| SLD 2        | 30%              |
| SLD 3        | 35%              |
| SLD 4        | 40%              |
| SLD 5        | 45%              |
| SLD 6        | 50%              |

**Planet-Breaker ships bypass shields entirely:**

If Planet-Breaker ships present:
```
Planet-Breaker hits = Planet-Breaker AS × CER (NO reduction)
Regular fleet hits = (Fleet AS - Planet-Breaker AS) × CER × (1 - Shield %)
Total attacker hits = Planet-Breaker hits + Reduced fleet hits
```

If no Planet-Breaker ships:
```
Total attacker hits = Fleet AS × CER × (1 - Shield %)
```

Example:
```
Attacker: 200 AS fleet (40 AS Planet-Breaker, 160 AS regular)
CER: 1.0×
Base hits: 200 × 1.0 = 200

Shield: SLD 6 (50% reduction)

Planet-Breaker: 40 × 1.0 = 40 hits (bypass shield)
Regular: 160 × 1.0 × 0.5 = 80 hits (reduced by shield)
Total: 120 hits penetrate shield

Without Planet-Breaker: 200 × 0.5 = 100 hits (all reduced)
Planet-Breaker advantage: +20 hits
```

**Step 6: Apply Hits (Simultaneous)**

Attacker hits → Ground Batteries (cripple/destroy), then Infrastructure
Defender hits → Fleet ships (cripple/destroy)

**Hit Flow:**
1. Apply hits to Ground Batteries first (following hit application rules)
2. Excess hits (after all batteries destroyed) cascade through three phases:
   - **Phase 1**: Damage spaceports (large planetary facilities, visible and targetable from orbit)
   - **Phase 2**: Damage ground forces (dispersed armies/marines, mobile and harder to target)
   - **Phase 3**: Remaining hits split 50/50 between infrastructure and population (collateral damage)
3. See Section 7.7.6 for detailed excess hit distribution mechanics

**Step 7: Check Retreat (Attacker Only)**

Attacker fleets check ROE:
- If taking heavy casualties from battery fire, may retreat
- Bombardment abandoned if attacker retreats
- Defender cannot retreat (batteries are fixed installations)

**Repeat Rounds:**

Continue bombardment rounds until:
- All ground batteries destroyed (bombardment successful)
- Attacker retreats (ROE triggered by heavy losses)
- Maximum 20 rounds (rare—usually batteries destroyed or attacker retreats)

### 7.7.4 Planetary Shields

Shields reduce bombardment damage from conventional ships. Higher shield levels block larger percentages of incoming hits.

**Shield Mechanics:**
- Shields are ALWAYS active (no activation roll)
- Reduce damage every bombardment round consistently
- Planet-Breaker hits bypass shields entirely (no reduction)
- Shields do NOT degrade or get destroyed by bombardment
- Shields ARE destroyed when Marines land during invasion (represents marines seizing shield generators on surface)

**Strategic Implications:**

High-level shields (SLD 5-6) make conventional bombardment extremely inefficient. Fleets without Planet-Breaker ships may bombard for many rounds with minimal effect, taking heavy casualties from battery return fire.

Planet-Breaker ships are late-game stalemate breakers—expensive but essential for cracking fortress worlds with high shields and multiple batteries.

### 7.7.5 Ground Batteries

Ground-based defensive installations fire on orbiting ships. Batteries threaten bombarding fleets with sustained return fire.

**Ground Battery Mechanics:**
- Each battery has attack strength (AS) and defense strength (DS)
- Targets orbiting ships using standard hit application rules
- Can cripple or destroy bombarding vessels
- Battery fire continues until batteries destroyed
- Multiple batteries = sustained defensive fire

**Neutralizing Batteries:**
- Bombardment hits damage batteries first (before infrastructure)
- Follow standard hit application rules (must cripple all before destroying any)
- Each battery can be crippled (50% AS) then destroyed
- All batteries must be destroyed before standard invasion can proceed

**Strategic Considerations:**
- High battery count = dangerous bombardment (heavy attacker casualties)
- Weak bombarding fleet risks losses to battery fire
- Alternative: Starve colony via blockade instead of bombardment (avoids casualties)

### 7.7.6 Infrastructure Damage

Excess bombardment hits (after all batteries destroyed) cascade through three targeting phases before causing general infrastructure damage:

**Phase 1: Spaceport Destruction**

Large planetary spaceport facilities are visible and targetable from orbit:
- Each spaceport has Defense Strength (DS) based on facility class
- Bombardment follows standard damage model:
  - Undamaged → Crippled (requires DS hits)
  - Crippled → Destroyed (requires 50% DS hits)
- Spaceports are hardened targets requiring sustained bombardment
- Hits consumed destroying spaceports do not carry over to next phase

**Phase 2: Ground Force Attrition**

Remaining hits target dispersed ground forces (armies and marines stationed at colony):
- Ground forces are mobile and dispersed, harder to target precisely from orbit
- Bombardment follows standard damage model:
  - Undamaged → Crippled (requires unit DS hits)
  - Crippled → Destroyed (requires 50% unit DS hits)
- Must cripple all undamaged units before destroying crippled units
- Weakens garrison before invasion attempts

**Phase 3: Infrastructure and Population**

Remaining hits represent indiscriminate bombardment causing collateral damage:
- Hits split **50/50** between infrastructure and population
- **Infrastructure damage**: Each hit destroys 1 IU (Infrastructure Unit)
  - Permanent production capacity loss (until repaired)
  - Reduces colony GDP proportionally
- **Population casualties**: Each hit kills 1 PTU (50,000 souls per config)
  - Permanent population loss
  - Defender prestige penalties

**Targeting Priority Rationale:**

1. **Spaceports first**: Large, fixed facilities visible from orbit, strategic military targets
2. **Ground forces second**: Mobile units harder to target, require area bombardment
3. **Infrastructure/population last**: Collateral damage from indiscriminate fire

**Damage Accumulation:**

Infrastructure damage is permanent (until repaired):
- 10 IU destroyed = 10 IU loss from colony total
- Reduces production capacity proportionally
- Captured colonies often require extensive rebuilding (PP investment)

**Repair Costs:**

Damaged infrastructure requires PP investment to repair:
- Cost: 25% of original build cost per IU
- Repair time: Immediate (once PP spent)
- Captured colonies often devastated (50% IU destroyed from invasion + bombardment damage)

---

## 7.8 Planetary Invasion

Seize enemy colonies by landing ground forces after achieving orbital supremacy. Your marines fight defending ground forces for control of the planet surface.

### 7.8.1 Standard Invasion

Land ground forces to conquer enemy colonies. Invasion requires orbital supremacy, cleared ground defenses, and loaded troop transports.

**Invasion Requirements:**
- Orbital supremacy achieved (won orbital combat)
- **ALL ground batteries destroyed** (mandatory—batteries fire on landing transports)
- Troop Transports with loaded Marines (MD = Marine Division)
- Invade command issued to fleet

**Invasion Process:**

**Step 1: Marines Land**
- Transports unload marines (troops committed to battle)
- **Shields and spaceports immediately destroyed** upon marine landing (marines seize shield generators on surface)

**Step 2: Calculate Attack Strength**

Attacker AS = Marines total AS (all Marine Divisions)
Defender AS = Ground Forces total AS (Armies + colonial Marines)

**Step 3: Calculate Die Roll Modifiers**

Attacker DRM:
- Morale: ±1 or ±2

Defender DRM:
- **Prepared Defenses: +2 (entrenched colony defenders)**
- Homeworld: +1 (if defending house homeworld)
- Morale: ±1 or ±2

Total defender advantage: Typically +2 to +3 DRM

**No air superiority bonus** (already achieved by winning orbital combat—prerequisite for invasion).

**Step 4: Roll CER**

Both sides: 1d10 + DRM → Ground Combat CRT

Ground Combat CRT (higher effectiveness):
| Modified Roll | CER  |
|---------------|------|
| ≤2            | 0.5× |
| 3-6           | 1.0× |
| 7-8           | 1.5× |
| 9+            | 2.0× |

**Step 5: Calculate Hits**

Attacker hits = Marine AS × Attacker CER (round up)
Defender hits = Ground Forces AS × Defender CER (round up)

**Step 6: Apply Hits (SIMULTANEOUS)**

Both sides apply hits to ground units:
- Must cripple all before destroying any
- Critical Hits (natural 9) bypass this rule
- Ground combat is brutal—high casualty rates on both sides

**Step 7: Repeat Rounds**

Continue ground combat rounds until:
- One side eliminated (winner captures/holds colony)
- Maximum 20 rounds (rare—ground combat usually decisive within few rounds)

**Outcome:**

**If Attackers Win:**
- Colony captured, ownership transfers to attacker
- **50% of remaining IU destroyed** by loyal citizens before order restored (sabotage)
- Surviving attacker marines garrison colony

**If Defenders Win:**
- Invasion repelled
- All attacker marines destroyed
- Colony remains under defender control

### 7.8.2 Planetary Blitz

Conduct rapid combined bombardment + invasion operations. Blitz sacrifices safety for speed—marines land under fire from ground batteries.

**Blitz Requirements:**
- Orbital supremacy achieved
- Loaded Troop Transports present
- Blitz command issued to fleet
- **No requirement for batteries destroyed**—blitz works against any defenses (risky!)

**Blitz Mechanics:**

**Phase 1: Bombardment Round (Transports Vulnerable)**

Conduct ONE round of bombardment:
- Fleet bombards batteries/shields
- **Ground batteries fire at ALL fleet ships** (including Troop Transports!)
- Transports can be destroyed before landing marines (mission fails)
- Shields reduce bombardment damage normally
- No infrastructure targeted (avoid damaging assets to be captured)

**Phase 2: Landing Phase (If Transports Survive)**

Marines land immediately (don't wait for batteries eliminated):
- Marines commit to ground combat
- **Shields, spaceports, batteries seized intact** if invasion successful
- Batteries do NOT fire during ground combat (marines are on surface, not in orbit)

**Phase 3: Ground Combat**

**Step 1: Calculate Attack Strength**

Attacker AS = Marines total AS
Defender AS = Ground Forces AS

**Note:** Batteries do not participate directly in ground combat resolution (their effect is captured by the "Landing Under Fire" DRM).

**Step 2: Calculate Die Roll Modifiers**

Attacker DRM:
- Morale: ±1 or ±2

Defender DRM:
- **Landing Under Fire: +3 (marines landing under battery fire, even more advantageous than prepared defenses)**
- Homeworld: +1 (if defending house homeworld)
- Morale: ±1 or ±2

Total defender advantage: Typically +3 to +4 DRM (very dangerous for attacker)

**Step 3: Roll CER**

Both sides: 1d10 + DRM → Ground Combat CRT (same as standard invasion)

**Step 4: Apply Hits and Resolve**

Same as standard invasion, but defender has significant advantage (+3 DRM instead of +2).

**Outcome:**

**If Attackers Win:**
- Colony captured, ownership transfers
- **0% IU destroyed** (all assets seized intact!) ← Key Blitz advantage
- Shields, batteries, spaceports captured functional

**If Defenders Win:**
- Invasion repelled
- All attacker marines destroyed
- Colony remains under defender control

### 7.8.3 Invasion Strategy Comparison

**Standard Invasion:**

**Advantages:**
- Safer (batteries destroyed before landing)
- Lower marine casualties (defender +2 DRM instead of +3)
- More predictable outcome

**Disadvantages:**
- Slower (requires bombardment rounds first)
- Infrastructure damaged (50% IU destroyed on capture)
- Shields/spaceports destroyed (must rebuild)

**Blitz Operation:**

**Advantages:**
- Faster (one bombardment round, immediate invasion)
- Infrastructure intact (0% IU destroyed on capture!)
- Shields/batteries/spaceports captured functional
- Speed captures territory before rivals

**Disadvantages:**
- Riskier (transports vulnerable in bombardment phase)
- Higher marine casualties (defender +3 DRM)
- Dangerous against heavily defended colonies (high shields, many batteries, large garrison)

**When to Use Each:**

Standard Invasion:
- Heavily fortified colonies (high shields, many batteries)
- When you have time (no rival rushing same target)
- When you want to minimize military losses
- When infrastructure damage acceptable

Blitz:
- Weak frontier colonies (low shields, few batteries, small garrison)
- Land grab races (beat rivals to capture)
- High-value infrastructure (want to capture intact)
- Accept higher casualties for strategic speed

---

## 7.9 Multi-House Combat

When three or more houses have fleets in the same system, complex multi-faction battles can occur. Combat resolves based on diplomatic status and force allocation.

### 7.9.1 Diplomatic Status and Hostility

Combat only occurs between houses following the diplomatic escalation ladder with grace period timing. For complete rules, see [Section 8.1 Diplomacy](08-diplomacy.md#81-diplomacy).

**Key Combat Triggers:**

**Enemy Status:**
- Combat occurs during travel (fleets engage when they meet in any system)
- Combat occurs at destination (regardless of mission type)
- Full warfare posture

**Hostile Status:**
- No combat during travel (safe passage even through hostile territory)
- Combat at destination if Tier 2 mission present (Patrol, Hold, Rendezvous in their system)
- Tier 1 mission at their colony escalates to Enemy with immediate combat

**Neutral Status:**
- No combat during travel (safe passage)
- Tier 2 mission in their territory: Escalate to Hostile with **grace period** (no combat Turn X, combat Turn X+1 if continues)
- Tier 1 mission at their colony: Escalate to Enemy with **immediate combat** (no grace period)

**Mission Threat Tiers** (from Section 8.1.5):

**Tier 1 - Direct Colony Attacks** (Enemy escalation, immediate combat):
- Blockade (Command 06), Bombard (Command 07), Invade (Command 08), Blitz (Command 09)

**Tier 2 - System Control Contestation** (Hostile escalation, grace period):
- Patrol a System (Command 03), Hold Position (Command 00), Rendezvous (Command 15)

**Grace Period Logic:**
- Turn X: Neutral + Tier 2 mission → Escalate to Hostile, no combat (warning)
- Turn X+1: Hostile + Tier 2 mission → Combat occurs (warning ignored)
- This gives players one turn to correct mistakes (cancel orders, retreat, adjust diplomacy)

### 7.9.2 Multi-Faction Battle Resolution

When 3+ houses have hostile relationships in same system:

**Step 1: Identify Hostile Pairs**

Determine which houses fight which:
```
Example:
  House A: Enemy with House B, Neutral with House C
  House B: Enemy with House A, Hostile (provocative) with House C
  House C: Neutral with House A, Hostile with House B

Result: Two separate battles
  Battle 1: A vs B
  Battle 2: B vs C (House B fights on two fronts!)
```

**Step 2: Allocate Forces**

Houses fighting multiple enemies must divide forces:

**Proportional Allocation (Automatic):**

House allocates AS proportionally based on enemy strength:
```
House H: 100 AS total
  Faces: House A (80 AS) and House C (40 AS)
  Total enemy AS: 120

Allocation:
  vs A: 100 × (80/120) = 67 AS
  vs C: 100 × (40/120) = 33 AS
```

Each fleet commits to one battle based on proportional needs. Fleets remain organizationally distinct (check own ROE independently).

**Step 3: Resolve Battles Independently**

Each hostile pair resolves combat simultaneously but independently:
- Battle 1: A (80 AS) vs H (67 AS)
- Battle 2: C (40 AS) vs H (33 AS)

House H takes casualties from BOTH battles (same ships can only fight in one battle).

**Step 4: Apply Casualties and Determine Winners**

Each battle determines winner independently:
- Battle 1 winner advances to orbital (if attacking) or repels (if defending)
- Battle 2 winner advances or repels independently
- House fighting multiple battles may win one and lose another

### 7.9.3 Retreat Priority in Multi-House Battles

When 3+ houses attempt to retreat simultaneously from same battle:

**Retreat Order:**
1. Weakest retreats first (lowest total AS)
2. Ties broken by house ID (alphanumeric)
3. After each retreat, remaining houses re-check ROE against new enemy strength
4. Re-evaluation may cause house to cancel retreat and continue fighting
5. Continue until one retreats or all commit to fighting

Example:
```
Round 3 ends:
  House A: 50 AS, ROE 6 (threshold 1.0)
  House B: 60 AS, ROE 6 (threshold 1.0)
  House C: 100 AS, ROE 6 (threshold 1.0)

House A checks: 50 / (60+100) = 0.31 < 1.0 → Retreat!
House A (weakest) retreats first.

Remaining:
  House B: 60 AS
  House C: 100 AS

House B checks: 60 / 100 = 0.6 < 1.0 → Retreat!
House B retreats.

House C wins by attrition.
```

---

## 7.10 Combat Example

**Scenario**: House Valerian (CLK 3, ELI 2) raids House Stratos mining colony defended by a starbase.

**Space Combat**: Valerian Raiders (45 AS) + Destroyers (40 AS) vs Stratos Cruisers (60 AS). Detection: Valerian wins by 4 → Surprise (+3 DRM). Valerian DRM +4, Stratos DRM +1 (starbase sensors). Both roll CER 1.0× and 0.5×. Valerian inflicts 85 hits (cripples both cruisers), Stratos inflicts 30 hits (cripples 2 raiders). Stratos retreats (0.39:1 ratio below ROE 6 threshold).

**Orbital Combat**: Valerian engages Stratos starbases (AS 80, DS 100) + guard cruisers. Starbase provides +1 DRM. Critical hit from defender destroys multiple Valerian destroyers despite undamaged ships present. Valerian wins at heavy cost, proceeds to bombardment.

**Bombardment**: Valerian fleet (150 AS) vs ground batteries (60 AS) + SLD 5 shields (45% reduction). Shields reduce 150 hits to 83 effective hits. Two rounds required to destroy batteries. Excess 29 hits damage infrastructure.

**Invasion**: Marines (40 AS) land. Defender gets +2 Prepared Defenses DRM. Ground Combat CRT produces 1.5× and 1.0× CER. Marines eliminate ground forces with minimal casualties. Colony captured with 50% IU destroyed (invasion penalty).

---

**End of Section 7: Combat**