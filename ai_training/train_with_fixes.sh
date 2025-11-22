#!/usr/bin/env bash
#
# Training script with ROCm compatibility fixes
# Based on solutions from:
# - https://gist.github.com/AlkindiX/9c54d1155ba72415f3b585e26c9df6b3
# - https://github.com/ROCm/ROCm/issues/2974
# - https://apatero.com/blog/train-lora-sdxl-amd-gpu-guide-2025

set -e

echo "======================================================================="
echo "EC4X Training with ROCm Compatibility Fixes"
echo "======================================================================="
echo ""

# Fix 1: HSA_OVERRIDE_GFX_VERSION for RDNA3 (RX 7900 series)
export HSA_OVERRIDE_GFX_VERSION=11.0.0
echo "✓ Set HSA_OVERRIDE_GFX_VERSION=11.0.0 (RDNA3/gfx1100)"

# Fix 2: HIP debugging and memory management
export HIP_LAUNCH_BLOCKING=1
echo "✓ Set HIP_LAUNCH_BLOCKING=1 (synchronous execution for debugging)"

export PYTORCH_HIP_ALLOC_CONF=garbage_collection_threshold:0.6,max_split_size_mb:6144
echo "✓ Set PYTORCH_HIP_ALLOC_CONF (memory management)"

# Fix 3: Nix library path
export LD_LIBRARY_PATH="/nix/store/dj06r96j515npcqi9d8af1d1c60bx2vn-gcc-14.3.0-lib/lib:$LD_LIBRARY_PATH"
echo "✓ Set LD_LIBRARY_PATH for Nix"

# Fix 4: Use only the discrete GPU (avoid integrated GPU issues)
export HIP_VISIBLE_DEVICES=0
echo "✓ Set HIP_VISIBLE_DEVICES=0 (use only discrete GPU)"

# Fix 5: ROCm home
if [ -d "/opt/rocm" ]; then
    export ROCM_HOME=/opt/rocm
    echo "✓ Set ROCM_HOME=/opt/rocm"
fi

echo ""
echo "Environment configured. Starting training..."
echo ""

# Activate virtual environment
source venv/bin/activate

# Use the recommended additional memory setting
export PYTORCH_HIP_ALLOC_CONF=expandable_segments:True,garbage_collection_threshold:0.6,max_split_size_mb:6144
echo "✓ Set expandable_segments for memory management"

# Run training with the memory-optimized script
python3 train_lowmem.py 2>&1 | tee training_fixed.log

echo ""
echo "Training complete! Check training_fixed.log for details."
