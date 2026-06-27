#!/bin/sh

# Requires cc cmake ninja-build

set -x
set -e

TARGET="x86_64-linux-musl"
MCPU="baseline"
CACHE_BASENAME="zig+llvm+lld+clang-$TARGET-0.17.0-dev.203+073889523"
PREFIX="$HOME/deps/$CACHE_BASENAME"
ZIG="$PREFIX/bin/zig"

export PATH="$HOME/deps/wasmtime-v46.0.1-x86_64-linux:$HOME/deps/qemu-linux-x86_64-11.0.2/bin:$HOME/local/bin:$PATH"

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

mkdir build-release
cd build-release

export CC="$ZIG cc -target $TARGET -mcpu=$MCPU"
export CXX="$ZIG c++ -target $TARGET -mcpu=$MCPU"

cmake .. \
  -DCMAKE_INSTALL_PREFIX="stage3-release" \
  -DCMAKE_PREFIX_PATH="$PREFIX" \
  -DCMAKE_BUILD_TYPE=Release \
  -DZIG_TARGET_TRIPLE="$TARGET" \
  -DZIG_TARGET_MCPU="$MCPU" \
  -DZIG_STATIC=ON \
  -DZIG_NO_LIB=ON \
  -GNinja

# Now cmake will use zig as the C/C++ compiler. We reset the environment variables
# so that installation and testing do not get affected by them.
unset CC
unset CXX

ninja install

# Covers several things:
# 1. building the compiler without LLVM
# 2. 32-bit
# 3. arm
stage3-release/bin/zig build \
  -Dtarget=arm-linux-musleabihf \
  -Dno-lib

stage3-release/bin/zig build test docs \
  --maxrss ${ZSF_MAX_RSS:-0} \
  -Dlldb=$HOME/deps/lldb-zig/Release-7c1090fd46/bin/lldb \
  -Dlibc-test-path=$HOME/deps/libc-test-b95fe84 \
  -fqemu \
  --libc-runtimes $HOME/deps/glibc-2.43-musl-1.2.5 \
  -fwasmtime \
  -Dstatic-llvm \
  -Dtarget=native-native-musl \
  --search-prefix "$PREFIX" \
  --zig-lib-dir "$PWD/../lib" \
  -Denable-superhtml \
  --test-timeout 12m

# Ensure that the fuzzer at least compiles.
stage3-release/bin/zig build test-std --fuzz=1K -Dno-lib -Dfuzz-only -Doptimize=ReleaseSafe
stage3-release/bin/zig build test-std --fuzz=1K -Dno-lib -Dfuzz-only -Doptimize=Debug

# Ensure that stage3 and stage4 are byte-for-byte identical.
stage3-release/bin/zig build \
  --prefix stage4-release \
  -Denable-llvm \
  -Dno-lib \
  -Doptimize=ReleaseFast \
  -Dstrip \
  -Dtarget=$TARGET \
  -Duse-zig-libcxx \
  -Dversion-string="$(stage3-release/bin/zig version)"

echo "If the following command fails, it means nondeterminism has been"
echo "introduced, making stage3 and stage4 no longer byte-for-byte identical."
diff stage3-release/bin/zig stage4-release/bin/zig

# Ensure that updating the wasm binary from this commit will result in a viable build.
stage3-release/bin/zig build update-zig1

mkdir ../build-new
cd ../build-new

export CC="$ZIG cc -target $TARGET -mcpu=$MCPU"
export CXX="$ZIG c++ -target $TARGET -mcpu=$MCPU"

cmake .. \
  -DCMAKE_PREFIX_PATH="$PREFIX" \
  -DCMAKE_BUILD_TYPE=Release \
  -DZIG_TARGET_TRIPLE="$TARGET" \
  -DZIG_TARGET_MCPU="$MCPU" \
  -DZIG_STATIC=ON \
  -DZIG_NO_LIB=ON \
  -GNinja \
  -DCMAKE_C_LINKER_DEPFILE_SUPPORTED=FALSE \
  -DCMAKE_CXX_LINKER_DEPFILE_SUPPORTED=FALSE
# https://github.com/ziglang/zig/issues/22213

unset CC
unset CXX

ninja install

stage3/bin/zig test ../test/behavior.zig
stage3/bin/zig build -p stage4 \
  -Dstatic-llvm \
  -Dtarget=native-native-musl \
  -Dno-lib \
  --search-prefix "$PREFIX" \
  --zig-lib-dir "$PWD/../lib"
stage4/bin/zig test ../test/behavior.zig
