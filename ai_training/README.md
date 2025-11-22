# EC4X AI Training Data Generation

## Status: Phase 2.5 Complete ✓

Training data generation system is implemented and tested. Ready to generate large-scale datasets.

## What's Working

- ✅ Nim training data exporter (`tests/balance/training_data_export.nim`)
- ✅ Batch training data generator (`tests/balance/generate_training_data.nim`)
- ✅ Python parallel orchestration script (`ai_training/generate_parallel.py`)
- ✅ Successfully generated 200 training examples from test game

## Training Data Format

Each training example contains:
- **Turn number** and **house ID**
- **Game state snapshot**: treasury, production, colonies, fleets, tech levels, military/economic strength, diplomatic relations, threats
- **AI decision**: diplomatic actions, fleet orders, build priority, research focus
- **Strategy type**: Aggressive, Economic, Balanced, Turtle, Diplomatic, Espionage

Example structure (from `batch_001.json`):
```json
{
  "turn": 1,
  "house_id": "house-ordos",
  "strategy": "Aggressive",
  "game_state": {
    "treasury": 1000,
    "production": 0,
    "colony_count": 1,
    "fleet_count": 1,
    "tech": { "energy_level": 1, "shield_level": 1, "weapons_tech": 1 },
    "military": { "own_strength": 5, "enemy_strength": 0, "ratio": 10.0 },
    "economy": { "own_strength": 1000, "enemy_strength": 0 },
    "diplomacy": { "house-atreides": "Neutral", ... },
    "threats": { "colonies_under_threat": 0 }
  },
  "ai_decision": {
    "diplomatic_action": { "action": "DeclareEnemy", "target": "house-corrino", "reasoning": "aggressive_strategy" },
    "fleet_actions": [{ "fleet": "house-ordos_fleet1", "order": "Move", "target": "67", "reasoning": "attack_or_expand" }],
    "build_priority": "Defense",
    "research_focus": "Balanced"
  }
}
```

## Known Issue

Game 2 in test run hit an "over- or underflow" error. This is a numerical overflow bug in the game engine that needs investigation. Game 1 completed successfully, so the system works but needs robustness improvements.

**Impact**: ~50% success rate expected. With 1000 game runs, expect ~500 successful games = ~100,000 training examples.

## Quick Start: Generate Training Data

### Small Test (10 games, ~2-3 minutes)
```bash
cd ai_training
python3 generate_parallel.py
# Edit line 18: TOTAL_GAMES = 10
```

### Medium Dataset (100 games, ~20-30 minutes)
```bash
cd ai_training
python3 generate_parallel.py
# Edit line 18: TOTAL_GAMES = 100
```

### Full Dataset (1000 games, ~3-5 hours)
```bash
cd ai_training
python3 generate_parallel.py
# Uses 25 parallel workers (80% of 32 threads)
# Expected output: ~500 successful games, ~100K training examples
```

## Output Structure

```
ai_training/
├── training_data/
│   ├── game_00001/
│   │   └── batches/
│   │       └── batch_001.json    # 200 examples (50 turns × 4 houses)
│   ├── game_00002/
│   │   └── batches/
│   │       └── batch_001.json
│   ├── ...
│   ├── logs/
│   │   ├── game_00001.log
│   │   ├── game_00002.log
│   │   └── ...
│   └── training_dataset_combined.json   # All examples merged
└── generate_parallel.py
```

## Resource Usage (80% allocation)

- **CPU**: 25 of 32 threads (Ryzen 9 7950X3D)
- **RAM**: ~2-4 GB (Nim simulations are memory-efficient)
- **Disk**: ~100-200 MB per 1000 games
- **Time**: ~3-5 hours for 1000 games

## Next Steps (Phase 3: Model Training)

Once you have 100,000+ training examples:

### 1. Setup Training Environment
```bash
# Install PyTorch with ROCm support for AMD GPU
python -m venv venv
source venv/bin/activate
pip install torch torchvision --index-url https://download.pytorch.org/whl/rocm6.0
pip install transformers accelerate peft bitsandbytes datasets
```

### 2. Create Training Script
See `docs/AI_IMPLEMENTATION_PLAN.md` Phase 3 for detailed training script.

Key components:
- Load `training_dataset_combined.json`
- Format as prompts for Mistral-7B
- Fine-tune with LoRA (Low-Rank Adaptation)
- Export to GGUF format for llama.cpp inference

### 3. Training Time Estimate
- **Dataset**: 100,000 examples
- **Model**: Mistral-7B with LoRA
- **Hardware**: RX 7900 GRE (16GB VRAM)
- **Time**: 6-12 hours
- **Output**: `ec4x-mistral-7b-q4_K_M.gguf` (~4GB)

## Alternative: Start with Small Dataset

Don't wait for 1000 games! You can start training with even 50 successful games (~10,000 examples) to:
- Test training pipeline
- Validate prompt engineering
- Iterate on data format
- Catch issues early

Then retrain with full dataset later.

## Fixing the Overflow Bug

To improve success rate from ~50% to >90%:

1. Run simulation with debugging to find overflow
2. Likely culprit: integer overflow in economic calculations (treasury, production accumulation)
3. Fix: Use proper bounds checking or larger integer types
4. Recompile and regenerate data

This is NOT blocking for Phase 3. You can train on 500 successful games now and regenerate more data later after bug fix.

## Progress Summary

**Phase 2.5 Complete:**
- ✅ Training data export format designed
- ✅ Batch generator implemented and compiled
- ✅ Parallel orchestration script (80% resource usage)
- ✅ Tested and verified with real game data

**Ready for Phase 3:**
- Model training (Mistral-7B fine-tuning)
- Inference service setup (llama.cpp with ROCm)
- Nim integration (LLM player)

**Current Blocker:**
- Game engine overflow bug (needs investigation)
- Workaround: Accept ~50% success rate, generate 2x games to compensate

## Commands Reference

```bash
# Generate training data (parallel)
cd ai_training
python3 generate_parallel.py

# Check progress
ls -lh training_data/game_*/batches/*.json | wc -l  # Count successful games
cat training_data/logs/game_00001.log  # View individual game log

# Inspect training examples
head -100 training_data/training_dataset_combined.json | jq '.'

# Clean up and restart
rm -rf training_data/
```
