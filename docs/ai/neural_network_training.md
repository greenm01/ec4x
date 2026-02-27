# Neural Network Training from LLM Bot Games

**Status:** Design Document (Post Play-Testing Phase)
**Last Updated:** 2026-02-27
**Dependencies:** LLM Playtesting Bot (`ec4x-bot`), GPU infrastructure

---

## Overview

We can train neural networks directly from high-quality games played by automated LLM bots (Claude, Gemini, Codex). This approach leverages modern imitation learning techniques pioneered by AlphaGo and similar systems. Instead of playing manually, we use `ec4x-bot` to parse the game state, prompt the LLM, and submit orders automatically (see `docs/bot/README.md`).

**Key Insight:** You don't need millions of expert games. Start with 10-20 high-quality LLM bot games, then bootstrap via self-play.

---

## Why LLM Bot Games?

LLM-driven games provide high-quality "expert demonstrations" for imitation learning, while also serving as engine validation. They offer:
- Expert-level strategic play derived from foundation models
- Explicit reasoning (LLM chain-of-thought explains WHY)
- Varied approaches to same situations (by changing prompts/models)
- High play-test value (validates engine balance)

---

## The AlphaGo-Inspired Approach

### Phase 1: Supervised Learning (Imitation)

**Goal:** Train network to mimic the LLM Bot's decisions

**Input:** Fog-of-war game state (what the LLM sees)
**Output:** Predicted orders (fleet movements, builds, research allocation)
**Loss Function:** How closely do predicted orders match Claude's actual orders?

**Data Required:** 10-20 complete games (~200-400 turn states)

**Training Time:** 1-3 days on modern GPU

### Phase 2: Self-Play (Bootstrapping)

**Goal:** Generate thousands of additional training examples

**Method:** Network plays against itself
- Winner: Positive reinforcement
- Loser: Negative reinforcement
- Both learn from experience

**Data Generated:** 1,000-10,000 games (automated, fast)

**Key Advantage:** Self-play discovers strategies Claude never showed you!

### Phase 3: Reinforcement Learning (Optimization)

**Goal:** Optimize for winning, not just imitating

**Method:**
- Reward: Prestige gains, battle victories, colony captures
- Penalty: Prestige losses, fleet destruction, elimination
- Policy gradient methods (PPO, A3C, etc.)

**Result:** Network learns to win, not just copy Claude

### Phase 4 (Optional): RLHF-Style Refinement

**Goal:** Human feedback fine-tuning

**Method:**
- Network plays games
- Claude reviews selected games
- "This strategy was brilliant" / "This was a mistake"
- Fine-tune with preference learning

**Benefit:** Combines network's breadth with Claude's strategic depth

---

## Training Data Format

### What Gets Captured from Each Turn

```json
{
  "game_id": 42,
  "turn": 5,
  "house_id": 1,

  "state": {
    // Economic
    "treasury": 1450,
    "income_last_turn": 180,
    "maintenance_cost": 45,

    // Military
    "total_ships": 47,
    "fleet_composition": {
      "destroyers": 15,
      "cruisers": 8,
      "carriers": 2,
      // ... all ship types
    },
    "fleet_positions": [
      {"id": 123, "system": 5, "composition": [...], "orders": "move"},
      {"id": 456, "system": 12, "composition": [...], "orders": "patrol"}
    ],

    // Colonies
    "colonies": [
      {
        "system_id": 1,
        "population": 840,
        "industrial": 420,
        "tax_rate": 25,
        "facilities": ["spaceport", "shipyard", "starbase"],
        "defense": {"armies": 12, "marines": 0, "batteries": 3}
      }
      // ... all colonies
    ],

    // Technology
    "tech": {"EL": 3, "SL": 1, "CST": 1, "WEP": 2, "TER": 1, "ELI": 1, "CIC": 1},

    // Intelligence (fog-of-war)
    "visible_enemy_fleets": [
      {"house": 3, "system": 8, "composition": {"frigates": 6}, "quality": "visual"}
    ],
    "scouted_systems": [
      {"system": 15, "class": "lush", "owner": null, "last_scouted": 5}
    ],

    // Diplomatic
    "diplomatic_status": {
      "house_2": "neutral",
      "house_3": "enemy",
      "house_4": "neutral"
    },

    // Strategic Context
    "prestige": 275,
    "prestige_rank": 2,
    "turns_played": 5
  },

  "claude_orders": {
    "fleets": [
      {
        "fleet_id": 123,
        "action": "move",
        "destination": 8,
        "reasoning": "Intercept enemy colonization. Intel shows 6 frigates."
      },
      {
        "fleet_id": 456,
        "action": "colonize",
        "destination": 15,
        "etac_count": 2,
        "reasoning": "System 15 is Lush (1200 PU). Secure buffer zone."
      }
    ],
    "colonies": [
      {
        "system_id": 1,
        "builds": ["destroyer", "destroyer", "army", "army", "army"],
        "tax_rate": 25,
        "reasoning": "Primary industrial world. Fleet reinforcement + defense."
      }
    ],
    "research": {
      "erp": 400,
      "srp": 150,
      "trp": 100,
      "reasoning": "Push EL4 for +20% production modifier (+120 PP/turn)."
    },
    "diplomacy": [
      {
        "house": 2,
        "action": "propose",
        "pact": "trade",
        "reasoning": "Distant neutral. Ally against House 3 threat."
      }
    ]
  },

  "outcome": {
    "next_turn_prestige": 280,
    "prestige_change": +5,
    "battles_won": 0,
    "battles_lost": 0,
    "colonies_gained": 1,
    "colonies_lost": 0
  }
}
```

### SQLite Extraction Query

```sql
-- Extract complete training example for turn N
SELECT
    -- Identifiers
    d.game_id,
    d.turn,
    d.house_id,

    -- Economic state
    d.treasury,
    d.income,
    d.maintenance_cost,
    d.production,

    -- Military state
    d.total_ships,
    d.corvette_ships,
    d.frigate_ships,
    d.destroyer_ships,
    -- ... all ship columns

    -- Colony state
    d.total_colonies,
    d.total_population,
    d.total_industrial,

    -- Tech state
    d.tech_el,
    d.tech_sl,
    d.tech_cst,
    d.tech_wep,
    d.tech_ter,
    d.tech_eli,
    d.tech_cic,

    -- Prestige
    d.prestige,
    d.prestige_change,

    -- Fleet tracking (join)
    f.fleet_id,
    f.system_id,
    f.orders,
    f.ship_composition,

    -- Orders (join with orders table)
    o.fleet_orders,
    o.colony_orders,
    o.research_allocation

FROM diagnostics d
LEFT JOIN fleet_tracking f ON d.game_id = f.game_id
                            AND d.turn = f.turn
                            AND d.house_id = f.house_id
LEFT JOIN orders o ON d.game_id = o.game_id
                   AND d.turn = o.turn
                   AND d.house_id = o.house_id
WHERE d.house_id = 1  -- Claude's house
ORDER BY d.turn;
```

---

## Network Architecture

### State Encoder (Input Processing)

```python
import torch
import torch.nn as nn

class GameStateEncoder(nn.Module):
    """
    Encode EC4X game state into fixed-size vector representation.
    Handles variable-length inputs (fleets, colonies) via attention.
    """
    def __init__(self, hidden_dim=256):
        super().__init__()

        # Economic state encoder
        self.economic_encoder = nn.Sequential(
            nn.Linear(10, 64),  # treasury, income, maintenance, etc.
            nn.ReLU(),
            nn.Linear(64, hidden_dim // 4)
        )

        # Military state encoder (ship counts)
        self.military_encoder = nn.Sequential(
            nn.Linear(18, 64),  # All ship type counts
            nn.ReLU(),
            nn.Linear(64, hidden_dim // 4)
        )

        # Tech state encoder
        self.tech_encoder = nn.Sequential(
            nn.Linear(7, 32),  # EL, SL, CST, WEP, TER, ELI, CIC
            nn.ReLU(),
            nn.Linear(32, hidden_dim // 4)
        )

        # Fleet encoder (handles variable number of fleets)
        self.fleet_encoder = nn.TransformerEncoder(
            nn.TransformerEncoderLayer(d_model=64, nhead=4),
            num_layers=2
        )

        # Colony encoder (handles variable number of colonies)
        self.colony_encoder = nn.TransformerEncoder(
            nn.TransformerEncoderLayer(d_model=64, nhead=4),
            num_layers=2
        )

        # Intelligence encoder (visible enemy activity)
        self.intel_encoder = nn.TransformerEncoder(
            nn.TransformerEncoderLayer(d_model=64, nhead=4),
            num_layers=2
        )

        # Combine all encodings
        self.combiner = nn.Sequential(
            nn.Linear(hidden_dim + 128, hidden_dim),  # +128 for fleet/colony/intel
            nn.ReLU(),
            nn.Linear(hidden_dim, hidden_dim)
        )

    def forward(self, state):
        # Encode fixed-size features
        econ = self.economic_encoder(state['economic'])
        mil = self.military_encoder(state['military'])
        tech = self.tech_encoder(state['tech'])

        # Encode variable-size features with attention
        fleets = self.fleet_encoder(state['fleets'])
        fleets = fleets.mean(dim=0)  # Pool over fleet dimension

        colonies = self.colony_encoder(state['colonies'])
        colonies = colonies.mean(dim=0)  # Pool over colony dimension

        intel = self.intel_encoder(state['intelligence'])
        intel = intel.mean(dim=0)  # Pool over intel reports

        # Combine all encodings
        combined = torch.cat([econ, mil, tech, fleets, colonies, intel], dim=-1)
        return self.combiner(combined)
```

### Policy Head (Decision Making)

```python
class EC4XPolicyNetwork(nn.Module):
    """
    Multi-headed policy network for different decision types.
    Predicts actions across fleets, colonies, research, and diplomacy.
    """
    def __init__(self, state_dim=256):
        super().__init__()

        # Shared state encoder
        self.encoder = GameStateEncoder(hidden_dim=state_dim)

        # Fleet action policy (per-fleet decisions)
        self.fleet_policy = nn.Sequential(
            nn.Linear(state_dim, 128),
            nn.ReLU(),
            nn.Linear(128, len(FleetAction))  # move, colonize, patrol, etc.
        )

        # Fleet destination policy (where to send fleets)
        self.destination_policy = nn.Sequential(
            nn.Linear(state_dim, 128),
            nn.ReLU(),
            nn.Linear(128, MAX_SYSTEMS)  # Probability distribution over systems
        )

        # Build policy (what to construct)
        self.build_policy = nn.Sequential(
            nn.Linear(state_dim, 128),
            nn.ReLU(),
            nn.Linear(128, len(ShipClass) + len(FacilityType))  # All buildable types
        )

        # Research allocation policy (ERP/SRP/TRP splits)
        self.research_policy = nn.Sequential(
            nn.Linear(state_dim, 64),
            nn.ReLU(),
            nn.Linear(64, 3),  # ERP, SRP, TRP percentages
            nn.Softmax(dim=-1)  # Ensure they sum to 100%
        )

        # Tax rate policy (per-colony)
        self.tax_policy = nn.Sequential(
            nn.Linear(state_dim, 64),
            nn.ReLU(),
            nn.Linear(64, 1),  # Tax rate 0-100%
            nn.Sigmoid()
        )

        # Diplomatic action policy
        self.diplomacy_policy = nn.Sequential(
            nn.Linear(state_dim, 64),
            nn.ReLU(),
            nn.Linear(64, len(DiplomaticAction))  # propose, accept, reject, etc.
        )

    def forward(self, state):
        # Encode game state
        encoded_state = self.encoder(state)

        # Compute all policy outputs
        return {
            'fleet_actions': self.fleet_policy(encoded_state),
            'fleet_destinations': self.destination_policy(encoded_state),
            'build_priorities': self.build_policy(encoded_state),
            'research_allocation': self.research_policy(encoded_state),
            'tax_rates': self.tax_policy(encoded_state),
            'diplomatic_actions': self.diplomacy_policy(encoded_state)
        }
```

### Value Head (Position Evaluation)

```python
class ValueNetwork(nn.Module):
    """
    Estimate expected prestige outcome from current state.
    Used for reinforcement learning and Monte Carlo Tree Search.
    """
    def __init__(self, state_dim=256):
        super().__init__()

        self.encoder = GameStateEncoder(hidden_dim=state_dim)

        self.value_head = nn.Sequential(
            nn.Linear(state_dim, 128),
            nn.ReLU(),
            nn.Linear(128, 64),
            nn.ReLU(),
            nn.Linear(64, 1),  # Predicted prestige advantage
            nn.Tanh()  # Normalized value [-1, 1]
        )

    def forward(self, state):
        encoded = self.encoder(state)
        return self.value_head(encoded)
```

### Multi-Task Network (Policy + Value + Reasoning)

```python
class ExplainableEC4XNetwork(nn.Module):
    """
    Combined network that predicts actions AND generates explanations.
    Trained on Claude's KDL comments to learn strategic reasoning.
    """
    def __init__(self, state_dim=256, vocab_size=10000):
        super().__init__()

        # Shared encoder
        self.encoder = GameStateEncoder(hidden_dim=state_dim)

        # Policy head (what to do)
        self.policy = EC4XPolicyNetwork(state_dim)

        # Value head (how good is this state)
        self.value = ValueNetwork(state_dim)

        # Reasoning head (why do this - text generation)
        self.reasoning_decoder = nn.TransformerDecoder(
            nn.TransformerDecoderLayer(d_model=state_dim, nhead=8),
            num_layers=4
        )
        self.reasoning_output = nn.Linear(state_dim, vocab_size)

    def forward(self, state, reasoning_prompt=None):
        encoded = self.encoder(state)

        policy = self.policy(state)
        value = self.value(state)

        # Generate reasoning if prompted
        reasoning = None
        if reasoning_prompt is not None:
            decoded = self.reasoning_decoder(reasoning_prompt, encoded)
            reasoning = self.reasoning_output(decoded)

        return {
            'policy': policy,
            'value': value,
            'reasoning': reasoning  # Text explaining the decision
        }
```

---

## Training Procedures

### Phase 1: Behavioral Cloning (Imitation Learning)

```python
import torch.optim as optim
from torch.utils.data import DataLoader

class ClaudeGameDataset(Dataset):
    """Load training examples from SQLite database."""
    def __init__(self, db_path, games):
        self.conn = sqlite3.connect(db_path)
        self.examples = self.load_examples(games)

    def load_examples(self, games):
        examples = []
        for game_id in games:
            # Query diagnostics + orders for all turns
            query = """
                SELECT d.*, o.fleet_orders, o.colony_orders, o.research
                FROM diagnostics d
                JOIN orders o ON d.game_id = o.game_id AND d.turn = o.turn
                WHERE d.game_id = ?
                ORDER BY d.turn
            """
            cursor = self.conn.execute(query, (game_id,))
            for row in cursor:
                state = self.parse_state(row)
                orders = self.parse_orders(row)
                examples.append((state, orders))
        return examples

    def __len__(self):
        return len(self.examples)

    def __getitem__(self, idx):
        return self.examples[idx]

def train_behavioral_cloning(network, dataset, epochs=100):
    """
    Train network to mimic Claude's decisions.
    Loss: Cross-entropy between predicted orders and Claude's actual orders.
    """
    dataloader = DataLoader(dataset, batch_size=32, shuffle=True)
    optimizer = optim.Adam(network.parameters(), lr=1e-3)

    for epoch in range(epochs):
        total_loss = 0
        for states, target_orders in dataloader:
            optimizer.zero_grad()

            # Forward pass
            predicted_orders = network(states)

            # Compute loss for each decision type
            fleet_loss = F.cross_entropy(
                predicted_orders['fleet_actions'],
                target_orders['fleet_actions']
            )
            build_loss = F.cross_entropy(
                predicted_orders['build_priorities'],
                target_orders['builds']
            )
            research_loss = F.mse_loss(
                predicted_orders['research_allocation'],
                target_orders['research']
            )

            # Combined loss
            loss = fleet_loss + build_loss + research_loss
            loss.backward()
            optimizer.step()

            total_loss += loss.item()

        print(f"Epoch {epoch}: Loss = {total_loss / len(dataloader):.4f}")
```

### Phase 2: Self-Play with Reinforcement Learning

```python
def self_play_episode(network1, network2, game_state):
    """
    Play one complete game between two networks.
    Returns trajectory of (state, action, reward) tuples.
    """
    trajectory = []
    current_player = network1

    while not game_state.is_terminal():
        # Get current state
        state = game_state.get_state(current_player.house_id)

        # Network predicts orders
        with torch.no_grad():
            orders = current_player(state)

        # Execute orders
        reward = game_state.execute_turn(orders)

        # Store experience
        trajectory.append((state, orders, reward))

        # Switch players
        current_player = network2 if current_player == network1 else network1

    # Final reward: who won?
    final_reward = game_state.get_final_prestige(network1.house_id)

    return trajectory, final_reward

def train_self_play(network, num_games=1000):
    """
    Self-play training loop.
    Network plays against itself to generate training data.
    """
    optimizer = optim.Adam(network.parameters(), lr=1e-4)

    for game_num in range(num_games):
        # Create fresh game
        game_state = EC4XGame(players=2, seed=game_num)

        # Play episode
        trajectory, final_reward = self_play_episode(network, network, game_state)

        # Train on trajectory with policy gradients
        for state, action, reward in trajectory:
            optimizer.zero_grad()

            predicted = network(state)

            # Policy gradient loss (REINFORCE algorithm)
            log_prob = compute_log_prob(predicted, action)
            loss = -log_prob * reward  # Negative because we maximize reward

            loss.backward()
            optimizer.step()

        if game_num % 100 == 0:
            print(f"Game {game_num}: Final Reward = {final_reward}")
```

### Phase 3: PPO (Proximal Policy Optimization)

```python
def train_ppo(network, old_network, num_iterations=1000):
    """
    More stable RL training with PPO algorithm.
    Used in AlphaGo, OpenAI Five, etc.
    """
    optimizer = optim.Adam(network.parameters(), lr=3e-4)

    for iteration in range(num_iterations):
        # Collect rollouts using old policy
        states, actions, rewards, advantages = collect_rollouts(
            old_network, num_games=10
        )

        # Train on collected data (multiple epochs)
        for epoch in range(5):
            for batch in iterate_batches(states, actions, rewards, advantages):
                optimizer.zero_grad()

                # Compute probability ratios
                new_log_probs = network.compute_log_prob(batch['states'], batch['actions'])
                old_log_probs = old_network.compute_log_prob(batch['states'], batch['actions'])
                ratio = torch.exp(new_log_probs - old_log_probs)

                # Clipped surrogate objective (PPO's key innovation)
                clipped_ratio = torch.clamp(ratio, 0.8, 1.2)
                loss = -torch.min(
                    ratio * batch['advantages'],
                    clipped_ratio * batch['advantages']
                ).mean()

                loss.backward()
                optimizer.step()

        # Update old network
        old_network.load_state_dict(network.state_dict())
```

### Phase 4: RLHF (Reinforcement Learning from Human Feedback)

```python
def train_with_claude_feedback(network, game_logs):
    """
    Fine-tune network using Claude's strategic evaluations.
    Similar to ChatGPT's RLHF training.
    """
    # Present games to Claude for review
    for game in game_logs:
        # Extract key decisions
        decisions = extract_key_moments(game)

        for state, network_action, outcome in decisions:
            # Ask Claude to rate this decision
            claude_rating = get_claude_evaluation(state, network_action, outcome)
            # Returns: {"rating": 7/10, "feedback": "Good economic focus but..."}

            # Train reward model to predict Claude's ratings
            predicted_rating = reward_model(state, network_action)
            loss = F.mse_loss(predicted_rating, claude_rating['rating'])
            loss.backward()

        # Use reward model to fine-tune policy
        # (Preference learning / DPO algorithm)
```

---

## Integration with EC4X Infrastructure

### Export Training Data from Game Database

**Script:** `scripts/export_training_data.py`

```python
import sqlite3
import json
import polars as pl

def export_claude_games_to_json(db_path, output_dir):
    """
    Extract all training examples from Claude games.
    One JSON file per game for easy batching.
    """
    conn = sqlite3.connect(db_path)

    # Get all Claude games
    games = pl.read_database(
        "SELECT DISTINCT game_id FROM diagnostics WHERE house_id = 1",
        conn
    )

    for game_id in games['game_id']:
        # Load full game trajectory
        df = pl.read_database(f"""
            SELECT
                d.*,
                o.fleet_orders,
                o.colony_orders,
                o.research_allocation
            FROM diagnostics d
            LEFT JOIN orders o ON d.game_id = o.game_id
                               AND d.turn = o.turn
            WHERE d.game_id = {game_id} AND d.house_id = 1
            ORDER BY d.turn
        """, conn)

        # Convert to training format
        training_examples = []
        for row in df.iter_rows(named=True):
            example = {
                'state': extract_state(row),
                'orders': extract_orders(row),
                'outcome': extract_outcome(row)
            }
            training_examples.append(example)

        # Save to JSON
        output_file = f"{output_dir}/game_{game_id}.json"
        with open(output_file, 'w') as f:
            json.dump(training_examples, f, indent=2)

        print(f"Exported game {game_id}: {len(training_examples)} turns")

def extract_state(row):
    """Convert SQL row to network input format."""
    return {
        'economic': {
            'treasury': row['treasury'],
            'income': row['income'],
            'maintenance': row['maintenance_cost'],
            'production': row['production']
        },
        'military': {
            'total_ships': row['total_ships'],
            'corvettes': row['corvette_ships'],
            'frigates': row['frigate_ships'],
            'destroyers': row['destroyer_ships'],
            # ... all ship types
        },
        'tech': {
            'EL': row['tech_el'],
            'SL': row['tech_sl'],
            'CST': row['tech_cst'],
            # ... all tech fields
        },
        # ... rest of state
    }
```

### Load Network for Live Play

**Module:** `src/ai/neural/network_player.nim`

```nim
import std/[json, httpclient]
import ../../../engine/types/game_state
import ../../../engine/types/orders

type
  NeuralNetworkPlayer* = object
    apiEndpoint*: string
    houseId*: HouseId

proc queryNetwork(player: NeuralNetworkPlayer, state: GameState): HouseOrders =
  ## Send game state to Python/PyTorch inference server
  ## Returns predicted orders

  let client = newHttpClient()
  let stateJson = state.toJson()

  let response = client.postContent(
    player.apiEndpoint & "/predict",
    body = stateJson
  )

  let ordersJson = parseJson(response)
  result = parseOrdersFromJson(ordersJson)

proc generateOrders*(player: NeuralNetworkPlayer,
                     game: GameState): HouseOrders =
  ## Neural network decides orders for this turn

  # Get fog-of-war filtered state
  let visibleState = createFogOfWarView(game, player.houseId)

  # Query network (via HTTP to Python inference server)
  result = player.queryNetwork(visibleState)

  # Validate orders (fog-of-war checks)
  validateOrders(game, result)
```

### Inference Server (Python/PyTorch)

**Script:** `scripts/neural/inference_server.py`

```python
from flask import Flask, request, jsonify
import torch

app = Flask(__name__)

# Load trained model
model = torch.load('models/ec4x_policy_v1.pt')
model.eval()

@app.route('/predict', methods=['POST'])
def predict():
    """
    Receive game state, return predicted orders.
    Called by Nim engine via HTTP.
    """
    state_json = request.json

    # Convert to tensor
    state = preprocess_state(state_json)

    # Run inference
    with torch.no_grad():
        orders = model(state)

    # Convert to KDL format
    orders_kdl = postprocess_orders(orders)

    return jsonify(orders_kdl)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
```

---

## Development Timeline

### Phase 0: Play-Testing (Already Planned)

**Duration:** 2-3 weeks
**Effort:** Play 10-20 complete games against Claude
**Output:**
- 200-400 turn states with expert orders
- Balance validation
- Engine bug identification

### Phase 1: Data Pipeline (Parallel with Play-Testing)

**Duration:** 3-4 days
**Effort:**
- Write SQLite → JSON export script
- Define state/order encoding format
- Create PyTorch dataset loader
- Test end-to-end data flow

**Output:** Training data ready for ML

### Phase 2: Initial Network Training

**Duration:** 1 week
**Effort:**
- Implement network architectures (encoder, policy, value)
- Train via behavioral cloning on Claude games
- Evaluate: Can network beat random player?
- Iterate on architecture

**Output:** First working neural network player

### Phase 3: Self-Play Bootstrapping

**Duration:** 2-3 weeks (mostly automated)
**Effort:**
- Implement self-play infrastructure
- Generate 1,000-10,000 games
- Train with PPO/A3C
- Evaluate: Can network beat simple heuristics?

**Output:** Strong neural network from self-play

### Phase 4 (Optional): RLHF Fine-Tuning

**Duration:** Ongoing (iterative)
**Effort:**
- Network plays games
- Claude reviews interesting moments
- Fine-tune based on feedback
- Repeat

**Output:** Human-aligned strategic AI

---

## Resource Requirements

### Compute (Training)

**GPU:**
- Minimum: RTX 3090 (24GB VRAM)
- Recommended: RTX 4090 or A100
- Cloud: AWS p3.2xlarge or p4d.24xlarge

**Training Time Estimates:**
- Phase 1 (Behavioral Cloning): 2-6 hours
- Phase 2 (Self-Play 1K games): 24-48 hours
- Phase 3 (Self-Play 10K games): 1-2 weeks

### Compute (Inference)

**CPU Inference:**
- Network predictions: ~50-100ms per turn
- Acceptable for turn-based game

**GPU Inference:**
- Network predictions: ~5-10ms per turn
- Overkill but possible

### Storage

**Training Data:**
- 10 games × 20 turns × 50KB per state = 10MB
- 1,000 self-play games = 1GB
- 10,000 self-play games = 10GB

**Model Checkpoints:**
- Small network: 50-100MB per checkpoint
- Large network: 500MB-1GB per checkpoint

### Development

**Skills Required:**
- PyTorch/JAX (Python ML frameworks)
- Reinforcement learning basics
- Nim ↔ Python interop (HTTP API or FFI)
- SQLite data extraction

**Libraries:**
- PyTorch (model + training)
- Polars (data processing)
- Flask/FastAPI (inference server)
- OpenAI Gym (optional, for RL environment)

---

## Development Path

| Milestone | Neural Network |
|-----------|---------------|
| **Play-testable opponent** | Day 0 (Claude) |
| **Training data collection** | Week 2-3 (play-testing) |
| **First working AI** | Week 4 (behavioral cloning) |
| **Strong AI** | Week 6-8 (self-play) |
| **Total time to strong AI** | **6-8 weeks** |

### Quality Comparison

Neural networks offer expert strategic depth by learning from high-quality play, adapt to opponents dynamically, and can be automatically tuned via training.

### Why Neural Network Wins

1. **Already play-testing with Claude** - Data collection is free
2. **Modern ML is mature** - AlphaGo techniques are well-understood
3. **Self-play scales** - Network improves beyond initial training
4. **No manual rules** - Discovers strategies you didn't think of
5. **GPU infrastructure exists** - Most developers have access

---

## Risk Mitigation

### Risk: Not Enough Training Data

**Problem:** 10-20 games might not be sufficient
**Mitigation:**
- Self-play generates thousands more games
- Use data augmentation (rotate map, swap houses)
- Start with simpler network architecture

### Risk: Network Doesn't Generalize

**Problem:** Overfits to Claude's specific strategies
**Mitigation:**
- Use regularization (dropout, weight decay)
- Self-play exposes network to different situations
- Validate on held-out Claude games

### Risk: Compute Too Expensive

**Problem:** GPU training costs add up
**Mitigation:**
- Use free tier: Google Colab, Kaggle kernels
- Rent cloud GPU only during training
- CPU inference is fine for turn-based game

### Risk: Integration Complexity

**Problem:** Nim ↔ Python communication
**Mitigation:**
- Simple HTTP API (Flask server)
- Alternative: Nim → ONNX → C++ inference
- Or: Pure Nim inference with arraymancer

### Risk: Network Makes Stupid Moves

**Problem:** AI does illegal or nonsensical actions
**Mitigation:**
- Validate all orders in Nim before execution
- Mask illegal actions during inference
- Fine-tune with RLHF to fix bad behaviors

---

## Future Enhancements

### Multi-Agent Training

Train separate specialists:
- **Economic AI**: Optimizes colony development
- **Military AI**: Optimizes fleet tactics
- **Diplomatic AI**: Optimizes alliance formation
- **Coordinator AI**: Combines specialist outputs

### AlphaZero-Style MCTS

Combine neural network with Monte Carlo Tree Search:
- Network evaluates positions
- MCTS explores best moves
- Even stronger than pure network

### Transfer Learning

Pre-train on similar games:
- Stellaris
- Civilization
- Master of Orion
- Then fine-tune on EC4X

### Continual Learning

Network keeps learning from human games:
- Store all multiplayer games
- Periodically retrain on new data
- AI evolves with the meta

---

## Getting Started (Post Play-Testing)

### Step 1: Export Training Data

```bash
# After playing 10 Claude games
python3 scripts/export_training_data.py \
    --db balance_results/diagnostics/game_*.db \
    --output training_data/

# Verify export
ls training_data/
# game_1.json  game_2.json  ...  game_10.json
```

### Step 2: Train Initial Network

```bash
# Install PyTorch
pip install torch torchvision torchaudio

# Run behavioral cloning
python3 scripts/neural/train_bc.py \
    --data training_data/ \
    --epochs 100 \
    --output models/ec4x_bc_v1.pt

# Check performance
python3 scripts/neural/evaluate.py \
    --model models/ec4x_bc_v1.pt \
    --test-games 5
```

### Step 3: Self-Play

```bash
# Generate 1000 games
python3 scripts/neural/self_play.py \
    --model models/ec4x_bc_v1.pt \
    --games 1000 \
    --output self_play_data/

# Train on self-play data
python3 scripts/neural/train_ppo.py \
    --init models/ec4x_bc_v1.pt \
    --data self_play_data/ \
    --output models/ec4x_ppo_v1.pt
```

### Step 4: Deploy

```bash
# Start inference server
python3 scripts/neural/inference_server.py \
    --model models/ec4x_ppo_v1.pt \
    --port 5000

# Test with Nim engine
./bin/run_simulation --ai-endpoint http://localhost:5000
```

---

## References

### Machine Learning

- **AlphaGo Paper** - "Mastering the game of Go with deep neural networks and tree search" (Nature 2016)
- **AlphaZero Paper** - "A general reinforcement learning algorithm that masters chess, shogi, and Go" (Science 2018)
- **OpenAI Five** - DOTA 2 AI using PPO and self-play
- **Spinning Up in Deep RL** - OpenAI's educational resource

### Imitation Learning

- **DAGGER** - Dataset Aggregation for Imitation Learning
- **Behavioral Cloning** - Learning from Expert Demonstrations
- **GAIL** - Generative Adversarial Imitation Learning

### Reinforcement Learning

- **PPO** - Proximal Policy Optimization (stable, widely used)
- **A3C** - Asynchronous Advantage Actor-Critic
- **DQN** - Deep Q-Network (for discrete actions)
- **RLHF** - Reinforcement Learning from Human Feedback (ChatGPT's training method)

### PyTorch Resources

- [PyTorch Tutorial](https://pytorch.org/tutorials/)
- [PyTorch RL Examples](https://github.com/pytorch/examples/tree/master/reinforcement_learning)
- [Stable Baselines3](https://stable-baselines3.readthedocs.io/) - High-quality RL implementations

---

## Conclusion

Training neural networks from Claude games is highly effective:

✅ **Faster to strong AI** (6-8 weeks)
✅ **Better data quality** (expert demonstrations)
✅ **Play-testing synergy** (same games validate engine + provide training data)
✅ **Modern ML techniques** (AlphaGo approach is proven)
✅ **Scales naturally** (self-play generates unlimited data)

**Recommended path:**
1. Refactor engine (current work)
2. Play 10-20 games vs Claude (play-testing + data collection)
3. Train initial network (behavioral cloning, 1 week)
4. Self-play bootstrapping (automated, 2-3 weeks)
5. Deploy as AI opponent

---

**Document Status:** Design for post-play-testing phase
**Implementation Priority:** After 10-20 Claude games completed
**Dependencies:** Play-testing infrastructure, Python ML environment, GPU access

---

**Last Updated:** 2025-12-25
