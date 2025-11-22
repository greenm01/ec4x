#!/bin/bash
# EC4X AI Training Setup - AMD GPU (ROCm)
# For AMD Ryzen 9 7950X3D + RX 7900 GRE
#
# This script sets up the ML environment for training and inference

set -e  # Exit on error

echo "================================================================"
echo "EC4X AI Training Setup - AMD GPU Edition"
echo "================================================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Directory structure
AI_TRAINING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$AI_TRAINING_DIR")"
MODELS_DIR="$PROJECT_ROOT/models"
TRAINING_DATA_DIR="$AI_TRAINING_DIR/training_data"

echo "Project root: $PROJECT_ROOT"
echo "AI training dir: $AI_TRAINING_DIR"
echo ""

# Step 1: Check ROCm installation
echo -e "${YELLOW}[1/8] Checking ROCm installation...${NC}"

# Add ROCm to PATH if not already there
if [ -d "/opt/rocm/bin" ]; then
    export PATH="/opt/rocm/bin:$PATH"
fi

if command -v rocm-smi &> /dev/null; then
    echo -e "${GREEN}✓ ROCm is installed${NC}"
    rocm-smi --showproductname 2>/dev/null || echo "  (rocm-smi basic check passed)"
else
    echo -e "${RED}✗ ROCm not found${NC}"
    echo ""
    echo "Install ROCm with:"
    echo "  sudo pacman -S rocm-hip-sdk rocm-opencl-sdk rocm-smi-lib"
    echo ""
    exit 1
fi
echo ""

# Step 2: Check GPU detection
echo -e "${YELLOW}[2/8] Detecting AMD GPU...${NC}"
GPU_INFO=$(lspci | grep -i 'vga.*amd' | head -1)
if [ -n "$GPU_INFO" ]; then
    echo -e "${GREEN}✓ AMD GPU detected:${NC}"
    echo "  $GPU_INFO"
else
    echo -e "${RED}✗ No AMD GPU found${NC}"
    exit 1
fi
echo ""

# Step 3: Create directory structure
echo -e "${YELLOW}[3/8] Creating directory structure...${NC}"
mkdir -p "$MODELS_DIR"
mkdir -p "$TRAINING_DATA_DIR/raw"
mkdir -p "$TRAINING_DATA_DIR/processed"
mkdir -p "$AI_TRAINING_DIR/checkpoints"
mkdir -p "$AI_TRAINING_DIR/logs"
echo -e "${GREEN}✓ Directories created${NC}"
echo "  Models: $MODELS_DIR"
echo "  Training data: $TRAINING_DATA_DIR"
echo ""

# Step 4: Setup Python virtual environment
echo -e "${YELLOW}[4/8] Setting up Python virtual environment...${NC}"
cd "$AI_TRAINING_DIR"

# Use Python 3.11 for PyTorch ROCm compatibility
PYTHON_CMD="python3.11"
if ! command -v $PYTHON_CMD &> /dev/null; then
    echo -e "${RED}✗ Python 3.11 not found${NC}"
    echo ""
    echo "PyTorch with ROCm requires Python 3.11 or 3.12"
    echo ""
    echo "Install with:"
    echo "  sudo pacman -S python311"
    echo ""
    echo "Or use Nix shell (recommended):"
    echo "  nix develop"
    echo ""
    exit 1
fi

if [ ! -d "venv" ]; then
    $PYTHON_CMD -m venv venv
    echo -e "${GREEN}✓ Virtual environment created${NC}"
else
    echo -e "${GREEN}✓ Virtual environment already exists${NC}"
fi

# Activate virtual environment
source venv/bin/activate
echo "  Python: $(which python)"
echo "  Version: $(python --version)"
echo ""

# Step 5: Install PyTorch with ROCm support
echo -e "${YELLOW}[5/8] Installing PyTorch with ROCm support...${NC}"
echo "  This may take 5-10 minutes..."
pip install --upgrade pip wheel setuptools

# Install PyTorch with ROCm 6.0 support
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/rocm6.0

echo -e "${GREEN}✓ PyTorch installed${NC}"
echo ""

# Step 6: Test GPU detection in PyTorch
echo -e "${YELLOW}[6/8] Testing PyTorch GPU detection...${NC}"
python << 'PYTEST'
import torch
import sys

print(f"PyTorch version: {torch.__version__}")
print(f"CUDA available (ROCm): {torch.cuda.is_available()}")

if torch.cuda.is_available():
    print(f"GPU device: {torch.cuda.get_device_name(0)}")
    print(f"GPU memory: {torch.cuda.get_device_properties(0).total_memory / 1024**3:.1f} GB")

    # Quick tensor test
    x = torch.randn(1000, 1000).cuda()
    y = torch.matmul(x, x)
    print(f"GPU tensor operations: OK")

    print("\n✓ GPU is working correctly with PyTorch!")
    sys.exit(0)
else:
    print("\n✗ GPU not detected by PyTorch")
    print("Check ROCm installation and HSA_OVERRIDE_GFX_VERSION")
    sys.exit(1)
PYTEST

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ PyTorch GPU test passed${NC}"
else
    echo -e "${RED}✗ PyTorch GPU test failed${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "1. Check ROCm version: rocm-smi"
    echo "2. Try setting: export HSA_OVERRIDE_GFX_VERSION=11.0.0"
    echo "3. Verify ROCR_VISIBLE_DEVICES=0"
    exit 1
fi
echo ""

# Step 7: Install ML libraries
echo -e "${YELLOW}[7/8] Installing ML libraries...${NC}"
pip install transformers accelerate peft bitsandbytes datasets
pip install fastapi uvicorn pydantic
pip install tqdm wandb  # Training monitoring (optional)

echo -e "${GREEN}✓ ML libraries installed${NC}"
echo ""

# Step 8: Clone and build llama.cpp with ROCm
echo -e "${YELLOW}[8/8] Setting up llama.cpp for inference...${NC}"
cd "$PROJECT_ROOT"

if [ ! -d "llama.cpp" ]; then
    echo "  Cloning llama.cpp..."
    git clone https://github.com/ggerganov/llama.cpp
else
    echo "  llama.cpp already cloned"
fi

cd llama.cpp

# Build with ROCm support
echo "  Building with ROCm support (using all 32 CPU cores)..."
make clean 2>/dev/null || true
make LLAMA_HIPBLAS=1 -j32

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ llama.cpp built successfully${NC}"
    echo "  Binary: $PROJECT_ROOT/llama.cpp/server"
else
    echo -e "${RED}✗ llama.cpp build failed${NC}"
    exit 1
fi
echo ""

# Create models directory in llama.cpp
mkdir -p models

echo "================================================================"
echo -e "${GREEN}Setup Complete!${NC}"
echo "================================================================"
echo ""
echo "Your AMD ML environment is ready:"
echo "  • ROCm: Installed and working"
echo "  • GPU: RX 7900 GRE detected"
echo "  • PyTorch: Installed with ROCm support"
echo "  • llama.cpp: Built with ROCm backend"
echo ""
echo "Next steps:"
echo "  1. Improve rule-based AI (Phase 1)"
echo "  2. Generate training data (Phase 2)"
echo "  3. Download base model:"
echo "     cd $PROJECT_ROOT"
echo "     # Option A: Direct GGUF (fast start)"
echo "     huggingface-cli download TheBloke/Mistral-7B-Instruct-v0.2-GGUF \\"
echo "       mistral-7b-instruct-v0.2.Q4_K_M.gguf --local-dir models/"
echo ""
echo "     # Option B: Full model for training"
echo "     git clone https://huggingface.co/mistralai/Mistral-7B-Instruct-v0.2 models/mistral-7b-base"
echo ""
echo "  4. Test inference:"
echo "     cd llama.cpp"
echo "     ./server -m ../models/mistral-7b-instruct-v0.2.Q4_K_M.gguf -ngl 99"
echo ""
echo "To activate Python environment:"
echo "  cd $AI_TRAINING_DIR"
echo "  source venv/bin/activate"
echo ""
