# 7.0 Combat

Combat in EC4X occurs across three distinct combat theaters. When fleets execute invasion or blitz orders against an enemy colony, they must fight progressively through each theater to capture the planet.

## Three-Phase Combat Progression

**Progressive Combat Requirement:**

Attacking forces must successfully win each combat phase before advancing to the next:

**Phase 1: Space Combat** ([Section 7.3](#73-space-combat))
- Fleet vs fleet engagements in deep space
- Mobile task forces fighting for space superiority
- Determined by fleet composition, tactics, and technology
- Occurs FIRST when attackers enter a system with mobile defenders
- Attackers must defeat or force retreat of mobile defenders to proceed to orbital combat
- Detection mechanics apply: ELI-equipped scouts can detect cloaked Raiders
- Ambush advantage (+4 CER): Undetected Raiders strike first with bonus in space combat only

**Phase 2: Orbital Combat** ([Section 7.4](#74-orbital-combat))
- Attacks on defended colonies after space superiority achieved
- Combines guard fleets, reserve fleets, starbases, and unassigned squadrons
- Protects screened units (mothballed ships, spacelift vessels)
- Occurs SECOND after attackers win space combat (or if no mobile defenders present)
- Attackers must defeat orbital defenses to proceed to planetary bombardment
- Detection mechanics apply: ELI-equipped scouts and starbases can detect cloaked Raiders
- NO ambush advantage: Raiders detected in space remain detected; newly encountered Raiders get no +4 bonus
- Orbital defenses cannot be "surprised" but detection still determines initiative

**Phase 3: Planetary Combat** ([Section 7.5](#75-planetary-bombardment) & [Section 7.6](#76-planetary-invasion--blitz))
- Surface warfare after orbital supremacy achieved
- Bombardment, invasion, and blitz operations
- Planetary shields, ground batteries, and ground forces defend
- Occurs THIRD after attackers win orbital combat
- Final phase before colony capture

**Combat Sequence Example:**

An invasion fleet entering an enemy system:
1. Fights mobile defenders in space combat (if present)
2. If victorious, proceeds to orbital combat against guard fleets, reserve, starbases
3. If victorious, proceeds to planetary bombardment and invasion
4. Only after clearing all three phases can troop transports land

Attackers cannot skip phases. Guard orders mean fleets defend in orbital combat only, not space combat.

## 6.4 Standing Orders

Your fleets execute standing orders automatically when no explicit order exists—persistent behaviors that reduce micromanagement while maintaining strategic control. Standing orders activate only for fleets without active missions, providing default behaviors that align with your strategic intent.

### 6.4.1 Standing Order Mechanics

**Execution Priority:**

Standing orders execute AFTER active fleet orders during each turn's Command Phase:
1. Active fleet orders execute first (Move, Patrol, Bombard, etc.)
2. Fleets with no active orders check for standing orders
3. Standing orders generate appropriate fleet orders automatically
4. Generated orders persist until completed or overridden

**Override Behavior:**

Your active orders always override standing orders—issue any fleet order and the standing order suspends automatically. When your active order completes, the standing order resumes execution. This gives you tactical flexibility without sacrificing automation.

**Suspension and Resumption:**

Standing orders suspend when you issue active orders, resume when those orders complete. A PatrolRoute standing order pauses while you manually send the fleet to intercept an enemy, then resumes the patrol route automatically after the interception order completes.

### 6.4.2 Patrol Route

Your fleet follows a predefined path indefinitely, looping through specified systems. Each turn, the fleet moves to the next system in the patrol route, returning to the first system after completing the circuit.

**Parameters:**
- Patrol path (sequence of system IDs)
- Current position in path (tracked automatically)

**Behavior:**
- Fleet moves to next system in path each turn
- Loops continuously (system 1 → 2 → 3 → 1 → ...)
- Engages hostile forces per ROE while patrolling
- Resumes patrol automatically after combat

**Best Uses:**
- Border patrols monitoring frontier systems
- Trade route protection through key corridors
- Defensive circuits around strategic colonies
- Reconnaissance loops gathering intelligence

**Example:**

You establish a four-system patrol route: Alpha → Beta → Gamma → Delta. Your fleet automatically moves Alpha → Beta (turn 1), Beta → Gamma (turn 2), Gamma → Delta (turn 3), Delta → Alpha (turn 4), continuing indefinitely. If combat occurs at Beta, the fleet engages per ROE, then continues to Gamma next turn.

### 6.4.3 Defend System

Your fleet guards a specific system, patrolling when at the target and returning automatically if pulled away by combat or explicit orders.

**Parameters:**
- Target system to defend
- Maximum range (jumps from target before returning)

**Behavior:**
- Fleet patrols target system when present
- Returns immediately if moved beyond maximum range
- Engages all hostile forces entering defended system
- Prioritizes defending target over pursuing retreating enemies

**Best Uses:**
- Homeworld defense fleets
- Strategic chokepoint garrisons
- Colony protection during expansion
- Starbase guard forces

**Strategic Note:**

DefendSystem provides elastic defense—fleets pursue enemies briefly but snap back to defensive position automatically. This prevents your defensive fleets from being lured away from critical systems by feints and raids.

### 6.4.4 Guard Colony

Your fleet maintains station at a specific colony, executing GuardPlanet orders to defend against invasions and bombardments.

**Parameters:**
- Colony system to guard

**Behavior:**
- Fleet issues GuardPlanet orders at target colony
- Participates in orbital combat defending the colony
- Does not pursue fleeing enemies beyond the system
- Maintains station until enemy threat eliminated

**Best Uses:**
- High-value colony protection (advanced research colonies)
- Capital system defense-in-depth
- Mining colony escorts
- Vulnerable frontier outposts

**Difference from DefendSystem:**

GuardColony focuses on planetary defense (orbital combat), while DefendSystem patrols the system and engages mobile enemies. GuardColony fleets participate in orbital combat mechanics; DefendSystem fleets engage before enemies reach orbit.

### 6.4.5 Auto-Colonize

Your ETAC fleets automatically colonize the nearest suitable unoccupied planet, executing colonization missions without explicit orders.

**Parameters:**
- Preferred planet classes (Benign, Harsh, etc.)
- Maximum colonization range (jumps from current position)

**Behavior:**
- Scans for unoccupied planets within range
- Prioritizes by planet class preferences
- Issues Colonize orders to nearest suitable target
- Continues seeking new targets after each colony established
- Holds position if no suitable planets within range

**Best Uses:**
- Rapid expansion during early game
- Automated frontier colonization
- Economic AI fleet behavior
- Reducing colonization micromanagement

**Strategic Considerations:**

AutoColonize fleets expand your empire automatically but follow predictable patterns. Rival houses can intercept if they identify your colonization vectors. Use AutoColonize for secondary expansion while manually directing strategic colony placements.

### 6.4.6 Auto-Reinforce

Your fleet automatically joins the nearest friendly fleet when damaged below a threshold, seeking safety in numbers.

**Parameters:**
- Damage threshold (percentage, e.g., 50% hull integrity)
- Target fleet (specific fleet ID or nearest)

**Behavior:**
- Monitors fleet combat effectiveness continuously
- Issues JoinFleet order when damage exceeds threshold
- Seeks nearest friendly fleet if no target specified
- Merges with target fleet for repairs and refit

**Best Uses:**
- Raiding fleets returning for repairs
- Damaged scouts rejoining main forces
- AI self-preservation behavior
- Automated fleet consolidation after combat

**Note:**

AutoReinforce provides automatic damage control but doesn't seek shipyard repairs. Use AutoRepair (below) for fleets needing industrial refit. AutoReinforce consolidates damaged forces for combined defense and eventual repair at colonies.

### 6.4.7 Auto-Repair

Your fleet returns to the nearest shipyard when damaged below a threshold, seeking industrial repair facilities.

**Parameters:**
- Damage threshold (percentage hull integrity)
- Target shipyard (specific system or nearest)

**Behavior:**
- Monitors fleet hull integrity continuously
- Issues SeekHome to nearest shipyard colony when threshold exceeded
- Holds at shipyard colony for repairs
- Resumes standing orders after repairs complete

**Best Uses:**
- Capital ship preservation
- High-value fleet maintenance
- Automated repair logistics
- AI fleet sustainability

**Repair Mechanics:**

Fleets at friendly colonies with shipyards repair automatically each turn (see Section 3.9 for repair rates). AutoRepair automates the seeking behavior; the actual repairs follow standard mechanics at the destination colony.

### 6.4.8 Auto-Evade

Your fleet automatically retreats to a safe system when facing overwhelming enemy forces, preserving your assets for future engagements.

**Parameters:**
- Fallback system (safe retreat destination)
- Strength ratio trigger (e.g., 2.0 = retreat when outnumbered 2:1)

**Behavior:**
- Compares fleet strength to hostile forces each turn
- Issues Move order to fallback system when ratio exceeded
- Engages per ROE while retreating
- Returns automatically when threat eliminated

**Best Uses:**
- Scout fleet self-preservation
- Raiding force protection
- AI defensive behavior
- Avoiding unfavorable engagements

**Tactical Considerations:**

AutoEvade provides automatic force preservation but can create exploitable patterns. Enemies observing your fallback destination can ambush retreating fleets. Vary fallback destinations for strategic fleets or disable AutoEvade when seeking decisive battle.

### 6.4.9 Blockade Target

Your fleet maintains continuous blockade of an enemy colony, preventing production and starving the target of resources.

**Parameters:**
- Target colony system

**Behavior:**
- Issues BlockadePlanet orders at target system
- Maintains blockade indefinitely
- Engages relief forces automatically
- Repairs at nearest friendly colony when damaged

**Best Uses:**
- Economic warfare against enemy production
- Siege operations before invasion
- Cutting off strategic resources
- Forcing enemy fleet response

**Blockade Mechanics:**

Blockaded colonies cannot export production, receive reinforcements, or execute most orders (see Section 8.1 for complete blockade rules). Effective blockades require sufficient fleet strength to defeat relief forces and sustain the siege.

### 6.4.10 Rules of Engagement Integration

All standing orders respect your fleet's ROE setting (0-10). High ROE fleets engage aggressively while executing standing orders; low ROE fleets prioritize mission completion and retreat from unfavorable combat. Set ROE appropriately for each standing order's strategic purpose—defensive patrols use low ROE, offensive blockades use high ROE.

### 6.4.11 Standing Order Management

**Setting Standing Orders:**

Issue standing orders through fleet command interface—select fleet, specify standing order type and parameters. Standing orders persist until explicitly cancelled or replaced.

**Canceling Standing Orders:**

Set standing order to None or issue active fleet orders. Active orders suspend standing orders automatically; canceling returns the fleet to no-orders state (Hold position).

**Multiple Fleets, Same Standing Order:**

You can assign identical standing orders to multiple fleets—three fleets with PatrolRoute orders covering different sectors, five ETAC fleets with AutoColonize orders expanding in different directions. Each fleet executes its standing order independently.

**Strategic Combinations:**

Combine standing orders with active tactical commands—your border patrol fleet (PatrolRoute) receives an active "Intercept enemy at Beta" order, completes the interception, then resumes patrol automatically. This blends automation with tactical control seamlessly.

## 6.5 Ship Repairs and Repair Queues

Your warships damaged in combat require systematic repairs at colonies with shipyard or spaceport facilities. Understanding repair mechanics ensures your fleets maintain combat readiness.

### 6.5.1 Repair Fundamentals

**Damage States:**
- **Undamaged**: Full combat effectiveness
- **Crippled**: 50% attack and defense strength, can still move and fight
- **Destroyed**: Permanently lost (salvage value only)

**Repair Requirements:**
- Colony with operational shipyard or spaceport
- Available dock capacity (repairs compete with construction for docks)
- Treasury funds (25% of ship's build cost per economy.md)
- One turn repair time

**Automatic Repair Submission:**

Your fleets don't need explicit repair orders. When a fleet with crippled ships stations at a colony with repair facilities and available dock capacity, all crippled ships (escorts and flagships) automatically extract and enter the repair queue.

**Flagship Extraction:**
- **Squadron has escorts**: The strongest escort (highest AS + DS) is promoted to flagship. The crippled flagship extracts for repair. Squadron continues operating.
- **Squadron has no escorts**: The squadron dissolves entirely. The flagship extracts for repair. If this was the fleet's last squadron, the fleet is removed from the game.

**Standing Orders for Repairs:**

Fleets don't automatically return to shipyards when damaged. You must give your fleet a **standing order: AutoRepair** (see 6.4.6) to make damaged fleets automatically return to the nearest shipyard and hold for repairs. Without this standing order, damaged fleets will continue executing their current orders until you explicitly redirect them.

### 6.5.2 Repair Queue Mechanics

**Dock Capacity:**
- **Shipyards**: 10 docks per facility (for capital ships and larger escorts)
- **Spaceports**: 5 docks per facility (for smaller escorts)
- **Shared Capacity**: Construction and repairs compete for the same docks

**Priority System:**
1. **Construction Projects** (Priority 0): Ship/building construction takes precedence
2. **Ship Repairs** (Priority 1): Combat vessel repairs
3. **Starbase Repairs** (Priority 2): Orbital fortress repairs

**Facility Assignment:**

Each repair is assigned to a facility type based on asset type:
- **Shipyard Repairs**: Battleships, Dreadnoughts, Carriers, Heavy Cruisers, Cruisers, **Starbases**
- **Spaceport Repairs**: Light Cruisers, Destroyers, Frigates, Scouts

Construction projects can use any available dock type, but repairs are facility-specific. Starbases always require shipyard facilities (they're orbital structures, cannot be repaired at ground spaceports).

### 6.5.3 Starbase Repairs and Crippled Penalties

**Crippled Starbase Effects:**

Crippled starbases lose ALL operational benefits until repaired:
- **No ELI bonus**: Electronic Intelligence (ELI) surveillance disabled
- **No population bonus**: Cannot support additional population capacity
- **No defense bonus**: Defensive combat strength reduced to 50%
- **Automatic repair**: Starbases at colonies with operational shipyards automatically enter repair queue

**Starbase Repair Specifics:**

- **Facility Required**: Shipyard only (orbital structures, cannot use spaceports)
- **Cost**: 25% of starbase build cost (~25 PP for standard starbase)
- **Duration**: 1 turn
- **Priority**: Lowest (priority 2, after construction and ship repairs)
- **Automatic**: No player action needed—crippled starbases automatically queue when shipyard capacity available

**Strategic Implications:**

Losing starbase surveillance during repairs creates intelligence gaps. Enemy fleets can move through your systems undetected while your starbase repairs. Protect your starbases aggressively or maintain backup surveillance (scouts, adjacent starbases).

### 6.5.4 Ship Repair Pipeline

**Stage One: Extraction**

When your fleet arrives at a colony with repair capacity:
1. System identifies all crippled escort ships (flagships remain with squadron)
2. Escorts extracted from their squadrons one at a time
3. Each ship becomes a separate repair project in the queue

**Stage Two: Repair Queue**

Ships enter facility-specific queues:
- Repair projects occupy one dock each
- Repair duration: 1 turn (all repairs complete simultaneously)
- Cost: 25% of ship's build cost (deducted when repair completes)

If dock capacity full, ships remain with their squadrons and retry next turn.

**Stage Three: Recommissioning**

Repaired ships recommission through the standard squadron pipeline (see 6.2.2):
- Capital ships become new squadron flagships
- Escorts join existing capital ship squadrons (balanced distribution)
- Escorts join same-class escort squadrons if no capital squadrons available
- New escort squadrons created only when no suitable squadrons exist

**Stage Four: Fleet Assignment**

If colony has `autoAssignFleets = true` (default):
- Repaired squadrons automatically join existing stationary fleets at colony
- Load-balanced across all Active fleets
- New fleets created only if no candidate fleets exist

If `autoAssignFleets = false`:
- Squadrons remain in colony.unassignedSquadrons for manual assignment

### 6.5.5 Repair Costs and Economics

**Cost Structure:**

Repairs cost 25% of the ship's construction cost at **shipyards** (orbital facilities):
- Battleship (70 PP build cost) = 17-18 PP repair
- Heavy Cruiser (35 PP build cost) = 8-9 PP repair

**Spaceport Penalty:**

Repairs at **spaceports** (ground-based facilities) cost 50% more due to less efficient equipment:
- Destroyer (15 PP build cost) = 5-6 PP repair at spaceport (vs 3-4 PP at shipyard)
- Light Cruiser (20 PP build cost) = 7-8 PP repair at spaceport (vs 5 PP at shipyard)
- Frigate (10 PP build cost) = 3-4 PP repair at spaceport (vs 2-3 PP at shipyard)

**Facility Assignment:**

You cannot choose which facility repairs your ships—assignment is automatic by ship class. Build orbital shipyards for more cost-effective escort repairs if you have the industrial capacity.

**Treasury Requirements:**

Repair costs deducted from house treasury when repair completes. If insufficient funds, repair fails and ship remains crippled in queue (will retry next turn).

**Economic Trade-offs:**

Repairing a crippled battleship (17 PP) vs building new destroyer (15 PP):
- Repair preserves expensive capital ship
- New construction adds fleet capacity
- Consider strategic value vs immediate need

**Starbase Repairs:**

Starbases cost ~25 PP to repair (25% of ~100 PP build cost). This is expensive but essential—crippled starbases lose all surveillance and defensive bonuses. Prioritize starbase repairs in critical defensive positions.

### 6.5.6 Facility Vulnerability

**Combat Damage to Facilities:**

Per economy.md:5.0, ships under construction or repair are destroyed if:
- Facility destroyed by orbital bombardment
- Facility crippled by combat damage
- Colony successfully invaded (spaceports destroyed on marine landing)

**Queue Behavior:**
- **Facility-specific repairs**: Destroyed immediately when that facility type lost
- **Construction projects**: Can transfer to other facility types at colony (shipyard → spaceport)
- **All facilities lost**: All construction and repair projects destroyed (no salvage value)

**Strategic Implications:**

Protect your industrial colonies—losing an orbital shipyard during enemy bombardment destroys all ships under repair at that facility, costing you both the repair investment and the crippled ships.

### 6.5.7 Practical Examples

**Example 1: Battle-Damaged Fleet Returns Home**

Your battle fleet (3 battleship squadrons, 8 destroyer escorts) engages enemy forces. After combat:
- 2 battleships crippled (remain as flagships)
- 5 destroyers crippled

You assign standing order: **AutoRepair** with target shipyard at your capital:
1. **Turn 1**: Fleet moves toward capital (2 jumps away)
2. **Turn 2**: Fleet arrives at capital, holds for repairs
3. **Turn 3**: All 7 crippled ships automatically extracted:
   - 5 destroyers enter spaceport repair queue
   - 2 battleship flagships enter shipyard repair queue
   - For battleship squadrons: strongest escorts promoted to new flagships
4. **Turn 4**: All ships complete repairs (1 turn), recommission to new squadrons
5. **Turn 4**: New squadrons auto-assign back to same fleet (if `autoAssignFleets = true`)

**Result**: Your entire fleet is restored to full combat effectiveness. Flagship extraction happens automatically with escort promotion.

**Example 2: Construction vs Repair Priority**

Your border fortress colony has:
- 1 shipyard (10 docks)
- 5 ships under construction (occupying 5 docks)
- 5 docks available

Damaged patrol fleet arrives with 7 crippled destroyers:
1. **Turn N**: 5 destroyers extract and enter repair queue (5/10 docks used by construction + repairs)
2. **Turn N**: 2 destroyers remain crippled with fleet (no dock capacity)
3. **Turn N+1**: 5 ships complete construction (5 docks freed)
4. **Turn N+1**: 2 remaining destroyers extract (now capacity available)
5. **Turn N+1**: Original 5 destroyers complete repairs, recommission
6. **Turn N+2**: Final 2 destroyers complete repairs, recommission

**Result**: Construction takes priority, but repairs process as capacity becomes available.

**Example 3: Enemy Bombardment Destroys Repairs**

Your shipyard colony under siege:
- 1 shipyard (10 docks)
- 3 battleships under repair (priority 1)
- 2 battleships under construction (priority 0)

Enemy fleet bombards colony, destroys shipyard:
1. **Conflict Phase**: Shipyard destroyed
2. **Immediate Effect**: All 5 ships (construction + repairs) lost with no salvage
3. **Economic Loss**: ~350 PP in ships + ~35 PP in repair investments = 385 PP total loss

**Result**: Catastrophic industrial loss. Defend your shipyards aggressively.

**Example 4: Crippled Starbase Loses Surveillance**

Your border system has 1 starbase (ELI surveillance) and 1 shipyard. Enemy raid cripples the starbase:
1. **Turn N (Conflict Phase)**: Starbase crippled in combat
2. **Turn N (Immediate Effect)**: ELI surveillance disabled, population bonus lost
3. **Turn N+1 (Maintenance Phase)**: Starbase automatically queued for repair at shipyard
4. **Turn N+2**: Starbase repair completes, ELI and bonuses restored

During Turn N+1 (repair in progress):
- No surveillance of enemy fleet movements
- Enemy fleets can transit system undetected
- Reduced defensive strength (starbase still provides combat power, but crippled)

**Result**: 1-turn intelligence blackout. Consider backup surveillance (scouts, adjacent starbases) for critical systems.

### 6.5.8 Best Practices

**Standing Orders Are Essential:**

Without standing order AutoRepair, your damaged fleets will not automatically return to shipyards. Assign AutoRepair to all combat fleets operating far from home to ensure they seek repairs when damaged.

**Repair Capacity Planning:**

Build multiple repair facilities:
- Frontline colonies: 1 spaceport (5 docks) for escort repairs
- Industrial hubs: 2-3 shipyards (20-30 docks) for capital ship repairs
- Dispersed repair capacity reduces single-point-of-failure risk

**Flagship Extraction:**

Crippled flagships automatically extract for repair like any other crippled ship. The extraction process depends on squadron composition:
- **Squadrons with escorts**: Strongest escort promoted to flagship, squadron continues operating
- **Single-flagship squadrons**: Squadron dissolves, flagship repairs, fleet may be removed if empty
- Both cases restore ships to full combat effectiveness after repair

**Defensive Priorities:**

Your industrial colonies are high-value targets:
- Station defensive fleets at shipyard colonies
- Build starbases for orbital defense
- Evacuate or suspend repairs before enemy arrival

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

### 7.1.3 Cloaking and Detection

Cloaked Raiders have two distinct advantages that are tracked separately:

**Detection State:**
- Determines which combat phase Raiders attack in
- Undetected Raiders attack in Phase 1 (before all other units)
- Detected Raiders lose initiative and attack in Phase 3 (with capital ships)
- Detection state persists across combat phases within the same engagement

**Ambush Bonus (+4 CER):**
- Only applies in Space Combat ([Section 7.3](#73-space-combat))
- Undetected Raiders in space combat receive +4 CER modifier on first round
- Does NOT apply in Orbital Combat ([Section 7.4](#74-orbital-combat))
- Rationale: Cannot ambush stationary orbital defenses

**Pre-Combat Detection:**

Before combat begins, ELI-equipped units (scouts and starbases) attempt to detect cloaked Raiders:
- Roll for detection per [Section 2.4.3](assets.md#243-raiders)
- Scouts use house ELI technology level
- Starbases receive +2 ELI modifier for detection rolls
- Multiple scouts form mesh network (use effective ELI calculation)
- If detected, Raider loses initiative advantage and attacks in Phase 3

**Detection State Persistence:**

Once a house's Raiders are detected in Space Combat, they remain detected in subsequent Orbital Combat:
- No new detection rolls for already-detected houses
- Detection state tracked per house across combat phases
- New Raiders encountering defenders for the first time get fresh detection rolls

**Starbase Detection Participation:**

Starbases assist in pre-combat detection regardless of which combat phase is being resolved:
- **Space Combat**: Starbases detect cloaked Raiders but are screened and cannot fight or be targeted
- **Orbital Combat**: Starbases detect cloaked Raiders AND participate in combat as defenders
- Starbases at a colony contribute their detection capability (+2 ELI bonus) to all combat phases
- Rationale: Advanced sensors on starbases provide detection support to all friendly forces in the system

**Multi-Faction Cloaking:**

If cloaked fleets on all sides pass undetected from one another:
- In owned systems: Defender wins initiative
- In neutral territory: Forces avoid engagement and continue with movement orders (combat cancelled)

### 7.1.4 Morale

House prestige affects crew morale and combat effectiveness. At the start of each turn, the game rolls 1D20 to determine morale status for that turn.

**Morale Check Table:**

*Note: Morale levels and thresholds are defined in Table 9.4. The values below match the current configuration but may change - always refer to Table 9.4 for authoritative values.*

| Morale Level | Morale Threshold | Effect on Success                      |
|:-------------|:----------------:|:---------------------------------------|
| Collapsing   | Never succeeds   | -1 to all CER rolls this turn          |
| VeryLow      | > 18             | No effect                              |
| Low          | > 15             | +1 to CER for one random squadron      |
| Normal       | > 12             | +1 to all CER rolls this turn          |
| High         | > 9              | +1 CER + one critical auto-succeeds    |
| VeryHigh/Exceptional | > 6     | +2 to all CER rolls this turn          |

See [Table 9.4](reference.md#104-prestige) for prestige ranges that determine morale level.

**Morale Effects:**

- CER bonuses/penalties apply to all CER die rolls before consulting the CER table.
- Critical auto-success (61-80 prestige): The first squadron to execute a valid attack during the turn's Conflict Phase per [Section 1.3.1](gameplay.md#131-conflict-phase) automatically achieves critical hit effects as if a natural 9 was rolled on the CER table, bypassing destruction protection and applying force reduction rules as defined in [Section 7.3.3](#733-combat-effectiveness-rating-cer). This applies to the first valid attack across all combats in the turn, regardless of system or initiative phase. If multiple combats occur, only the first attacking squadron in the earliest resolved combat receives this benefit.
- Morale effects last for the current turn only.
- Prestige ≤ 0 automatically triggers morale crisis without requiring a roll.

**Morale Crisis (Collapsing Morale):**

When a House's morale reaches Collapsing level (see [Table 9.4](reference.md#104-prestige) for prestige threshold), morale collapses:
- All CER rolls receive -1 penalty (no morale check roll required).
- One random fleet refuses orders and holds position for the turn.
- Effects persist until prestige rises above the Collapsing threshold.

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

When multiple houses are present in a solar system, each house forms an independent Task Force from its applicable fleets and installations per [Section 7.2](#72-task-force-assignment). Houses do not combine forces into joint Task Forces, even under Non-Aggression Pacts.

Attacking units select targets using diplomatic filtering and priority rules defined in [Section 7.3.2](#732-target-priority-rules).

Squadrons are not allowed to change assignments or restructure during combat engagements or retreats.

### 7.3.1 Combat Initiative and Phase Resolution

Space combat resolves in initiative phases based on unit tactical characteristics. Each phase resolves completely before proceeding to the next phase. When multiple houses are present, all houses participate simultaneously in each phase according to their unit types.

**Combat Initiative Order:**

1. **Undetected Raiders** (Ambush Phase)
2. **Fighter Squadrons** (Intercept Phase)
3. **Capital Ships** (Main Engagement Phase)

Units destroyed in an earlier phase do not participate in later phases.

**Simultaneous Attack Resolution:**

Within each phase, when multiple units attack simultaneously (same initiative tier), use the following resolution sequence:

1. **Target Selection**: All attacking units select their targets using [Section 7.3.2](#732-target-priority-rules)
2. **Damage Application**: All damage is applied simultaneously after all selections are made
3. **State Transitions**: All squadron state transitions are evaluated after all damage is applied
4. **Overkill Handling**: If multiple attackers independently selected the same target and combined damage exceeds destruction threshold, excess damage is lost

#### 7.3.1.1 Phase 1: Undetected Raiders (Ambush Phase)

Cloaked Raider fleets that successfully evaded ELI detection during the pre-combat detection phase strike first with initiative advantage.

**Pre-Combat Detection:**

Before combat begins, all ELI-equipped units (Scouts and Starbases) in the defending force attempt to detect cloaked Raiders using the detection mechanics defined in [Section 2.4.3](assets.md#243-raiders).

For each defending ELI unit:
- Calculate effective ELI level (weighted average, dominant tech penalty, mesh network modifier)
- Starbases receive +2 ELI modifier for detection rolls in all combat phases
- Starbases participate in detection for both Space Combat and Orbital Combat
- In Space Combat, starbases detect but cannot fight or be targeted (screened)
- Roll detection against each attacking cloaked fleet's highest CLK rating
- If detected, the Raider fleet loses initiative advantage and attacks in Phase 3 instead

**Detection State Tracking:**

Detection state is tracked per house and persists across combat phases:
- Raiders detected in Space Combat remain detected in subsequent Orbital Combat
- No new detection rolls for already-detected houses in Orbital Combat
- New Raiders (not present in Space Combat) get fresh detection rolls in Orbital Combat

**Ambush Resolution:**

Undetected Raiders attack before any defending units can respond:
- **Space Combat Only:** Raiders receive +4 die roll modifier on CER roll (ambush bonus)
- **Orbital Combat:** Raiders attack in Phase 1 but do NOT receive +4 ambush bonus (cannot ambush prepared defenses)
- Each Raider squadron independently selects targets using [Section 7.3.2](#732-target-priority-rules)
- All Raider squadrons select targets, then all damage is applied simultaneously
- All state transitions are evaluated after all damage is applied
- Destroyed targets do not return fire
- Multiple undetected Raider squadrons attack simultaneously in this phase

See [Section 7.3.3](#733-combat-effectiveness-rating-cer) for full CER modifier details.

#### 7.3.1.2 Phase 2: Fighter Squadrons (Intercept Phase)

All fighter squadrons in the system attack simultaneously, regardless of ownership or deployment status.

**Fighter Combat Behavior:**

**Colony-Owned Fighters:**
- Always participate in system defense
- Never retreat independently from combat
- Fight until destroyed or enemy eliminated

**Carrier-Owned Fighters:**
- Automatically deploy when carrier enters combat
- Retreat only when carrier retreats

All fighters attack using target priority rules defined in [Section 7.3.2](#732-target-priority-rules). Each fighter squadron applies its full AS as damage to its selected target.

**Fighter State Transitions:**

Fighter squadrons skip the crippled state due to their lightweight construction. Fighters transition directly from undamaged to destroyed when they take damage equal to or exceeding their DS.

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

#### 7.3.1.3 Phase 3: Capital Ships (Main Engagement Phase)

All capital ships attack by squadron in this phase. Squadron attack order is determined by flagship Command Rating (CR).

**Attack Order Resolution:**

1. Squadrons attack in descending order by flagship CR (highest CR attacks first)
2. Squadrons with equal CR attack simultaneously using simultaneous attack resolution
3. For each CR tier (attacking simultaneously):
   - Each squadron rolls for CER (see [Section 7.3.3](#733-combat-effectiveness-rating-cer))
   - Each squadron selects target using [Section 7.3.2](#732-target-priority-rules)
   - All squadrons in this CR tier complete selections
   - All damage is applied simultaneously
   - All state transitions are evaluated after all damage is applied
4. Destroyed squadrons do not return fire in subsequent CR tiers

**Squadron Combat Mechanics:**

A squadron fights as a unified tactical unit with pooled combat values:

- **Squadron AS**: Sum of all ships' AS values under flagship command
- **Squadron DS**: Sum of all ships' DS values under flagship command
- **Damage Application**: All damage is applied to the squadron as a single entity
- **State Transitions**: Squadron state (undamaged/crippled/destroyed) applies uniformly to all ships in the squadron

**Squadron State Propagation:**

When a squadron transitions state, all ships under its command transition simultaneously:
- **Undamaged → Crippled**: All ships in the squadron become crippled
- **Crippled → Destroyed**: All ships in the squadron are destroyed
- Individual ships within a squadron cannot have different states during combat

**Squadron Composition During Combat:**

Command Capacity (CC) is a fleet formation constraint validated during fleet commissioning and reorganization in the Command Phase per [Section 1.3.3](gameplay.md#133-command-phase). Once combat begins, squadrons fight as integrated tactical units regardless of CC/CR ratios. Players can reorganize squadrons to restore CC/CR compliance during the Command Phase after combat concludes.

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

**Fleet Order Targeting Restrictions:**

Certain fleet orders have additional targeting restrictions beyond diplomatic filtering:

1. **Blockade (Fleet Order 05)**: Fleets blockading an enemy planet may only target enemy fleets with Fleet Order 05 (Guard/Blockade) at that same planet
2. **Guard (Fleet Order 05)**: Fleets guarding a planet may only target enemy fleets with orders 05 through 08 or 12 (threatening orders)

**No Valid Targets:**

If an attacking squadron has no valid hostile targets available due to diplomatic filtering or fleet order restrictions, that squadron does not attack during the current phase. The squadron remains in the engagement and may attack in subsequent combat rounds if hostile targets become available.

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
   Weight = Base_Weight(bucket) × Crippled_Modifier
   ```
   Where:
   - `Base_Weight(bucket)` is from the bucket classification table (7.3.2.2)
   - `Crippled_Modifier` = 2.0 if unit is crippled, 1.0 if undamaged

2. **Perform weighted random draw:**
   - Use PRNG seeded with SHA-256 hash of string `"{gameId}-{turnNumber}-{combatId}-{phaseNumber}-{roundNumber}"` modulo 2^32
   - Alternatively, custom seed can be specified for testing or alternate outcomes
   - Select target based on weighted probability distribution
   - Standard weighted random selection algorithm (available in most programming language standard libraries)

3. **Apply damage to selected target:**
   - Fighters: Apply full AS as damage
   - Other units: Apply CER × AS as damage (see [Section 7.3.3](#733-combat-effectiveness-rating-cer))

### 7.3.3 Combat Effectiveness Rating (CER)

After determining combat initiative order and resolving detection checks, combat proceeds in rounds. At the beginning of each combat round (for phases that use CER), each attacking unit rolls independently for Combat Effectiveness Rating.

Each squadron rolls once for CER and applies CER × (squadron total AS).

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
| Ambush   | +4    | First round only, Space Combat ONLY    | Phase 1 (Space Combat only) |

**Ambush Modifier Restriction:**

The +4 Ambush modifier applies ONLY in Space Combat. In Orbital Combat, undetected Raiders still attack in Phase 1 (initiative advantage) but do NOT receive the +4 CER bonus. Rationale: Cannot ambush stationary orbital defenses waiting in prepared defensive positions.

**CER Application:**

**Phase 2 (Fighter Squadrons):**
- Fighters do NOT use CER
- Each fighter squadron independently selects a target using [Section 7.3.2](#732-target-priority-rules)
- Each fighter squadron applies its full AS as damage to its selected target
- All selections are made, then all damage is applied simultaneously
- Fighter squadrons transition from undamaged to destroyed when damage ≥ DS (no crippled state)

**Phases 1 and 3 (Raiders and Capital Ships):**
- Each attacking squadron rolls independently for CER
- Calculate total hits: `Total Hits = CER × Squadron_AS`
- Squadron selects target using [Section 7.3.2](#732-target-priority-rules)
- All squadrons in the same initiative tier complete target selection
- All damage is applied simultaneously
- All state transitions are evaluated after all damage is applied

**Squadron State Transitions:**

After all damage is applied in a phase:

1. **Undamaged → Crippled**: If total damage to an undamaged squadron ≥ squadron DS, the squadron becomes crippled
2. **Crippled → Destroyed**: If total damage to a crippled squadron ≥ squadron DS, the squadron is destroyed
3. **Destruction Protection**: A squadron may not transition from undamaged → crippled → destroyed within the same combat round, even if damage accumulates across multiple attack phases (Phase 2 then Phase 3). The squadron must survive until the next round begins before it can be destroyed.
4. **State Propagation**: All ships in the squadron transition to the squadron's new state simultaneously

**Crippled Squadron Effects:**

When a squadron becomes crippled:
- All ships in the squadron are crippled
- Squadron AS is multiplied by 0.5, rounded up to the nearest whole number
- Squadron DS remains unchanged (used for calculating destruction threshold)
- Crippled squadrons receive 2× targeting weight modifier per [Section 7.3.2.5](#7325-weighted-random-target-selection)

Destroyed squadrons are eliminated from combat and the Task Force loses their associated die roll modifiers (e.g. Scouts).

**Critical Hits:**

Critical hits (natural 9 on die roll before modifiers) have special effects:

1. **Bypass Destruction Protection**: The squadron can be destroyed in the same round it is crippled, even across multiple phases
2. **Force Reduction**: If the critical hit deals insufficient damage to reduce the selected target (hits < target DS), then the squadron with the lowest current DS in the target Task Force is reduced instead (undamaged → crippled, or crippled → destroyed)
3. **Prestige Award**: The house that achieves a critical hit causing squadron destruction is awarded prestige for the kill, even in multi-house combat scenarios

**Overkill Damage:**

When multiple attackers independently select the same target during simultaneous attack resolution:
- Combined damage from all attackers is applied to the target
- If combined damage would destroy a squadron in the same round it is crippled, and no critical hit was rolled, destruction protection applies
- The squadron becomes crippled, and excess damage beyond the crippling threshold is lost
- If any attacking squadron rolled a critical hit against this target, destruction protection is bypassed and the squadron is destroyed

**Multi-House Combat Prestige Attribution:**

When three or more houses participate in combat:
- **FleetVictory** prestige is awarded to the house that dealt the crippling blow to the final squadron in that Task Force - see [Table 9.4](reference.md#104-prestige)
- If a squadron is destroyed in the same round it is crippled (via critical hit or overkill with critical), prestige goes to the house that dealt the crippling blow
- If multiple houses attack simultaneously and a squadron is destroyed (already crippled from previous round), all attacking houses share prestige equally (rounded down, minimum 1 per house)
- **FleetVictory** prestige is awarded to all houses engaged with the retreating Task Force, divided evenly (rounded down, minimum 1 per house) - see [Table 9.4](reference.md#104-prestige)
- Track damage sources to determine which house dealt the crippling blow for prestige awards

### 7.3.4 Rounds

Combat continues in rounds until one side is completely destroyed or manages a retreat.

All units attack in their designated phase regardless of damage sustained during the round.

After all phases complete and hits are applied:

1. **Casualty Assessment**: Mark all crippled and destroyed units (colony-owned and carrier-owned fighters tracked separately)
2. **Capacity Violation Checks**: Evaluate colonies for fighter capacity violations (only colony-owned fighters count toward capacity)
3. **Recalculate AS**: Determine total AS of all surviving Task Forces
4. **ROE Check**: Each Task Force evaluates retreat conditions independently according to [Section 7.1.1](#711-rules-of-engagement-roe)

**Multi-Faction Retreat Evaluation:**

When multiple houses are present in combat, each Task Force independently evaluates retreat by comparing its total combat strength against the combined strength of all hostile Task Forces.

To evaluate retreat:
1. Sum the total AS of all Task Forces identified as hostile per [Section 7.3.2.1](#7321-diplomatic-filtering)
2. Compare this combined hostile strength against the evaluating house's own Task Force strength
3. Apply morale modifier to effective ROE (see below)
4. Apply the modified ROE threshold from [Section 7.1.1](#711-rules-of-engagement-roe) to determine if retreat is warranted
5. Apply homeworld defense exception (see below)

**Homeworld Defense Exception:**

Houses never voluntarily retreat from their homeworld system regardless of ROE evaluation:
- If a house is defending their homeworld system (original starting colony per [Section 8.1.5](diplomacy.md#815-territorial-control)), that house's forces always remain and fight to the death
- Homeworld defense overrides all ROE thresholds and morale modifiers
- Forces are not destroyed by the exception; they fight normally but cannot choose to retreat
- Exception only prevents voluntary retreat; forces can still be destroyed in combat
- Rationale: Abandoning your capital is political suicide; admirals fight to the death defending the homeworld

Non-homeworld colonies follow standard ROE evaluation and may be tactically abandoned if ROE indicates retreat.

**Morale ROE Modifier:**

House morale affects combat behavior by modifying effective ROE for retreat evaluation. See [Table 9.4](reference.md#104-prestige) for morale level definitions.

| Morale Level     | Morale ROE Modifier | Effect                                      |
|:-----------------|:-------------------:|:--------------------------------------------|
| Collapsing       | -2                  | Retreat much more readily                   |
| VeryLow          | -1                  | Retreat more readily                        |
| Low              | 0                   | No modification                             |
| Normal           | 0                   | No modification                             |
| High             | +1                  | Fight more aggressively, retreat less often |
| VeryHigh         | +1                  | Fight more aggressively, retreat less often |
| Exceptional      | +2                  | Fight much more aggressively                |

**Application:**
- Effective ROE = Base ROE + Morale ROE Modifier
- Example: A fleet with ROE 6 (engage equal or inferior) and Exceptional morale has effective ROE 8 (engage even if outgunned 2:1)
- Example: A fleet with ROE 6 and Collapsing morale has effective ROE 4 (engage only if 2:1 advantage)
- Morale modifier applies only to retreat evaluation, not to fleet orders or diplomatic status
- Minimum effective ROE is 0 (flee from all combat), maximum is 10 (fight to the death)
- Homeworld defense exception overrides morale-modified ROE

One house retreating does not force other houses to retreat. Combat continues between remaining Task Forces.

**Multi-House Retreat Priority:**

When multiple houses attempt to retreat simultaneously:
1. Houses retreat in ascending order of total Task Force AS (weakest first)
2. When multiple houses have equal AS, retreat priority is determined by house ID (ascending alphanumeric order)
3. After each house retreats, remaining houses re-evaluate ROE against remaining hostile forces
4. Re-evaluation may cause a house to cancel its retreat and continue fighting
5. Process continues until all retreat decisions are finalized

**Simultaneous Retreat Resolution:**

If multiple Task Forces simultaneously attempt to retreat after Round 1, and re-evaluation confirms all still wish to retreat:
1. All houses evaluate retreat intentions simultaneously
2. If all hostile Task Forces attempt to retreat after re-evaluation, all successfully disengage
3. All retreating forces withdraw to their designated fallback systems
4. No combat occurs - treat as mutual withdrawal
5. No prestige is awarded or lost for mutual withdrawal

**Combat Duration Limit:**

If combat continues for 20 consecutive rounds without any squadron being destroyed, retreating, or state transition occurring:
1. All Task Forces are forced to disengage due to ammunition and fuel depletion
2. All forces withdraw per post-combat positioning rules below
3. No prestige is awarded for this engagement
4. This represents a tactical stalemate

**Combat Termination Conditions:**

Combat ends when any of the following conditions are met:

- Only one Task Force remains in the system
- All remaining Task Forces are non-hostile to each other per [Section 7.3.2.1](#7321-diplomatic-filtering)
- All Task Forces have retreated from the engagement
- Tactical stalemate declared after desperation round (see [Section 7.3.4.1](#7341-desperation-tactics))
- 20 consecutive rounds have elapsed without resolution (forced stalemate)

If combat reduces the engagement such that all remaining Task Forces are non-hostile to each other, combat immediately ceases even if multiple houses remain in the system. This occurs when all Enemy relationships have been eliminated through retreat or destruction, leaving only Neutral or Non-Aggression relationships.

If more than one hostile Task Force remains and no retreat occurs, proceed to the next combat round.

#### 7.3.4.1 Desperation Tactics

When combat stalls with neither side able to inflict damage, commanders resort to desperate, high-risk maneuvers in a final attempt to break the deadlock.

**Trigger Condition:**

If 5 consecutive combat rounds elapse without any squadron state changes (no squadrons crippled or destroyed), both Task Forces immediately execute one desperation round.

**Desperation Round:**

- Both Task Forces receive +2 CER modifier on all attack rolls
- This bonus applies to Ambush phase and Main Engagement phase
- The bonus stacks with all other modifiers (scouts, morale, surprise, ambush)
- Fighters are unaffected (they do not use CER rolls)

**Narrative:** Desperate commanders order aggressive, high-risk tactics: fighters commit to closer strafing runs despite increased exposure, capital ships drop auxiliary shields to redirect power to weapons, and cloaked raiders decloak for point-blank attack runs.

**Resolution:**

After the desperation round resolves:

- **If any squadron state changes occurred**: Reset the no-progress counter. Combat continues normally.
- **If no state changes occurred**: Declare **Tactical Stalemate** immediately. Combat ends with no victor.

**Tactical Stalemate vs Forced Stalemate:**

- **Tactical Stalemate**: Neither side can damage the other despite desperate tactics (triggers after desperation round fails)
- **Forced Stalemate**: Maximum combat duration reached (20 total rounds)

Both result in no victor and apply identical post-combat positioning rules.

**Post-Combat Positioning:**

After combat terminates but before Task Forces disband, determine final fleet positioning based on retreat evaluation and system ownership:

**If combat ended via retreat orders:**
- Forces that executed retreat orders arrive at their designated fallback systems per [Section 7.3.5](#735-retreat)
- Forces that remained in combat stay in the current system

**If combat ended without retreat execution (mutual withdrawal, stalemate, or total destruction of one side):**

Apply positioning rules based on system ownership status:

**1. Systems with Colony Present (Owned Systems):**

**System Owner Forces:**

**If Homeworld System:**
- Forces always remain in system (hold position 00)
- Cannot choose to retreat even if modified ROE indicates retreat
- Homeworld defense is absolute; admirals fight to the death
- Only exception: All forces destroyed in combat

**If Non-Homeworld Colony:**
- Remain in system and hold position (Fleet Order 00)
- Exception: If owner's modified ROE (base ROE + morale modifier) indicated retreat was desired, owner may choose to retreat to fallback system
- Owner forces never automatically abandon territory unless choosing to retreat

**Non-Owner Forces:**

Evaluate positioning based on whether owner forces remain present:

**If Owner Forces Present (Active Defense):**
- Non-owner forces cannot maintain presence while owner actively defends
- All non-owner forces must withdraw to their closest friendly system per [Section 7.3.5](#735-retreat)
- Rationale: Cannot occupy territory under active defense

**If Owner Forces Absent (No Active Defense):**
- If modified ROE indicated retreat: Execute retreat to fallback system per [Section 7.3.5](#735-retreat)
- If modified ROE indicated stay: Remain in system and hold position (Fleet Order 00)
- System state becomes "Under Siege" - non-owner forces may execute blockade (Fleet Order 05), bombardment (06), invasion (07), or blitz (08) orders
- Multiple non-owner houses may remain if all indicated stay (multi-faction siege)
- Rationale: Victorious forces can besiege undefended or abandoned colonies

**2. Contested Systems (No Colony Present):**

**All Forces:**
- If modified ROE indicated retreat: Execute retreat to fallback system per [Section 7.3.5](#735-retreat)
- If modified ROE indicated stay: Remain in system and hold position (Fleet Order 00)
- Multiple houses may remain simultaneously
- System remains contested until a house establishes colony via Fleet Order 12

**Forced Withdrawal Mechanics:**

When forces must withdraw (non-owner in owned system, or ROE-based retreat):
- Use retreat destination priority from [Section 7.3.5](#735-retreat)
- Crippled ships cannot use restricted lanes (must seek alternative routes)
- Carriers execute emergency withdrawal with all embarked fighters
- Crippled carriers can withdraw at full fighter capacity
- Withdrawing fighters cannot attack or be targeted during withdrawal
- Spacelift Command ships accompany their house's forces during withdrawal
- Spacelift ships are not destroyed during forced post-combat withdrawal

**System Control Status:**

After post-combat positioning, update system status for game state tracking:

- **Controlled**: Owner colony present, owner forces present
- **Undefended**: Owner colony present, no owner forces, no hostile forces
- **Under Siege**: Owner colony present, hostile forces present (may execute blockade/bombardment/invasion orders)
- **Contested**: No colony present (regardless of forces present)

System status changes do not transfer ownership. Ownership transfers only via successful planetary invasion per [Section 7.6](#76-planetary-invasion-blitz) or abandonment/destruction of colony.

### 7.3.5 Retreat

A Task Force may retreat from combat after the first round, in accordance with their ROE, and between rounds thereafter.

**Retreat Mechanics:**

Squadrons in a retreating Task Force fall back to their original fleet formations and flee to a friendly star system via available jump lanes. Friendly systems are those controlled by the retreating house via colony presence per [Section 8.1.5](diplomacy.md#815-territorial-control).

**Retreat Destination Priority:**

1. **Player-Designated Fallback**: If the fleet was assigned a fallback system during the Command Phase, retreat to that system
2. **Closest Friendly System**: If no designation exists, retreat to the closest friendly system without hostile forces present
3. **Next Tier Systems**: If all adjacent friendly systems contain hostile forces, retreat to systems 2 jumps away
4. **Fight to the Death**: If no valid retreat destination exists, the Task Force must continue fighting until destroyed

**No Retreat Sanctuary:**

Retreating fleets arriving in a new system do not receive sanctuary protection. If hostile forces are present at the retreat destination, the retreating fleet immediately engages in combat according to standard engagement rules. Fleets should plan retreat routes to avoid hostile territory.

**Retreat Restrictions:**

- Colony-owned fighters never retreat from combat
- If colony-owned fighters remain, they screen their retreating Task Force
- Combat continues until all colony-owned fighters are destroyed
- Spacelift Command ships are destroyed if their escort fleets are destroyed or retreat while hostile forces remain in the system per [Section 7.2](#72-task-force-assignment)
- Crippled ships can retreat normally through major and minor jump lanes
- Crippled ships cannot retreat through restricted lanes and must seek alternative routes

**Carrier-Owned Fighter Retreat:**

Carrier-owned fighters do not retreat independently. They retreat only when their carrier retreats.

**In Hostile/Neutral Systems:**
- Carrier-owned fighters withdraw with retreating carrier (emergency withdrawal, no re-embark time required)
- Crippled carriers can perform emergency withdrawal with carrier-owned fighters at full capacity
- Destroyed carriers result in all their embarked fighters being destroyed
- Fighters left behind (carrier destroyed during retreat) are destroyed

**In Friendly Systems:**
- Carrier-owned fighters withdraw with carrier (emergency withdrawal, no re-embark time)
- Carrier-owned fighters remain carrier-owned, do not transfer to colony
- Crippled carriers can perform emergency withdrawal with carrier-owned fighters at full capacity
**Colony-Owned Fighters:**
- Never retreat independently from combat
- Screen retreating friendly forces
- Fight until destroyed

**Withdrawing Fighter Combat Participation:**

Fighters withdrawing with retreating carriers do not participate in rearguard combat during the retreat round. They are considered to be embarking on their carriers and cannot attack or be targeted during the withdrawal process.

### 7.3.6 End of Space Combat

After the last round of combat and post-combat positioning is resolved per [Section 7.3.4](#734-rounds), surviving Task Forces disband and squadrons rejoin their original fleets at their current locations.

**Post-Combat Resolution:**

1. **Squadron Reorganization**: All squadrons return to their original fleet assignments at their current system locations
2. **Repair Requirements**: Crippled squadrons require shipyard repairs (1 turn, 25% of squadron PC)
3. **Carrier Fighter Re-embark**: Carrier-owned fighters temporarily deployed re-embark immediately after combat
4. **Fighter Capacity Violations**: Colonies exceeding fighter capacity limits begin the 2-turn grace period for resolving violations per [Section 2.4.1](assets.md#241-fighter-squadrons-carriers)
5. **System Control Status Update**: Update system control status based on post-combat positioning results (controlled/occupied/contested)

Destroyed ships cannot be salvaged from battle wreckage. Salvage operations apply only to active fleets intentionally decommissioned via Fleet Order 15 per [Section 6.2.16](#6216-salvage-15).

**Fighter Ownership After Combat:**

- Colony-owned fighters remain colony-owned
- Carrier-owned fighters re-embark immediately and remain carrier-owned
- No automatic ownership transfers occur as result of combat
- Players must execute permanent deployment procedure to transfer carrier-owned fighters to colony ownership (see [Section 2.4.1](assets.md#241-fighter-squadrons-carriers))

**Prestige Awards:**

Prestige is awarded after combat resolution:
- **FleetVictory** prestige for destroying an enemy Task Force (awarded to house that dealt crippling blow to final squadron) - see [Table 9.4](reference.md#104-prestige)
- **FleetVictory** prestige for forcing an enemy Task Force to retreat (divided among all engaged houses) - see [Table 9.4](reference.md#104-prestige)
- **StarbaseDestroyed** prestige for destroying an enemy Starbase - see [Table 9.4](reference.md#104-prestige)
- **StarbaseDestroyed** penalty for losing a Starbase - see [Table 9.4](reference.md#104-prestige)
- **DishonoredExpires** penalty for being ambushed by a cloaked fleet (if Raiders achieved surprise in Phase 1) - see [Table 9.4](reference.md#104-prestige)
- No prestige awarded or lost for mutual withdrawal, forced stalemate, or forced post-combat withdrawal

## 7.4 Orbital Combat

Orbital combat occurs when hostile fleets attack a defended colony after winning Space Combat (or if no mobile defenders were present). The defending house combines all available orbital forces into a unified defense.

**Attacker Composition:**
- Only fleets that survived Space Combat (if it occurred)
- Attackers with invasion/blitz orders (07, 08) must win Orbital Combat to proceed to planetary assault

**Orbital Defenders Include:**
- **Guard Fleets:** Active fleets with orders 04 or 05 (did not fight in space combat)
- **Reserve Fleets:** Orbital garrison with 50% AS/DS (per [Section 3.9](economy.md#39-maintenance-costs))
- **Mothballed Fleets:** Partially reactivated, 50% AS/DS (per [Section 3.9](economy.md#39-maintenance-costs))
- **Starbases:** Fixed defensive installations with special combat bonuses
- **Unassigned Squadrons:** Ships at colony not yet assigned to fleets
- **Screened Units (Non-Combatants):**
  - Spacelift ships (transport/colonization vessels)

Orbital defenders form a unified Task Force per [Section 7.2](#72-task-force-assignment).

### 7.4.1 Combat Resolution

Orbital combat uses the same mechanics as [Section 7.3](#73-space-combat) with these key differences:

**Detection vs Ambush:**
- **Detection Rolls:** ELI-equipped scouts and starbases attempt to detect cloaked Raiders (per [Section 7.1.3](#713-cloaking-and-detection))
- **Detection State Persistence:** Raiders detected in Space Combat remain detected (no new detection roll)
- **NO Ambush Bonus:** Undetected Raiders attack in Phase 1 but do NOT receive +4 CER modifier
- **Rationale:** Cannot ambush stationary orbital defenses waiting in prepared positions

**Reserve and Mothballed Fleet Penalties:**
- Reserve fleets fight at 50% of their normal AS/DS values
- Mothballed fleets fight at 50% of their normal AS/DS values (partial emergency reactivation)
- Still provide valuable defensive capability at reduced maintenance cost

**Starbase Special Rules:**
1. **Critical Hit Protection:** If a player rolls a critical hit against a Starbase on the first attempt, re-roll a second time. The second roll stands regardless of result.
2. **Starbase Bonus:** Starbases receive an extra +2 die roll modifier on all CER rolls.
3. **Starbase Detection Bonus:** Starbases receive +2 ELI modifier for pre-combat detection rolls against cloaked Raiders.
4. **Starbase State Transitions:** Starbases follow the same state transitions as squadrons (undamaged → crippled → destroyed) as defined in [Section 7.1.2](#712-combat-state).
5. **Starbase Targeting:** Starbases are assigned to bucket 5 and can be targeted using the rules in [Section 7.3.2](#732-target-priority-rules). Crippled Starbases receive the 2x targeting weight modifier.

Starbases are fortified with superior AI and sensors, making them formidable defensive platforms with high defensive capabilities.

### 7.4.2 Screened Unit Vulnerability

Spacelift ships do not participate in orbital combat - they are screened behind defending forces.

**Mothballed Fleet Emergency Reactivation:**

When orbital combat begins, mothballed fleets undergo emergency partial reactivation:
- Mothballed fleets fight at 50% AS/DS (same as reserve status)
- Emergency reactivation is automatic and immediate (no turn delay)
- After combat, surviving mothballed fleets return to mothballed status
- Allows desperate defense using stored ships without full reactivation cost

**If all orbital defenders are destroyed:**
- All spacelift ships at the colony are destroyed
- Spaceports become vulnerable to attack
- Colony is undefended and vulnerable to bombardment/invasion

**If any defenders survive:**
- Screened spacelift units remain safe
- Colony maintains orbital defense

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

<!-- SHIELD_EFFECTIVENESS_TABLE_START -->
| SLD Level | % Chance | 1D20 Roll | % of Hits Blocked |
|:---------:|:--------:|:---------:|:-----------------:|
| SLD1      | 15       | > 17      | 25%               |
| SLD2      | 30       | > 14      | 30%               |
| SLD3      | 45       | > 11      | 35%               |
| SLD4      | 60       | > 8      | 40%               |
| SLD5      | 75       | > 5      | 45%               |
| SLD6      | 90       | > 2      | 50%               |

*Source: config/combat.toml [planetary_shields] section*
<!-- SHIELD_EFFECTIVENESS_TABLE_END -->

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






