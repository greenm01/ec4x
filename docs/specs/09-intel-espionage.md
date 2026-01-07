# 9.0 Intelligence & Espionage

Knowledge is power in EC4X. The intelligence and espionage systems determine what you know about your rivals, when you know it, and how you can disrupt their operations through covert action. In the fog of war, victory often belongs to the House Archon who sees the battlefield most clearly and strikes from the shadows most effectively.

## 9.1 Gathering Intelligence

Intelligence flows from multiple sources, each revealing different aspects of your enemies' capabilities and intentions.

### 9.1.1 Spy Scout Missions (Perfect Quality)

Your **Scouts** are the primary tool for gathering detailed, high-quality intelligence. When you dispatch a fleet of Scouts on an espionage mission (e.g., `Spy on Planet`), they travel to the target system and establish a persistent intelligence-gathering operation.

**Mission Execution**:

Scout espionage missions progress through multiple phases:

1. **Travel** (Production Phase): The Scout fleet moves toward the target system. During this phase, you can cancel the mission by issuing a new command.
2. **Arrival** (Production Phase): When the fleet arrives at the target system, it prepares to begin the mission. The mission starts in the following Conflict Phase.
3. **Mission Start & First Detection** (Conflict Phase): When the fleet begins its mission:
   - Scouts establish position at target and begin intelligence gathering
   - **First detection check** runs immediately - if successful, the mission becomes persistent
   - If detected: All scouts destroyed, mission fails, no intelligence gathered
   - If undetected: Scouts "consumed" (committed to mission), fleet locked, mission becomes active
   - Perfect Quality intelligence gathered on first turn
4. **Persistent Operation** (Conflict Phase, subsequent turns): Scouts remain at the target, gathering intelligence each turn while evading detection.
5. **Ongoing Detection Checks**: Every turn while the mission is active, the defending house attempts to detect your scouts. If detected, all scouts are destroyed immediately and the mission fails. If undetected, scouts gather **Perfect Quality** intelligence for that turn.

**Intelligence Quality**:

If successful, the intelligence gathered each turn is of **Perfect Quality**—it is detailed, accurate, and current as of that turn. This includes:
- Complete fleet compositions with tech levels
- Detailed colony statistics (population, industrial output, facilities)
- Construction queues with turn counts
- Economic output and net tax revenue
- Defensive installations (starbases, ground batteries, shields)

**Risk vs. Reward**:

Scout missions are high-risk operations with significant rewards:
- **First Detection Check**: Scouts face an initial detection check when starting the mission. Failure means immediate loss with no intelligence gathered.
- **Cumulative Risk**: Detection checks occur every turn. Longer missions face higher cumulative detection risk.
- **Multi-Turn Intelligence**: Successful missions provide Perfect Quality intelligence over multiple turns, tracking enemy development in real-time.
- **Irreversible Commitment**: Once scouts start their mission (pass the first detection check), you cannot recall them. They remain on mission until detected or the target is lost. You can cancel orders during the travel phase.
- **Diplomatic Escalation**: If detected, your diplomatic stance with the defender escalates to Hostile.

See espionage commands in [Section 6.3.13-6.3.15](06-operations.md#6313-spy-on-a-planet-11) for mission details and detection mechanics.

### 9.1.2 Fleet Encounters

When your fleets encounter enemy forces in the same system, your captains automatically report what they observe. These visual sightings provide basic tactical intelligence: ship types, fleet sizes, and observable behavior such as patrol or blockade operations. You can count the enemy destroyers and cruisers, note the presence of transport vessels, and observe their standing commands.

Visual intelligence has natural limitations. Your captains cannot assess technological sophistication from a distance, determine hull damage states, or identify cargo contents. An enemy transport fleet shows only the number of ships, not whether they carry invasion troops, colonists, or equipment. Tech levels display as zero since there is no way to visually assess research advancement. This reflects the reality of tactical observation in space warfare.

### 9.1.3 Espionage Operations (Perfect Quality)

Your **Scouts** conducting espionage missions (`Spy on Planet`, `Spy on System`, `Hack a Starbase`) penetrate deeper than visual observation. If successful, these covert operations provide **Perfect Quality** intelligence, including economic data, construction queues, and technological assessments that visual sightings cannot reveal.

This level of detail transforms strategic decision-making. Knowing an enemy's economic strength and research focus allows you to predict their capabilities turns in advance.

### 9.1.4 Starbase Surveillance

Advanced sensor arrays installed on starbases monitor their system continuously. A starbase watches its home system, detecting non-stealthed fleet movements, combat activity, and bombardment operations. This active surveillance provides early warning of enemy fleet approaches and documents hostile activity in your territory.

Scouts and cloaked Raiders can evade starbase detection through stealth. Detection mechanics are described in [Section 7.2.4](07-combat.md#724-cloaking-and-detection).
## 9.2 Subversion & Subterfuge

The Space Guilds are key players in the clandestine world of diplomacy and espionage. They dominate trade, technology sharing, and offer covert operations, wielding influence through subterfuge and strategic manipulation. While their partnerships can significantly enhance your House's capabilities, the Space Guilds remain neutral—their loyalties bought by the highest bidder or the most strategic offer.

You can allocate Espionage Budget points (EBPs) toward various espionage actions every turn.

EBP points **cost 40 PP each**.

If you invest more than 5% of your turn budget into EBP, you lose Prestige points.

- Investments > 5% lose 1 Prestige point for each additional 1% invested over 5%.
- Example: If your turn budget is 100 points and you invest 7 points in EBP, you lose 2 Prestige points.

**Restrictions**:

- Maximum of One Espionage Action Per Turn.

<!-- ESPIONAGE_PRESTIGE_TABLE_START -->
| Espionage Action           | Cost in EBPs | Description                                                          | Prestige Change for Player | Prestige Change for Target |
|----------------------------|:------------:|----------------------------------------------------------------------|----------------------------|----------------------------|
| Tech Theft                 | 5            | Attempt to steal critical R&D tech.                                  | +20                        | -30                        |
| Sabotage (Low Impact)      | 2            | Small-scale sabotage to a colony's industry.                         | +10                        | -10                        |
| Sabotage (High Impact)     | 7            | Major sabotage to a colony's industry.                               | +30                        | -50                        |
| Assassination              | 10           | Attempt to eliminate a key figures within the target House.          | +50                        | -70                        |
| Cyber Attack               | 6            | Attempt to hack into a Starbase's systems to cause damage and chaos. | +20                        | -30                        |
| Economic Manipulation      | 6            | Influence markets to harm the target's economy                       | +30                        | -7                         |
| Psyops Campaign            | 3            | Launch a misinformation campaign or demoralization effort.           | +10                        | -3                         |
| Counter-Intelligence Sweep | 4            | Defensive operation to block enemy intelligence gathering.           | +5                         | +0                         |
| Intelligence Theft         | 8            | Steal target's entire intelligence database.                         | +40                        | -20                        |
| Plant Disinformation       | 6            | Corrupt target's intelligence with false data.                       | +15                        | -15                        |

*Source: config/prestige.toml [espionage] and [espionage_victim] sections; config/espionage.toml [costs]*
<!-- ESPIONAGE_PRESTIGE_TABLE_END -->

### **9.2.1 Espionage Mechanics**

Espionage actions allow you to disrupt your rivals' operations and gain tactical advantages through covert maneuvers. Below is a detailed overview of each available action, including its effects and thematic narrative.

| Espionage Action               | Effect                                                       |
| ------------------------------ | ------------------------------------------------------------ |
| **Tech Theft**                 | Steals **10 SRP** from the target's research pool            |
| **Low Impact Sabotage**        | Reduces target's **1d6 Industrial Units (IU)**               |
| **High Impact Sabotage**       | Reduces target's **1d20 Industrial Units (IU)**              |
| **Assassination**              | Reduces target's **SRP gain by 50%** for one turn            |
| **Economic Disruption**        | Halves target's **Net Colony Value (NCV)** for one turn      |
| **Propaganda Campaign**        | Reduces target's **tax revenue by 25%** for one turn         |
| **Cyber Attack**               | Cripples the target's **Starbase**                           |
| **Counter-Intelligence Sweep** | Blocks enemy intelligence gathering for **1 turn**           |
| **Intelligence Theft**         | Steals target's **entire intelligence database**             |
| **Plant Disinformation**       | Corrupts target's intel with **20-40% variance for 2 turns** |

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
A coordinated propaganda blitz floods the rival House's communications networks with fake news and altered footage, painting their leadership as corrupt and ineffective. Citizens begin to protest, refusing to pay full taxes as public confidence crumbles. The unrest leaves the enemy Archon struggling to maintain control, with lower revenues compounding their problems.

**Cyber Attack**:
A powerful virus infiltrates the core systems of the enemy's Starbase, shutting down its defenses and key operational modules. The Starbase is left crippled, its functions severely impaired until extensive repairs are completed. The colony's defensive posture and economic output suffer a significant blow, leaving it vulnerable to further attacks.

### **9.2.2 Intelligence Warfare Actions**

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

The interplay between **Intelligence Corruption** (disinformation and dishonor) and **Counter-Intelligence** creates strategic depth. See [Section 9.7](09-intel-espionage.md#97-intelligence-corruption) for complete intelligence corruption mechanics.

## 9.3 Counter Intelligence Command (CIC)

The mission of the Counter Intelligence Command (CIC) is to safeguard the House's interests by identifying and neutralizing espionage activities from rival Houses. This involves employing advanced surveillance technologies and running counter-espionage operations to ensure the security of House secrets.

**CIC Investment**:

You can allocate a portion of your turn budget into Counter Intelligence Points (CIP).

- CIP points cost **40 PP each**.
- Each detection attempt (roll) costs **1 CIP point**. If your House has no CIP points, espionage attempts automatically succeed.
- When an espionage event occurs, a **detection modifier** is applied based on your total CIP points.

If you invest more than 5% of your turn budget into CIP, you lose Prestige points.

- Investments > 5% lose 1 Prestige point for each additional 1% invested over 5%.
- Example: If your turn budget is 100 points and you invest 7 points in CIP, you lose 2 Prestige points.

### Detection Modifier:

The modifier is determined based on the total **CIP points** held by the player when an espionage event occurs:

<!-- CIC_MODIFIER_TABLE_START -->
| Total CIP Points | Automatic Detection Modifier         |
|:----------------:|:------------------------------------:|
| 0                | 0 (espionage automatically succeeds) |
| 1-5              | +1                                   |
| 6-10             | +2                                   |
| 11-15            | +3                                   |
| 16-20            | +4                                   |
| 21+              | +5 (maximum)                         |

*Source: config/espionage.toml [detection] section*
<!-- CIC_MODIFIER_TABLE_END -->

### Espionage Detection Table:

<!-- CIC_THRESHOLD_TABLE_START -->
| CIC Level | Base 1D20 Roll | Detection Probability (with Automatic Modifier) |
|:---------:|:--------------:|:-----------------------------------------------:|
| CIC1      | > 15           | 25% → 30-50%                                    |
| CIC2      | > 12           | 40% → 45-65%                                    |
| CIC3      | > 10           | 55% → 60-80%                                    |
| CIC4      | > 7            | 65% → 70-90%                                    |
| CIC5      | > 4            | 80% → 85-95%                                    |

*Source: config/espionage.toml [detection] section*
<!-- CIC_THRESHOLD_TABLE_END -->

**Example**:

1. You have **CIC3** and **8 CIP points** when facing an espionage event.
2. The game deducts **1 CIP point** for the detection roll and applies a +2 modifier (based on having 6-10 CIP points).
3. The detection roll threshold for CIC3 is **10+**. With the +2 modifier, the roll only needs to meet or exceed **8**.
4. The roll result is **8**, so the espionage attempt is successfully detected.

**Outcome of Successful Detection**:

- If the roll (including the modifier) meets or exceeds the required threshold, the espionage action is detected and prevented.
- The attacking player loses **2 prestige points** for the failed attempt.

## 9.4 Risks of Over-Investing in Espionage

While espionage is a powerful tool for undermining rival Houses, over-reliance on covert actions comes with significant risks. In the volatile political landscape of EC4X, the perception of your House can be as important as its actual strength. An overly aggressive espionage strategy can backfire, tarnishing your reputation and eroding the trust of allies, subjects, and even neutral factions. The path to the throne is narrow, and using shadow tactics too liberally can leave a House vulnerable to unforeseen consequences.

### Reputation Damage

A House known for excessive use of espionage becomes synonymous with treachery. Other Houses may become wary of forming alliances or trading agreements, fearing betrayal. This distrust can isolate a House diplomatically, limiting options for cooperation or joint military efforts against common threats.

The citizens of the Empire prize strength, honor, and open warfare over deceit. An Archon who leans too heavily on spies and saboteurs may be seen as weak or dishonorable, risking a loss of public support. This can manifest in reduced prestige, lower tax compliance, and even increased civil unrest across your colonies.

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

In EC4X, effective use of espionage is about balance. Strategic investments in covert operations can provide decisive advantages, but overextending your reach can be disastrous. Successful Archons must weigh the immediate gains of espionage against the long-term costs to prestige, diplomatic relations, and overall stability. In the quest for the imperial throne, it is often the House that combines subtlety with strength, and deception with diplomacy, that emerges victorious.

## 9.11 Intelligence Reports

Your intelligence network generates detailed reports from all sources. These reports accumulate in your intelligence database, building a picture of enemy capabilities and activities over time.

### 9.5.1 Scout Encounter Reports

Scout encounters produce your most detailed intelligence reports. When scouts observe enemy fleets, the report includes complete fleet compositions, tech levels for all ships, hull integrity assessments, and cargo manifests for transport vessels. Fleet behavior patterns are noted, including standing commands and patrol routes.

Colony discoveries provide comprehensive settlement data. Your analysts learn population levels, industrial capacity, defensive installations, construction queues, and orbital defenses. Economic intelligence reveals gross output and net tax revenue. The construction queue shows what the enemy is building and how many turns remain to completion.

Combat observations document both sides' forces before battle, losses sustained during the engagement, and battle outcomes. Scouts witnessing bombardment or invasion operations report the attacking force composition and target defenses.

Each report is assigned a significance rating from 1-10 based on strategic value. Discovery of a major enemy colony rates 8/10. Observing a small fleet patrol might rate 5/10. Witnessing a major space battle between rival houses could rate 10/10 depending on strategic implications.

### 9.5.2 Fleet Movement Tracking

Your intelligence system maintains chronological records of enemy fleet sightings. Each observation notes the turn, system, and fleet composition. Over time, these sightings reveal movement patterns and patrol routes.

Your intelligence staff tracks last known positions for all enemy fleets. Repeated sightings in a predictable pattern indicate patrol routes or blockade stations. Time since last sighting (staleness) helps you assess whether intelligence remains current or has aged beyond reliability.

This historical tracking enables strategic prediction. If an enemy fleet has patrolled the same three-system route for five turns, you can anticipate its position and plan accordingly.

### 9.5.3 Combat Intelligence

Combat generates automatic intelligence reports for all participating forces. Before battle, both sides gain complete knowledge of enemy fleet composition, ship lists, spacelift cargo, and fleet commands. The fog of war lifts completely during combat - you see exactly what you're fighting.

Post-combat intelligence depends on survival. If your forces survive or retreat successfully, they report battle outcomes, losses sustained by both sides, and which enemy forces retreated. Complete annihilation provides no post-combat intelligence.

Combat observers (scouts or neutral forces in system) witness the entire engagement and receive full intelligence reports without participating in the battle.

### 9.5.4 Diplomatic Intelligence

Major diplomatic events are public knowledge. All houses automatically receive intelligence reports when diplomatic states change (e.g., Neutral to Hostile, Hostile to Enemy, or vice-versa).

Diplomatic intelligence includes the houses involved, the nature of the event, and resulting status changes. This transparency reflects the political reality that major diplomatic shifts cannot be concealed in a small region of contested space.

See [Section 8.1](08-diplomacy.md#81-diplomacy) for complete diplomatic mechanics.

### 9.5.5 Espionage Detection

Counter-intelligence operations may detect enemy espionage attempts against your House. Detection reports identify the perpetrator (if discovered), the type of espionage attempted, the target system, and whether the operation succeeded or failed.

Failed espionage provides valuable counter-intelligence. Knowing your rivals attempted tech theft or sabotage reveals their strategic priorities and resource allocation. Repeated failed attempts indicate persistent espionage pressure requiring increased counter-intelligence investment.

## 9.9 Intelligence Quality Levels

Intelligence reports carry quality indicators reflecting reliability and detail level.

**None** indicates complete fog of war. You have no intelligence on the target. The system has never been scouted or visited by your forces.

**Visual** quality comes from fleet encounters. You see what's there but cannot assess technological sophistication or internal states. Ship types and counts are accurate. Tech levels, hull damage, and cargo contents remain unknown. This represents what your ship captains observe visually.

**Spy** quality is not currently used.

**Perfect** quality comes from successful **Spy Scout** missions and observations of your own assets. All details are available, accurate, and current. Perfect quality intelligence forms the foundation of strategic planning.

Intelligence quality affects decision-making. Visual sightings reveal enemy presence but not capability. Spy-quality intelligence reveals capability but may lack real-time updates. Perfect quality intelligence provides complete situational awareness.

## 9.10 Intelligence Corruption

Intelligence can be compromised through enemy action or diplomatic dishonor. Corrupted intelligence introduces false data into your reports, potentially leading to catastrophic strategic miscalculations.

### 9.7.1 Disinformation

The Plant Disinformation espionage action corrupts your intelligence gathering systems. Enemy operatives inject false data into scout telemetry, alter sensor readings, and fabricate statistical reports. The corruption is sophisticated and designed to appear legitimate.

Disinformation persists for two turns after the enemy plants it. During this time, all your intelligence reports contain corrupted data with 20-40% variance from true values. Fleet strengths are inflated or deflated randomly. Colony statistics are distorted. Economic data is falsified. Tech levels are misreported.

The variance is significant enough to cause serious errors in strategic planning. An enemy fleet reported at 12 ships might actually have 7 or 17. A colony showing 8,000 PP monthly output might produce 5,000 or 11,000. You don't know your intelligence is corrupted until you act on false data and discover the truth through direct engagement.

Counter-Intelligence Sweeps can block disinformation attempts. Investing in counter-intelligence protection is the only defense against this insidious form of espionage.

See [Section 9.2.2](#922-intelligence-warfare-actions) for disinformation mechanics and costs.

### 9.7.2 Dishonor and Intelligence Failure

Houses operating under Dishonored status suffer severe intelligence corruption. Dishonor stems from Non-Aggression pact violations and reflects deep organizational shame and demoralization. When your House is dishonored, your forces become disorganized, command structures falter, and intelligence gathering suffers catastrophic degradation.

Dishonored intelligence corruption is more severe than disinformation, introducing 50% variance into all intelligence reports. The corruption lasts three turns, matching the dishonor duration. Every report from every source - scouts, spies, visual sightings - contains wildly inaccurate data. Strategic planning becomes nearly impossible.

The final two houses remaining in the game are exempt from dishonor and its intelligence effects. This exception ensures the endgame remains decisive rather than random.

Dishonor mechanics are described in [Section 8.1.2](08-diplomacy.md#812-neutral).

### 9.7.3 Corruption Detection

You receive no notification when your intelligence is corrupted. The false data appears legitimate in all reports. Discovery comes only when you act on corrupted intelligence and confront reality.

An invasion force planned around corrupted fleet strength reports may find itself outnumbered 2:1. Economic projections based on false colony output data lead to strategic miscalculations. Tech level assessments showing inferior enemy research may be dangerously wrong.

The uncertainty introduced by potential corruption creates strategic depth. Can you trust this scout report? Is the enemy weaker than they appear, or is your intelligence compromised? Counter-intelligence investment becomes critical not just for stopping enemy espionage but for ensuring your own intelligence remains reliable.

## 9.11 Intelligence Staleness

Intelligence ages over time. A scout report from five turns ago may no longer reflect current reality. The enemy could have moved fleets, constructed new ships, or abandoned positions.

The intelligence system tracks staleness for all reports, noting turns elapsed since observation. Your intelligence analysts flag aged reports so you can assess reliability. Fresh intelligence (0-1 turns old) is highly reliable. Moderate age (2-3 turns) introduces some uncertainty. Old intelligence (4+ turns) may be significantly outdated.

Staleness affects different intelligence types differently. Fleet positions become stale quickly as ships move between systems. Colony statistics age more slowly since population and industry change gradually. Technology levels are relatively stable until research breakthroughs occur.

Strategic planning must account for intelligence age. Old reports provide historical context but shouldn't drive tactical decisions. Fresh intelligence drives immediate action.

## 9.9 Intelligence Database

Your House maintains a comprehensive intelligence database storing all reports chronologically. The database indexes intelligence by target house, system, and report type, enabling rapid access to relevant information.

The database supports strategic analysis by providing historical context. You can review enemy fleet movements over ten turns, track colony development over time, or analyze construction patterns. This historical depth reveals strategic intentions and enables prediction.

Intelligence Theft espionage operations steal a target house's entire intelligence database, giving you access to everything they know about the galaxy, including their intelligence on your own forces and those of other houses. This high-value operation can reveal enemy strategic plans, planned offensives, and alliance negotiations.

Database contents remain confidential unless stolen through espionage. No house can see what intelligence other houses possess except through Intelligence Theft operations.

## 9.10 Strategic Use of Intelligence

Superior intelligence enables your strategic advantage. With comprehensive enemy intelligence, you can plan invasions with confidence, anticipate enemy movements, and identify vulnerabilities for exploitation.

Intelligence investment creates a positive feedback loop. Better intelligence enables better strategic decisions. Better decisions lead to stronger position. Stronger position enables more aggressive reconnaissance. More reconnaissance provides better intelligence.

However, intelligence gathering is expensive. Scout missions risk detection and destruction. Espionage operations cost EBP points and face counter-intelligence. Maintaining comprehensive intelligence on multiple rivals requires significant resource allocation.

Your strategic intelligence priorities must align with campaign objectives. If planning to invade House Atreides, invest heavily in Atreides intelligence to identify weak colonies and fleet deployments. If concerned about House Harkonnen expansion, focus intelligence gathering on their core systems and fleet movements.

Intelligence also reveals opportunities. Scout reports showing an enemy colony with minimal defenses suggest invasion targets. Fleet movement tracking reveals undefended systems. Economic intelligence identifies houses with financial weakness.

## 9.11 Intelligence in Combat

Combat reveals perfect intelligence temporarily. When forces engage, both sides see complete enemy compositions. This intelligence persists in post-combat reports, providing detailed assessment of enemy ship classes, tech levels, and fleet strength.

Observers gain the same intelligence benefits without combat risk. Positioning scouts to observe anticipated battles provides perfect intelligence on both combatants. This is particularly valuable when rival houses fight each other, revealing their military capabilities without your direct involvement.

Combat intelligence can be surprising. Visual sightings suggested a small enemy force. Combat reveals advanced tech levels and hull integrity that make the force much stronger than anticipated. Corrupted pre-combat intelligence leads to disastrous engagements.

The intelligence advantage in combat is why surprise attacks are so valuable. Cloaked Raiders achieve surprise through detection evasion, denying enemies time to assess force strength before engagement. By the time the enemy realizes the threat, combat has already begun.
