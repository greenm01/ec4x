# 1.0 How to Play

## 1.1 Prestige

Victory in EC4X is achieved through prestige accumulation—the ultimate measure of your House's dominance. Command your path to the imperial throne:

- **Total Warfare**: Annihilate rival military assets through devastating fleet engagements
- **Planetary Conquest**: Seize homeworlds and colonies through invasion and occupation
- **Strategic Subjugation**: Break the spirit of your adversaries and compel their surrender
- **Covert Operations**: Blend military might with espionage, subversion, and cunning to outmaneuver your foes
- **Economic Dominance**: Focus on growth and expansion, using prosperity to overwhelm rivals
- **Last Man Standing**: Survive and eliminate all opposition
- **Hybrid Strategy**: Employ all methods simultaneously

Every action influences your House's prestige. Military victories enhance it directly. A prosperous and growing economy strengthens it. Technological advancements demonstrate your House's sophistication. All elevate your standing.

Poor colony management tarnishes your legacy. Exposure to rival covert operations leads to public disgrace. Diplomatic betrayal brings dishonor.

**Zero-Sum Competition:** EC4X models the brutal reality of Imperial politics. When you defeat an enemy in battle, **your prestige rises while theirs falls by an equal amount**. Combat, espionage, and invasions are winner-takes-all: your gains come directly from your opponent's losses. This ensures losers don't just slow down—they actively decline. Only one house can rule the Imperium.

Non-competitive achievements (colony establishment, technological research, good governance) still provide absolute prestige gains. But military dominance is the path to victory: **when one house rises, another must fall**.

Flexibility and strategic foresight are your greatest tools. Use every resource and opportunity to crush your rivals and ensure your House's dominance.

<!-- STARTING_PRESTIGE_START -->

You start the game with 50 prestige points.

<!-- STARTING_PRESTIGE_END -->

If your House's prestige drops below zero and stays there for three consecutive turns, your empire enters Defensive Collapse and you are permanently eliminated. See [Section 1.4](#14-player-elimination--autopilot) for complete elimination and autopilot mechanics.

### Dynamic Prestige Scaling

**The Challenge:** Victory requires 2500 prestige. If prestige awards are fixed, small maps finish too quickly and large maps drag on forever.

**The Solution:** Prestige awards automatically scale based on map size.

**How it works:**

- **Small maps** (8-10 systems per player): You earn **full** prestige values listed in the tables → games last ~30 turns
- **Large maps** (30+ systems per player): You earn **scaled** prestige per action → games last ~60-80 turns

**Why?** More territory means more turns needed to conquer everything. Lower prestige per action on large maps means you need more victories to reach 2500, perfectly matching the longer conquest timeline.

**Example:** On a small map, colonizing a planet awards 50 prestige. On a large map, the same action awards 20 prestige. Both maps reach 2500 prestige around the time all territory is conquered.

**For You:** The game calculates scaling automatically when the map generates. Larger maps mean longer campaigns—plan accordingly.

See [Section 10.4](reference.md#104-prestige) for mathematical details.

---

## 1.2 Game Setup

At game start, one player spins up the game server. The server becomes your impartial arbiter—tireless, incorruptible, and instant. It processes turn orders, resolves conflicts, calculates economics, and maintains fog of war without human error or bias.

**Localhost Mode (Tabletop Sessions):**

Run the server on one machine. Everyone else connects from their laptops over the local network. You're gathered around the table, commanding your empires, while the server handles the tedious mathematics. No more spreadsheet errors. No more arguments about combat resolution. The machine does the bookwork; you make the decisions.

**Nostr Mode (Remote Play):**

Deploy the server anywhere with Nostr relay access. Your friends connect from across the world. Submit your turn orders at 3 AM or during lunch break—the asynchronous architecture doesn't care. The Nostr protocol provides cryptographic verification ensuring nobody tampers with turn submissions. When all players finish (or the 24-hour deadline expires), the server processes the next cycle automatically.

**What The Server Handles:**

The game server executes every tedious task a human moderator would handle:

- Processes turn orders from all Houses simultaneously
- Resolves space battles, invasions, bombardments, and espionage operations
- Calculates economic production, population growth, and prestige changes
- Advances construction projects and research investments
- Maintains separate intelligence databases—you see only what your scouts discover
- Issues customized reports showing your empire's status and gathered intelligence
- Enforces fog of war rigorously—no information leakage between players
- Tracks turn deadlines and activates autopilot for missing commanders

**Map Generation:**

Generate your star map using the tools provided in the GitHub repository (see [Section 2.1](assets.md#21-star-map)). The server loads the map at game initialization. Map size determines prestige scaling automatically—larger maps mean longer campaigns.

**Your Starting Position:**

You begin with a foundation for empire:

**Homeworld**: Abundant Eden planet, Level V colony with 840 PU  
**Treasury**: 1000 production points (PP)  
**Infrastructure**: One spaceport, one shipyard  
**Industrial Capacity**: 420 IU (0.5 × PU)  
**Fleet**: Two Light Cruisers, two Destroyers  
**Colonization**: Two ETACs loaded with colonists  
**Scouts**: None—build these immediately  
**Tax Rate**: 50% (you'll want to adjust this)

**Starting Technology:**

Your House begins at technology tier 1 across all domains: EL1, SL1, CST1, WEP1, TER1, ELI1, CIC1, FD I, ACO I. Every House starts equal. Your research priorities determine how quickly you advance. See [Section 4.0](economy.md#40-research--development) for tech effects and [Section 10.11](reference.md#1011-technology-research) for advancement costs.

**Diplomacy & Communication:**

The server processes orders mechanically but doesn't handle diplomacy. You negotiate alliances, betray pacts, and coordinate strategies through your preferred communication method—Discord, Signal, email, or face-to-face trash talk at the table. The server doesn't care how you scheme; it only processes the orders you submit. Diplomacy is between humans. The server just enforces the consequences.

---

## 1.3 Turns

Each turn comprises four phases:

1. Conflict Phase
2. Income Phase
3. Command Phase
4. Maintenance Phase

### 1.3.1 Conflict Phase

At the beginning of each turn, the game server resolves all military actions from the previous turn. Combat, planetary bombardment, invasions, and espionage activities process automatically according to the rules engines.

**This phase happens FIRST** so damaged infrastructure affects production in the Income Phase. Bombarded planets produce less. Destroyed shipyards cannot build ships. Damaged starbases provide reduced bonuses.

Space battles, orbital bombardment, ground invasions, and espionage operations all resolve during this phase. Infrastructure damage applies to colonies, shipyards, and starbases before economic calculations.

### 1.3.2 Income Phase

After conflict resolution, all economic factors ([Section 3](economy.md#30-economics)) are recalculated and production points deposited in your house treasury. Production calculates **after** conflict, accounting for infrastructure damage from bombardment or invasion.

This phase accounts for population growth at each colony, construction progress, maintenance costs, taxes, and R&D. Your House prestige points are recalculated and updated. The game server processes these calculations automatically using the master game state.

The server issues updated game state to each player for the new turn. Each House receives customized data showing only their own assets and gathered intelligence—fog of war is maintained automatically.

You receive new reports reflecting updated economics and the outcome of military orders issued in the previous turn. Access these reports through your game client.

In the new turn, you decide which construction orders to place and where to invest production points in R&D, industry, terraforming, population movement, espionage, and savings. You can change your tax rate during this phase. Your client updates your local game state accordingly.

### 1.3.3 Command Phase

In the command phase, you issue fleet orders ([Section 6.2](operations.md#62-fleet-orders)) and make strategic decisions around asset management. You can change diplomatic status ([Section 8.1](diplomacy.md#81-diplomacy)) toward rival Houses.

Build orders may fail if shipyards were destroyed in the conflict phase. You issue fleet movement and colonization orders for execution in the next turn's conflict phase.

You submit your turn orders to the game server. Once all players submit (or the turn deadline expires), the server processes the next turn cycle.

### 1.3.4 Maintenance Phase

In the maintenance phase, the game server advances construction projects, applies repairs to damaged facilities, and processes upkeep costs. Fleet maintenance is deducted from your house treasury.

New construction orders process, along with investments in R&D, terraforming, Space Guild services, and industry.

The server updates game state and issues customized reports to each player. You receive your own unique intelligence database, blind to other players' activities.

---

## 1.4 Player Elimination & Autopilot

### 1.4.1 Prestige Failure (Defensive Collapse)

If your House's prestige drops below zero and stays there for three consecutive turns, your empire enters **Defensive Collapse** and you are permanently eliminated.

**Defensive Collapse Behavior:**

- All your fleets immediately return to the nearest controlled system
- Your fleets defend colonies against attacks from Enemy-status houses per [Section 8.1.4](diplomacy.md#814-enemy)
- No offensive operations or expansion
- No new construction orders
- No diplomatic changes
- Economy ceases (no income, no R&D, no maintenance costs)

Your collapsed empire remains on the map as a defensive AI target. Other players can conquer your colonies and destroy your fleets for prestige as normal. Defensive Collapse is permanent—you cannot rejoin the game.

### 1.4.2 MIA Autopilot



If you fail to submit orders for three consecutive turns, your empire automatically enters **Autopilot** mode. Unlike Defensive Collapse, autopilot is temporary and you can rejoin at any time.

**Autopilot Behavior:**

- Your fleets continue executing standing orders until completion
- Fleets without active orders patrol and defend home systems
- Your economy continues operating (current tax rate and R&D allocations maintained)
- Construction focuses on defensive infrastructure and essential facilities
- No new offensive operations or colonization attempts
- Diplomatic stances remain unchanged
- Engages Enemy-status houses that enter controlled territory per [Section 8.1.4](diplomacy.md#814-enemy)

When you return and submit new orders, your empire immediately exits autopilot and resumes normal operations.

**Turn Processing:**

- Autopilot activates in the Income Phase after the third consecutive missed turn per [Section 1.3.2](#132-income-phase)
- Autopilot orders execute during the Command Phase per [Section 1.3.3](#133-command-phase)
- You can resume control in any subsequent turn by submitting orders

### 1.4.3 Standard Elimination & Last-Stand Invasions

Your House is eliminated from the game when you lose all colonies AND have no invasion capability remaining.

**Elimination Triggers:**

1. **Total Defeat**: No colonies AND no fleets
2. **Hopeless Position**: No colonies AND no marines for reconquest

**Last-Stand Invasion Capability:**

If you lose all your colonies but retain fleets with loaded marine divisions, you can attempt desperate reconquest operations:

- **Invasion Orders**: Target enemy colonies per [Section 7.6](operations.md#76-planetary-invasion)
- **Blitz Operations**: Execute high-risk planetary assaults per [Section 7.6.2](operations.md#762-blitz)
- **No Elimination**: Your House remains active as long as marines exist on transports
- **Empty Transports**: If you have only empty transports or non-combat ships, you are eliminated

**Example Last-Stand Scenario:**

House Atreides controls 15 systems. House Harkonnen launches a massive offensive and conquers all 15 colonies in a single turn. However, three Atreides troop transports carrying marine divisions survive the onslaught in deep space.

**Result:** House Atreides is NOT eliminated. On the next turn, they can attempt invasion/blitz operations with their surviving marines. If they successfully recapture even one colony, they're back in the game. If all marines are killed in failed invasions, THEN they're eliminated.

This creates dramatic comeback opportunities and rewards players who maintain mobile invasion forces even when losing territory.

### 1.4.4 Victory Conditions

You achieve victory by reaching 2500 prestige or by being the last active player in the game.

- **Active Players**: Players submitting orders (not in autopilot or defensive collapse)
- **Autopilot Players**: Count as active and can return to win
- **Defensive Collapse Players**: Eliminated, do not count toward victory
- **Last-Stand Players**: Count as active until final elimination

A player in autopilot can still win through prestige accumulation if their empire's defensive economy generates sufficient prestige growth.

**Final Conflict Rule:**

When only two active players remain in the game (excluding Defensive Collapse and Autopilot empires), their diplomatic status automatically converts to Enemy per [Section 8.1.4](diplomacy.md#814-enemy) and cannot be changed. Non-Aggression Pacts dissolve. Neutral status cannot be established. There can be only one Emperor—the final two houses must fight for the throne. This rule takes effect at the start of the Income Phase when the condition is detected.

---

## 1.5 Intelligence & Fog of War

EC4X employs fog of war mechanics where you have limited visibility into rival empires' activities. Intelligence gathering is critical for strategic planning and tactical operations.

### 1.5.1 Fleet Encounters and Intelligence

When your fleets encounter forces from different houses in the same system, intelligence is automatically gathered regardless of diplomatic status or whether combat occurs.

**Automatic Intelligence Reporting:**

Whenever your friendly fleets are present in the same system as foreign forces, you receive **Visual quality** intelligence reports containing:

- Fleet composition (ship types and squadron sizes)
- Number of spacelift ships (transport count)
- Standing orders (Patrol, Guard, Blockade, etc.)
- Fleet location (current system)

**Visual Intelligence Limitations:**

Visual quality intelligence does NOT reveal:

- ❌ Tech levels (always shows as 0)
- ❌ Hull integrity/damage status
- ❌ Cargo contents of transport ships (only count visible)

This represents tactical observation—you can see what ships are present and their behavior, but not their technological sophistication or strategic cargo.

**Intelligence Quality Levels:**

EC4X uses four intelligence quality tiers:

1. **Visual** (Regular Fleets) - Basic tactical observation, ship types visible but not tech/damage
2. **Spy** (Espionage Operations) - High-quality intel with tech levels, hull status, economic data
3. **Perfect** (Scouts & Owned Assets) - Complete accuracy, all details, real-time updates
4. **None** (Fog of War) - No intelligence available

See [Section 9.3](intelligence.md#93-intelligence-quality-levels) for complete quality level specifications.

**Intelligence Collection Scenarios:**

You gather intelligence in all of the following situations:

- **Patrol operations**: Visual quality fleet intel per [Section 6.2.4](operations.md#624-patrol-a-system-03)
- **Fleet movement**: Visual quality intel when passing through systems with foreign forces
- **Combat engagements**: Perfect quality intel revealed pre-combat for all participants
- **Scout reconnaissance**: Perfect quality intel from missions per [Section 6.2.9-6.2.12](operations.md#629-spy-on-a-planet-09)
- **Espionage operations**: Spy quality intel from SpyOnPlanet, SpyOnSystem, HackStarbase

**Diplomatic Status Independence:**

You gather intelligence regardless of diplomatic relationships:

- Enemy forces: Intelligence gathered, combat may occur
- Neutral forces: Intelligence gathered, no combat
- Non-Aggression partners: Intelligence gathered, no combat (unless pact violated)

This reflects the reality that military forces cannot remain completely hidden when operating in the same system, even if diplomatic protocols prevent engagement.

**Intelligence Reports:**

All intelligence is stored in your house's intelligence database with timestamps. See [Section 9](intelligence.md) for complete intelligence system documentation including:

- Report types and contents
- Intelligence corruption from disinformation/dishonor
- Staleness indicators
- Strategic use of intelligence

### 1.5.2 Fog of War

You do not have automatic visibility into:

- Rival empire economics (income, production, treasury)
- Rival empire technology levels (requires espionage per [Section 8.2](diplomacy.md#82-subversion--subterfuge))
- Fleet movements in systems without your friendly presence
- Colony development and construction projects
- Strategic intentions and future orders

The game server maintains separate intelligence databases for each house to preserve fog of war. You must actively gather intelligence through fleet operations, scout missions, and espionage activities. The server ensures you see only what your House has legitimately discovered—no information leakage between players.

---
