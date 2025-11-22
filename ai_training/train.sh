#!/usr/bin/env bash
# Wrapper script for training with proper LD_LIBRARY_PATH

export LD_LIBRARY_PATH="/nix/store/dj06r96j515npcqi9d8af1d1c60bx2vn-gcc-14.3.0-lib/lib:$LD_LIBRARY_PATH"
source venv/bin/activate
python3 train_model.py
