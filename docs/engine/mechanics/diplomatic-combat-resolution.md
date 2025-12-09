# Diplomatic Status and Combat Resolution

**Last Updated:** 2025-12-09
**Status:** Specification (Implementation Required)

---

## Overview

This document specifies how diplomatic status between houses determines combat engagement, escalation, and multi-faction combat resolution. The system uses a three-state escalation ladder with bidirectional movement to allow strategic flexibility while maintaining consequences for aggressive actions.

---

## 1. Three-State Diplomatic System

### 1.1 Diplomatic States

| State       | Description                         | Default Relations                      |
|-------------|-------------------------------------|----------------------------------------|
| **Neutral** | Default state, safe passage allowed | All houses start Neutral to each other |
| **Hostile** | Tense relations, limited engagement | First warning after provocation        |
| **Enemy**   | Active warfare, combat on sight     | Declared war state                     |

### 1.2 Design Philosophy

- **Neutral**: Peaceful coexistence, transit allowed
- **Hostile**: Warning state after provocation, allows de-escalation
- **Enemy**: Total war, but can negotiate cease-fire
- **No Ally State**: Zero-sum conquest game, temporary cooperation via Neutral status only

---

## 2. Escalation Ladder

### 2.1 Automatic Escalation (Triggered by Actions)

```
Neutral → Hostile → Enemy
```

#### 2.1.1 Neutral → Hostile

**Triggers:**
- Fleet stops in defender's system with non-threatening but provocative orders
- First offense only (warning)

**Examples:**
- Hold (00) - Loitering in defender's space
- Patrol (03) - Patrolling defender's system
- SpyPlanet (11) - Espionage against defender
- ViewWorld (20) - Reconnaissance in defender's system

**Does NOT Trigger:**
- Move (01) order if just passing through (transit to another system)
- No fleet presence in defender's system

#### 2.1.2 Hostile → Enemy

**Triggers:**
- **Second offense**: Fleet operates in defender's system again while already Hostile
- **Threatening orders**: Any of the following orders in defender's system:
  - BlockadePlanet (06)
  - Bombard (07)
  - Invade (08)
  - Blitz (09)
  - HackStarbase (13)
  - BlockadeTarget (SO)

**Note:** Threatening orders escalate directly to Enemy even from Neutral if first offense against a controlled system.

### 2.2 Negotiated De-escalation (Requires Agreement)

```
Enemy ⟷ Hostile ⟷ Neutral
```

#### 2.2.1 De-escalation Requirements

**To De-escalate One Level:**
1. One house offers de-escalation
2. Other house accepts offer
3. No combat between houses for past 3 turns
4. Optional: Prestige/resource cost to initiate

**Rejection:**
- Offer can be rejected
- Status remains unchanged
- 3-turn cooldown before can offer again

#### 2.2.2 De-escalation Use Cases

**Strategic Reasons:**
- Allow neutral house transit through your space to attack common enemy
- Temporary truce to focus on greater threat
- Recovery from accidental provocation (misclick, navigation error)
- Multi-front warfare coordination without formal alliance

**"Mistakes Happen":**
- Accidental fleet movement into wrong system
- Miscommunication or misunderstanding
- Strategic repositioning that wasn't meant as aggression

---

## 3. Fleet Order Threat Classification

### 3.1 Threatening Orders (Immediate Enemy Status)

These orders immediately escalate to **Enemy** status when executed in defender's controlled system:

| Order Code        | Order Name                 | Combat Phases                    |
|-------------------|----------------------------|----------------------------------|
| 06                | BlockadePlanet             | Space → Orbital                  |
| 07                | Bombard                    | Space → Orbital → Planetary      |
| 08                | Invade                     | Space → Orbital → Planetary      |
| 09                | Blitz                      | Space → Orbital → Planetary      |
| 13                | HackStarbase               | Space → Orbital                  |
| SO-BlockadeTarget | Blockade Target (Standing) | Space → Orbital                  |

### 3.2 Non-Threatening but Provocative Orders (Gradual Escalation)

These orders escalate Neutral→Hostile on first offense, Hostile→Enemy on second offense when executed in defender's controlled system:

| Order Code     | Order Name   | Can Target Defender? | Notes                                           |
|----------------|--------------|----------------------|-------------------------------------------------|
| 00             | Hold         | YES                  | Loitering in defender's space                   |
| 03             | Patrol       | YES                  | Active patrol in defender's system              |
| 11             | SpyPlanet    | YES                  | Espionage against defender's colony             |
| 12             | SpySystem    | YES                  | Intel gathering in defender's system            |
| 14             | JoinFleet    | MAYBE                | Only if consolidating in defender's space       |
| 15             | Rendezvous   | MAYBE                | Only if meeting in defender's space             |
| 16             | Salvage      | YES                  | Salvaging wreckage in defender's system         |
| 20             | ViewWorld    | YES                  | Observation/reconnaissance                      |
| SO-PatrolRoute | Patrol Route | YES                  | Persistent patrol through defender's space      |

### 3.3 Safe Transit

| Order Code | Order Name | Condition     | Notes                                          |
|------------|------------|---------------|------------------------------------------------|
| 01         | Move       | Transit only  | Safe if passing through to another destination |
| 01         | Move       | Stopping      | Does NOT escalate if destination IS defender's system and no provocative orders |

### 3.4 Orders That Cannot Target Defender's System (No Escalation Risk)

These orders physically cannot be executed at another house's facilities or systems:

| Order Code       | Order Name     | Reason                              |
|------------------|----------------|-------------------------------------|
| 02               | SeekHome       | Returns to own homeworld only       |
| 04               | GuardStarbase  | Can only guard own starbases        |
| 05               | GuardPlanet    | Can only guard own planets          |
| 10               | Colonize       | Can only colonize unowned systems   |
| 17               | Reserve        | Can only reserve at own colonies    |
| 18               | Mothball       | Can only mothball at own colonies   |
| 19               | Reactivate     | Can only reactivate at own colonies |
| SO-DefendSystem  | Defend System  | Can only defend own systems         |
| SO-AutoColonize  | Auto Colonize  | Only colonizes unowned systems      |
| SO-AutoReinforce | Auto Reinforce | Only reinforces own colonies        |
| SO-AutoRepair    | Auto Repair    | Only seeks repair at own facilities |
| SO-GuardColony   | Guard Colony   | Only guards own colonies            |

---

## 4. Combat Phase Participation Matrix

### 4.1 Complete Order Combat Matrix

| Order Code        | Order Name      | Space Combat?            | Orbital Combat?        | Planetary Combat?    | Notes                                    |
|-------------------|-----------------|--------------------------|------------------------|----------------------|------------------------------------------|
| 00                | Hold            | YES (if hostile present) | NO                     | NO                   | Idle fleet fights in space combat        |
| 01                | Move            | YES (if hostile present) | NO                     | NO                   | Transit fleet vulnerable to interception |
| 02                | SeekHome        | YES (if hostile present) | NO                     | NO                   | Returning fleet vulnerable               |
| 03                | Patrol          | YES (if hostile present) | NO                     | NO                   | Patrol fleet participates                |
| 04                | GuardStarbase   | NO                       | YES (defender)         | NO                   | Guard fleet, orbital defense only        |
| 05                | GuardPlanet     | NO                       | YES (defender)         | NO                   | Guard fleet, orbital defense only        |
| 06                | BlockadePlanet  | YES (if mobile defs)     | YES (attacker)         | NO                   | Economic warfare                         |
| 07                | Bombard         | YES (if mobile defs)     | YES (attacker)         | YES (if win orbital) | Orbital bombardment                      |
| 08                | Invade          | YES (if mobile defs)     | YES (attacker)         | YES (if win orbital) | Ground assault                           |
| 09                | Blitz           | YES (if mobile defs)     | YES (attacker)         | YES (if win orbital) | Combined attack                          |
| 10                | Colonize        | YES (if hostile present) | NO                     | NO                   | Peaceful mission but vulnerable          |
| 11                | SpyPlanet       | YES (if hostile present) | NO                     | NO                   | Espionage vulnerable to interception     |
| 12                | SpySystem       | YES (if hostile present) | NO                     | NO                   | Intel gathering vulnerable               |
| 13                | HackStarbase    | YES (if mobile defs)     | YES (attacker)         | NO                   | Cyberattack on defenses                  |
| 14                | JoinFleet       | YES (if hostile present) | NO                     | NO                   | Fleet consolidation vulnerable           |
| 15                | Rendezvous      | YES (if hostile present) | NO                     | NO                   | Fleet meeting vulnerable                 |
| 16                | Salvage         | YES (if hostile present) | NO                     | NO                   | Salvage operation vulnerable             |
| 17                | Reserve         | NO                       | YES (defender at 50%)  | NO                   | Reserved fleet, reduced effectiveness    |
| 18                | Mothball        | NO                       | NO (SCREENED)          | NO                   | Offline, protected by defenders          |
| 19                | Reactivate      | YES (if hostile present) | NO                     | NO                   | Reactivating, vulnerable during process  |
| 20                | ViewWorld       | YES (if hostile present) | NO                     | NO                   | Observation vulnerable                   |
| SO-PatrolRoute    | Patrol Route    | YES (if hostile present) | NO                     | NO                   | Persistent patrol participates           |
| SO-DefendSystem   | Defend System   | NO                       | YES (defender)         | NO                   | System defense, orbital only             |
| SO-AutoColonize   | Auto Colonize   | YES (if hostile present) | NO                     | NO                   | Colonization vulnerable                  |
| SO-AutoReinforce  | Auto Reinforce  | YES (if hostile present) | NO                     | NO                   | Reinforcement vulnerable                 |
| SO-AutoRepair     | Auto Repair     | YES (if hostile present) | NO                     | NO                   | Repair-seeking vulnerable                |
| SO-AutoEvade      | Auto Evade      | NO (fleeing)             | NO                     | NO                   | Actively avoiding combat                 |
| SO-GuardColony    | Guard Colony    | NO                       | YES (defender)         | NO                   | Colony guard, orbital defense            |
| SO-BlockadeTarget | Blockade Target | YES (if mobile defs)     | YES (attacker)         | NO                   | Persistent blockade                      |

### 4.2 Defender Assets (Not Fleet Orders)

| Asset Type           | Space Combat? | Orbital Combat? | Planetary Combat? | Notes                                        |
|----------------------|---------------|-----------------|-------------------|----------------------------------------------|
| Starbase             | NO            | YES (defender)  | NO                | Fixed orbital defense installation           |
| Unassigned Squadrons | NO            | YES (defender)  | NO                | Combat squadrons at colony not in fleets     |
| Colony Fighters      | NO            | YES (defender)  | NO                | Fighters launched from colony defenses       |
| Spacelift Ships      | NO            | NO (SCREENED)   | NO                | No combat capability, protected by defenders |

### 4.3 Combat Flow Sequence

**1. Space Combat** (First Theater)
- **Participants**: Mobile fleets (all non-guard orders)
- **Condition**: If hostile diplomatic status exists between houses
- **Outcome**: Winner proceeds to orbital combat

**2. Orbital Combat** (Second Theater)
- **Attackers**: Surviving fleets from space combat (if won) OR fleets that bypassed space (no mobile defenders)
- **Defenders**: Guard fleets (04, 05, SO-DefendSystem, SO-GuardColony), Reserve fleets (50% effectiveness), Starbases, Unassigned squadrons, Colony fighters
- **Outcome**: If attackers win, proceed to planetary combat (for orders 07/08/09 only)

**3. Planetary Combat** (Final Theater)
- **Attackers**: Only orders 07 (Bombard), 08 (Invade), 09 (Blitz)
- **Defenders**: Ground forces (armies, marines, batteries, shields)
- **Outcome**: Colony capture, infrastructure damage, or repelled invasion

---

## 5. Multi-Faction Combat Resolution

### 5.1 Three-or-More Houses in Same System

When multiple houses have fleets in the same system, combat is resolved using **pairwise diplomatic checks**:

#### 5.1.1 Combat Pairing Logic

For each pair of houses present in the system:
1. Check diplomatic status between that pair
2. Determine if combat occurs based on status + orders
3. Each hostile pair engages independently

#### 5.1.2 Neutral Cooperation Against Common Enemy

**Scenario:** House A and House B are both Neutral to each other, both attacking House C (Enemy to both)

**Combat Matrix:**

| House Pair | Diplomatic Status | Combat Occurs?                |
|------------|-------------------|-------------------------------|
| A vs B     | Neutral           | NO (do not fight each other)  |
| A vs C     | Enemy             | YES                           |
| B vs C     | Enemy             | YES                           |

**Result:**
- House A and House B both attack House C simultaneously
- House A and House B do NOT attack each other
- Allows temporary cooperation without formal alliance

**Key Rule:** Neutral houses can coexist in contested systems and jointly attack a common enemy without engaging each other in combat.

### 5.2 Task Force Formation

**Each house forms separate task force:**
- All participating fleets from that house combine into unified task force
- Task force targets only hostile houses based on diplomatic status
- Multiple task forces can target the same enemy simultaneously

**Example (3-way fight):**
- House A: Enemy to both B and C → Fights both
- House B: Enemy to A, Neutral to C → Fights only A
- House C: Enemy to A, Neutral to B → Fights only A
- **Result:** A fights both B and C, but B and C don't fight each other

---

## 6. Implementation Notes

### 6.1 Diplomatic Status Tracking

**Per House Pair:**
```nim
type DiplomaticState*{.pure.} = enum
  Neutral,  # Default, safe passage
  Hostile,  # Warning state
  Enemy     # Active war

# Stored in each house's diplomatic relations table
diplomaticRelations: Table[(HouseId, HouseId), DiplomaticState]
```

### 6.2 Escalation Tracking

**Required State:**
- Current diplomatic status between each house pair
- Turn counter since last combat (for de-escalation eligibility)
- Pending de-escalation offers
- Historical offense count (for Hostile → Enemy second offense)

### 6.3 Combat Detection Algorithm

**For each system with multiple houses:**

```nim
proc detectCombat(systemId: SystemId, state: GameState): seq[(HouseId, HouseId)] =
  ## Returns pairs of houses that should engage in combat
  var combatPairs: seq[(HouseId, HouseId)] = @[]

  # Get all houses with fleets in this system
  let housesPresent = getHousesInSystem(systemId, state)

  # Check each pair
  for i in 0..<housesPresent.len:
    for j in (i+1)..<housesPresent.len:
      let house1 = housesPresent[i]
      let house2 = housesPresent[j]

      # Get diplomatic status
      let status = getDiplomaticState(state, house1, house2)

      # Check if combat triggers
      if shouldEngageInCombat(status, house1, house2, systemId, state):
        combatPairs.add((house1, house2))
        # Also trigger escalation if needed
        checkEscalation(state, house1, house2, systemId)

  return combatPairs
```

### 6.4 Order Threat Classification

**Helper function to determine if order is threatening:**

```nim
proc isThreateningOrder(order: FleetOrderType): bool =
  ## Returns true if order immediately escalates to Enemy status
  case order:
  of BlockadePlanet, Bombard, Invade, Blitz, HackStarbase:
    return true
  else:
    return false

proc isNonThreateningButProvocative(order: FleetOrderType): bool =
  ## Returns true if order escalates gradually (Neutral→Hostile, Hostile→Enemy)
  case order:
  of Hold, Patrol, SpyPlanet, SpySystem, ViewWorld, Salvage:
    return true
  of JoinFleet, Rendezvous:
    # Only if happening in defender's space
    return true
  else:
    return false
```

---

## 7. Current vs Planned State

### 7.1 Legacy Systems to Remove

**Dishonored Status:**
- Was previously in codebase, now removed.
- **Reason**: Replaced by simple escalation ladder + negotiated de-escalation.

**Ally Diplomatic State:**
- Was previously defined in diplomatic types, now removed.
- **Reason**: Zero-sum conquest game, no formal alliances.
- **Alternative**: Neutral status provides temporary cooperation capability.

**Treaty System:**
- Was previously in codebase, now removed.
- **Reason**: Replaced by simple de-escalation offers.

### 7.2 Current Implementation Issues

**In `src/engine/resolution/phases/conflict_phase.nim`:**

**Problem 1:** Combat detection only checks Enemy/Hostile, missing Neutral + threatening orders
```nim
# Current (WRONG):
if relation == DiplomaticState.Enemy or relation == DiplomaticState.Hostile:
  combatDetected = true

# Should be:
if relation == DiplomaticState.Enemy:
  combatDetected = true
elif relation == DiplomaticState.Hostile:
  # Check if threatening operations present
  if hasThreateningOrders(...):
    combatDetected = true
elif relation == DiplomaticState.Neutral:
  # Check if threatening orders in defender's system
  if hasThreateningOrders(...) and isDefenderSystem(...):
    # Escalate to Enemy and trigger combat
    combatDetected = true
```

**Problem 2:** ELI/Raider detection logic preventing combat instead of determining ambush bonuses
```nim
# Current (WRONG): Uses detection to determine if combat triggers
let house1Detected = not house1Cloaked or house2HasScouts
if house1Detected and house2Detected:
  combatDetected = true

# Should be: Combat triggers based on diplomatic status, detection only affects ambush
# Detection logic belongs in combat resolution phase, not combat detection
```

**Problem 3:** No system owner check for Neutral + threatening orders
- Current code doesn't verify if system has a defender's colony
- Needs to check if threatening house is in system controlled by other house

---

## 8. Testing Requirements

### 8.1 Escalation Path Testing

**Test Scenarios:**
1. Neutral fleet moves through system (transit) → No escalation
2. Neutral fleet stops in system (Hold) → Escalate to Hostile
3. Hostile fleet returns to same system → Escalate to Enemy
4. Neutral fleet uses Bombard order → Escalate directly to Enemy
5. Enemy status persists across turns → No auto-de-escalation

### 8.2 De-escalation Testing

**Test Scenarios:**
1. Enemy house offers de-escalation → Hostile house can accept/reject
2. Successful de-escalation → Enemy → Hostile after 3 turns no combat
3. Rejected offer → 3-turn cooldown before can offer again
4. Combat during de-escalation period → Resets timer

### 8.3 Multi-Faction Combat Testing

**Test Scenarios:**
1. Three houses in system: A+B Neutral, both Enemy to C → A and B don't fight each other, both fight C
2. Three houses: A Enemy to both B and C, B Neutral to C → A fights both, B and C don't fight
3. Combat resolution with multiple task forces targeting same enemy → Simultaneous damage application

---

## 9. Related Documentation

**See Also:**
- `/docs/specs/operations.md` - Section 7: Combat operations (space, orbital, planetary)
- `/docs/specs/reference.md` - Diplomatic states and order definitions
- `/docs/engine/architecture/diplomatic-system.md` - (To be created) Diplomatic state machine implementation
- `/docs/ai/mechanics/unit-progression.md` - How AI uses diplomatic status for strategic decisions

**Supersedes:**
- Previous ally/treaty/dishonored diplomatic system (to be removed)
- Non-aggression pact mechanics (replaced by Neutral status)

---

## 10. Open Questions

1. **Prestige cost for de-escalation offers?** Should offering peace cost prestige/resources, or is diplomatic flexibility free?

2. **Automatic escalation on combat?** Should any combat automatically escalate status (e.g., Hostile combat → Enemy), or only based on orders/offenses?

3. **De-escalation asymmetry?** Should Enemy → Hostile be harder/costlier than Hostile → Neutral?

4. **Historical grievances?** Should repeated escalation/de-escalation cycles affect future negotiations (e.g., "fool me twice")?

5. **Third-party enforcement?** Can neutral houses sanction aggressive houses (e.g., trade embargoes, prestige penalties)?

---

**End of Specification**
