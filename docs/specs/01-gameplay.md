# 1.0 How to Play

# The Dynatoi

The *dynatoi* (δυνατοί - "the powerful") are the great houses that dominate known space. These ancient families control vast territories, command private fleets, and compete for power through conquest, alliances, and betrayal. Each house carries centuries of history, old grudges, and proud traditions.

## The Twelve Houses

**House Valerian**
The oldest of the *dynatoi*, claiming unbroken lineage from the First Expansion. Their ancestral palace orbits a dying red giant, and family tradition requires every heir to make a pilgrimage there before assuming leadership.

**House Thelon**
Rose to power during the Collapse Wars by playing all sides. Their motto translates roughly as "patience cuts deeper than blades." Other houses consider them untrustworthy but valuable allies.

**House Marius**
A martial dynasty that's produced more fleet admirals than any other house. Marius officers traditionally duel for command positions. Their war college is considered the finest in known space.

**House Kalan**
Merchant princes who built their fortune on monopolizing rare earth extraction in the Kalan Cluster. Marriages into other houses always include complex financial arrangements that benefit Kalan interests for generations.

**House Delos**
Founded by a legendary scientist-explorer who discovered the Delos Traverse. The house maintains an obsession with technological superiority and views other houses as provincial. Their ceremonial robes incorporate circuit patterns.

**House Stratos**
Conquered and absorbed three lesser houses in the past two centuries through strategic marriages and opportunistic invasions. They celebrate "Incorporation Day" annually, which offends the descendants of the absorbed families.

**House Nikos**
Known for internal power struggles that sometimes spill into open civil war between branches of the family. Despite chronic instability, they've held their core territories for eight centuries through sheer stubbornness.

**House Hektor**
Their ancestral homeworld was rendered uninhabitable three centuries ago by industrial collapse. Now scattered across multiple systems, Hektor gatherings are melancholic affairs focused on lost glory and eventual restoration.

**House Krios**
Began as frontier colonists who struck it rich finding habitable worlds in what others considered worthless space. They still maintain a frontier mentality and look down on the "soft" core-world houses.

**House Zenos**
Every generation produces one designated Philosopher-Heir who writes the official history and strategic doctrine. These texts are studied throughout the empire, giving Zenos outsized cultural influence despite modest military power.

**House Theron**
Survived five major invasions in their history by trading space for time and bleeding attackers dry. Theron commanders are legendarily cautious, earning them a reputation for cowardice among more aggressive houses.

**House Alexos**
The newest great house, elevated only three generations ago through a marriage alliance that united two middling families. The older *dynatoi* still treat them as upstarts, which Alexos takes as a personal insult requiring constant proof of legitimacy.

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

**Undefended Colony Penalty:** Losing a colony with NO ground defense (no armies, marines, or ground batteries) incurs a **+50% prestige penalty**. This represents the dishonor of leaving your citizens defenseless. Planetary shields alone do NOT count as "defended" - shields buy time but don't stop invasions. At least one army, marine, or ground battery is required to avoid the penalty.

- **Defended colony lost**: -50 prestige (base, scaled by map size)
- **Undefended colony lost**: -75 prestige (base × 1.5, scaled by map size)

Flexibility and strategic foresight are your greatest tools. Use every resource and opportunity to crush your rivals and ensure your House's dominance.

<!-- STARTING_PRESTIGE_START -->

You start the game with 100 prestige points.

<!-- STARTING_PRESTIGE_END -->

If your House's prestige drops below zero and stays there for three consecutive turns, your empire enters Defensive Collapse and you are permanently eliminated. See [Section 1.4](#14-player-elimination--autopilot) for complete elimination and autopilot mechanics.

### Dynamic Prestige Scaling

**How it works:**

- **Small maps** (8-10 systems per player): You earn **full** prestige values listed in the tables → games last ~30 turns
- **Large maps** (30+ systems per player): You earn **scaled** prestige per action → games last ~60-80 turns

**Why?** More territory means more turns needed to conquer everything. Lower prestige per action on large maps means you need more victories to reach 2500, perfectly matching the longer conquest timeline.

**Example:** On a small map, colonizing a planet awards 50 prestige. On a large map, the same action awards 20 prestige. 

**For You:** The game calculates scaling automatically when the map generates. Larger maps mean longer campaigns—plan accordingly.

See [Section 10.4](10-reference.md#104-prestige) for mathematical details.

---

## 1.2 Game Setup

At game start, one player spins up the game server. The server becomes your impartial arbiter—tireless, incorruptible, and instant. It processes turn commands, resolves conflicts, calculates economics, and maintains fog of war without human error or bias.

**Localhost Mode (Tabletop Sessions):**

Run the server on one machine. Everyone else connects from their laptops over the local network. You're gathered around the table, commanding your empires, while the server handles the tedious mathematics. No more spreadsheet errors. No more arguments about combat resolution. The machine does the bookwork; you make the decisions.

**Nostr Mode (Remote Play):**

Deploy the server anywhere with Nostr relay access. Your friends connect from across the world. Submit your turn commands at 3 AM or during lunch break—the asynchronous architecture doesn't care. The Nostr protocol provides cryptographic verification ensuring nobody tampers with turn submissions. When all players finish (or the 24-hour deadline expires), the server processes the next cycle automatically.

**What The Server Handles:**

The game server executes every tedious task a human moderator would handle:

- Processes turn commands from all Houses simultaneously
- Resolves space battles, invasions, bombardments, and espionage operations
- Calculates economic production, population growth, and prestige changes
- Advances construction projects and research investments
- Maintains separate intelligence databases—you see only what your scouts discover
- Issues customized reports showing your empire's status and gathered intelligence
- Enforces fog of war rigorously—no information leakage between players
- Tracks turn deadlines and activates autopilot for missing commanders

**Map Generation:**

Config files define the number of players and map size. The map size is set by the number of hexagonal rings centered around the hub system.

**Your Starting Position:**

You begin with a foundation for empire:

**Homeworld**: Abundant Eden planet, Level V colony with 840 PU
**Treasury**: 1000 production points (PP)
**Infrastructure**: One spaceport, one shipyard, one drydock
**Industrial Capacity**: 420 IU (0.5 × PU)
**Fleet**: Two Light Cruisers (each escorting an ETAC), two Destroyers
**Colonization**: Two ETACs loaded with colonists (3 PTU each, foundation colonies)
**Scouts**: None—build these immediately
**Tax Rate**: 50% (you'll want to adjust this)

**Starting Technology:**

Your House begins at technology tier 1 across all domains: EL1, SL1, CST1, WEP1, TER1, ELI1, FC I, SC I, FD I, ACO I. Every House starts equal. Your research priorities determine how quickly you advance. See [Section 4.0](04-research_development.md#40-research-development) for tech effects and [Section 10.11](10-reference.md#1011-technology-research) for advancement costs.

**Diplomacy & Communication:**

The server processes commands mechanically but doesn't handle diplomacy. You negotiate alliances, betray pacts, and coordinate strategies through your preferred communication method—Discord, Signal, email, or face-to-face trash talk at the table. The server doesn't care how you scheme; it only processes the commands you submit. Diplomacy is between humans. The server just enforces the consequences.

---

## 1.3 Turns

Each turn comprises four phases, representing a complete cycle of player action and server resolution. From a player's perspective, the sequence is:

1.  **Command Phase:** You issue commands.
2.  **Production Phase:** The server processes construction and fleet movement.
3.  **Conflict Phase:** The server resolves combat based on the new fleet positions.
4.  **Income Phase:** The server calculates economic results, and the turn's results are presented.

### 1.3.1 Command Phase

In the command phase, you issue fleet commands ([Section 6.3](06-operations.md#63-fleet-commands)) and make strategic decisions around asset management. You can change diplomatic status ([Section 8.1](08-diplomacy.md#81-diplomacy)) toward rival Houses.

You also decide which construction commands to place and where to invest production points in R&D, industry, terraforming, population movement, espionage, and savings. You can change your tax rate during this phase.

You submit your turn commands to the game server. Once all players submit (or the turn deadline expires), the server begins processing the next phases of the turn cycle.

### 1.3.2 Production Phase

In the production phase, the game server advances construction projects, applies repairs to damaged facilities, and processes upkeep costs. Fleet maintenance is deducted from your house treasury. Your fleets execute their movement commands, positioning them for the next phase.

New construction commands process, along with investments in R&D, terraforming, Space Guild services, and industry.

The server updates the master game state but does not yet issue reports.

### 1.3.3 Conflict Phase

At the beginning of this phase, the game server resolves all military actions. Fleets that moved in the Production Phase now engage in combat. Planetary bombardment, invasions, and espionage activities process automatically according to the rules engines.

**This phase happens AFTER movement** so that fleets can engage in their new locations. Infrastructure damage from combat applies to colonies, shipyards, and starbases before economic calculations in the next phase.

### 1.3.4 Income Phase

After conflict resolution, all economic factors ([Section 3](03-economy.md#30-economics)) are recalculated and production points are deposited in your house treasury. Production calculates **after** conflict, accounting for infrastructure damage from bombardment or invasion.

This phase also accounts for population growth at each colony. Your House prestige points are recalculated and updated.

At the end of this phase, the turn is complete. The server issues updated game state reports to each player for the new turn. Each House receives customized data showing only their own assets and gathered intelligence—fog of war is maintained automatically. You receive new reports reflecting updated economics and the outcome of the turn's military actions.

---

## 1.4 Player Elimination & Autopilot

### 1.4.1 Prestige Failure (Defensive Collapse)

If your House's prestige drops below zero and stays there for three consecutive turns, your empire enters **Defensive Collapse** and you are permanently eliminated.

**Defensive Collapse Behavior:**

- All your fleets immediately return to the nearest controlled system
- Your fleets defend colonies against attacks from Enemy-status houses per [Section 8.1.4](diplomacy.md#814-enemy)
- No offensive operations or expansion
- No new construction commands
- No diplomatic changes
- Economy ceases (no income, no R&D, no maintenance costs)

Your collapsed empire remains on the map as a defensive AI target. Other players can conquer your colonies and destroy your fleets for prestige as normal. Defensive Collapse is permanent—you cannot rejoin the game.

### 1.4.2 MIA Autopilot

If you fail to submit commands for three consecutive turns, your empire automatically enters **Autopilot** mode. Unlike Defensive Collapse, autopilot is temporary and you can rejoin at any time.

**Autopilot Behavior:**

- Your fleets continue executing standing commands until completion
- Fleets without active commands patrol and defend home systems
- Your economy continues operating (current tax rate and R&D allocations maintained)
- Construction focuses on defensive infrastructure and essential facilities
- No new offensive operations or colonization attempts
- Diplomatic stances remain unchanged
- Engages Enemy-status houses that enter controlled territory per [Section 8.1.4](08-diplomacy.md#814-enemy)

When you return and submit new commands, your empire immediately exits autopilot and resumes normal operations.

**Turn Processing:**

- Autopilot activates in the Income Phase after the third consecutive missed turn per [Section 1.3.2](#132-income-phase)
- Autopilot commands execute during the Command Phase per [Section 1.3.3](#133-command-phase)
- You can resume control in any subsequent turn by submitting commands

### 1.4.3 Standard Elimination & Last-Stand Invasions

Your House is eliminated from the game when you lose all colonies AND have no invasion capability remaining.

**Elimination Triggers:**

1. **Total Defeat**: No colonies AND no fleets
2. **Hopeless Position**: No colonies AND no marines for reconquest

**Last-Stand Invasion Capability:**

If you lose all your colonies but retain fleets with loaded marine divisions, you can attempt desperate reconquest operations:

- **Invasion Orders**: Target enemy colonies per [Section 7.6.1](07-combat.md#761-planetary-invasion)
- **Blitz Operations**: Execute high-risk planetary assaults per [Section 7.6.2](07-combat.md#762-planetary-blitz)
- **No Elimination**: Your House remains active as long as marines exist on transports
- **Empty Transports**: If you have only empty transports or non-combat ships, you are eliminated

**Example Last-Stand Scenario:**

House Atreides controls 15 systems. House Harkonnen launches a massive offensive and conquers all 15 colonies in a single turn. However, three Atreides troop transports carrying marine divisions survive the onslaught in deep space.

**Result:** House Atreides is NOT eliminated. On the next turn, they can attempt invasion/blitz operations with their surviving marines. If they successfully recapture even one colony, they're back in the game. If all marines are killed in failed invasions, THEN they're eliminated.

This creates dramatic comeback opportunities and rewards players who maintain mobile invasion forces even when losing territory.

### 1.4.4 Victory Conditions

You achieve victory through one of two conditions:

**1. Turn Limit Victory**: When the maximum turn limit is reached, the House with the highest prestige wins. Prestige accumulation scales dynamically with map size per [Section 1.1](#11-prestige).

**2. Military Victory**: Be the last active House standing—all rivals eliminated through conquest or defensive collapse.

**Player Status for Victory:**

- **Active Players**: Players submitting commands (not in autopilot or defensive collapse)
- **Autopilot Players**: Count as active and can return to win
- **Defensive Collapse Players**: Eliminated, do not count toward victory
- **Last-Stand Players**: Count as active until final elimination

A player in autopilot can still win through prestige accumulation if their empire's defensive economy generates sufficient prestige growth. When the turn limit is reached, autopilot empires compete for victory based on final prestige.

**Final Conflict Rule:**

When only two active players remain in the game (excluding Defensive Collapse and Autopilot empires), their diplomatic status automatically converts to Enemy per [Section 8.1.4](08-diplomacy.md#814-enemy) and cannot be changed. Neutral status cannot be established. There can be only one Emperor—the final two houses must fight for the throne. This rule takes effect at the start of the Income Phase when the condition is detected.

---

## 1.5 Intelligence & Fog of War

EC4X employs fog of war mechanics where you have limited visibility into rival empires' activities. Intelligence gathering is critical for strategic planning and tactical operations.

### 1.5.1 Fleet Encounters and Intelligence

When your fleets encounter forces from different houses in the same system, intelligence is automatically gathered regardless of diplomatic status or whether combat occurs.

**Automatic Intelligence Reporting:**

Whenever your friendly fleets are present in the same system as foreign forces, you receive **Visual quality** intelligence reports containing:

- Fleet composition (ship types and squadron sizes)
- Number of spacelift ships (transport count)
- Standing commands (Patrol, Guard, Blockade, etc.)
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

See [Section 9.6](09-intel-espionage.md#96-intelligence-quality-levels) for complete quality level specifications.

**Intelligence Collection Scenarios:**

You gather intelligence in all of the following situations:

- **Patrol operations**: Visual quality fleet intel per [Section 6.2.4](06-operations.md#624-patrol-a-system-03)
- **Fleet movement**: Visual quality intel when passing through systems with foreign forces
- **Combat engagements**: Perfect quality intel revealed pre-combat for all participants
- **Scout reconnaissance**: Perfect quality intel from missions per [Section 6.2.9-6.2.12](06-operations.md#629-spy-on-a-planet-09)
- **Espionage operations**: Spy quality intel from SpyOnPlanet, SpyOnSystem, HackStarbase

**Diplomatic Status Independence:**

You gather intelligence regardless of diplomatic relationships:

- Enemy forces: Intelligence gathered, combat may occur
- Hostile forces: Intelligence gathered, combat may occur
- Neutral forces: Intelligence gathered, combat only if threatening commands are present

This reflects the reality that military forces cannot remain completely hidden when operating in the same system, even if diplomatic protocols prevent engagement.

**Intelligence Reports:**

All intelligence is stored in your house's intelligence database with timestamps. See [Section 9](09-intel-espionage.md) for complete intelligence system documentation including:

- Report types and contents
- Intelligence corruption from disinformation/dishonor
- Staleness indicators
- Strategic use of intelligence

### 1.5.2 Fog of War

You do not have automatic visibility into:

- Rival empire economics (income, production, treasury)
- Rival empire technology levels (requires espionage per [Section 9.2](09-intel-espionage.md#92-subversion--subterfuge))
- Fleet movements in systems without your friendly presence
- Colony development and construction projects
- Strategic intentions and future commands

The game server maintains separate intelligence databases for each house to preserve fog of war. You must actively gather intelligence through fleet operations, scout missions, and espionage activities. The server ensures you see only what your House has legitimately discovered—no information leakage between players.

---
