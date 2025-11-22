# EC4X AI System Architecture

## Overview

The EC4X AI system provides both **rule-based AI for balance testing** and **LLM-powered AI players** for strategic gameplay. The system is designed as a **hybrid Nim + Python architecture** that integrates seamlessly with the existing game engine while maintaining transport-agnostic design.

## Design Principles

1. **Modular**: AI components are independent of core game engine
2. **Transport-Agnostic**: AI players work in both localhost and Nostr modes
3. **Hybrid Language**: Nim for game logic, Python for ML/AI
4. **Training Pipeline**: Generate training data from simulations
5. **Production-Ready**: Fast inference with GPU acceleration

## Architecture Layers

```
┌──────────────────────────────────────────────────────────────┐
│              EC4X Game Engine (Nim)                          │
│  • Core game logic (src/engine/)                             │
│  • Turn resolution                                           │
│  • Order validation                                          │
│  • Combat & economy systems                                  │
└───────────────────────┬──────────────────────────────────────┘
                        │
            ┌───────────┴───────────┐
            ▼                       ▼
┌─────────────────────────┐  ┌────────────────────────────┐
│  Rule-Based AI (Nim)    │  │  LLM AI Player (Hybrid)    │
│  tests/balance/         │  │                            │
│  • Strategic decision   │  │  ┌──────────────────────┐  │
│  • Diplomatic AI        │  │  │ Nim Client Layer     │  │
│  • Military AI          │  │  │ src/ai/llm_player    │  │
│  • Training data gen    │  │  └──────────┬───────────┘  │
│                         │  │             │ HTTP/JSON    │
│  Output:                │  │  ┌──────────▼───────────┐  │
│  • JSON training data   │  │  │ Python LLM Service   │  │
│  • Balance test reports │  │  │ ai_inference/        │  │
└─────────────────────────┘  │  │ • FastAPI server     │  │
                             │  │ • Prompt formatting  │  │
                             │  │ • Response parsing   │  │
                             │  └──────────┬───────────┘  │
                             │             │              │
                             │  ┌──────────▼───────────┐  │
                             │  │ llama.cpp (C++)      │  │
                             │  │ • GPU inference      │  │
                             │  │ • ROCm backend       │  │
                             │  │ • GGUF models        │  │
                             │  └──────────────────────┘  │
                             └────────────────────────────┘
                                          │
                                          ▼
                             ┌────────────────────────────┐
                             │ Training Pipeline (Python) │
                             │ ai_training/               │
                             │ • Load simulation data     │
                             │ • Fine-tune Mistral-7B     │
                             │ • Export to GGUF           │
                             └────────────────────────────┘
```

## Components

### 1. Rule-Based AI (Nim)

**Location**: `tests/balance/ai_controller.nim`

**Purpose**:
- Strategic AI for balance testing
- Generate training data for LLM
- Baseline for LLM comparison

**Capabilities**:
- Strategic diplomacy (pact formation, violation assessment)
- Intelligent military decisions (combat odds, fleet composition)
- Economic optimization (research allocation, production)
- Adaptive behavior based on personality profiles

**Integration**:
```nim
# tests/balance/run_simulation.nim
import ai_controller

proc runBalanceTest() =
  var controller = newAIController(houseId, AIStrategy.Economic)

  for turn in 1..100:
    let orders = controller.generateAIOrders(state, rng)
    state = resolveTurn(state, orders)

    # Export training data
    if exportTrainingData:
      saveTrainingExample(state, orders, outcome)
```

**Output**:
- Training data: `training_data/game_XXXX_turn_YY.json`
- Balance reports: `tests/balance/balance_results/`
- Performance metrics: win rates, tech progression, economic growth

### 2. LLM AI Player

**Location**:
- Nim client: `src/ai/llm_player.nim`
- Python service: `ai_inference/server.py`
- Inference engine: `llama.cpp/`

**Purpose**:
- Provide human-like strategic AI for gameplay
- Enable AI players in localhost and Nostr modes
- Demonstrate advanced strategic reasoning

**Architecture**:

```
┌─────────────────────────────────────────────────────────┐
│  Game Engine (Nim)                                      │
│                                                         │
│  ┌──────────────┐         ┌──────────────┐             │
│  │ Game State   │────────▶│ LLMPlayer    │             │
│  │ (GameState)  │         │ (Nim)        │             │
│  └──────────────┘         └──────┬───────┘             │
│                                   │                     │
└───────────────────────────────────┼─────────────────────┘
                                    │ HTTP POST
                                    │ /get_orders
                                    │
                          ┌─────────▼────────────┐
                          │ LLM Service (Python) │
                          │                      │
                          │ 1. Format prompt     │
                          │ 2. Call llama.cpp    │
                          │ 3. Parse response    │
                          │ 4. Return orders     │
                          └─────────┬────────────┘
                                    │ HTTP
                                    │
                          ┌─────────▼────────────┐
                          │ llama.cpp server     │
                          │                      │
                          │ • Load GGUF model    │
                          │ • GPU inference      │
                          │ • 50-100 tokens/sec  │
                          └──────────────────────┘
```

**API Contract**:

Request (Nim → Python):
```json
{
  "game_id": "game-123",
  "turn": 42,
  "house": "house-atreides",
  "game_state": {
    "treasury": 450,
    "prestige": 125,
    "colonies": [...],
    "fleets": [...],
    "tech_levels": {...},
    "diplomatic_relations": {...},
    "intelligence": {
      "enemy_fleets_spotted": [...],
      "uncolonized_systems": [...]
    }
  }
}
```

Response (Python → Nim):
```json
{
  "reasoning": "Strategic analysis from LLM",
  "orders": {
    "fleet_orders": [...],
    "build_orders": [...],
    "research_allocation": {...},
    "diplomatic_actions": [...]
  }
}
```

**Error Handling**:
```nim
proc generateOrders*(player: LLMPlayer, state: GameState): Option[OrderPacket] =
  try:
    let response = player.callLLMService(state)
    return some(parseOrdersFromJSON(response))
  except HttpRequestError:
    # Fallback to rule-based AI
    echo "LLM service unavailable, using rule-based fallback"
    return ruleBasedFallback.generateOrders(state)
```

### 3. Training Pipeline (Python)

**Location**: `ai_training/`

**Purpose**:
- Fine-tune base models on EC4X gameplay
- Generate specialized game AI models
- Export models for production inference

**Workflow**:

```
1. Data Collection
   └─▶ Run 1000+ simulations with rule-based AI
       └─▶ Export training_data/*.json

2. Data Processing
   └─▶ Convert game states to prompts
       └─▶ Format expert decisions as completions
           └─▶ Create training dataset

3. Model Training
   └─▶ Load Mistral-7B-Instruct-v0.2
       └─▶ Apply LoRA fine-tuning
           └─▶ Train 3 epochs on AMD GPU
               └─▶ Export adapter weights

4. Model Export
   └─▶ Merge LoRA with base model
       └─▶ Convert to GGUF format
           └─▶ Quantize to Q4_K_M
               └─▶ Deploy to llama.cpp

5. Evaluation
   └─▶ Run LLM AI vs rule-based AI
       └─▶ Measure win rates, strategy quality
           └─▶ Iterate if needed
```

**Training Script**:
```python
# ai_training/train_ec4x_model.py
from transformers import AutoModelForCausalLM, Trainer
from peft import LoraConfig, get_peft_model

# Load base model (to AMD GPU via ROCm)
model = AutoModelForCausalLM.from_pretrained(
    "mistralai/Mistral-7B-Instruct-v0.2",
    device_map="auto",  # Auto-detect RX 7900 GRE
    torch_dtype=torch.float16
)

# Configure LoRA (parameter-efficient fine-tuning)
lora_config = LoraConfig(
    r=16,
    lora_alpha=32,
    target_modules=["q_proj", "v_proj"],
    lora_dropout=0.05
)

model = get_peft_model(model, lora_config)

# Train on EC4X gameplay data
trainer = Trainer(
    model=model,
    train_dataset=load_ec4x_dataset("training_data/"),
    args=training_args
)

trainer.train()
```

**Hardware Requirements**:
- GPU: RX 7900 GRE (16GB VRAM) - ✅ Available
- RAM: 32GB+ (for large batches) - ✅ 64GB available
- Storage: 50GB+ (model checkpoints) - ✅ 1.8TB available
- Training time: 6-12 hours for 10k examples

### 4. Inference Service

**Location**: `llama.cpp/` + `ai_inference/server.py`

**Purpose**:
- Fast LLM inference on AMD GPU
- HTTP API for Nim game engine
- Production-ready AI player backend

**Deployment**:

**Option A: llama.cpp Direct (Recommended)**
```bash
# Start llama.cpp server
cd llama.cpp
./server \
    -m models/ec4x-mistral-7b-q4_K_M.gguf \
    --host 127.0.0.1 \
    --port 8080 \
    -c 4096 \
    -ngl 99  # Offload all layers to AMD GPU
```

**Option B: Python Wrapper (Alternative)**
```python
# ai_inference/server.py
from fastapi import FastAPI
from vllm import LLM

app = FastAPI()
llm = LLM(model="models/ec4x-mistral-7b", gpu_memory_utilization=0.9)

@app.post("/get_orders")
async def get_orders(request: GameStateRequest):
    prompt = format_game_state_prompt(request.game_state)
    output = llm.generate(prompt)
    return parse_llm_response(output)
```

**Performance** (RX 7900 GRE):
- Model size: 7B parameters (Q4_K_M)
- VRAM usage: ~5GB
- Inference speed: 50-100 tokens/sec
- Latency per turn: 3-5 seconds
- Concurrent requests: 4-8 (batched)

**Systemd Service** (Production):
```ini
# /etc/systemd/system/ec4x-llm.service
[Unit]
Description=EC4X LLM Inference Service
After=network.target

[Service]
Type=simple
User=niltempus
WorkingDirectory=/home/niltempus/llama.cpp
ExecStart=/home/niltempus/llama.cpp/server \
    -m /home/niltempus/models/ec4x-mistral-7b-q4_K_M.gguf \
    --host 127.0.0.1 --port 8080 -c 4096 -ngl 99
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

## Integration with Game Engine

### AI Player Types

```nim
# src/ai/types.nim
type
  AIPlayerType* {.pure.} = enum
    Human,      # Real human player (default)
    RuleBased,  # Rule-based AI from ai_controller.nim
    LLM         # LLM-powered AI via HTTP service

  AIPlayer* = ref object
    houseId*: HouseId
    playerType*: AIPlayerType
    case playerType
    of AIPlayerType.RuleBased:
      controller*: AIController
    of AIPlayerType.LLM:
      llmPlayer*: LLMPlayer
    of AIPlayerType.Human:
      discard  # No AI needed
```

### Order Generation

```nim
# src/engine/turn_processor.nim
proc collectOrders(state: GameState, aiPlayers: Table[HouseId, AIPlayer]): Table[HouseId, OrderPacket] =
  result = initTable[HouseId, OrderPacket]()

  for houseId in state.houses.keys:
    if houseId in aiPlayers:
      let aiPlayer = aiPlayers[houseId]

      case aiPlayer.playerType
      of AIPlayerType.RuleBased:
        let orders = aiPlayer.controller.generateAIOrders(state, rng)
        result[houseId] = orders

      of AIPlayerType.LLM:
        let ordersOpt = aiPlayer.llmPlayer.generateOrders(state)
        if ordersOpt.isSome:
          result[houseId] = ordersOpt.get()
        else:
          # Fallback to rule-based if LLM fails
          echo "LLM failed for ", houseId, ", using fallback"
          result[houseId] = generateDefaultOrders(state, houseId)

      of AIPlayerType.Human:
        # Wait for human orders via transport
        discard
    else:
      # Human player - orders come from transport layer
      discard
```

### Transport Integration

**Localhost Mode**:
```nim
# AI orders written to same directory structure as human orders
# Daemon treats them identically

proc submitAIOrders(gameDir: string, houseId: HouseId, orders: OrderPacket) =
  let ordersFile = gameDir / "houses" / $houseId / "orders_pending.json"
  writeFile(ordersFile, $(%orders))
  # Daemon will pick these up on next poll cycle
```

**Nostr Mode**:
```nim
# AI player uses Nostr keypair, publishes orders as encrypted events
# Indistinguishable from human players on the network

proc submitAIOrdersNostr(llmPlayer: LLMPlayer, orders: OrderPacket, relayUrl: string) =
  let event = createOrderPacketEvent(
    orders,
    llmPlayer.nostrKeypair,  # AI has its own identity
    moderatorPubkey
  )
  publishToRelay(relayUrl, event)
  # Moderator decrypts and processes like any other player
```

**Key Insight**: AI players are **first-class citizens** in both transport modes. The daemon doesn't distinguish between human and AI orders - both go through the same validation and resolution pipeline.

## Training Data Format

### Game State Snapshot

```json
{
  "game_id": "game_001",
  "turn": 15,
  "house": "house-atreides",
  "game_state": {
    "turn": 15,
    "treasury": 450,
    "prestige": 125,
    "tech_levels": {
      "economic_level": 2,
      "science_level": 2,
      "construction_tech": 2,
      "weapons_tech": 1,
      "terraforming_tech": 1,
      "electronic_intelligence": 1,
      "counter_intelligence": 1
    },
    "colonies": [
      {
        "system_id": "arrakis",
        "infrastructure": 10,
        "production": 85,
        "population": 100,
        "planet_class": "Desert",
        "resources": "Rich",
        "shipyards": 2,
        "starbases": 1,
        "ground_batteries": 3,
        "armies": 2
      },
      {
        "system_id": "caladan",
        "infrastructure": 5,
        "production": 42,
        "population": 60,
        "planet_class": "Terran",
        "resources": "Standard",
        "shipyards": 1
      }
    ],
    "fleets": [
      {
        "fleet_id": "alpha",
        "location": "arrakis",
        "squadrons": [
          {"class": "Cruiser", "count": 2, "combat_strength": 120},
          {"class": "Destroyer", "count": 3, "combat_strength": 60}
        ],
        "total_combat_strength": 180
      }
    ],
    "diplomatic_relations": {
      "house-harkonnen": "Enemy",
      "house-corrino": "Neutral"
    },
    "intelligence": {
      "enemy_fleets_spotted": [
        {
          "fleet_id": "harkonnen-fleet-1",
          "location": "giedi-prime",
          "estimated_strength": 200,
          "last_seen_turn": 14
        }
      ],
      "uncolonized_systems": ["kaitain", "ix"],
      "known_enemy_colonies": [
        {
          "system_id": "giedi-prime",
          "owner": "house-harkonnen",
          "estimated_infrastructure": 8,
          "last_scouted_turn": 12
        }
      ]
    }
  },
  "expert_decision": {
    "reasoning": "Harkonnen fleet threatens newly captured Giedi Prime. Need to consolidate fleets for defense. Economy is strong enough to invest in research for tech advantage. Avoid opening second front with Corrino.",
    "fleet_orders": [
      {
        "fleet_id": "beta",
        "order_type": "Move",
        "target_system": "giedi-prime",
        "reasoning": "Reinforce Alpha Fleet before Harkonnen attack"
      }
    ],
    "build_orders": [
      {
        "colony": "arrakis",
        "build_type": "Ship",
        "ship_class": "Cruiser",
        "quantity": 1,
        "reasoning": "Need heavy ships for Harkonnen war"
      }
    ],
    "research_allocation": {
      "economic": 100,
      "science": 80,
      "technology": {
        "weapons_tech": 70
      },
      "reasoning": "Boost WEP for combat advantage against Harkonnen"
    },
    "diplomatic_actions": []
  },
  "outcome": {
    "turn_score": 85,
    "prestige_change": 5,
    "territories_gained": 0,
    "territories_lost": 0,
    "fleet_losses": 0,
    "combat_victories": 0,
    "tech_advances": 0
  }
}
```

## Data Flow

### Training Data Generation

```
┌──────────────────────────────────────────────────────────┐
│ 1. Run Balance Test Simulations                         │
│    tests/balance/run_simulation --export-training-data  │
│                                                          │
│    For each turn:                                        │
│      • Capture game state before orders                 │
│      • Record AI decision (orders + reasoning)          │
│      • Apply orders, resolve turn                       │
│      • Record outcome (score, prestige, victories)      │
│      • Export as JSON                                    │
└──────────────────┬───────────────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────────────┐
│ 2. Training Data Storage                                 │
│    training_data/                                        │
│    ├── game_00001_turn_01.json                          │
│    ├── game_00001_turn_02.json                          │
│    ├── ...                                               │
│    └── game_01000_turn_100.json                         │
│                                                          │
│    Total: 10,000+ training examples                     │
│    Size: ~100-200 MB (compressed)                       │
└──────────────────┬───────────────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────────────┐
│ 3. Data Processing (Python)                              │
│    ai_training/prepare_dataset.py                       │
│                                                          │
│    • Load JSON files                                     │
│    • Convert to prompt-completion pairs                  │
│    • Apply formatting for Mistral instruct format       │
│    • Split train/validation (90/10)                     │
│    • Save as HuggingFace dataset                        │
└──────────────────┬───────────────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────────────┐
│ 4. Model Training (Python + PyTorch + ROCm)              │
│    ai_training/train_ec4x_model.py                      │
│                                                          │
│    • Load Mistral-7B base model                         │
│    • Apply LoRA adapters                                │
│    • Train 3 epochs on AMD GPU (6-12 hours)            │
│    • Save checkpoints every 500 steps                   │
│    • Evaluate on validation set                         │
└──────────────────┬───────────────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────────────┐
│ 5. Model Export                                          │
│    llama.cpp/convert.py                                 │
│                                                          │
│    • Merge LoRA with base model                         │
│    • Convert PyTorch → GGUF format                      │
│    • Quantize to Q4_K_M (4-bit)                        │
│    • Output: ec4x-mistral-7b-q4_K_M.gguf (~4GB)        │
└──────────────────┬───────────────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────────────┐
│ 6. Production Deployment                                 │
│    llama.cpp/server (systemd service)                   │
│                                                          │
│    • Load GGUF model to GPU                             │
│    • Listen on localhost:8080                           │
│    • Serve inference requests from Nim                  │
└──────────────────────────────────────────────────────────┘
```

### LLM Inference Flow

```
┌──────────────────────────────────────────────────────────┐
│ Game Engine (Nim)                                        │
│                                                          │
│ Turn 42 order collection phase:                         │
│   For each AI player (LLM type):                        │
│     1. Extract game state for house                     │
│     2. Format as JSON request                           │
│     3. HTTP POST to localhost:8080/completion           │
└──────────────────┬───────────────────────────────────────┘
                   │ JSON over HTTP
                   ▼
┌──────────────────────────────────────────────────────────┐
│ LLM Service (llama.cpp server)                          │
│                                                          │
│ 1. Receive game state JSON                              │
│ 2. Format into prompt:                                   │
│    "<s>[INST] You are advisor for House Atreides...     │
│     [game state details]                                 │
│     Provide strategic orders. [/INST]"                   │
│                                                          │
│ 3. Run inference:                                        │
│    • Load GGUF model on AMD GPU                         │
│    • Generate ~500-1000 tokens                          │
│    • Parse JSON from response                           │
│                                                          │
│ 4. Return JSON response with orders                     │
│                                                          │
│ Performance: 3-5 seconds per request                    │
└──────────────────┬───────────────────────────────────────┘
                   │ JSON response
                   ▼
┌──────────────────────────────────────────────────────────┐
│ Game Engine (Nim)                                        │
│                                                          │
│ 5. Parse LLM response:                                   │
│    • Extract fleet_orders, build_orders, etc.           │
│    • Validate against game rules                        │
│    • Convert to OrderPacket                             │
│                                                          │
│ 6. If invalid:                                           │
│    • Log error with LLM response                        │
│    • Retry once with correction prompt                  │
│    • If still invalid, use rule-based fallback          │
│                                                          │
│ 7. Submit orders to turn resolution                     │
└──────────────────────────────────────────────────────────┘
```

## Performance Characteristics

### Training

| Metric | Value |
|--------|-------|
| Training examples needed | 10,000+ |
| Training time (7B model) | 6-12 hours |
| GPU utilization | 90-95% (RX 7900 GRE) |
| VRAM usage | 12-14 GB |
| Checkpoint size | 150 MB (LoRA adapters) |
| Final model size | 4 GB (Q4_K_M GGUF) |

### Inference

| Metric | Value |
|--------|-------|
| Latency per request | 3-5 seconds |
| Tokens per second | 50-100 |
| VRAM usage | 5 GB |
| GPU utilization | 60-80% |
| CPU usage | <10% |
| RAM usage | 2 GB |

### Scalability

| Scenario | Feasibility |
|----------|-------------|
| 1 AI player per game | ✅ Excellent (5 sec/turn) |
| 4 AI players per game | ✅ Good (20 sec/turn, batched) |
| 8 AI players per game | ⚠️ Acceptable (40 sec/turn) |
| Multiple concurrent games | ✅ Good (queue requests) |
| 24/7 production service | ✅ Excellent (systemd, auto-restart) |

## Security Considerations

### Training Data

- ❌ **Do NOT commit to git**: Large files, potentially contains strategy secrets
- ✅ **Store locally**: `/home/niltempus/training_data/`
- ✅ **Backup separately**: External drive or S3
- ✅ **Documented in .gitignore**: All training/model paths excluded

### LLM Service

- ✅ **Localhost only**: Bind to 127.0.0.1, not exposed to network
- ✅ **No authentication needed**: Only game engine can access
- ⚠️ **For production Nostr games**: Add API key if service is remote
- ✅ **Fallback to rule-based**: Never fail game due to AI unavailability

### Model Weights

- ❌ **Do NOT commit to git**: 4GB+ files
- ✅ **Store in models/**: Excluded by .gitignore
- ✅ **Open source models only**: Mistral-7B (Apache 2.0 license)
- ✅ **Redistribute fine-tuned models**: Can share if desired

## Future Enhancements

### Reinforcement Learning

Once supervised learning baseline works:

1. **Self-play training**:
   - LLM plays against itself (3+ houses)
   - Track win rates, prestige scores
   - Reward function based on game outcomes

2. **PPO/DPO fine-tuning**:
   - Optimize for winning, not imitating
   - Learn from failures
   - Discover novel strategies

3. **Iterative improvement**:
   - Train → Evaluate → Retrain
   - Benchmark against previous versions
   - Track ELO ratings

### Nostr AI Player Service

Provide LLM AI as a service over Nostr:

```
┌──────────────────────────────────────────────────────┐
│ Remote AI Player Service (Nostr)                     │
│                                                      │
│ • Runs on game server                               │
│ • Has own Nostr keypair                             │
│ • Subscribes to EventKindStateDelta                  │
│ • Publishes EventKindOrderPacket                     │
│ • Indistinguishable from human players              │
│                                                      │
│ Use case:                                            │
│   - Fill empty slots in multiplayer games           │
│   - Practice opponent for solo players              │
│   - Fallback when human drops out                   │
└──────────────────────────────────────────────────────┘
```

### Multi-Model Ensemble

Train specialized models:

- **Military AI**: Expert at fleet combat, positioning
- **Economic AI**: Optimizes production, research
- **Diplomatic AI**: Masters alliance formation, betrayal timing

Combine via **voting** or **coordinator model**:
```
Game State → [Military AI, Economic AI, Diplomatic AI]
              ↓         ↓           ↓
          Orders   Orders      Orders
              ↓         ↓           ↓
            Ensemble Coordinator (meta-model)
                      ↓
                Final Orders
```

Benefits: Better than single generalist model, each specialist learns faster.

## Related Documentation

- [Architecture Overview](./overview.md) - Overall EC4X system design
- [Data Flow](./dataflow.md) - Turn resolution pipeline
- [Transport Layer](./transport.md) - Localhost and Nostr integration
- [AI Implementation Plan](../AI_IMPLEMENTATION_PLAN.md) - Detailed implementation roadmap
- [AI Balance Testing Status](../AI_BALANCE_TESTING_STATUS.md) - Rule-based AI capabilities

## Development Workflow

### Phase 1: Setup Environment

```bash
# 1. Setup AMD GPU ML stack
cd ec4x/ai_training
./setup_amd_ml.sh

# 2. Verify GPU detection
python -c "import torch; print(torch.cuda.is_available())"

# 3. Build llama.cpp with ROCm
cd ../llama.cpp
make LLAMA_HIPBLAS=1 -j32
```

### Phase 2: Improve Rule-Based AI

```bash
# Implement strategic diplomacy and military AI
# See AI_BALANCE_TESTING_STATUS.md Phase 1-2

# Run balance tests
cd tests/balance
./run_simulation --turns 50 --houses 3 --export-training-data
```

### Phase 3: Train LLM

```bash
# Collect training data (1000+ games)
# Takes ~24 hours on Ryzen 9 7950X3D

# Train model
cd ai_training
source venv/bin/activate
python train_ec4x_model.py

# Convert to GGUF
cd ../llama.cpp
python convert.py --outfile models/ec4x-mistral-7b.gguf ../ai_training/ec4x-mistral-7b
./quantize models/ec4x-mistral-7b.gguf models/ec4x-mistral-7b-q4_K_M.gguf Q4_K_M
```

### Phase 4: Test LLM AI

```bash
# Start inference service
cd llama.cpp
./server -m models/ec4x-mistral-7b-q4_K_M.gguf -ngl 99

# Run test game (in another terminal)
cd tests/balance
./run_simulation --houses llm,rule-based --turns 50
```

### Phase 5: Deploy to Production

```bash
# Setup systemd service
sudo cp ai_training/ec4x-llm.service /etc/systemd/system/
sudo systemctl enable ec4x-llm
sudo systemctl start ec4x-llm

# Verify running
curl http://localhost:8080/health

# Use in games
# AI players automatically use LLM service if available
```
