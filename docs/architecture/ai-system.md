# EC4X AI System Architecture (Revised v2)

## Overview

The EC4X AI system uses **neural network self-play training** to create strategic AI opponents. The architecture is built as a **hybrid Nim + Python system** where rule-based AI provides bootstrapping data and neural networks learn optimal strategy through reinforcement learning.

**Architecture Decision:** 
- ❌ **Rejected:** LLM approach (Mistral-7B, llama.cpp, prompt engineering)
- ✅ **Selected:** Specialized neural networks trained via self-play on EC4X mechanics

**Why Neural Networks Beat LLMs for EC4X:**
1. **Game Complexity:** 3-phase combat (Space → Orbital → Planetary), fighter ownership tracking, capacity violations, ELI mesh networks, CLK/ELI arms race - too complex for text-based prompting
2. **Model Size:** 3.2MB vs 4GB (1,250x smaller)
3. **Inference Speed:** 10-20ms vs 3-5 seconds (150-500x faster)
4. **Learning Quality:** Game-specific patterns vs general language understanding
5. **Proven Approach:** AlphaZero defeated world champions in Go, Chess, Shogi

## Design Principles

1. **Modular**: AI components independent of core game engine
2. **Transport-Agnostic**: AI players work in both localhost and Nostr modes
3. **Hybrid Language**: Nim for game logic, Python for training
4. **Self-Play Pipeline**: Generate training data from AI vs AI games
5. **Production-Ready**: Fast inference with CPU or GPU

## Architecture Layers

```
┌──────────────────────────────────────────────────────────────┐
│              EC4X Game Engine (Nim)                          │
│  • Core game logic (src/engine/)                             │
│  • 3-phase combat (Space/Orbital/Planetary)                  │
│  • Fighter ownership tracking                                │
│  • ELI mesh networks & CLK detection                         │
│  • Capacity violation management                             │
└───────────────────────┬──────────────────────────────────────┘
                        │
            ┌───────────┴───────────┐
            ▼                       ▼
┌─────────────────────────┐  ┌────────────────────────────┐
│  Rule-Based AI (Nim)    │  │  Neural Network AI (Hybrid)│
│  tests/balance/         │  │                            │
│  ai_controller.nim      │  │  ┌──────────────────────┐  │
│                         │  │  │ Nim Inference Layer  │  │
│  • 2,800+ lines         │  │  │ src/ai/nn_player.nim │  │
│  • 7 strategy types     │  │  │ • ONNX Runtime       │  │
│  • Intelligence system  │  │  │ • Fast CPU inference │  │
│  • Fleet coordination   │  │  └──────────┬───────────┘  │
│  • Special unit tactics │  │             │              │
│                         │  │  ┌──────────▼───────────┐  │
│  Output:                │  │  │ Neural Networks      │  │
│  • Training data (JSON) │  │  │ • Policy network     │  │
│  • Baseline opponent    │  │  │ • Value network      │  │
│  • Bootstrap self-play  │  │  │ (ONNX format)        │  │
└─────────────────────────┘  │  └──────────────────────┘  │
                             └────────────────────────────┘
                                          │
                                          ▼
                             ┌────────────────────────────┐
                             │ Training Pipeline (Python) │
                             │ ai_training/               │
                             │ • PyTorch + ROCm           │
                             │ • Self-play generator      │
                             │ • AlphaZero-style RL       │
                             │ • Export to ONNX           │
                             └────────────────────────────┘
```

## Game Mechanics Overview (What AI Must Learn)

### 1. Three-Phase Combat System

**Phase 1: Space Combat** (operations.md:7.3)
- Fleet vs fleet in deep space
- Mobile defenders fight here
- ELI scouts detect cloaked Raiders
- Undetected Raiders get +4 CER ambush bonus
- Must win to proceed to orbital combat

**Phase 2: Orbital Combat** (operations.md:7.4)
- Guard fleets (didn't fight in space)
- Reserve fleets (50% AS/DS)
- Starbases (+2 CER, +2 ELI, critical protection)
- Unassigned squadrons
- NO ambush bonus (can't surprise prepared defenses)
- Must win to proceed to planetary assault

**Phase 3: Planetary Combat** (operations.md:7.5, 7.6)
- Bombardment (destroy ground batteries)
- Invasion (full assault, destroys 50% IU)
- Blitz (quick insertion, preserves IU)
- Planetary shields block bombardment
- Must clear all phases to capture colony

**AI Learning Challenge:** Sequence operations correctly (scout → space → orbital → planetary)

### 2. Fighter/Carrier Ownership System

**Fighter Ownership** (assets.md:2.4.1):

**Colony-Owned Fighters:**
- Commissioned at colony
- Count against colony capacity: `floor(PU / 100) × FD_multiplier`
- Require starbases: 1 per 5 fighters
- Never retreat from combat
- Defend colony automatically

**Carrier-Owned Fighters:**
- Loaded from colony (ownership transfers)
- Do NOT count against colony capacity while embarked
- Retreat with carrier
- Deploy for combat, re-embark after
- Can transfer back to colony (requires capacity)

**Capacity Violations:**
- Triggered by: PU loss, starbase destruction
- 2-turn grace period to resolve
- Resolution: build starbases, transfer PU, relocate fighters via carrier, disband excess
- Carriers resolve violations by loading excess fighters

**AI Learning Challenge:** 
- Track two types of fighter ownership
- Manage capacity dynamically (population changes, combat losses)
- Use carriers for fighter logistics (not just combat)

### 3. Scout Operational Modes

**Single-Scout Squadrons** (assets.md:2.4.2, operations.md:6.2.10-12):
- Required for espionage missions (SpyPlanet, SpySystem, HackStarbase)
- Minimize detection risk
- Vulnerable if discovered (no defensive escort)

**Multi-Ship Squadrons** (assets.md:2.4.2):
- Scouts auto-join capital ship squadrons (CC permitting)
- Form ELI mesh networks (+1 to +3 modifier)
- Detect cloaked Raiders in combat
- Provide fleet-wide intelligence bonus

**AI Learning Challenge:**
- Manually reorganize scouts for espionage (single-ship)
- Allow auto-commissioning for fleet support (multi-ship)
- Balance intelligence gathering vs combat support

### 4. ELI/CLK Arms Race

**Electronic Intelligence (ELI)** (assets.md:2.4.2):
- Scouts provide ELI capability
- Mesh network bonuses: 2-3 scouts (+1), 4-5 (+2), 6+ (+3)
- Starbases get +2 ELI bonus
- Detects spy scouts and cloaked Raiders
- Defensive technology (counter-offense)

**Cloaking Tech (CLK)** (assets.md:2.4.3):
- Raiders cloak entire fleets
- Undetected Raiders: Phase 1 attack + ambush bonus (+4 CER)
- Detection roll: ELI vs CLK (weighted average, dominant tech penalty)
- Offensive technology (stealth attack)

**Tech Race Dynamics:**
- Aggressive houses research CLK for Raiders
- Defensive houses research ELI for scouts
- Asymmetric warfare: CLK for first strike, ELI for detection
- Starbases (+2 ELI) are strong counter to Raiders

**AI Learning Challenge:**
- Assess opponent tech levels (CLK vs ELI)
- Research appropriate counter-tech
- Deploy Raiders when ELI advantage exists
- Build starbases to counter enemy Raiders

### 5. Fighter Doctrine & Advanced Carrier Ops

**Fighter Doctrine (FD)** (assets.md:2.4.1):
- Tech levels multiply fighter capacity
- FD I (base): 1.0x capacity
- FD II: 1.5x capacity
- FD III: 2.0x capacity
- Critical for fighter-heavy strategies

**Advanced Carrier Ops (ACO)** (assets.md:2.4.1):
- Increases carrier hangar capacity
- CV: 3 FS (base) → 4 FS (ACO II) → 5 FS (ACO III)
- CX: 5 FS (base) → 6 FS (ACO II) → 8 FS (ACO III)
- Synergy with FD research

**Starbase Infrastructure:**
- Required: 1 starbase per 5 fighter squadrons
- Provides logistics coordination
- Fighters remain operational if starbases destroyed (2-turn grace)

**AI Learning Challenge:**
- Research FD when approaching capacity (70%+)
- Research ACO after FD investment
- Build starbases proactively (not reactively)
- Use carriers for fighter relocation during capacity violations

### 6. Combat Initiative & Detection

**Initiative Order** (operations.md:7.3.1):
1. Undetected Raiders (Phase 1 - ambush)
2. Fighter Squadrons (Phase 2 - intercept)
3. Capital Ships (Phase 3 - main engagement)

**Pre-Combat Detection** (operations.md:7.1.3):
- All ELI units roll for Raider detection
- Starbases participate in detection for ALL phases:
  - Space Combat: detect but can't fight (screened)
  - Orbital Combat: detect AND fight
- Detection state persists across phases
- Raiders detected in space remain detected in orbital

**Ambush Bonus** (operations.md:7.3.3):
- **Space Combat:** Undetected Raiders get +4 CER
- **Orbital Combat:** NO ambush bonus (can't surprise defenses)
- Detection advantage ≠ ambush bonus

**AI Learning Challenge:**
- Build ELI mesh networks (multiple scouts per fleet)
- Position scouts strategically (defensive coverage)
- Deploy Raiders when detection odds favorable
- Understand detection ≠ ambush (different mechanics)

### 7. Guard vs Patrol Orders

**Guard Orders (04, 05)** (operations.md:6.2.4-6):
- Fleets do NOT fight in Space Combat
- Only engage in Orbital Combat
- Defend colony directly (layered defense)
- Can include Raiders (maintain cloaking until orbital phase)

**Patrol Orders (03)** (operations.md:6.2.4):
- Engage in Space Combat
- Actively seek hostile forces
- Patrol zones, gather intelligence

**Strategic Defense Layering:**
- Mobile patrols fight in space (first line)
- Guard fleets defend in orbit (second line)
- Starbases + ground forces (final line)

**AI Learning Challenge:**
- Assign aggressive fleets to patrol
- Assign defensive fleets to guard
- Create defense-in-depth (not all-or-nothing)

### 8. Reserve & Mothballed Fleets

**Reserve Fleets** (operations.md:6.2.17):
- 50% maintenance cost
- 50% AS/DS in combat
- Automatically guard colony (Order 05)
- Cost-effective planetary defense

**Mothballed Fleets** (operations.md:6.2.18):
- 0% maintenance cost (storage orbit)
- Cannot fight (screened)
- Emergency reactivate at 50% AS/DS
- Vulnerable if no active defenders
- Requires spaceport

**AI Learning Challenge:**
- Mothball excess fleets during peace (economic warfare)
- Keep reserves at threatened colonies (reactive defense)
- Reactivate when war begins (timing is critical)

### 9. Automated Seek Home

**Pre-Order Retreat** (operations.md:6.2.3):
- ETAC destination becomes enemy → abort mission
- Guard/blockade/patrol system falls → retreat
- Strategic retreat (orders become impossible)

**Post-Combat Retreat** (operations.md:7.3.5):
- ROE threshold exceeded → auto-assign Seek Home
- Begin movement immediately (same turn)
- Pathfinding through enemy territory
- No retreat if no valid destination → fight to death

**AI Learning Challenge:**
- Set appropriate ROE for fleet role
- Designate fallback systems proactively
- Don't over-commit to losing battles

## Component Details

### 1. Rule-Based AI (Nim) - Bootstrap System

**Location**: `tests/balance/ai_controller.nim` (2,800+ lines)

**Current Capabilities:**
- ✅ Strategic Diplomacy (pact formation, threat assessment)
- ✅ Intelligent Military (combat odds, 3-phase invasion assessment)
- ✅ Economic Intelligence (production tracking, target selection)
- ✅ Fleet Coordination (multi-fleet operations, strategic reserves)
- ✅ Comprehensive Build Logic (ship construction, garrison management)
- ✅ Personality Profiles (7 strategy types)

**Gaps to Address (Phase 2 Improvements):**
- ⏳ Fighter ownership tracking (colony vs carrier)
- ⏳ Capacity violation management (proactive, not reactive)
- ⏳ Scout operational mode switching (single vs multi-ship)
- ⏳ ELI mesh network coordination (multiple scouts per fleet)
- ⏳ CLK vs ELI strategic assessment (tech race dynamics)
- ⏳ Fighter Doctrine / ACO research timing
- ⏳ Defense layering (patrol + guard + reserve)

**Training Data Generation:**
```nim
# tests/balance/run_simulation.nim
import ai_controller

proc generateTrainingData(numGames: int) =
  for gameNum in 1..numGames:
    var state = initGameState(players = 4)
    var controllers = [
      newAIController(house1, AIStrategy.Aggressive),
      newAIController(house2, AIStrategy.Economic),
      newAIController(house3, AIStrategy.Balanced),
      newAIController(house4, AIStrategy.Turtle)
    ]
    
    while not state.isGameOver():
      # Generate orders for each AI
      for controller in controllers:
        let orders = controller.generateAIOrders(state, rng)
        
        # Record state-action pair
        saveTrainingExample(
          state = encodeGameState(state, controller.houseId),
          action = encodeOrders(orders),
          houseId = controller.houseId
        )
      
      # Resolve turn (includes all 3 combat phases)
      state = resolveTurn(state, allOrders)
    
    # Record final outcome for each house
    for houseId in state.houses.keys:
      let outcome = if state.winner == houseId: 1.0 else: 0.0
      updateTrainingDataWithOutcome(gameNum, houseId, outcome)
```

**Output Format:**
```json
{
  "game_id": "game_00001",
  "turn": 15,
  "house": "house-atreides",
  "state": {
    "treasury": 450,
    "prestige": 125,
    "tech_levels": {
      "EL": 2, "SL": 2, "CST": 2, "WEP": 1,
      "TER": 1, "ELI": 2, "CLK": 0, "SLD": 1,
      "CIC": 1, "FD": 1, "ACO": 0
    },
    "colonies": [
      {
        "system_id": "arrakis",
        "population": 85,
        "production": 180,
        "colony_owned_fighters": 3,
        "starbases": 1,
        "capacity_violation": false
      }
    ],
    "fleets": [
      {
        "fleet_id": "alpha",
        "location": "arrakis",
        "squadrons": [
          {"class": "Cruiser", "count": 2, "has_scout": true}
        ],
        "carrier_owned_fighters": 0
      }
    ],
    "intelligence": {
      "enemy_eli_levels": {"house-harkonnen": 2},
      "enemy_clk_levels": {"house-harkonnen": 1}
    }
  },
  "action": {
    "fleet_orders": [...],
    "build_orders": [...],
    "research_allocation": {
      "economic": 100,
      "science": 80,
      "technology": {"FD": 50, "ELI": 30}
    },
    "squadron_management": [
      {
        "action": "reorganize",
        "from_squadron": "scout-01",
        "create_single_scout": true,
        "reason": "prepare_espionage_mission"
      }
    ]
  },
  "outcome": 1.0
}
```

### 2. Neural Network AI Player

**Location**: 
- Nim inference: `src/ai/nn_player.nim` (new)
- Python training: `ai_training/` (new)
- Trained models: `models/*.onnx` (new)

**Architecture**:

**Policy Network** (suggests moves):
```python
class EC4XPolicyNet(nn.Module):
    def __init__(self):
        super().__init__()
        # Input: 600-dim game state encoding
        self.encoder = nn.Sequential(
            nn.Linear(600, 256),
            nn.ReLU(),
            nn.Dropout(0.2),
            nn.Linear(256, 128),
            nn.ReLU()
        )
        
        # Output: Action probabilities
        self.fleet_head = nn.Linear(128, 64)          # Fleet movement/orders
        self.build_head = nn.Linear(128, 32)          # Construction
        self.research_head = nn.Linear(128, 11)       # Tech allocation (11 fields)
        self.diplo_head = nn.Linear(128, 8)           # Diplomatic actions
        self.squadron_mgmt_head = nn.Linear(128, 16)  # Squadron reorganization
        
    def forward(self, state):
        features = self.encoder(state)
        return {
            'fleet': self.fleet_head(features),
            'build': self.build_head(features),
            'research': self.research_head(features),
            'diplomacy': self.diplo_head(features),
            'squadron': self.squadron_mgmt_head(features)
        }
```

**Value Network** (evaluates positions):
```python
class EC4XValueNet(nn.Module):
    def __init__(self):
        super().__init__()
        # Input: 600-dim game state encoding
        self.network = nn.Sequential(
            nn.Linear(600, 256),
            nn.ReLU(),
            nn.Dropout(0.2),
            nn.Linear(256, 128),
            nn.ReLU(),
            nn.Linear(128, 64),
            nn.ReLU(),
            nn.Linear(64, 1),  # Output: win probability
            nn.Tanh()          # [-1, 1] range
        )
    
    def forward(self, state):
        return self.network(state)
```

**State Encoding** (600 dimensions):
```python
def encodeGameState(state: GameState, houseId: HouseId) -> np.ndarray:
    """Encode game state as 600-dim vector for neural network input"""
    
    encoding = []
    
    # Economic state (60 dims)
    encoding += [
        state.houses[houseId].treasury / 1000.0,
        state.houses[houseId].prestige / 5000.0,
        len(getOwnedColonies(state, houseId)) / 20.0,
        totalProduction(state, houseId) / 500.0,
        # Colony capacity metrics
        totalColonyFighters(state, houseId) / 50.0,
        totalColonyCapacity(state, houseId) / 50.0,
        capacityViolationCount(state, houseId) / 5.0,
        # ... more economic indicators
    ]
    
    # Military state (120 dims)
    encoding += [
        totalFleetStrength(state, houseId) / 1000.0,
        scoutCount(state, houseId) / 10.0,
        raiderCount(state, houseId) / 10.0,
        carrierCount(state, houseId) / 10.0,
        capitalShipCount(state, houseId) / 20.0,
        # Fighter ownership tracking
        colonyOwnedFighters(state, houseId) / 50.0,
        carrierOwnedFighters(state, houseId) / 30.0,
        # Capacity metrics
        starbaseCount(state, houseId) / 20.0,
        fighterCapacityUtilization(state, houseId),  # 0.0-1.0
        # ... more military indicators
    ]
    
    # Tech state (60 dims) - All 11 tech fields
    for tech in [EL, SL, CST, WEP, TER, ELI, CLK, SLD, CIC, FD, ACO]:
        encoding.append(state.houses[houseId].techLevels[tech] / 5.0)
    # Tech race indicators
    encoding.append(getMaxOpponentELI(state, houseId) / 5.0)
    encoding.append(getMaxOpponentCLK(state, houseId) / 5.0)
    # ... more tech indicators
    
    # Diplomatic state (60 dims)
    for otherHouse in state.houses.keys:
        if otherHouse != houseId:
            encoding.append(diplomaticStateEncoding(...))
            encoding.append(relativeMilitaryStrength(...))
            encoding.append(relativeELI(...))
            encoding.append(relativeCLK(...))
    
    # Combat phase awareness (60 dims)
    encoding += [
        activeSpaceCombats(state, houseId) / 5.0,
        activeOrbitalCombats(state, houseId) / 5.0,
        activePlanetaryCombats(state, houseId) / 5.0,
        # Detection state tracking
        raiderDetectionRisk(state, houseId),  # 0.0-1.0
        opponentStarbaseCount(state) / 20.0,
        # ... more combat indicators
    ]
    
    # Strategic situation (240 dims)
    encoding += [
        uncolonizedSystemsCount / 50.0,
        threatenedColoniesCount / 10.0,
        blockadedColoniesCount / 5.0,
        guardFleetsCount / 10.0,
        patrolFleetsCount / 10.0,
        reserveFleetsCount / 5.0,
        mothballedFleetsCount / 5.0,
        # Squadron composition metrics
        singleScoutSquadrons / 5.0,  # For espionage
        multiScoutSquadrons / 10.0,  # For ELI mesh
        # ... more strategic indicators
    ]
    
    return np.array(encoding, dtype=np.float32)
```

**Nim Integration**:
```nim
# src/ai/nn_player.nim
import onnxruntime

type
  NeuralNetPlayer* = object
    houseId*: HouseId
    policyNet*: OnnxSession
    valueNet*: OnnxSession
    temperature*: float  # Exploration parameter

proc newNeuralNetPlayer*(houseId: HouseId, 
                         policyPath: string,
                         valuePath: string): NeuralNetPlayer =
  result.houseId = houseId
  result.policyNet = loadOnnxModel(policyPath)
  result.valueNet = loadOnnxModel(valuePath)
  result.temperature = 1.0

proc evaluatePosition*(player: NeuralNetPlayer, 
                       state: GameState): float =
  """Evaluate current position (win probability)"""
  let stateVector = encodeGameState(state, player.houseId)
  let value = player.valueNet.run(stateVector)[0]
  return value  # Returns [-1.0, 1.0]

proc generateOrders*(player: NeuralNetPlayer, 
                     state: GameState,
                     rng: var Rand): OrderPacket =
  """Generate orders using policy network"""
  let stateVector = encodeGameState(state, player.houseId)
  let actionProbs = player.policyNet.run(stateVector)
  
  # Sample actions from probability distribution
  result.fleetOrders = sampleFleetOrders(actionProbs["fleet"], state, rng)
  result.buildOrders = sampleBuildOrders(actionProbs["build"], state, rng)
  result.researchAllocation = sampleResearch(actionProbs["research"], state)
  result.diplomaticActions = sampleDiplomacy(actionProbs["diplomacy"], state, rng)
  result.squadronManagement = sampleSquadronMgmt(actionProbs["squadron"], state, rng)
  
  # Validate orders (neural net might produce invalid moves)
  if not validateOrders(result, state, player.houseId):
    # Fallback to rule-based AI
    return generateRuleBasedOrders(state, player.houseId, rng)
```

### 3. Training Pipeline (Python)

**Workflow**:

```
1. Bootstrap Phase (Rule-Based Data)
   └─▶ Run 10,000 games with enhanced ai_controller.nim
       └─▶ Generate 1.6M state-action-outcome examples
           └─▶ training_data/bootstrap/*.json

2. Supervised Learning Phase
   └─▶ Train policy network to imitate rule-based AI
       └─▶ Train value network to predict outcomes
           └─▶ Export to ONNX format
               └─▶ models/policy_v1.onnx, models/value_v1.onnx

3. Self-Play Reinforcement Learning Phase
   └─▶ Neural net plays against itself (4+ players)
       └─▶ Generate new training data
           └─▶ Retrain networks on new data
               └─▶ Export improved models
                   └─▶ Repeat for N iterations

4. Evaluation Phase
   └─▶ Neural net vs rule-based AI
       └─▶ Measure win rate improvement
           └─▶ Track ELO ratings
               └─▶ Deploy best model to production
```

**Training Script:**
```python
# ai_training/train_ec4x_network.py
import torch
import torch.nn as nn
from torch.utils.data import DataLoader
import json
from pathlib import Path

class EC4XDataset:
    def __init__(self, data_dir: Path):
        self.examples = []
        for json_file in data_dir.glob("*.json"):
            with open(json_file) as f:
                self.examples.append(json.load(f))
    
    def __len__(self):
        return len(self.examples)
    
    def __getitem__(self, idx):
        ex = self.examples[idx]
        state = encode_state(ex["state"])
        action = encode_action(ex["action"])
        outcome = ex["outcome"]
        return state, action, outcome

def train_policy_network(data_dir: Path, epochs: int = 20):
    """Train policy network to imitate rule-based AI"""
    dataset = EC4XDataset(data_dir)
    dataloader = DataLoader(dataset, batch_size=32, shuffle=True)
    
    policy_net = EC4XPolicyNet()
    optimizer = torch.optim.Adam(policy_net.parameters(), lr=1e-3)
    criterion = nn.CrossEntropyLoss()
    
    # Move to GPU if available (ROCm)
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    policy_net = policy_net.to(device)
    
    for epoch in range(epochs):
        total_loss = 0
        for state, action, outcome in dataloader:
            state = state.to(device)
            action = action.to(device)
            
            optimizer.zero_grad()
            pred_action = policy_net(state)
            loss = criterion(pred_action, action)
            loss.backward()
            optimizer.step()
            
            total_loss += loss.item()
        
        print(f"Epoch {epoch+1}/{epochs}, Loss: {total_loss/len(dataloader):.4f}")
    
    # Export to ONNX
    dummy_input = torch.randn(1, 600).to(device)
    torch.onnx.export(
        policy_net,
        dummy_input,
        "models/policy_network.onnx",
        input_names=["state"],
        output_names=["action_probs"]
    )

# Similar for value network...
```

**Self-Play Generator:**
```python
# ai_training/self_play.py
import subprocess
import json
from pathlib import Path

def generate_self_play_games(num_games: int, model_version: int):
    """Generate training data from neural net self-play"""
    for game_num in range(num_games):
        # Run EC4X game with neural net AI
        result = subprocess.run([
            "./bin/moderator",
            "self-play",
            f"--model-version={model_version}",
            f"--game-id={game_num}",
            "--players=4",
            "--export-training-data"
        ], capture_output=True)
        
        if result.returncode != 0:
            print(f"Game {game_num} failed: {result.stderr}")
            continue
        
        print(f"Completed game {game_num}/{num_games}")

def train_next_iteration(iteration: int):
    """Train next iteration on combined data"""
    data_dir = Path("training_data")
    
    # Combine bootstrap + self-play data
    all_data = []
    all_data.extend(load_json_files(data_dir / "bootstrap"))
    
    for i in range(1, iteration):
        all_data.extend(load_json_files(data_dir / f"iteration_{i}"))
    
    # Train on combined dataset
    train_policy_network(all_data, epochs=10)
    train_value_network(all_data, epochs=10)
    
    print(f"Completed training iteration {iteration}")

# Iterative improvement loop
for iteration in range(1, 11):  # 10 iterations
    print(f"\n=== Iteration {iteration} ===")
    
    # Generate self-play games
    print("Generating self-play games...")
    generate_self_play_games(num_games=1000, model_version=iteration-1)
    
    # Train on new data
    print("Training networks...")
    train_next_iteration(iteration)
    
    # Evaluate against baseline
    print("Evaluating...")
    win_rate = evaluate_vs_baseline(iteration)
    print(f"Win rate vs baseline: {win_rate*100:.1f}%")
```

### 4. Model Size & Performance

**Network Sizes:**
- Policy Network: ~550K parameters → ~2.2MB ONNX file
- Value Network: ~350K parameters → ~1.4MB ONNX file
- **Total**: ~3.6MB (vs 4GB for LLM approach!)

**Inference Performance** (CPU):
- Policy network: 5-10ms per evaluation
- Value network: 2-5ms per evaluation
- **Total per turn**: 10-20ms (vs 3-5 seconds for LLM)

**Training Performance** (RX 7900 GRE):
- Supervised learning: 1-2 hours (10K examples, 20 epochs)
- Self-play generation: 100 games/hour (Ryzen 9 7950X3D)
- Single iteration cycle: 4-6 hours

**Scalability:**
- Can run 10+ concurrent games during self-play
- Parallel training on multiple GPUs (if available)
- Inference scales to hundreds of concurrent AI players

## Development Roadmap

### Phase 1: Environment Setup ✅ COMPLETE
- ✅ PyTorch + ROCm installed on AMD GPU
- ✅ ONNX Runtime available in Nim
- ✅ Rule-based AI fully functional (2,800+ lines)
- ✅ 100k game stress test (zero crashes)
- ✅ Engine production-ready

### Phase 2: Rule-Based AI Improvements (CURRENT)
**Goal**: Maximize training data quality from bootstrap AI

See detailed implementation plan in `AI_CONTROLLER_IMPROVEMENTS.md`

**Summary of Improvements:**
1. Fighter/Carrier ownership tracking
2. Capacity violation management
3. Scout operational mode switching
4. ELI mesh network coordination
5. CLK vs ELI tech race assessment
6. Fighter Doctrine / ACO research timing
7. Defense layering (patrol + guard + reserve)

**Deliverable**: Enhanced `ai_controller.nim` producing high-quality training data

### Phase 3: Bootstrap Data Generation
**Goal**: Generate 10,000+ high-quality training examples

**Steps:**
1. Create `tests/balance/export_training_data.nim`
2. Run 10,000 games (4 AI players each)
3. Record state-action-outcome for all players (~1.6M examples)
4. Generate training dataset (train/validation split)

**Deliverable**: `training_data/bootstrap/*.json` (100MB-500MB)

### Phase 4: Supervised Learning
**Goal**: Train neural networks to imitate rule-based AI

**Steps:**
1. Implement state encoding (600-dim vector)
2. Implement action encoding (multi-head output)
3. Create PyTorch dataset loader
4. Train policy network (20 epochs)
5. Train value network (20 epochs)
6. Export to ONNX format
7. Validate ONNX inference in Nim

**Deliverable**: `models/policy_v1.onnx`, `models/value_v1.onnx`

### Phase 5: Nim Integration
**Goal**: Neural network AI playable in EC4X

**Steps:**
1. Create `src/ai/nn_player.nim`
2. Implement ONNX Runtime integration
3. Add neural net AI type to game engine
4. Create evaluation framework (NN vs rule-based)
5. Run 100-game test (measure win rate)

**Deliverable**: Playable neural network AI

### Phase 6: Self-Play Reinforcement Learning
**Goal**: Improve beyond rule-based AI

**Steps:**
1. Create self-play game generator
2. Run 1,000 self-play games (iteration 1)
3. Combine with bootstrap data
4. Retrain networks (iteration 2)
5. Evaluate improvement
6. Repeat 5-10 iterations

**Deliverable**: `models/policy_v10.onnx`, `models/value_v10.onnx`

### Phase 7: Production Deployment
**Goal**: Best AI available for gameplay

**Steps:**
1. Package ONNX models with game distribution
2. Add AI difficulty levels (different model versions)
3. Profile inference performance
4. Optimize if needed
5. Document AI player usage

**Deliverable**: Production-ready neural network AI

## Why This Approach Works for EC4X

**1. Game Complexity Demands Specialized Learning**

EC4X has intricate mechanics that text-based prompting can't handle:
- Fighter ownership (colony vs carrier)
- Capacity violations with 2-turn grace period
- 3-phase combat progression (space → orbital → planetary)
- ELI mesh networks (weighted averages, dominant tech penalty)
- CLK/ELI detection rolls (asymmetric warfare)
- Pre-combat vs post-combat detection states
- Ambush bonus (space only, not orbital)

An LLM would need thousands of tokens to explain these mechanics in each prompt. A neural network learns them directly from gameplay.

**2. Much Smaller Models**
- 3.6MB vs 4GB (1,111x smaller!)
- 10-20ms inference vs 3-5 seconds (150-500x faster!)
- Can run on CPU without GPU

**3. Game-Specific Learning**
- Neural nets learn EC4X-specific strategy
- Training data perfectly aligned with game mechanics
- No need to translate game state to/from text

**4. Proven Technique**
- AlphaZero defeated world champions in Go, Chess, Shogi
- DeepMind's MuZero generalized this to more domains
- Leela Chess Zero successfully uses this for chess AI

**5. Incremental Development**
- Can ship rule-based AI immediately
- Neural network AI is an enhancement, not a requirement
- Each phase delivers value independently

**6. Leverages Existing Assets**
- Your 2,800-line rule-based AI is already sophisticated
- 100k game stress test proves engine stability
- No need to start from scratch

## Next Steps

### Immediate Actions
1. ✅ Review existing ai_controller.nim capabilities
2. ⏳ Begin Phase 2 improvements (fighter ownership tracking)
3. ⏳ Create training data export format
4. ⏳ Implement state/action encoding design

### Short Term
1. Complete Phase 2 AI improvements
2. Generate bootstrap training data (10k games)
3. Create PyTorch training pipeline
4. Train initial networks

### Medium Term
1. Integrate ONNX inference in Nim
2. Evaluate neural net vs rule-based
3. Begin self-play training
4. Iterate for improvements

### Long Term
1. Production deployment
2. Multiple difficulty levels
3. Continuous improvement via self-play
4. Tournament-style AI testing

---

**Status**: Phase 1 complete (environment setup)
**Current**: Phase 2 - Rule-based AI enhancements
**Next**: Phase 3 - Bootstrap data generation
