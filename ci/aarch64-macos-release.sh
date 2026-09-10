#!/bin/sh

# Requires cmake ninja

set -x
set -e

TARGET="aarch64-macos-none"
MCPU="baseline"
CACHE_BASENAME="zig+llvm+lld+clang-$TARGET-0.17.0-dev.203+073889523"
PREFIX="$HOME/$CACHE_BASENAME"
ZIG="$PREFIX/bin/zig"

ZIGDIR="$PWD"
if [ ! -d "$PREFIX" ]; then
  cd $HOME
  curl -L -O "https://ziglang.org/deps/$CACHE_BASENAME.tar.xz"
  tar xf "$CACHE_BASENAME.tar.xz"
fi
cd $ZIGDIR

export PATH="$HOME/local/bin:$PATH"

# Override the cache directories because they won't actually help other CI runs
# which will be testing alternate versions of zig, and ultimately would just
# fill up space on the hard drive for no reason.
export ZIG_GLOBAL_CACHE_DIR="$PWD/zig-global-cache"
export ZIG_LOCAL_CACHE_DIR="$PWD/zig-local-cache"

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

# Must be done after zig cc is finished.
export ZIG_LIB_DIR="$PWD/../lib"

stage3-release/bin/zig build install test docs \
  --maxrss "${ZSF_MAX_RSS:-0}" \
  --prefix stage4-release \
  --search-prefix "$PREFIX" \
  --test-timeout 2m \
  -Dversion-string="$(stage3-release/bin/zig version)" \
  -Dtarget=$TARGET \
  -Dcpu=$MCPU \
  -Doptimize=ReleaseFast \
  -Dstrip \
  -Duse-zig-libcxx \
  -Denable-llvm \
  -Dno-lib \
  -Denable-macos-sdk \
  -Dskip-spirv \
  -Dskip-wasm \
  -Dskip-freebsd \
  -Dskip-netbsd \
  -Dskip-openbsd \
  -Dskip-windows \
  -Dskip-linux

# Ensure that the fuzzer at least compiles.
stage3-release/bin/zig build test-std --fuzz=1K -Dno-lib -Dfuzz-only -Doptimize=ReleaseSafe
stage3-release/bin/zig build test-std --fuzz=1K -Dno-lib -Dfuzz-only -Doptimize=Debug

# Ensure that stage3 and stage4 are byte-for-byte identical.
echo "If the following command fails, it means nondeterminism has been"
echo "introduced, making stage3 and stage4 no longer byte-for-byte identical."
diff stage3-release/bin/zig stage4-release/bin/zig
