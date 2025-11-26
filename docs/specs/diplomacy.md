# 8.0 Diplomacy & Espionage

## 8.1 Diplomacy

In EC4X, diplomacy includes Neutral, Enemy, and Non-Aggression categories. As House Duke, your mandate is to lead your House to victory by strategic means, where diplomacy can play a pivotal role alongside the sword. Your primary directive remains to decisively manage your adversaries, leveraging both military might and diplomatic cunning.

### 8.1.1 Neutral

Fleets are instructed to avoid initiating hostilities with the designated neutral House outside of the player's controlled territory. This status allows for coexistence in neutral or contested spaces without immediate aggression.

### 8.1.2 Non-Aggression Pacts

Houses can enter into formal or informal agreements to not attack each other, allowing for cooperation or at least a mutual stance of non-hostility.

This can include:
- Joint Military Operations: Against common threats or for mutual defense without direct conflict between the signing parties.
- Territorial Recognition: Agreements to respect each others territories.
- Strategic Flexibility: While not allies, Houses in a non-aggression pact can share intelligence, coordinate against mutual enemies.

**Violation Consequences:**

Attacking a Non-Aggression partner constitutes immediate pact violation. When a violation is detected during the Conflict Phase per [Section 1.3.1](gameplay.md#131-conflict-phase), the diplomatic status automatically converts to Enemy and takes effect at the start of the next turn's Conflict Phase.

**Penalties for Violating House:**
- **Immediate Prestige Loss:** **PactViolation** penalty - see [Table 9.4](reference.md#104-prestige)
- **Dishonored Status:** For 3 turns, other houses receive +1 prestige (**DishonoredBonus**) when they attack the violator (represents reputational damage) - see [Table 9.4](reference.md#104-prestige)
- **Diplomatic Isolation:** Cannot establish new Non-Aggression Pacts with any house for 5 turns
- **Repeat Violations:** Each subsequent violation within 10 turns incurs **RepeatViolation** penalty - see [Table 9.4](reference.md#104-prestige)

**Diplomatic Reinstatement:**
Non-Aggression Pacts cannot be reinstated between the same houses for 5 turns after violation. The Dishonored status and diplomatic isolation apply to all houses, not just the betrayed partner, reflecting widespread loss of trust in the galactic community.

### 8.1.3 Enemy

Fleets are commanded to engage with the forces of the declared enemy House at every opportunity, both within and outside controlled territories.

This state leads to full-scale warfare where all encounters are treated as hostile, pushing for direct and aggressive confrontations.

### 8.1.4 Defense Protocol

Regardless of diplomatic status, all units will defend home planets against any foreign incursions with maximum aggression.

Fleets will retaliate against direct attacks regardless of diplomatic state, in accordance with ROE.

### 8.1.5 Territorial Control

A house controls territory in systems containing its colony. Each system can contain only one colony per the colonization rules in [Section 6.2.13](operations.md#6213-colonize-a-planet-12).

**Territory Classifications:**

- **Controlled Territory**: Systems containing the house's colony
- **Foreign Territory**: Systems containing another house's colony
- **Neutral Space**: Systems without any colonies

**Diplomatic Application:**

Neutral diplomatic status (Section 8.1.1) governs behavior outside controlled territory. Within controlled territory, houses may engage neutral forces per Defense Protocol (Section 8.1.4). Enemy status (Section 8.1.3) applies in all territories regardless of location.

## 8.2 Subversion & Subterfuge

The Space Guilds are key players in the clandestine world of diplomacy and espionage. They dominate trade, technology sharing, and offer covert operations, wielding influence through subterfuge and strategic manipulation. While their partnerships can significantly enhance a House's capabilities, the Space Guilds remain neutral, their loyalties bought by the highest bidder or the most strategic offer.

Players can allocate Espionage Budget points (EBPs) towards various espionage actions every turn.

EBP points **cost 40 PP each**.

If a player invests more than 5% of their turn budget into EBP they lose Prestige points.

- Investments > 5% lose 1 Prestige point for each additional 1% invested over 5%.
- Example: If a player's turn budget is 100 points, and they invest 7 points in EBP, they lose 2 Prestige points.

**Restrictions**:

- Maximum of One Espionage Action Per Turn.

<!-- ESPIONAGE_PRESTIGE_TABLE_START -->
| Espionage Action | Cost in EBPs | Description | Prestige Change for Player | Prestige Change for Target |
|------------------|:------------:|-------------|----------------------------|----------------------------|
| Tech Theft | 5 | Attempt to steal critical R&D tech. | +20 | -30 |
| Sabotage (Low Impact) | 2 | Small-scale sabotage to a colony's industry. | +10 | -10 |
| Sabotage (High Impact) | 7 | Major sabotage to a colony's industry. | +30 | -50 |
| Assassination | 10 | Attempt to eliminate a key figures within the target House. | +50 | -70 |
| Cyber Attack | 6 | Attempt to hack into a Starbase's systems to cause damage and chaos. | +20 | -30 |
| Economic Manipulation | 6 | Influence markets to harm the target's economy | +30 | -7 |
| Psyops Campaign | 3 | Launch a misinformation campaign or demoralization effort. | +10 | -3 |
| Counter-Intelligence Sweep | 4 | Defensive operation to block enemy intelligence gathering. | +5 | +0 |
| Intelligence Theft | 8 | Steal target's entire intelligence database. | +40 | -20 |
| Plant Disinformation | 6 | Corrupt target's intelligence with false data. | +15 | -15 |

*Source: config/prestige.toml [espionage] and [espionage_victim] sections; config/espionage.toml [costs]*
<!-- ESPIONAGE_PRESTIGE_TABLE_END -->

### **8.2.1 Espionage Mechanics**

Espionage actions allow players to disrupt their rivals' operations and gain tactical advantages through covert maneuvers. Below is a detailed overview of each available action, including its effects and thematic narrative.

| Espionage Action              | Effect                                                     |
| ----------------------------- | ---------------------------------------------------------- |
| **Tech Theft**                | Steals **10 SRP** from the target's research pool          |
| **Low Impact Sabotage**       | Reduces target's **1d6 Industrial Units (IU)**             |
| **High Impact Sabotage**      | Reduces target's **1d20 Industrial Units (IU)**            |
| **Assassination**             | Reduces target's **SRP gain by 50%** for one turn          |
| **Economic Disruption**       | Halves target's **Net Colony Value (NCV)** for one turn    |
| **Propaganda Campaign**       | Reduces target's **tax revenue by 25%** for one turn       |
| **Cyber Attack**              | Cripples the target's **Starbase**                         |
| **Counter-Intelligence Sweep** | Blocks enemy intelligence gathering for **1 turn**        |
| **Intelligence Theft**        | Steals target's **entire intelligence database**           |
| **Plant Disinformation**      | Corrupts target's intel with **20-40% variance for 2 turns** |

**Tech Theft**:
In the dead of night, a covert team of elite hackers infiltrates the rival House's research network, siphoning critical data and blueprints. By the time their intrusion is detected, valuable research progress has already been uploaded and integrated into your own laboratories, giving your scientists a sudden leap forward.

**Low Impact Sabotage**:
A series of small, untraceable explosions ripple through the industrial district of the target colony. Machines grind to a halt, assembly lines are disrupted, and productivity drops. While the damage is minimal, it forces costly repairs and creates a ripple effect of delays across the colony’s production schedule.

**High Impact Sabotage**:
Coordinated explosions rock the core industrial facilities of the enemy colony, sending plumes of smoke into the sky. Entire factories are leveled, leaving a twisted wreck of debris and fire. The sabotage is devastating, crippling the enemy’s manufacturing capabilities and resulting in the loss of up to **1d20 Industrial Units (IU)**.

**Assassination**:
A shadowy operative slips through the security perimeter and strikes at a key figure in the rival House’s R&D division. The death sends shock-waves through their research teams, causing chaos and demoralizing the scientists. The pace of research slows to a crawl as panic and distrust spread among the staff.

**Economic Disruption**:
Anonymous agents spread false rumors of an impending financial collapse, triggering a panic among investors and merchants in the enemy colony. Markets plunge, trade grinds to a halt, and the local economy falters. Revenues drop sharply as the effects of the disruption ripple through the entire colony’s financial system.

**Propaganda Campaign**:
A coordinated propaganda blitz floods the rival House’s communications networks with fake news and altered footage, painting their leadership as corrupt and ineffective. Citizens begin to protest, refusing to pay full taxes as public confidence crumbles. The unrest leaves the enemy Duke struggling to maintain control, with lower revenues compounding their problems.

**Cyber Attack**:
A powerful virus infiltrates the core systems of the enemy's Starbase, shutting down its defenses and key operational modules. The Starbase is left crippled, its functions severely impaired until extensive repairs are completed. The colony's defensive posture and economic output suffer a significant blow, leaving it vulnerable to further attacks.

### **8.2.2 Intelligence Warfare Actions**

EC4X introduces three specialized espionage actions focused on information warfare, bringing the total to **10 espionage actions**. These operations target enemy intelligence gathering capabilities rather than physical assets.

**Counter-Intelligence Sweep** (4 EBP):
Your security forces conduct a comprehensive sweep of all intelligence operations, communications networks, and data channels. Hidden surveillance equipment is discovered and destroyed, compromised personnel are identified and removed, and security protocols are hardened against enemy infiltration. For one turn, enemy intelligence gathering attempts are blocked - scout reports fail to transmit, spy operations are detected before completion, and surveillance networks go dark. This defensive operation provides critical protection during sensitive military operations or when preparing surprise attacks.

**Intelligence Theft** (8 EBP):
A masterful cyber-espionage operation penetrates the target House's most secure intelligence archives. Over the course of hours, massive data transfers siphon their entire intelligence database - scout reports, spy assessments, fleet movement tracking, economic analyses, and strategic evaluations. When complete, you possess a perfect copy of everything they know about the galaxy, including their intelligence on your own forces and those of other houses. This high-value operation can reveal enemy strategic intentions, planned offensives, and alliance negotiations. The theft may go undetected for turns, giving you time to exploit the stolen intelligence before counter-measures are implemented.

**Plant Disinformation** (6 EBP):
Your intelligence operatives conduct a sophisticated disinformation campaign, subtly corrupting the target House's intelligence gathering systems. False data is injected into scout telemetry, spy reports are altered with fabricated statistics, and sensor networks are fed phantom readings. The corruption is designed to appear legitimate - fleet strengths are inflated or deflated by 20-40%, colony statistics are randomized, economic data is distorted, and tech levels are misreported. The disinformation persists for 2 turns, during which all enemy intelligence reports (scouts, spies, visual encounters) contain corrupted data. Strategic decisions made on false intelligence can lead to disastrous military miscalculations, wasted resources, and failed offensives. The beauty of disinformation is that the enemy doesn't know their intelligence is compromised until they act on false data.

**Strategic Implications:**

Intelligence warfare creates a meta-game layer where information itself becomes a weapon:

- **Counter-Intelligence Sweep** is defensive, protecting your operations during critical turns
- **Intelligence Theft** provides one-time strategic insight into enemy knowledge and intentions
- **Plant Disinformation** is offensive, degrading enemy decision-making for multiple turns

Houses must balance offensive espionage (sabotage, assassination) with intelligence warfare. A well-timed disinformation campaign can cause more damage than physical sabotage by poisoning enemy strategic planning. Intelligence Theft can reveal enemy war plans, allowing preemptive counter-measures. Counter-Intelligence Sweeps protect your most sensitive operations from enemy surveillance.

The interplay between **Intelligence Corruption** (disinformation and dishonor) and **Counter-Intelligence** creates strategic depth. See [Section 9.4](intelligence.md#94-intelligence-corruption) for complete intelligence corruption mechanics.

## 8.3 Counter Intelligence Command (CIC)

The mission of the Counter Intelligence Command (CIC) is to safeguard the House's interests by identifying and neutralizing espionage activities from rival Houses. This involves employing advanced surveillance technologies and running counter-espionage operations to ensure the security of House secrets.

**CIC Investment**:

Players can allocate a portion of their turn budget into Counter Intelligence Points (CIP).

- CIP points cost **40 PP each**.
- Each detection attempt (roll) costs **1 CIP point**. If a House has no CIP points, espionage attempts automatically succeed.
- When an espionage event occurs, a **detection modifier** is applied based on the player's total CIP points.

If a player invests more than 5% of their turn budget into CIP they lose Prestige points.

- Investments > 5% lose 1 Prestige point for each additional 1% invested over 5%.
- Example: If a player's turn budget is 100 points, and they invest 7 points in CIP, they lose 2 Prestige points.

### Detection Modifier:

The modifier is determined based on the total **CIP points** held by the player when an espionage event occurs:

<!-- CIC_MODIFIER_TABLE_START -->
| Total CIP Points | Automatic Detection Modifier |
|:----------------:|:----------------------------:|
| 0 | 0 (espionage automatically succeeds) |
| 1-5 | +1 |
| 6-10 | +2 |
| 11-15 | +3 |
| 16-20 | +4 |
| 21+ | +5 (maximum) |

*Source: config/espionage.toml [detection] section*
<!-- CIC_MODIFIER_TABLE_END -->

### Espionage Detection Table:

<!-- CIC_THRESHOLD_TABLE_START -->
| CIC Level | Base 1D20 Roll | Detection Probability (with Automatic Modifier) |
|:---------:|:--------------:|:-----------------------------------------------:|
| CIC1 | > 15 | 25% → 30-50% |
| CIC2 | > 12 | 40% → 45-65% |
| CIC3 | > 10 | 55% → 60-80% |
| CIC4 | > 7 | 65% → 70-90% |
| CIC5 | > 4 | 80% → 85-95% |

*Source: config/espionage.toml [detection] section*
<!-- CIC_THRESHOLD_TABLE_END -->

**Example**:

1. A player with **CIC3** and **8 CIP points** faces an espionage event.
2. The game deducts **1 CIP point** for the detection roll and applies a +2 modifier (based on having 6-10 CIP points).
3. The detection roll threshold for CIC3 is **10+**. With the +2 modifier, the roll only needs to meet or exceed **8**.
4. The roll result is **8**, so the espionage attempt is successfully detected.

**Outcome of Successful Detection**:

- If the roll (including the modifier) meets or exceeds the required threshold, the espionage action is detected and prevented.
- The attacking player loses **2 prestige points** for the failed attempt.

## 8.4 Risks of Over-Investing in Espionage

While espionage is a powerful tool for undermining rival Houses, over-reliance on covert actions comes with significant risks. In the volatile political landscape of EC4X, the perception of your House can be as important as its actual strength. An overly aggressive espionage strategy can backfire, tarnishing your reputation and eroding the trust of allies, subjects, and even neutral factions. The path to the throne is narrow, and using shadow tactics too liberally can leave a House vulnerable to unforeseen consequences.

### Reputation Damage

A House known for excessive use of espionage becomes synonymous with treachery. Other Houses may become wary of forming alliances or trading agreements, fearing betrayal. This distrust can isolate a House diplomatically, limiting options for cooperation or joint military efforts against common threats.

The citizens of the Empire prize strength, honor, and open warfare over deceit. A Duke who leans too heavily on spies and saboteurs may be seen as weak or dishonorable, risking a loss of public support. This can manifest in reduced prestige, lower tax compliance, and even increased civil unrest across your colonies.

### Diminished Strategic Impact

The more frequently espionage tactics are used, the more likely rivals are to bolster their counter-intelligence efforts. As other Houses ramp up their CIP investments, the effectiveness of your espionage actions diminishes, resulting in wasted resources and fewer successful missions.

Excessive espionage may trigger rival Houses to adopt aggressive countermeasures, such as initiating economic sanctions, launching retaliatory cyber attacks, or coordinating with other players to mount a joint military response. The risks of provoking a coalition against your House increase with every detected espionage action.

### Prestige Penalties

Investing too much in espionage can erode the prestige of your House over time, creating a long-term disadvantage. The aristocracy views shadowy tactics as a sign of desperation rather than strength, leading to the perception that your House is incapable of achieving its goals through legitimate means.

Each turn that espionage investments exceed 5% of your budget, your House loses 2 prestige points for every additional 1% invested over the 5% threshold. This penalty reflects the growing skepticism of your peers and the erosion of your House's noble reputation.

*Configuration: `over_invest_espionage = -2` in config/prestige.toml [penalties] section*

Repeated over-investment in espionage actions compounds the loss of prestige, as the Empire’s nobility becomes increasingly suspicious of your methods. Over time, this can severely impact your standing, making it difficult to assert dominance and achieve key diplomatic or military objectives.

### Increased Vulnerability to Espionage

Ironically, focusing heavily on offensive espionage often means neglecting your own defenses. Houses that pour resources into EBP at the expense of CIP may find themselves exposed to enemy spies, suffering from stolen technologies, sabotage, and propaganda campaigns. A House that gains a reputation for aggressive espionage is likely to attract more counter-espionage efforts from its rivals, creating a dangerous cycle of escalating spy wars.

Rivals who detect your espionage efforts are likely to respond in kind, targeting your colonies with sabotage, tech theft, or even assassination attempts. The cost of countering these actions can quickly exceed the initial benefits of your own espionage investments.

### Finding the Balance

In EC4X, effective use of espionage is about balance. Strategic investments in covert operations can provide decisive advantages, but overextending your reach can be disastrous. Successful Dukes must weigh the immediate gains of espionage against the long-term costs to prestige, diplomatic relations, and overall stability. In the quest for the imperial throne, it is often the House that combines subtlety with strength, and deception with diplomacy, that emerges victorious.

