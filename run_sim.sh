#!/bin/bash
# IMP Simulation Runner - Compile and run Verilator simulation
#     Copyright (C) 2026 Randy Smits-Schreuder Goedheijt
#
# Usage: ./run_sim.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/sim_build"

echo "=== IMP Verilator Simulation ==="

# Clean and create build dir
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Copy sources
cp "$SCRIPT_DIR/generated/neuralcore.sv" "$BUILD_DIR/"
cp "$SCRIPT_DIR/generated/neuralcore_tb.sv" "$BUILD_DIR/"

cd "$BUILD_DIR"

echo "[1/4] Compiling with --timing support..."
verilator --cc --timing --trace \
    neuralcore.sv neuralcore_tb.sv \
    -o neuralcore_sim \
    --Mdir obj_dir \
    --main \
    --main-top-name neuralcore_tb \
    -Wno-TIMESCALEMOD \
    2>&1 | grep -v "^%Warning" || true

echo "[2/4] Building..."
make -C obj_dir -f Vneuralcore.mk VM_PARALLEL=0 2>&1 | grep -E "^(g\+\+|ar|ln)" || make -C obj_dir -f Vneuralcore.mk 2>&1 | tail -5

echo "[3/4] Linking executable..."
# Find the object files and link manually
cd "$BUILD_DIR"
g++ -o neuralcore_sim \
    obj_dir/*.o \
    -lm \
    2>&1

echo "[4/4] Running simulation..."
./neuralcore_sim

echo ""
echo "=== Simulation complete ==="
echo "Waveform saved to: $BUILD_DIR/waveform.vcd"
