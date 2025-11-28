# 1.0 How to Play

## 1.1 Prestige

Victory in EC4X is achieved through the accumulation of prestige, which is the ultimate measure of a House's dominance. Here are some strategic pathways to ascend to the throne of Emperor:

- Engage in total warfare to annihilate the military assets of your rivals.
- Seize homeworlds and colonies through planetary conquest.
- Break the spirit of your adversaries, compelling them to surrender.
- Blend military might with espionage, subversion, and cunning to outfox your foes.
- Focus on economic growth and population expansion, using prosperity to dominate.
- Be the last man standing.
- Adopt a hybrid strategy, employing a mix of all the above.

Every action in the game influences your House's prestige. Military victories directly enhance it, a prosperous and growing economy strengthens it, and technological advancements demonstrate your House's cunning, all of which elevate your standing.

Poor colony management will tarnish your House's legacy, while over-exposure to covert operations by rivals can lead to public disgrace.

Flexibility and strategic foresight are your greatest tools in the quest for power. Use every resource and opportunity the game provides to crush your rivals and ensure the dominance of your House.

<!-- STARTING_PRESTIGE_START -->
Players start the game with 50 prestige points.
<!-- STARTING_PRESTIGE_END -->

If a House's prestige drops and stays below zero for three consecutive turns, the empire enters Defensive Collapse and the player is permanently eliminated. See [Section 1.4](#14-player-elimination--autopilot) for full elimination and autopilot mechanics.

### Dynamic Prestige Scaling

**The Problem:** Victory requires 2500 prestige. If prestige awards are fixed, small maps finish too fast and large maps take forever.

**The Solution:** Prestige awards automatically adjust based on map size.

**How it works:**
- **Small maps** (8-10 systems per player): You get the **full** prestige values listed in the tables → games last ~30 turns
- **Large maps** (30+ systems per player): You get **less** prestige per action (automatically scaled down) → games last ~60-80 turns

**Why?** More territory = more turns needed to conquer everything. Lower prestige per action means you need more victories to hit 2500, which perfectly matches the longer conquest time.

**Example:** On a small map, colonizing a planet gives you 50 prestige. On a large map, the same action might only give 20 prestige. This way, both maps reach 2500 prestige around the time all territory is conquered.

**For Players:** You don't need to do anything - the game calculates this automatically when the map is created. Just know that larger maps = longer campaigns!

See [Section 10.4](reference.md#104-prestige) for the mathematical details.

## 1.2 Game Setup

At the start of a game, players will agree upon and designate a game moderator. The moderator's function is to collect player turn orders, update the master game database, and reissue updated game data back to players at the beginning of each turn. Software tools will be provided to make this a smooth process and maintain fog of war. The moderator would have to go out of their way to cheat, and deconstructing and analyzing the game data would not be an enjoyable task. Regardless, choose a game moderator with integrity. EC4X is intended to be played among friends.[^1]

[^1]: Future iterations of the game will allow for a server/client model, but not everyone will want to setup a dedicated server. Encrypting the game data is also a feature to be integrated.

Communicating with other players over email or in a dedicated chat room is recommended. There are plenty to choose from.

Generate a star-map as described in [Section 2.1](assets.md#21-star-map) for the selected number of players. Resources will be provided in the GitHub repo to spawn a map.

Players start the game with one homeworld (An Abundant Eden planet, Level V colony with 840 PU), 1000 production points (PP) in the treasury, one spaceport, one shipyard, two fully loaded ETAC, 2 Light Cruiser, two Destroyers, and 0 Scouts. The tax rate is set to 50% by default.

**All technology levels start at level 1** (EL1, SL1, CST1, WEP1, TER1, ELI1, CIC1, FD I, ACO I). See [Section 4.0](economy.md#40-research--development) for complete starting tech details and effects, and [Section 10.11](reference.md#1011-technology-research) for tech advancement tables.

## 1.3 Turns

Each turn comprises four phases

1. Conflict phase
2. Income phase
3. Command phase
4. Maintenance phase

### 1.3.1 Conflict Phase

At the beginning of each turn, the game moderator will resolve all military actions from the previous turn. Game software will resolve combat, planetary bombardment, invasions, and espionage activities.

**This phase happens FIRST** so that damaged infrastructure affects production in the Income phase. Bombarded planets produce less, destroyed shipyards cannot build ships, and damaged starbases provide reduced bonuses.

Space battles, orbital bombardment, ground invasions, and espionage operations are all resolved during this phase. Infrastructure damage is applied to colonies, shipyards, and starbases before economic calculations.

### 1.3.2 Income Phase

After conflict resolution, all economic factors ([Section 3](economy.md#30-economics)) are recalculated and production points deposited in house treasuries. Production is calculated **after** conflict, accounting for any infrastructure damage from bombardment or invasion.

This phase accounts for population growth for each colony, construction, maintenance costs, taxes, R&D, etc. House prestige points are recalculated and updated. This will be completed by the game moderator using blind software tools and maintained in a master game database.

Updated player databases, unique to each House, are reissued by the game moderator for the new turn. Various tools and database formats can be used to perform this step, including Excel or client game software.

Players receive new reports that reflect updated economics and the outcome of military orders issued in the previous turn. This can be achieved through email, on a server, or locally on a laptop for tabletop play.

In the new turn, players decide which construction orders to place and where to invest production points in R&D, industry, terraforming, population movement, espionage, and savings ([Section 3.8](economy.md#38-expenditures)). The tax rate can be changed in this phase. Player local databases are updated accordingly.

### 1.3.3 Command Phase

In the command phase, players issue fleet orders ([Section 6.2](operations.md#62-fleet-orders)) and make strategic decisions around asset management. Players have the opportunity change diplomatic state ([Section 8.1](diplomacy.md#81-diplomacy)) in relation to rival Houses.

Build orders may fail if shipyards were destroyed in the conflict phase. Fleet movement and colonization orders are issued for execution in the next turn's conflict phase.

Players send their locally updated game database back to the game moderator for turn processing.

### 1.3.4 Maintenance Phase

In the maintenance phase, the game software will advance construction projects, apply repairs to damaged facilities, and process upkeep costs. Fleet maintenance is deducted from house treasuries.

New construction orders will be processed, along with investments in R&D, terraforming, Space Guild services, industry, etc.

Player databases will be updated and customized reports issued for each player. Players have their own unique database, blind to the activities of other players.

## 1.4 Player Elimination & Autopilot

### 1.4.1 Prestige Failure (Defensive Collapse)

⚠️ *AI BEHAVIOR NOT YET IMPLEMENTED - Elimination tracking functional, AI autopilot pending*

If a House's prestige drops and stays below zero for three consecutive turns, the empire enters **Defensive Collapse** and the player is permanently eliminated.

**Defensive Collapse Behavior:**

- All fleets immediately return to the nearest controlled system
- Fleets defend colonies against attacks from Enemy-status houses per [Section 8.1.3](diplomacy.md#813-enemy)
- No offensive operations or expansion
- No new construction orders
- No diplomatic changes
- Economy ceases (no income, no R&D, no maintenance costs)

The collapsed empire remains on the map as a defensive AI target. Other players can conquer colonies and destroy fleets for prestige as normal. Defensive Collapse is permanent - eliminated players cannot rejoin the game.

### 1.4.2 MIA Autopilot

⚠️ *NOT YET IMPLEMENTED - Turn tracking functional, AI behavior pending*

If a player fails to submit orders for three consecutive turns, the empire automatically enters **Autopilot** mode. Unlike Defensive Collapse, autopilot is temporary and allows the player to rejoin at any time.

**Autopilot Behavior:**

- Fleets continue executing standing orders until completion
- Fleets without active orders patrol and defend home systems
- Economy continues operating (current tax rate and R&D allocations maintained)
- Construction focuses on defensive infrastructure and essential facilities
- No new offensive operations or colonization attempts
- Diplomatic stances remain unchanged
- Engages Enemy-status houses that enter controlled territory per [Section 8.1.3](diplomacy.md#813-enemy)

When the player returns and submits new orders, the empire immediately exits autopilot and resumes normal operations.

**Turn Processing:**

- Autopilot activates in the Income Phase after the third consecutive missed turn per [Section 1.3.2](#132-income-phase)
- Autopilot orders are executed during the Command Phase per [Section 1.3.3](#133-command-phase)
- Player can resume control in any subsequent turn by submitting orders

### 1.4.3 Standard Elimination & Last-Stand Invasions

A House is eliminated from the game when they lose all colonies AND have no invasion capability remaining.

**Elimination Triggers:**

1. **Total Defeat**: No colonies AND no fleets
2. **Hopeless Position**: No colonies AND no marines for reconquest

**Last-Stand Invasion Capability:**

Houses that lose all their colonies but retain fleets with loaded marine divisions can attempt desperate reconquest operations:

- **Invasion Orders**: Can target enemy colonies per [Section 7.6](operations.md#76-planetary-invasion)
- **Blitz Operations**: Can execute high-risk planetary assaults per [Section 7.6.2](operations.md#762-blitz)
- **No Elimination**: House remains active as long as marines exist on transports
- **Empty Transports**: Houses with only empty transports or non-combat ships are eliminated

**Example Last-Stand Scenario:**

House Atreides controls 15 systems. House Harkonnen launches a massive offensive and conquers all 15 colonies in a single turn. However, three Atreides troop transports carrying marine divisions survive the onslaught in deep space.

**Result:** House Atreides is NOT eliminated. On the next turn, they can attempt invasion/blitz operations with their surviving marines. If they successfully recapture even one colony, they're back in the game. If all marines are killed in failed invasions, THEN they're eliminated.

This creates dramatic comeback opportunities and rewards players who maintain mobile invasion forces even when losing territory.

### 1.4.4 Victory Conditions

Victory is achieved by reaching 2500 prestige or by being the last active player in the game.

- **Active Players**: Players submitting orders (not in autopilot or defensive collapse)
- **Autopilot Players**: Count as active and can return to win
- **Defensive Collapse Players**: Eliminated, do not count toward victory
- **Last-Stand Players**: Count as active until final elimination

A player in autopilot can still win through prestige accumulation if their empire's defensive economy generates sufficient prestige growth.

**Final Conflict Rule:**

When only two active players remain in the game (excluding Defensive Collapse and Autopilot empires), their diplomatic status automatically converts to Enemy per [Section 8.1.3](diplomacy.md#813-enemy) and cannot be changed. Non-Aggression Pacts are dissolved, and Neutral status cannot be established. There can be only one Emperor - the final two houses must fight for the throne. This rule takes effect at the start of the Income Phase when the condition is detected.

## 1.5 Intelligence & Fog of War

EC4X employs fog of war mechanics where players have limited visibility into rival empires' activities. Intelligence gathering is a critical component of strategic planning and tactical operations.

### 1.5.1 Fleet Encounters and Intelligence

When fleets from different houses encounter each other in the same system, intelligence is automatically gathered regardless of diplomatic status or whether combat occurs.

**Automatic Intelligence Reporting:**

Whenever friendly fleets are present in the same system as foreign forces, players receive **Visual quality** intelligence reports containing:
- Fleet composition (ship types and squadron sizes)
- Number of spacelift ships (transport count)
- Standing orders (Patrol, Guard, Blockade, etc.)
- Fleet location (current system)

**Visual Intelligence Limitations:**

Visual quality intelligence does NOT reveal:
- ❌ Tech levels (always shows as 0)
- ❌ Hull integrity/damage status
- ❌ Cargo contents of transport ships (only count visible)

This represents tactical observation - you can see what ships are present and their behavior, but not their technological sophistication or strategic cargo.

**Intelligence Quality Levels:**

EC4X uses four intelligence quality tiers:

1. **Visual** (Regular Fleets) - Basic tactical observation, ship types visible but not tech/damage
2. **Spy** (Espionage Operations) - High-quality intel with tech levels, hull status, economic data
3. **Perfect** (Scouts & Owned Assets) - Complete accuracy, all details, real-time updates
4. **None** (Fog of War) - No intelligence available

See [Section 9.3](intelligence.md#93-intelligence-quality-levels) for complete quality level specifications.

**Intelligence Collection Scenarios:**

Intelligence is gathered in all of the following situations:
- **Patrol operations**: Visual quality fleet intel per [Section 6.2.4](operations.md#624-patrol-a-system-03)
- **Fleet movement**: Visual quality intel when passing through systems with foreign forces
- **Combat engagements**: Perfect quality intel revealed pre-combat for all participants
- **Scout reconnaissance**: Perfect quality intel from missions per [Section 6.2.9-6.2.12](operations.md#629-spy-on-a-planet-09)
- **Espionage operations**: Spy quality intel from SpyOnPlanet, SpyOnSystem, HackStarbase

**Diplomatic Status Independence:**

Intelligence gathering occurs regardless of diplomatic relationships:
- Enemy forces: Intelligence gathered, combat may occur
- Neutral forces: Intelligence gathered, no combat
- Non-Aggression partners: Intelligence gathered, no combat (unless pact violated)

This reflects the reality that military forces cannot remain completely hidden when operating in the same system, even if diplomatic protocols prevent engagement.

**Intelligence Reports:**

All intelligence is stored in each house's intelligence database with timestamps. See [Section 9](intelligence.md) for complete intelligence system documentation including:
- Report types and contents
- Intelligence corruption from disinformation/dishonor
- Staleness indicators
- Strategic use of intelligence

### 1.5.2 Fog of War

Players do not have automatic visibility into:
- Rival empire economics (income, production, treasury)
- Rival empire technology levels (requires espionage per [Section 8.2](diplomacy.md#82-subversion--subterfuge))
- Fleet movements in systems without friendly presence
- Colony development and construction projects
- Strategic intentions and future orders

The game moderator maintains separate databases for each house to preserve fog of war. Intelligence must be actively gathered through fleet operations, scout missions, and espionage activities.

