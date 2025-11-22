#!/usr/bin/env bash
# Setup script for EC4X model training environment

set -e

echo "========================================================================"
echo "EC4X Training Environment Setup"
echo "========================================================================"
echo

# Check for ROCm
echo "Checking for ROCm..."
if command -v rocm-smi &> /dev/null; then
    echo "✓ ROCm detected"
    rocm-smi --showproductname
else
    echo "⚠ ROCm not found. This system may not have AMD GPU support."
    echo "  For AMD GPU acceleration, install ROCm from: https://rocm.docs.amd.com/"
    echo "  Training will proceed with CPU (much slower)."
fi
echo

# Create virtual environment
echo "Creating Python virtual environment..."
if [ ! -d "venv" ]; then
    python3 -m venv venv
    echo "✓ Virtual environment created"
else
    echo "✓ Virtual environment already exists"
fi
echo

# Activate virtual environment
source venv/bin/activate

# Upgrade pip
echo "Upgrading pip..."
pip install --upgrade pip
echo

# Install PyTorch with ROCm support (if ROCm detected)
echo "Installing PyTorch..."
if command -v rocm-smi &> /dev/null; then
    # ROCm 6.0 support
    echo "Installing PyTorch with ROCm 6.0 support..."
    pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/rocm6.0
else
    # CPU-only fallback
    echo "Installing PyTorch (CPU-only)..."
    pip install torch torchvision torchaudio
fi
echo

# Install other requirements
echo "Installing training dependencies..."
pip install -r requirements.txt
echo

# Verify installation
echo "========================================================================"
echo "Verifying Installation"
echo "========================================================================"
python3 << 'EOF'
import sys

print("Python version:", sys.version)
print()

try:
    import torch
    print(f"✓ PyTorch {torch.__version__}")
    print(f"  CUDA available: {torch.cuda.is_available()}")
    if torch.cuda.is_available():
        print(f"  Device count: {torch.cuda.device_count()}")
        print(f"  Device name: {torch.cuda.get_device_name(0)}")
        print(f"  Device memory: {torch.cuda.get_device_properties(0).total_memory / 1e9:.1f} GB")

    if hasattr(torch.version, 'hip'):
        print(f"  ROCm version: {torch.version.hip}")
except ImportError as e:
    print(f"✗ PyTorch import failed: {e}")
    sys.exit(1)

print()

try:
    import transformers
    print(f"✓ Transformers {transformers.__version__}")
except ImportError:
    print("✗ Transformers not installed")
    sys.exit(1)

try:
    import peft
    print(f"✓ PEFT {peft.__version__}")
except ImportError:
    print("✗ PEFT not installed")
    sys.exit(1)

try:
    import datasets
    print(f"✓ Datasets {datasets.__version__}")
except ImportError:
    print("✗ Datasets not installed")
    sys.exit(1)

try:
    import accelerate
    print(f"✓ Accelerate {accelerate.__version__}")
except ImportError:
    print("✗ Accelerate not installed")
    sys.exit(1)

print()
print("✓ All dependencies installed successfully!")
EOF

echo
echo "========================================================================"
echo "Setup Complete!"
echo "========================================================================"
echo
echo "To activate the training environment:"
echo "  source venv/bin/activate"
echo
echo "To verify GPU is working:"
echo "  python3 -c 'import torch; print(torch.cuda.is_available())'"
echo
