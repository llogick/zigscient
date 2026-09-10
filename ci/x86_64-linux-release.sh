#!/bin/sh

# Requires cc cmake ninja-build

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

# Test building from source without LLVM.
cc -o bootstrap bootstrap.c
./bootstrap
./zig2 build -Dno-lib
./zig-out/bin/zig test test/behavior.zig

mkdir -p build-release
cd build-release

cmake .. \
  -DCMAKE_INSTALL_PREFIX="stage3-release" \
  -DCMAKE_PREFIX_PATH="$PREFIX" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER="$ZIG;cc;-target;$TARGET;-mcpu=$MCPU" \
  -DCMAKE_CXX_COMPILER="$ZIG;c++;-target;$TARGET;-mcpu=$MCPU" \
  -DZIG_TARGET_TRIPLE="$TARGET" \
  -DZIG_TARGET_MCPU="$MCPU" \
  -DZIG_STATIC=ON \
  -DZIG_NO_LIB=ON \
  -GNinja

ninja install

# Must not be set while using the other `zig cc` which has its own zig lib dir.
export ZIG_LIB_DIR="$PWD/../lib"

# Simultaneously test building self-hosted without LLVM and with 32-bit arm
stage3-release/bin/zig build \
  -Dtarget=arm-linux-musleabihf \
  -Dno-lib

stage3-release/bin/zig build install test docs \
  --maxrss "${ZSF_MAX_RSS:-0}" \
  --prefix stage4-release \
  --search-prefix "$PREFIX" \
  --libc-runtimes "$HOME/deps/glibc-2.43-musl-1.2.5" \
  --test-timeout 12m \
  -fqemu \
  -fwasmtime \
  -Dversion-string="$(stage3-release/bin/zig version)" \
  -Dtarget=$TARGET \
  -Dcpu=$MCPU \
  -Doptimize=ReleaseFast \
  -Dstrip \
  -Duse-zig-libcxx \
  -Denable-llvm \
  -Dno-lib \
  -Denable-superhtml \
  -Dlldb="$HOME/deps/lldb-zig/Release-aad646607a/bin/lldb" \
  -Dlibc-test-path="$HOME/deps/libc-test-b95fe84"

# Ensure that the fuzzer at least compiles.
stage3-release/bin/zig build test-std --fuzz=1K -Dno-lib -Dfuzz-only -Doptimize=ReleaseSafe
stage3-release/bin/zig build test-std --fuzz=1K -Dno-lib -Dfuzz-only -Doptimize=Debug

# Ensure that stage3 and stage4 are byte-for-byte identical.
echo "If the following command fails, it means nondeterminism has been"
echo "introduced, making stage3 and stage4 no longer byte-for-byte identical."
diff stage3-release/bin/zig stage4-release/bin/zig

# Ensure that updating the wasm binary from this commit will result in a viable build.
stage3-release/bin/zig build update-zig1

mkdir -p ../build-new
cd ../build-new

unset ZIG_LIB_DIR

cmake .. \
  -DCMAKE_PREFIX_PATH="$PREFIX" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER="$ZIG;cc;-target;$TARGET;-mcpu=$MCPU" \
  -DCMAKE_CXX_COMPILER="$ZIG;c++;-target;$TARGET;-mcpu=$MCPU" \
  -DZIG_TARGET_TRIPLE="$TARGET" \
  -DZIG_TARGET_MCPU="$MCPU" \
  -DZIG_STATIC=ON \
  -DZIG_NO_LIB=ON \
  -GNinja

ninja install

export ZIG_LIB_DIR="$PWD/../lib"

stage3/bin/zig test ../test/behavior.zig
stage3/bin/zig build \
  --maxrss "${ZSF_MAX_RSS:-0}" \
  --prefix stage4 \
  --search-prefix "$PREFIX" \
  -Dtarget=$TARGET \
  -Dcpu=$MCPU \
  -Dstatic-llvm \
  -Dno-lib
stage4/bin/zig test ../test/behavior.zig
