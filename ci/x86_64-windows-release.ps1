$TARGET = "x86_64-windows-gnu"
$MCPU = "baseline"
$PREFIX_PATH = "$($Env:USERPROFILE)\deps\zig+llvm+lld+clang-$TARGET-0.17.0-dev.203+073889523"
$ZIG = "$PREFIX_PATH\bin\zig.exe"
$ZIG_LIB_DIR = "$(Get-Location)\lib"
$ZSF_MAX_RSS = if ($Env:ZSF_MAX_RSS) { $Env:ZSF_MAX_RSS } else { 0 }

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
New-Item -Path 'build-release' -ItemType Directory
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

Write-Output "Main test suite..."
stage3-release\bin\zig.exe build test docs `
  --maxrss $ZSF_MAX_RSS `
  --zig-lib-dir "$ZIG_LIB_DIR" `
  --search-prefix "$PREFIX_PATH" `
  -Dstatic-llvm `
  -Dskip-non-native `
  -Dskip-test-incremental `
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
  -Duse-zig-libcxx `
  -Dversion-string="$(stage3-release\bin\zig version)"
CheckLastExitCode

# Compare-Object returns an error code if the files differ.
Write-Output "If the following command fails, it means nondeterminism has been"
Write-Output "introduced, making stage3 and stage4 no longer byte-for-byte identical."
Compare-Object (Get-Content stage3-release\bin\zig.exe) (Get-Content stage4-release\bin\zig.exe)
CheckLastExitCode

Write-Output "Build x86_64-windows-msvc behavior tests using the C backend..."
stage3-release\bin\zig.exe build-obj `
  --zig-lib-dir "$ZIG_LIB_DIR" `
  -ofmt=c `
  -OReleaseSmall `
  --name compiler_rt `
  -femit-bin="compiler_rt-x86_64-windows-msvc.c" `
  -target x86_64-windows-msvc `
  -lc `
  ..\lib\compiler_rt.zig
CheckLastExitCode

stage3-release\bin\zig.exe test `
  --zig-lib-dir "$ZIG_LIB_DIR" `
  -ofmt=c `
  -femit-bin="behavior-x86_64-windows-msvc.c" `
  --test-no-exec `
  -target x86_64-windows-msvc `
  -lc `
  ..\test\behavior.zig
CheckLastExitCode

Import-Module "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\Common7\Tools\Microsoft.VisualStudio.DevShell.dll"
CheckLastExitCode

Enter-VsDevShell -VsInstallPath "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools" `
  -DevCmdArguments '-arch=x64 -no_logo' `
  -StartInPath $(Get-Location)
CheckLastExitCode

Write-Output "Build and run behavior tests with msvc..."
cl /I..\lib /W3 /Z7 behavior-x86_64-windows-msvc.c compiler_rt-x86_64-windows-msvc.c /link /nologo /debug /subsystem:console kernel32.lib ntdll.lib libcmt.lib
CheckLastExitCode

.\behavior-x86_64-windows-msvc
CheckLastExitCode
