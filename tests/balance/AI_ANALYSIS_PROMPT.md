# AI Balance Analysis Prompt Template

## Instructions for AI Analysis

You are analyzing balance test data from EC4X, a 4X space strategy game. Your goal is to identify balance issues, evaluate strategic viability, and recommend specific config adjustments.

## Analysis Framework

### 1. Strategic Viability Analysis
- **Question**: Do all strategies have roughly equal win rates (±15%)?
- **Look for**:
  - Dominant strategies (>50% win rate)
  - Non-viable strategies (<10% win rate)
  - Rock-paper-scissors dynamics
  - Counter-play opportunities

### 2. Game Pacing Analysis
- **Question**: Is game progression smooth and engaging?
- **Look for**:
  - Runaway leader problems (one house dominates early and never loses)
  - Comeback mechanisms (can houses recover from setbacks?)
  - Stalemates (games that drag on with no progress)
  - Early eliminations (houses knocked out turn <30)

### 3. Economic Balance
- **Question**: Are economic growth curves appropriate?
- **Look for**:
  - Exponential vs linear growth patterns
  - Diminishing returns kicking in appropriately
  - Economic advantages translating to military power
  - Resource scarcity creating meaningful decisions

### 4. Military Balance
- **Question**: Is combat balanced and decisive?
- **Look for**:
  - Tech advantages being meaningful but not overwhelming
  - Numerical superiority vs quality tradeoffs
  - Defensive vs offensive balance
  - Fleet composition diversity

### 5. Espionage Effectiveness
- **Question**: Is espionage worth the investment?
- **Look for**:
  - Detection rates (too high = useless, too low = overpowered)
  - Impact of successful operations
  - Cost vs benefit analysis
  - Counter-intelligence effectiveness

### 6. Diplomatic Impact
- **Question**: Do diplomatic actions matter?
- **Look for**:
  - Pact violation consequences
  - Value of maintaining alliances
  - Diplomatic isolation effects
  - Betrayal incentives vs penalties

## Output Format

Provide analysis in this structure:

```json
{
  "summary": "Brief 2-3 sentence overview of balance state",
  "concerns": [
    {
      "severity": "critical|high|medium|low",
      "category": "strategy|economic|military|espionage|diplomatic|pacing",
      "issue": "Clear description of the problem",
      "evidence": "Specific metrics/patterns from data",
      "impact": "How this affects gameplay"
    }
  ],
  "recommendations": [
    {
      "priority": "high|medium|low",
      "config_file": "config/filename.toml",
      "parameter": "section.parameter_name",
      "current_value": 100,
      "suggested_value": 150,
      "rationale": "Why this change will improve balance",
      "expected_impact": "Predicted effect on gameplay"
    }
  ],
  "positive_findings": [
    "Things that are working well"
  ],
  "follow_up_tests": [
    "Additional test scenarios needed to verify balance"
  ]
}
```

## Specific Metrics to Examine

### From HouseSnapshot:
- `prestige` - Track leader changes and gaps
- `totalGCO` / `totalNCV` - Economic growth rates
- `totalFleetStrength` - Military buildup patterns
- `techLevels` - Technology progression rates
- `cumulativeGCO` / `cumulativeNCV` - Long-term accumulation

### From GameOutcome:
- `victoryType` - Are all victory types achievable?
- `victoryTurn` - Game length distribution
- `finalRankings` - Competitive spread

### From GameMetrics:
- `prestigeVolatility` - Game stability
- `leaderChanges` - Competitive dynamics
- `comebacksObserved` - Recovery potential
- `dominationGames` - Runaway leader frequency
- `closenessScore` - Overall competitiveness

## Common Balance Issues to Watch For

### Red Flags:
1. **Snowball Effect**: Winner at turn 20 wins 90%+ of games
2. **Useless Mechanics**: Certain actions never taken by AI
3. **Dominant Strategy**: One approach wins 60%+ of games
4. **Turtle Meta**: Defensive play strictly dominates
5. **Rush Meta**: Early aggression strictly dominates
6. **Tech Dominance**: Higher tech level = guaranteed win
7. **Economic Dominance**: Richest player always wins
8. **No Comebacks**: Last at turn 30 = eliminated by turn 50

### Green Flags:
1. **Strategic Diversity**: All strategies win 20-40% of games
2. **Dynamic Leadership**: Leader changes 3-7 times per game
3. **Meaningful Choices**: Clear tradeoffs in spending
4. **Recovery Potential**: Houses can recover from -500 prestige
5. **Multiple Paths**: Victory achievable via military, economic, or hybrid
6. **Timing Windows**: Early/mid/late game strategies all viable
7. **Counter-Play**: Every strategy has counters

## Example Analysis

**Sample Concern:**
```json
{
  "severity": "high",
  "category": "strategy",
  "issue": "Military rush strategy wins 65% of games",
  "evidence": "Aggressive AI won 13/20 games, average victory turn 45. Economic AI eliminated by turn 60 in 80% of losses.",
  "impact": "Economic strategy non-viable, game becomes pure military race"
}
```

**Sample Recommendation:**
```json
{
  "priority": "high",
  "config_file": "config/military.toml",
  "parameter": "ships.fighter.build_cost",
  "current_value": 10,
  "suggested_value": 15,
  "rationale": "Increase early military cost to slow rush timing, giving economic players time to build up",
  "expected_impact": "Rush timing delayed ~10 turns, economic players reach defensive threshold"
}
```

---

## How to Use This Prompt

1. **Run balance tests** to generate JSON files
2. **Copy this prompt** into your AI conversation
3. **Attach the JSON file** from balance_results/
4. **Ask**: "Please analyze this EC4X balance test data and provide recommendations"
5. **Review recommendations** and implement config changes
6. **Re-run tests** to verify improvements
7. **Iterate** until balance is achieved

---

## Additional Context for AI

### Game Design Goals:
- **Multiple Paths to Victory**: Military, economic, and hybrid strategies should all be viable
- **Meaningful Choices**: Players face interesting tradeoffs (offense vs defense, economy vs military, expansion vs consolidation)
- **Dynamic Games**: Leadership should change hands several times, comebacks should be possible
- **Strategic Depth**: Skilled play should be rewarded, but not create insurmountable advantages
- **Game Length**: Target 80-120 turns for competitive games
- **Elimination Balance**: Eliminations should be rare before turn 50, but possible after turn 80

### Config System:
- All game values are in TOML files under `config/`
- 13 config files with 2000+ parameters
- Changes to config files are automatically synced to documentation
- Test-driven balance: change config → run tests → analyze → repeat

### What Makes a Good Recommendation:
1. **Specific**: "Increase espionage.tech_theft.srp_percentage from 20 to 30"
2. **Justified**: References specific data from tests
3. **Testable**: Clear prediction of impact
4. **Scoped**: One or two related parameters, not wholesale changes
5. **Incremental**: 20-50% adjustments, not doubling/halving

### What to Avoid:
- Vague suggestions ("make espionage better")
- Wholesale redesigns ("change how combat works")
- Contradictory recommendations
- Changes without data support
- Over-tuning (adjusting too many things at once)

---

**Now please analyze the attached balance test data.**
