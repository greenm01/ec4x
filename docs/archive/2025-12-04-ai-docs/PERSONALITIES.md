# EC4X AI Personalities

## Overview

EC4X features **12 distinct AI personalities**, each representing a different strategic archetype. Personalities are defined by 6 continuous traits (0.0-1.0 scale) that influence all AI decisions.

**Personality Traits:**
- `aggression` - Willingness to engage in combat
- `riskTolerance` - Acceptance of uncertain outcomes
- `economicFocus` - Priority on infrastructure/production
- `expansionDrive` - Colony acquisition urgency
- `diplomacyValue` - Pact formation preference
- `techPriority` - Research investment priority

---

## The 12 Strategies

### 1. Aggressive (Harkonnen-style)
**"Strike first, strike hard"**

```nim
aggression: 0.9
riskTolerance: 0.8
economicFocus: 0.2
expansionDrive: 0.7
diplomacyValue: 0.1
techPriority: 0.3
```

**Play Style:**
- Early military buildup (fighters, escorts by turn 8)
- Attacks weak neighbors aggressively
- Minimal infrastructure investment
- Low diplomacy (breaks pacts readily)
- High risk tolerance (risky invasions)

**Strengths:** Strong early game, punishes weak opponents
**Weaknesses:** Vulnerable to tech/economic snowball, over-extends
**Counter:** Turtle defense + tech rush, then counterattack

---

### 2. Economic (Richese-style)
**"Money makes the galaxy turn"**

```nim
aggression: 0.2
riskTolerance: 0.3
economicFocus: 0.9
expansionDrive: 0.6
diplomacyValue: 0.5
techPriority: 0.7
```

**Play Style:**
- Maximal infrastructure (factories, shipyards)
- Defensive military (just enough to deter)
- Tech focus for economic efficiency
- Neutral diplomacy (pacts for stability)
- Late-game powerhouse

**Strengths:** Unstoppable once infrastructure matures
**Weaknesses:** Vulnerable early (low military), slow start
**Counter:** Aggressive rush before turn 15

---

### 3. Espionage (Ordos-style)
**"Knowledge is power"**

```nim
aggression: 0.3
riskTolerance: 0.7
economicFocus: 0.6
expansionDrive: 0.4
diplomacyValue: 0.4
techPriority: 0.8
```

**Play Style:**
- Heavy espionage investment (EBP/CIP)
- Stealth scouts for intel gathering
- Asymmetric warfare (sabotage)
- Tech advantage through stolen research
- Manipulative diplomacy

**Strengths:** Perfect information, disrupts opponents
**Weaknesses:** Expensive, requires finesse
**Counter:** Counter-intelligence, rapid expansion

---

### 4. Diplomatic (Corrino-style)
**"Words before weapons"**

```nim
aggression: 0.2
riskTolerance: 0.4
economicFocus: 0.6
expansionDrive: 0.5
diplomacyValue: 0.9
techPriority: 0.5
```

**Play Style:**
- Forms multiple pacts early
- Peaceful expansion through diplomacy
- Breaks pacts only when overwhelmingly superior
- Leverages alliances against common enemies
- Prestige-focused victory

**Strengths:** Stable borders, coordinated attacks
**Weaknesses:** Dependent on pact partners, slow military
**Counter:** Break pacts unexpectedly, divide alliances

---

### 5. Balanced (Atreides-style)
**"Honor and pragmatism"**

```nim
aggression: 0.5
riskTolerance: 0.5
economicFocus: 0.5
expansionDrive: 0.5
diplomacyValue: 0.5
techPriority: 0.5
```

**Play Style:**
- Well-rounded approach
- Adapts to circumstances
- No glaring weaknesses
- No dominant strength
- Consistent performance

**Strengths:** Flexible, no hard counters
**Weaknesses:** Master of none, can be out-specialized
**Counter:** Specialize to extremes (rush or turtle)

---

### 6. Turtle (Bene Gesserit-style)
**"Patience yields victory"**

```nim
aggression: 0.1
riskTolerance: 0.2
economicFocus: 0.7
expansionDrive: 0.3
diplomacyValue: 0.6
techPriority: 0.6
```

**Play Style:**
- Heavy defense (starbases, garrisons)
- Minimal expansion (quality > quantity)
- Long-term planning (tech + economy)
- Defensive pacts
- Late-game monster

**Strengths:** Nearly unbreakable defense, tech advantage
**Weaknesses:** Small territory, low prestige
**Counter:** Blockade economy, out-expand

---

### 7. Expansionist (Ixian-style)
**"Every star is ours"**

```nim
aggression: 0.4
riskTolerance: 0.6
economicFocus: 0.5
expansionDrive: 0.9
diplomacyValue: 0.3
techPriority: 0.4
```

**Play Style:**
- Maximum ETAC production
- Grab every colonizable system
- Spread thin but wide
- Prestige through colony count
- Risky overextension

**Strengths:** Huge territory, high prestige
**Weaknesses:** Thin defense, low development
**Counter:** Pick off weak colonies, force defensive spread

---

### 8. TechRush (Vernius-style)
**"Science conquers all"**

```nim
aggression: 0.2
riskTolerance: 0.4
economicFocus: 0.7
expansionDrive: 0.4
diplomacyValue: 0.5
techPriority: 0.9
```

**Play Style:**
- Maximal research investment
- Rush critical techs (weapons, shields)
- Small but elite military
- Tech advantage by turn 15
- Quality over quantity

**Strengths:** Superior units, economic efficiency
**Weaknesses:** Vulnerable during research phase
**Counter:** Early aggression before tech matures

---

### 9. Raider (Moritani-style)
**"Hit and run"**

```nim
aggression: 0.7
riskTolerance: 0.8
economicFocus: 0.3
expansionDrive: 0.5
diplomacyValue: 0.2
techPriority: 0.4
```

**Play Style:**
- Fast attack ships (scouts, raiders)
- Harassment over conquest
- Disrupts economy (blockades)
- Hit weak targets, flee from strong
- Annoying but not dominant

**Strengths:** Disruption, hard to pin down
**Weaknesses:** Can't hold territory, weak economy
**Counter:** Strong defense, ignore harassment

---

### 10. MilitaryIndustrial (Ginaz-style)
**"Peace through strength"**

```nim
aggression: 0.6
riskTolerance: 0.5
economicFocus: 0.7
expansionDrive: 0.6
diplomacyValue: 0.3
techPriority: 0.5
```

**Play Style:**
- Balanced military + economy
- Sustainable warfare
- Strong production base
- Constant fleet buildup
- Attrition warfare specialist

**Strengths:** Sustained military power, robust economy
**Weaknesses:** No extreme advantage, predictable
**Counter:** Extreme specialization (tech rush or zerg rush)

---

### 11. Opportunistic (Ecaz-style)
**"Seize the moment"**

```nim
aggression: 0.5
riskTolerance: 0.7
economicFocus: 0.6
expansionDrive: 0.6
diplomacyValue: 0.4
techPriority: 0.6
```

**Play Style:**
- High adaptability
- Attacks weak/distracted opponents
- Switches strategies mid-game
- Exploits enemy mistakes
- Unpredictable

**Strengths:** Flexible, exploits opportunities
**Weaknesses:** No clear identity, can be unfocused
**Counter:** Force commitment, don't show weakness

---

### 12. Isolationist (Tleilaxu-style)
**"Self-sufficiency is survival"**

```nim
aggression: 0.3
riskTolerance: 0.3
economicFocus: 0.8
expansionDrive: 0.4
diplomacyValue: 0.1
techPriority: 0.7
```

**Play Style:**
- Minimal interaction
- Self-contained economy
- Tech + infrastructure focus
- Defensive military only
- Solo victory path

**Strengths:** Independent, tech advantage, robust
**Weaknesses:** Small footprint, low prestige
**Counter:** Force interaction, blockade economy

---

## Strategy Matchups

### Rock-Paper-Scissors Dynamics

```
Aggressive > Economic (rush before buildup)
Economic > Turtle (outgrow defenses)
Turtle > Aggressive (wall off rush)

TechRush > Balanced (superior units)
Balanced > Raider (stable defense)
Raider > TechRush (disrupt research)

Expansionist > Isolationist (territory advantage)
Isolationist > Diplomatic (ignores pacts)
Diplomatic > Expansionist (coordinate against sprawl)

Espionage > TechRush (steal tech)
MilitaryIndustrial > Opportunistic (consistent pressure)
Opportunistic > Espionage (adaptability)
```

**Note:** These are *tendencies*, not guarantees. Map layout, execution quality, and luck matter.

---

## 4-Act Progression

How personalities evolve through game phases:

### Act 1: Land Grab (Turns 1-7)

**Dominant Strategies:**
- Expansionist (maximum colonies)
- Balanced (consistent growth)
- Economic (infrastructure foundation)

**Struggling:**
- Aggressive (too early for military payoff)
- Turtle (too defensive, loses territory)
- Espionage (expensive early)

---

### Act 2: Rising Tensions (Turns 8-15)

**Dominant Strategies:**
- Aggressive (military comes online)
- MilitaryIndustrial (balanced approach peaks)
- TechRush (tech advantage kicks in)

**Struggling:**
- Raider (still too weak)
- Isolationist (small footprint hurts)
- Diplomatic (pacts haven't matured)

---

### Act 3: Total War (Turns 16-25)

**Dominant Strategies:**
- Economic (mature infrastructure dominates)
- TechRush (superior tech overwhelming)
- Turtle (unbreakable + late-game power)

**Struggling:**
- Aggressive (overextended, weak economy)
- Expansionist (thin defense crumbles)
- Raider (can't hold conquests)

---

### Act 4: Endgame (Turns 26-30)

**Victory Conditions:**
- **Prestige:** Expansionist, Diplomatic
- **Elimination:** Economic, TechRush, Turtle
- **Survival:** Any with strong position

**Critical:** Position at turn 25 determines winners. Comebacks rare.

---

## Custom Personalities (Genetic Algorithms)

AI tuning tools can evolve custom personalities:

```bash
nimble evolveAI    # 50 generations, find optimal traits
```

**Discovered Archetypes (Example Results):**

```nim
# "The Conqueror" - Evolved dominant strategy
aggression: 0.85
riskTolerance: 0.72
economicFocus: 0.43
expansionDrive: 0.78
diplomacyValue: 0.08
techPriority: 0.31
# Win rate: 68% (overpowered, needs balance patch)

# "The Builder" - Economic specialist
aggression: 0.15
riskTolerance: 0.28
economicFocus: 0.94
expansionDrive: 0.52
diplomacyValue: 0.61
techPriority: 0.82
# Win rate: 61% (strong in 30+ turn games)
```

**Use Cases:**
- Balance testing (find exploits)
- Challenge modes (boss AI)
- Player modeling (learn from human behavior)

---

## House-Strategy Mappings

Default strategies for 12 Great Houses:

| House | Strategy | Rationale |
|-------|----------|-----------|
| Atreides | Balanced | Noble, honorable, adaptable |
| Harkonnen | Aggressive | Brutal, militaristic |
| Ordos | Espionage | Secretive, saboteurs |
| Corrino | Diplomatic | Emperor, political manipulation |
| Vernius (Ix) | TechRush | Technology masters |
| Moritani | Raider | Assassins, hit-and-run |
| Richese | Economic | Wealthy merchants |
| Ginaz | MilitaryIndustrial | Swordmasters, military excellence |
| Ecaz | Opportunistic | Flexible, adaptable |
| Tleilaxu | Isolationist | Xenophobic, self-contained |
| Ixian Confederacy | Expansionist | Rapid expansion focus |
| Bene Gesserit | Turtle | Patient, long-term planning |

**Note:** Houses are cosmetic - any house can use any strategy.

---

## Tuning & Balance

### Balance Goals

1. **No dominant strategy** - 50-60% win rate max across all strategies
2. **Cyclical dynamics** - Rock-paper-scissors relationships
3. **Act-appropriate strength** - Each strategy has a "peak act"
4. **Skill expression** - Better execution beats counter-strategy

### Balance Methodology

**Regression Testing:**
```bash
nimble testBalanceAll4Acts  # 400 games, all strategies
```

**Exploit Detection:**
```bash
nimble coevolveAI  # Competitive co-evolution exposes imbalances
```

**Diagnostic Analysis:**
```bash
nimble tuneAIDiagnostics  # 100 games + automatic analysis
```

### Known Balance Issues (Example)

```
Issue: Aggressive dominates Act 1-2 (65% win rate)
Fix: Increase early colony defense, reduce early fighter effectiveness

Issue: Turtle too weak in Act 1 (28% win rate)
Fix: Faster starbase construction, cheaper garrisons
```

---

## See Also

- [README.md](README.md) - AI documentation overview
- [ARCHITECTURE.md](ARCHITECTURE.md) - Modular AI system design
- [DECISION_FRAMEWORK.md](DECISION_FRAMEWORK.md) - How AI makes decisions
- `../../tools/ai_tuning/USAGE.md` - Genetic algorithm tools
- `../testing/BALANCE_METHODOLOGY.md` - Testing approach
