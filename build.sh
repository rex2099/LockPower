#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
build_dir="$script_dir/build"

/bin/mkdir -p "$build_dir"
/usr/bin/clang \
    -fobjc-arc \
    -O2 \
    -framework AppKit \
    -framework CoreGraphics \
    "$script_dir/Sources/LockPower/main.m" \
    -o "$build_dir/LockPower"

echo "Built $build_dir/LockPower"
