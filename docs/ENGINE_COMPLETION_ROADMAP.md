# EC4X Engine Completion Roadmap

## Current Status

**Overall Completion: ~95%**

Based on STATUS.md analysis:
- ✅ 13 major systems complete and tested
- ✅ 91+ integration tests passing
- ✅ 13 TOML config files implemented
- ⏳ Minor gaps remain for 100% completion

## What's Needed for 100% Engine Completion

### 1. Remaining TODOs in Core Engine

**Found via grep:** 5 files with TODO/FIXME markers

#### A. orders.nim TODOs
**Status**: Validation enhancements needed

```nim
// TODO: Check pathfinding - can fleet reach target?
// TODO: Check if system already colonized
// TODO: Check fleets are in same location
// TODO: Validate build orders (check resources, production capacity)
// TODO: Validate research allocation (check total points available)
// TODO: Validate diplomatic actions (check diplomatic state)
```

**Priority**: Medium
**Impact**: Better order validation prevents invalid game states
**Estimated Time**: 2-3 days

**Implementation**:
1. Add pathfinding validation (use existing starmap jump routes)
2. Add colony existence checks
3. Add fleet proximity validation
4. Add resource/capacity checks for build orders
5. Add research budget validation
6. Add diplomatic state checks (can't propose pact if isolated)

#### B. resolve.nim TODOs
**Status**: Multiple systems need minor fixes

```nim
// TODO: Track salvage operations per house
// TODO: Check if house has available shipyards
// TODO: Colony combat resolution
// TODO: Fleet vs starbase combat
// TODO: Espionage effect duration tracking
```

**Priority**: High (affects gameplay quality)
**Impact**: More robust turn resolution
**Estimated Time**: 3-4 days

**Implementation**:
1. Add salvage tracking to house state
2. Implement shipyard availability checks
3. Complete colony invasion mechanics
4. Finish starbase combat integration
5. Add effect duration countdown system

#### C. gamestate.nim TODOs
**Status**: Minor enhancements

```nim
// TODO: Add validation for game state consistency
```

**Priority**: Low
**Impact**: Better debugging, prevents corrupted states
**Estimated Time**: 1 day

#### D. squadron.nim TODOs
**Status**: Combat integration

```nim
// TODO: Apply tech modifiers to combat strength
```

**Priority**: Medium
**Impact**: Tech levels properly affect combat
**Estimated Time**: 1 day

#### E. salvage.nim TODOs
**Status**: Minor enhancements

```nim
// TODO: Add validation for salvage operations
```

**Priority**: Low
**Impact**: Better error handling
**Estimated Time**: 0.5 days

### 2. Missing Integration Tests

#### A. Order Validation Tests
**What's Missing**:
- Test invalid orders (non-existent fleets, unreachable systems)
- Test resource insufficiency (can't afford build orders)
- Test diplomatic restrictions (can't attack ally)

**Priority**: High
**Files**: New file `tests/integration/test_order_validation.nim`
**Estimated Time**: 1-2 days

#### B. Colony Combat Tests
**What's Missing**:
- Test ground invasion mechanics
- Test colony capture and ownership transfer
- Test garrison requirements

**Priority**: High (needed before training AI)
**Files**: Expand `tests/integration/test_combat_ground.nim`
**Estimated Time**: 2 days

#### C. Starbase Combat Tests
**What's Missing**:
- Test fleet vs starbase combat
- Test starbase defense bonuses
- Test starbase crippling mechanics

**Priority**: Medium
**Files**: New file `tests/integration/test_starbase_combat.nim`
**Estimated Time**: 1-2 days

#### D. Full Turn Integration Test
**What's Missing**:
- Test complete 100-turn game simulation
- Test all systems interacting together
- Test elimination mechanics
- Test victory condition triggers

**Priority**: Critical (needed before AI training)
**Files**: New file `tests/integration/test_full_game.nim`
**Estimated Time**: 2-3 days

### 3. Pre-Commit Hook Setup

**Status**: Documented as needed, not implemented

**What's Needed**:
```bash
# .git/hooks/pre-commit
#!/bin/bash

# 1. Run tests
nimble test || exit 1

# 2. Build verification
nim c src/engine/resolve.nim || exit 1

# 3. Config sync check
python3 scripts/sync_specs.py --check || exit 1

# 4. Nim format check (optional)
# nimpretty --check src/ || exit 1

echo "Pre-commit checks passed"
```

**Priority**: Medium
**Estimated Time**: 0.5 days

### 4. Documentation Gaps

#### A. AI System Integration
**Status**: ✅ Complete (just created docs/architecture/ai-system.md)

#### B. Full Gameplay Example
**What's Missing**: End-to-end example showing complete turn cycle with all systems

**Priority**: Low (useful for testing)
**Files**: `docs/examples/FULL_TURN_EXAMPLE.md`
**Estimated Time**: 1 day

#### C. Balance Testing Guide
**What's Missing**: How to run balance tests, interpret results

**Priority**: Medium (needed before AI training)
**Files**: `docs/BALANCE_TESTING_GUIDE.md`
**Estimated Time**: 1 day

## Completion Timeline

### Phase A: Critical for AI Training (1-2 weeks)

**Must-Have**:
1. ✅ Colony invasion mechanics (resolve.nim)
2. ✅ Starbase combat (resolve.nim)
3. ✅ Full turn integration test
4. ✅ Order validation enhancements
5. ✅ Tech modifier application (squadron.nim)

**Deliverable**: Engine can simulate complete 100-turn games without crashes

**Estimated**: 7-10 days

### Phase B: Nice-to-Have (1 week)

**Should-Have**:
1. Pre-commit hooks
2. Additional integration tests
3. Better error handling
4. Documentation examples

**Deliverable**: Production-ready engine with excellent test coverage

**Estimated**: 5-7 days

### Phase C: Polish (ongoing)

**Could-Have**:
1. Performance optimizations
2. Additional validation
3. Edge case handling
4. Extended documentation

**Deliverable**: Bulletproof engine

**Estimated**: Ongoing as issues discovered

## Recommendation for AI Training

### Option 1: Start Training Now (Recommended)

**Rationale**:
- 95% complete engine is sufficient for initial training
- AI will play within existing mechanics
- Missing features (colony combat, starbase fights) are rare edge cases
- Can generate 10,000+ training examples with current engine

**Approach**:
1. ✅ Improve rule-based AI (Phase 1-2 from AI_BALANCE_TESTING_STATUS.md)
2. ✅ Generate training data from 1000+ games
3. ⏳ Train initial LLM model (Mistral-7B)
4. ⏳ Complete Phase A fixes in parallel
5. ⏳ Regenerate training data with 100% engine
6. ⏳ Retrain model with complete game mechanics

**Pros**:
- Start training pipeline development immediately
- Validate training approach early
- Iterate on prompt engineering
- Parallel workstreams (engine fixes + AI training)

**Cons**:
- First model won't understand colony invasions
- Need to retrain after engine completion

### Option 2: Complete Engine First (Conservative)

**Rationale**:
- Train on complete game mechanics
- Single training run with full feature set
- More accurate AI from start

**Approach**:
1. Complete Phase A (1-2 weeks)
2. Improve rule-based AI (Phase 1-2)
3. Generate training data
4. Train final model

**Pros**:
- Train once on complete mechanics
- AI understands full game from start
- No wasted training runs

**Cons**:
- 2-3 week delay before any AI training
- Training pipeline untested until then
- Risk of training issues discovered late

**My Recommendation**: **Option 1 - Start training now**

Reasons:
1. Training pipeline is complex - better to test early
2. Engine is 95% complete - sufficient for initial data
3. Retraining is cheap with your GPU (6-12 hours)
4. Can fix engine bugs in parallel
5. Iterative approach = faster learning

---

## Continuous Training Daemon Design

### Architecture

```
┌─────────────────────────────────────────────────────┐
│  EC4X Training Daemon (Python)                      │
│  Runs 24/7 on your desktop                          │
│                                                      │
│  ┌───────────────────────────────────────────────┐  │
│  │ Game Simulation Loop                          │  │
│  │                                                │  │
│  │ While True:                                    │  │
│  │   1. Run Nim simulation (1 game, 100 turns)  │  │
│  │   2. Export training data (JSON)              │  │
│  │   3. Append to training dataset               │  │
│  │   4. Check if retrain needed (N games/week)   │  │
│  │   5. If retrain: Fine-tune model              │  │
│  │   6. Deploy new model to inference service    │  │
│  │   7. Sleep (or start next game)               │  │
│  │                                                │  │
│  │ Resource Management:                           │  │
│  │   - GPU: Training only (not simulations)      │  │
│  │   - CPU: 16 cores for parallel simulations    │  │
│  │   - Storage: Rotate old training data         │  │
│  └───────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

### Implementation

**File**: `ai_training/training_daemon.py`

```python
#!/usr/bin/env python3
"""
EC4X Continuous Training Daemon

Runs 24/7 to:
1. Generate training data from simulations
2. Periodically retrain LLM
3. Deploy improved models
4. Manage storage (rotate old data)
"""

import subprocess
import json
import time
from pathlib import Path
from datetime import datetime, timedelta
import logging

# Configuration
CONFIG = {
    "simulations_per_week": 200,       # Run ~30 games/day
    "retrain_threshold": 1000,         # Retrain after 1000 new games
    "max_storage_gb": 100,             # Use max 100GB for training data
    "training_data_dir": Path("training_data"),
    "models_dir": Path("../models"),
    "simulation_binary": Path("../../tests/balance/run_simulation"),

    # Training config
    "base_model": "mistralai/Mistral-7B-Instruct-v0.2",
    "training_epochs": 3,
    "batch_size": 4,
    "learning_rate": 2e-4,

    # Resource limits
    "max_parallel_sims": 16,           # Use 16 of 32 CPU cores
    "sleep_between_sims": 60,          # 1 minute between games
}

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[
        logging.FileHandler('training_daemon.log'),
        logging.StreamHandler()
    ]
)

class TrainingDaemon:
    def __init__(self):
        self.config = CONFIG
        self.games_since_retrain = 0
        self.total_games = 0
        self.last_retrain = None

        # Create directories
        self.config["training_data_dir"].mkdir(exist_ok=True)
        self.config["models_dir"].mkdir(exist_ok=True)

        # Load state
        self.load_state()

    def load_state(self):
        """Load daemon state from disk"""
        state_file = Path("training_daemon_state.json")
        if state_file.exists():
            with open(state_file) as f:
                state = json.load(f)
                self.games_since_retrain = state.get("games_since_retrain", 0)
                self.total_games = state.get("total_games", 0)
                self.last_retrain = state.get("last_retrain")

    def save_state(self):
        """Save daemon state to disk"""
        state = {
            "games_since_retrain": self.games_since_retrain,
            "total_games": self.total_games,
            "last_retrain": self.last_retrain
        }
        with open("training_daemon_state.json", "w") as f:
            json.dump(state, f, indent=2)

    def run_simulation(self, game_id: int):
        """Run one game simulation"""
        logging.info(f"Starting simulation #{game_id}")

        try:
            result = subprocess.run([
                str(self.config["simulation_binary"]),
                "--turns", "100",
                "--houses", "3",
                "--export-training-data",
                "--output", f"training_data/game_{game_id:06d}.json"
            ], timeout=600, check=True, capture_output=True, text=True)

            logging.info(f"Simulation #{game_id} complete")
            self.games_since_retrain += 1
            self.total_games += 1
            self.save_state()
            return True

        except subprocess.TimeoutExpired:
            logging.error(f"Simulation #{game_id} timed out after 10 minutes")
            return False
        except subprocess.CalledProcessError as e:
            logging.error(f"Simulation #{game_id} failed: {e.stderr}")
            return False

    def check_storage_usage(self):
        """Check training data storage and rotate if needed"""
        training_dir = self.config["training_data_dir"]
        total_size_gb = sum(f.stat().st_size for f in training_dir.glob("*.json")) / (1024**3)

        if total_size_gb > self.config["max_storage_gb"]:
            logging.warning(f"Training data exceeds {self.config['max_storage_gb']}GB, rotating old files")

            # Delete oldest 20% of files
            files = sorted(training_dir.glob("*.json"), key=lambda f: f.stat().st_mtime)
            delete_count = len(files) // 5

            for f in files[:delete_count]:
                f.unlink()
                logging.info(f"Deleted old training file: {f.name}")

            new_size_gb = sum(f.stat().st_size for f in training_dir.glob("*.json")) / (1024**3)
            logging.info(f"Storage reduced from {total_size_gb:.1f}GB to {new_size_gb:.1f}GB")

    def should_retrain(self):
        """Check if we should retrain the model"""
        if self.games_since_retrain >= self.config["retrain_threshold"]:
            return True

        # Also retrain weekly if we have new data
        if self.last_retrain:
            last_train_time = datetime.fromisoformat(self.last_retrain)
            if datetime.now() - last_train_time > timedelta(days=7):
                if self.games_since_retrain > 100:  # At least 100 new games
                    return True

        return False

    def train_model(self):
        """Fine-tune model on accumulated training data"""
        logging.info("Starting model training...")

        try:
            # Run training script
            result = subprocess.run([
                "python", "train_ec4x_model.py",
                "--training-data", str(self.config["training_data_dir"]),
                "--output-dir", f"ec4x-mistral-7b-v{self.total_games}",
                "--epochs", str(self.config["training_epochs"]),
                "--batch-size", str(self.config["batch_size"]),
                "--learning-rate", str(self.config["learning_rate"])
            ], check=True, capture_output=True, text=True)

            logging.info("Model training complete")
            logging.info(result.stdout)

            # Export to GGUF
            self.export_model(self.total_games)

            # Deploy new model
            self.deploy_model(self.total_games)

            # Reset counter
            self.games_since_retrain = 0
            self.last_retrain = datetime.now().isoformat()
            self.save_state()

            return True

        except subprocess.CalledProcessError as e:
            logging.error(f"Model training failed: {e.stderr}")
            return False

    def export_model(self, version: int):
        """Export trained model to GGUF format"""
        logging.info(f"Exporting model v{version} to GGUF...")

        subprocess.run([
            "python", "../llama.cpp/convert.py",
            "--outfile", f"../models/ec4x-mistral-7b-v{version}.gguf",
            "--outtype", "f16",
            f"ec4x-mistral-7b-v{version}"
        ], check=True)

        # Quantize
        subprocess.run([
            "../llama.cpp/quantize",
            f"../models/ec4x-mistral-7b-v{version}.gguf",
            f"../models/ec4x-mistral-7b-v{version}-q4_K_M.gguf",
            "Q4_K_M"
        ], check=True)

        logging.info(f"Model v{version} exported and quantized")

    def deploy_model(self, version: int):
        """Deploy new model to inference service"""
        logging.info(f"Deploying model v{version}...")

        # Symlink to latest
        latest_link = self.config["models_dir"] / "ec4x-mistral-7b-latest-q4_K_M.gguf"
        new_model = self.config["models_dir"] / f"ec4x-mistral-7b-v{version}-q4_K_M.gguf"

        if latest_link.exists():
            latest_link.unlink()

        latest_link.symlink_to(new_model.name)

        # Restart inference service (if running)
        try:
            subprocess.run(["systemctl", "--user", "restart", "ec4x-llm"], check=False)
            logging.info("Inference service restarted with new model")
        except:
            logging.warning("Could not restart inference service (may not be running)")

    def run_forever(self):
        """Main daemon loop"""
        logging.info("EC4X Training Daemon started")
        logging.info(f"Total games so far: {self.total_games}")
        logging.info(f"Games since last retrain: {self.games_since_retrain}")

        game_id = self.total_games + 1

        while True:
            try:
                # Run simulation
                if self.run_simulation(game_id):
                    game_id += 1

                # Check storage
                self.check_storage_usage()

                # Check if we should retrain
                if self.should_retrain():
                    logging.info(f"Retrain threshold reached ({self.games_since_retrain} games)")
                    self.train_model()

                # Sleep between simulations
                time.sleep(self.config["sleep_between_sims"])

            except KeyboardInterrupt:
                logging.info("Daemon stopped by user")
                break
            except Exception as e:
                logging.error(f"Unexpected error: {e}", exc_info=True)
                time.sleep(60)  # Sleep 1 minute before retry

if __name__ == "__main__":
    daemon = TrainingDaemon()
    daemon.run_forever()
```

### Storage Requirements (2TB Drive)

**Training Data**:
- Per game: ~500 KB JSON (100 turns × 5 KB/turn)
- 10,000 games: ~5 GB
- 100,000 games: ~50 GB
- **Configured max: 100 GB** (rotate oldest when exceeded)

**Model Checkpoints**:
- Base model: 14 GB (Mistral-7B FP16)
- LoRA adapters: 150 MB per checkpoint
- Final GGUF (Q4_K_M): 4 GB per version
- Keep last 5 versions: 20 GB

**Logs and State**:
- Training logs: ~100 MB
- Daemon logs: ~10 MB
- State files: < 1 MB

**Total Expected Usage**: 100-150 GB

**Your 2TB Drive**: More than sufficient! ✅

You'll use <8% of available storage even at maximum.

### Systemd Service (Auto-Start on Boot)

```ini
# ~/.config/systemd/user/ec4x-training-daemon.service
[Unit]
Description=EC4X Continuous Training Daemon
After=network.target

[Service]
Type=simple
WorkingDirectory=/home/niltempus/dev/ec4x/ai_training
ExecStart=/home/niltempus/dev/ec4x/ai_training/venv/bin/python training_daemon.py
Restart=always
RestartSec=60

# Resource limits
CPUQuota=1600%  # Use 16 of 32 cores (50%)
MemoryMax=32G

[Install]
WantedBy=default.target
```

**Enable**:
```bash
systemctl --user enable ec4x-training-daemon
systemctl --user start ec4x-training-daemon

# View logs
journalctl --user -u ec4x-training-daemon -f
```

### Benefits of Continuous Training

1. **Always improving**: Model gets better as more games are played
2. **Discover strategies**: AI learns from successful games
3. **Balance testing**: Automatically collects balance data
4. **Zero intervention**: Runs in background while you work
5. **Resource efficient**: Uses idle GPU time
6. **Version tracking**: Each retrain is versioned (v1, v2, v3...)

### Monitoring Dashboard (Optional)

**Simple web UI to track progress**:

```python
# ai_training/dashboard.py
from fastapi import FastAPI
from fastapi.responses import HTMLResponse
import json

app = FastAPI()

@app.get("/", response_class=HTMLResponse)
def dashboard():
    # Load state
    with open("training_daemon_state.json") as f:
        state = json.load(f)

    return f"""
    <html><head><title>EC4X Training Dashboard</title></head>
    <body>
        <h1>EC4X Training Daemon Status</h1>
        <p>Total Games: {state['total_games']}</p>
        <p>Games Since Last Retrain: {state['games_since_retrain']}</p>
        <p>Last Retrain: {state.get('last_retrain', 'Never')}</p>

        <h2>Latest Model</h2>
        <p>Version: v{state['total_games']}</p>

        <h2>Storage Usage</h2>
        <p>Training Data: Check training_data/ directory</p>
    </body></html>
    """

# Run with: uvicorn dashboard:app --port 8081
```

Access at `http://localhost:8081` to monitor progress.

---

## Recommendation

**Path to 100% + AI Training**:

1. **Week 1**: Complete Phase A critical fixes (colony combat, validation)
2. **Week 1-2**: Improve rule-based AI (diplomacy + military)
3. **Week 2**: Start continuous training daemon
4. **Week 2-3**: Daemon runs 24/7, accumulates 500+ games
5. **Week 3**: First model training (6-12 hours)
6. **Week 3+**: Daemon continues, retrains weekly

**Parallel workstreams**:
- Engine fixes (Phase A): 1-2 weeks human time
- AI training: Runs unattended on GPU
- No wasted time - both happen simultaneously

**Result**:
- 100% engine completion
- Continuously improving AI
- Thousands of balance test games
- Production-ready system

Ready to proceed with the setup script and start Phase A fixes?
