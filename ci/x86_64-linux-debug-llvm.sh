#!/bin/sh

# Requires cmake ninja-build

set -x
set -e

TARGET="x86_64-linux-musl"
MCPU="baseline"
CACHE_BASENAME="zig+llvm+lld+clang-$TARGET-0.17.0-dev.203+073889523"
PREFIX="$HOME/deps/$CACHE_BASENAME"
ZIG="$PREFIX/bin/zig"

export PATH="$HOME/deps/wasmtime-v46.0.1-x86_64-linux:$HOME/deps/qemu-linux-x86_64-11.1.1/bin:$HOME/local/bin:$PATH"

# Override the cache directories because they won't actually help other CI runs
# which will be testing alternate versions of zig, and ultimately would just
# fill up space on the hard drive for no reason.
export ZIG_GLOBAL_CACHE_DIR="$PWD/zig-global-cache"
export ZIG_LOCAL_CACHE_DIR="$PWD/zig-local-cache"

mkdir -p build-debug-llvm
cd build-debug-llvm

cmake .. \
  -DCMAKE_INSTALL_PREFIX="stage3-debug" \
  -DCMAKE_PREFIX_PATH="$PREFIX" \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_C_COMPILER="$ZIG;cc;-target;$TARGET;-mcpu=$MCPU" \
  -DCMAKE_CXX_COMPILER="$ZIG;c++;-target;$TARGET;-mcpu=$MCPU" \
  -DZIG_TARGET_TRIPLE="$TARGET" \
  -DZIG_TARGET_MCPU="$MCPU" \
  -DZIG_STATIC=ON \
  -DZIG_NO_LIB=ON \
  -DZIG_EXTRA_BUILD_ARGS="-Duse-llvm=true" \
  -GNinja

ninja install

# Must be done after zig cc is finished.
export ZIG_LIB_DIR="$PWD/../lib"

# Simultaneously test building self-hosted without LLVM and with 32-bit arm
stage3-debug/bin/zig build \
  --maxrss "${ZSF_MAX_RSS:-0}" \
  -Dtarget=arm-linux-musleabihf \
  -Dno-lib

stage3-debug/bin/zig build install test docs \
  --maxrss "${ZSF_MAX_RSS:-0}" \
  --prefix stage4-debug \
  --search-prefix "$PREFIX" \
  --libc-runtimes "$HOME/deps/glibc-2.43-musl-1.2.5" \
  --test-timeout 12m \
  -fqemu \
  -fwasmtime \
  -Dversion-string="$(stage3-debug/bin/zig version)" \
  -Dtarget=$TARGET \
  -Dcpu=$MCPU \
  -Duse-llvm \
  -Duse-zig-libcxx \
  -Denable-llvm \
  -Dno-lib \
  -Dskip-freebsd \
  -Dskip-netbsd \
  -Dskip-openbsd \
  -Dskip-windows \
  -Dskip-darwin \
  -Denable-superhtml \
  -Dlldb="$HOME/deps/lldb-zig/Debug-aad646607a/bin/lldb" \
  -Dlibc-test-path="$HOME/deps/libc-test-b95fe84"

stage4-debug/bin/zig test ../test/behavior.zig
