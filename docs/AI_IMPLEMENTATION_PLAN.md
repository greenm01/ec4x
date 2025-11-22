# EC4X AI Implementation Plan - Practical Approach

## Architecture: Nim + Python Hybrid

```
┌─────────────────────────────────────────────────────┐
│  EC4X Game Engine (Nim)                             │
│  ├── Game rules, turn resolution                    │
│  ├── Rule-based AI (for training data)              │
│  └── HTTP client to Python LLM service              │
└──────────────────┬──────────────────────────────────┘
                   │ JSON over HTTP
                   ▼
┌─────────────────────────────────────────────────────┐
│  LLM Inference Service (Python + llama.cpp)         │
│  ├── FastAPI REST server                            │
│  ├── Game state → Prompt formatting                 │
│  ├── llama.cpp backend (ROCm GPU)                   │
│  └── LLM response → OrderPacket parser              │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│  Training Pipeline (Python + PyTorch)               │
│  ├── Load simulation data (JSON)                    │
│  ├── Fine-tune base model (Mistral-7B)              │
│  ├── Export to GGUF (quantized)                     │
│  └── Deploy to inference service                    │
└─────────────────────────────────────────────────────┘
```

## Hardware: AMD Ryzen 9 7950X3D + RX 7900 GRE

- **CPU**: 32 threads (parallel game simulations)
- **GPU**: 16GB VRAM (can run 13B models)
- **RAM**: 64GB (large training batches)
- **Storage**: 1.8TB (store millions of training examples)

## Implementation Phases

### Phase 0: Environment Setup (1-2 hours)

**Goal**: Get AMD GPU working with PyTorch

**Tasks**:
1. Install ROCm drivers and SDK
2. Install PyTorch with ROCm support
3. Verify GPU detection and performance
4. Install llama.cpp with ROCm backend
5. Test inference with base model

**Deliverable**: GPU running PyTorch and llama.cpp successfully

---

### Phase 1: Rule-Based AI Enhancement (1-2 weeks)

**Goal**: Create "expert" AI for training data generation

**Priority**: Implement strategic diplomacy and military AI (from AI_BALANCE_TESTING_STATUS.md)

**Tasks**:
1. **Diplomatic AI** (ai_controller.nim):
   - Add `assessDiplomaticSituation` function
   - Calculate relative military/economic strength
   - Identify mutual enemies
   - Evaluate violation risk
   - Strategic pact formation/breaking

2. **Military AI** (ai_controller.nim):
   - Add `assessCombatSituation` function
   - Calculate combat odds with tech modifiers
   - Evaluate defensive strength (starbases, shields, armies)
   - Smart attack/retreat decisions
   - Fleet composition optimization

3. **Testing**:
   - Run 50-turn simulations with enhanced AI
   - Verify strategic behavior (pact formation, tactical combat)
   - Ensure games complete without crashes

**Deliverable**: Rule-based AI that makes intelligent strategic decisions

**Output**: Training data with strategic play patterns

---

### Phase 2: Training Data Generation (1 week)

**Goal**: Generate 10,000+ high-quality training examples

**Format**:
```json
{
  "game_id": "game_001",
  "turn": 15,
  "house": "house-atreides",
  "game_state": {
    "turn": 15,
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
  },
  "expert_decision": {
    "reasoning": "Harkonnen fleet threatens Giedi Prime. Consolidate forces for defense.",
    "fleet_orders": [...],
    "build_orders": [...],
    "research_allocation": {...},
    "diplomatic_actions": [...]
  },
  "outcome": {
    "turn_score": 85,
    "prestige_change": 5,
    "territories_gained": 0,
    "territories_lost": 0,
    "fleet_losses": 0
  }
}
```

**Tasks**:
1. **Data Generator** (Python script):
   ```python
   # ai_training/generate_training_data.py
   import subprocess
   import json
   from pathlib import Path

   def run_simulation(game_id: int, strategy: str):
       """Run Nim simulation with enhanced AI"""
       result = subprocess.run([
           "./tests/balance/run_simulation",
           "--turns", "100",
           "--output", f"training_data/raw/game_{game_id:05d}.json",
           "--strategy", strategy,
           "--export-training-data"  # New flag
       ])
       return result.returncode == 0

   def convert_to_training_format(raw_data_dir: Path):
       """Convert simulation logs to LLM training format"""
       # Parse turn reports
       # Extract game_state + expert_decision pairs
       # Add outcome information
       # Save as individual examples
   ```

2. **Simulation Modifications** (Nim):
   - Add `--export-training-data` flag
   - Save game state snapshots each turn
   - Record AI decisions with reasoning
   - Track outcomes (prestige change, territory, losses)

3. **Data Collection Campaign**:
   - Run 200+ games with different strategies
   - Vary starting conditions (map size, house count)
   - Collect ~50 turns/game = 10,000 training examples
   - Takes ~24 hours on 7950X3D (parallel simulations)

**Deliverable**: `training_data/` directory with 10,000+ JSON examples

---

### Phase 3: Model Training (1-2 weeks)

**Goal**: Fine-tune Mistral-7B on EC4X gameplay

**Base Model**: `mistralai/Mistral-7B-Instruct-v0.2`
- 7 billion parameters
- Strong reasoning abilities
- Good instruction following
- Apache 2.0 license (can use commercially)

**Training Approach**: LoRA (Low-Rank Adaptation)
- Only train 0.1% of parameters (memory efficient)
- Much faster than full fine-tuning
- 16GB VRAM sufficient for 7B model

**Tasks**:
1. **Setup Training Environment**:
   ```bash
   cd ai_training
   python -m venv venv
   source venv/bin/activate
   pip install torch torchvision --index-url https://download.pytorch.org/whl/rocm6.0
   pip install transformers accelerate peft bitsandbytes datasets
   ```

2. **Create Training Script** (`ai_training/train_ec4x_model.py`):
   ```python
   from transformers import (
       AutoModelForCausalLM,
       AutoTokenizer,
       TrainingArguments,
       Trainer
   )
   from peft import LoraConfig, get_peft_model, TaskType
   import torch

   # Load base model to AMD GPU
   model = AutoModelForCausalLM.from_pretrained(
       "mistralai/Mistral-7B-Instruct-v0.2",
       device_map="auto",
       torch_dtype=torch.float16,
       load_in_8bit=True  # Quantization for memory efficiency
   )

   # Configure LoRA
   lora_config = LoraConfig(
       task_type=TaskType.CAUSAL_LM,
       r=16,  # Rank
       lora_alpha=32,
       lora_dropout=0.05,
       target_modules=["q_proj", "k_proj", "v_proj", "o_proj"]
   )

   model = get_peft_model(model, lora_config)

   # Training arguments
   training_args = TrainingArguments(
       output_dir="./ec4x-mistral-7b",
       num_train_epochs=3,
       per_device_train_batch_size=4,
       gradient_accumulation_steps=4,
       learning_rate=2e-4,
       fp16=True,
       save_steps=500,
       logging_steps=10,
       warmup_steps=100,
       save_total_limit=3
   )

   # Train
   trainer = Trainer(
       model=model,
       args=training_args,
       train_dataset=dataset,
       tokenizer=tokenizer
   )

   trainer.train()
   ```

3. **Prompt Engineering**:
   ```python
   def format_training_example(data: dict) -> str:
       """Convert training data to prompt format"""
       return f"""<s>[INST] You are a strategic advisor for {data['house']} in EC4X.

## Current Situation (Turn {data['turn']})
Treasury: {data['game_state']['treasury']} PP
Prestige: {data['game_state']['prestige']}
Tech Levels: {format_tech(data['game_state']['tech_levels'])}

## Your Colonies
{format_colonies(data['game_state']['colonies'])}

## Your Fleets
{format_fleets(data['game_state']['fleets'])}

## Diplomatic Relations
{format_diplomacy(data['game_state']['diplomatic_relations'])}

## Intelligence Reports
{format_intel(data['game_state']['intelligence'])}

Provide your strategic analysis and orders. [/INST]

## Strategic Analysis
{data['expert_decision']['reasoning']}

## Orders
{format_orders_as_json(data['expert_decision'])}
</s>"""
   ```

4. **Training Run**:
   - Estimated time: 6-12 hours on RX 7900 GRE
   - Monitor GPU utilization with `rocm-smi`
   - Watch loss curve for convergence
   - Save checkpoints every 500 steps

5. **Export to GGUF** (for llama.cpp):
   ```bash
   # Clone llama.cpp (if not already)
   git clone https://github.com/ggerganov/llama.cpp
   cd llama.cpp

   # Convert PyTorch model to GGUF
   python convert.py \
       --outfile models/ec4x-mistral-7b-f16.gguf \
       --outtype f16 \
       /path/to/ec4x-mistral-7b

   # Quantize for faster inference
   ./quantize models/ec4x-mistral-7b-f16.gguf \
                models/ec4x-mistral-7b-q4_K_M.gguf Q4_K_M
   ```

**Deliverable**:
- `ec4x-mistral-7b-q4_K_M.gguf` (~4GB file)
- Training metrics and loss curves
- Validation results

---

### Phase 4: Inference Service (1 week)

**Goal**: Fast LLM inference server that Nim can call

**Option A: llama.cpp Server (RECOMMENDED)**

**Setup**:
```bash
cd llama.cpp

# Build with ROCm support
make clean
make LLAMA_HIPBLAS=1 -j32  # Use all 32 threads

# Start server
./server \
    -m models/ec4x-mistral-7b-q4_K_M.gguf \
    --host 127.0.0.1 \
    --port 8080 \
    -c 4096 \
    -ngl 99 \
    --n-gpu-layers 99  # Offload all layers to AMD GPU
```

**API Usage**:
```bash
curl http://localhost:8080/completion \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "You are playing EC4X...",
    "temperature": 0.7,
    "top_p": 0.9,
    "max_tokens": 1024,
    "stop": ["</orders>", "[/INST]"]
  }'
```

**Performance**: 50-100 tokens/sec on RX 7900 GRE

**Option B: Python + vllm (Alternative)**

```python
# ai_inference/server.py
from fastapi import FastAPI
from vllm import LLM, SamplingParams
from pydantic import BaseModel

app = FastAPI()

# Load model (auto-detects ROCm)
llm = LLM(
    model="models/ec4x-mistral-7b",
    tensor_parallel_size=1,
    gpu_memory_utilization=0.9
)

class GameStateRequest(BaseModel):
    turn: int
    house: str
    game_state: dict

@app.post("/get_orders")
async def get_orders(request: GameStateRequest):
    prompt = format_game_state_prompt(request.game_state)

    sampling_params = SamplingParams(
        temperature=0.7,
        max_tokens=1024,
        stop=["</orders>"]
    )

    outputs = llm.generate([prompt], sampling_params)
    orders = parse_llm_response(outputs[0].outputs[0].text)

    return {"orders": orders}
```

**Trade-off**: vllm is 10-20% slower than llama.cpp but easier to debug.

**Deliverable**: Running inference server on localhost:8080

---

### Phase 5: Nim Integration (3-4 days)

**Goal**: Nim game engine calls LLM service for AI decisions

**Architecture**:
```nim
# src/ai/llm_player.nim
import std/[httpclient, json, options, strformat]
import ../engine/[gamestate, orders]

type
  LLMPlayer* = ref object
    houseId*: HouseId
    baseUrl*: string
    client*: HttpClient
    temperature*: float
    maxTokens*: int

proc newLLMPlayer*(houseId: HouseId,
                   baseUrl: string = "http://localhost:8080"): LLMPlayer =
  result = LLMPlayer(
    houseId: houseId,
    baseUrl: baseUrl,
    client: newHttpClient(),
    temperature: 0.7,
    maxTokens: 1024
  )

proc formatGameStatePrompt(state: GameState, houseId: HouseId): string =
  ## Convert game state to LLM prompt
  let house = state.houses[houseId]
  let colonies = getOwnedColonies(state, houseId)
  let fleets = getOwnedFleets(state, houseId)

  result = fmt"""<s>[INST] You are a strategic advisor for {house.name} in EC4X.

## Current Situation (Turn {state.turn})
Treasury: {house.treasury} PP
Prestige: {house.prestige}
Tech Levels: EL{house.techTree.levels.energyLevel}, SL{house.techTree.levels.shieldLevel}

## Your Colonies ({colonies.len})
"""

  for colony in colonies:
    result.add fmt"""
- {colony.systemId}: {colony.infrastructure} infrastructure, {colony.production} production
"""

  result.add fmt"""

## Your Fleets ({fleets.len})
"""

  for fleet in fleets:
    result.add fmt"""
- Fleet @ {fleet.location}: {fleet.squadrons.len} squadrons
"""

  result.add """

## Diplomatic Relations
"""

  for otherHouse in state.houses.keys:
    if otherHouse != houseId:
      let status = house.diplomaticRelations.getDiplomaticState(otherHouse)
      result.add fmt"- {otherHouse}: {status}\n"

  result.add """

Provide your strategic orders in JSON format:
{
  "reasoning": "Your strategic analysis",
  "fleet_orders": [...],
  "build_orders": [...],
  "research_allocation": {...},
  "diplomatic_actions": [...]
}
[/INST]
"""

proc parseOrdersFromJSON(jsonStr: string, houseId: HouseId,
                        turn: int): Option[OrderPacket] =
  ## Parse LLM JSON response into OrderPacket
  try:
    let json = parseJson(jsonStr)
    var packet = newOrderPacket(houseId, turn)

    # Parse fleet orders
    if json.hasKey("fleet_orders"):
      for orderJson in json["fleet_orders"]:
        # Convert JSON to FleetOrder
        # Add validation
        packet.fleetOrders.add(parseFleetOrder(orderJson))

    # Parse build orders
    if json.hasKey("build_orders"):
      for orderJson in json["build_orders"]:
        packet.buildOrders.add(parseBuildOrder(orderJson))

    # Parse research allocation
    if json.hasKey("research_allocation"):
      packet.researchAllocation = parseResearchAllocation(
        json["research_allocation"]
      )

    # Parse diplomatic actions
    if json.hasKey("diplomatic_actions"):
      for actionJson in json["diplomatic_actions"]:
        packet.diplomaticActions.add(parseDiplomaticAction(actionJson))

    return some(packet)

  except JsonParsingError, KeyError:
    echo "Failed to parse LLM response"
    return none(OrderPacket)

proc generateOrders*(player: LLMPlayer,
                    state: GameState): Option[OrderPacket] =
  ## Call LLM service to generate orders
  let prompt = formatGameStatePrompt(state, player.houseId)

  # Call llama.cpp API
  let request = %*{
    "prompt": prompt,
    "temperature": player.temperature,
    "max_tokens": player.maxTokens,
    "stop": ["</s>", "[/INST]"]
  }

  try:
    let response = player.client.postContent(
      player.baseUrl & "/completion",
      body = $request,
      headers = newHttpHeaders({"Content-Type": "application/json"})
    )

    let jsonResponse = parseJson(response)
    let completion = jsonResponse["content"].getStr()

    # Extract JSON from response (LLM might wrap it in markdown)
    let jsonStart = completion.find("{")
    let jsonEnd = completion.rfind("}") + 1

    if jsonStart >= 0 and jsonEnd > jsonStart:
      let ordersJson = completion[jsonStart..<jsonEnd]
      return parseOrdersFromJSON(ordersJson, player.houseId, state.turn)

    return none(OrderPacket)

  except HttpRequestError, IOError:
    echo "Failed to call LLM service"
    return none(OrderPacket)
```

**Integration into Simulation**:
```nim
# tests/balance/run_simulation.nim

import ../../src/ai/llm_player

# Add LLM player option
type PlayerType = enum
  RuleBased, LLM

proc runGame(playerTypes: Table[HouseId, PlayerType]) =
  var llmPlayers: Table[HouseId, LLMPlayer]

  # Initialize LLM players
  for houseId, ptype in playerTypes:
    if ptype == PlayerType.LLM:
      llmPlayers[houseId] = newLLMPlayer(houseId)

  # Game loop
  for turn in 1..maxTurns:
    for houseId in state.houses.keys:
      let orders = if playerTypes[houseId] == PlayerType.LLM:
        llmPlayers[houseId].generateOrders(state)
      else:
        ruleBasedAI.generateOrders(state)

      if orders.isSome:
        applyOrders(state, orders.get())
```

**Deliverable**: Nim code that calls LLM service and parses responses

---

### Phase 6: Testing & Iteration (1 week)

**Goal**: Verify LLM AI plays competently

**Test Suite**:
1. **Legality Test**: LLM generates only legal moves
2. **Sanity Test**: LLM doesn't make obviously bad moves
3. **Competence Test**: LLM wins ≥30% vs rule-based AI
4. **Strategy Test**: LLM adapts to different situations

**Benchmark Games**:
```bash
# 1v1: LLM vs Rule-based
./run_simulation --house1=llm --house2=rule-based --turns=50

# 3-way: LLM vs 2 Rule-based
./run_simulation --houses=llm,rule-based,rule-based --turns=50

# Mirror match: LLM vs LLM (with different seeds)
./run_simulation --house1=llm --house2=llm --turns=50
```

**Metrics to Track**:
- Win rate (survival to turn 100)
- Average prestige at turn 50
- Tech progression speed
- Economic growth rate
- Combat casualties ratio
- Diplomatic stability

**Common Issues & Fixes**:

| Issue | Cause | Fix |
|-------|-------|-----|
| Illegal moves | LLM hallucinates unit IDs | Add validation, retry with correction |
| JSON parse errors | LLM outputs markdown | Better prompt, extract JSON via regex |
| Slow inference | GPU not used | Check `rocm-smi`, verify `-ngl 99` |
| Repetitive moves | Low temperature | Increase to 0.7-0.9 |
| Overly cautious | Training data bias | Add aggressive games to training set |

**Deliverable**: Report showing LLM AI performance vs baselines

---

### Phase 7: Production Deployment (3-4 days)

**Goal**: Reliable AI service for game server

**Tasks**:
1. **Systemd Service** (auto-start on boot):
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
       --host 127.0.0.1 \
       --port 8080 \
       -c 4096 \
       -ngl 99
   Restart=always
   RestartSec=10

   [Install]
   WantedBy=multi-user.target
   ```

2. **Monitoring**:
   - Log inference times
   - Track GPU utilization
   - Monitor memory usage
   - Alert on errors

3. **Fallback Strategy**:
   ```nim
   proc generateOrdersWithFallback(llmPlayer: LLMPlayer,
                                  ruleBasedAI: AIController,
                                  state: GameState): OrderPacket =
     ## Try LLM first, fall back to rule-based if it fails
     let llmOrders = llmPlayer.generateOrders(state)

     if llmOrders.isSome:
       return llmOrders.get()
     else:
       echo "LLM failed, using rule-based AI fallback"
       return ruleBasedAI.generateOrders(state)
   ```

4. **Caching** (optional optimization):
   - Cache similar game states
   - Avoid redundant LLM calls
   - Save ~50% inference costs for repetitive positions

**Deliverable**: Production-ready AI service

---

## Timeline Summary

| Phase | Duration | Dependencies |
|-------|----------|--------------|
| 0. Setup | 1-2 hours | None |
| 1. Rule-based AI | 1-2 weeks | Phase 0 |
| 2. Training Data | 1 week | Phase 1 |
| 3. Model Training | 1-2 weeks | Phase 2 |
| 4. Inference Service | 1 week | Phase 3 |
| 5. Nim Integration | 3-4 days | Phase 4 |
| 6. Testing | 1 week | Phase 5 |
| 7. Production | 3-4 days | Phase 6 |

**Total**: 6-8 weeks for complete LLM AI system

## Future Enhancements

### Phase 8: Reinforcement Learning (Optional)
- Self-play with reward shaping
- PPO or DPO training
- Achieve superhuman play

### Phase 9: Nostr Integration
- Publish game state as Nostr events
- AI responds via Nostr protocol
- Enable remote AI players

### Phase 10: Multi-Model Ensemble
- Train specialized models (military, economic, diplomatic)
- Ensemble voting for final decisions
- Better than single generalist model

---

## Cost Analysis

### One-Time Costs
- **Hardware**: Already owned (RX 7900 GRE)
- **Development Time**: 6-8 weeks
- **Electricity** (~$0.10/kWh):
  - Training: 12 hours × 300W = 3.6 kWh = $0.36
  - Data generation: 24 hours × 150W = 3.6 kWh = $0.36
  - **Total**: ~$1

### Ongoing Costs
- **Inference**: ~100W GPU, $0.01/hour
- **1000 games/month**: ~500 hours = $5/month
- **vs Claude API**: Would cost $3000/month 😱

**ROI**: Infinite - saves $3000/month

---

## Next Step

Let's start with **Phase 0: Environment Setup**. I'll create a setup script to:
1. Verify ROCm installation
2. Install PyTorch with ROCm
3. Test GPU detection
4. Build llama.cpp with ROCm
5. Run quick inference test

Ready to proceed?
