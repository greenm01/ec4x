# 8.0 Diplomacy

## 8.1 Diplomacy

In EC4X, diplomacy consists of a three-state system: Neutral, Hostile, and Enemy. As House Archon, your mandate is to lead your House to victory by strategic means, where diplomacy plays a pivotal role alongside the sword. Your primary directive remains decisively managing your adversaries, leveraging both military might and diplomatic cunning.

### 8.1.1 Diplomatic States

| State       | Description                         | Default Relations                      |
|-------------|-------------------------------------|----------------------------------------|
| **Neutral** | Default state, safe passage allowed | All houses start Neutral to each other |
| **Hostile** | Tense relations, limited engagement | First warning after provocation        |
| **Enemy**   | Active warfare, combat on sight     | Declared war state                     |

### 8.1.2 Neutral

Your fleets are instructed to avoid initiating hostilities with the designated neutral House outside of your controlled territory. This status allows for coexistence in neutral or contested spaces without immediate aggression.

**During Travel:**
- Neutral fleets do NOT engage each other while traveling through systems
- Safe passage through neutral and uncontrolled space

**At Mission Destination:**
- Non-threatening missions in neutral space: No escalation
- Non-threatening missions in their territory: No escalation
- Threatening missions in their territory: Escalate to **Hostile**
- Threatening missions at their colony: Escalate to **Enemy**

### 8.1.3 Hostile

Tense relations where combat occurs only under specific conditions. Houses with Hostile diplomatic status maintain guarded interactions.

**During Travel:**
- Hostile fleets do NOT engage each other while traveling through systems
- Safe passage even through enemy-controlled territory during transit

**At Mission Destination:**
- Non-threatening missions: No combat
- Threatening missions in their territory: Combat occurs
- Threatening missions at their colony: Escalate to **Enemy**

**Escalation Triggers:**
- Neutral → Hostile: Threatening mission in their controlled territory
- Hostile → Enemy: Threatening mission at their colony

### 8.1.4 Enemy

Your fleets are commanded to engage with the forces of the declared enemy House at every opportunity, both within and outside controlled territories. This state leads to full-scale warfare where all encounters are treated as hostile, pushing for direct and aggressive confrontations.

**During Travel:**
- Enemy fleets engage on sight
- Combat occurs when fleets encounter each other in any system

**At Mission Destination:**
- Combat always occurs regardless of mission type
- Full warfare posture

**Escalation Triggers:**
- Neutral → Enemy: Threatening mission at their colony
- Hostile → Enemy: Threatening mission at their colony

### 8.1.5 Threatening vs Non-Threatening Missions

Fleet commands are only threatening when the **fleet's mission target is this system** and the **system is owned by another house**. Fleets traveling through systems to reach their destination are not threatening during transit.

**Command Threat Classification Table:**

| Command # | Mission | Threat Level | Escalation Effect | Notes |
|-----------|---------|--------------|-------------------|-------|
| 06 | Blockade | **Attack** | Enemy, immediate combat | Orbital control (blocks colonization or disrupts economy) |
| 07 | Bombard | **Attack** | Enemy, immediate combat | Orbital bombardment targeting colony |
| 08 | Invade | **Attack** | Enemy, immediate combat | Ground invasion targeting colony |
| 09 | Blitz | **Attack** | Enemy, immediate combat | Combined assault targeting colony |
| 03 | Patrol | **Contest** | Hostile, grace period | Active patrol of their controlled system |
| 00 | Hold | **Contest** | Hostile, grace period | Sustained military presence in their system |
| 15 | Rendezvous | **Contest** | Hostile, grace period | Assembling forces in their system |
| 01 | Move | Benign | No escalation | Strategic repositioning or traveling through |
| 02 | Seek Home | Benign | No escalation | Return to base (retreating) |
| 04 | Guard Starbase | Benign | No escalation | Only valid for your own starbases |
| 05 | Guard Colony | Benign | No escalation | Only valid for your own colonies |
| 10 | Colonize | Benign | No escalation | Only valid in neutral space |
| 11 | Scout Colony | Benign | No escalation | If undetected (mission fails if detected) |
| 12 | Scout System | Benign | No escalation | If undetected (mission fails if detected) |
| 13 | Hack Starbase | Benign | No escalation | If undetected (mission fails if detected) |
| 14 | Join Fleet | Benign | No escalation | Force consolidation |
| 16 | Salvage | Benign | No escalation | Only valid in friendly space |
| 17 | Reserve | Benign | No escalation | Administrative action |
| 18 | Mothball | Benign | No escalation | Administrative action |
| 19 | Reactivate | Benign | No escalation | Administrative action |
| 20 | View | Benign | No escalation | Passive reconnaissance |

**Threat Level Effects:**

- **Attack**: Direct colony attacks escalate to Enemy status with immediate combat (no grace period)
- **Contest**: System control contestation escalates to Hostile with grace period (combat Turn X+1 if continues)
- **Benign**: Non-threatening missions cause no escalation or combat

### 8.1.6 Escalation Ladder Summary

**Phase 1: Travel (Moving Through Systems)**

| Diplomatic Status | Combat During Travel? |
|-------------------|----------------------|
| Neutral           | No                   |
| Hostile           | No                   |
| Enemy             | Yes (always)         |

**Phase 2: Mission Execution (At Destination)**

**Turn X (Threatening Mission Arrives):**

| Current Status | Tier 1 (Colony Attack) | Tier 2 (System Contestation) | Tier 3 (Non-Threatening) |
|----------------|------------------------|------------------------------|--------------------------|
| Neutral        | Escalate to Enemy, immediate combat | Escalate to Hostile, NO combat (grace period) | No change, no combat |
| Hostile        | Escalate to Enemy, immediate combat | No escalation, NO combat yet | No combat |
| Enemy          | Immediate combat | Immediate combat | Immediate combat |

**Turn X+1 (Mission Continues):**

| Current Status | Tier 1 (Colony Attack) | Tier 2 (System Contestation) | Tier 3 (Non-Threatening) |
|----------------|------------------------|------------------------------|--------------------------|
| Neutral        | N/A (escalated to Enemy) | N/A (escalated to Hostile) | No combat |
| Hostile        | N/A (escalated to Enemy) | Combat occurs (warning ignored) | No combat |
| Enemy          | Combat | Combat | Combat |

**Key Principles:**
- **Direct colony attacks** (Tier 1) are acts of war → Immediate Enemy escalation + combat
- **System contestation** (Tier 2) gets grace period → Hostile escalation on Turn X, combat on Turn X+1 if not corrected
- **Space combat doesn't escalate to Enemy** → Fighting over system control (Patrol, Hold) remains Hostile
- **Only colony attacks escalate to Enemy** → Blockade, Bombard, Invade, Blitz at colony
- **Grace period allows corrections** → Players can cancel orders, retreat, or adjust diplomacy before combat

### 8.1.7 Defense Protocol

Regardless of diplomatic status, all your units will defend your House colonies against any foreign incursions with maximum aggression. Your fleets will retaliate against direct colony attacks regardless of diplomatic state, in accordance with ROE.

**Defensive Posture:**
- Guard commands (GuardStarbase, GuardColony) are non-threatening
- Fleets responding to attacks on your colonies escalate diplomatic status

### 8.1.8 Territorial Control

Your house controls territory in systems containing your colony. Each system can contain only one colony per the colonization rules in [Section 6.3.12](06-operations.md#6312-colonize-a-planet-10).

**Territory Classifications:**

- **Controlled Territory**: Systems containing your house's colony
- **Foreign Territory**: Systems containing another house's colony
- **Neutral Space**: Systems without any colonies

**Diplomatic Application:**

Neutral diplomatic status (Section 8.1.2) governs behavior outside your controlled territory. Within your controlled territory, you may engage neutral forces per Defense Protocol (Section 8.1.7). Enemy status (Section 8.1.4) applies in all territories regardless of location.

