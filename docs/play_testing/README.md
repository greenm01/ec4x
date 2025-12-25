# EC4X Play-Testing Documentation

**Purpose:** Document play-testing approaches for EC4X engine validation and balance tuning.

---

## Documents

### [Claude as Opponent](claude_opponent.md)

**Status:** Design Document (Post-Refactor Implementation)

Play against Claude using KDL-formatted orders and fog-of-war SQLite state exports. This approach enables immediate play-testing without building AI systems.

**Key Benefits:**
- Zero AI development time
- Intelligent, explained decision-making
- Fast iteration on balance changes
- Transparent debugging (human-readable orders)
- Enforces fog-of-war correctly

**Use When:**
- Engine is refactored and stable
- Need to validate game mechanics
- Want to test balance and pacing
- Before investing in AI development

### [Neural Network Training](neural_network_training.md)

**Status:** Design Document (Post Play-Testing Phase)

Train neural networks using game data from Claude play-testing sessions. Uses modern imitation learning techniques (AlphaGo-style) to create strong AI opponents without building RBA first.

**Key Benefits:**
- Train from expert demonstrations (Claude's games)
- Faster to strong AI than RBA approach (6-8 weeks vs 8-12 weeks)
- Self-play bootstrapping (network improves beyond initial training)
- Leverages play-testing data (dual-purpose effort)
- Modern ML techniques (proven approach)

**Use When:**
- Have 10-20 complete Claude games
- Want GPU-based AI opponent
- Prefer data-driven over rule-based AI
- Have PyTorch/ML infrastructure

---

## Play-Testing Philosophy

EC4X is fundamentally a **social game** designed for human players (see [Game Spec](../specs/index.md)). The game specification explicitly states:

> Diplomacy is between humans. The server doesn't care how you scheme; it only processes the orders you submit.

### Development Priority Order

1. **Engine Correctness** ← Current focus (refactoring)
2. **Play-Testing** ← Claude-as-opponent approach
3. **Balance Tuning** ← Based on actual gameplay data
4. **Human Player Client** ← CLI or web interface
5. **AI Opponents** ← Only if needed (nice-to-have)

### Why This Order?

**Engine First:**
- AI can't test a broken engine
- Bugs caught by integration tests, not AI

**Play-Testing Second:**
- Validates mechanics feel good
- Identifies balance issues
- Provides real gameplay data
- Fast iteration without AI complexity

**Human Client Third:**
- Core experience is multiplayer
- AI is supplementary, not primary

**AI Last:**
- Only build if warranted
- By then, you know what "good play" looks like
- Can train on historical Claude games

---

## Current Status

**Engine:** Refactoring in progress (config system migrated to KDL)
**Play-Testing:** Design documented, implementation pending
**AI Development:** On hold until play-testing phase complete

See [TODO.md](../TODO.md) for current roadmap.

---

## Future Documents

As play-testing progresses, add documentation here:

- `balance_notes.md` - Observations from actual games
- `scenario_tests.md` - Specific test scenarios for mechanics
- `replay_analysis.md` - Post-game analysis and lessons
- `ai_requirements.md` - If/when AI is needed, document requirements

---

## Quick Reference

**Play-Test a Game (After Implementation):**

```bash
# 1. Start new game
./bin/ec4x new-game --players 2 --seed 42

# 2. Export Claude's state
./bin/ec4x export-state --house 1 --turn 2 > claude_state.txt

# 3. Share with Claude, get orders back
# (Copy orders_house1_turn3.kdl from Claude)

# 4. Execute turn
./bin/run_simulation --game game_42.db \
                     --orders orders_house1_turn3.kdl \
                     --pause-at-turn 3

# 5. Analyze results
./bin/ec4x show-results --game game_42.db --turn 3
```

See [claude_opponent.md](claude_opponent.md) for complete workflow and implementation details.

---

**Last Updated:** 2025-12-25
