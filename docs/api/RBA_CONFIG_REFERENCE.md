# EC4X RBA Configuration Reference

Complete reference for tuning Rule-Based AI personalities and behavior via `config/rba.toml`.

## Table of Contents
1. [Overview](#overview)
2. [Strategy Personalities](#strategy-personalities)
3. [Budget Allocations](#budget-allocations)
4. [Tactical Parameters](#tactical-parameters)
5. [Strategic Parameters](#strategic-parameters)
6. [Economic Parameters](#economic-parameters)
7. [Orders Parameters](#orders-parameters)
8. [Logistics Parameters](#logistics-parameters)
9. [Fleet Composition](#fleet-composition)
10. [Threat Assessment](#threat-assessment)
11. [Tuning Guidelines](#tuning-guidelines)

## Overview

### Configuration Philosophy

The RBA configuration system enables:
- ✅ **Balance testing without recompilation** - Iterate rapidly on AI behavior
- ✅ **Genetic algorithm parameter evolution** - Automated personality optimization
- ✅ **A/B testing** - Compare different AI configurations scientifically
- ✅ **Rapid iteration** - Tweak, test, analyze in minutes

### File Location

**Config file:** `config/rba.toml`
**Loader:** `src/ai/rba/config.nim`
**Usage:** Loaded automatically when RBA initializes

### Reloading Configuration

```bash
# Configuration is loaded at program start
# Changes require restart for RBA-based tests
nimble testBalanceQuick

# For persistent testing, edit config → run test → analyze → repeat
vim config/rba.toml
nimble testBalanceAct1
python3 tests/balance/analyze_results.py
```

## Strategy Personalities

### Personality Trait System

Each strategy defines 6 weighted traits (0.0-1.0) that influence decision-making:

| Trait | Range | Influences |
|-------|-------|------------|
| `aggression` | 0.0-1.0 | Attack timing, military spending, combat engagement thresholds |
| `risk_tolerance` | 0.0-1.0 | Bold moves vs cautious play, invasion timing, fleet split decisions |
| `economic_focus` | 0.0-1.0 | Production investment, tax rates, facility construction priority |
| `expansion_drive` | 0.0-1.0 | Colonization priority, ETAC production, colony infrastructure |
| `diplomacy_value` | 0.0-1.0 | Alliance seeking, treaty adherence, diplomatic investment |
| `tech_priority` | 0.0-1.0 | Research allocation, tech tree paths, prototype unit usage |

### 12 Built-In Strategies

#### [strategies_aggressive]
**Playstyle:** Early military rush, high-risk attacks
```toml
[strategies_aggressive]
aggression = 0.9           # Near-maximum military focus
risk_tolerance = 0.8       # Bold, aggressive moves
economic_focus = 0.5       # Moderate economy (to fuel military)
expansion_drive = 0.8      # High expansion for resources
diplomacy_value = 0.2      # Minimal diplomacy
tech_priority = 0.4        # Low tech investment
```

**Typical Behavior:**
- Builds combat fleets early (Act 1-2)
- Attacks with 0.4 strength ratio (aggressive threshold)
- Prioritizes military budget over research
- Ignores diplomatic opportunities

**Balance Testing:** Should win ~20-30% of games if balanced

---

#### [strategies_economic]
**Playstyle:** Patient empire builder, late-game power
```toml
[strategies_economic]
aggression = 0.3           # Defensive posture
risk_tolerance = 0.3       # Cautious, calculated moves
economic_focus = 0.9       # Maximum production investment
expansion_drive = 0.5      # Moderate expansion
diplomacy_value = 0.6      # Uses alliances for protection
tech_priority = 0.8        # Heavy tech investment
```

**Typical Behavior:**
- Builds infrastructure (IU, spaceports, shipyards) in Act 1-2
- Delays military until Act 3
- Invests heavily in research (20-25% of treasury)
- Forms defensive pacts

**Balance Testing:** Should survive early aggression and dominate late game

---

#### [strategies_espionage]
**Playstyle:** Intelligence-driven, sabotage specialist
```toml
[strategies_espionage]
aggression = 0.5           # Moderate military
risk_tolerance = 0.6       # Willing to take spy risks
economic_focus = 0.5       # Balanced economy
expansion_drive = 0.65     # Above-average expansion
diplomacy_value = 0.4      # Limited diplomacy
tech_priority = 0.6        # Focus on ELI/CLK tech
```

**Typical Behavior:**
- Commissions many scouts (9+ by Act 3)
- Runs SpyOnPlanet/HackStarbase missions
- Invests 3% of treasury in espionage operations
- Sabotages rival economies before attacking

**Balance Testing:** Intel advantage should offset lower military spending

---

#### [strategies_diplomatic]
**Playstyle:** Alliance builder, coalition warfare
```toml
[strategies_diplomatic]
aggression = 0.3           # Defensive
risk_tolerance = 0.4       # Cautious
economic_focus = 0.6       # Moderate economy
expansion_drive = 0.5      # Average expansion
diplomacy_value = 0.9      # Maximum diplomacy focus
tech_priority = 0.5        # Balanced tech
```

**Typical Behavior:**
- Forms multiple alliances early
- Coordinates attacks with allies
- Avoids solo aggression
- Builds reputation through treaty adherence

**Balance Testing:** Should leverage alliances to compete with stronger solo players

---

#### [strategies_balanced]
**Playstyle:** Jack-of-all-trades, adaptable
```toml
[strategies_balanced]
aggression = 0.4
risk_tolerance = 0.5
economic_focus = 0.7
expansion_drive = 0.5
diplomacy_value = 0.6
tech_priority = 0.5
```

**Typical Behavior:**
- Moderate in all areas
- Adapts to game state
- No extreme specialization
- Reliable baseline performance

**Balance Testing:** Should achieve ~25% win rate (reference benchmark)

---

#### [strategies_turtle]
**Playstyle:** Extreme defense, patient development
```toml
[strategies_turtle]
aggression = 0.1           # Minimal aggression
risk_tolerance = 0.3       # Very cautious
economic_focus = 0.7       # High economy
expansion_drive = 0.4      # Limited expansion
diplomacy_value = 0.7      # Seeks protection
tech_priority = 0.7        # Heavy tech focus
```

**Typical Behavior:**
- Builds starbases and defensive fleets
- Minimal territory expansion
- Heavy infrastructure investment
- Reactive, not proactive military

**Balance Testing:** Should survive but struggle to win (defensive bias)

---

#### [strategies_expansionist]
**Playstyle:** Maximum territory control, colony sprawl
```toml
[strategies_expansionist]
aggression = 0.6           # Moderate-high aggression
risk_tolerance = 0.7       # Willing to overextend
economic_focus = 0.4       # Lower economy (spread thin)
expansion_drive = 0.95     # Maximum expansion
diplomacy_value = 0.3      # Limited diplomacy
tech_priority = 0.3        # Minimal tech
```

**Typical Behavior:**
- Colonizes aggressively (ETACs every turn)
- Spreads infrastructure across many colonies
- Vulnerable to focused attacks
- Wins via territory control

**Balance Testing:** Should excel in large maps, struggle in small maps

---

#### [strategies_tech_rush]
**Playstyle:** Science advantage, prototype units
```toml
[strategies_tech_rush]
aggression = 0.2           # Low aggression
risk_tolerance = 0.4       # Moderate caution
economic_focus = 0.8       # High economy to fund research
expansion_drive = 0.4      # Limited expansion
diplomacy_value = 0.7      # Seeks alliances for time
tech_priority = 0.95       # Maximum tech focus
```

**Typical Behavior:**
- Invests 25% of treasury in research
- Rushes critical techs (WEP4, FD3, ELI5)
- Delays military until tech advantage
- Overwhelms with superior units late game

**Balance Testing:** Should lose early, dominate late if given time

---

#### [strategies_raider]
**Playstyle:** Hit-and-run, cloaked strikes
```toml
[strategies_raider]
aggression = 0.85          # Very high aggression
risk_tolerance = 0.9       # Maximum risk-taking
economic_focus = 0.4       # Moderate economy
expansion_drive = 0.6      # Moderate expansion
diplomacy_value = 0.1      # Minimal diplomacy
tech_priority = 0.5        # Focus on CLK tech
```

**Typical Behavior:**
- Builds cloaked Raider fleets
- Hit-and-run attacks on weak targets
- Avoids direct confrontation with strong fleets
- Disrupts enemy economy

**Balance Testing:** Should excel vs Turtle, struggle vs Aggressive

---

#### [strategies_military_industrial]
**Playstyle:** War economy, sustained military power
```toml
[strategies_military_industrial]
aggression = 0.7           # High aggression
risk_tolerance = 0.5       # Calculated risks
economic_focus = 0.75      # High economy for war machine
expansion_drive = 0.6      # Moderate expansion
diplomacy_value = 0.3      # Limited diplomacy
tech_priority = 0.6        # Balanced tech
```

**Typical Behavior:**
- Balances military and economic investment
- Builds many shipyards early
- Sustained fleet production
- Long-term military campaigns

**Balance Testing:** Should perform well in extended games (Act 3-4)

---

#### [strategies_opportunistic]
**Playstyle:** Adaptive, exploits weaknesses
```toml
[strategies_opportunistic]
aggression = 0.5           # Context-dependent
risk_tolerance = 0.6       # Moderate-high risk
economic_focus = 0.6       # Above-average economy
expansion_drive = 0.6      # Above-average expansion
diplomacy_value = 0.5      # Flexible diplomacy
tech_priority = 0.5        # Balanced tech
```

**Typical Behavior:**
- Attacks weak neighbors
- Avoids strong opponents
- Switches strategies mid-game
- Exploits game state opportunities

**Balance Testing:** Should perform consistently across scenarios

---

#### [strategies_isolationist]
**Playstyle:** Solo development, minimal interaction
```toml
[strategies_isolationist]
aggression = 0.15          # Very low aggression
risk_tolerance = 0.2       # Very cautious
economic_focus = 0.85      # Very high economy
expansion_drive = 0.3      # Minimal expansion
diplomacy_value = 0.2      # Avoids alliances
tech_priority = 0.75       # High tech
```

**Typical Behavior:**
- Focuses on internal development
- Avoids conflict and diplomacy
- Small but highly developed empire
- Late-game economic powerhouse

**Balance Testing:** Should struggle to win but survive consistently

---

## Budget Allocations

### 4-Act Budget Progression

Budget percentages determine PP allocation across 6 build objectives. Must sum to 1.0 per act.

#### Act 1: Land Grab (Turns 1-7)
**Focus:** Colony expansion and reconnaissance

```toml
[budget_act1_land_grab]
expansion = 0.35        # Colony ships (ETACs), spaceports
defense = 0.10          # Minimal defensive fleets
military = 0.10         # Small combat presence
reconnaissance = 0.40   # Maximum scout production (ELI mesh)
special_units = 0.05    # Transports for colonization
technology = 0.00       # No research investment yet
```

**Rationale:**
- Scouts essential for intelligence and unclaimed system discovery
- Early colonies compound economic advantage
- Combat is rare (diplomatic peace phase)
- Research deferred until income stabilizes

---

#### Act 2: Rising Tensions (Turns 8-15)
**Focus:** Infrastructure and early military buildup

```toml
[budget_act2_rising_tensions]
expansion = 0.30        # Continued colonization
defense = 0.20          # Defensive positioning
military = 0.30         # Combat fleet buildup
reconnaissance = 0.10   # Maintain scout network
special_units = 0.05    # Specialized units
technology = 0.05       # Begin research investment
```

**Rationale:**
- Expansion slows as prime colonies are claimed
- Military becomes necessary (early skirmishes)
- Defense protects infrastructure investment
- Research begins (WEP, FD, CST priorities)

---

#### Act 3: Total War (Turns 16-25)
**Focus:** Military dominance and combat operations

```toml
[budget_act3_total_war]
expansion = 0.10        # Minimal new colonies
defense = 0.15          # Defensive fleets at key systems
military = 0.45         # Maximum combat spending
reconnaissance = 0.05   # Scout maintenance only
special_units = 0.15    # Fighters, transports for invasions
technology = 0.10       # Sustained research for tech edge
```

**Rationale:**
- Territory established, focus shifts to conquest
- Military spending peaks (wars of aggression)
- Special units critical for 3-phase combat
- Tech advantage can decide battles

---

#### Act 4: Endgame (Turns 26-30)
**Focus:** Victory conditions and final assaults

```toml
[budget_act4_endgame]
expansion = 0.05        # Rare colonization
defense = 0.10          # Minimal defense
military = 0.55         # All-in military push
reconnaissance = 0.05   # Scout maintenance
special_units = 0.15    # Fighters/transports for final battles
technology = 0.10       # Tech edge matters in close fights
```

**Rationale:**
- Winner likely determined, focus on closing
- Maximum military spending for final push
- Defense minimal (offense wins games)
- Tech still matters (WEP4 vs WEP3 is huge)

---

### Budget Tuning Guidelines

**Increasing expansion budget:**
- Effect: More colonies, faster economic growth
- Risk: Spread too thin, vulnerable to aggression
- Test: Does expansionist strategy win >40%?

**Increasing military budget:**
- Effect: Stronger fleets, more successful attacks
- Risk: Neglected economy, can't sustain losses
- Test: Does aggressive strategy win >40%?

**Increasing technology budget:**
- Effect: Tech advantage, superior units
- Risk: Weaker short-term, vulnerable to early aggression
- Test: Does tech_rush survive to Act 3?

---

## Tactical Parameters

### Operational Limits

```toml
[tactical]
response_radius_jumps = 3        # Maximum distance for fleet response
max_invasion_eta_turns = 8       # Maximum ETA for invasions
max_response_eta_turns = 5       # Maximum ETA for defensive response
```

#### response_radius_jumps
**Default:** 3 jumps
**Purpose:** Limits how far fleets will move to respond to threats

**Effect of increasing:**
- Fleets respond to distant threats
- Better coordination across map
- Risk: Overextension, weakened local defense

**Effect of decreasing:**
- Fleets stay near home
- Stronger local defense
- Risk: Fails to respond to threats

**Tuning:** Increase for large maps (4+ rings), decrease for small maps

---

#### max_invasion_eta_turns
**Default:** 8 turns
**Purpose:** Maximum travel time for invasion fleets

**Effect of increasing:**
- Attacks across larger distances
- More strategic options
- Risk: Slow invasions, enemy prepares

**Effect of decreasing:**
- Only nearby invasions
- Faster attacks
- Risk: Limited targets

**Tuning:** Match to average game length (30% of total turns)

---

#### max_response_eta_turns
**Default:** 5 turns
**Purpose:** Maximum travel time for defensive reinforcements

**Effect of increasing:**
- Better defensive coverage
- Fewer successful invasions
- Risk: Defenders too strong

**Effect of decreasing:**
- Weaker defense
- More successful attacks
- Risk: Attackers too strong

**Tuning:** Balance attack success rate (~50-60%)

---

## Strategic Parameters

### Combat Engagement Thresholds

```toml
[strategic]
attack_threshold = 0.6           # Balanced personalities
aggressive_attack_threshold = 0.4 # Aggressive personalities
retreat_threshold = 0.3          # All personalities
```

#### attack_threshold
**Default:** 0.6 (balanced)
**Purpose:** Minimum strength ratio to initiate attack

**Calculation:** `ourStrength / theirStrength >= threshold`

**Effect of increasing (e.g., 0.8):**
- Requires overwhelming superiority
- Fewer attacks, more cautious
- Longer games, economic strategies excel

**Effect of decreasing (e.g., 0.5):**
- Attacks with moderate advantage
- More aggression, shorter games
- Military strategies excel

**Tuning:** Balance game length and aggression level

---

#### aggressive_attack_threshold
**Default:** 0.4 (aggressive personalities)
**Purpose:** Lower threshold for aggressive/raider strategies

**Effect:**
- Aggressive personalities attack with less advantage
- Differentiates risk-takers from balanced players
- Should be 0.6-0.8× of base threshold

---

#### retreat_threshold
**Default:** 0.3
**Purpose:** Strength ratio triggering retreat orders

**Effect of increasing (e.g., 0.5):**
- Fleets retreat earlier
- Fewer losses, but less aggressive
- Defensive advantage

**Effect of decreasing (e.g., 0.2):**
- Fleets fight longer
- Higher casualties
- Offensive advantage

---

## Economic Parameters

### Terraforming Costs

```toml
[economic]
terraforming_costs_extreme_to_desolate = 60
terraforming_costs_desolate_to_hostile = 150
terraforming_costs_hostile_to_harsh = 350
terraforming_costs_harsh_to_benign = 850
terraforming_costs_benign_to_lush = 2100
terraforming_costs_lush_to_eden = 5100
```

**Purpose:** PP cost for each planet class upgrade step

**Economic Strategy Impact:**
- High costs favor military strategies (conquest over development)
- Low costs favor economic strategies (terraforming pays off)

**Tuning:**
- Increase: Economic strategies weaken (terraforming too expensive)
- Decrease: Economic strategies strengthen (rapid development)

**Balance Target:** Terraforming should be viable but not dominant

---

## Orders Parameters

### Research and Espionage Investment

```toml
[orders]
research_max_percent = 0.25      # Maximum research budget
espionage_investment_percent = 0.03  # Espionage budget
scout_count_act1 = 5             # Scout targets by act
scout_count_act2 = 7
scout_count_act3_plus = 9
```

#### research_max_percent
**Default:** 0.25 (25% of treasury)
**Purpose:** Maximum PP allocation to research per turn

**Effect of increasing (e.g., 0.35):**
- Faster tech progression
- Tech rush strategies stronger
- Shorter tech race

**Effect of decreasing (e.g., 0.15):**
- Slower tech progression
- Military advantage lasts longer
- Longer tech race

**Tuning:** Balance tech vs military strategies

---

#### espionage_investment_percent
**Default:** 0.03 (3% of treasury)
**Purpose:** EBP/CIP investment for espionage operations

**Effect of increasing:**
- More espionage actions
- Espionage strategy stronger
- Intel advantage more significant

**Effect of decreasing:**
- Less espionage
- Military strategies dominate
- Intel less impactful

---

#### scout_count targets
**Purpose:** Target scout squadron count by game act

**Effect of increasing:**
- Better ELI mesh networks (+1 to +3 modifier)
- Improved Raider detection
- More intelligence gathering
- Higher scout maintenance costs

**Tuning:** Balance intel advantage vs cost

---

## Logistics Parameters

### Mothballing Thresholds

```toml
[logistics]
mothballing_treasury_threshold_pp = 900
mothballing_maintenance_ratio_threshold = 0.10
mothballing_min_fleet_count = 3
```

#### mothballing_treasury_threshold_pp
**Default:** 900 PP
**Purpose:** Treasury level below which AI considers mothballing fleets

**Effect of increasing:**
- AI mothballs more readily
- Lower maintenance costs
- Weaker military presence

**Effect of decreasing:**
- AI resists mothballing
- Higher maintenance
- Stronger military but economic strain

---

## Fleet Composition

### Doctrine-Based Ratios

```toml
[fleet_composition_balanced]
capital_ratio = 0.40    # Battlecruisers, Heavy Cruisers
escort_ratio = 0.40     # Destroyers, Frigates
specialist_ratio = 0.20 # Scouts, Raiders, Carriers

[fleet_composition_aggressive]
capital_ratio = 0.50
escort_ratio = 0.35
specialist_ratio = 0.15

[fleet_composition_defensive]
capital_ratio = 0.30
escort_ratio = 0.50
specialist_ratio = 0.20
```

**Purpose:** Target squadron composition ratios for fleet construction

**Tuning Effects:**
- High capital_ratio: Slower, powerful fleets (tank-heavy)
- High escort_ratio: Fast, numerous fleets (swarm tactics)
- High specialist_ratio: Flexible, utility-focused (scout/raider/carrier)

---

## Threat Assessment

### Threat Classification Thresholds

```toml
[threat_assessment]
critical_threshold = 0.8  # Enemy strength 80%+ of ours
high_threshold = 0.6      # Enemy strength 60-80% of ours
moderate_threshold = 0.4  # Enemy strength 40-60% of ours
low_threshold = 0.2       # Enemy strength 20-40% of ours
```

**Purpose:** Classify threat levels based on strength ratios

**Effect on AI behavior:**
- Critical threats trigger emergency responses (fleet recalls, defensive positioning)
- High threats increase defense budget allocation
- Moderate threats monitored, no immediate action
- Low threats ignored (expansion continues)

---

## Tuning Guidelines

### Iterative Balance Testing Workflow

```bash
# 1. Identify imbalance
nimble testBalanceAll4Acts
python3 analyze_results.py
# Output: "Aggressive wins 65% (target: 20-40%)"

# 2. Hypothesize fix
# "Aggressive too strong → increase attack threshold"
vim config/rba.toml
# Change: attack_threshold = 0.6 → 0.7

# 3. Test hypothesis
nimble testBalanceAll4Acts

# 4. Analyze results
python3 analyze_results.py
# Output: "Aggressive wins 42% (improved!)"

# 5. Iterate until balanced
# Repeat steps 2-4 until all strategies achieve 20-40% win rate
```

### Common Balance Issues

**Issue:** Aggressive strategy dominates (>50% win rate)
**Solutions:**
- Increase `attack_threshold` (0.6 → 0.7)
- Increase Act 1-2 `defense` budget (0.10 → 0.20)
- Decrease Act 2 `military` budget (0.30 → 0.20)

**Issue:** Economic strategy never wins (<10% win rate)
**Solutions:**
- Increase Act 3-4 `economic_focus` for all strategies (slow military buildup)
- Decrease `aggressive_attack_threshold` (makes early aggression riskier)
- Increase terraforming costs (economic advantage less impactful)

**Issue:** Tech rush gets crushed early
**Solutions:**
- Increase Act 1-2 `defense` budget
- Decrease `aggressive_attack_threshold` (fewer early attacks)
- Increase `research_max_percent` (faster tech progression)

**Issue:** Games too short (<15 turns)
**Solutions:**
- Increase `attack_threshold` (fewer attacks)
- Increase Act 1-2 `defense` budget (harder to conquer)
- Decrease Act 1-2 `military` budget (less offensive power)

**Issue:** Games too long (>40 turns)
**Solutions:**
- Decrease `attack_threshold` (more aggression)
- Increase Act 3-4 `military` budget (faster conquests)
- Decrease `retreat_threshold` (fewer retreats, decisive battles)

### Genetic Algorithm Tuning (Advanced)

**Purpose:** Automated optimization of RBA parameters

```bash
# Run genetic algorithm evolution
nimble evolveAI --generations 50 --population 20

# Output: Optimized personality weights
# strategies_aggressive: aggression=0.87 (was 0.9)
# strategies_aggressive: risk_tolerance=0.76 (was 0.8)
```

**Process:**
1. Generate population of personality variants
2. Run balance tests for each variant
3. Score by win rate distribution (target: 20-40% for all)
4. Breed best performers, mutate slightly
5. Repeat for N generations
6. Export best configuration to `config/rba.toml`

**See:** `tools/ai_tuning/genetic_algorithm.nim` (future implementation)

---

## See Also

- **[RBA Quick-Start Guide](RBA_QUICKSTART.md)** - Development patterns and usage
- **[Balance Testing README](../../tests/balance/README.md)** - Testing framework
- **[Analytics CLI](ANALYTICS_CLI.md)** - Data analysis tools
- **[Architecture Docs](../architecture/ai-system.md)** - AI system design
