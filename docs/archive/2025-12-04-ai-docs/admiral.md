# Admiral Module - Strategic Fleet Management

The Admiral module provides high-level strategic oversight for RBA AI fleet operations and build planning.

## Core Philosophy: Act+Personality System

The Admiral's strategic decisions are driven by two complementary systems:

### Acts: WHAT to prioritize (Strategic Objectives)

Acts define the game's strategic phases and what objectives matter most:

- **Act 1 (Land Grab)**: Expansion is paramount
  - Primary goal: Claim as many systems as possible
  - Secondary considerations: Maintain minimal defense
  - Build focus: Colony ships (ETACs), expansion infrastructure

- **Act 2 (Rising Tensions)**: Preparation for conflict
  - Primary goal: Build intelligence network (ELI mesh)
  - Secondary goals: Establish defenses, prepare offensive capability
  - Build focus: Scouts, defensive fleets, production colonies

- **Act 3 (Total War)**: Active warfare
  - Primary goal: Prosecute military campaigns
  - Secondary goals: Protect production, maintain momentum
  - Build focus: Combat fleets, defenders, invasion forces

- **Act 4 (Endgame)**: Victory push
  - Primary goal: Achieve victory conditions or survive
  - Secondary goals: Consolidate defenses, final offensives
  - Build focus: Maximum military output

### Personality: HOW to pursue objectives (Risk Tolerance)

Personality traits (especially `risk_tolerance`) modulate how aggressively each AI pursues Act objectives:

#### High Risk Tolerance (0.7+)
**Personalities**: Expansionist, Raider, Aggressive, Military-Industrial

**Behavior**:
- **Act 1**: Pure expansion, zero colony defense
  - "Grab everything, defend later"
  - Maximum colony acquisition speed
  - Homeworld-only protection

- **Act 2+**: Aggressive stance, minimal defense
  - "Best defense is a good offense"
  - Only defends high-value targets or direct threats
  - Prioritizes offensive capability over defensive coverage

**Strategic Trade-off**: Fast expansion and powerful offense, but vulnerable to raids

#### Medium Risk Tolerance (0.4-0.6)
**Personalities**: Balanced, Opportunistic, Espionage

**Behavior**:
- **Act 1**: Homeworld-only defense
  - "Secure the core, expand aggressively"
  - Fast expansion with minimal security
  - Colonies fend for themselves

- **Act 2+**: Balanced defense-offense mix
  - Standard defense thresholds
  - Responds to threats promptly
  - Maintains production security

**Strategic Trade-off**: Good expansion speed with reasonable security

#### Low Risk Tolerance (0.0-0.3)
**Personalities**: Turtle, Isolationist, Diplomatic, Economic, Tech-Rush

**Behavior**:
- **Act 1**: Cautious expansion with full defense
  - "Secure each colony before claiming the next"
  - Slower expansion, but safer
  - Defends all colonies immediately

- **Act 2+**: Comprehensive defense network
  - Proactive defense of all assets
  - Responds to even minor threats
  - High security, lower offensive tempo

**Strategic Trade-off**: Slower expansion but very difficult to raid

## Emergent Complexity

This simple 2-dimensional system (4 Acts × 3 Risk Tiers × 12 Personalities) creates rich emergent behaviors:

### Example 1: Expansionist vs Turtle in Act 1
- **Expansionist (risk=0.95)**:
  - Builds only ETACs and scouts
  - Claims 15+ systems in 10 turns
  - Homeworld has 1 defender, colonies have 0
  - Vulnerable to early aggression

- **Turtle (risk=0.3)**:
  - Builds ETACs + Destroyers in parallel
  - Claims 8-10 systems in 10 turns
  - Every colony has 1+ defenders
  - Difficult to attack, slower expansion

### Example 2: Act Transition Behaviors
- **Turn 15 (Act 1→Act 2 transition)**:
  - **Aggressive AI**: Continues expansion push, ignores defense gaps
  - **Balanced AI**: Shifts to reconnaissance, starts defending colonies
  - **Cautious AI**: Already has defenses, focuses on ELI mesh

### Example 3: Personality Diversity in Act 3 War
- **Raider (risk=0.9)**: All-in offense, minimal colony defenders
- **Balanced (risk=0.5)**: Equal offense/defense split
- **Turtle (risk=0.3)**: Heavy defense, limited offensives

## Build Requirements System

The Admiral generates prioritized build requirements based on tactical gap analysis:

### Requirement Priorities

- **Critical**: Must fulfill immediately (homeworld defense, existential threats)
- **High**: Important for strategic success (high-value colony defense, war prep)
- **Medium**: Should address but not urgent (standard colony defense, distance gaps)
- **Low**: Eventually needed (minor under-defense, optional reinforcement)
- **Deferred**: Skip for now (personality says not worth it)

### Gap Analysis

Admiral analyzes three categories of tactical gaps:

1. **Defense Gaps**: Undefended or under-defended colonies
2. **Reconnaissance Gaps**: Insufficient intel coverage (stale intel, unknown systems)
3. **Offensive Readiness**: Capability to execute military operations

Each gap is evaluated using:
- **Base severity** (from Act objectives)
- **Personality modulation** (risk tolerance adjustment)
- **Escalation** (persistence increases urgency)

### Example: Colony Defense Gap

**Scenario**: Medium-value colony (30 industry), no defenders, no nearby threats

**Act 1 Priorities**:
- High risk: Deferred (pure expansion focus)
- Medium risk: Deferred (homeworld-only)
- Low risk: Medium (defend during expansion)

**Act 2 Priorities**:
- High risk: Deferred (focus on offense)
- Medium risk: Low (eventually defend)
- Low risk: Medium (prepare defenses now)

**Act 3 Priorities**:
- High risk: Low (meh, offense > defense)
- Medium risk: Medium (important in war)
- Low risk: High (critical to defend all!)

## Integration with Budget System

Admiral requirements feed into the budget allocation system:

1. **Admiral runs BEFORE build orders** (critical ordering!)
2. Admiral generates requirements with priorities and cost estimates
3. Budget system allocates PP across objectives (Expansion, Defense, etc.)
4. Build system fulfills requirements in priority order within budget limits
5. Unfulfilled requirements carry forward to next turn (with escalation)

### Why Ordering Matters

**Wrong**: Build orders → Admiral generates requirements
- Result: Budget already spent, requirements unfulfilled forever

**Right**: Admiral generates requirements → Build orders execute them
- Result: Requirements drive spending, budget allocated appropriately

## Future Enhancements

Potential extensions to the Act+Personality system:

### More Personality Traits
- `aggression`: Willingness to initiate attacks
- `expansion_drive`: Priority of new colonies vs developing existing
- `economic_focus`: Production efficiency vs military output
- `tech_priority`: Research investment priority

### Act-Specific Objectives
- Act 2 reconnaissance quotas (% map revealed)
- Act 3 offensive momentum (attacks per turn)
- Act 4 victory condition focus

### Dynamic Act Transitions
- Early Act 2 if strong neighbor detected
- Skip Act 2 if already dominant
- Emergency defensive Act if under attack

### Escalation System
- Persistent defense gaps increase priority over turns
- Successful raids trigger defensive reinforcement
- Failed offensives reduce offensive readiness targets

## Module Structure

```
admiral/
├── README.md                    # This file
├── fleet_analysis.nim          # Fleet state analysis
├── defensive_ops.nim           # Defensive fleet operations
├── offensive_ops.nim           # Offensive fleet operations
├── staging.nim                 # Fleet staging and coordination
└── build_requirements.nim      # Requirement generation (Act+Personality logic)
```

## Key Implementation Notes

1. **Personality is per-AI, Acts are per-game-state**
   - Each house has ONE personality for entire game
   - All houses transition Acts together based on turn number

2. **Requirements are regenerated each turn**
   - Fresh tactical analysis every turn
   - Escalation tracks persistence of unmet needs
   - No stale requirements

3. **Budget constraints are respected**
   - Admiral requests, budget system decides
   - Unfulfilled requirements logged as warnings
   - Not an error - just budget prioritization

4. **Homeworld always protected**
   - Critical priority regardless of Act or Personality
   - Single universal exception to personality modulation

## Testing the System

To observe personality diversity:

```bash
# 30-turn test showing Act 1 → Act 2 transition
./tests/balance/run_simulation 30 | grep "Admiral generated"

# See personality-driven decisions
./tests/balance/run_simulation 30 | grep "risk_tolerance"

# Track unfulfilled requirements
./tests/balance/run_simulation 50 | grep "unfulfilled"
```

Expected behaviors:
- **Act 1**: High-risk AIs generate 0 defense requirements
- **Act 1**: Low-risk AIs generate many defense requirements
- **Act 1→2**: All AIs shift to defense, but different priorities
- **Act 2+**: Aggressive AIs still have fewer requirements than cautious
