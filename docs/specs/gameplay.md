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

Players start the game with 50 prestige points.

If a House's prestige drops and stays below zero for three consecutive turns, the Duke is forced surrender to a rival House.

A table of prestige values is listed in [Section 9.4](reference.md#94-prestige).

## 1.2 Game Setup

At the start of a game, players will agree upon and designate a game moderator. The moderator's function is to collect player turn orders, update the master game database, and reissue updated game data back to players at the beginning of each turn. Software tools will be provided to make this a smooth process and maintain fog of war. The moderator would have to go out of their way to cheat, and deconstructing and analyzing the game data would not be an enjoyable task. Regardless, choose a game moderator with integrity. EC4X is intended to be played among friends.[^1]

[^1]: Future iterations of the game will allow for a server/client model, but not everyone will want to setup a dedicated server. Encrypting the game data is also a feature to be integrated.

Communicating with other players over email or in a dedicated chat room is recommended. There are plenty to choose from.

Generate a star-map as described in [Section 2.1](military.md#21-star-map) for the selected number of players. Resources will be provided in the GitHub repo to spawn a map.

Players start the game with one homeworld (An Abundant Eden planet, Level V colony with 840 PU), 420 production points (PP) in the treasury, one spaceport, one shipyard, one fully loaded ETAC, a Light Cruiser, two Destroyers, and two Scouts. The tax rate is set to 50% by default.

Tech levels start at: EL1, SL1, CST1, WEP1, TER1, ELI1, and CIC1.

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

