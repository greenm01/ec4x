#!/bin/bash
# Wrapper script to run training data generation from correct directory
# Args: game_id

GAME_ID=$1
EC4X_ROOT="/home/niltempus/dev/ec4x"
OUTPUT_PATH="ai_training/training_data/game_$(printf "%05d" $GAME_ID)"

echo "DEBUG: wrapper called with game_id=$GAME_ID" >&2
echo "DEBUG: EC4X_ROOT=$EC4X_ROOT" >&2
echo "DEBUG: OUTPUT_PATH=$OUTPUT_PATH" >&2
echo "DEBUG: pwd=$(pwd)" >&2

cd "$EC4X_ROOT" && \
  ./tests/balance/generate_training_data \
    --games=1 \
    --batch=1 \
    --output="$OUTPUT_PATH"
