# EC4X AI Training Pipeline

This directory contains the complete pipeline for training an LLM-based AI player for EC4X using fine-tuned Mistral-7B.

## Overview

The training pipeline consists of four main steps:

1. **Data Generation** - Run game simulations to collect expert decisions
2. **Data Preparation** - Convert raw data to LLM training format
3. **Model Training** - Fine-tune Mistral-7B with LoRA
4. **Model Export** - Convert to GGUF format for fast inference

## Quick Start

### Prerequisites

**Hardware Requirements:**
- AMD GPU with ROCm support (RX 7900 GRE or similar)
  - Or NVIDIA GPU with CUDA support
  - Or CPU (very slow, not recommended)
- 16GB+ VRAM (for 7B model with 8-bit quantization)
- 32GB+ RAM
- 50GB+ disk space

**Software Requirements:**
- Python 3.11+
- ROCm 6.0+ (for AMD GPUs) or CUDA 12.0+ (for NVIDIA)
- Nim compiler (for data generation)

### Step 1: Setup Training Environment

```bash
cd ai_training

# Install dependencies and verify GPU
./setup_training_env.sh

# Activate virtual environment
source venv/bin/activate
```

This will:
- Create Python virtual environment
- Install PyTorch with ROCm/CUDA support
- Install transformers, PEFT, datasets, etc.
- Verify GPU detection

### Step 2: Generate Training Data

```bash
# Generate 50 games (10,000 examples) using parallel simulation
python3 generate_parallel.py

# This will create: training_data/training_dataset_combined.json
```

**Configuration:**
- Modify `TOTAL_GAMES` in `generate_parallel.py` for more/less data
- Modify `PARALLEL_JOBS` to use more/less CPU cores
- Default: 50 games, 25 parallel workers (80% of 32 cores)

**Expected output:**
```
Total games: 50
Successful: 50 (100.0%)
Training examples: 10000
File size: 10.7 MB
Speed: 540 games/second
```

### Step 3: Prepare Training Data

```bash
# Convert to prompt-completion format
python3 prepare_training_data.py

# This will create: training_data/training_dataset_processed.json
```

**What it does:**
- Converts game states to Mistral instruction format
- Creates prompt-completion pairs
- Adds metadata and statistics
- Splits into train/validation sets

### Step 4: Train Model

```bash
# Fine-tune Mistral-7B with LoRA
python3 train_model.py

# Training will take 6-12 hours on RX 7900 GRE
# Checkpoints saved to: models/ec4x-mistral-7b/
```

**Training Configuration:**
- Base model: Mistral-7B-Instruct-v0.2
- Method: LoRA (Low-Rank Adaptation)
- Epochs: 3
- Batch size: 2 (per device) × 8 (accumulation) = 16 effective
- Learning rate: 2e-4
- Quantization: 8-bit (reduces VRAM to ~10GB)

**Monitor training:**
```bash
# Watch GPU utilization
watch -n 1 rocm-smi  # AMD
# or
watch -n 1 nvidia-smi  # NVIDIA

# Check training logs
tail -f models/ec4x-mistral-7b/trainer_state.json
```

### Step 5: Export to GGUF (Optional)

For fastest inference using llama.cpp:

```bash
# Clone llama.cpp (if not already done)
cd ..
git clone https://github.com/ggerganov/llama.cpp
cd llama.cpp

# Build with ROCm support
make clean
make LLAMA_HIPBLAS=1 -j32

# Convert PyTorch model to GGUF
python3 convert.py \
    --outfile ../ai_training/models/ec4x-mistral-7b.gguf \
    --outtype f16 \
    ../ai_training/models/ec4x-mistral-7b/final

# Quantize for faster inference (optional)
./quantize \
    ../ai_training/models/ec4x-mistral-7b.gguf \
    ../ai_training/models/ec4x-mistral-7b-q4_K_M.gguf \
    Q4_K_M
```

## File Structure

```
ai_training/
├── README.md                       # This file
├── TRAINING_README.md              # Training guide
├── requirements.txt                # Python dependencies
├── setup_training_env.sh           # Environment setup script
│
├── generate_parallel.py            # Data generation orchestrator
├── run_game.sh                     # Wrapper for game simulation
├── test_multiproc.py               # Test parallel execution
│
├── prepare_training_data.py        # Data preprocessing
├── train_model.py                  # Model training script
├── export_to_gguf.py               # GGUF export script (TODO)
├── test_model.py                   # Model testing script (TODO)
│
├── training_data/                  # Generated datasets
│   ├── game_00001/                 # Individual game data
│   ├── ...
│   ├── training_dataset_combined.json
│   └── training_dataset_processed.json
│
├── models/                         # Trained models
│   └── ec4x-mistral-7b/
│       ├── final/                  # Final trained model
│       ├── checkpoint-100/         # Training checkpoints
│       ├── checkpoint-200/
│       └── training_metrics.json
│
└── venv/                           # Python virtual environment
```

## Training Data Format

### Input (Raw Training Data)

```json
{
  "game_id": "game_00001",
  "turn": 15,
  "house": "house-atreides",
  "strategy": "Aggressive",
  "game_state": {
    "turn": 15,
    "treasury": 450,
    "prestige": 125,
    "colonies": [...],
    "fleets": [...],
    "tech_levels": {"energy": 3, "shields": 2, ...},
    "diplomatic_relations": {...},
    "intelligence": {...}
  },
  "expert_decision": {
    "reasoning": "Strategic analysis...",
    "fleet_orders": [...],
    "build_orders": [...],
    "research_allocation": {...},
    "diplomatic_actions": [...]
  }
}
```

### Output (Processed for Training)

```
<s>[INST] You are a strategic advisor for house-atreides in EC4X.

## Current Situation (Turn 15)
Treasury: 450 PP
Prestige: 125
Tech Levels: EL3, SL2, WL2, ML1

## Your Colonies
  - arrakis: 5 infrastructure, 25 PP/turn, 10 PTU
  - caladan: 3 infrastructure, 15 PP/turn, 6 PTU

## Your Fleets
  - fleet-001 @ arrakis: 3 Fighter, 1 Frigate

## Diplomatic Relations
  - house-harkonnen: Neutral
  - house-corrino: Non-Aggression Pact

## Intelligence Reports
  Enemy Forces Detected:
    - house-harkonnen fleet @ giedi-prime (strength: Medium)

Provide your strategic analysis and orders in JSON format. [/INST]

{
  "reasoning": "Strategic analysis...",
  "fleet_orders": [...],
  "build_orders": [...],
  "research_allocation": {...},
  "diplomatic_actions": [...]
}</s>
```

## Troubleshooting

### GPU Not Detected

**AMD GPU:**
```bash
# Check ROCm installation
rocm-smi

# Verify PyTorch sees the GPU
python3 -c "import torch; print(torch.cuda.is_available())"

# Check ROCm version
python3 -c "import torch; print(torch.version.hip)"
```

**NVIDIA GPU:**
```bash
# Check CUDA installation
nvidia-smi

# Verify PyTorch sees the GPU
python3 -c "import torch; print(torch.cuda.is_available())"
```

### Out of Memory Errors

Reduce memory usage:

1. **Reduce batch size** in `train_model.py`:
   ```python
   per_device_train_batch_size: int = 1  # Instead of 2
   ```

2. **Enable 4-bit quantization** in `train_model.py`:
   ```python
   load_in_4bit: bool = True  # Instead of load_in_8bit
   ```

3. **Reduce sequence length** in `train_model.py`:
   ```python
   max_seq_length: int = 1024  # Instead of 2048
   ```

### Training Too Slow

Speed up training:

1. **Increase batch size** (if you have VRAM):
   ```python
   per_device_train_batch_size: int = 4
   gradient_accumulation_steps: int = 4
   ```

2. **Reduce validation frequency**:
   ```python
   save_steps: int = 200  # Instead of 100
   eval_steps: int = 200
   ```

3. **Use faster tokenizer**:
   - Already using fast tokenizers by default

### Model Quality Issues

Improve model quality:

1. **Generate more training data**:
   ```python
   TOTAL_GAMES = 100  # Instead of 50
   ```

2. **Train for more epochs**:
   ```python
   num_train_epochs: int = 5  # Instead of 3
   ```

3. **Adjust LoRA rank**:
   ```python
   lora_r: int = 32  # Higher rank = more capacity (but more VRAM)
   ```

## Performance Benchmarks

**RX 7900 GRE (16GB VRAM):**
- Data generation: 540 games/second (50 games in 0.1s)
- Training: ~6-8 hours for 3 epochs on 10,000 examples
- Inference: 50-100 tokens/second (with llama.cpp + ROCm)

**Memory Usage:**
- Data generation: ~4GB RAM
- Training: ~10GB VRAM (8-bit quantization), ~20GB RAM
- Inference: ~4-6GB VRAM (Q4_K_M quantization)

## Next Steps

After training is complete:

1. **Phase 4: Inference Service** - Set up llama.cpp server
2. **Phase 5: Nim Integration** - Connect game engine to LLM API
3. **Phase 6: Testing** - Benchmark AI vs rule-based opponents
4. **Phase 7: Production** - Deploy as systemd service

See `../docs/AI_IMPLEMENTATION_PLAN.md` for the full roadmap.

## Resources

- [Mistral AI Documentation](https://docs.mistral.ai/)
- [Hugging Face Transformers](https://huggingface.co/docs/transformers)
- [PEFT (LoRA) Documentation](https://huggingface.co/docs/peft)
- [llama.cpp GitHub](https://github.com/ggerganov/llama.cpp)
- [ROCm Documentation](https://rocm.docs.amd.com/)
