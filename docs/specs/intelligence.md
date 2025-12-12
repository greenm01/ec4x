# 9.0 Intelligence System

Knowledge is power in EC4X. The intelligence system determines what you know about your rivals and when you know it. In the fog of war, victory often belongs to the House Duke who sees the battlefield most clearly.

## 9.1 Gathering Intelligence

Intelligence flows from multiple sources, each revealing different aspects of your enemies' capabilities and intentions.

### 9.1.1 Scout Reconnaissance (Perfect Quality)

Your scout squadrons are the eyes and ears of your House. When dispatched on reconnaissance missions, they gather comprehensive intelligence on enemy assets, movements, and capabilities. Scout reports include complete fleet compositions with tech levels and hull integrity, detailed colony statistics including economic output and construction projects, and strategic assessments of enemy patrol patterns and force deployments.

Scouts provide the highest quality intelligence available. Their reports are detailed, accurate, and current. However, even scout intelligence can be compromised. Houses that successfully plant disinformation in your intelligence network or those operating under the stigma of dishonor may corrupt scout reports with false data. See [Section 9.4](#94-intelligence-corruption) for details on intelligence reliability.

Scout missions are described in [Section 6.3.13-6.3.15](operations.md#6313-spy-on-a-planet-11) of the Operations manual.

### 9.1.2 Fleet Encounters

When your fleets encounter enemy forces in the same system, your captains automatically report what they observe. These visual sightings provide basic tactical intelligence: ship types, squadron sizes, and observable behavior such as patrol or blockade operations. You can count the enemy destroyers and cruisers, note the presence of transport vessels, and observe their standing orders.

Visual intelligence has natural limitations. Your captains cannot assess technological sophistication from a distance, determine hull damage states, or identify cargo contents. An enemy transport fleet shows only the number of ships, not whether they carry invasion troops, colonists, or equipment. Tech levels display as zero since there is no way to visually assess research advancement. This reflects the reality of tactical observation in space warfare.

### 9.1.3 Spy Operations (Spy Quality)

Your scout squadrons conducting espionage missions (SpyOnPlanet, SpyOnSystem, HackStarbase) penetrate deeper than visual observation. These covert operations provide economic intelligence, construction queue details, and technological assessments that visual sightings cannot reveal.

Planet surveillance exposes colony population, industrial capacity, defensive installations, and most critically, economic output and tax revenue. You learn what the colony produces and how much flows to the enemy treasury. System reconnaissance reveals full fleet dispositions including tech levels, hull integrity, and cargo manifests. Starbase hacking accesses financial records, research allocations, and technology advancement across all fields.

This level of detail transforms strategic decision-making. Knowing an enemy's economic strength and research focus allows you to predict their capabilities turns in advance.

### 9.1.4 Starbase Surveillance

Advanced sensor arrays installed on starbases monitor their system continuously. A starbase watches its home system, detecting non-stealthed fleet movements, combat activity, and bombardment operations. This active surveillance provides early warning of enemy fleet approaches and documents hostile activity in your territory.

Scouts and cloaked Raiders can evade starbase detection through stealth. Detection mechanics are described in [Section 7.1.3](operations.md#713-cloaking-and-detection).

## 9.2 Intelligence Reports

Your intelligence network generates detailed reports from all sources. These reports accumulate in your intelligence database, building a picture of enemy capabilities and activities over time.

### 9.2.1 Scout Encounter Reports

Scout encounters produce your most detailed intelligence reports. When scouts observe enemy fleets, the report includes complete squadron compositions, tech levels for all ships, hull integrity assessments, and cargo manifests for transport vessels. Fleet behavior patterns are noted, including standing orders and patrol routes.

Colony discoveries provide comprehensive settlement data. Your analysts learn population levels, industrial capacity, defensive installations, construction queues, and orbital defenses. Economic intelligence reveals gross output and net tax revenue. The construction queue shows what the enemy is building and how many turns remain to completion.

Combat observations document both sides' forces before battle, losses sustained during the engagement, and battle outcomes. Scouts witnessing bombardment or invasion operations report the attacking force composition and target defenses.

Each report is assigned a significance rating from 1-10 based on strategic value. Discovery of a major enemy colony rates 8/10. Observing a small fleet patrol might rate 5/10. Witnessing a major space battle between rival houses could rate 10/10 depending on strategic implications.

### 9.2.2 Fleet Movement Tracking

Your intelligence system maintains chronological records of enemy fleet sightings. Each observation notes the turn, system, and fleet composition. Over time, these sightings reveal movement patterns and patrol routes.

Your intelligence staff tracks last known positions for all enemy fleets. Repeated sightings in a predictable pattern indicate patrol routes or blockade stations. Time since last sighting (staleness) helps you assess whether intelligence remains current or has aged beyond reliability.

This historical tracking enables strategic prediction. If an enemy fleet has patrolled the same three-system route for five turns, you can anticipate its position and plan accordingly.

### 9.2.3 Combat Intelligence

Combat generates automatic intelligence reports for all participating forces. Before battle, both sides gain complete knowledge of enemy fleet composition, squadron breakdowns, spacelift cargo, and fleet orders. The fog of war lifts completely during combat - you see exactly what you're fighting.

Post-combat intelligence depends on survival. If your forces survive or retreat successfully, they report battle outcomes, losses sustained by both sides, and which enemy forces retreated. Complete annihilation provides no post-combat intelligence.

Combat observers (scout squadrons or neutral forces in system) witness the entire engagement and receive full intelligence reports without participating in the battle.

### 9.2.4 Diplomatic Intelligence

Major diplomatic events are public knowledge. All houses automatically receive intelligence reports when diplomatic states change (e.g., Neutral to Hostile, Hostile to Enemy, or vice-versa).

Diplomatic intelligence includes the houses involved, the nature of the event, and resulting status changes. This transparency reflects the political reality that major diplomatic shifts cannot be concealed in a small region of contested space.

See [Section 8.1](diplomacy.md#81-diplomacy) for complete diplomatic mechanics.

### 9.2.5 Espionage Detection

Counter-intelligence operations may detect enemy espionage attempts against your House. Detection reports identify the perpetrator (if discovered), the type of espionage attempted, the target system, and whether the operation succeeded or failed.

Failed espionage provides valuable counter-intelligence. Knowing your rivals attempted tech theft or sabotage reveals their strategic priorities and resource allocation. Repeated failed attempts indicate persistent espionage pressure requiring increased counter-intelligence investment.

## 9.3 Intelligence Quality Levels

Intelligence reports carry quality indicators reflecting reliability and detail level.

**None** indicates complete fog of war. You have no intelligence on the target. The system has never been scouted or visited by your forces.

**Visual** quality comes from fleet encounters. You see what's there but cannot assess technological sophistication or internal states. Ship types and counts are accurate. Tech levels, hull damage, and cargo contents remain unknown. This represents what your ship captains observe visually.

**Spy** quality comes from espionage operations. You gain economic data, tech levels, hull integrity assessments, and construction details. This penetrates beyond visual observation to reveal strategic information.

**Perfect** quality comes from scout reconnaissance and your own assets. All details are available, accurate, and current. Perfect quality intelligence forms the foundation of strategic planning.

Intelligence quality affects decision-making. Visual sightings reveal enemy presence but not capability. Spy-quality intelligence reveals capability but may lack real-time updates. Perfect quality intelligence provides complete situational awareness.

## 9.4 Intelligence Corruption

Intelligence can be compromised through enemy action or diplomatic dishonor. Corrupted intelligence introduces false data into your reports, potentially leading to catastrophic strategic miscalculations.

### 9.4.1 Disinformation

The Plant Disinformation espionage action corrupts your intelligence gathering systems. Enemy operatives inject false data into scout telemetry, alter sensor readings, and fabricate statistical reports. The corruption is sophisticated and designed to appear legitimate.

Disinformation persists for two turns after the enemy plants it. During this time, all your intelligence reports contain corrupted data with 20-40% variance from true values. Fleet strengths are inflated or deflated randomly. Colony statistics are distorted. Economic data is falsified. Tech levels are misreported.

The variance is significant enough to cause serious errors in strategic planning. An enemy fleet reported at 12 ships might actually have 7 or 17. A colony showing 8,000 PP monthly output might produce 5,000 or 11,000. You don't know your intelligence is corrupted until you act on false data and discover the truth through direct engagement.

Counter-Intelligence Sweeps can block disinformation attempts. Investing in counter-intelligence protection is the only defense against this insidious form of espionage.

See [Section 8.2.2](diplomacy.md#822-intelligence-warfare-actions) for disinformation mechanics and costs.

### 9.4.2 Dishonor and Intelligence Failure

Houses operating under Dishonored status suffer severe intelligence corruption. Dishonor stems from Non-Aggression pact violations and reflects deep organizational shame and demoralization. When your House is dishonored, your forces become disorganized, command structures falter, and intelligence gathering suffers catastrophic degradation.

Dishonored intelligence corruption is more severe than disinformation, introducing 50% variance into all intelligence reports. The corruption lasts three turns, matching the dishonor duration. Every report from every source - scouts, spies, visual sightings - contains wildly inaccurate data. Strategic planning becomes nearly impossible.

The final two houses remaining in the game are exempt from dishonor and its intelligence effects. This exception ensures the endgame remains decisive rather than random.

Dishonor mechanics are described in [Section 8.1.2](diplomacy.md#812-neutral).

### 9.4.3 Corruption Detection

You receive no notification when your intelligence is corrupted. The false data appears legitimate in all reports. Discovery comes only when you act on corrupted intelligence and confront reality.

An invasion force planned around corrupted fleet strength reports may find itself outnumbered 2:1. Economic projections based on false colony output data lead to strategic miscalculations. Tech level assessments showing inferior enemy research may be dangerously wrong.

The uncertainty introduced by potential corruption creates strategic depth. Can you trust this scout report? Is the enemy weaker than they appear, or is your intelligence compromised? Counter-intelligence investment becomes critical not just for stopping enemy espionage but for ensuring your own intelligence remains reliable.

## 9.5 Intelligence Staleness

Intelligence ages over time. A scout report from five turns ago may no longer reflect current reality. The enemy could have moved fleets, constructed new ships, or abandoned positions.

The intelligence system tracks staleness for all reports, noting turns elapsed since observation. Your intelligence analysts flag aged reports so you can assess reliability. Fresh intelligence (0-1 turns old) is highly reliable. Moderate age (2-3 turns) introduces some uncertainty. Old intelligence (4+ turns) may be significantly outdated.

Staleness affects different intelligence types differently. Fleet positions become stale quickly as ships move between systems. Colony statistics age more slowly since population and industry change gradually. Technology levels are relatively stable until research breakthroughs occur.

Strategic planning must account for intelligence age. Old reports provide historical context but shouldn't drive tactical decisions. Fresh intelligence drives immediate action.

## 9.6 Intelligence Database

Your House maintains a comprehensive intelligence database storing all reports chronologically. The database indexes intelligence by target house, system, and report type, enabling rapid access to relevant information.

The database supports strategic analysis by providing historical context. You can review enemy fleet movements over ten turns, track colony development over time, or analyze construction patterns. This historical depth reveals strategic intentions and enables prediction.

Intelligence Theft espionage operations steal a target house's entire intelligence database, giving you access to everything they know about the galaxy, including their intelligence on your own forces and those of other houses. This high-value operation can reveal enemy strategic plans, planned offensives, and alliance negotiations.

Database contents remain confidential unless stolen through espionage. No house can see what intelligence other houses possess except through Intelligence Theft operations.

## 9.7 Strategic Use of Intelligence

Superior intelligence enables your strategic advantage. With comprehensive enemy intelligence, you can plan invasions with confidence, anticipate enemy movements, and identify vulnerabilities for exploitation.

Intelligence investment creates a positive feedback loop. Better intelligence enables better strategic decisions. Better decisions lead to stronger position. Stronger position enables more aggressive reconnaissance. More reconnaissance provides better intelligence.

However, intelligence gathering is expensive. Scout missions risk detection and destruction. Espionage operations cost EBP points and face counter-intelligence. Maintaining comprehensive intelligence on multiple rivals requires significant resource allocation.

Your strategic intelligence priorities must align with campaign objectives. If planning to invade House Atreides, invest heavily in Atreides intelligence to identify weak colonies and fleet deployments. If concerned about House Harkonnen expansion, focus intelligence gathering on their core systems and fleet movements.

Intelligence also reveals opportunities. Scout reports showing an enemy colony with minimal defenses suggest invasion targets. Fleet movement tracking reveals undefended systems. Economic intelligence identifies houses with financial weakness.

## 9.8 Intelligence in Combat

Combat reveals perfect intelligence temporarily. When forces engage, both sides see complete enemy compositions. This intelligence persists in post-combat reports, providing detailed assessment of enemy ship classes, tech levels, and fleet strength.

Observers gain the same intelligence benefits without combat risk. Positioning scout squadrons to observe anticipated battles provides perfect intelligence on both combatants. This is particularly valuable when rival houses fight each other, revealing their military capabilities without your direct involvement.

Combat intelligence can be surprising. Visual sightings suggested a small enemy force. Combat reveals advanced tech levels and hull integrity that make the force much stronger than anticipated. Corrupted pre-combat intelligence leads to disastrous engagements.

The intelligence advantage in combat is why surprise attacks are so valuable. Cloaked Raiders achieve surprise through detection evasion, denying enemies time to assess force strength before engagement. By the time the enemy realizes the threat, combat has already begun.
