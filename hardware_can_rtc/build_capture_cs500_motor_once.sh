#!/bin/sh
# Optional VM rebuild with the Linaro AArch64 compiler selected in CXX.
set -eu
if [ "$#" -ne 2 ]; then
    echo "usage: CXX=/path/to/linaro/aarch64-linux-gnu-g++ sh $0 ARMNN_LIB_DIR NEW_OUTPUT" >&2
    exit 2
fi
armnn=$1
output=$2
srcdir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cxx=${CXX:-aarch64-linux-gnu-g++}
if ! command -v "$cxx" >/dev/null 2>&1; then
    echo "FAIL: C++ cross-compiler not found: $cxx" >&2
    exit 1
fi
if [ -e "$output" ]; then
    echo "FAIL: refusing to overwrite $output" >&2
    exit 1
fi
if [ ! -r "$armnn/include/armnnALUtils/cma_mem_init.hpp" ] ||
   [ ! -r "$armnn/lib/libarmnn.so.32.1" ]; then
    echo "FAIL: Arm NN headers/runtime missing under $armnn" >&2
    exit 1
fi
"$cxx" -std=c++17 -O2 -Wall -Wextra \
    -I"$armnn/include" \
    "$srcdir/capture_cs500_motor_once.cpp" \
    "$armnn/lib/libarmnn.so.32.1" \
    -pthread -ldl -lm \
    -o "$output"
file "$output"
echo "Built only: $output; no board capture has been run"
