$TARGET = "aarch64-windows-gnu"
$MCPU = "baseline"
$PREFIX_PATH = "$($Env:USERPROFILE)\deps\zig+llvm+lld+clang-$TARGET-0.17.0-dev.203+073889523"
$ZIG = "$PREFIX_PATH\bin\zig.exe"
$ZSF_MAX_RSS = if ($Env:ZSF_MAX_RSS) { $Env:ZSF_MAX_RSS } else { 0 }

$Env:PATH = "$($Env:USERPROFILE)\local\bin;$Env:PATH"

function CheckLastExitCode {
    if (!$?) {
        exit 1
    }
    return 0
}

# Override the cache directories because they won't actually help other CI runs
# which will be testing alternate versions of zig, and ultimately would just
# fill up space on the hard drive for no reason.
$Env:ZIG_GLOBAL_CACHE_DIR="$(Get-Location)\zig-global-cache"
$Env:ZIG_LOCAL_CACHE_DIR="$(Get-Location)\zig-local-cache"

Write-Output "Building from source..."
New-Item -Force -Path 'build-release' -ItemType Directory
Set-Location -Path 'build-release'

# CMake gives a syntax error when file paths with backward slashes are used.
# Here, we use forward slashes only to work around this.
cmake .. `
  -GNinja `
  -DCMAKE_INSTALL_PREFIX="stage3-release" `
  -DCMAKE_PREFIX_PATH="$($PREFIX_PATH -Replace "\\", "/")" `
  -DCMAKE_BUILD_TYPE=Release `
  -DCMAKE_C_COMPILER="$($ZIG -Replace "\\", "/");cc;-target;$TARGET;-mcpu=$MCPU" `
  -DCMAKE_CXX_COMPILER="$($ZIG -Replace "\\", "/");c++;-target;$TARGET;-mcpu=$MCPU" `
  -DCMAKE_AR="$($ZIG -Replace "\\", "/")" `
  -DZIG_AR_WORKAROUND=ON `
  -DZIG_TARGET_TRIPLE="$TARGET" `
  -DZIG_TARGET_MCPU="$MCPU" `
  -DZIG_STATIC=ON `
  -DZIG_NO_LIB=ON
CheckLastExitCode

ninja install
CheckLastExitCode

# Must be done after zig cc is finished.
$Env:ZIG_LIB_DIR="$(Get-Location)\..\lib"

Write-Output "Main test suite..."
stage3-release\bin\zig.exe build test docs `
  --maxrss $ZSF_MAX_RSS `
  --search-prefix "$PREFIX_PATH" `
  -Dstatic-llvm `
  -Dskip-non-native `
  -Denable-symlinks-windows `
  --test-timeout 30m
CheckLastExitCode

# Ensure that the fuzzer at least compiles.
# https://codeberg.org/ziglang/zig/issues/31893
# stage3-release\bin\zig.exe build test-std --fuzz=1K -Dno-lib -Dfuzz-only -Doptimize=ReleaseSafe
# CheckLastExitCode
# stage3-release\bin\zig.exe build test-std --fuzz=1K -Dno-lib -Dfuzz-only -Doptimize=Debug
# CheckLastExitCode

# Ensure that stage3 and stage4 are byte-for-byte identical.
Write-Output "Build and compare stage4..."
stage3-release\bin\zig.exe build `
  --prefix stage4-release `
  -Denable-llvm `
  -Dno-lib `
  -Doptimize=ReleaseFast `
  -Dstrip `
  -Dtarget="$TARGET" `
  -Dcpu="$MCPU" `
  -Duse-zig-libcxx `
  -Dversion-string="$(stage3-release\bin\zig.exe version)"
CheckLastExitCode

# Compare-Object returns an error code if the files differ.
Write-Output "If the following command fails, it means nondeterminism has been"
Write-Output "introduced, making stage3 and stage4 no longer byte-for-byte identical."
Compare-Object (Get-Content stage3-release\bin\zig.exe) (Get-Content stage4-release\bin\zig.exe)
CheckLastExitCode
