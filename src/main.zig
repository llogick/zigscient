const builtin = @import("builtin");
const native_os = builtin.os.tag;

const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;
const fs = std.fs;
const mem = std.mem;
const process = std.process;
const Allocator = mem.Allocator;
const Ast = std.zig.Ast;
const Color = std.zig.Color;
const warn = std.log.warn;
const cleanExit = std.process.cleanExit;
const Cache = std.Build.Cache;
const Path = std.Build.Cache.Path;
const Directory = std.Build.Cache.Directory;
const EnvVar = std.zig.EnvVar;
const LibCInstallation = std.zig.LibCInstallation;
const AstGen = std.zig.AstGen;
const ZonGen = std.zig.ZonGen;
const Server = std.zig.Server;
const stringToEnum = std.meta.stringToEnum;

pub const tracy = @import("tracy.zig");
pub const Compilation = @import("Compilation.zig");
const link = @import("link.zig");
const build_options = @import("build_options");
const wasi_libc = @import("libs/wasi_libc.zig");
const target_util = @import("target.zig");
pub const crash_report = @import("crash_report.zig");
const Zcu = @import("Zcu.zig");
const mingw = @import("libs/mingw.zig");
const dev = @import("dev.zig");
const Module = @import("Module.zig");

test {
    _ = @import("codegen.zig");
}

pub const thread_stack_size = 60 << 20;

pub const std_options: std.Options = .{
    .logFn = log,

    .log_level = switch (builtin.mode) {
        .debug => .debug,
        .safe, .fast => .info,
        .small => .err,
    },
};

pub const std_options_cwd = if (native_os == .wasi) wasi_cwd else null;

pub const panic = crash_report.panic;
pub const debug = crash_report.debug;

var preopens: std.process.Preopens = .empty;
pub fn wasi_cwd() Io.Dir {
    // Expect the first preopen to be current working directory.
    const cwd_fd: std.posix.fd_t = 3;
    assert(mem.eql(u8, preopens.map.keys()[cwd_fd], "."));
    return .{ .handle = cwd_fd };
}

const fatal = std.process.fatal;

/// This can be global since stdin is a singleton.
var stdin_buffer: [4096]u8 align(std.heap.page_size_min) = undefined;
/// This can be global since stdout is a singleton.
var stdout_buffer: [4096]u8 align(std.heap.page_size_min) = undefined;

const normal_usage =
    \\Usage: zig [command] [options]
    \\
    \\Commands:
    \\
    \\  build            Build project from build.zig
    \\  fetch            Copy a package into global cache and print its hash
    \\  init             Initialize a Zig package in the current directory
    \\
    \\  build-exe        Create executable from source or object files
    \\  build-lib        Create library from source or object files
    \\  build-obj        Create object from source or object files
    \\  test             Perform unit testing
    \\  test-obj         Create object for unit testing
    \\  run              Create executable and run immediately
    \\
    \\  ast-check        Look for simple compile errors in any set of files
    \\  fmt              Reformat Zig source into canonical form
    \\  reduce           Minimize a bug report
    \\  translate-c      Convert C code to Zig code
    \\
    \\  ar               Combine object files into static archive
    \\  cc               Use Zig as a drop-in C compiler
    \\  c++              Use Zig as a drop-in C++ compiler
    \\  dlltool          Use Zig as a drop-in dlltool.exe
    \\  lib              Use Zig as a drop-in lib.exe
    \\  objcopy          Manipulate executables and relocatables
    \\  objdump          Print information about executables and relocatables
    \\  ranlib           Use Zig as a drop-in ranlib
    \\  rc               Use Zig as a drop-in rc.exe
    \\
    \\  env              Print lib path, std path, cache directory, and version
    \\  help             Print this help and exit
    \\  std              View standard library documentation in a browser
    \\  libc             Display native libc paths file or validate one
    \\  targets          List available compilation targets
    \\  version          Print version number and exit
    \\  zen              Print Zen of Zig and exit
    \\
    \\General Options:
    \\
    \\  -h, --help       Print command-specific usage
    \\
;

const debug_usage = normal_usage ++
    \\
    \\Debug Commands:
    \\
    \\  changelist       Compute mappings from old ZIR to new ZIR
    \\  dump-zir         Dump a file containing cached ZIR
    \\
;

pub const usage = if (build_options.enable_debug_extensions) debug_usage else normal_usage;

var log_scopes: std.ArrayList([]const u8) = .empty;

pub fn log(
    comptime level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    // Hide debug messages unless:
    // * logging enabled with `-Dlog`.
    // * the --debug-log arg for the scope has been provided
    if (@backingInt(level) > @backingInt(std.options.log_level) or
        @backingInt(level) > @backingInt(std.log.Level.info))
    {
        if (!build_options.enable_logging) return;

        const scope_name = @tagName(scope);
        for (log_scopes.items) |log_scope| {
            if (mem.eql(u8, log_scope, scope_name))
                break;
        } else return;
    }

    // Otherwise, use the default implementation.
    std.log.defaultLog(level, scope, format, args);
}

const use_safe_allocator = build_options.debug_gpa or
    (native_os != .wasi and !builtin.link_libc and switch (builtin.mode) {
        .debug, .safe => true,
        .fast, .small => false,
    });

var safe_allocator: std.heap.SafeAllocator = .init(std.heap.page_allocator, .{
    .stack_trace_frames = build_options.mem_leak_frames,
});

pub fn main(init: std.process.Init.Minimal) anyerror!void {
    const root_gpa = if (use_safe_allocator)
        safe_allocator.allocator()
    else if (native_os == .wasi)
        std.heap.wasm_allocator
    else if (builtin.link_libc)
        std.heap.c_allocator
    else
        std.heap.smp_allocator;
    defer if (use_safe_allocator) {
        _ = safe_allocator.deinit();
    };
    var io_impl: IoImpl = undefined;
    switch (build_options.io_mode) {
        .threaded => io_impl = .init(root_gpa, .{
            .stack_size = thread_stack_size,

            .argv0 = .init(init.args),
            .environ = init.environ,
        }),
        .evented => try io_impl.init(root_gpa, .{
            .argv0 = .init(init.args),
            .environ = init.environ,

            .backing_allocator_needs_mutex = false,
        }),
    }
    defer io_impl.deinit();
    globals.io_impl_ptr = &io_impl;
    const io = io_impl.io();
    const gpa = switch (build_options.io_mode) {
        .threaded => root_gpa,
        .evented => io_impl.allocator(),
    };
    var arena_instance = std.heap.ArenaAllocator.init(gpa);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    const args = try init.args.toSlice(arena);

    if (args.len > 0) crash_report.zig_argv0 = args[0];

    var environ_map = init.environ.createMap(arena) catch |err| fatal("failed to parse environment: {t}", .{err});

    if (args.len <= 2) {
        std.log.info("{s}", .{usage});
        fatal("expected command argument", .{});
    }

    if (tracy.enable_allocation) {
        var tracy_allocator: tracy.Allocator = .{ .parent_allocator = gpa };
        return mainArgs(tracy_allocator.interface(), arena, io, args, &environ_map);
    }

    if (native_os == .wasi) {
        preopens = try .init(arena);
    }

    return mainArgs(gpa, arena, io, args, &environ_map);
}

const Cmd = enum {
    @"build-exe",
    @"build-lib",
    @"build-obj",
    @"test",
    @"test-obj",
    run,

    dlltool,
    ranlib,
    lib,
    ar,

    build,

    clang,
    @"-cc1",
    @"-cc1as",

    @"ld.lld",
    @"lld-link",
    @"wasm-ld",

    cc,
    @"c++",
    @"translate-c",
    rc,
    fmt,
    objcopy,
    objdump,
    fetch,
    libc,
    std,
    init,
    targets,
    version,
    env,
    reduce,
    zen,
    @"ast-check",

    help,
    @"-h",
    @"--help",

    changelist,
    @"dump-zir",
};

pub fn mainArgs(
    gpa: Allocator,
    arena: Allocator,
    io: Io,
    args: []const [:0]const u8,
    environ_map: *process.Environ.Map,
) !void {
    if (process.can_replace and EnvVar.ZIG_IS_DETECTING_LIBC_PATHS.isSet(environ_map)) {
        dev.check(.cc_command);
        // In this case we have accidentally invoked ourselves as "the system C compiler"
        // to figure out where libc is installed. This is essentially infinite recursion
        // via child process execution due to the CC environment variable pointing to Zig.
        // Here we ignore the CC environment variable and exec `cc` as a child process.
        // However it's possible Zig is installed as *that* C compiler as well, which is
        // why we have this additional environment variable here to check.

        const inf_loop_env_key: EnvVar = .ZIG_IS_AVOIDING_CALLING_ITSELF;
        if (inf_loop_env_key.isSet(environ_map)) {
            fatal("{s}", .{
                "The compilation links against libc, but Zig is unable to provide a libc " ++
                    "for this operating system, and no --libc " ++
                    "parameter was provided, so Zig attempted to invoke the system C compiler " ++
                    "in order to determine where libc is installed. However the system C " ++
                    "compiler is `zig cc`, so no libc installation was found.",
            });
        }
        try environ_map.put(@tagName(inf_loop_env_key), "1");

        // Some programs such as CMake will strip the `cc` and subsequent args from the
        // CC environment variable. We detect and support this scenario here because of
        // the ZIG_IS_DETECTING_LIBC_PATHS environment variable.
        if (mem.eql(u8, args[2], "cc")) {
            return process.replace(io, .{ .argv = args[1..], .environ_map = environ_map });
        } else {
            const modified_args = try arena.dupe([]const u8, args);
            modified_args[1] = "cc";
            return process.replace(io, .{ .argv = modified_args[1..], .environ_map = environ_map });
        }
    }

    const cmd = args[2];
    const cmd_args = args[3..];
    switch (stringToEnum(Cmd, cmd) orelse {
        std.log.info("{s}", .{usage});
        fatal("unknown command: {s}", .{cmd});
    }) {
        .@"build-exe" => {
            dev.check(.build_exe_command);
            var cs: CompilationState = .{};
            defer cs.deinit(gpa);
            return buildOutputType(gpa, arena, io, args, .{ .build = .Exe }, environ_map, &cs, null, null);
        },
        .@"build-lib" => {
            dev.check(.build_lib_command);
            var cs: CompilationState = .{};
            defer cs.deinit(gpa);
            return buildOutputType(gpa, arena, io, args, .{ .build = .Lib }, environ_map, &cs, null, null);
        },
        .@"build-obj" => {
            dev.check(.build_obj_command);
            var cs: CompilationState = .{};
            defer cs.deinit(gpa);
            return buildOutputType(gpa, arena, io, args, .{ .build = .Obj }, environ_map, &cs, null, null);
        },
        .@"test" => {
            dev.check(.test_command);
            var cs: CompilationState = .{};
            defer cs.deinit(gpa);
            return buildOutputType(gpa, arena, io, args, .zig_test, environ_map, &cs, null, null);
        },
        .@"test-obj" => {
            dev.check(.test_command);
            var cs: CompilationState = .{};
            defer cs.deinit(gpa);
            return buildOutputType(gpa, arena, io, args, .zig_test_obj, environ_map, &cs, null, null);
        },
        .run => {
            dev.check(.run_command);
            var cs: CompilationState = .{};
            defer cs.deinit(gpa);
            return buildOutputType(gpa, arena, io, args, .run, environ_map, &cs, null, null);
        },
        .dlltool, .ranlib, .lib, .ar => {
            dev.check(.ar_command);
            return process.exit(try llvmArMain(arena, args));
        },
        .build, .fetch, .init, .libc => {
            return jitCmd(gpa, arena, io, cmd_args, environ_map, .{
                .cmd_name = "maker",
                .root_src_path = "Maker.zig",
                .prepend_cmd = cmd,
                .prepend_zig_lib_dir_path = true,
                .prepend_global_cache_path = true,
                .prepend_zig_exe_path = true,
                .prepend_seed = true,
                .release_mode = .safe,
            });
        },
        .clang, .@"-cc1", .@"-cc1as" => {
            dev.check(.clang_command);
            return process.exit(try clangMain(arena, args));
        },
        .@"ld.lld", .@"lld-link", .@"wasm-ld" => {
            dev.check(.lld_linker);
            return process.exit(try lldMain(arena, args, true));
        },
        .cc => {
            dev.check(.cc_command);
            var cs: CompilationState = .{};
            defer cs.deinit(gpa);
            return buildOutputType(gpa, arena, io, args, .cc, environ_map, &cs, null, null);
        },
        .@"c++" => {
            dev.check(.cc_command);
            var cs: CompilationState = .{};
            defer cs.deinit(gpa);
            return buildOutputType(gpa, arena, io, args, .cpp, environ_map, &cs, null, null);
        },
        .@"translate-c" => {
            dev.check(.translate_c_command);
            var cs: CompilationState = .{};
            defer cs.deinit(gpa);
            return buildOutputType(gpa, arena, io, args, .translate_c, environ_map, &cs, null, null);
        },
        .rc => {
            const use_server = cmd_args.len > 0 and std.mem.eql(u8, cmd_args[0], "--zig-integration");
            return jitCmd(gpa, arena, io, cmd_args, environ_map, .{
                .cmd_name = "resinator",
                .root_src_path = "resinator/main.zig",
                .depend_on_aro = true,
                .prepend_zig_lib_dir_path = true,
                .server = use_server,
            });
        },
        .fmt => {
            dev.check(.fmt_command);
            return @import("fmt.zig").run(gpa, arena, io, cmd_args);
        },
        .objcopy => {
            return jitCmd(gpa, arena, io, cmd_args, environ_map, .{
                .cmd_name = "objcopy",
                .root_src_path = "objcopy.zig",
            });
        },
        .objdump => {
            return jitCmd(gpa, arena, io, cmd_args, environ_map, .{
                .cmd_name = "objdump",
                .root_src_path = "objdump.zig",
            });
        },
        .std => {
            return jitCmd(gpa, arena, io, cmd_args, environ_map, .{
                .cmd_name = "std",
                .root_src_path = "std-docs.zig",
                .prepend_zig_lib_dir_path = true,
                .prepend_zig_exe_path = true,
                .prepend_global_cache_path = true,
            });
        },
        .targets => {
            dev.check(.targets_command);
            const self_exe_path = switch (native_os) {
                .wasi => {},
                else => process.executablePathAlloc(io, arena) catch |err| fatal("unable to find zig self exe path: {t}", .{err}),
            };
            var dirs: std.zig.Directories = .init(
                arena,
                io,
                EnvVar.ZIG_LIB_DIR.get(environ_map),
                EnvVar.ZIG_GLOBAL_CACHE_DIR.get(environ_map),
                .global,
                preopens,
                self_exe_path,
                environ_map,
                try std.zig.getResolvedCwd(io, arena),
            );
            defer dirs.deinit(io);
            const host = std.zig.resolveTargetQueryOrFatal(io, .{});
            var stdout_writer = Io.File.stdout().writer(io, &stdout_buffer);
            try @import("print_targets.zig").cmdTargets(
                arena,
                io,
                &dirs,
                cmd_args,
                &stdout_writer.interface,
                &host,
            );
            return stdout_writer.interface.flush();
        },
        .version => {
            // dev.check(.version_command);
            try Io.File.stdout().writeStreamingAll(io, build_options.version ++ "\n");
            return;
        },
        .env => {
            dev.check(.env_command);
            const self_exe_path = switch (native_os) {
                .wasi => args[0],
                else => process.executablePathAlloc(io, arena) catch |err| fatal("unable to find zig self exe path: {t}", .{err}),
            };
            var dirs: std.zig.Directories = .init(
                arena,
                io,
                EnvVar.ZIG_LIB_DIR.get(environ_map),
                EnvVar.ZIG_GLOBAL_CACHE_DIR.get(environ_map),
                .global,
                preopens,
                if (native_os != .wasi) self_exe_path,
                environ_map,
                try std.zig.getResolvedCwd(io, arena),
            );
            defer dirs.deinit(io);
            const host = std.zig.resolveTargetQueryOrFatal(io, .{});
            var stdout_writer = Io.File.stdout().writer(io, &stdout_buffer);
            try @import("print_env.zig").cmdEnv(
                arena,
                &stdout_writer.interface,
                &host,
                environ_map,
                &dirs,
                self_exe_path,
            );
            return stdout_writer.interface.flush();
        },
        .reduce => {
            return jitCmd(gpa, arena, io, cmd_args, environ_map, .{
                .cmd_name = "reduce",
                .root_src_path = "reduce.zig",
            });
        },
        .zen => {
            dev.check(.zen_command);
            return Io.File.stdout().writeStreamingAll(io, info_zen);
        },
        .help, .@"-h", .@"--help" => {
            dev.check(.help_command);
            return Io.File.stdout().writeStreamingAll(io, usage);
        },
        .@"ast-check" => {
            dev.check(.ast_check_command);
            return cmdAstCheck(arena, io, cmd_args, environ_map);
        },
        .changelist => {
            dev.check(.changelist_command);
            return cmdChangelist(arena, io, cmd_args, environ_map);
        },
        .@"dump-zir" => {
            dev.check(.dump_zir_command);
            return cmdDumpZir(arena, io, cmd_args);
        },
    }
}

const usage_build_generic =
    \\Usage: zig build-exe   [options] [files]
    \\       zig build-lib   [options] [files]
    \\       zig build-obj   [options] [files]
    \\       zig test        [options] [files]
    \\       zig run         [options] [files] [-- [args]]
    \\       zig translate-c [options] [file]
    \\
    \\Supported file types:
    \\                         .zig    Zig source code
    \\                           .o    ELF object file
    \\                           .o    Mach-O (macOS) object file
    \\                           .o    WebAssembly object file
    \\                         .obj    COFF (Windows) object file
    \\                         .lib    COFF (Windows) static library
    \\                           .a    ELF static library
    \\                           .a    Mach-O (macOS) static library
    \\                           .a    WebAssembly static library
    \\                          .so    ELF shared object (dynamic link)
    \\                         .dll    Windows Dynamic Link Library
    \\                       .dylib    Mach-O (macOS) dynamic library
    \\                         .tbd    (macOS) text-based dylib definition
    \\                           .s    Target-specific assembly source code
    \\                           .S    Assembly with C preprocessor (requires LLVM extensions)
    \\                           .c    C source code (requires LLVM extensions)
    \\        .cxx .cc .C .cpp .c++    C++ source code (requires LLVM extensions)
    \\                           .m    Objective-C source code (requires LLVM extensions)
    \\                          .mm    Objective-C++ source code (requires LLVM extensions)
    \\                          .bc    LLVM IR Module (requires LLVM extensions)
    \\
    \\General Options:
    \\  -h, --help                Print this help and exit
    \\  --color [auto|off|on]     Enable or disable colored error messages
    \\  -j<N>                     Limit concurrent jobs (default is to use all CPU cores)
    \\  -fincremental             Enable incremental compilation
    \\  -fno-incremental          Disable incremental compilation
    \\  -femit-bin[=path]         (default) Output machine code
    \\  -fno-emit-bin             Do not output machine code
    \\  -femit-asm[=path]         Output .s (assembly code)
    \\  -fno-emit-asm             (default) Do not output .s (assembly code)
    \\  -femit-llvm-ir[=path]     Produce a .ll file with optimized LLVM IR (requires LLVM extensions)
    \\  -fno-emit-llvm-ir         (default) Do not produce a .ll file with optimized LLVM IR
    \\  -femit-llvm-bc[=path]     Produce an optimized LLVM module as a .bc file (requires LLVM extensions)
    \\  -fno-emit-llvm-bc         (default) Do not produce an optimized LLVM module as a .bc file
    \\  -femit-h[=path]           Generate a C header file (.h)
    \\  -fno-emit-h               (default) Do not generate a C header file (.h)
    \\  -femit-docs[=path]        Create a docs/ dir with html documentation
    \\  -fno-emit-docs            (default) Do not produce docs/ dir with html documentation
    \\  -femit-implib[=path]      (default) Produce an import .lib when building a Windows DLL
    \\  -fno-emit-implib          Do not produce an import .lib when building a Windows DLL
    \\  --show-builtin            Output the source of @import("builtin") then exit
    \\  --cache-dir [path]        Override the local cache directory
    \\  --global-cache-dir [path] Override the global cache directory
    \\  --zig-lib-dir [path]      Override path to Zig installation lib directory
    \\
    \\Global Compile Options:
    \\  --name [name]             Compilation unit name (not a file path)
    \\  --libc [file]             Provide a file which specifies libc paths
    \\  -x language               Treat subsequent input files as having type <language>
    \\  --dep [[import=]name]     Add an entry to the next module's import table
    \\  -M[name][=src]            Create a module based on the current per-module settings.
    \\                            The first module is the main module.
    \\                            "std" can be configured by omitting src
    \\                            After a -M argument, per-module settings are reset.
    \\  --error-limit [num]       Set the maximum amount of distinct error values
    \\  -fllvm                    Force using LLVM as the codegen backend
    \\  -fno-llvm                 Prevent using LLVM as the codegen backend
    \\  -flibllvm                 Force using the LLVM API in the codegen backend
    \\  -fno-libllvm              Prevent using the LLVM API in the codegen backend
    \\  -fclang                   Force using Clang as the C/C++ compilation backend
    \\  -fno-clang                Prevent using Clang as the C/C++ compilation backend
    \\  -fPIE                     Force-enable Position Independent Executable
    \\  -fno-PIE                  Force-disable Position Independent Executable
    \\  -flto                     Force-enable Link Time Optimization (requires LLVM extensions)
    \\  -fno-lto                  Force-disable Link Time Optimization
    \\  -fdll-export-fns          Mark exported functions as DLL exports (Windows)
    \\  -fno-dll-export-fns       Force-disable marking exported functions as DLL exports
    \\  -freference-trace[=num]   Show num lines of reference trace per compile error
    \\  -fno-reference-trace      Disable reference trace
    \\  -ffunction-sections       Places each function in a separate section
    \\  -fno-function-sections    All functions go into same section
    \\  -fdata-sections           Places each data in a separate section
    \\  -fno-data-sections        All data go into same section
    \\  -mexec-model=[value]      (WASI) Execution model
    \\  -municode                 (Windows) Use wmain/wWinMain as entry point
    \\  --time-report             Send timing diagnostics to '--listen' clients
    \\
    \\Per-Module Compile Options:
    \\  -target [name]            <arch><sub>-<os>-<abi> see the targets command
    \\  -O [mode]                 Choose what to optimize for
    \\    debug (default)         Prioritize bug detection, accurate debug info, compilation speed
    \\    fast                    Prioritize runtime performance. Safety checks off.
    \\    safe                    Enable both safety checks and machine code optimizations
    \\    small                   Prioritize small binary size. Safety checks off.
    \\  -ofmt=[fmt]               Override target object format
    \\    elf                     Executable and Linking Format
    \\    c                       C source code
    \\    wasm                    WebAssembly
    \\    coff                    Common Object File Format (Windows)
    \\    macho                   macOS relocatables
    \\    spirv                   Standard, Portable Intermediate Representation V (SPIR-V)
    \\    plan9                   Plan 9 from Bell Labs object format
    \\    hex  (planned feature)  Intel IHEX
    \\    raw  (planned feature)  Dump machine code directly
    \\  -mcpu [cpu]               Specify target CPU and feature set
    \\  -mcmodel=[model]          Limit range of code and data virtual addresses
    \\    default
    \\    extreme
    \\    kernel
    \\    large
    \\    medany
    \\    medium
    \\    medlow
    \\    medmid
    \\    normal
    \\    small
    \\    tiny
    \\  -mred-zone                Force-enable the "red-zone"
    \\  -mno-red-zone             Force-disable the "red-zone"
    \\  -fomit-frame-pointer      Omit the stack frame pointer
    \\  -fno-omit-frame-pointer   Store the stack frame pointer
    \\  -fPIC                     Force-enable Position Independent Code
    \\  -fno-PIC                  Force-disable Position Independent Code
    \\  -fstack-check             Enable stack probing in unsafe builds
    \\  -fno-stack-check          Disable stack probing in safe builds
    \\  -fstack-protector         Enable stack protection in unsafe builds
    \\  -fno-stack-protector      Disable stack protection in safe builds
    \\  -fvalgrind                Include valgrind client requests in release builds
    \\  -fno-valgrind             Omit valgrind client requests in debug builds
    \\  -fsanitize-c[=mode]       Enable C undefined behavior detection in unsafe builds
    \\    trap                    Insert trap instructions on undefined behavior
    \\    full                    (Default) Insert runtime calls on undefined behavior
    \\  -fno-sanitize-c           Disable C undefined behavior detection in safe builds
    \\  -fsanitize-thread         Enable Thread Sanitizer
    \\  -fno-sanitize-thread      Disable Thread Sanitizer
    \\  -ffuzz                    Enable fuzz testing instrumentation
    \\  -fno-fuzz                 Disable fuzz testing instrumentation
    \\  -fbuiltin                 Enable implicit builtin knowledge of functions
    \\  -fno-builtin              Disable implicit builtin knowledge of functions
    \\  -funwind-tables           Always produce unwind table entries for all functions
    \\  -fasync-unwind-tables     Always produce asynchronous unwind table entries for all functions
    \\  -fno-unwind-tables        Never produce unwind table entries
    \\  -ferror-tracing           Enable error tracing in release builds
    \\  -fno-error-tracing        Disable error tracing in debug builds
    \\  -fsingle-threaded         Code assumes there is only one thread
    \\  -fno-single-threaded      Code may not assume there is only one thread
    \\  -fstrip                   Omit debug symbols
    \\  -fno-strip                Keep debug symbols
    \\  -idirafter [dir]          Add directory to AFTER include search path
    \\  -isystem  [dir]           Add directory to SYSTEM include search path
    \\  -I[dir]                   Add directory to include search path
    \\  --embed-dir=[dir]         Add directory to embed search path
    \\  -D[macro]=[value]         Define C [macro] to [value] (1 if [value] omitted)
    \\  -cflags [flags] --        Set extra flags for the next positional C source files
    \\  -rcflags [flags] --       Set extra flags for the next positional .rc source files
    \\  -rcincludes=[type]        Set the type of includes to use when compiling .rc source files
    \\    any                     (default) Use msvc if available, fall back to gnu
    \\    msvc                    Use msvc include paths (must be present on the system)
    \\    gnu                     Use mingw include paths (distributed with Zig)
    \\    none                    Do not use any autodetected include paths
    \\
    \\Global Link Options:
    \\  -T[script], --script [script]  Use a custom linker script
    \\  --version-script [path]        Provide a version .map file
    \\  --undefined-version            Allow version scripts to refer to undefined symbols
    \\  --no-undefined-version         (default) Disallow version scripts from referring to undefined symbols
    \\  --enable-new-dtags             Use the new behavior for dynamic tags (RUNPATH)
    \\  --disable-new-dtags            Use the old behavior for dynamic tags (RPATH)
    \\  --dynamic-linker [path]        Set the dynamic interpreter path (usually ld.so)
    \\  --no-dynamic-linker            Do not set any dynamic interpreter path
    \\  --sysroot [path]               Set the system root directory (usually /)
    \\  --version [ver]                Dynamic library semver
    \\  -fentry                        Enable entry point with default symbol name
    \\  -fentry=[name]                 Override the entry point symbol name
    \\  -fno-entry                     Do not output any entry point
    \\  --force_undefined [name]       Specify the symbol must be defined for the link to succeed
    \\  -fsoname[=name]                Override the default SONAME value
    \\  -fno-soname                    Disable emitting a SONAME
    \\  -flld                          Force using LLD as the linker
    \\  -fno-lld                       Prevent using LLD as the linker
    \\  -fcompiler-rt                  Always include compiler-rt symbols in output
    \\  -fno-compiler-rt               Prevent including compiler-rt symbols in output
    \\  -fubsan-rt                     Always include ubsan-rt symbols in the output
    \\  -fno-ubsan-rt                  Prevent including ubsan-rt symbols in the output
    \\  -rdynamic                      Add all symbols to the dynamic symbol table
    \\  -feach-lib-rpath               Ensure adding rpath for each used dynamic library
    \\  -fno-each-lib-rpath            Prevent adding rpath for each used dynamic library
    \\  -fallow-shlib-undefined        Allows undefined symbols in shared libraries
    \\  -fno-allow-shlib-undefined     Disallows undefined symbols in shared libraries
    \\  -fallow-so-scripts             Allows .so files to be GNU ld scripts
    \\  -fno-allow-so-scripts          (default) .so files must be ELF files
    \\  --build-id[=style]             At a minor link-time expense, embeds a build ID in binaries
    \\      fast                       8-byte non-cryptographic hash (COFF, ELF, WASM)
    \\      sha1, tree                 20-byte cryptographic hash (ELF, WASM)
    \\      md5                        16-byte cryptographic hash (ELF)
    \\      uuid                       16-byte random UUID (ELF, WASM)
    \\      0x[hexstring]              Constant ID, maximum 32 bytes (ELF, WASM)
    \\      none                     (default) No build ID
    \\  --eh-frame-hdr                 Enable C++ exception handling by passing --eh-frame-hdr to linker
    \\  --no-eh-frame-hdr              Disable C++ exception handling by passing --no-eh-frame-hdr to linker
    \\  --emit-relocs                  Enable output of relocation sections for post build tools
    \\  -z [arg]                       Set linker extension flags
    \\    nodelete                     Indicate that the object cannot be deleted from a process
    \\    notext                       Permit read-only relocations in read-only segments
    \\    defs                         Force a fatal error if any undefined symbols remain
    \\    undefs                       Reverse of -z defs
    \\    origin                       Indicate that the object must have its origin processed
    \\    nocopyreloc                  Disable the creation of copy relocations
    \\    now                          (default) Force all relocations to be processed on load
    \\    lazy                         Don't force all relocations to be processed on load
    \\    relro                        (default) Force all relocations to be read-only after processing
    \\    norelro                      Don't force all relocations to be read-only after processing
    \\    common-page-size=[bytes]     Set the common page size for ELF binaries
    \\    max-page-size=[bytes]        Set the max page size for ELF binaries
    \\  -dynamic                       Force output to be dynamically linked
    \\  -static                        Force output to be statically linked
    \\  -Bsymbolic                     Bind global references locally
    \\  --compress-debug-sections=[e]  Debug section compression settings
    \\      none                       No compression
    \\      zlib                       Compression with deflate/inflate
    \\      zstd                       Compression with zstandard
    \\  --gc-sections                  Force removal of functions and data that are unreachable by the entry point or exported symbols
    \\  --no-gc-sections               Don't force removal of unreachable functions and data
    \\  --sort-section=[value]         Sort wildcard section patterns by 'name' or 'alignment'
    \\  --subsystem [subsystem]        (Windows) /SUBSYSTEM:<subsystem> to the linker
    \\  --stack [size]                 Override default stack size
    \\  --image-base [addr]            Set base address for executable image
    \\  -install_name=[value]          (Darwin) add dylib's install name
    \\  --entitlements [path]          (Darwin) add path to entitlements file for embedding in code signature
    \\  -pagezero_size [value]         (Darwin) size of the __PAGEZERO segment in hexadecimal notation
    \\  -headerpad [value]             (Darwin) set minimum space for future expansion of the load commands in hexadecimal notation
    \\  -headerpad_max_install_names   (Darwin) set enough space as if all paths were MAXPATHLEN
    \\  -dead_strip                    (Darwin) remove functions and data that are unreachable by the entry point or exported symbols
    \\  -dead_strip_dylibs             (Darwin) remove dylibs that are unreachable by the entry point or exported symbols
    \\  -ObjC                          (Darwin) force load all members of static archives that implement an Objective-C class or category
    \\  --import-memory                (WebAssembly) import memory from the environment
    \\  --export-memory                (WebAssembly) export memory to the host (Default unless --import-memory used)
    \\  --import-symbols               (WebAssembly) import missing symbols from the host environment
    \\  --import-table                 (WebAssembly) import function table from the host environment
    \\  --export-table                 (WebAssembly) export function table to the host environment
    \\  --growable-table               (WebAssembly) remove maximum size from function table, allowing table to grow
    \\  --initial-memory=[bytes]       (WebAssembly) initial size of the linear memory
    \\  --max-memory=[bytes]           (WebAssembly) maximum size of the linear memory
    \\  --shared-memory                (WebAssembly) use shared linear memory
    \\  --global-base=[addr]           (WebAssembly) where to start to place global data
    \\
    \\Per-Module Link Options:
    \\  -l[lib], --library [lib]       Link against system library (only if actually used)
    \\  -needed-l[lib],                Link against system library (even if unused)
    \\    --needed-library [lib]
    \\  -weak-l[lib]                   link against system library marking it and all
    \\    -weak_library [lib]          referenced symbols as weak
    \\  -L[d], --library-directory [d] Add a directory to the library search path
    \\  -search_paths_first            For each library search path, check for dynamic
    \\                                 lib then static lib before proceeding to next path.
    \\  -search_paths_first_static     For each library search path, check for static
    \\                                 lib then dynamic lib before proceeding to next path.
    \\  -search_dylibs_first           Search for dynamic libs in all library search
    \\                                 paths, then static libs.
    \\  -search_static_first           Search for static libs in all library search
    \\                                 paths, then dynamic libs.
    \\  -search_dylibs_only            Only search for dynamic libs.
    \\  -search_static_only            Only search for static libs.
    \\  -rpath [path]                  Add directory to the runtime library search path
    \\  -framework [name]              (Darwin) link against framework
    \\  -needed_framework [name]       (Darwin) link against framework (even if unused)
    \\  -needed_library [lib]          (Darwin) link against system library (even if unused)
    \\  -weak_framework [name]         (Darwin) link against framework and mark it and all referenced symbols as weak
    \\  -F[dir]                        (Darwin) add search path for frameworks
    \\  --export=[value]               (WebAssembly) Force a symbol to be exported
    \\
    \\Test Options:
    \\  --test-filter [text]           Skip tests that do not match any filter
    \\  --test-cmd [arg]               Specify test execution command one arg at a time
    \\  --test-cmd-bin                 Appends test binary path to test cmd args
    \\  --test-no-exec                 Compiles test binary without running it
    \\  --test-runner [path]           Specify a custom test runner
    \\  --test-execve                  Runs the test binary with execve if available instead of as a child process
    \\
    \\Debug Options (Zig Compiler Development):
    \\  -fopt-bisect-limit=[limit]   Only run [limit] first LLVM optimization passes
    \\  -fstack-report               Print stack size diagnostics
    \\  --verbose-link               Display linker invocations
    \\  --verbose-cc                 Display C compiler invocations
    \\  --verbose-air                Enable compiler debug output for Zig AIR
    \\  --verbose-intern-pool        Enable compiler debug output for InternPool
    \\  --verbose-generic-instances  Enable compiler debug output for generic instance generation
    \\  --verbose-llvm-ir[=path]     Enable compiler debug output for unoptimized LLVM IR
    \\  --verbose-llvm-bc=[path]     Enable compiler debug output for unoptimized LLVM BC
    \\  --verbose-cimport            Enable compiler debug output for C imports
    \\  --verbose-llvm-cpu-features  Enable compiler debug output for LLVM CPU features
    \\  --debug-log [scope]          Enable printing debug/info log messages for scope
    \\  --debug-compile-errors       Crash with helpful diagnostics at the first compile error
    \\  --debug-link-snapshot        Enable dumping of the linker's state in JSON format
    \\  --debug-rt[=mode]            Build compiler runtime libraries with [mode] optimization
    \\                               (Debug if [=mode] is omitted)
    \\  --debug-incremental          Enable incremental compilation debug features
    \\
;

const SOName = union(enum) {
    no,
    yes_default_value,
    yes: []const u8,
};

const EmitBin = union(enum) {
    no,
    yes_default_path,
    yes: []const u8,
    yes_a_out,
};

const Emit = union(enum) {
    no,
    yes_default_path,
    yes: []const u8,

    const OutputToCacheReason = enum { listen, @"zig run", @"zig test" };
    fn resolve(emit: Emit, io: Io, default_basename: []const u8, output_to_cache: ?OutputToCacheReason) Compilation.CreateOptions.Emit {
        return switch (emit) {
            .no => .no,
            .yes_default_path => if (output_to_cache != null) .yes_cache else .{ .yes_path = default_basename },
            .yes => |path| if (output_to_cache) |reason| {
                switch (reason) {
                    .listen => fatal("--listen incompatible with explicit output path {q}", .{path}),
                    .@"zig run", .@"zig test" => fatal(
                        "{q} with explicit output path {q} requires explicit '-femit-bin=path' or '-fno-emit-bin'",
                        .{ @tagName(reason), path },
                    ),
                }
            } else e: {
                // If there's a dirname, check that dir exists. This will give a more descriptive error than `Compilation` otherwise would.
                if (fs.path.dirname(path)) |dir_path| {
                    var dir = Io.Dir.cwd().openDir(io, dir_path, .{}) catch |err| {
                        fatal("unable to open output directory {q}: {t}", .{ dir_path, err });
                    };
                    dir.close(io);
                }
                break :e .{ .yes_path = path };
            },
        };
    }
};

pub const ArgMode = union(enum) {
    build: std.lang.OutputMode,
    cc,
    cpp,
    translate_c,
    zig_test,
    zig_test_obj,
    run,
};

const Listen = union(enum) {
    none,
    stdio: if (dev.env.supports(.stdio_listen)) void else noreturn,
    ip4: if (dev.env.supports(.network_listen)) Io.net.Ip4Address else noreturn,
};

const ArgsIterator = struct {
    resp_file: ?ArgIteratorResponseFile = null,
    args: []const []const u8,
    i: usize = 0,
    fn next(it: *@This()) ?[]const u8 {
        if (it.i >= it.args.len) {
            if (it.resp_file) |*resp| return resp.next();
            return null;
        }
        defer it.i += 1;
        return it.args[it.i];
    }
    fn nextOrFatal(it: *@This()) []const u8 {
        if (it.i >= it.args.len) {
            if (it.resp_file) |*resp| if (resp.next()) |ret| return ret;
            fatal("expected parameter after {s}", .{it.args[it.i - 1]});
        }
        defer it.i += 1;
        return it.args[it.i];
    }
};

/// Similar to `link.Framework` except it doesn't store yet unresolved
/// path to the framework.
const Framework = struct {
    needed: bool = false,
    weak: bool = false,
};

const CliModule = struct {
    root_path: []const u8,
    root_src_path: []const u8,
    cc_argv: []const []const u8,
    inherited: Module.CreateOptions.Inherited,
    target_arch_os_abi: ?[]const u8,
    target_mcpu: ?[]const u8,
    dynamic_linker: ?[]const u8,

    deps: []const Dep,
    resolved: ?*Module,

    c_source_files_start: usize,
    c_source_files_end: usize,
    rc_source_files_start: usize,
    rc_source_files_end: usize,

    const Dep = struct {
        key: []const u8,
        value: []const u8,
    };
};

pub const CompilationState = struct {
    diag_tag: lsp_server.DiagnosticsCollection.Tag = undefined,
    diag_rev_id: u32 = 0,
    project_root_path: ?[]const u8 = null,
    provided_name: ?[]const u8 = null,
    root_src_file: ?[]const u8 = null,
    version: std.SemanticVersion = .{ .major = 0, .minor = 0, .patch = 0 },
    have_version: bool = false,
    compatibility_version: ?std.SemanticVersion = null,
    function_sections: bool = false,
    data_sections: bool = false,
    listen: Listen = .none,
    debug_compile_errors: bool = false,
    debug_incremental: bool = false,
    verbose_link: bool = false,
    verbose_cc: bool = false,
    verbose_air: bool = false,
    verbose_intern_pool: bool = false,
    verbose_generic_instances: bool = false,
    verbose_llvm_ir: ?[]const u8 = null,
    verbose_llvm_bc: ?[]const u8 = null,
    link_depfile: ?[]const u8 = null,
    verbose_llvm_cpu_features: bool = false,
    time_report: bool = false,
    stack_report: bool = false,
    show_builtin: bool = false,
    emit_bin: EmitBin = .yes_default_path,
    emit_asm: Emit = .no,
    emit_llvm_ir: Emit = .no,
    emit_llvm_bc: Emit = .no,
    emit_docs: Emit = .no,
    emit_implib: Emit = .yes_default_path,
    emit_implib_arg_provided: bool = false,
    target_arch_os_abi: ?[]const u8 = null,
    target_mcpu: ?[]const u8 = null,
    dynamic_linker: ?[]const u8 = null,
    emit_h: Emit = .no,
    soname: SOName = undefined,
    want_compiler_rt: ?bool = null,
    zig_cc_explicitly_link_compiler_rt: bool = false,
    want_ubsan_rt: ?bool = null,
    linker_script: ?[]const u8 = null,
    version_script: ?[]const u8 = null,
    linker_repro: ?bool = null,
    linker_allow_undefined_version: bool = false,
    linker_enable_new_dtags: ?bool = null,
    disable_c_depfile: bool = false,
    linker_sort_section: ?link.File.Lld.Elf.SortSection = null,
    linker_gc_sections: ?bool = null,
    linker_compress_debug_sections: ?std.zig.CompressDebugSections = null,
    linker_allow_shlib_undefined: ?bool = null,
    allow_so_scripts: bool = false,
    linker_bind_global_refs_locally: ?bool = null,
    linker_import_symbols: bool = false,
    linker_import_table: bool = false,
    linker_export_table: bool = false,
    linker_growable_table: bool = false,
    linker_initial_memory: ?u64 = null,
    linker_max_memory: ?u64 = null,
    linker_global_base: ?u64 = null,
    linker_print_gc_sections: bool = false,
    linker_print_icf_sections: bool = false,
    linker_print_map: bool = false,
    linker_nmagic: bool = false,
    linker_fatal_warnings: bool = false,
    llvm_opt_bisect_limit: c_int = -1,
    linker_z_nocopyreloc: bool = false,
    linker_z_nodelete: bool = false,
    linker_z_notext: bool = false,
    linker_z_defs: bool = false,
    linker_z_origin: bool = false,
    linker_z_now: bool = true,
    linker_z_relro: bool = true,
    linker_z_common_page_size: ?u64 = null,
    linker_z_max_page_size: ?u64 = null,
    linker_tsaware: bool = false,
    linker_nxcompat: bool = false,
    linker_dynamicbase: bool = true,
    linker_optimization: ?[]const u8 = null,
    self_exe_path_or_argv0: switch (native_os) {
        .wasi => void,
        else => []const u8,
    } = undefined,
    dirs: std.zig.Directories = undefined,
    linker_module_definition_file: ?[]const u8 = null,
    test_no_exec: bool = false,
    test_execve: bool = false,
    entry: Compilation.CreateOptions.Entry = .default,
    force_undefined_symbols: std.StringArrayHashMapUnmanaged(void) = .empty,
    stack_size: ?u64 = null,
    image_base: ?u64 = null,
    link_eh_frame_hdr: bool = false,
    link_emit_relocs: bool = false,
    build_id: ?std.zig.BuildId = null,
    runtime_args_start: ?usize = null,
    test_filters: std.ArrayList([]const u8) = .empty,
    test_runner_path: ?[]const u8 = null,
    override_local_cache_dir: ?[]const u8 = null,
    override_global_cache_dir: ?[]const u8 = null,
    override_lib_dir: ?[]const u8 = null,
    clang_preprocessor_mode: Compilation.ClangPreprocessorMode = .no,
    subsystem: ?std.zig.Subsystem = null,
    major_subsystem_version: ?u16 = null,
    minor_subsystem_version: ?u16 = null,
    mingw_unicode_entry_point: bool = false,
    enable_link_snapshots: bool = false,
    debug_compiler_runtime_libs: ?std.lang.OptimizeMode = null,
    install_name: ?[]const u8 = null,
    hash_style: link.File.Lld.Elf.HashStyle = .both,
    entitlements: ?[]const u8 = null,
    pagezero_size: ?u64 = null,
    lib_search_strategy: link.UnresolvedInput.SearchStrategy = .paths_first,
    lib_preferred_mode: std.lang.LinkMode = .dynamic,
    headerpad_size: ?u32 = null,
    headerpad_max_install_names: bool = false,
    dead_strip_dylibs: bool = false,
    force_load_objc: bool = false,
    discard_local_symbols: bool = false,
    contains_res_file: bool = false,
    reference_trace: ?u32 = null,
    pdb_out_path: ?[]const u8 = null,
    error_limit: ?Zcu.ErrorInt = null,
    // These are before resolving sysroot.
    extra_cflags: std.ArrayList([]const u8) = .empty,
    extra_rcflags: std.ArrayList([]const u8) = .empty,
    symbol_wrap_set: std.StringArrayHashMapUnmanaged(void) = .empty,
    rc_includes: std.zig.RcIncludes = .any,
    manifest_file: ?[]const u8 = null,
    linker_export_symbol_names: std.ArrayList([]const u8) = .empty,

    // Tracks the position in c_source_files which have already their owner populated.
    c_source_files_owner_index: usize = 0,
    // Tracks the position in rc_source_files which have already their owner populated.
    rc_source_files_owner_index: usize = 0,

    // null means replace with the test executable binary
    test_exec_args: std.ArrayList(?[]const u8) = .empty,

    // These get set by CLI flags and then snapshotted when a `-M` flag is
    // encountered.
    mod_opts: Module.CreateOptions.Inherited = .{},

    // These get appended to by CLI flags and then slurped when a `-M` flag
    // is encountered.
    cssan: ClangSearchSanitizer = .{},
    cc_argv: std.ArrayList([]const u8) = .empty,
    deps: std.ArrayList(CliModule.Dep) = .empty,

    // Contains every module specified via -M. The dependencies are added
    // after argument parsing is completed. We use a StringArrayHashMap to make
    // error output consistent. "root" is special.
    create_module: CreateModule = .{
        // Populated just before the call to `createModule`.
        .dirs = undefined,
        .object_format = null,
        .modules = .empty,
        .opts = .{
            .is_test = undefined,
            // Populated while parsing CLI args.
            .output_mode = undefined,
            // Populated in the call to `createModule` for the root module.
            .resolved_target = undefined,
            .have_zcu = false,
            // Populated just before the call to `createModule`.
            .emit_llvm_ir = undefined,
            // Populated just before the call to `createModule`.
            .emit_llvm_bc = undefined,
            // Populated just before the call to `createModule`.
            .emit_bin = undefined,
            // Populated just before the call to `createModule`.
            .any_c_source_files = undefined,
        },
        // Populated in the call to `createModule` for the root module.
        .resolved_options = undefined,

        .cli_link_inputs = .empty,
        .windows_libs = .empty,
        .link_inputs = .empty,

        .c_source_files = .empty,
        .rc_source_files = .empty,

        .llvm_m_args = .empty,
        .sysroot = null,
        .lib_directories = .empty, // populated by createModule()
        .lib_dir_args = .empty, // populated from CLI arg parsing
        .libc_installation = null,
        .want_native_include_dirs = false,
        .frameworks = .empty,
        .framework_dirs = .empty,
        .rpath_list = .empty,
        .each_lib_rpath = null,
        .libc_paths_file = undefined,
        .native_system_include_paths = &.{},
    },

    // before arg parsing, check for the NO_COLOR and CLICOLOR_FORCE environment variables
    // if set, default the color setting to .off or .on, respectively
    // explicit --color arguments will still override this setting.
    // Disable color on WASI per https://github.com/WebAssembly/WASI/issues/162
    color: Color = .auto,
    n_jobs: ?u32 = null,

    cache_mode: Compilation.CacheMode = .incremental,
    root_name: []const u8 = undefined,

    io_impl: IoImpl = undefined,
    io: std.Io = undefined,

    file_system_inputs: std.ArrayList(u8) = .empty,

    pub fn deinit(self: *CompilationState, gpa: std.mem.Allocator) void {
        self.dirs.deinit(self.io);
        self.file_system_inputs.deinit(gpa);
        self.create_module.link_inputs.deinit(gpa);
        self.io_impl.deinit();
    }
};

const lsp_server = @import("lsp-server");

pub fn buildOutputType(
    gpa: Allocator,
    arena: Allocator,
    io: Io,
    all_args: []const []const u8,
    arg_mode: ArgMode,
    environ_map: *process.Environ.Map,
    cs: *CompilationState,
    ds: ?*lsp_server.DocumentStore,
    lsp_compilation_build: ?*lsp_server.BldDoc.Build,
) !void {
    cs.provided_name = null;
    cs.root_src_file = null;
    cs.version = .{ .major = 0, .minor = 0, .patch = 0 };
    cs.have_version = false;
    cs.compatibility_version = null;
    cs.function_sections = false;
    cs.data_sections = false;
    cs.listen = .none;
    cs.debug_compile_errors = false;
    cs.debug_incremental = false;
    cs.verbose_link = (native_os != .wasi or builtin.link_libc) and
        EnvVar.ZIG_VERBOSE_LINK.isSet(environ_map);
    cs.verbose_cc = (native_os != .wasi or builtin.link_libc) and
        EnvVar.ZIG_VERBOSE_CC.isSet(environ_map);
    cs.verbose_air = false;
    cs.verbose_intern_pool = false;
    cs.verbose_generic_instances = false;
    cs.verbose_llvm_ir = null;
    cs.verbose_llvm_bc = null;
    cs.link_depfile = null;
    cs.verbose_llvm_cpu_features = false;
    cs.time_report = false;
    cs.stack_report = false;
    cs.show_builtin = false;
    cs.emit_bin = .yes_default_path;
    cs.emit_asm = .no;
    cs.emit_llvm_ir = .no;
    cs.emit_llvm_bc = .no;
    cs.emit_docs = .no;
    cs.emit_implib = .yes_default_path;
    cs.emit_implib_arg_provided = false;
    cs.target_arch_os_abi = null;
    cs.target_mcpu = null;
    cs.dynamic_linker = null;
    cs.emit_h = .no;
    cs.soname = undefined;
    cs.want_compiler_rt = null;
    cs.want_ubsan_rt = null;
    cs.linker_script = null;
    cs.version_script = null;
    cs.linker_repro = null;
    cs.linker_allow_undefined_version = false;
    cs.linker_enable_new_dtags = null;
    cs.disable_c_depfile = false;
    cs.linker_sort_section = null;
    cs.linker_gc_sections = null;
    cs.linker_compress_debug_sections = null;
    cs.linker_allow_shlib_undefined = null;
    cs.allow_so_scripts = false;
    cs.linker_bind_global_refs_locally = null;
    cs.linker_import_symbols = false;
    cs.linker_import_table = false;
    cs.linker_export_table = false;
    cs.linker_growable_table = false;
    cs.linker_initial_memory = null;
    cs.linker_max_memory = null;
    cs.linker_global_base = null;
    cs.linker_print_gc_sections = false;
    cs.linker_print_icf_sections = false;
    cs.linker_print_map = false;
    cs.linker_nmagic = false;
    cs.linker_fatal_warnings = false;
    cs.llvm_opt_bisect_limit = -1;
    cs.linker_z_nocopyreloc = false;
    cs.linker_z_nodelete = false;
    cs.linker_z_notext = false;
    cs.linker_z_defs = false;
    cs.linker_z_origin = false;
    cs.linker_z_now = true;
    cs.linker_z_relro = true;
    cs.linker_z_common_page_size = null;
    cs.linker_z_max_page_size = null;
    cs.linker_tsaware = false;
    cs.linker_nxcompat = false;
    cs.linker_dynamicbase = true;
    cs.linker_optimization = null;
    cs.linker_module_definition_file = null;
    cs.test_no_exec = false;
    cs.test_execve = false;
    cs.entry = .default;
    cs.force_undefined_symbols = .empty;
    cs.stack_size = null;
    cs.image_base = null;
    cs.link_eh_frame_hdr = false;
    cs.link_emit_relocs = false;
    cs.build_id = null;
    cs.runtime_args_start = null;
    cs.test_filters = .empty;
    cs.test_runner_path = null;
    cs.override_local_cache_dir = EnvVar.ZIG_LOCAL_CACHE_DIR.get(environ_map);
    cs.override_global_cache_dir = EnvVar.ZIG_GLOBAL_CACHE_DIR.get(environ_map);
    cs.override_lib_dir = EnvVar.ZIG_LIB_DIR.get(environ_map);
    cs.clang_preprocessor_mode = .no;
    cs.subsystem = null;
    cs.major_subsystem_version = null;
    cs.minor_subsystem_version = null;
    cs.mingw_unicode_entry_point = false;
    cs.enable_link_snapshots = false;
    cs.debug_compiler_runtime_libs = null;
    cs.install_name = null;
    cs.hash_style = .both;
    cs.entitlements = null;
    cs.pagezero_size = null;
    cs.lib_search_strategy = .paths_first;
    cs.lib_preferred_mode = .dynamic;
    cs.headerpad_size = null;
    cs.headerpad_max_install_names = false;
    cs.dead_strip_dylibs = false;
    cs.force_load_objc = false;
    cs.discard_local_symbols = false;
    cs.contains_res_file = false;
    cs.reference_trace = null;
    cs.pdb_out_path = null;
    cs.error_limit = null;
    // These are before resolving sysroot.
    cs.extra_cflags = .empty;
    cs.extra_rcflags = .empty;
    cs.symbol_wrap_set = .empty;
    cs.rc_includes = .any;
    cs.manifest_file = null;
    cs.linker_export_symbol_names = .empty;

    // Tracks the position in c_source_files which have already their owner populated.
    cs.c_source_files_owner_index = 0;
    // Tracks the position in rc_source_files which have already their owner populated.
    cs.rc_source_files_owner_index = 0;

    // null means replace with the test executable binary
    cs.test_exec_args = .empty;

    // These get set by CLI flags and then snapshotted when a `-M` flag is
    // encountered.
    cs.mod_opts = .{};

    // These get appended to by CLI flags and then slurped when a `-M` flag
    // is encountered.
    cs.cssan = .{};
    cs.cc_argv = .empty;
    cs.deps = .empty;

    // We need to raise the FD limit *before* CLI parsing, because we open link inputs during CLI
    // parsing (in `createModule`), so a large number of link inputs could push us past the limit on
    // targets with a low soft limit (e.g. macOS has a default limit of 256).
    process.raiseFileDescriptorLimit();

    // Contains every module specified via -M. The dependencies are added
    // after argument parsing is completed. We use a StringArrayHashMap to make
    // error output consistent. "root" is special.
    cs.create_module = .{
        // Populated just before the call to `createModule`.
        .dirs = undefined,
        .object_format = null,
        .modules = .empty,
        .opts = .{
            .is_test = switch (arg_mode) {
                .zig_test, .zig_test_obj => true,
                .build, .cc, .cpp, .translate_c, .run => false,
            },
            // Populated while parsing CLI args.
            .output_mode = undefined,
            // Populated in the call to `createModule` for the root module.
            .resolved_target = undefined,
            .have_zcu = false,
            // Populated just before the call to `createModule`.
            .emit_llvm_ir = undefined,
            // Populated just before the call to `createModule`.
            .emit_llvm_bc = undefined,
            // Populated just before the call to `createModule`.
            .emit_bin = undefined,
            // Populated just before the call to `createModule`.
            .any_c_source_files = undefined,
        },
        // Populated in the call to `createModule` for the root module.
        .resolved_options = undefined,

        .cli_link_inputs = .empty,
        .windows_libs = .empty,
        .link_inputs = .empty,

        .c_source_files = .empty,
        .rc_source_files = .empty,

        .llvm_m_args = .empty,
        .sysroot = null,
        .lib_directories = .empty, // populated by createModule()
        .lib_dir_args = .empty, // populated from CLI arg parsing
        .libc_installation = null,
        .want_native_include_dirs = false,
        .frameworks = .empty,
        .framework_dirs = .empty,
        .rpath_list = .empty,
        .each_lib_rpath = null,
        .libc_paths_file = EnvVar.ZIG_LIBC.get(environ_map),
        .native_system_include_paths = &.{},
    };

    cs.color = Color.settingFromEnvironment(environ_map);
    cs.n_jobs = null;

    switch (arg_mode) {
        .build, .translate_c, .zig_test, .zig_test_obj, .run => {
            switch (arg_mode) {
                .build => |m| {
                    cs.create_module.opts.output_mode = m;
                },
                .translate_c => {
                    cs.emit_bin = .no;
                    cs.create_module.opts.output_mode = .Obj;
                },
                .zig_test, .run => {
                    cs.create_module.opts.output_mode = .Exe;
                },
                .zig_test_obj => {
                    cs.create_module.opts.output_mode = .Obj;
                },
                else => unreachable,
            }

            cs.soname = .yes_default_value;

            var args_iter = ArgsIterator{
                .args = all_args[2..],
            };

            var file_ext: ?Compilation.FileExt = null;
            args_loop: while (args_iter.next()) |arg| {
                if (mem.cutPrefix(u8, arg, "@")) |resp_file_path| {
                    // This is a "compiler response file". We must parse the file and treat its
                    // contents as command line parameters.
                    args_iter.resp_file = initArgIteratorResponseFile(arena, io, resp_file_path) catch |err|
                        fatal("unable to read response file {q}: {t}", .{ resp_file_path, err });
                } else if (mem.startsWith(u8, arg, "-")) {
                    if (mem.eql(u8, arg, "-h") or mem.eql(u8, arg, "--help")) {
                        try Io.File.stdout().writeStreamingAll(io, usage_build_generic);
                        return cleanExit(io);
                    } else if (mem.eql(u8, arg, "--")) {
                        if (arg_mode == .run) {
                            // args_iter.i is 1, referring the next arg after "--" in ["--", ...]
                            // Add +2 to the index so it is relative to all_args
                            cs.runtime_args_start = args_iter.i + 2;
                            break :args_loop;
                        } else {
                            fatal("unexpected end-of-parameter mark: --", .{});
                        }
                    } else if (mem.eql(u8, arg, "--dep")) {
                        const next_arg = args_iter.nextOrFatal();
                        const key, const value = mem.cutScalar(u8, next_arg, '=') orelse .{ next_arg, next_arg };
                        if (mem.eql(u8, key, "std") and !mem.eql(u8, value, "std")) {
                            fatal("unable to import as {q}: conflicts with builtin module", .{key});
                        }
                        for ([_][]const u8{ "root", "builtin" }) |name| {
                            if (mem.eql(u8, key, name)) {
                                fatal("unable to import as {q}: conflicts with builtin module", .{key});
                            }
                        }
                        try cs.deps.append(arena, .{
                            .key = key,
                            .value = value,
                        });
                    } else if (mem.cutPrefix(u8, arg, "-M")) |rest| {
                        const mod_name, const root_src_orig = mem.cutScalar(u8, rest, '=') orelse .{ rest, null };
                        try handleModArg(
                            arena,
                            mod_name,
                            root_src_orig,
                            &cs.create_module,
                            &cs.mod_opts,
                            &cs.cc_argv,
                            &cs.target_arch_os_abi,
                            &cs.target_mcpu,
                            &cs.dynamic_linker,
                            &cs.deps,
                            &cs.c_source_files_owner_index,
                            &cs.rc_source_files_owner_index,
                            &cs.cssan,
                        );
                    } else if (mem.eql(u8, arg, "--error-limit")) {
                        const next_arg = args_iter.nextOrFatal();
                        cs.error_limit = std.fmt.parseUnsigned(Zcu.ErrorInt, next_arg, 0) catch |err| {
                            fatal("unable to parse error limit {q}: {t}", .{ next_arg, err });
                        };
                    } else if (mem.eql(u8, arg, "-cflags")) {
                        cs.extra_cflags.shrinkRetainingCapacity(0);
                        while (true) {
                            const next_arg = args_iter.next() orelse {
                                fatal("expected -- after -cflags", .{});
                            };
                            if (mem.eql(u8, next_arg, "--")) break;
                            try cs.extra_cflags.append(arena, next_arg);
                        }
                    } else if (mem.eql(u8, arg, "-rcincludes")) {
                        cs.rc_includes = parseRcIncludes(args_iter.nextOrFatal());
                    } else if (mem.cutPrefix(u8, arg, "-rcincludes=")) |rest| {
                        cs.rc_includes = parseRcIncludes(rest);
                    } else if (mem.eql(u8, arg, "-rcflags")) {
                        cs.extra_rcflags.shrinkRetainingCapacity(0);
                        while (true) {
                            const next_arg = args_iter.next() orelse {
                                fatal("expected -- after -rcflags", .{});
                            };
                            if (mem.eql(u8, next_arg, "--")) break;
                            try cs.extra_rcflags.append(arena, next_arg);
                        }
                    } else if (mem.eql(u8, arg, "--color")) {
                        const next_arg = args_iter.next() orelse {
                            fatal("expected [auto|on|off] after --color", .{});
                        };
                        cs.color = stringToEnum(Color, next_arg) orelse {
                            fatal("expected [auto|on|off] after --color, found {q}", .{next_arg});
                        };
                    } else if (mem.cutPrefix(u8, arg, "-j")) |str| {
                        const num = std.fmt.parseUnsigned(u32, str, 10) catch |err| {
                            fatal("unable to parse jobs count {q}: {t}", .{ str, err });
                        };
                        if (num < 1) {
                            fatal("number of jobs must be at least 1", .{});
                        }
                        cs.n_jobs = num;
                    } else if (mem.eql(u8, arg, "--subsystem")) {
                        cs.subsystem = try parseSubsystem(args_iter.nextOrFatal());
                    } else if (mem.eql(u8, arg, "-O")) {
                        cs.mod_opts.optimize_mode = parseOptimizeMode(args_iter.nextOrFatal());
                    } else if (mem.cutPrefix(u8, arg, "-fentry=")) |rest| {
                        cs.entry = .{ .named = rest };
                    } else if (mem.eql(u8, arg, "--force_undefined")) {
                        try cs.force_undefined_symbols.put(arena, args_iter.nextOrFatal(), {});
                    } else if (mem.eql(u8, arg, "--discard-all")) {
                        cs.discard_local_symbols = true;
                    } else if (mem.eql(u8, arg, "--stack")) {
                        cs.stack_size = parseStackSize(args_iter.nextOrFatal());
                    } else if (mem.eql(u8, arg, "--image-base")) {
                        cs.image_base = parseImageBase(args_iter.nextOrFatal());
                    } else if (mem.eql(u8, arg, "--name")) {
                        cs.provided_name = args_iter.nextOrFatal();
                        if (!mem.eql(u8, cs.provided_name.?, fs.path.basename(cs.provided_name.?)))
                            fatal("invalid package name {q}: cannot contain folder separators", .{cs.provided_name.?});
                    } else if (mem.eql(u8, arg, "-rpath")) {
                        try cs.create_module.rpath_list.append(arena, args_iter.nextOrFatal());
                    } else if (mem.eql(u8, arg, "--library-directory") or mem.eql(u8, arg, "-L")) {
                        try cs.create_module.lib_dir_args.append(arena, args_iter.nextOrFatal());
                    } else if (mem.eql(u8, arg, "-F")) {
                        try cs.create_module.framework_dirs.append(arena, args_iter.nextOrFatal());
                    } else if (mem.eql(u8, arg, "-framework")) {
                        try cs.create_module.frameworks.put(arena, args_iter.nextOrFatal(), .{});
                    } else if (mem.eql(u8, arg, "-weak_framework")) {
                        try cs.create_module.frameworks.put(arena, args_iter.nextOrFatal(), .{ .weak = true });
                    } else if (mem.eql(u8, arg, "-needed_framework")) {
                        try cs.create_module.frameworks.put(arena, args_iter.nextOrFatal(), .{ .needed = true });
                    } else if (mem.eql(u8, arg, "-install_name")) {
                        cs.install_name = args_iter.nextOrFatal();
                    } else if (mem.cutPrefix(u8, arg, "--compress-debug-sections=")) |param| {
                        cs.linker_compress_debug_sections = stringToEnum(std.zig.CompressDebugSections, param) orelse {
                            fatal("expected --compress-debug-sections=[none|zlib|zstd], found: {s}", .{param});
                        };
                    } else if (mem.eql(u8, arg, "--compress-debug-sections")) {
                        cs.linker_compress_debug_sections = .zlib;
                    } else if (mem.eql(u8, arg, "-pagezero_size")) {
                        const next_arg = args_iter.nextOrFatal();
                        cs.pagezero_size = std.fmt.parseUnsigned(u64, eatIntPrefix(next_arg, 16), 16) catch |err| {
                            fatal("unable to parse pagezero size {q}: {t}", .{ next_arg, err });
                        };
                    } else if (mem.eql(u8, arg, "-search_paths_first")) {
                        cs.lib_search_strategy = .paths_first;
                        cs.lib_preferred_mode = .dynamic;
                    } else if (mem.eql(u8, arg, "-search_paths_first_static")) {
                        cs.lib_search_strategy = .paths_first;
                        cs.lib_preferred_mode = .static;
                    } else if (mem.eql(u8, arg, "-search_dylibs_first")) {
                        cs.lib_search_strategy = .mode_first;
                        cs.lib_preferred_mode = .dynamic;
                    } else if (mem.eql(u8, arg, "-search_static_first")) {
                        cs.lib_search_strategy = .mode_first;
                        cs.lib_preferred_mode = .static;
                    } else if (mem.eql(u8, arg, "-search_dylibs_only")) {
                        cs.lib_search_strategy = .no_fallback;
                        cs.lib_preferred_mode = .dynamic;
                    } else if (mem.eql(u8, arg, "-search_static_only")) {
                        cs.lib_search_strategy = .no_fallback;
                        cs.lib_preferred_mode = .static;
                    } else if (mem.eql(u8, arg, "-headerpad")) {
                        const next_arg = args_iter.nextOrFatal();
                        cs.headerpad_size = std.fmt.parseUnsigned(u32, eatIntPrefix(next_arg, 16), 16) catch |err| {
                            fatal("unable to parse headerpad size {q}: {t}", .{ next_arg, err });
                        };
                    } else if (mem.eql(u8, arg, "-headerpad_max_install_names")) {
                        cs.headerpad_max_install_names = true;
                    } else if (mem.eql(u8, arg, "-dead_strip")) {
                        cs.linker_gc_sections = true;
                    } else if (mem.eql(u8, arg, "-dead_strip_dylibs")) {
                        cs.dead_strip_dylibs = true;
                    } else if (mem.eql(u8, arg, "-ObjC")) {
                        cs.force_load_objc = true;
                    } else if (mem.eql(u8, arg, "-T") or mem.eql(u8, arg, "--script")) {
                        cs.linker_script = args_iter.nextOrFatal();
                    } else if (mem.eql(u8, arg, "-version-script") or mem.eql(u8, arg, "--version-script")) {
                        cs.version_script = args_iter.nextOrFatal();
                    } else if (mem.eql(u8, arg, "--undefined-version")) {
                        cs.linker_allow_undefined_version = true;
                    } else if (mem.eql(u8, arg, "--no-undefined-version")) {
                        cs.linker_allow_undefined_version = false;
                    } else if (mem.eql(u8, arg, "--enable-new-dtags")) {
                        cs.linker_enable_new_dtags = true;
                    } else if (mem.eql(u8, arg, "--disable-new-dtags")) {
                        cs.linker_enable_new_dtags = false;
                    } else if (mem.eql(u8, arg, "--library") or mem.eql(u8, arg, "-l")) {
                        // We don't know whether this library is part of libc
                        // or libc++ until we resolve the target, so we append
                        // to the list for now.
                        try cs.create_module.cli_link_inputs.append(arena, .{ .name_query = .{
                            .name = args_iter.nextOrFatal(),
                            .query = .{
                                .needed = false,
                                .weak = false,
                                .preferred_mode = cs.lib_preferred_mode,
                                .search_strategy = cs.lib_search_strategy,
                                .allow_so_scripts = cs.allow_so_scripts,
                            },
                        } });
                    } else if (mem.eql(u8, arg, "--needed-library") or
                        mem.eql(u8, arg, "-needed-l") or
                        mem.eql(u8, arg, "-needed_library"))
                    {
                        const next_arg = args_iter.nextOrFatal();
                        try cs.create_module.cli_link_inputs.append(arena, .{ .name_query = .{
                            .name = next_arg,
                            .query = .{
                                .needed = true,
                                .weak = false,
                                .preferred_mode = cs.lib_preferred_mode,
                                .search_strategy = cs.lib_search_strategy,
                                .allow_so_scripts = cs.allow_so_scripts,
                            },
                        } });
                    } else if (mem.eql(u8, arg, "-weak_library") or mem.eql(u8, arg, "-weak-l")) {
                        try cs.create_module.cli_link_inputs.append(arena, .{ .name_query = .{
                            .name = args_iter.nextOrFatal(),
                            .query = .{
                                .needed = false,
                                .weak = true,
                                .preferred_mode = cs.lib_preferred_mode,
                                .search_strategy = cs.lib_search_strategy,
                                .allow_so_scripts = cs.allow_so_scripts,
                            },
                        } });
                    } else if (mem.eql(u8, arg, "-D")) {
                        try cs.cc_argv.appendSlice(arena, &.{ arg, args_iter.nextOrFatal() });
                    } else if (mem.eql(u8, arg, "-I")) {
                        try cs.cssan.addIncludePath(arena, &cs.cc_argv, .I, arg, args_iter.nextOrFatal(), false);
                    } else if (mem.cutPrefix(u8, arg, "--embed-dir=")) |rest| {
                        try cs.cssan.addIncludePath(arena, &cs.cc_argv, .embed_dir, arg, rest, true);
                    } else if (mem.eql(u8, arg, "-isystem")) {
                        try cs.cssan.addIncludePath(arena, &cs.cc_argv, .isystem, arg, args_iter.nextOrFatal(), false);
                    } else if (mem.eql(u8, arg, "-iwithsysroot")) {
                        try cs.cssan.addIncludePath(arena, &cs.cc_argv, .iwithsysroot, arg, args_iter.nextOrFatal(), false);
                    } else if (mem.eql(u8, arg, "-idirafter")) {
                        try cs.cssan.addIncludePath(arena, &cs.cc_argv, .idirafter, arg, args_iter.nextOrFatal(), false);
                    } else if (mem.eql(u8, arg, "-iframework")) {
                        const path = args_iter.nextOrFatal();
                        try cs.cssan.addIncludePath(arena, &cs.cc_argv, .iframework, arg, path, false);
                        try cs.create_module.framework_dirs.append(arena, path); // Forward to the backend as -F
                    } else if (mem.eql(u8, arg, "-iframeworkwithsysroot")) {
                        const path = args_iter.nextOrFatal();
                        try cs.cssan.addIncludePath(arena, &cs.cc_argv, .iframeworkwithsysroot, arg, path, false);
                        try cs.create_module.framework_dirs.append(arena, path); // Forward to the backend as -F
                    } else if (mem.eql(u8, arg, "--version")) {
                        const next_arg = args_iter.nextOrFatal();
                        cs.version = std.SemanticVersion.parse(next_arg) catch |err| {
                            fatal("unable to parse --version {q}: {t}", .{ next_arg, err });
                        };
                        cs.have_version = true;
                    } else if (mem.eql(u8, arg, "-target")) {
                        cs.target_arch_os_abi = args_iter.nextOrFatal();
                    } else if (mem.eql(u8, arg, "-mcpu")) {
                        cs.target_mcpu = args_iter.nextOrFatal();
                    } else if (mem.eql(u8, arg, "-mcmodel")) {
                        cs.mod_opts.code_model = parseCodeModel(args_iter.nextOrFatal());
                    } else if (mem.cutPrefix(u8, arg, "-mcmodel=")) |rest| {
                        cs.mod_opts.code_model = parseCodeModel(rest);
                    } else if (mem.cutPrefix(u8, arg, "-ofmt=")) |rest| {
                        cs.create_module.object_format = rest;
                    } else if (mem.cutPrefix(u8, arg, "-mcpu=")) |rest| {
                        cs.target_mcpu = rest;
                    } else if (mem.cutPrefix(u8, arg, "-O")) |rest| {
                        cs.mod_opts.optimize_mode = parseOptimizeMode(rest);
                    } else if (mem.eql(u8, arg, "--dynamic-linker")) {
                        cs.dynamic_linker = args_iter.nextOrFatal();
                    } else if (mem.eql(u8, arg, "--no-dynamic-linker")) {
                        cs.dynamic_linker = "";
                    } else if (mem.eql(u8, arg, "--sysroot")) {
                        const next_arg = args_iter.nextOrFatal();
                        cs.create_module.sysroot = next_arg;
                        try cs.cc_argv.appendSlice(arena, &.{ "-isysroot", next_arg });
                    } else if (mem.eql(u8, arg, "--libc")) {
                        cs.create_module.libc_paths_file = args_iter.nextOrFatal();
                    } else if (mem.eql(u8, arg, "--test-filter")) {
                        try cs.test_filters.append(arena, args_iter.nextOrFatal());
                    } else if (mem.eql(u8, arg, "--test-runner")) {
                        cs.test_runner_path = args_iter.nextOrFatal();
                    } else if (mem.eql(u8, arg, "--test-cmd")) {
                        try cs.test_exec_args.append(arena, args_iter.nextOrFatal());
                    } else if (mem.eql(u8, arg, "--cache-dir")) {
                        cs.override_local_cache_dir = args_iter.nextOrFatal();
                    } else if (mem.eql(u8, arg, "--global-cache-dir")) {
                        cs.override_global_cache_dir = args_iter.nextOrFatal();
                    } else if (mem.eql(u8, arg, "--zig-lib-dir")) {
                        cs.override_lib_dir = args_iter.nextOrFatal();
                    } else if (mem.eql(u8, arg, "--debug-log")) {
                        try addDebugLog(arena, args_iter.nextOrFatal());
                    } else if (mem.eql(u8, arg, "--listen")) {
                        const next_arg = args_iter.nextOrFatal();
                        if (mem.eql(u8, next_arg, "-")) {
                            dev.check(.stdio_listen);
                            cs.listen = .stdio;
                        } else {
                            dev.check(.network_listen);
                            // example: --listen 127.0.0.1:9000
                            const host, const port_text = mem.cutScalar(u8, next_arg, ':') orelse .{ next_arg, "14735" };
                            const port = std.fmt.parseInt(u16, port_text, 10) catch |err|
                                fatal("invalid port number: {q}: {t}", .{ port_text, err });
                            cs.listen = .{ .ip4 = Io.net.Ip4Address.parse(host, port) catch |err|
                                fatal("invalid host: {q}: {t}", .{ host, err }) };
                        }
                    } else if (mem.eql(u8, arg, "--listen=-")) {
                        dev.check(.stdio_listen);
                        cs.listen = .stdio;
                    } else if (mem.eql(u8, arg, "--debug-link-snapshot")) {
                        if (!build_options.enable_debug_extensions) {
                            warn("Zig was compiled without debug extensions. --debug-link-snapshot has no effect.", .{});
                        } else {
                            cs.enable_link_snapshots = true;
                        }
                    } else if (mem.eql(u8, arg, "--debug-rt")) {
                        cs.debug_compiler_runtime_libs = .debug;
                    } else if (mem.cutPrefix(u8, arg, "--debug-rt=")) |rest| {
                        cs.debug_compiler_runtime_libs = parseOptimizeMode(rest);
                    } else if (mem.eql(u8, arg, "--debug-incremental")) {
                        if (build_options.enable_debug_extensions) {
                            cs.debug_incremental = true;
                        } else {
                            warn("Zig was compiled without debug extensions. --debug-incremental has no effect.", .{});
                        }
                    } else if (mem.eql(u8, arg, "-fincremental")) {
                        dev.check(.incremental);
                        cs.create_module.opts.incremental = true;
                    } else if (mem.eql(u8, arg, "-fno-incremental")) {
                        cs.create_module.opts.incremental = false;
                    } else if (mem.eql(u8, arg, "--entitlements")) {
                        cs.entitlements = args_iter.nextOrFatal();
                    } else if (mem.eql(u8, arg, "-fcompiler-rt")) {
                        cs.want_compiler_rt = true;
                    } else if (mem.eql(u8, arg, "-fno-compiler-rt")) {
                        cs.want_compiler_rt = false;
                    } else if (mem.eql(u8, arg, "-fubsan-rt")) {
                        cs.want_ubsan_rt = true;
                    } else if (mem.eql(u8, arg, "-fno-ubsan-rt")) {
                        cs.want_ubsan_rt = false;
                    } else if (mem.eql(u8, arg, "-feach-lib-rpath")) {
                        cs.create_module.each_lib_rpath = true;
                    } else if (mem.eql(u8, arg, "-fno-each-lib-rpath")) {
                        cs.create_module.each_lib_rpath = false;
                    } else if (mem.eql(u8, arg, "--test-cmd-bin")) {
                        try cs.test_exec_args.append(arena, null);
                    } else if (mem.eql(u8, arg, "--test-no-exec")) {
                        cs.test_no_exec = true;
                    } else if (mem.eql(u8, arg, "--time-report")) {
                        cs.time_report = true;
                    } else if (mem.eql(u8, arg, "--test-execve")) {
                        cs.test_execve = true;
                    } else if (mem.eql(u8, arg, "-fstack-report")) {
                        cs.stack_report = true;
                    } else if (mem.eql(u8, arg, "-fPIC")) {
                        cs.mod_opts.pic = true;
                    } else if (mem.eql(u8, arg, "-fno-PIC")) {
                        cs.mod_opts.pic = false;
                    } else if (mem.eql(u8, arg, "-fPIE")) {
                        cs.create_module.opts.pie = true;
                    } else if (mem.eql(u8, arg, "-fno-PIE")) {
                        cs.create_module.opts.pie = false;
                    } else if (mem.eql(u8, arg, "-flto")) {
                        cs.create_module.opts.lto = .full;
                    } else if (mem.cutPrefix(u8, arg, "-flto=")) |mode| {
                        if (mem.eql(u8, mode, "full")) {
                            cs.create_module.opts.lto = .full;
                        } else if (mem.eql(u8, mode, "thin")) {
                            cs.create_module.opts.lto = .thin;
                        } else {
                            fatal("invalid -flto mode: {q}; must be \"full\" or \"thin\"", .{mode});
                        }
                    } else if (mem.eql(u8, arg, "-fno-lto")) {
                        cs.create_module.opts.lto = .none;
                    } else if (mem.eql(u8, arg, "-funwind-tables")) {
                        cs.mod_opts.unwind_tables = .sync;
                    } else if (mem.eql(u8, arg, "-fasync-unwind-tables")) {
                        cs.mod_opts.unwind_tables = .async;
                    } else if (mem.eql(u8, arg, "-fno-unwind-tables")) {
                        cs.mod_opts.unwind_tables = .none;
                    } else if (mem.eql(u8, arg, "-fstack-check")) {
                        cs.mod_opts.stack_check = true;
                    } else if (mem.eql(u8, arg, "-fno-stack-check")) {
                        cs.mod_opts.stack_check = false;
                    } else if (mem.eql(u8, arg, "-fstack-protector")) {
                        cs.mod_opts.stack_protector = Compilation.default_stack_protector_buffer_size;
                    } else if (mem.eql(u8, arg, "-fno-stack-protector")) {
                        cs.mod_opts.stack_protector = 0;
                    } else if (mem.eql(u8, arg, "-mred-zone")) {
                        cs.mod_opts.red_zone = true;
                    } else if (mem.eql(u8, arg, "-mno-red-zone")) {
                        cs.mod_opts.red_zone = false;
                    } else if (mem.eql(u8, arg, "-fomit-frame-pointer")) {
                        cs.mod_opts.omit_frame_pointer = true;
                    } else if (mem.eql(u8, arg, "-fno-omit-frame-pointer")) {
                        cs.mod_opts.omit_frame_pointer = false;
                    } else if (mem.eql(u8, arg, "-fsanitize-c")) {
                        cs.mod_opts.sanitize_c = .full;
                    } else if (mem.cutPrefix(u8, arg, "-fsanitize-c=")) |mode| {
                        if (mem.eql(u8, mode, "trap")) {
                            cs.mod_opts.sanitize_c = .trap;
                        } else if (mem.eql(u8, mode, "full")) {
                            cs.mod_opts.sanitize_c = .full;
                        } else {
                            fatal("invalid -fsanitize-c mode: {q}; must be \"trap\" or \"full\"", .{mode});
                        }
                    } else if (mem.eql(u8, arg, "-fno-sanitize-c")) {
                        cs.mod_opts.sanitize_c = .off;
                    } else if (mem.eql(u8, arg, "-fvalgrind")) {
                        cs.mod_opts.valgrind = true;
                    } else if (mem.eql(u8, arg, "-fno-valgrind")) {
                        cs.mod_opts.valgrind = false;
                    } else if (mem.eql(u8, arg, "-fsanitize-thread")) {
                        cs.mod_opts.sanitize_thread = true;
                    } else if (mem.eql(u8, arg, "-fno-sanitize-thread")) {
                        cs.mod_opts.sanitize_thread = false;
                    } else if (mem.eql(u8, arg, "-ffuzz")) {
                        cs.mod_opts.fuzz = true;
                    } else if (mem.eql(u8, arg, "-fno-fuzz")) {
                        cs.mod_opts.fuzz = false;
                    } else if (mem.eql(u8, arg, "-fllvm")) {
                        cs.create_module.opts.use_llvm = true;
                    } else if (mem.eql(u8, arg, "-fno-llvm")) {
                        cs.create_module.opts.use_llvm = false;
                    } else if (mem.eql(u8, arg, "-flibllvm")) {
                        cs.create_module.opts.use_lib_llvm = true;
                    } else if (mem.eql(u8, arg, "-fno-libllvm")) {
                        cs.create_module.opts.use_lib_llvm = false;
                    } else if (mem.eql(u8, arg, "-flld")) {
                        cs.create_module.opts.use_lld = true;
                    } else if (mem.eql(u8, arg, "-fno-lld")) {
                        cs.create_module.opts.use_lld = false;
                    } else if (mem.eql(u8, arg, "-fnew-linker")) {
                        cs.create_module.opts.use_new_linker = true;
                    } else if (mem.eql(u8, arg, "-fno-new-linker")) {
                        cs.create_module.opts.use_new_linker = false;
                    } else if (mem.eql(u8, arg, "-fclang")) {
                        cs.create_module.opts.use_clang = true;
                    } else if (mem.eql(u8, arg, "-fno-clang")) {
                        cs.create_module.opts.use_clang = false;
                    } else if (mem.eql(u8, arg, "-fsanitize-coverage-trace-pc-guard")) {
                        cs.create_module.opts.san_cov_trace_pc_guard = true;
                    } else if (mem.eql(u8, arg, "-fno-sanitize-coverage-trace-pc-guard")) {
                        cs.create_module.opts.san_cov_trace_pc_guard = false;
                    } else if (mem.eql(u8, arg, "-freference-trace")) {
                        cs.reference_trace = 256;
                    } else if (mem.cutPrefix(u8, arg, "-freference-trace=")) |num| {
                        cs.reference_trace = std.fmt.parseUnsigned(u32, num, 10) catch |err| {
                            fatal("unable to parse reference_trace count {q}: {t}", .{ num, err });
                        };
                    } else if (mem.eql(u8, arg, "-fno-reference-trace")) {
                        cs.reference_trace = null;
                    } else if (mem.eql(u8, arg, "-ferror-tracing")) {
                        cs.mod_opts.error_tracing = true;
                    } else if (mem.eql(u8, arg, "-fno-error-tracing")) {
                        cs.mod_opts.error_tracing = false;
                    } else if (mem.eql(u8, arg, "-rdynamic")) {
                        cs.create_module.opts.rdynamic = true;
                    } else if (mem.eql(u8, arg, "-fsoname")) {
                        cs.soname = .yes_default_value;
                    } else if (mem.cutPrefix(u8, arg, "-fsoname=")) |rest| {
                        cs.soname = .{ .yes = rest };
                    } else if (mem.eql(u8, arg, "-fno-soname")) {
                        cs.soname = .no;
                    } else if (mem.eql(u8, arg, "-femit-bin")) {
                        cs.emit_bin = .yes_default_path;
                    } else if (mem.cutPrefix(u8, arg, "-femit-bin=")) |rest| {
                        cs.emit_bin = .{ .yes = rest };
                    } else if (mem.eql(u8, arg, "-fno-emit-bin")) {
                        cs.emit_bin = .no;
                    } else if (mem.eql(u8, arg, "-femit-h")) {
                        fatal("-femit-h is currently broken, see https://github.com/ziglang/zig/issues/9698", .{});
                        cs.emit_h = .yes_default_path;
                    } else if (mem.cutPrefix(u8, arg, "-femit-h=")) |rest| {
                        cs.emit_h = .{ .yes = rest };
                    } else if (mem.eql(u8, arg, "-fno-emit-h")) {
                        cs.emit_h = .no;
                    } else if (mem.eql(u8, arg, "-femit-asm")) {
                        cs.emit_asm = .yes_default_path;
                    } else if (mem.cutPrefix(u8, arg, "-femit-asm=")) |rest| {
                        cs.emit_asm = .{ .yes = rest };
                    } else if (mem.eql(u8, arg, "-fno-emit-asm")) {
                        cs.emit_asm = .no;
                    } else if (mem.eql(u8, arg, "-femit-llvm-ir")) {
                        cs.emit_llvm_ir = .yes_default_path;
                    } else if (mem.cutPrefix(u8, arg, "-femit-llvm-ir=")) |rest| {
                        cs.emit_llvm_ir = .{ .yes = rest };
                    } else if (mem.eql(u8, arg, "-fno-emit-llvm-ir")) {
                        cs.emit_llvm_ir = .no;
                    } else if (mem.eql(u8, arg, "-femit-llvm-bc")) {
                        cs.emit_llvm_bc = .yes_default_path;
                    } else if (mem.cutPrefix(u8, arg, "-femit-llvm-bc=")) |rest| {
                        cs.emit_llvm_bc = .{ .yes = rest };
                    } else if (mem.eql(u8, arg, "-fno-emit-llvm-bc")) {
                        cs.emit_llvm_bc = .no;
                    } else if (mem.eql(u8, arg, "-femit-docs")) {
                        cs.emit_docs = .yes_default_path;
                    } else if (mem.cutPrefix(u8, arg, "-femit-docs=")) |rest| {
                        cs.emit_docs = .{ .yes = rest };
                    } else if (mem.eql(u8, arg, "-fno-emit-docs")) {
                        cs.emit_docs = .no;
                    } else if (mem.eql(u8, arg, "-femit-implib")) {
                        cs.emit_implib = .yes_default_path;
                        cs.emit_implib_arg_provided = true;
                    } else if (mem.cutPrefix(u8, arg, "-femit-implib=")) |rest| {
                        cs.emit_implib = .{ .yes = rest };
                        cs.emit_implib_arg_provided = true;
                    } else if (mem.eql(u8, arg, "-fno-emit-implib")) {
                        cs.emit_implib = .no;
                        cs.emit_implib_arg_provided = true;
                    } else if (mem.eql(u8, arg, "-dynamic")) {
                        cs.create_module.opts.link_mode = .dynamic;
                        cs.lib_preferred_mode = .dynamic;
                        cs.lib_search_strategy = .mode_first;
                    } else if (mem.eql(u8, arg, "-static")) {
                        cs.create_module.opts.link_mode = .static;
                        cs.lib_preferred_mode = .static;
                        cs.lib_search_strategy = .no_fallback;
                    } else if (mem.eql(u8, arg, "-fdll-export-fns")) {
                        cs.create_module.opts.dll_export_fns = true;
                    } else if (mem.eql(u8, arg, "-fno-dll-export-fns")) {
                        cs.create_module.opts.dll_export_fns = false;
                    } else if (mem.eql(u8, arg, "--show-builtin")) {
                        cs.show_builtin = true;
                        cs.emit_bin = .no;
                    } else if (mem.eql(u8, arg, "-fstrip")) {
                        cs.mod_opts.strip = true;
                    } else if (mem.eql(u8, arg, "-fno-strip")) {
                        cs.mod_opts.strip = false;
                    } else if (mem.eql(u8, arg, "-gdwarf32")) {
                        cs.create_module.opts.debug_format = .{ .dwarf = .@"32" };
                    } else if (mem.eql(u8, arg, "-gdwarf64")) {
                        cs.create_module.opts.debug_format = .{ .dwarf = .@"64" };
                    } else if (mem.eql(u8, arg, "-fsingle-threaded")) {
                        cs.mod_opts.single_threaded = true;
                    } else if (mem.eql(u8, arg, "-fno-single-threaded")) {
                        cs.mod_opts.single_threaded = false;
                    } else if (mem.eql(u8, arg, "-ffunction-sections")) {
                        cs.function_sections = true;
                    } else if (mem.eql(u8, arg, "-fno-function-sections")) {
                        cs.function_sections = false;
                    } else if (mem.eql(u8, arg, "-fdata-sections")) {
                        cs.data_sections = true;
                    } else if (mem.eql(u8, arg, "-fno-data-sections")) {
                        cs.data_sections = false;
                    } else if (mem.eql(u8, arg, "-fbuiltin")) {
                        cs.mod_opts.no_builtin = false;
                    } else if (mem.eql(u8, arg, "-fno-builtin")) {
                        cs.mod_opts.no_builtin = true;
                    } else if (mem.cutPrefix(u8, arg, "-fopt-bisect-limit=")) |next_arg| {
                        cs.llvm_opt_bisect_limit = std.fmt.parseInt(c_int, next_arg, 0) catch |err|
                            fatal("unable to parse {q}: {t}", .{ arg, err });
                    } else if (mem.eql(u8, arg, "--eh-frame-hdr")) {
                        cs.link_eh_frame_hdr = true;
                    } else if (mem.eql(u8, arg, "--no-eh-frame-hdr")) {
                        cs.link_eh_frame_hdr = false;
                    } else if (mem.eql(u8, arg, "--dynamicbase")) {
                        cs.linker_dynamicbase = true;
                    } else if (mem.eql(u8, arg, "--no-dynamicbase")) {
                        cs.linker_dynamicbase = false;
                    } else if (mem.eql(u8, arg, "--emit-relocs")) {
                        cs.link_emit_relocs = true;
                    } else if (mem.eql(u8, arg, "-fallow-shlib-undefined")) {
                        cs.linker_allow_shlib_undefined = true;
                    } else if (mem.eql(u8, arg, "-fno-allow-shlib-undefined")) {
                        cs.linker_allow_shlib_undefined = false;
                    } else if (mem.eql(u8, arg, "-fallow-so-scripts")) {
                        cs.allow_so_scripts = true;
                    } else if (mem.eql(u8, arg, "-fno-allow-so-scripts")) {
                        cs.allow_so_scripts = false;
                    } else if (mem.eql(u8, arg, "-z")) {
                        const z_arg = args_iter.nextOrFatal();
                        if (mem.eql(u8, z_arg, "nodelete")) {
                            cs.linker_z_nodelete = true;
                        } else if (mem.eql(u8, z_arg, "notext")) {
                            cs.linker_z_notext = true;
                        } else if (mem.eql(u8, z_arg, "defs")) {
                            cs.linker_z_defs = true;
                        } else if (mem.eql(u8, z_arg, "undefs")) {
                            cs.linker_z_defs = false;
                        } else if (mem.eql(u8, z_arg, "origin")) {
                            cs.linker_z_origin = true;
                        } else if (mem.eql(u8, z_arg, "nocopyreloc")) {
                            cs.linker_z_nocopyreloc = true;
                        } else if (mem.eql(u8, z_arg, "now")) {
                            cs.linker_z_now = true;
                        } else if (mem.eql(u8, z_arg, "lazy")) {
                            cs.linker_z_now = false;
                        } else if (mem.eql(u8, z_arg, "relro")) {
                            cs.linker_z_relro = true;
                        } else if (mem.eql(u8, z_arg, "norelro")) {
                            cs.linker_z_relro = false;
                        } else if (prefixedIntArg(z_arg, "common-page-size=")) |int| {
                            cs.linker_z_common_page_size = int;
                        } else if (prefixedIntArg(z_arg, "max-page-size=")) |int| {
                            cs.linker_z_max_page_size = int;
                        } else {
                            fatal("unsupported linker extension flag: -z {s}", .{z_arg});
                        }
                    } else if (mem.eql(u8, arg, "--import-memory")) {
                        cs.create_module.opts.import_memory = true;
                    } else if (mem.eql(u8, arg, "-fentry")) {
                        switch (cs.entry) {
                            .default, .disabled => cs.entry = .enabled,
                            .enabled, .named => {},
                        }
                    } else if (mem.eql(u8, arg, "-fno-entry")) {
                        cs.entry = .disabled;
                    } else if (mem.eql(u8, arg, "--export-memory")) {
                        cs.create_module.opts.export_memory = true;
                    } else if (mem.eql(u8, arg, "--import-symbols")) {
                        cs.linker_import_symbols = true;
                    } else if (mem.eql(u8, arg, "--import-table")) {
                        cs.linker_import_table = true;
                    } else if (mem.eql(u8, arg, "--export-table")) {
                        cs.linker_export_table = true;
                    } else if (mem.eql(u8, arg, "--growable-table")) {
                        cs.linker_growable_table = true;
                    } else if (prefixedIntArg(arg, "--initial-memory=")) |int| {
                        cs.linker_initial_memory = int;
                    } else if (prefixedIntArg(arg, "--max-memory=")) |int| {
                        cs.linker_max_memory = int;
                    } else if (mem.eql(u8, arg, "--shared-memory")) {
                        cs.create_module.opts.shared_memory = true;
                    } else if (prefixedIntArg(arg, "--global-base=")) |int| {
                        cs.linker_global_base = int;
                    } else if (mem.cutPrefix(u8, arg, "--export=")) |rest| {
                        try cs.linker_export_symbol_names.append(arena, rest);
                    } else if (mem.eql(u8, arg, "-Bsymbolic")) {
                        cs.linker_bind_global_refs_locally = true;
                    } else if (mem.eql(u8, arg, "--gc-sections")) {
                        cs.linker_gc_sections = true;
                    } else if (mem.eql(u8, arg, "--no-gc-sections")) {
                        cs.linker_gc_sections = false;
                    } else if (mem.eql(u8, arg, "--build-id")) {
                        cs.build_id = .fast;
                    } else if (mem.cutPrefix(u8, arg, "--build-id=")) |style| {
                        cs.build_id = std.zig.BuildId.parse(style) catch |err| {
                            fatal("unable to parse --build-id style {q}: {t}", .{ style, err });
                        };
                    } else if (mem.eql(u8, arg, "--debug-compile-errors")) {
                        if (build_options.enable_debug_extensions) {
                            cs.debug_compile_errors = true;
                        } else {
                            warn("Zig was compiled without debug extensions. --debug-compile-errors has no effect.", .{});
                        }
                    } else if (mem.eql(u8, arg, "--verbose-link")) {
                        cs.verbose_link = true;
                    } else if (mem.eql(u8, arg, "--verbose-cc")) {
                        cs.verbose_cc = true;
                    } else if (mem.eql(u8, arg, "--verbose-air")) {
                        cs.verbose_air = true;
                    } else if (mem.eql(u8, arg, "--verbose-intern-pool")) {
                        cs.verbose_intern_pool = true;
                    } else if (mem.eql(u8, arg, "--verbose-generic-instances")) {
                        cs.verbose_generic_instances = true;
                    } else if (mem.eql(u8, arg, "--verbose-llvm-ir")) {
                        cs.verbose_llvm_ir = "-";
                    } else if (mem.cutPrefix(u8, arg, "--verbose-llvm-ir=")) |rest| {
                        cs.verbose_llvm_ir = rest;
                    } else if (mem.cutPrefix(u8, arg, "--verbose-llvm-bc=")) |rest| {
                        cs.verbose_llvm_bc = rest;
                    } else if (mem.eql(u8, arg, "--verbose-llvm-cpu-features")) {
                        cs.verbose_llvm_cpu_features = true;
                    } else if (mem.cutPrefix(u8, arg, "-T")) |rest| {
                        cs.linker_script = rest;
                    } else if (mem.cutPrefix(u8, arg, "-L")) |rest| {
                        try cs.create_module.lib_dir_args.append(arena, rest);
                    } else if (mem.cutPrefix(u8, arg, "-F")) |rest| {
                        try cs.create_module.framework_dirs.append(arena, rest);
                    } else if (mem.cutPrefix(u8, arg, "-l")) |name| {
                        // We don't know whether this library is part of libc
                        // or libc++ until we resolve the target, so we append
                        // to the list for now.
                        try cs.create_module.cli_link_inputs.append(arena, .{ .name_query = .{
                            .name = name,
                            .query = .{
                                .needed = false,
                                .weak = false,
                                .preferred_mode = cs.lib_preferred_mode,
                                .search_strategy = cs.lib_search_strategy,
                                .allow_so_scripts = cs.allow_so_scripts,
                            },
                        } });
                    } else if (mem.cutPrefix(u8, arg, "-needed-l")) |name| {
                        try cs.create_module.cli_link_inputs.append(arena, .{ .name_query = .{
                            .name = name,
                            .query = .{
                                .needed = true,
                                .weak = false,
                                .preferred_mode = cs.lib_preferred_mode,
                                .search_strategy = cs.lib_search_strategy,
                                .allow_so_scripts = cs.allow_so_scripts,
                            },
                        } });
                    } else if (mem.cutPrefix(u8, arg, "-weak-l")) |name| {
                        try cs.create_module.cli_link_inputs.append(arena, .{ .name_query = .{
                            .name = name,
                            .query = .{
                                .needed = false,
                                .weak = true,
                                .preferred_mode = cs.lib_preferred_mode,
                                .search_strategy = cs.lib_search_strategy,
                                .allow_so_scripts = cs.allow_so_scripts,
                            },
                        } });
                    } else if (mem.startsWith(u8, arg, "-D")) {
                        try cs.cc_argv.append(arena, arg);
                    } else if (mem.cutPrefix(u8, arg, "-I")) |rest| {
                        try cs.cssan.addIncludePath(arena, &cs.cc_argv, .I, arg, rest, true);
                    } else if (mem.cutPrefix(u8, arg, "-x")) |rest| {
                        const lang = if (rest.len == 0) args_iter.nextOrFatal() else rest;
                        if (mem.eql(u8, lang, "none")) {
                            file_ext = null;
                        } else if (Compilation.FileExt.from_lang.get(lang)) |got_ext| {
                            file_ext = got_ext;
                        } else {
                            fatal("language not recognized: {s}", .{lang});
                        }
                    } else if (mem.cutPrefix(u8, arg, "-mexec-model=")) |rest| {
                        cs.create_module.opts.wasi_exec_model = parseWasiExecModel(rest);
                    } else if (mem.eql(u8, arg, "-municode")) {
                        cs.mingw_unicode_entry_point = true;
                    } else {
                        fatal("unrecognized parameter: {s}", .{arg});
                    }
                } else switch (file_ext orelse Compilation.classifyFileExt(arg)) {
                    .shared_library, .object, .static_library => {
                        try cs.create_module.cli_link_inputs.append(arena, .{ .path_query = .{
                            .path = Path.initCwd(arg),
                            .query = .{
                                .preferred_mode = cs.lib_preferred_mode,
                                .search_strategy = cs.lib_search_strategy,
                                .allow_so_scripts = cs.allow_so_scripts,
                            },
                        } });
                        // We do not set `any_dyn_libs` yet because a .so file
                        // may actually resolve to a GNU ld script which ends
                        // up being a static library.
                    },
                    .res => {
                        try cs.create_module.cli_link_inputs.append(arena, .{ .path_query = .{
                            .path = Path.initCwd(arg),
                            .query = .{
                                .preferred_mode = cs.lib_preferred_mode,
                                .search_strategy = cs.lib_search_strategy,
                                .allow_so_scripts = cs.allow_so_scripts,
                            },
                        } });
                        cs.contains_res_file = true;
                    },
                    .manifest => {
                        if (cs.manifest_file) |other| {
                            fatal("only one manifest file can be specified, found {q} after {q}", .{ arg, other });
                        } else cs.manifest_file = arg;
                    },
                    .def => {
                        cs.linker_module_definition_file = arg;
                    },
                    .assembly, .assembly_with_cpp, .c, .cpp, .h, .hpp, .hm, .hmm, .ll, .bc, .m, .mm => {
                        dev.check(.c_compiler);
                        try cs.create_module.c_source_files.append(arena, .{
                            // Populated after module creation.
                            .owner = undefined,
                            .src_path = arg,
                            .extra_flags = try arena.dupe([]const u8, cs.extra_cflags.items),
                            // duped when parsing the args.
                            .ext = file_ext,
                        });
                    },
                    .rc => {
                        dev.check(.win32_resource);
                        try cs.create_module.rc_source_files.append(arena, .{
                            // Populated after module creation.
                            .owner = undefined,
                            .src_path = arg,
                            .extra_flags = try arena.dupe([]const u8, cs.extra_rcflags.items),
                        });
                    },
                    .zig => {
                        if (cs.root_src_file) |other| {
                            fatal("found another zig file {q} after root source file {q}", .{ arg, other });
                        } else cs.root_src_file = arg;
                    },
                    .unknown => {
                        if (std.ascii.eqlIgnoreCase(".xml", fs.path.extension(arg))) {
                            warn("embedded manifest files must have the extension '.manifest'", .{});
                        }
                        fatal("unrecognized file extension of parameter {q}", .{arg});
                    },
                }
            }
        },
        .cc, .cpp => {
            dev.check(.cc_command);

            cs.emit_h = .no;
            cs.soname = .no;
            cs.create_module.opts.ensure_libc_on_non_freestanding = true;
            cs.create_module.opts.ensure_libcpp_on_non_freestanding = arg_mode == .cpp;
            cs.create_module.want_native_include_dirs = true;
            // Clang's driver enables this switch unconditionally.
            // Disabling the emission of .eh_frame_hdr can unexpectedly break
            // some functionality that depend on it, such as C++ exceptions and
            // DWARF-based stack traces.
            cs.link_eh_frame_hdr = true;
            cs.allow_so_scripts = true;

            const COutMode = enum {
                link,
                object,
                assembly,
                preprocessor,
                version,
            };
            var c_out_mode: ?COutMode = null;
            var out_path: ?[]const u8 = null;
            var is_shared_lib = false;
            var preprocessor_args = std.array_list.Managed([]const u8).init(arena);
            var linker_args = std.array_list.Managed([]const u8).init(arena);
            var it = ClangArgIterator.init(arena, all_args);
            var emit_llvm = false;
            var needed = false;
            var must_link = false;
            var file_ext: ?Compilation.FileExt = null;
            while (it.has_next) {
                it.next(io) catch |err| fatal("unable to parse command line parameters: {t}", .{err});
                switch (it.zig_equivalent) {
                    .target => cs.target_arch_os_abi = it.only_arg, // example: -target riscv64-linux-unknown
                    .o => {
                        // We handle -o /dev/null equivalent to -fno-emit-bin because
                        // otherwise our atomic rename into place will fail. This also
                        // makes Zig do less work, avoiding pointless file system operations.
                        if (mem.eql(u8, it.only_arg, "/dev/null")) {
                            cs.emit_bin = .no;
                        } else {
                            out_path = it.only_arg;
                        }
                    },
                    .c, .r => c_out_mode = .object, // -c or -r
                    .asm_only => c_out_mode = .assembly, // -S
                    .preprocess_only => c_out_mode = .preprocessor, // -E
                    .version => {
                        c_out_mode = .version; // --version
                        cs.disable_c_depfile = true;
                    },
                    .emit_llvm => emit_llvm = true,
                    .x => {
                        const lang = mem.sliceTo(it.only_arg, 0);
                        if (mem.eql(u8, lang, "none")) {
                            file_ext = null;
                        } else if (Compilation.FileExt.from_lang.get(lang)) |got_ext| {
                            file_ext = got_ext;
                        } else {
                            fatal("language not recognized: {q}", .{lang});
                        }
                    },
                    .other => {
                        try cs.cc_argv.appendSlice(arena, it.other_args);
                    },
                    .positional => switch (file_ext orelse Compilation.classifyFileExt(mem.sliceTo(it.only_arg, 0))) {
                        .assembly, .assembly_with_cpp, .c, .cpp, .ll, .bc, .h, .hpp, .hm, .hmm, .m, .mm => {
                            try cs.create_module.c_source_files.append(arena, .{
                                // Populated after module creation.
                                .owner = undefined,
                                .src_path = it.only_arg,
                                .ext = file_ext, // duped while parsing the args.
                            });
                        },
                        .unknown, .object, .static_library, .shared_library => {
                            try cs.create_module.cli_link_inputs.append(arena, .{ .path_query = .{
                                .path = Path.initCwd(it.only_arg),
                                .query = .{
                                    .must_link = must_link,
                                    .needed = needed,
                                    .preferred_mode = cs.lib_preferred_mode,
                                    .search_strategy = cs.lib_search_strategy,
                                    .allow_so_scripts = cs.allow_so_scripts,
                                },
                            } });
                            // We do not set `any_dyn_libs` yet because a .so file
                            // may actually resolve to a GNU ld script which ends
                            // up being a static library.
                        },
                        .res => {
                            try cs.create_module.cli_link_inputs.append(arena, .{ .path_query = .{
                                .path = Path.initCwd(it.only_arg),
                                .query = .{
                                    .must_link = must_link,
                                    .needed = needed,
                                    .preferred_mode = cs.lib_preferred_mode,
                                    .search_strategy = cs.lib_search_strategy,
                                    .allow_so_scripts = cs.allow_so_scripts,
                                },
                            } });
                            cs.contains_res_file = true;
                        },
                        .manifest => {
                            if (cs.manifest_file) |other| {
                                fatal("only one manifest file can be specified, found {q} after previously specified manifest {q}", .{ it.only_arg, other });
                            } else cs.manifest_file = it.only_arg;
                        },
                        .def => {
                            cs.linker_module_definition_file = it.only_arg;
                        },
                        .rc => {
                            try cs.create_module.rc_source_files.append(arena, .{
                                // Populated after module creation.
                                .owner = undefined,
                                .src_path = it.only_arg,
                            });
                        },
                        .zig => {
                            if (cs.root_src_file) |other| {
                                fatal("found another zig file {q} after root source file {q}", .{ it.only_arg, other });
                            } else cs.root_src_file = it.only_arg;
                        },
                    },
                    .l => {
                        // -l
                        // We don't know whether this library is part of libc or libc++ until
                        // we resolve the target, so we simply append to the list for now.
                        if (mem.startsWith(u8, it.only_arg, ":")) {
                            // -l :path/to/filename is used when callers need
                            // more control over what's in the resulting
                            // binary: no extra rpaths and DSO filename exactly
                            // as provided. CGo compilation depends on this.
                            try cs.create_module.cli_link_inputs.append(arena, .{ .dso_exact = .{
                                .name = it.only_arg,
                            } });
                        } else {
                            const compiler_rt_classification = target_util.classifyCompilerRtLibName(it.only_arg);
                            switch (compiler_rt_classification) {
                                .only_compiler_rt, .both => {
                                    // We need this variable separately from `want_compiler_rt` because of
                                    // invocations such as `zig cc -lcompiler_rt -nostdlib`. If we just set
                                    // `want_compiler_rt = true` here, processing of the later `-nostdlib`
                                    // would undo that.
                                    cs.zig_cc_explicitly_link_compiler_rt = true;
                                },
                                .none, .only_libunwind => {},
                            }
                            if (compiler_rt_classification != .only_compiler_rt) {
                                // The case in which this arg wants to link libunwind is handled in createModule.
                                try cs.create_module.cli_link_inputs.append(arena, .{ .name_query = .{
                                    .name = it.only_arg,
                                    .query = .{
                                        .must_link = must_link,
                                        .needed = needed,
                                        .weak = false,
                                        .preferred_mode = cs.lib_preferred_mode,
                                        .search_strategy = cs.lib_search_strategy,
                                        .allow_so_scripts = cs.allow_so_scripts,
                                    },
                                } });
                            }
                        }
                    },
                    .ignore => {},
                    .driver_punt => {
                        // Never mind what we're doing, just pass the args directly. For example --help.
                        return process.exit(try clangMain(arena, all_args));
                    },
                    .pic => cs.mod_opts.pic = true,
                    .no_pic => cs.mod_opts.pic = false,
                    .pie => cs.create_module.opts.pie = true,
                    .no_pie => cs.create_module.opts.pie = false,
                    .lto => {
                        if (mem.eql(u8, it.only_arg, "flto") or
                            mem.eql(u8, it.only_arg, "auto") or
                            mem.eql(u8, it.only_arg, "full") or
                            mem.eql(u8, it.only_arg, "jobserver"))
                        {
                            cs.create_module.opts.lto = .full;
                        } else if (mem.eql(u8, it.only_arg, "thin")) {
                            cs.create_module.opts.lto = .thin;
                        } else {
                            fatal("invalid -flto mode {q}; must be \"auto\", \"full\", \"thin\", or \"jobserver\"", .{it.only_arg});
                        }
                    },
                    .no_lto => cs.create_module.opts.lto = .none,
                    .red_zone => cs.mod_opts.red_zone = true,
                    .no_red_zone => cs.mod_opts.red_zone = false,
                    .omit_frame_pointer => cs.mod_opts.omit_frame_pointer = true,
                    .no_omit_frame_pointer => cs.mod_opts.omit_frame_pointer = false,
                    .function_sections => cs.function_sections = true,
                    .no_function_sections => cs.function_sections = false,
                    .data_sections => cs.data_sections = true,
                    .no_data_sections => cs.data_sections = false,
                    .builtin => cs.mod_opts.no_builtin = false,
                    .no_builtin => cs.mod_opts.no_builtin = true,
                    .color_diagnostics => cs.color = .on,
                    .no_color_diagnostics => cs.color = .off,
                    .stack_check => cs.mod_opts.stack_check = true,
                    .no_stack_check => cs.mod_opts.stack_check = false,
                    .stack_protector => {
                        if (cs.mod_opts.stack_protector == null) {
                            cs.mod_opts.stack_protector = Compilation.default_stack_protector_buffer_size;
                        }
                    },
                    .no_stack_protector => cs.mod_opts.stack_protector = 0,
                    // The way these unwind table options are processed in GCC and Clang is crazy
                    // convoluted, and we also don't know the target triple here, so this is all
                    // best-effort.
                    .unwind_tables => if (cs.mod_opts.unwind_tables) |uwt| switch (uwt) {
                        .none => {
                            cs.mod_opts.unwind_tables = .sync;
                        },
                        .sync, .async => {},
                    } else {
                        cs.mod_opts.unwind_tables = .sync;
                    },
                    .no_unwind_tables => cs.mod_opts.unwind_tables = .none,
                    .asynchronous_unwind_tables => cs.mod_opts.unwind_tables = .async,
                    .no_asynchronous_unwind_tables => if (cs.mod_opts.unwind_tables) |uwt| switch (uwt) {
                        .none, .sync => {},
                        .async => {
                            cs.mod_opts.unwind_tables = .sync;
                        },
                    } else {
                        cs.mod_opts.unwind_tables = .sync;
                    },
                    .nostdlib => {
                        cs.create_module.opts.ensure_libc_on_non_freestanding = false;
                        cs.create_module.opts.ensure_libcpp_on_non_freestanding = false;
                        cs.want_compiler_rt = false;
                        cs.want_ubsan_rt = false;
                    },
                    .nostdlib_cpp => cs.create_module.opts.ensure_libcpp_on_non_freestanding = false,
                    .shared => {
                        cs.create_module.opts.link_mode = .dynamic;
                        is_shared_lib = true;
                    },
                    .rdynamic => cs.create_module.opts.rdynamic = true,
                    .wp => {
                        var split_it = mem.splitScalar(u8, it.only_arg, ',');
                        while (split_it.next()) |preprocessor_arg| {
                            if (preprocessor_arg.len >= 3 and
                                preprocessor_arg[0] == '-' and
                                preprocessor_arg[2] != '-')
                            {
                                if (mem.findScalar(u8, preprocessor_arg, '=')) |equals_pos| {
                                    const key = preprocessor_arg[0..equals_pos];
                                    const value = preprocessor_arg[equals_pos + 1 ..];
                                    try preprocessor_args.append(key);
                                    try preprocessor_args.append(value);
                                    continue;
                                }
                            }
                            try preprocessor_args.append(preprocessor_arg);
                        }
                    },
                    .wl => {
                        var split_it = mem.splitScalar(u8, it.only_arg, ',');
                        while (split_it.next()) |linker_arg| {
                            // Unfortunately duplicated with the `for_linker` handling below.

                            // Handle nested-joined args like `-Wl,-rpath=foo`.
                            // Must be prefixed with 1 or 2 dashes.
                            if (linker_arg.len >= 3 and
                                linker_arg[0] == '-' and
                                linker_arg[2] != '-')
                            {
                                if (mem.findScalar(u8, linker_arg, '=')) |equals_pos| {
                                    const key = linker_arg[0..equals_pos];
                                    const value = linker_arg[equals_pos + 1 ..];

                                    // We have to handle these here because they would be ambiguous
                                    // if split and added to `linker_args`, as there are argument-less
                                    // variants of them.
                                    if (mem.eql(u8, key, "--build-id")) {
                                        cs.build_id = std.zig.BuildId.parse(value) catch |err| {
                                            fatal("unable to parse --build-id style {q}: {t}", .{ value, err });
                                        };
                                        continue;
                                    } else if (mem.eql(u8, key, "--sort-common")) {
                                        // this ignores --sort=common=<anything>; ignoring plain --sort-common
                                        // is done below.
                                        continue;
                                    }

                                    try linker_args.append(key);
                                    try linker_args.append(value);
                                    continue;
                                }
                            }

                            // These options are handled inline because their order matters for
                            // other non-linker options.
                            if (mem.eql(u8, linker_arg, "--as-needed")) {
                                needed = false;
                            } else if (mem.eql(u8, linker_arg, "--no-as-needed")) {
                                needed = true;
                            } else if (mem.eql(u8, linker_arg, "--whole-archive") or
                                mem.eql(u8, linker_arg, "-whole-archive"))
                            {
                                must_link = true;
                            } else if (mem.eql(u8, linker_arg, "--no-whole-archive") or
                                mem.eql(u8, linker_arg, "-no-whole-archive"))
                            {
                                must_link = false;
                            } else if (mem.eql(u8, linker_arg, "-Bdynamic") or
                                mem.eql(u8, linker_arg, "-dy") or
                                mem.eql(u8, linker_arg, "-call_shared"))
                            {
                                cs.lib_search_strategy = .no_fallback;
                                cs.lib_preferred_mode = .dynamic;
                            } else if (mem.eql(u8, linker_arg, "-Bstatic") or
                                mem.eql(u8, linker_arg, "-dn") or
                                mem.eql(u8, linker_arg, "-non_shared") or
                                mem.eql(u8, linker_arg, "-static"))
                            {
                                cs.lib_search_strategy = .no_fallback;
                                cs.lib_preferred_mode = .static;
                            } else if (mem.eql(u8, linker_arg, "-search_paths_first")) {
                                cs.lib_search_strategy = .paths_first;
                                cs.lib_preferred_mode = .dynamic;
                            } else if (mem.eql(u8, linker_arg, "-search_dylibs_first")) {
                                cs.lib_search_strategy = .mode_first;
                                cs.lib_preferred_mode = .dynamic;
                            } else {
                                try linker_args.append(linker_arg);
                            }
                        }
                    },
                    .san_cov_trace_pc_guard => cs.create_module.opts.san_cov_trace_pc_guard = true,
                    .san_cov => {
                        var split_it = mem.splitScalar(u8, it.only_arg, ',');
                        while (split_it.next()) |san_arg| {
                            if (std.mem.eql(u8, san_arg, "trace-pc-guard")) {
                                cs.create_module.opts.san_cov_trace_pc_guard = true;
                            }
                        }
                        try cs.cc_argv.appendSlice(arena, it.other_args);
                    },
                    .no_san_cov => {
                        var split_it = mem.splitScalar(u8, it.only_arg, ',');
                        while (split_it.next()) |san_arg| {
                            if (std.mem.eql(u8, san_arg, "trace-pc-guard")) {
                                cs.create_module.opts.san_cov_trace_pc_guard = false;
                            }
                        }
                        try cs.cc_argv.appendSlice(arena, it.other_args);
                    },
                    .optimize => {
                        // Alright, what release mode do they want?
                        const level = if (it.only_arg.len >= 1 and it.only_arg[0] == 'O') it.only_arg[1..] else it.only_arg;
                        if (mem.eql(u8, level, "s") or
                            mem.eql(u8, level, "z"))
                        {
                            cs.mod_opts.optimize_mode = .small;
                        } else if (mem.eql(u8, level, "1") or
                            mem.eql(u8, level, "2") or
                            mem.eql(u8, level, "3") or
                            mem.eql(u8, level, "4") or
                            mem.eql(u8, level, "fast"))
                        {
                            cs.mod_opts.optimize_mode = .fast;
                        } else if (mem.eql(u8, level, "g") or
                            mem.eql(u8, level, "0"))
                        {
                            cs.mod_opts.optimize_mode = .debug;
                        } else {
                            try cs.cc_argv.appendSlice(arena, it.other_args);
                        }
                    },
                    .debug => {
                        cs.mod_opts.strip = false;
                        if (mem.eql(u8, it.only_arg, "g")) {
                            // We handled with strip = false above.
                        } else if (mem.eql(u8, it.only_arg, "g1") or
                            mem.eql(u8, it.only_arg, "gline-tables-only"))
                        {
                            // We handled with strip = false above. but we also want reduced debug info.
                            try cs.cc_argv.append(arena, "-gline-tables-only");
                        } else {
                            try cs.cc_argv.appendSlice(arena, it.other_args);
                        }
                    },
                    .gdwarf32 => {
                        cs.mod_opts.strip = false;
                        cs.create_module.opts.debug_format = .{ .dwarf = .@"32" };
                    },
                    .gdwarf64 => {
                        cs.mod_opts.strip = false;
                        cs.create_module.opts.debug_format = .{ .dwarf = .@"64" };
                    },
                    .sanitize, .no_sanitize => |t| {
                        const enable = t == .sanitize;
                        var san_it = std.mem.splitScalar(u8, it.only_arg, ',');
                        var recognized_any = false;
                        while (san_it.next()) |sub_arg| {
                            if (mem.eql(u8, sub_arg, "undefined")) {
                                cs.mod_opts.sanitize_c = if (enable) .full else .off;
                                recognized_any = true;
                            } else if (mem.eql(u8, sub_arg, "thread")) {
                                cs.mod_opts.sanitize_thread = enable;
                                recognized_any = true;
                            } else if (mem.eql(u8, sub_arg, "fuzzer") or mem.eql(u8, sub_arg, "fuzzer-no-link")) {
                                cs.mod_opts.fuzz = enable;
                                recognized_any = true;
                            }
                        }
                        if (!recognized_any) {
                            try cs.cc_argv.appendSlice(arena, it.other_args);
                        }
                    },
                    .sanitize_trap, .no_sanitize_trap => |t| {
                        const enable = t == .sanitize_trap;
                        var san_it = std.mem.splitScalar(u8, it.only_arg, ',');
                        var recognized_any = false;
                        while (san_it.next()) |sub_arg| {
                            // This logic doesn't match Clang 1:1, but it's probably good enough, and avoids
                            // significantly complicating the resolution of the options.
                            if (mem.eql(u8, sub_arg, "undefined")) {
                                if (cs.mod_opts.sanitize_c) |sc| switch (sc) {
                                    .off => if (enable) {
                                        cs.mod_opts.sanitize_c = .trap;
                                    },
                                    .trap => if (!enable) {
                                        cs.mod_opts.sanitize_c = .full;
                                    },
                                    .full => if (enable) {
                                        cs.mod_opts.sanitize_c = .trap;
                                    },
                                } else {
                                    if (enable) {
                                        cs.mod_opts.sanitize_c = .trap;
                                    } else {
                                        // This means we were passed `-fno-sanitize-trap=undefined` and nothing else. In
                                        // this case, ideally, we should use whatever value `sanitize_c` resolves to by
                                        // default, except change `trap` to `full`. However, we don't yet know what
                                        // `sanitize_c` will resolve to! So we either have to pick `off` or `full`.
                                        //
                                        // `full` has the potential to be problematic if `optimize_mode` turns out to
                                        // be `fast`/`small` because the user will get a slower and larger
                                        // binary than expected. On the other hand, if `optimize_mode` turns out to be
                                        // `debug`/`safe`, `off` would mean UBSan would unexpectedly be disabled.
                                        //
                                        // `off` seems very slightly less bad, so let's go with that.
                                        cs.mod_opts.sanitize_c = .off;
                                    }
                                }
                                recognized_any = true;
                            }
                        }
                        if (!recognized_any) {
                            try cs.cc_argv.appendSlice(arena, it.other_args);
                        }
                    },
                    .linker_script => cs.linker_script = it.only_arg,
                    .verbose => {
                        cs.verbose_link = true;
                        // Have Clang print more infos, some tools such as CMake
                        // parse this to discover any implicit include and
                        // library dir to look-up into.
                        try cs.cc_argv.append(arena, "-v");
                    },
                    .dry_run => {
                        // This flag means "dry run". Clang will not actually output anything
                        // to the file system.
                        cs.verbose_link = true;
                        cs.disable_c_depfile = true;
                        try cs.cc_argv.append(arena, "-###");
                    },
                    .for_linker => blk: {
                        // Unfortunately duplicated with the `wl` handling above.

                        // Handle joined args like `--dependency-file=foo.d`.
                        // Must be prefixed with 1 or 2 dashes.
                        if (it.only_arg.len >= 3 and it.only_arg[0] == '-' and it.only_arg[2] != '-') {
                            if (mem.findScalar(u8, it.only_arg, '=')) |equals_pos| {
                                const key = it.only_arg[0..equals_pos];
                                const value = it.only_arg[equals_pos + 1 ..];

                                // We have to handle these here because they would be ambiguous
                                // if split and added to `linker_args`, as there are argument-less
                                // variants of them.
                                if (mem.eql(u8, key, "--build-id")) {
                                    cs.build_id = std.zig.BuildId.parse(value) catch |err| {
                                        fatal("unable to parse --build-id style {q}: {t}", .{ value, err });
                                    };
                                    continue;
                                } else if (mem.eql(u8, key, "--sort-common")) {
                                    // this ignores --sort-common=<anything>
                                    continue;
                                }

                                try linker_args.append(key);
                                try linker_args.append(value);
                                break :blk;
                            }
                        }

                        // These options are handled inline because their order matters for
                        // other non-linker options.
                        if (mem.eql(u8, it.only_arg, "--as-needed")) {
                            needed = false;
                        } else if (mem.eql(u8, it.only_arg, "--no-as-needed")) {
                            needed = true;
                        } else if (mem.eql(u8, it.only_arg, "--whole-archive") or
                            mem.eql(u8, it.only_arg, "-whole-archive"))
                        {
                            must_link = true;
                        } else if (mem.eql(u8, it.only_arg, "--no-whole-archive") or
                            mem.eql(u8, it.only_arg, "-no-whole-archive"))
                        {
                            must_link = false;
                        } else if (mem.eql(u8, it.only_arg, "-Bdynamic") or
                            mem.eql(u8, it.only_arg, "-dy") or
                            mem.eql(u8, it.only_arg, "-call_shared"))
                        {
                            cs.lib_search_strategy = .no_fallback;
                            cs.lib_preferred_mode = .dynamic;
                        } else if (mem.eql(u8, it.only_arg, "-Bstatic") or
                            mem.eql(u8, it.only_arg, "-dn") or
                            mem.eql(u8, it.only_arg, "-non_shared") or
                            mem.eql(u8, it.only_arg, "-static"))
                        {
                            cs.lib_search_strategy = .no_fallback;
                            cs.lib_preferred_mode = .static;
                        } else if (mem.eql(u8, it.only_arg, "-search_paths_first")) {
                            cs.lib_search_strategy = .paths_first;
                            cs.lib_preferred_mode = .dynamic;
                        } else if (mem.eql(u8, it.only_arg, "-search_dylibs_first")) {
                            cs.lib_search_strategy = .mode_first;
                            cs.lib_preferred_mode = .dynamic;
                        } else {
                            try linker_args.append(it.only_arg);
                        }
                    },
                    .for_linker => blk: {
                        // Unfortunately duplicated with the `wl` handling above.

                        // Handle joined args like `--dependency-file=foo.d`.
                        // Must be prefixed with 1 or 2 dashes.
                        if (it.only_arg.len >= 3 and it.only_arg[0] == '-' and it.only_arg[2] != '-') {
                            if (mem.indexOfScalar(u8, it.only_arg, '=')) |equals_pos| {
                                const key = it.only_arg[0..equals_pos];
                                const value = it.only_arg[equals_pos + 1 ..];

                                // We have to handle these here because they would be ambiguous
                                // if split and added to `linker_args`, as there are argument-less
                                // variants of them.
                                if (mem.eql(u8, key, "--build-id")) {
                                    cs.build_id = std.zig.BuildId.parse(value) catch |err| {
                                        fatal("unable to parse --build-id style '{s}': {s}", .{
                                            value, @errorName(err),
                                        });
                                    };
                                    continue;
                                } else if (mem.eql(u8, key, "--sort-common")) {
                                    // this ignores --sort-common=<anything>
                                    continue;
                                }

                                try linker_args.append(key);
                                try linker_args.append(value);
                                break :blk;
                            }
                        }

                        // These options are handled inline because their order matters for
                        // other non-linker options.
                        if (mem.eql(u8, it.only_arg, "--as-needed")) {
                            needed = false;
                        } else if (mem.eql(u8, it.only_arg, "--no-as-needed")) {
                            needed = true;
                        } else if (mem.eql(u8, it.only_arg, "--whole-archive") or
                            mem.eql(u8, it.only_arg, "-whole-archive"))
                        {
                            must_link = true;
                        } else if (mem.eql(u8, it.only_arg, "--no-whole-archive") or
                            mem.eql(u8, it.only_arg, "-no-whole-archive"))
                        {
                            must_link = false;
                        } else if (mem.eql(u8, it.only_arg, "-Bdynamic") or
                            mem.eql(u8, it.only_arg, "-dy") or
                            mem.eql(u8, it.only_arg, "-call_shared"))
                        {
                            cs.lib_search_strategy = .no_fallback;
                            cs.lib_preferred_mode = .dynamic;
                        } else if (mem.eql(u8, it.only_arg, "-Bstatic") or
                            mem.eql(u8, it.only_arg, "-dn") or
                            mem.eql(u8, it.only_arg, "-non_shared") or
                            mem.eql(u8, it.only_arg, "-static"))
                        {
                            cs.lib_search_strategy = .no_fallback;
                            cs.lib_preferred_mode = .static;
                        } else if (mem.eql(u8, it.only_arg, "-search_paths_first")) {
                            cs.lib_search_strategy = .paths_first;
                            cs.lib_preferred_mode = .dynamic;
                        } else if (mem.eql(u8, it.only_arg, "-search_dylibs_first")) {
                            cs.lib_search_strategy = .mode_first;
                            cs.lib_preferred_mode = .dynamic;
                        } else {
                            try linker_args.append(it.only_arg);
                        }
                    },
                    .linker_input_z => {
                        try linker_args.append("-z");
                        try linker_args.append(it.only_arg);
                    },
                    .lib_dir => try cs.create_module.lib_dir_args.append(arena, it.only_arg),
                    .mcpu => cs.target_mcpu = it.only_arg,
                    .m => try cs.create_module.llvm_m_args.append(arena, it.only_arg),
                    .dep_file => {
                        cs.disable_c_depfile = true;
                        try cs.cc_argv.appendSlice(arena, it.other_args);
                    },
                    .dep_file_to_stdout => { // -M, -MM
                        // "Like -MD, but also implies -E and writes to stdout by default"
                        // "Like -MMD, but also implies -E and writes to stdout by default"
                        c_out_mode = .preprocessor;
                        cs.disable_c_depfile = true;
                        try cs.cc_argv.appendSlice(arena, it.other_args);
                    },
                    .framework_dir => try cs.create_module.framework_dirs.append(arena, it.only_arg),
                    .framework => try cs.create_module.frameworks.put(arena, it.only_arg, .{}),
                    .nostdlibinc => cs.create_module.want_native_include_dirs = false,
                    .strip => cs.mod_opts.strip = true,
                    .exec_model => {
                        cs.create_module.opts.wasi_exec_model = parseWasiExecModel(it.only_arg);
                    },
                    .sysroot => {
                        cs.create_module.sysroot = it.only_arg;
                    },
                    .entry => {
                        cs.entry = .{ .named = it.only_arg };
                    },
                    .force_undefined_symbol => {
                        try cs.force_undefined_symbols.put(arena, it.only_arg, {});
                    },
                    .force_load_objc => cs.force_load_objc = true,
                    .mingw_unicode_entry_point => cs.mingw_unicode_entry_point = true,
                    .weak_library => try cs.create_module.cli_link_inputs.append(arena, .{ .name_query = .{
                        .name = it.only_arg,
                        .query = .{
                            .needed = false,
                            .weak = true,
                            .preferred_mode = cs.lib_preferred_mode,
                            .search_strategy = cs.lib_search_strategy,
                            .allow_so_scripts = cs.allow_so_scripts,
                        },
                    } }),
                    .weak_framework => try cs.create_module.frameworks.put(arena, it.only_arg, .{ .weak = true }),
                    .headerpad_max_install_names => cs.headerpad_max_install_names = true,
                    .compress_debug_sections => {
                        if (it.only_arg.len == 0) {
                            cs.linker_compress_debug_sections = .zlib;
                        } else {
                            cs.linker_compress_debug_sections = stringToEnum(std.zig.CompressDebugSections, it.only_arg) orelse {
                                fatal("expected [none|zlib|zstd] after --compress-debug-sections, found {q}", .{it.only_arg});
                            };
                        }
                    },
                    .install_name => {
                        cs.install_name = it.only_arg;
                    },
                    .undefined => {
                        if (mem.eql(u8, "dynamic_lookup", it.only_arg)) {
                            cs.linker_allow_shlib_undefined = true;
                        } else if (mem.eql(u8, "error", it.only_arg)) {
                            cs.linker_allow_shlib_undefined = false;
                        } else {
                            fatal("unsupported -undefined option {q}", .{it.only_arg});
                        }
                    },
                    .rtlib => {
                        // Unlike Clang, we support `none` for explicitly omitting compiler-rt.
                        if (mem.eql(u8, "none", it.only_arg)) {
                            cs.want_compiler_rt = false;
                        } else if (mem.eql(u8, "compiler-rt", it.only_arg) or
                            mem.eql(u8, "libgcc", it.only_arg))
                        {
                            cs.want_compiler_rt = true;
                        } else {
                            // Note that we don't support `platform`.
                            fatal("unsupported -rtlib option {q}", .{it.only_arg});
                        }
                    },
                    .static => {
                        cs.create_module.opts.link_mode = .static;
                        cs.lib_preferred_mode = .static;
                        cs.lib_search_strategy = .no_fallback;
                    },
                    .dynamic => {
                        cs.create_module.opts.link_mode = .dynamic;
                        cs.lib_preferred_mode = .dynamic;
                        cs.lib_search_strategy = .mode_first;
                    },
                }
            }
            // Parse linker args.
            var linker_args_it = ArgsIterator{
                .args = linker_args.items,
            };
            while (linker_args_it.next()) |arg| {
                if (mem.eql(u8, arg, "-soname") or
                    mem.eql(u8, arg, "--soname"))
                {
                    const name = linker_args_it.nextOrFatal();
                    cs.soname = .{ .yes = name };
                    // Use it as --name.
                    // Example: libsoundio.so.2
                    var prefix: usize = 0;
                    if (mem.startsWith(u8, name, "lib")) {
                        prefix = 3;
                    }
                    var end: usize = name.len;
                    if (mem.endsWith(u8, name, ".so")) {
                        end -= 3;
                    } else {
                        var found_digit = false;
                        while (end > 0 and std.ascii.isDigit(name[end - 1])) {
                            found_digit = true;
                            end -= 1;
                        }
                        if (found_digit and end > 0 and name[end - 1] == '.') {
                            end -= 1;
                        } else {
                            end = name.len;
                        }
                        if (mem.endsWith(u8, name[prefix..end], ".so")) {
                            end -= 3;
                        }
                    }
                    cs.provided_name = name[prefix..end];
                } else if (mem.eql(u8, arg, "--build-id")) {
                    cs.build_id = .fast;
                } else if (mem.eql(u8, arg, "-no-pie")) {
                    cs.create_module.opts.pie = false;
                } else if (mem.eql(u8, arg, "--sort-common")) {
                    // from ld.lld(1): --sort-common is ignored for GNU compatibility,
                    // this ignores plain --sort-common
                } else if (mem.eql(u8, arg, "-rpath") or mem.eql(u8, arg, "--rpath") or mem.eql(u8, arg, "-R")) {
                    try cs.create_module.rpath_list.append(arena, linker_args_it.nextOrFatal());
                } else if (mem.eql(u8, arg, "-rpath-link") or mem.eql(u8, arg, "--rpath-link")) {
                    _ = linker_args_it.nextOrFatal();
                    warn("rpath-link option is unimplemented and ignored", .{});
                } else if (mem.eql(u8, arg, "--subsystem")) {
                    cs.subsystem = try parseSubsystem(linker_args_it.nextOrFatal());
                } else if (mem.eql(u8, arg, "-I") or
                    mem.eql(u8, arg, "--dynamic-linker") or
                    mem.eql(u8, arg, "-dynamic-linker"))
                {
                    cs.dynamic_linker = linker_args_it.nextOrFatal();
                } else if (mem.eql(u8, arg, "--no-dynamic-linker") or
                    mem.eql(u8, arg, "-no-dynamic-linker"))
                {
                    cs.dynamic_linker = "";
                } else if (mem.eql(u8, arg, "-E") or
                    mem.eql(u8, arg, "--export-dynamic") or
                    mem.eql(u8, arg, "-export-dynamic"))
                {
                    cs.create_module.opts.rdynamic = true;
                } else if (mem.eql(u8, arg, "-version-script") or mem.eql(u8, arg, "--version-script")) {
                    cs.version_script = linker_args_it.nextOrFatal();
                } else if (mem.eql(u8, arg, "--undefined-version")) {
                    cs.linker_allow_undefined_version = true;
                } else if (mem.eql(u8, arg, "--no-undefined-version")) {
                    cs.linker_allow_undefined_version = false;
                } else if (mem.eql(u8, arg, "--enable-new-dtags")) {
                    cs.linker_enable_new_dtags = true;
                } else if (mem.eql(u8, arg, "--disable-new-dtags")) {
                    cs.linker_enable_new_dtags = false;
                } else if (mem.eql(u8, arg, "-O")) {
                    cs.linker_optimization = linker_args_it.nextOrFatal();
                } else if (mem.cutPrefix(u8, arg, "-O")) |rest| {
                    cs.linker_optimization = rest;
                } else if (mem.eql(u8, arg, "-pagezero_size")) {
                    const next_arg = linker_args_it.nextOrFatal();
                    cs.pagezero_size = std.fmt.parseUnsigned(u64, eatIntPrefix(next_arg, 16), 16) catch |err| {
                        fatal("unable to parse pagezero size {q}: {t}", .{ next_arg, err });
                    };
                } else if (mem.eql(u8, arg, "-headerpad")) {
                    const next_arg = linker_args_it.nextOrFatal();
                    cs.headerpad_size = std.fmt.parseUnsigned(u32, eatIntPrefix(next_arg, 16), 16) catch |err| {
                        fatal("unable to parse  headerpad size {q}: {t}", .{ next_arg, err });
                    };
                } else if (mem.eql(u8, arg, "-headerpad_max_install_names")) {
                    cs.headerpad_max_install_names = true;
                } else if (mem.eql(u8, arg, "-dead_strip")) {
                    cs.linker_gc_sections = true;
                } else if (mem.eql(u8, arg, "-dead_strip_dylibs")) {
                    cs.dead_strip_dylibs = true;
                } else if (mem.eql(u8, arg, "-ObjC")) {
                    cs.force_load_objc = true;
                } else if (mem.eql(u8, arg, "--no-undefined")) {
                    cs.linker_z_defs = true;
                } else if (mem.eql(u8, arg, "--gc-sections")) {
                    cs.linker_gc_sections = true;
                } else if (mem.eql(u8, arg, "--no-gc-sections")) {
                    cs.linker_gc_sections = false;
                } else if (mem.eql(u8, arg, "--print-gc-sections")) {
                    cs.linker_print_gc_sections = true;
                } else if (mem.eql(u8, arg, "--print-icf-sections")) {
                    cs.linker_print_icf_sections = true;
                } else if (mem.eql(u8, arg, "--print-map")) {
                    cs.linker_print_map = true;
                } else if (mem.eql(u8, arg, "-n") or mem.eql(u8, arg, "--nmagic")) {
                    cs.linker_nmagic = true;
                } else if (mem.eql(u8, arg, "--fatal-warnings")) {
                    cs.linker_fatal_warnings = true;
                } else if (mem.eql(u8, arg, "--no-fatal-warnings")) {
                    cs.linker_fatal_warnings = false;
                } else if (mem.eql(u8, arg, "-m")) {
                    _ = linker_args_it.nextOrFatal();
                    warn("-m option is ignored; emulation is derived from target", .{});
                } else if (mem.eql(u8, arg, "--sort-section")) {
                    const arg1 = linker_args_it.nextOrFatal();
                    cs.linker_sort_section = stringToEnum(link.File.Lld.Elf.SortSection, arg1) orelse {
                        fatal("expected [name|alignment] after --sort-section, found {q}", .{arg1});
                    };
                } else if (mem.eql(u8, arg, "--allow-shlib-undefined") or
                    mem.eql(u8, arg, "-allow-shlib-undefined"))
                {
                    cs.linker_allow_shlib_undefined = true;
                } else if (mem.eql(u8, arg, "--no-allow-shlib-undefined") or
                    mem.eql(u8, arg, "-no-allow-shlib-undefined"))
                {
                    cs.linker_allow_shlib_undefined = false;
                } else if (mem.eql(u8, arg, "-Bsymbolic")) {
                    cs.linker_bind_global_refs_locally = true;
                } else if (mem.eql(u8, arg, "--import-memory")) {
                    cs.create_module.opts.import_memory = true;
                } else if (mem.eql(u8, arg, "--export-memory")) {
                    cs.create_module.opts.export_memory = true;
                } else if (mem.eql(u8, arg, "--import-symbols")) {
                    cs.linker_import_symbols = true;
                } else if (mem.eql(u8, arg, "--import-table")) {
                    cs.linker_import_table = true;
                } else if (mem.eql(u8, arg, "--export-table")) {
                    cs.linker_export_table = true;
                } else if (mem.eql(u8, arg, "--growable-table")) {
                    cs.linker_growable_table = true;
                } else if (mem.eql(u8, arg, "--no-entry")) {
                    cs.entry = .disabled;
                } else if (mem.eql(u8, arg, "--initial-memory")) {
                    const next_arg = linker_args_it.nextOrFatal();
                    cs.linker_initial_memory = std.fmt.parseUnsigned(u32, next_arg, 10) catch |err| {
                        fatal("unable to parse initial memory size {q}: {t}", .{ next_arg, err });
                    };
                } else if (mem.eql(u8, arg, "--max-memory")) {
                    const next_arg = linker_args_it.nextOrFatal();
                    cs.linker_max_memory = std.fmt.parseUnsigned(u32, next_arg, 10) catch |err| {
                        fatal("unable to parse max memory size {q}: {t}", .{ next_arg, err });
                    };
                } else if (mem.eql(u8, arg, "--shared-memory")) {
                    cs.create_module.opts.shared_memory = true;
                } else if (mem.eql(u8, arg, "--global-base")) {
                    const next_arg = linker_args_it.nextOrFatal();
                    cs.linker_global_base = std.fmt.parseUnsigned(u32, next_arg, 10) catch |err| {
                        fatal("unable to parse global base {q}: {t}", .{ next_arg, err });
                    };
                } else if (mem.eql(u8, arg, "--export")) {
                    try cs.linker_export_symbol_names.append(arena, linker_args_it.nextOrFatal());
                } else if (mem.eql(u8, arg, "-exported_symbols_list")) {
                    const exported_symbols_list = linker_args_it.nextOrFatal();
                    const content = Io.Dir.cwd().readFileAlloc(io, exported_symbols_list, arena, .limited(10 * 1024 * 1024)) catch |err| {
                        fatal("unable to read exported symbols list {q}: {t}", .{ exported_symbols_list, err });
                    };
                    var symbols_it = mem.splitScalar(u8, content, '\n');
                    while (symbols_it.next()) |line| {
                        if (line.len == 0) continue;
                        try cs.linker_export_symbol_names.append(arena, line);
                    }
                } else if (mem.eql(u8, arg, "--compress-debug-sections")) {
                    const arg1 = linker_args_it.nextOrFatal();
                    cs.linker_compress_debug_sections = stringToEnum(std.zig.CompressDebugSections, arg1) orelse {
                        fatal("expected [none|zlib|zstd] after --compress-debug-sections, found {q}", .{arg1});
                    };
                } else if (mem.cutPrefix(u8, arg, "-z")) |z_rest| {
                    const z_arg = if (z_rest.len == 0) linker_args_it.nextOrFatal() else z_rest;
                    if (mem.eql(u8, z_arg, "nodelete")) {
                        cs.linker_z_nodelete = true;
                    } else if (mem.eql(u8, z_arg, "notext")) {
                        cs.linker_z_notext = true;
                    } else if (mem.eql(u8, z_arg, "defs")) {
                        cs.linker_z_defs = true;
                    } else if (mem.eql(u8, z_arg, "undefs")) {
                        cs.linker_z_defs = false;
                    } else if (mem.eql(u8, z_arg, "origin")) {
                        cs.linker_z_origin = true;
                    } else if (mem.eql(u8, z_arg, "nocopyreloc")) {
                        cs.linker_z_nocopyreloc = true;
                    } else if (mem.eql(u8, z_arg, "noexecstack")) {
                        // noexecstack is the default when linking with LLD
                    } else if (mem.eql(u8, z_arg, "now")) {
                        cs.linker_z_now = true;
                    } else if (mem.eql(u8, z_arg, "lazy")) {
                        cs.linker_z_now = false;
                    } else if (mem.eql(u8, z_arg, "relro")) {
                        cs.linker_z_relro = true;
                    } else if (mem.eql(u8, z_arg, "norelro")) {
                        cs.linker_z_relro = false;
                    } else if (mem.cutPrefix(u8, z_arg, "stack-size=")) |rest| {
                        cs.stack_size = parseStackSize(rest);
                    } else if (prefixedIntArg(z_arg, "common-page-size=")) |int| {
                        cs.linker_z_common_page_size = int;
                    } else if (prefixedIntArg(z_arg, "max-page-size=")) |int| {
                        cs.linker_z_max_page_size = int;
                    } else {
                        fatal("unsupported linker extension flag: -z {s}", .{z_arg});
                    }
                } else if (mem.eql(u8, arg, "--major-image-version")) {
                    const major = linker_args_it.nextOrFatal();
                    cs.version.major = std.fmt.parseUnsigned(u32, major, 10) catch |err| {
                        fatal("unable to parse major image version {q}: {t}", .{ major, err });
                    };
                    cs.have_version = true;
                } else if (mem.eql(u8, arg, "--minor-image-version")) {
                    const minor = linker_args_it.nextOrFatal();
                    cs.version.minor = std.fmt.parseUnsigned(u32, minor, 10) catch |err| {
                        fatal("unable to parse minor image version {q}: {t}", .{ minor, err });
                    };
                    cs.have_version = true;
                } else if (mem.eql(u8, arg, "-e") or mem.eql(u8, arg, "--entry")) {
                    cs.entry = .{ .named = linker_args_it.nextOrFatal() };
                } else if (mem.eql(u8, arg, "-u")) {
                    try cs.force_undefined_symbols.put(arena, linker_args_it.nextOrFatal(), {});
                } else if (mem.eql(u8, arg, "-w")) {
                    // This ignores the -w flag of ld64 and ld64.lld to suppress all linker warnings
                    // since Zig doesn't emit linker warnings.
                } else if (mem.eql(u8, arg, "-x") or mem.eql(u8, arg, "--discard-all")) {
                    cs.discard_local_symbols = true;
                } else if (mem.eql(u8, arg, "--stack") or mem.eql(u8, arg, "-stack_size")) {
                    cs.stack_size = parseStackSize(linker_args_it.nextOrFatal());
                } else if (mem.eql(u8, arg, "--image-base")) {
                    cs.image_base = parseImageBase(linker_args_it.nextOrFatal());
                } else if (mem.eql(u8, arg, "--enable-auto-image-base") or
                    mem.eql(u8, arg, "--disable-auto-image-base"))
                {
                    // `--enable-auto-image-base` is a flag that binutils added in ~2000 for MinGW.
                    // It does a hash of the file and uses that as part of the image base value.
                    // Presumably the idea was to avoid DLLs needing to be relocated when loaded.
                    // This is practically irrelevant today as all PEs produced since Windows Vista
                    // have ASLR enabled by default anyway, and Windows 10+ has Mandatory ASLR which
                    // doesn't even care what the PE file wants and relocates it anyway.
                    //
                    // Unfortunately, Libtool hardcodes usage of this archaic flag when targeting
                    // MinGW, so to make `zig cc` for that use case work, accept and ignore the
                    // flag, and warn the user that it has no effect.
                    warn("auto-image-base options are unimplemented and ignored", .{});
                } else if (mem.eql(u8, arg, "-T") or mem.eql(u8, arg, "--script")) {
                    cs.linker_script = linker_args_it.nextOrFatal();
                } else if (mem.eql(u8, arg, "--eh-frame-hdr")) {
                    cs.link_eh_frame_hdr = true;
                } else if (mem.eql(u8, arg, "--no-eh-frame-hdr")) {
                    cs.link_eh_frame_hdr = false;
                } else if (mem.eql(u8, arg, "--tsaware")) {
                    cs.linker_tsaware = true;
                } else if (mem.eql(u8, arg, "--nxcompat")) {
                    cs.linker_nxcompat = true;
                } else if (mem.eql(u8, arg, "--dynamicbase")) {
                    cs.linker_dynamicbase = true;
                } else if (mem.eql(u8, arg, "--no-dynamicbase")) {
                    cs.linker_dynamicbase = false;
                } else if (mem.eql(u8, arg, "--high-entropy-va")) {
                    // This option does not do anything.
                } else if (mem.eql(u8, arg, "--export-all-symbols")) {
                    cs.create_module.opts.rdynamic = true;
                } else if (mem.eql(u8, arg, "--color-diagnostics") or
                    mem.eql(u8, arg, "--color-diagnostics=always"))
                {
                    cs.color = .on;
                } else if (mem.eql(u8, arg, "--no-color-diagnostics") or
                    mem.eql(u8, arg, "--color-diagnostics=never"))
                {
                    cs.color = .off;
                } else if (mem.eql(u8, arg, "-s") or mem.eql(u8, arg, "--strip-all") or
                    mem.eql(u8, arg, "-S") or mem.eql(u8, arg, "--strip-debug"))
                {
                    // -s, --strip-all             Strip all symbols
                    // -S, --strip-debug           Strip debugging symbols
                    cs.mod_opts.strip = true;
                } else if (mem.eql(u8, arg, "--start-group") or
                    mem.eql(u8, arg, "--end-group"))
                {
                    // We don't need to care about these because these args are
                    // for resolving circular dependencies but our linker takes
                    // care of this without explicit args.
                } else if (mem.eql(u8, arg, "--major-os-version") or
                    mem.eql(u8, arg, "--minor-os-version"))
                {
                    // This option does not do anything.
                    _ = linker_args_it.nextOrFatal();
                } else if (mem.eql(u8, arg, "--major-subsystem-version")) {
                    const major = linker_args_it.nextOrFatal();
                    cs.major_subsystem_version = std.fmt.parseUnsigned(u16, major, 10) catch |err| {
                        fatal("unable to parse major subsystem version {q}: {t}", .{ major, err });
                    };
                } else if (mem.eql(u8, arg, "--minor-subsystem-version")) {
                    const minor = linker_args_it.nextOrFatal();
                    cs.minor_subsystem_version = std.fmt.parseUnsigned(u16, minor, 10) catch |err| {
                        fatal("unable to parse minor subsystem version {q}: {t}", .{ minor, err });
                    };
                } else if (mem.eql(u8, arg, "-framework")) {
                    try cs.create_module.frameworks.put(arena, linker_args_it.nextOrFatal(), .{});
                } else if (mem.eql(u8, arg, "-weak_framework")) {
                    try cs.create_module.frameworks.put(arena, linker_args_it.nextOrFatal(), .{ .weak = true });
                } else if (mem.eql(u8, arg, "-needed_framework")) {
                    try cs.create_module.frameworks.put(arena, linker_args_it.nextOrFatal(), .{ .needed = true });
                } else if (mem.eql(u8, arg, "-needed_library")) {
                    try cs.create_module.cli_link_inputs.append(arena, .{ .name_query = .{
                        .name = linker_args_it.nextOrFatal(),
                        .query = .{
                            .weak = false,
                            .needed = true,
                            .preferred_mode = cs.lib_preferred_mode,
                            .search_strategy = cs.lib_search_strategy,
                            .allow_so_scripts = cs.allow_so_scripts,
                        },
                    } });
                } else if (mem.cutPrefix(u8, arg, "-weak-l")) |rest| {
                    try cs.create_module.cli_link_inputs.append(arena, .{ .name_query = .{
                        .name = rest,
                        .query = .{
                            .weak = true,
                            .needed = false,
                            .preferred_mode = cs.lib_preferred_mode,
                            .search_strategy = cs.lib_search_strategy,
                            .allow_so_scripts = cs.allow_so_scripts,
                        },
                    } });
                } else if (mem.eql(u8, arg, "-weak_library")) {
                    try cs.create_module.cli_link_inputs.append(arena, .{ .name_query = .{
                        .name = linker_args_it.nextOrFatal(),
                        .query = .{
                            .weak = true,
                            .needed = false,
                            .preferred_mode = cs.lib_preferred_mode,
                            .search_strategy = cs.lib_search_strategy,
                            .allow_so_scripts = cs.allow_so_scripts,
                        },
                    } });
                } else if (mem.eql(u8, arg, "-compatibility_version")) {
                    const compat_version = linker_args_it.nextOrFatal();
                    cs.compatibility_version = std.SemanticVersion.parse(compat_version) catch |err| {
                        fatal("unable to parse -compatibility_version {q}: {t}", .{ compat_version, err });
                    };
                } else if (mem.eql(u8, arg, "-current_version")) {
                    const curr_version = linker_args_it.nextOrFatal();
                    cs.version = std.SemanticVersion.parse(curr_version) catch |err| {
                        fatal("unable to parse -current_version {q}: {t}", .{ curr_version, err });
                    };
                    cs.have_version = true;
                } else if (mem.eql(u8, arg, "--out-implib") or
                    mem.eql(u8, arg, "-implib"))
                {
                    cs.emit_implib = .{ .yes = linker_args_it.nextOrFatal() };
                    cs.emit_implib_arg_provided = true;
                } else if (mem.eql(u8, arg, "--dependency-file")) {
                    cs.link_depfile = linker_args_it.nextOrFatal();
                } else if (mem.eql(u8, arg, "-Brepro") or mem.eql(u8, arg, "/Brepro")) {
                    cs.linker_repro = true;
                } else if (mem.eql(u8, arg, "-undefined")) {
                    const lookup_type = linker_args_it.nextOrFatal();
                    if (mem.eql(u8, "dynamic_lookup", lookup_type)) {
                        cs.linker_allow_shlib_undefined = true;
                    } else if (mem.eql(u8, "error", lookup_type)) {
                        cs.linker_allow_shlib_undefined = false;
                    } else {
                        fatal("unsupported -undefined option {q}", .{lookup_type});
                    }
                } else if (mem.eql(u8, arg, "-install_name")) {
                    cs.install_name = linker_args_it.nextOrFatal();
                } else if (mem.eql(u8, arg, "-force_load")) {
                    try cs.create_module.cli_link_inputs.append(arena, .{ .path_query = .{
                        .path = Path.initCwd(linker_args_it.nextOrFatal()),
                        .query = .{
                            .must_link = true,
                            .preferred_mode = .static,
                            .search_strategy = .no_fallback,
                        },
                    } });
                } else if (mem.eql(u8, arg, "-hash-style") or
                    mem.eql(u8, arg, "--hash-style"))
                {
                    const next_arg = linker_args_it.nextOrFatal();
                    cs.hash_style = stringToEnum(link.File.Lld.Elf.HashStyle, next_arg) orelse {
                        fatal("expected [sysv|gnu|both] after --hash-style, found {q}", .{next_arg});
                    };
                } else if (mem.eql(u8, arg, "-wrap") or mem.eql(u8, arg, "--wrap")) {
                    const next_arg = linker_args_it.nextOrFatal();
                    try cs.symbol_wrap_set.put(arena, next_arg, {});
                } else if (mem.cutPrefix(u8, arg, "--wrap=")) |symbol| {
                    try cs.symbol_wrap_set.put(arena, symbol, {});
                } else if (mem.startsWith(u8, arg, "/subsystem:")) {
                    var split_it = mem.splitBackwardsScalar(u8, arg, ':');
                    cs.subsystem = try parseSubsystem(split_it.first());
                } else if (mem.startsWith(u8, arg, "/implib:")) {
                    var split_it = mem.splitBackwardsScalar(u8, arg, ':');
                    cs.emit_implib = .{ .yes = split_it.first() };
                    cs.emit_implib_arg_provided = true;
                } else if (mem.startsWith(u8, arg, "/pdb:")) {
                    var split_it = mem.splitBackwardsScalar(u8, arg, ':');
                    cs.pdb_out_path = split_it.first();
                } else if (mem.startsWith(u8, arg, "/version:")) {
                    var split_it = mem.splitBackwardsScalar(u8, arg, ':');
                    const version_arg = split_it.first();
                    cs.version = std.SemanticVersion.parse(version_arg) catch |err| {
                        fatal("unable to parse /version {q}: {t}", .{ arg, err });
                    };
                    cs.have_version = true;
                } else if (mem.eql(u8, arg, "-V")) {
                    warn("ignoring request for supported emulations: unimplemented", .{});
                } else if (mem.eql(u8, arg, "-v")) {
                    try Io.File.stdout().writeStreamingAll(io, "zig ld " ++ build_options.version ++ "\n");
                } else if (mem.eql(u8, arg, "--version")) {
                    try Io.File.stdout().writeStreamingAll(io, "zig ld " ++ build_options.version ++ "\n");
                    process.exit(0);
                } else {
                    fatal("unsupported linker arg: {s}", .{arg});
                }
            }

            // Parse preprocessor args.
            var preprocessor_args_it = ArgsIterator{
                .args = preprocessor_args.items,
            };
            while (preprocessor_args_it.next()) |arg| {
                if (mem.eql(u8, arg, "-MD") or mem.eql(u8, arg, "-MMD") or mem.eql(u8, arg, "-MT")) {
                    cs.disable_c_depfile = true;
                    const cc_arg = try arena.print("-Wp,{s},{s}", .{ arg, preprocessor_args_it.nextOrFatal() });
                    try cs.cc_argv.append(arena, cc_arg);
                } else {
                    fatal("unsupported preprocessor arg: {s}", .{arg});
                }
            }

            if (cs.mod_opts.sanitize_c) |wsc| {
                if (wsc != .off and cs.mod_opts.optimize_mode == .fast) {
                    cs.mod_opts.optimize_mode = .safe;
                }
            }

            // precompiled header syntax: "zig cc -x c-header test.h -o test.pch"
            const emit_pch = if (file_ext) |fe| switch (fe) {
                .h, .hpp, .hm, .hmm => c_out_mode == null,
                else => false,
            } else false;
            if (emit_pch) c_out_mode = .preprocessor;

            switch (c_out_mode orelse .link) {
                .link => {
                    cs.create_module.opts.output_mode = if (is_shared_lib) .Lib else .Exe;
                    if (cs.emit_bin != .no) {
                        cs.emit_bin = if (out_path) |p| .{ .yes = p } else .yes_a_out;
                    }
                    if (emit_llvm) {
                        fatal("-emit-llvm cannot be used when linking", .{});
                    }
                },
                .object => {
                    cs.create_module.opts.output_mode = .Obj;
                    if (emit_llvm) {
                        cs.emit_bin = .no;
                        if (out_path) |p| {
                            cs.emit_llvm_bc = .{ .yes = p };
                        } else {
                            cs.emit_llvm_bc = .yes_default_path;
                        }
                    } else {
                        if (out_path) |p| {
                            cs.emit_bin = .{ .yes = p };
                        } else {
                            cs.emit_bin = .yes_default_path;
                        }
                    }
                },
                .assembly => {
                    cs.create_module.opts.output_mode = .Obj;
                    cs.emit_bin = .no;
                    if (emit_llvm) {
                        if (out_path) |p| {
                            cs.emit_llvm_ir = .{ .yes = p };
                        } else {
                            cs.emit_llvm_ir = .yes_default_path;
                        }
                    } else {
                        if (out_path) |p| {
                            cs.emit_asm = .{ .yes = p };
                        } else {
                            cs.emit_asm = .yes_default_path;
                        }
                    }
                },
                .preprocessor => {
                    cs.create_module.opts.output_mode = .Obj;
                    // An error message is generated when there is more than 1 C source file.
                    if (cs.create_module.c_source_files.items.len != 1) {
                        // For example `zig cc` and no args should print the "no input files" message.
                        return process.exit(try clangMain(arena, all_args));
                    }
                    if (emit_pch) {
                        cs.emit_bin = if (out_path) |p| .{ .yes = p } else .yes_default_path;
                        cs.clang_preprocessor_mode = .pch;
                    } else {
                        // If the output path is "-" (stdout), then we need to emit the preprocessed output to stdout
                        // like "clang -E main.c -o -" does.
                        if (out_path != null and !mem.eql(u8, out_path.?, "-")) {
                            cs.emit_bin = .{ .yes = out_path.? };
                            cs.clang_preprocessor_mode = .yes;
                        } else {
                            cs.emit_bin = .no;
                            cs.clang_preprocessor_mode = .stdout;
                        }
                    }
                },
                .version => {
                    // We can't allow control flow to reach the simpler logic
                    // below because the -target argument has to be lowered to
                    // clang syntax in Compilation.
                    cs.create_module.opts.output_mode = .Obj;
                    cs.clang_preprocessor_mode = .version;
                    if (cs.create_module.c_source_files.items.len == 0) {
                        try cs.create_module.c_source_files.append(arena, .{
                            .owner = undefined,
                            .src_path = "a.c", // dummy name
                            .ext = .c,
                        });
                    }
                },
            }
            if (cs.create_module.c_source_files.items.len == 0 and
                !anyObjectLinkInputs(cs.create_module.cli_link_inputs.items) and
                cs.root_src_file == null)
            {
                // For example `zig cc` and no args should print the "no input files" message.
                // There could be other reasons to punt to clang, for example, --help.
                return process.exit(try clangMain(arena, all_args));
            }
        },
    }

    if (arg_mode == .zig_test_obj and !cs.test_no_exec and cs.listen == .none) {
        fatal("test-obj requires --test-no-exec", .{});
    }

    if (cs.time_report and cs.listen == .none) {
        fatal("--time-report requires --listen", .{});
    }

    if (arg_mode == .translate_c and cs.create_module.c_source_files.items.len != 1) {
        fatal("translate-c expects exactly 1 source file (found {d})", .{cs.create_module.c_source_files.items.len});
    }

    if (cs.time_report and cs.listen == .none) {
        fatal("--time-report requires --listen", .{});
    }

    if (arg_mode == .translate_c and cs.create_module.c_source_files.items.len != 1) {
        fatal("translate-c expects exactly 1 source file (found {d})", .{cs.create_module.c_source_files.items.len});
    }

    if (cs.show_builtin and cs.root_src_file == null) {
        // Without this, there will be no main module created and no zig
        // compilation unit, and therefore also no builtin.zig contents
        // created.
        cs.root_src_file = "builtin.zig";
    }

    implicit_root_mod: {
        const src_path = b: {
            if (cs.root_src_file) |src_path| {
                if (cs.create_module.modules.count() != 0) {
                    fatal("main module provided both by '-M{s}={s}{c}{s}' and by positional argument {q}", .{
                        cs.create_module.modules.keys()[0],
                        cs.create_module.modules.values()[0].root_path,
                        fs.path.sep,
                        cs.create_module.modules.values()[0].root_src_path,
                        src_path,
                    });
                }
                cs.create_module.opts.have_zcu = true;
                break :b src_path;
            }

            if (cs.create_module.modules.count() != 0)
                break :implicit_root_mod;

            if (cs.create_module.c_source_files.items.len >= 1)
                break :b cs.create_module.c_source_files.items[0].src_path;

            for (cs.create_module.cli_link_inputs.items) |unresolved_link_input| switch (unresolved_link_input) {
                // Intentionally includes dynamic libraries provided by file path.
                .path_query => |pq| break :b pq.path.sub_path,
                else => continue,
            };

            if (cs.emit_bin == .yes)
                break :b cs.emit_bin.yes;

            if (cs.create_module.rc_source_files.items.len >= 1)
                break :b cs.create_module.rc_source_files.items[0].src_path;

            if (arg_mode == .run)
                fatal("`zig run` expects at least one positional argument", .{});

            fatal("expected a positional argument, -femit-bin=[path], --show-builtin, or --name [name]", .{});

            break :implicit_root_mod;
        };

        // See duplicate logic: ModCreationGlobalFlags
        if (cs.mod_opts.single_threaded == false)
            cs.create_module.opts.any_non_single_threaded = true;
        if (cs.mod_opts.sanitize_thread == true)
            cs.create_module.opts.any_sanitize_thread = true;
        if (cs.mod_opts.sanitize_c) |sc| switch (sc) {
            .off => {},
            .trap => if (cs.create_module.opts.any_sanitize_c == .off) {
                cs.create_module.opts.any_sanitize_c = .trap;
            },
            .full => cs.create_module.opts.any_sanitize_c = .full,
        };
        if (cs.mod_opts.fuzz == true)
            cs.create_module.opts.any_fuzz = true;
        if (cs.mod_opts.unwind_tables) |uwt| switch (uwt) {
            .none => {},
            .sync, .async => cs.create_module.opts.any_unwind_tables = true,
        };
        if (cs.mod_opts.strip == false)
            cs.create_module.opts.any_non_stripped = true;
        if (cs.mod_opts.error_tracing == true)
            cs.create_module.opts.any_error_tracing = true;

        const name = switch (arg_mode) {
            .zig_test => "test",
            .build, .cc, .cpp, .translate_c, .zig_test_obj, .run => fs.path.stem(fs.path.basename(src_path)),
        };

        try cs.create_module.modules.put(arena, name, .{
            .root_path = fs.path.dirname(src_path) orelse ".",
            .root_src_path = fs.path.basename(src_path),
            .cc_argv = try cs.cc_argv.toOwnedSlice(arena),
            .inherited = cs.mod_opts,
            .target_arch_os_abi = cs.target_arch_os_abi,
            .target_mcpu = cs.target_mcpu,
            .dynamic_linker = cs.dynamic_linker,
            .deps = try cs.deps.toOwnedSlice(arena),
            .resolved = null,
            .c_source_files_start = cs.c_source_files_owner_index,
            .c_source_files_end = cs.create_module.c_source_files.items.len,
            .rc_source_files_start = cs.rc_source_files_owner_index,
            .rc_source_files_end = cs.create_module.rc_source_files.items.len,
        });
        cs.cssan.reset();
        cs.mod_opts = .{};
        cs.target_arch_os_abi = null;
        cs.target_mcpu = null;
        cs.c_source_files_owner_index = cs.create_module.c_source_files.items.len;
        cs.rc_source_files_owner_index = cs.create_module.rc_source_files.items.len;
    }

    if (!cs.create_module.opts.have_zcu and cs.create_module.opts.is_test) {
        fatal("`zig test` expects a zig source file argument", .{});
    }

    if (cs.c_source_files_owner_index != cs.create_module.c_source_files.items.len) {
        fatal("C source file {q} has no parent module", .{
            cs.create_module.c_source_files.items[cs.c_source_files_owner_index].src_path,
        });
    }

    if (cs.rc_source_files_owner_index != cs.create_module.rc_source_files.items.len) {
        fatal("resource file {q} has no parent module", .{
            cs.create_module.rc_source_files.items[cs.rc_source_files_owner_index].src_path,
        });
    }

    cs.self_exe_path_or_argv0 = switch (native_os) {
        .wasi => {},
        else => if (std.fs.path.isAbsolute(all_args[0])) all_args[0] else process.executablePathAlloc(io, arena) catch |err| fatal("unable to find zig self exe path: {t}", .{err}),
    };

    const cwd_path = try std.zig.getResolvedCwd(io, arena);

    // This `init` calls `fatal` on error.
    cs.dirs = .init(
        arena,
        io,
        cs.override_lib_dir,
        cs.override_global_cache_dir,
        s: {
            if (cs.override_local_cache_dir) |p| break :s .{ .override = p };
            break :s switch (arg_mode) {
                .run => .global,
                else => .search,
            };
        },
        preopens,
        cs.self_exe_path_or_argv0,
        environ_map,
        cwd_path,
    );

    if (cs.linker_optimization) |o| warn("ignoring deprecated linker optimization setting {q}", .{o});

    cs.create_module.dirs = cs.dirs;
    cs.create_module.opts.emit_llvm_ir = cs.emit_llvm_ir != .no;
    cs.create_module.opts.emit_llvm_bc = cs.emit_llvm_bc != .no;
    cs.create_module.opts.emit_bin = cs.emit_bin != .no;
    cs.create_module.opts.any_c_source_files = cs.create_module.c_source_files.items.len != 0;

    const main_mod = try createModule(gpa, arena, io, &cs.create_module, 0, null, cs.color, environ_map);
    for (cs.create_module.modules.keys(), cs.create_module.modules.values()) |key, cli_mod| {
        if (cli_mod.resolved == null)
            fatal("module {q} declared but not used", .{key});
    }

    // When you're testing std, the main module is std, and we need to avoid duplicating the module.
    const main_mod_is_std = main_mod.root.root == .zig_lib and
        mem.eql(u8, main_mod.root.sub_path, "std") and
        mem.eql(u8, main_mod.root_src_path, "std.zig");

    const std_mod = m: {
        if (main_mod_is_std) break :m main_mod;
        if (cs.create_module.modules.get("std")) |cli_mod| break :m cli_mod.resolved.?;
        break :m null;
    };

    const root_mod = switch (arg_mode) {
        .zig_test, .zig_test_obj => root_mod: {
            const test_mod = if (cs.test_runner_path) |test_runner| test_mod: {
                const test_mod = try Module.create(arena, .{
                    .paths = .{
                        .root = try .fromUnresolved(arena, cs.dirs, &.{fs.path.dirname(test_runner) orelse "."}),
                        .root_src_path = fs.path.basename(test_runner),
                    },
                    .fully_qualified_name = "root",
                    .cc_argv = &.{},
                    .inherited = .{},
                    .global = cs.create_module.resolved_options,
                    .parent = main_mod,
                });
                test_mod.deps = try main_mod.deps.clone(arena);
                break :test_mod test_mod;
            } else try Module.create(arena, .{
                .paths = .{
                    .root = try .fromRoot(arena, cs.dirs, .zig_lib, "compiler"),
                    .root_src_path = "test_runner.zig",
                },
                .fully_qualified_name = "root",
                .cc_argv = &.{},
                .inherited = .{},
                .global = cs.create_module.resolved_options,
                .parent = main_mod,
            });

            break :root_mod test_mod;
        },
        else => main_mod,
    };

    const target = &main_mod.resolved_target.result;

    if (target.cpu.arch == .arc or target.cpu.arch.isNvptx()) {
        if (cs.emit_bin != .no and cs.create_module.resolved_options.use_llvm) {
            fatal("cannot emit {s} binary with the LLVM backend; only '-femit-asm' is supported", .{
                @tagName(target.cpu.arch),
            });
        }
    }

    if (target.cpu.arch == .arc or target.cpu.arch.isNvptx()) {
        if (cs.emit_bin != .no and cs.create_module.resolved_options.use_llvm) {
            fatal("cannot emit {s} binary with the LLVM backend; only '-femit-asm' is supported", .{
                @tagName(target.cpu.arch),
            });
        }
    }

    if (target.os.tag == .windows and cs.major_subsystem_version == null and cs.minor_subsystem_version == null) {
        cs.major_subsystem_version, cs.minor_subsystem_version = switch (target.os.version_range.windows.min) {
            .nt4 => .{ 4, 0 },
            .win2k => .{ 5, 0 },
            .xp => if (target.cpu.arch == .x86_64) .{ 5, 2 } else .{ 5, 1 },
            .ws2003 => .{ 5, 2 },
            else => .{ null, null },
        };
    }

    if (target.ofmt != .coff) {
        if (cs.manifest_file != null) {
            fatal("manifest file is not allowed unless the target object format is coff (Windows/UEFI)", .{});
        }
        if (cs.create_module.rc_source_files.items.len != 0) {
            fatal("rc files are not allowed unless the target object format is coff (Windows/UEFI)", .{});
        }
        if (cs.contains_res_file) {
            fatal("res files are not allowed unless the target object format is coff (Windows/UEFI)", .{});
        }
    }

    var resolved_frameworks = std.array_list.Managed(Compilation.Framework).init(arena);

    if (cs.create_module.frameworks.keys().len > 0) {
        var test_path = std.array_list.Managed(u8).init(gpa);
        defer test_path.deinit();

        var checked_paths = std.array_list.Managed(u8).init(gpa);
        defer checked_paths.deinit();

        var failed_frameworks = std.array_list.Managed(struct {
            name: []const u8,
            checked_paths: []const u8,
        }).init(arena);

        framework: for (cs.create_module.frameworks.keys(), cs.create_module.frameworks.values()) |framework_name, info| {
            checked_paths.clearRetainingCapacity();

            for (cs.create_module.framework_dirs.items) |framework_dir_path| {
                if (try accessFrameworkPath(
                    io,
                    &test_path,
                    &checked_paths,
                    framework_dir_path,
                    framework_name,
                )) {
                    const path = Path.initCwd(try arena.dupe(u8, test_path.items));
                    try resolved_frameworks.append(.{
                        .needed = info.needed,
                        .weak = info.weak,
                        .path = path,
                    });
                    continue :framework;
                }
            }

            try failed_frameworks.append(.{
                .name = framework_name,
                .checked_paths = try arena.dupe(u8, checked_paths.items),
            });
        }

        if (failed_frameworks.items.len > 0) {
            for (failed_frameworks.items) |f| {
                const searched_paths = if (f.checked_paths.len == 0) " none" else f.checked_paths;
                std.log.err("unable to find framework {q}. searched paths: {s}", .{
                    f.name, searched_paths,
                });
            }
            process.exit(1);
        }
    }
    // After this point, resolved_frameworks is used instead of frameworks.

    if (cs.create_module.resolved_options.output_mode == .Obj and target.ofmt == .coff) {
        const total_obj_count = cs.create_module.c_source_files.items.len +
            @intFromBool(cs.root_src_file != null) +
            cs.create_module.rc_source_files.items.len +
            link.countObjectInputs(cs.create_module.link_inputs.items);
        if (total_obj_count > 1) {
            fatal("{s} does not support linking multiple objects into one", .{@tagName(target.ofmt)});
        }
    }

    var cleanup_emit_bin_dir: ?Io.Dir = null;
    defer if (cleanup_emit_bin_dir) |*dir| dir.close(io);

    // For `zig run` and `zig test`, we don't want to put the binary in the cwd by default. So, if
    // the binary is requested with no explicit path (as is the default), we emit to the cache.
    const output_to_cache: ?Emit.OutputToCacheReason = switch (cs.listen) {
        .stdio, .ip4 => .listen,
        .none => if (arg_mode == .run and cs.emit_bin == .yes_default_path)
            .@"zig run"
        else if (arg_mode == .zig_test and cs.emit_bin == .yes_default_path)
            .@"zig test"
        else
            null,
    };
    const optional_version = if (cs.have_version) cs.version else null;

    cs.root_name = if (cs.provided_name) |n| n else main_mod.fully_qualified_name;

    const resolved_soname: ?[]const u8 = switch (cs.soname) {
        .yes => |explicit| explicit,
        .no => null,
        .yes_default_value => if (cs.create_module.resolved_options.output_mode == .Lib and
            cs.create_module.resolved_options.link_mode == .dynamic and target.ofmt == .elf)
            if (cs.have_version)
                try arena.print("lib{s}.so.{d}", .{ cs.root_name, cs.version.major })
            else
                try arena.print("lib{s}.so", .{cs.root_name})
        else
            null,
    };

    const emit_bin_resolved: Compilation.CreateOptions.Emit = switch (cs.emit_bin) {
        .no => .no,
        .yes_default_path => emit: {
            if (output_to_cache != null) break :emit .yes_cache;
            const name = switch (cs.clang_preprocessor_mode) {
                .pch => try arena.print("{s}.pch", .{cs.root_name}),
                else => try std.zig.binNameAlloc(arena, .{
                    .root_name = cs.root_name,
                    .cpu_arch = target.cpu.arch,
                    .os_tag = target.os.tag,
                    .ofmt = target.ofmt,
                    .abi = target.abi,
                    .output_mode = cs.create_module.resolved_options.output_mode,
                    .link_mode = cs.create_module.resolved_options.link_mode,
                    .version = optional_version,
                }),
            };
            break :emit .{ .yes_path = name };
        },
        .yes => |path| if (output_to_cache != null) {
            assert(output_to_cache == .listen); // there was an explicit bin path
            fatal("--listen incompatible with explicit output path {q}", .{path});
        } else emit: {
            // If there's a dirname, check that dir exists. This will give a more descriptive error than `Compilation` otherwise would.
            if (fs.path.dirname(path)) |dir_path| {
                var dir = Io.Dir.cwd().openDir(io, dir_path, .{}) catch |err| {
                    fatal("unable to open output directory {q}: {t}", .{ dir_path, err });
                };
                dir.close(io);
            }
            break :emit .{ .yes_path = path };
        },
        .yes_a_out => emit: {
            assert(output_to_cache == null);
            break :emit .{ .yes_path = switch (target.ofmt) {
                .coff => "a.exe",
                else => "a.out",
            } };
        },
    };

    const default_h_basename = try arena.print("{s}.h", .{cs.root_name});
    const emit_h_resolved = cs.emit_h.resolve(io, default_h_basename, output_to_cache);

    const default_asm_basename = try arena.print("{s}.s", .{cs.root_name});
    const emit_asm_resolved = cs.emit_asm.resolve(io, default_asm_basename, output_to_cache);

    const default_llvm_ir_basename = try arena.print("{s}.ll", .{cs.root_name});
    const emit_llvm_ir_resolved = cs.emit_llvm_ir.resolve(io, default_llvm_ir_basename, output_to_cache);

    const default_llvm_bc_basename = try arena.print("{s}.bc", .{cs.root_name});
    const emit_llvm_bc_resolved = cs.emit_llvm_bc.resolve(io, default_llvm_bc_basename, output_to_cache);

    const emit_docs_resolved = cs.emit_docs.resolve(io, "docs", output_to_cache);

    const is_exe_or_dyn_lib = switch (cs.create_module.resolved_options.output_mode) {
        .Obj => false,
        .Lib => cs.create_module.resolved_options.link_mode == .dynamic,
        .Exe => true,
    };
    // Note that cmake when targeting Windows will try to execute
    // zig cc to make an executable and output an implib too.
    const implib_eligible = is_exe_or_dyn_lib and
        emit_bin_resolved != .no and target.os.tag == .windows;
    if (!implib_eligible) {
        if (!cs.emit_implib_arg_provided) {
            cs.emit_implib = .no;
        } else if (cs.emit_implib != .no) {
            fatal("the argument -femit-implib is allowed only when building a Windows DLL", .{});
        }
    }
    const default_implib_basename = try arena.print("{s}.lib", .{cs.root_name});
    const emit_implib_resolved: Compilation.CreateOptions.Emit = switch (cs.emit_implib) {
        .no => .no,
        .yes => cs.emit_implib.resolve(io, default_implib_basename, output_to_cache),
        .yes_default_path => emit: {
            if (output_to_cache != null) break :emit .yes_cache;
            const p = try fs.path.join(arena, &.{
                fs.path.dirname(emit_bin_resolved.yes_path) orelse ".",
                default_implib_basename,
            });
            break :emit .{ .yes_path = p };
        },
    };

    const thread_limit = @min(
        @max(cs.n_jobs orelse std.Thread.getCpuCount() catch 1, 1),
        std.math.maxInt(Zcu.PerThread.IdBacking),
    );
    try setThreadLimit(arena, thread_limit, if (ds) |_| &cs.*.io_impl else globals.io_impl_ptr);

    for (cs.create_module.c_source_files.items) |*src| {
        dev.check(.c_compiler);
        if (!mem.eql(u8, src.src_path, "-")) continue;

        const ext = src.ext orelse
            fatal("-E or -x is required when reading from a non-regular file", .{});

        // "-" is stdin. Dump it to a real file.
        const sep = fs.path.sep_str;
        const dump_path = try arena.print("tmp" ++ sep ++ "{x}-dump-stdin{s}", .{
            randInt(io, u64), ext.canonicalName(target),
        });
        try cs.dirs.local_cache.handle.createDirPath(io, "tmp");

        // Note that in one of the happy paths, execve() is used to switch to
        // clang in which case any cleanup logic that exists for this temporary
        // file will not run and this temp file will be leaked. The filename
        // will be a hash of its contents — so multiple invocations of
        // `zig cc -` will result in the same temp file name.
        var f = try cs.dirs.local_cache.handle.createFile(io, dump_path, .{});
        defer f.close(io);

        // Re-using the hasher from Cache, since the functional requirements
        // for the hashing algorithm here and in the cache are the same.
        // We are providing our own cache key, because this file has nothing
        // to do with the cache manifest.
        var file_writer = f.writer(io, &.{});
        var buffer: [1000]u8 = undefined;
        var hasher = file_writer.interface.hashed(Cache.Hasher.init("0123456789abcdef"), &buffer);
        var stdin_reader = Io.File.stdin().readerStreaming(io, &.{});
        _ = hasher.writer.sendFileAll(&stdin_reader, .unlimited) catch |err| switch (err) {
            error.WriteFailed => fatal("failed to write {s}: {t}", .{ dump_path, file_writer.err.? }),
            else => fatal("failed to pipe stdin to {s}: {t}", .{ dump_path, err }),
        };
        try hasher.writer.flush();

        const bin_digest: Cache.BinDigest = hasher.hasher.finalResult();

        const sub_path = try arena.print("tmp" ++ sep ++ "{x}-stdin{s}", .{
            &bin_digest, ext.canonicalName(target),
        });
        try cs.dirs.local_cache.handle.rename(dump_path, cs.dirs.local_cache.handle, sub_path, io);

        // Convert `sub_path` to be relative to current working directory.
        src.src_path = try cs.dirs.local_cache.join(arena, &.{sub_path});
    }

    if (build_options.have_llvm and emit_asm_resolved != .no) {
        // LLVM has no way to set this non-globally.
        const argv = [_][*:0]const u8{ "zig (LLVM option parsing)", "--x86-asm-syntax=intel" };
        @import("codegen/llvm/bindings.zig").ParseCommandLineOptions(argv.len, &argv);
    }

    const clang_passthrough_mode = switch (arg_mode) {
        .cc, .cpp, .translate_c => true,
        else => false,
    };

    const incremental = cs.create_module.resolved_options.incremental;
    if (cs.debug_incremental and !incremental) {
        fatal("--debug-incremental requires -fincremental", .{});
    }

    cs.cache_mode = b: {
        // Once incremental compilation is the default, we'll want some smarter logic here,
        // considering things like the backend in use and whether there's a ZCU.
        if (output_to_cache == null) break :b .none;
        if (incremental) break :b .incremental;
        break :b .whole;
    };

    // Deduplicate rpath entries
    var rpath_dedup = std.array_hash_map.String(void){};
    for (cs.create_module.rpath_list.items) |rpath| {
        try rpath_dedup.put(arena, rpath, {});
    }
    cs.create_module.rpath_list.clearRetainingCapacity();
    try cs.create_module.rpath_list.appendSlice(arena, rpath_dedup.keys());

    var create_diag: Compilation.CreateDiagnostic = undefined;
    const comp = Compilation.create(gpa, arena, io, &create_diag, .{
        .dirs = cs.dirs,
        .thread_limit = thread_limit,
        .self_exe_path = switch (native_os) {
            .wasi => null,
            else => cs.self_exe_path_or_argv0,
        },
        .config = cs.create_module.resolved_options,
        .root_name = cs.root_name,
        .sysroot = cs.create_module.sysroot,
        .main_mod = main_mod,
        .root_mod = root_mod,
        .std_mod = std_mod,
        .emit_bin = emit_bin_resolved,
        .emit_h = emit_h_resolved,
        .emit_asm = emit_asm_resolved,
        .emit_llvm_ir = emit_llvm_ir_resolved,
        .emit_llvm_bc = emit_llvm_bc_resolved,
        .emit_docs = emit_docs_resolved,
        .emit_implib = emit_implib_resolved,
        .lib_directories = cs.create_module.lib_directories.items,
        .rpath_list = cs.create_module.rpath_list.items,
        .symbol_wrap_set = cs.symbol_wrap_set,
        .c_source_files = cs.create_module.c_source_files.items,
        .rc_source_files = cs.create_module.rc_source_files.items,
        .manifest_file = cs.manifest_file,
        .rc_includes = cs.rc_includes,
        .mingw_unicode_entry_point = cs.mingw_unicode_entry_point,
        .link_inputs = cs.create_module.link_inputs.items,
        .framework_dirs = cs.create_module.framework_dirs.items,
        .frameworks = resolved_frameworks.items,
        .windows_lib_names = cs.create_module.windows_libs.keys(),
        .want_compiler_rt = if (cs.zig_cc_explicitly_link_compiler_rt) true else cs.want_compiler_rt,
        .want_ubsan_rt = cs.want_ubsan_rt,
        .hash_style = cs.hash_style,
        .linker_script = cs.linker_script,
        .version_script = cs.version_script,
        .linker_allow_undefined_version = cs.linker_allow_undefined_version,
        .linker_enable_new_dtags = cs.linker_enable_new_dtags,
        .disable_c_depfile = cs.disable_c_depfile,
        .soname = resolved_soname,
        .linker_sort_section = cs.linker_sort_section,
        .linker_gc_sections = cs.linker_gc_sections,
        .linker_repro = cs.linker_repro,
        .linker_allow_shlib_undefined = cs.linker_allow_shlib_undefined,
        .linker_bind_global_refs_locally = cs.linker_bind_global_refs_locally,
        .linker_import_symbols = cs.linker_import_symbols,
        .linker_import_table = cs.linker_import_table,
        .linker_export_table = cs.linker_export_table,
        .linker_growable_table = cs.linker_growable_table,
        .linker_initial_memory = cs.linker_initial_memory,
        .linker_max_memory = cs.linker_max_memory,
        .linker_print_gc_sections = cs.linker_print_gc_sections,
        .linker_print_icf_sections = cs.linker_print_icf_sections,
        .linker_print_map = cs.linker_print_map,
        .linker_nmagic = cs.linker_nmagic,
        .linker_fatal_warnings = cs.linker_fatal_warnings,
        .llvm_opt_bisect_limit = cs.llvm_opt_bisect_limit,
        .linker_global_base = cs.linker_global_base,
        .linker_export_symbol_names = cs.linker_export_symbol_names.items,
        .linker_z_nocopyreloc = cs.linker_z_nocopyreloc,
        .linker_z_nodelete = cs.linker_z_nodelete,
        .linker_z_notext = cs.linker_z_notext,
        .linker_z_defs = cs.linker_z_defs,
        .linker_z_origin = cs.linker_z_origin,
        .linker_z_now = cs.linker_z_now,
        .linker_z_relro = cs.linker_z_relro,
        .linker_z_common_page_size = cs.linker_z_common_page_size,
        .linker_z_max_page_size = cs.linker_z_max_page_size,
        .linker_tsaware = cs.linker_tsaware,
        .linker_nxcompat = cs.linker_nxcompat,
        .linker_dynamicbase = cs.linker_dynamicbase,
        .linker_compress_debug_sections = cs.linker_compress_debug_sections,
        .linker_module_definition_file = cs.linker_module_definition_file,
        .major_subsystem_version = cs.major_subsystem_version,
        .minor_subsystem_version = cs.minor_subsystem_version,
        .link_eh_frame_hdr = cs.link_eh_frame_hdr,
        .link_emit_relocs = cs.link_emit_relocs,
        .entry = cs.entry,
        .force_undefined_symbols = cs.force_undefined_symbols,
        .stack_size = cs.stack_size,
        .image_base = cs.image_base,
        .function_sections = cs.function_sections,
        .data_sections = cs.data_sections,
        .clang_passthrough_mode = clang_passthrough_mode,
        .clang_preprocessor_mode = cs.clang_preprocessor_mode,
        .version = optional_version,
        .compatibility_version = cs.compatibility_version,
        .libc_installation = if (cs.create_module.libc_installation) |*lci| lci else null,
        .verbose_cc = cs.verbose_cc,
        .verbose_link = cs.verbose_link,
        .verbose_air = cs.verbose_air,
        .verbose_intern_pool = cs.verbose_intern_pool,
        .verbose_generic_instances = cs.verbose_generic_instances,
        .verbose_llvm_ir = cs.verbose_llvm_ir,
        .verbose_llvm_bc = cs.verbose_llvm_bc,
        .link_depfile = cs.link_depfile,
        .verbose_llvm_cpu_features = cs.verbose_llvm_cpu_features,
        .time_report = cs.time_report,
        .stack_report = cs.stack_report,
        .build_id = cs.build_id,
        .test_filters = cs.test_filters.items,
        .test_runner_path = cs.test_runner_path,
        .cache_mode = cs.cache_mode,
        .subsystem = cs.subsystem,
        .debug_compile_errors = cs.debug_compile_errors,
        .debug_incremental = cs.debug_incremental,
        .enable_link_snapshots = cs.enable_link_snapshots,
        .install_name = cs.install_name,
        .entitlements = cs.entitlements,
        .pagezero_size = cs.pagezero_size,
        .headerpad_size = cs.headerpad_size,
        .headerpad_max_install_names = cs.headerpad_max_install_names,
        .dead_strip_dylibs = cs.dead_strip_dylibs,
        .force_load_objc = cs.force_load_objc,
        .discard_local_symbols = cs.discard_local_symbols,
        .reference_trace = cs.reference_trace,
        .pdb_out_path = cs.pdb_out_path,
        .error_limit = cs.error_limit,
        .native_system_include_paths = cs.create_module.native_system_include_paths,
        // Any leftover C compilation args (such as -I) apply globally rather
        // than to any particular module. This feature can greatly reduce CLI
        // noise when --search-prefix and -M are combined.
        .global_cc_argv = try cs.cc_argv.toOwnedSlice(arena),
        .file_system_inputs = &cs.file_system_inputs,
        .debug_compiler_runtime_libs = cs.debug_compiler_runtime_libs,
        .environ_map = environ_map,
        .lsp_document_store = ds,
    }) catch |err| switch (err) {
        error.CreateFail => switch (create_diag) {
            .cross_libc_unavailable => {
                // We can emit a more informative error for this.
                const triple_name = try target.zigTriple(arena);
                std.log.err("unable to provide libc for target {q}", .{triple_name});

                for (std.zig.target.available_libcs) |t| {
                    if (t.arch == target.cpu.arch and t.os == target.os.tag) {
                        // If there's a `glibc_min`, there's also an `os_ver`.
                        if (t.glibc_min) |glibc_min| {
                            std.log.info("zig can provide libc for related target {t}-{t}.{f}-{t}.{d}.{d}", .{
                                t.arch, t.os, t.os_ver.?, t.abi, glibc_min.major, glibc_min.minor,
                            });
                        } else if (t.os_ver) |os_ver| {
                            std.log.info("zig can provide libc for related target {t}-{t}.{f}-{t}", .{
                                t.arch, t.os, os_ver, t.abi,
                            });
                        } else {
                            std.log.info("zig can provide libc for related target {t}-{t}-{t}", .{
                                t.arch, t.os, t.abi,
                            });
                        }
                    }
                }
                process.exit(1);
            },
            else => fatal("{f}", .{create_diag}),
        },
        else => fatal("failed to create compilation: {t}", .{err}),
    };

    if (lsp_compilation_build) |lsp_comp_build| {
        lsp_comp_build.compilation = comp;
        comp.lsp_comp_build = lsp_comp_build;
        return;
    }

    var comp_destroyed = false;
    defer if (!comp_destroyed) comp.destroy();

    if (cs.show_builtin) {
        const builtin_opts = comp.root_mod.getBuiltinOptions(comp.config);
        const source = try builtin_opts.generate(arena);
        return Io.File.stdout().writeStreamingAll(io, source);
    }
    switch (cs.listen) {
        .none => {},
        .stdio => {
            var stdin_reader = Io.File.stdin().reader(io, &stdin_buffer);
            var stdout_writer = Io.File.stdout().writer(io, &stdout_buffer);
            try serve(
                comp,
                &stdin_reader.interface,
                &stdout_writer.interface,
                cs.test_exec_args.items,
                cs.self_exe_path,
                arg_mode,
                all_args,
                cs.runtime_args_start,
                environ_map,
            );
            return cleanExit(io);
        },
        .ip4 => |ip4_addr| {
            const addr: Io.net.IpAddress = .{ .ip4 = ip4_addr };

            var server = try addr.listen(io, .{
                .reuse_address = true,
            });
            defer server.deinit(io);

            var stream = try server.accept(io);
            defer stream.close(io);

            var input = stream.reader(io, &stdin_buffer);
            var output = stream.writer(io, &stdout_buffer);

            try serve(
                comp,
                &input.interface,
                &output.interface,
                cs.test_exec_args.items,
                cs.self_exe_path,
                arg_mode,
                all_args,
                cs.runtime_args_start,
                environ_map,
            );
            return cleanExit(io);
        },
    }

    {
        const root_prog_node = std.Progress.start(io, .{
            .disable_printing = (cs.color == .off),
        });
        defer root_prog_node.end();

        if (arg_mode == .translate_c) {
            return cmdTranslateC(comp, arena, null, null, root_prog_node, environ_map);
        }

        updateModule(comp, cs.color, root_prog_node) catch |err| switch (err) {
            error.CompileErrorsReported => {
                assert(cs.listen == .none);
                saveState(comp, incremental);
                process.exit(1);
            },
            else => |e| return e,
        };
    }
    try comp.makeBinFileExecutable();
    saveState(comp, incremental);

    if (switch (arg_mode) {
        .run => true,
        .zig_test => !cs.test_no_exec,
        else => false,
    }) {
        dev.checkAny(&.{ .run_command, .test_command });

        cs.self_exe_path_or_argv0 = switch (native_os) {
            .wasi => all_args[0], // Will error because of `!process.can_spawn`
            else => cs.self_exe_path_or_argv0,
        };

        if (cs.test_exec_args.items.len == 0 and target.ofmt == .c and emit_bin_resolved != .no) {
            // Default to using `zig run` to execute the produced .c code from `zig test`.
            try cs.test_exec_args.appendSlice(arena, &.{ cs.self_exe_path_or_argv0, "run" });
            // Skip passing `-ofmt`, we want the default for the target, not `.c` anymore.

            var prev_has_cflags = false;
            var prev_has_rcflags = false;
            {
                if (cs.dirs.zig_lib.path) |zig_lib_path| {
                    try cs.test_exec_args.appendSlice(arena, &.{ "-cflags", "-I", zig_lib_path, "--" });
                    prev_has_cflags = true;
                }
                const emit_ext: Compilation.FileExt = .c;
                const need_lang = if (comp.emit_bin) |comp_emit_bin| Compilation.classifyFileExt(comp_emit_bin) != emit_ext else true;
                if (need_lang) try cs.test_exec_args.appendSlice(arena, &.{ "-x", emit_ext.toLang() });
                try cs.test_exec_args.append(arena, null);
                if (need_lang) try cs.test_exec_args.appendSlice(arena, &.{ "-x", "none" });
            }
            for (cs.create_module.modules.keys(), cs.create_module.modules.values()) |mod_name, mod| {
                for (cs.create_module.c_source_files.items[mod.c_source_files_start..mod.c_source_files_end]) |c_source_file| {
                    const cflags_len = c_source_file.extra_flags.len + c_source_file.cache_exempt_flags.len;
                    if (prev_has_cflags or cflags_len > 0) {
                        try cs.test_exec_args.ensureUnusedCapacity(arena, 1 + cflags_len + 1);
                        cs.test_exec_args.appendAssumeCapacity("-cflags");
                        for (c_source_file.extra_flags) |extra_flag| cs.test_exec_args.appendAssumeCapacity(extra_flag);
                        for (c_source_file.cache_exempt_flags) |cache_exempt_flag| cs.test_exec_args.appendAssumeCapacity(cache_exempt_flag);
                        cs.test_exec_args.appendAssumeCapacity("--");
                    }
                    prev_has_cflags = cflags_len > 0;
                    if (c_source_file.ext) |ext| try cs.test_exec_args.appendSlice(arena, &.{ "-x", ext.toLang() });
                    try cs.test_exec_args.append(arena, c_source_file.src_path);
                    if (c_source_file.ext) |_| try cs.test_exec_args.appendSlice(arena, &.{ "-x", "none" });
                }
                for (cs.create_module.rc_source_files.items[mod.rc_source_files_start..mod.rc_source_files_end]) |rc_source_file| {
                    const rcflags_len = rc_source_file.extra_flags.len;
                    if (prev_has_rcflags or rcflags_len > 0) {
                        try cs.test_exec_args.ensureUnusedCapacity(arena, 1 + rcflags_len + 1);
                        cs.test_exec_args.appendAssumeCapacity("-rcflags");
                        for (rc_source_file.extra_flags) |extra_flag| cs.test_exec_args.appendAssumeCapacity(extra_flag);
                        cs.test_exec_args.appendAssumeCapacity("--");
                    }
                    prev_has_rcflags = rcflags_len > 0;
                    try cs.test_exec_args.append(arena, rc_source_file.src_path);
                }
                if (mod.target_arch_os_abi) |triple| try cs.test_exec_args.appendSlice(arena, &.{ "-target", triple });
                if (mod.target_mcpu) |mcpu| try cs.test_exec_args.appendSlice(arena, &.{ "-mcpu", mcpu });
                if (mod.dynamic_linker) |dl| if (dl.len > 0)
                    try cs.test_exec_args.appendSlice(arena, &.{ "--dynamic-linker", dl })
                else
                    try cs.test_exec_args.append(arena, "--no-dynamic-linker");
                try cs.test_exec_args.ensureUnusedCapacity(arena, mod.cc_argv.len);
                for (mod.cc_argv) |cc_arg| cs.test_exec_args.appendAssumeCapacity(cc_arg);
                for (mod.deps) |dep| try cs.test_exec_args.appendSlice(arena, &.{
                    "--dep",
                    if (std.mem.eql(u8, dep.key, dep.value)) dep.value else try arena.print("{s}={s}", .{ dep.key, dep.value }),
                });
                try cs.test_exec_args.append(arena, try arena.print("-M{s}", .{mod_name}));
            }

            try cs.test_exec_args.ensureUnusedCapacity(arena, comp.global_cc_argv.len);
            for (comp.global_cc_argv) |global_cc_arg| cs.test_exec_args.appendAssumeCapacity(global_cc_arg);
            if (cs.create_module.resolved_options.link_libcpp) try cs.test_exec_args.append(arena, "-lc++");
            if (cs.create_module.resolved_options.link_libc) {
                try cs.test_exec_args.append(arena, "-lc");
            } else if (target.os.tag == .windows) {
                try cs.test_exec_args.appendSlice(arena, &.{
                    "--subsystem", "console",
                    "-lkernel32",  "-lntdll",
                });
            }

            try cs.test_exec_args.ensureUnusedCapacity(arena, 2 * log_scopes.items.len + @intFromBool(cs.verbose_link) + @intFromBool(cs.verbose_cc));
            for (log_scopes.items) |log_scope| cs.test_exec_args.appendSliceAssumeCapacity(&.{ "--debug-log", log_scope });
            if (cs.verbose_link) cs.test_exec_args.appendAssumeCapacity("--verbose-link");
            if (cs.verbose_cc) cs.test_exec_args.appendAssumeCapacity("--verbose-cc");
        }

        try runOrTest(
            comp,
            gpa,
            arena,
            io,
            cs.test_exec_args.items,
            cs.self_exe_path_or_argv0,
            arg_mode,
            target,
            &comp_destroyed,
            all_args,
            cs.runtime_args_start,
            cs.create_module.resolved_options.link_libc,
            cs.test_execve,
            environ_map,
        );
    }

    // Skip resource deallocation in release builds; let the OS do it.
    return cleanExit(io);
}

const CreateModule = struct {
    dirs: std.zig.Directories,
    modules: std.array_hash_map.String(CliModule),
    opts: Compilation.Config.Options,
    object_format: ?[]const u8,
    /// undefined until createModule() for the root module is called.
    resolved_options: Compilation.Config,

    /// This one is used while collecting CLI options. The set of libs is used
    /// directly after computing the target and used to compute link_libc,
    /// link_libcpp, and then the libraries are filtered into
    /// `unresolved_link_inputs` and `windows_libs`.
    cli_link_inputs: std.ArrayList(link.UnresolvedInput),
    windows_libs: std.array_hash_map.String(void),
    /// The local variable `unresolved_link_inputs` is fed into library
    /// resolution, mutating the input array, and producing this data as
    /// output. Allocated with gpa.
    link_inputs: std.ArrayList(link.Input),

    c_source_files: std.ArrayList(Compilation.CSourceFile),
    rc_source_files: std.ArrayList(Compilation.RcSourceFile),

    /// e.g. -m3dnow or -mno-outline-atomics. They correspond to std.Target llvm cpu feature names.
    /// This array is populated by zig cc frontend and then has to be converted to zig-style
    /// CPU features.
    llvm_m_args: std.ArrayList([]const u8),
    sysroot: ?[]const u8,
    lib_directories: std.ArrayList(Directory),
    lib_dir_args: std.ArrayList([]const u8),
    libc_installation: ?LibCInstallation,
    want_native_include_dirs: bool,
    frameworks: std.array_hash_map.String(Framework),
    native_system_include_paths: []const []const u8,
    framework_dirs: std.ArrayList([]const u8),
    rpath_list: std.ArrayList([]const u8),
    each_lib_rpath: ?bool,
    libc_paths_file: ?[]const u8,
};

fn createModule(
    gpa: Allocator,
    arena: Allocator,
    io: Io,
    create_module: *CreateModule,
    index: usize,
    parent: ?*Module,
    color: std.zig.Color,
    environ_map: *process.Environ.Map,
) Allocator.Error!*Module {
    const cli_mod = &create_module.modules.values()[index];
    if (cli_mod.resolved) |m| return m;

    const name = create_module.modules.keys()[index];

    cli_mod.inherited.resolved_target = t: {
        // If the target is not overridden, use the parent's target. Of course,
        // if this is the root module then we need to proceed to resolve the
        // target.
        if (cli_mod.target_arch_os_abi == null and cli_mod.target_mcpu == null) {
            if (parent) |p| break :t p.resolved_target;
        }

        var target_parse_options: std.Target.Query.ParseOptions = .{
            .arch_os_abi = cli_mod.target_arch_os_abi orelse "native",
            .cpu_features = cli_mod.target_mcpu,
            .dynamic_linker = cli_mod.dynamic_linker,
            .object_format = create_module.object_format,
        };

        // Before passing the mcpu string in for parsing, we convert any -m flags that were
        // passed in via zig cc to zig-style.
        if (create_module.llvm_m_args.items.len != 0) {
            // If this returns null, we let it fall through to the case below which will
            // run the full parse function and do proper error handling.
            if (std.Target.Query.parseCpuArch(target_parse_options)) |cpu_arch| {
                var llvm_to_zig_name = std.StringHashMap([]const u8).init(gpa);
                defer llvm_to_zig_name.deinit();

                for (cpu_arch.allFeaturesList()) |feature| {
                    const llvm_name = feature.llvm_name orelse continue;
                    try llvm_to_zig_name.put(llvm_name, feature.name);
                }

                var mcpu_buffer = std.array_list.Managed(u8).init(gpa);
                defer mcpu_buffer.deinit();

                try mcpu_buffer.appendSlice(cli_mod.target_mcpu orelse "baseline");

                for (create_module.llvm_m_args.items) |llvm_m_arg| {
                    if (mem.cutPrefix(u8, llvm_m_arg, "mno-")) |llvm_name| {
                        const zig_name = llvm_to_zig_name.get(llvm_name) orelse {
                            fatal("target architecture {t} has no LLVM CPU feature named {q}", .{
                                cpu_arch, llvm_name,
                            });
                        };
                        try mcpu_buffer.append('-');
                        try mcpu_buffer.appendSlice(zig_name);
                    } else if (mem.cutPrefix(u8, llvm_m_arg, "m")) |llvm_name| {
                        const zig_name = llvm_to_zig_name.get(llvm_name) orelse {
                            fatal("target architecture {t} has no LLVM CPU feature named {q}", .{
                                cpu_arch, llvm_name,
                            });
                        };
                        try mcpu_buffer.append('+');
                        try mcpu_buffer.appendSlice(zig_name);
                    } else {
                        unreachable;
                    }
                }

                const adjusted_target_mcpu = try arena.dupe(u8, mcpu_buffer.items);
                std.log.debug("adjusted target_mcpu: {s}", .{adjusted_target_mcpu});
                target_parse_options.cpu_features = adjusted_target_mcpu;
            }
        }

        const target_query = std.zig.parseTargetQueryOrReportFatalError(arena, target_parse_options);
        const target = std.zig.resolveTargetQueryOrFatal(io, target_query);
        break :t .{
            .result = target,
            .is_native_os = target_query.isNativeOs(),
            .is_native_abi = target_query.isNativeAbi(),
            .is_explicit_dynamic_linker = target_query.dynamic_linker != null,
        };
    };

    if (parent == null) {
        // This block is for initializing the fields of
        // `Compilation.Config.Options` that require knowledge of the
        // target (which was just now resolved for the root module above).
        const resolved_target = &cli_mod.inherited.resolved_target.?;
        create_module.opts.resolved_target = resolved_target.*;
        create_module.opts.root_optimize_mode = cli_mod.inherited.optimize_mode;
        create_module.opts.root_strip = cli_mod.inherited.strip;
        create_module.opts.root_error_tracing = cli_mod.inherited.error_tracing;
        const target = &resolved_target.result;

        // First, remove libc, libc++, and compiler_rt libraries from the system libraries list.
        // We need to know whether the set of system libraries contains anything besides these
        // to decide whether to trigger native path detection logic.
        // Preserves linker input order.
        var unresolved_link_inputs: std.ArrayList(link.UnresolvedInput) = .empty;
        defer unresolved_link_inputs.deinit(gpa);
        try unresolved_link_inputs.ensureUnusedCapacity(gpa, create_module.cli_link_inputs.items.len);
        var any_name_queries_remaining = false;
        for (create_module.cli_link_inputs.items) |cli_link_input| switch (cli_link_input) {
            .name_query => |nq| {
                const lib_name = nq.name;

                if (std.zig.target.isLibCLibName(target, lib_name)) {
                    create_module.opts.link_libc = true;
                    continue;
                }
                if (std.zig.target.isLibCxxLibName(target, lib_name)) {
                    create_module.opts.link_libcpp = true;
                    continue;
                }

                switch (target_util.classifyCompilerRtLibName(lib_name)) {
                    .none => {},
                    .only_libunwind, .both => {
                        create_module.opts.link_libunwind = true;
                        continue;
                    },
                    .only_compiler_rt => continue,
                }

                if (target.isMinGW()) {
                    const exists = mingw.libExists(arena, io, target, create_module.dirs.zig_lib, lib_name) catch |err|
                        fatal("failed to check zig installation for DLL import libs: {t}", .{err});
                    if (exists) {
                        try create_module.windows_libs.put(arena, lib_name, {});
                        continue;
                    }
                }

                if (fs.path.isAbsolute(lib_name)) {
                    fatal("cannot use absolute path as a system library: {s}", .{lib_name});
                }

                unresolved_link_inputs.appendAssumeCapacity(cli_link_input);
                any_name_queries_remaining = true;
            },
            else => {
                unresolved_link_inputs.appendAssumeCapacity(cli_link_input);
            },
        }; // After this point, unresolved_link_inputs is used instead of cli_link_inputs.

        if (any_name_queries_remaining) create_module.want_native_include_dirs = true;

        // Resolve the library path arguments with respect to sysroot.
        try create_module.lib_directories.ensureUnusedCapacity(arena, create_module.lib_dir_args.items.len);
        if (create_module.sysroot) |root| {
            for (create_module.lib_dir_args.items) |lib_dir_arg| {
                if (fs.path.isAbsolute(lib_dir_arg)) {
                    const stripped_dir = lib_dir_arg[fs.path.parsePath(lib_dir_arg).root.len..];
                    const full_path = try fs.path.join(arena, &[_][]const u8{ root, stripped_dir });
                    addLibDirectoryWarn(io, &create_module.lib_directories, full_path);
                } else {
                    addLibDirectoryWarn(io, &create_module.lib_directories, lib_dir_arg);
                }
            }
        } else {
            for (create_module.lib_dir_args.items) |lib_dir_arg| {
                addLibDirectoryWarn(io, &create_module.lib_directories, lib_dir_arg);
            }
        }
        create_module.lib_dir_args = undefined; // From here we use lib_directories instead.

        if (resolved_target.is_native_os and target.os.tag.isDarwin()) {
            // If we want to link against frameworks, we need system headers.
            if (create_module.frameworks.count() > 0)
                create_module.want_native_include_dirs = true;
        }

        if (create_module.each_lib_rpath orelse resolved_target.is_native_os) {
            try create_module.rpath_list.ensureUnusedCapacity(arena, create_module.lib_directories.items.len);
            for (create_module.lib_directories.items) |lib_directory| {
                create_module.rpath_list.appendAssumeCapacity(lib_directory.path.?);
            }
        }

        // Trigger native system library path detection if necessary.
        if (create_module.sysroot == null and
            resolved_target.is_native_os and resolved_target.is_native_abi and
            create_module.want_native_include_dirs)
        {
            var paths = std.zig.system.NativePaths.detect(arena, io, target, environ_map) catch |err|
                fatal("unable to detect native system paths: {t}", .{err});
            for (paths.warnings.items) |warning| {
                warn("{s}", .{warning});
            }

            create_module.native_system_include_paths = try paths.include_dirs.toOwnedSlice(arena);

            try create_module.framework_dirs.appendSlice(arena, paths.framework_dirs.items);
            try create_module.rpath_list.appendSlice(arena, paths.rpaths.items);

            try create_module.lib_directories.ensureUnusedCapacity(arena, paths.lib_dirs.items.len);
            for (paths.lib_dirs.items) |path| addLibDirectoryWarn2(io, &create_module.lib_directories, path, true);
        }

        if (create_module.libc_paths_file) |paths_file| {
            create_module.libc_installation = LibCInstallation.parse(arena, io, paths_file, target) catch |err|
                fatal("unable to parse libc paths file at path {s}: {t}", .{ paths_file, err });
        }

        if (target.os.tag == .windows and (target.abi == .msvc or target.abi == .itanium) and
            any_name_queries_remaining)
        {
            if (create_module.libc_installation == null) {
                create_module.libc_installation = LibCInstallation.findNative(arena, io, .{
                    .verbose = true,
                    .target = target,
                    .environ_map = environ_map,
                }) catch |err| {
                    fatal("unable to find native libc installation: {t}", .{err});
                };
            }
            try create_module.lib_directories.ensureUnusedCapacity(arena, 2);
            addLibDirectoryWarn(io, &create_module.lib_directories, create_module.libc_installation.?.msvc_lib_dir.?);
            addLibDirectoryWarn(io, &create_module.lib_directories, create_module.libc_installation.?.kernel32_lib_dir.?);
        }

        // Destructively mutates but does not transfer ownership of `unresolved_link_inputs`.
        link.resolveInputs(
            gpa,
            arena,
            io,
            target,
            &unresolved_link_inputs,
            &create_module.link_inputs,
            create_module.lib_directories.items,
            color,
        ) catch |err| fatal("failed to resolve link inputs: {s}", .{@errorName(err)});

        if (!create_module.opts.any_dyn_libs) for (create_module.link_inputs.items) |item| switch (item) {
            .dso, .dso_exact => {
                create_module.opts.any_dyn_libs = true;
                break;
            },
            else => {},
        };

        create_module.resolved_options = Compilation.Config.resolve(create_module.opts) catch |err| switch (err) {
            error.WasiExecModelRequiresWasi => fatal("only WASI OS targets support execution model", .{}),
            error.SharedMemoryIsWasmOnly => fatal("only WebAssembly CPU targets support shared memory", .{}),
            error.ObjectFilesCannotShareMemory => fatal("object files cannot share memory", .{}),
            error.SharedMemoryRequiresAtomicsAndBulkMemory => fatal("shared memory requires atomics and bulk_memory CPU features", .{}),
            error.ThreadsRequireSharedMemory => fatal("threads require shared memory", .{}),
            error.EmittingLlvmModuleRequiresLlvmBackend => fatal("emitting an LLVM module requires using the LLVM backend", .{}),
            error.LlvmLacksTargetSupport => fatal("LLVM lacks support for the specified target", .{}),
            error.ZigLacksTargetSupport => fatal("compiler backend unavailable for the specified target", .{}),
            error.EmittingBinaryRequiresLlvmLibrary => fatal("producing machine code via LLVM requires using the LLVM library", .{}),
            error.LldIncompatibleObjectFormat => fatal("using LLD to link {s} files is unsupported", .{@tagName(target.ofmt)}),
            error.LldIncompatibleWithSelfHostedBackend => fatal("self-hosted backends do not support linking with LLD", .{}),
            error.LtoRequiresLld => fatal("LTO requires using LLD", .{}),
            error.SanitizeThreadRequiresLibCpp => fatal("thread sanitization is (for now) implemented in C++, so it requires linking libc++", .{}),
            error.LibCRequiresLibUnwind => fatal("libc of the specified target requires linking libunwind", .{}),
            error.LibCppRequiresLibUnwind => fatal("libc++ requires linking libunwind", .{}),
            error.LibCppRequiresLibC => fatal("libc++ requires linking libc", .{}),
            error.LibUnwindRequiresLibC => fatal("libunwind requires linking libc", .{}),
            error.TargetCannotDynamicLink => fatal("dynamic linking unavailable on the specified target", .{}),
            error.TargetCannotStaticLinkExecutables => fatal("static linking of executables unavailable on the specified target", .{}),
            error.LibCRequiresDynamicLinking => fatal("libc of the specified target requires dynamic linking", .{}),
            error.SharedLibrariesRequireDynamicLinking => fatal("using shared libraries requires dynamic linking", .{}),
            error.DynamicLinkingWithLldRequiresSharedLibraries => fatal("dynamic linking with lld requires at least one shared library", .{}),
            error.ExportMemoryAndDynamicIncompatible => fatal("exporting memory is incompatible with dynamic linking", .{}),
            error.DynamicLibraryPrecludesPie => fatal("dynamic libraries cannot be position independent executables", .{}),
            error.TargetRequiresPie => fatal("the specified target requires position independent executables", .{}),
            error.SanitizeThreadRequiresPie => fatal("thread sanitization requires position independent executables", .{}),
            error.SanitizeThreadRequiresLlvmBackend => fatal("thread sanitization requires the LLVM backend", .{}),
            error.BackendLacksErrorTracing => fatal("the selected backend has not yet implemented error return tracing", .{}),
            error.LlvmLibraryUnavailable => fatal("zig was compiled without LLVM libraries", .{}),
            error.LldUnavailable => fatal("zig was compiled without LLD libraries", .{}),
            error.ClangUnavailable => fatal("zig was compiled without Clang libraries", .{}),
            error.DllExportFnsRequiresWindows => fatal("only Windows OS targets support DLLs", .{}),
            error.NewLinkerIncompatibleWithLld => fatal("using the new linker is incompatible with using lld", .{}),
            error.NewLinkerIncompatibleObjectFormat => fatal("no new linker available for '{t}' files", .{target.ofmt}),
        };
    }

    const root: Compilation.Path = try .fromUnresolved(arena, create_module.dirs, &.{cli_mod.root_path});

    const mod = Module.create(arena, .{
        .paths = .{
            .root = root,
            .root_src_path = cli_mod.root_src_path,
        },
        .fully_qualified_name = name,

        .cc_argv = cli_mod.cc_argv,
        .inherited = cli_mod.inherited,
        .global = create_module.resolved_options,
        .parent = parent,
    }) catch |err| switch (err) {
        error.ValgrindUnsupportedOnTarget => fatal("unable to create module {q}: valgrind does not support the selected target CPU architecture", .{name}),
        error.TargetRequiresSingleThreaded => fatal("unable to create module {q}: the selected target does not support multithreading", .{name}),
        error.BackendRequiresSingleThreaded => fatal("unable to create module {q}: the selected machine code backend is limited to single-threaded applications", .{name}),
        error.TargetRequiresPic => fatal("unable to create module {q}: the selected target requires position independent code", .{name}),
        error.PieRequiresPic => fatal("unable to create module {q}: making a Position Independent Executable requires enabling Position Independent Code", .{name}),
        error.DynamicLinkingRequiresPic => fatal("unable to create module {q}: dynamic linking requires enabling Position Independent Code", .{name}),
        error.TargetHasNoRedZone => fatal("unable to create module {q}: the selected target does not have a red zone", .{name}),
        error.StackCheckUnsupportedByTarget => fatal("unable to create module {q}: the selected target does not support stack checking", .{name}),
        error.StackProtectorUnsupportedByTarget => fatal("unable to create module {q}: the selected target does not support stack protection", .{name}),
        error.StackProtectorUnavailableWithoutLibC => fatal("unable to create module {q}: enabling stack protection requires libc", .{name}),
        error.OutOfMemory => |e| return e,
    };
    cli_mod.resolved = mod;

    for (create_module.c_source_files.items[cli_mod.c_source_files_start..cli_mod.c_source_files_end]) |*item| item.owner = mod;

    for (create_module.rc_source_files.items[cli_mod.rc_source_files_start..cli_mod.rc_source_files_end]) |*item| item.owner = mod;

    for (cli_mod.deps) |dep| {
        const dep_index = create_module.modules.getIndex(dep.value) orelse
            fatal("module {q} depends on non-existent module {q}", .{ name, dep.key });
        const dep_mod = try createModule(gpa, arena, io, create_module, dep_index, mod, color, environ_map);
        try mod.deps.put(arena, dep.key, dep_mod);
    }

    return mod;
}

fn saveState(comp: *Compilation, incremental: bool) void {
    if (incremental) {
        comp.saveState() catch |err| warn("unable to save incremental compilation state: {t}", .{err});
    }
}

fn serve(
    comp: *Compilation,
    in: *Io.Reader,
    out: *Io.Writer,
    test_exec_args: []const ?[]const u8,
    self_exe_path: switch (native_os) {
        .wasi => void,
        else => []const u8,
    },
    arg_mode: ArgMode,
    all_args: []const []const u8,
    runtime_args_start: ?usize,
    environ_map: *process.Environ.Map,
) !void {
    const gpa = comp.gpa;
    const io = comp.io;

    var server: Server = .{ .in = in, .out = out };
    try server.serveStringMessage(.zig_version, build_options.version);

    var child_pid: ?std.process.Child.Id = null;

    const main_progress_node = std.Progress.start(io, .{});
    defer main_progress_node.end();

    const file_system_inputs = comp.file_system_inputs.?;

    const IncrementalDebugServer = if (build_options.enable_debug_extensions and !builtin.single_threaded)
        @import("IncrementalDebugServer.zig")
    else
        void;

    var ids: IncrementalDebugServer = if (comp.debugIncremental()) ids: {
        break :ids .init(comp.zcu orelse @panic("--debug-incremental requires a ZCU"));
    } else undefined;
    defer if (comp.debugIncremental()) ids.deinit();

    if (comp.debugIncremental()) ids.spawn();

    while (true) {
        const hdr = try server.receiveMessage();

        // Lock the debug server while handling the message.
        if (comp.debugIncremental()) try ids.mutex.lock(io);
        defer if (comp.debugIncremental()) ids.mutex.unlock(io);

        switch (hdr.tag) {
            .exit => return cleanExit(io),
            .update => {
                file_system_inputs.clearRetainingCapacity();

                if (arg_mode == .translate_c) {
                    var arena_instance = std.heap.ArenaAllocator.init(gpa);
                    defer arena_instance.deinit();
                    const arena = arena_instance.allocator();
                    var output: Compilation.TranslateCResult = undefined;
                    try cmdTranslateC(comp, arena, &output, file_system_inputs, main_progress_node, environ_map);
                    defer output.deinit(gpa);

                    if (file_system_inputs.items.len != 0) {
                        try server.serveStringMessage(.file_system_inputs, file_system_inputs.items);
                    }

                    if (output.errors.errorMessageCount() != 0) {
                        try server.serveErrorBundle(output.errors);
                    } else {
                        try server.serveEmitDigest(&output.digest, .{
                            .flags = .{ .cache_hit = output.cache_hit },
                        });
                    }

                    continue;
                }

                if (comp.config.output_mode == .Exe) {
                    try comp.makeBinFileWritable();
                }

                try comp.update(main_progress_node);

                try comp.makeBinFileExecutable();
                try serveUpdateResults(&server, comp);
            },
            .run => {
                if (child_pid != null) {
                    @panic("TODO block until the child exits");
                }
                @panic("TODO call runOrTest");
                //try runOrTest(
                //    comp,
                //    gpa,
                //    arena,
                //    io,
                //    test_exec_args,
                //    self_exe_path.?,
                //    arg_mode,
                //    target,
                //    true,
                //    &comp_destroyed,
                //    all_args,
                //    runtime_args_start,
                //    link_libc,
                //);
            },
            .hot_update => {
                file_system_inputs.clearRetainingCapacity();
                if (child_pid) |pid| {
                    try comp.hotCodeSwap(main_progress_node, pid);
                    try serveUpdateResults(&server, comp);
                } else {
                    if (comp.config.output_mode == .Exe) {
                        try comp.makeBinFileWritable();
                    }
                    try comp.update(main_progress_node);
                    try comp.makeBinFileExecutable();
                    try serveUpdateResults(&server, comp);

                    child_pid = try runOrTestHotSwap(
                        comp,
                        gpa,
                        test_exec_args,
                        self_exe_path,
                        arg_mode,
                        all_args,
                        runtime_args_start,
                    );
                }
            },
            else => {
                fatal("unrecognized message from client: 0x{x}", .{@backingInt(hdr.tag)});
            },
        }
    }
}

fn serveUpdateResults(s: *Server, comp: *Compilation) !void {
    const gpa = comp.gpa;

    var error_bundle = try comp.getAllErrorsAlloc();
    defer error_bundle.deinit(gpa);

    if (comp.file_system_inputs) |file_system_inputs| {
        if (file_system_inputs.items.len == 0) {
            assert(error_bundle.errorMessageCount() > 0);
        } else {
            try s.serveStringMessage(.file_system_inputs, file_system_inputs.items);
        }
    }

    if (comp.time_report) |*tr| {
        var decls_len: u32 = 0;

        var file_name_bytes: std.ArrayList(u8) = .empty;
        defer file_name_bytes.deinit(gpa);
        var files: std.array_hash_map.Auto(Zcu.File.Index, void) = .empty;
        defer files.deinit(gpa);
        var decl_data: std.ArrayList(u8) = .empty;
        defer decl_data.deinit(gpa);

        // Each decl needs at least 34 bytes:
        // * 2 for 1-byte name plus null terminator
        // * 4 for `file`
        // * 4 for `sema_count`
        // * 8 for `sema_ns`
        // * 8 for `codegen_ns`
        // * 8 for `link_ns`
        // Most, if not all, decls in `tr.decl_sema_ns` are valid, so we have a good size estimate.
        try decl_data.ensureUnusedCapacity(gpa, tr.decl_sema_info.count() * 34);

        for (tr.decl_sema_info.keys(), tr.decl_sema_info.values()) |tracked_inst, sema_info| {
            const resolved = tracked_inst.resolveFull(&comp.zcu.?.intern_pool) orelse continue;
            const file = comp.zcu.?.fileByIndex(resolved.file);
            const zir = file.zir orelse continue;
            const decl_name = zir.nullTerminatedString(zir.getDeclaration(resolved.inst).name);

            const gop = try files.getOrPut(gpa, resolved.file);
            if (!gop.found_existing) try file_name_bytes.print(gpa, "{f}\x00", .{file.path.fmt(comp)});

            const codegen_ns = tr.decl_codegen_ns.get(tracked_inst) orelse 0;
            const link_ns = tr.decl_link_ns.get(tracked_inst) orelse 0;

            decls_len += 1;

            try decl_data.ensureUnusedCapacity(gpa, 33 + decl_name.len);
            decl_data.appendSliceAssumeCapacity(decl_name);
            decl_data.appendAssumeCapacity(0);

            const out_file = decl_data.addManyAsArrayAssumeCapacity(4);
            const out_sema_count = decl_data.addManyAsArrayAssumeCapacity(4);
            const out_sema_ns = decl_data.addManyAsArrayAssumeCapacity(8);
            const out_codegen_ns = decl_data.addManyAsArrayAssumeCapacity(8);
            const out_link_ns = decl_data.addManyAsArrayAssumeCapacity(8);
            std.mem.writeInt(u32, out_file, @intCast(gop.index), .little);
            std.mem.writeInt(u32, out_sema_count, sema_info.count, .little);
            std.mem.writeInt(u64, out_sema_ns, sema_info.ns, .little);
            std.mem.writeInt(u64, out_codegen_ns, codegen_ns, .little);
            std.mem.writeInt(u64, out_link_ns, link_ns, .little);
        }

        const header: std.zig.Server.Message.TimeReport = .{
            .stats = tr.stats,
            .llvm_pass_timings_len = @intCast(tr.llvm_pass_timings.len),
            .files_len = @intCast(files.count()),
            .decls_len = decls_len,
            .flags = .{
                .use_llvm = comp.zcu != null and comp.zcu.?.llvm_object != null,
            },
        };

        var slices: [4][]const u8 = .{
            @ptrCast(&header),
            tr.llvm_pass_timings,
            file_name_bytes.items,
            decl_data.items,
        };
        try s.serveMessageHeader(.{
            .tag = .time_report,
            .bytes_len = len: {
                var len: u32 = 0;
                for (slices) |slice| len += @intCast(slice.len);
                break :len len;
            },
        });
        try s.out.writeVecAll(&slices);
        try s.out.flush();
    }

    if (error_bundle.errorMessageCount() > 0) {
        try s.serveErrorBundle(error_bundle);
        return;
    }

    if (comp.digest) |digest| {
        try s.serveEmitDigest(&digest, .{
            .flags = .{ .cache_hit = comp.last_update_was_cache_hit },
        });
    }

    // Serve empty error bundle to indicate the update is done.
    try s.serveErrorBundle(std.zig.ErrorBundle.empty);
}

fn runOrTest(
    comp: *Compilation,
    gpa: Allocator,
    arena: Allocator,
    io: Io,
    test_exec_args: []const ?[]const u8,
    self_exe_path: []const u8,
    arg_mode: ArgMode,
    target: *const std.Target,
    comp_destroyed: *bool,
    all_args: []const []const u8,
    runtime_args_start: ?usize,
    link_libc: bool,
    test_execve: bool,
    environ_map: *process.Environ.Map,
) !void {
    const raw_emit_bin = comp.emit_bin orelse return;
    const exe_path = switch (comp.cache_use) {
        .none => p: {
            if (fs.path.isAbsolute(raw_emit_bin)) break :p raw_emit_bin;
            // Use `fs.path.join` to make a file in the cwd is still executed properly.
            break :p try fs.path.join(arena, &.{
                ".",
                raw_emit_bin,
            });
        },
        .whole, .incremental => try comp.dirs.local_cache.join(arena, &.{
            "o",
            &Cache.binToHex(comp.digest.?),
            raw_emit_bin,
        }),
    };

    var argv = std.array_list.Managed([]const u8).init(gpa);
    defer argv.deinit();

    if (test_exec_args.len == 0) {
        try argv.append(exe_path);
        if (arg_mode == .zig_test) {
            try argv.append(
                try arena.print("--seed=0x{x}", .{randInt(io, u32)}),
            );
        }
    } else {
        for (test_exec_args) |arg| {
            try argv.append(arg orelse exe_path);
        }
    }
    if (runtime_args_start) |i| {
        try argv.appendSlice(all_args[i..]);
    }
    try environ_map.put("ZIG_EXE", self_exe_path);

    // We do not execve for tests because if the test fails we want to print
    // the error message and invocation below.
    if (process.can_replace and (arg_mode == .run or (arg_mode == .zig_test and test_execve))) {
        // process replacement releases the locks; no need to destroy the Compilation here.
        _ = try io.lockStderr(&.{}, .no_color);
        const err = process.replace(io, .{ .argv = argv.items, .environ_map = environ_map });
        io.unlockStderr();
        try warnAboutForeignBinaries(io, arena, arg_mode, target, link_libc);
        const cmd = try std.mem.join(arena, " ", argv.items);
        fatal("the following command failed to execve with '{t}':\n{s}", .{ err, cmd });
    } else if (!process.can_spawn) {
        fatal("the following command cannot be executed ({t} does not support spawning a child process):\n{f}", .{
            native_os, std.zig.SubprocessCommand{ .argv = argv.items },
        });
    }
    const term_result = (term: {
        // Here we release all the locks associated with the Compilation so
        // that whatever this child process wants to do won't deadlock.
        comp.destroy();
        comp_destroyed.* = true;

        _ = try io.lockStderr(&.{}, .no_color);
        defer io.unlockStderr();

        var child = std.process.spawn(io, .{
            .argv = argv.items,
            .environ_map = environ_map,
            .stdin = .inherit,
            .stdout = .inherit,
            .stderr = .inherit,
        }) catch |err| break :term err;
        defer child.kill(io);

        break :term child.wait(io);
    });

    const term = term_result catch |err| {
        try warnAboutForeignBinaries(io, arena, arg_mode, target, link_libc);
        const cmd = try std.mem.join(arena, " ", argv.items);
        fatal("the following command failed with {t}:\n{s}", .{ err, cmd });
    };
    switch (arg_mode) {
        .run, .build => {
            switch (term) {
                .exited => |code| {
                    if (code == 0) {
                        return cleanExit(io);
                    } else {
                        process.exit(code);
                    }
                },
                .signal => |sig| {
                    const cmd = try std.mem.join(arena, " ", argv.items);
                    fatal("the following command terminated with signal {t}:\n{s}", .{ sig, cmd });
                },
                .stopped => |sig| {
                    const cmd = try std.mem.join(arena, " ", argv.items);
                    fatal("the following command stopped with signal {t}:\n{s}", .{ sig, cmd });
                },
                .unknown => {
                    process.exit(1);
                },
            }
        },
        .zig_test => {
            switch (term) {
                .exited => |code| {
                    if (code == 0) {
                        return cleanExit(io);
                    } else {
                        const cmd = try std.mem.join(arena, " ", argv.items);
                        fatal("the following test command failed with exit code {d}:\n{s}", .{ code, cmd });
                    }
                },
                .signal => |sig| {
                    const cmd = try std.mem.join(arena, " ", argv.items);
                    fatal("the following test command terminated with signal {t}:\n{s}", .{ sig, cmd });
                },
                else => {
                    const cmd = try std.mem.join(arena, " ", argv.items);
                    fatal("the following test command crashed:\n{s}", .{cmd});
                },
            }
        },
        else => unreachable,
    }
}

fn runOrTestHotSwap(
    comp: *Compilation,
    gpa: Allocator,
    test_exec_args: []const ?[]const u8,
    self_exe_path: switch (native_os) {
        .wasi => void,
        else => []const u8,
    },
    arg_mode: ArgMode,
    all_args: []const []const u8,
    runtime_args_start: ?usize,
) !std.process.Child.Id {
    const io = comp.io;
    const lf = comp.bin_file.?;

    const self_exe_path_or_argv0 = switch (native_os) {
        .wasi => all_args[0], // Will error because of `!process.can_spawn`
        else => self_exe_path,
    };

    const exe_path = switch (builtin.target.os.tag) {
        // On Windows it seems impossible to perform an atomic rename of a file that is currently
        // running in a process. Therefore, we do the opposite. We create a copy of the file in
        // tmp zig-cache and use it to spawn the child process. This way we are free to update
        // the binary with each requested hot update.
        .windows => blk: {
            try lf.emit.root_dir.handle.copyFile(lf.emit.sub_path, comp.dirs.local_cache.handle, lf.emit.sub_path, io, .{});
            break :blk try fs.path.join(gpa, &.{ comp.dirs.local_cache.path orelse ".", lf.emit.sub_path });
        },

        // A naive `directory.join` here will indeed get the correct path to the binary,
        // however, in the case of cwd, we actually want `./foo` so that the path can be executed.
        else => try fs.path.join(gpa, &.{
            lf.emit.root_dir.path orelse ".", lf.emit.sub_path,
        }),
    };
    defer gpa.free(exe_path);

    var argv = std.array_list.Managed([]const u8).init(gpa);
    defer argv.deinit();

    if (test_exec_args.len == 0) {
        // when testing pass the zig_exe_path to argv
        if (arg_mode == .zig_test)
            try argv.appendSlice(&[_][]const u8{
                exe_path, self_exe_path_or_argv0,
            })
            // when running just pass the current exe
        else
            try argv.appendSlice(&[_][]const u8{
                exe_path,
            });
    } else {
        for (test_exec_args) |arg| {
            if (arg) |a| {
                try argv.append(a);
            } else {
                try argv.appendSlice(&[_][]const u8{
                    exe_path, self_exe_path_or_argv0,
                });
            }
        }
    }
    if (runtime_args_start) |i| {
        try argv.appendSlice(all_args[i..]);
    }

    if (!process.can_spawn) {
        fatal("the following command cannot be executed ({t} does not support spawning a child process):\n{f}", .{
            native_os, std.zig.SubprocessCommand{ .argv = argv.items },
        });
    }

    const child = try std.process.spawn(io, .{
        .argv = argv.items,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    });
    return child.id.?;
}

const UpdateModuleError = Compilation.UpdateError || error{
    /// The update caused compile errors. The error bundle has already been
    /// reported to the user by being rendered to stderr.
    CompileErrorsReported,
    /// Error occurred printing compilation errors to stderr.
    PrintingErrorsFailed,
};
fn updateModule(comp: *Compilation, color: Color, prog_node: std.Progress.Node) UpdateModuleError!void {
    try comp.update(prog_node);

    var errors = try comp.getAllErrorsAlloc();
    defer errors.deinit(comp.gpa);

    if (errors.errorMessageCount() > 0) {
        const io = comp.io;
        errors.renderToStderr(io, .{}, color) catch |err| switch (err) {
            error.Canceled => |e| return e,
            else => return error.PrintingErrorsFailed,
        };
        return error.CompileErrorsReported;
    }
}

fn cmdTranslateC(
    comp: *Compilation,
    arena: Allocator,
    fancy_output: ?*Compilation.TranslateCResult,
    file_system_inputs: ?*std.ArrayList(u8),
    prog_node: std.Progress.Node,
    environ_map: *process.Environ.Map,
) !void {
    dev.check(.translate_c_command);

    const io = comp.io;

    assert(comp.c_source_files.len == 1);
    const c_source_file = comp.c_source_files[0];

    const translated_basename = try arena.print("{s}.zig", .{comp.root_name});

    var man: Cache.Manifest = comp.obtainCObjectCacheManifest(comp.root_mod);
    man.want_shared_lock = false;
    defer man.deinit();

    man.hash.add(@as(u16, 0xb945)); // Random number to distinguish translate-c from compiling C objects
    Compilation.cache_helpers.hashCSource(&man, c_source_file) catch |err|
        fatal("unable to process {q}: {t}", .{ c_source_file.src_path, err });

    const result: Compilation.TranslateCResult = if (try man.hit(prog_node)) .{
        .digest = man.finalBin(),
        .cache_hit = true,
        .errors = std.zig.ErrorBundle.empty,
    } else result: {
        const result = try comp.translateC(
            arena,
            &man,
            Compilation.classifyFileExt(c_source_file.src_path),
            c_source_file.src_path,
            translated_basename,
            comp.root_mod,
            prog_node,
            environ_map,
        );

        if (result.errors.errorMessageCount() != 0) {
            if (fancy_output) |p| {
                if (file_system_inputs) |buf| try man.populateFileSystemInputs(buf);
                p.* = result;
                return;
            } else {
                const color: Color = Color.settingFromEnvironment(environ_map);
                result.errors.renderToStderr(io, .{}, color) catch {};
                process.exit(1);
            }
        }

        man.writeManifest() catch |err| warn("failed to write cache manifest: {t}", .{err});
        break :result result;
    };

    if (file_system_inputs) |buf| try man.populateFileSystemInputs(buf);
    if (fancy_output) |p| {
        p.* = result;
    } else {
        const hex_digest = Cache.binToHex(result.digest);
        const out_zig_path = try fs.path.join(arena, &.{ "o", &hex_digest, translated_basename });
        const zig_file = comp.dirs.local_cache.handle.openFile(io, out_zig_path, .{}) catch |err| {
            const path = comp.dirs.local_cache.path orelse ".";
            fatal("unable to open cached translated zig file '{s}{s}{s}': {t}", .{
                path, fs.path.sep_str, out_zig_path, err,
            });
        };
        defer zig_file.close(io);
        var stdout_writer = Io.File.stdout().writer(io, &stdout_buffer);
        var file_reader = zig_file.reader(io, &.{});
        _ = try stdout_writer.interface.sendFileAll(&file_reader, .unlimited);
        try stdout_writer.interface.flush();
        return cleanExit(io);
    }
}

pub fn translateC(
    gpa: Allocator,
    arena: Allocator,
    io: Io,
    argv: []const []const u8,
    environ_map: *const process.Environ.Map,
    prog_node: std.Progress.Node,
    thread_limit: usize,
    capture: ?*[]u8,
    lsp_doc_store: ?*lsp_server.DocumentStore,
) !void {
    try jitCmdInner(gpa, arena, io, argv, environ_map, prog_node, thread_limit, lsp_doc_store, .{
        .cmd_name = "translate-c",
        .root_src_path = "translate-c/main.zig",
        .depend_on_aro = true,
        .capture = capture,
    });
}

const JitCmdOptions = struct {
    cmd_name: []const u8,
    root_src_path: []const u8,
    prepend_cmd: ?[]const u8 = null,
    prepend_zig_lib_dir_path: bool = false,
    prepend_global_cache_path: bool = false,
    prepend_zig_exe_path: bool = false,
    prepend_seed: bool = false,
    depend_on_aro: bool = false,
    capture: ?*[]u8 = null,
    /// Send error bundles via std.zig.Server over stdout
    server: bool = false,
    release_mode: std.lang.Optimize = .fast,
};

fn jitCmd(
    gpa: Allocator,
    arena: Allocator,
    io: Io,
    args: []const []const u8,
    environ_map: *const process.Environ.Map,
    options: JitCmdOptions,
) !void {
    dev.check(.jit_command);

    const color = Color.settingFromEnvironment(environ_map);

    const root_prog_node = std.Progress.start(io, .{
        .disable_printing = (color == .off),
        .root_name = try arena.print("Compiling {s} (first time setup)", .{options.cmd_name}),
    });
    defer root_prog_node.end();

    const thread_limit = @min(
        @max(std.Thread.getCpuCount() catch 1, 1),
        std.math.maxInt(Zcu.PerThread.IdBacking),
    );
    try setThreadLimit(arena, thread_limit, globals.io_impl_ptr);

    return jitCmdInner(gpa, arena, io, args, environ_map, root_prog_node, thread_limit, null, options);
}

fn jitCmdInner(
    gpa: Allocator,
    arena: Allocator,
    io: Io,
    args: []const []const u8,
    environ_map: *const process.Environ.Map,
    root_prog_node: std.Progress.Node,
    thread_limit: usize,
    lsp_doc_store: ?*lsp_server.DocumentStore,
    options: JitCmdOptions,
) !void {
    if (!std.process.can_spawn) {
        fatal("The {s} command cannot be executed ({t} does not support spawning a child process)", .{
            options.cmd_name, native_os,
        });
    }

    const target_query: std.Target.Query = .{};
    const resolved_target: Module.ResolvedTarget = .{
        .result = std.zig.resolveTargetQueryOrFatal(io, target_query),
        .is_native_os = true,
        .is_native_abi = true,
        .is_explicit_dynamic_linker = false,
    };

    const self_exe_path = process.executablePathAlloc(io, arena) catch |err|
        fatal("unable to find self exe path: {t}", .{err});

    const optimize_mode: std.lang.Optimize = if (EnvVar.ZIG_DEBUG_CMD.isSet(environ_map))
        .debug
    else
        options.release_mode;
    const strip = optimize_mode != .debug;
    var override_lib_dir: ?[]const u8 = EnvVar.ZIG_LIB_DIR.get(environ_map);
    const override_global_cache_dir: ?[]const u8 = EnvVar.ZIG_GLOBAL_CACHE_DIR.get(environ_map);

    // Special case: if first arg starts with --zig-lib= then it is handled here.
    var args_i: usize = 0;
    if (args.len - args_i != 0) {
        if (mem.cutPrefix(u8, args[args_i], "--zig-lib=")) |rest| {
            override_lib_dir = rest;
            args_i += 1;
        }
    }

    const cwd_path = try std.zig.getResolvedCwd(io, arena);

    // This `init` calls `fatal` on error.
    var dirs: std.zig.Directories = .init(
        arena,
        io,
        override_lib_dir,
        override_global_cache_dir,
        .global,
        preopens,
        self_exe_path,
        environ_map,
        cwd_path,
    );
    defer dirs.deinit(io);

    var child_argv: std.ArrayList([]const u8) = .empty;
    try child_argv.ensureUnusedCapacity(arena, (args.len - args_i) + 6);

    // We want to release all the locks before executing the child process, so we make a nice
    // big block here to ensure the cleanup gets run when we extract out our argv.
    if (lsp_doc_store == null) {
        const main_mod_paths: Module.CreateOptions.Paths = .{
            .root = try .fromRoot(arena, dirs, .zig_lib, "compiler"),
            .root_src_path = options.root_src_path,
        };

        const config = try Compilation.Config.resolve(.{
            .output_mode = .Exe,
            .root_strip = strip,
            .root_optimize_mode = optimize_mode,
            .resolved_target = resolved_target,
            .have_zcu = true,
            .emit_bin = true,
            .is_test = false,
        });

        const root_mod = try Module.create(arena, .{
            .paths = main_mod_paths,
            .fully_qualified_name = "root",
            .cc_argv = &.{},
            .inherited = .{
                .resolved_target = resolved_target,
                .optimize_mode = optimize_mode,
                .strip = strip,
            },
            .global = config,
            .parent = null,
        });

        if (options.depend_on_aro) {
            const aro_mod = try Module.create(arena, .{
                .paths = .{
                    .root = try .fromRoot(arena, dirs, .zig_lib, "compiler/aro"),
                    .root_src_path = "aro.zig",
                },
                .fully_qualified_name = "aro",
                .cc_argv = &.{},
                .inherited = .{
                    .resolved_target = resolved_target,
                    .optimize_mode = optimize_mode,
                    .strip = strip,
                },
                .global = config,
                .parent = null,
            });
            try root_mod.deps.put(arena, "aro", aro_mod);
            const aro_compiler_util_mod = try Module.create(arena, .{
                .paths = .{
                    .root = try .fromRoot(arena, dirs, .zig_lib, "compiler"),
                    .root_src_path = "util.zig",
                },
                .fully_qualified_name = "aro-compiler-util",
                .cc_argv = &.{},
                .inherited = .{
                    .resolved_target = resolved_target,
                    .optimize_mode = optimize_mode,
                    .strip = strip,
                },
                .global = config,
                .parent = null,
            });
            try aro_compiler_util_mod.deps.put(arena, "aro", aro_mod);
            try root_mod.deps.put(arena, "aro-compiler-util", aro_compiler_util_mod);
        }

        var create_diag: Compilation.CreateDiagnostic = undefined;
        const comp = Compilation.create(gpa, arena, io, &create_diag, .{
            .dirs = dirs,
            .root_name = options.cmd_name,
            .config = config,
            .root_mod = root_mod,
            .main_mod = root_mod,
            .emit_bin = .yes_cache,
            .self_exe_path = self_exe_path,
            .thread_limit = thread_limit,
            .cache_mode = .whole,
            .environ_map = environ_map,
        }) catch |err| switch (err) {
            error.CreateFail => fatal("failed to create compilation: {f}", .{create_diag}),
            else => fatal("failed to create compilation: {t}", .{err}),
        };
        defer comp.destroy();

        if (options.server) {
            var stdout_writer = Io.File.stdout().writer(io, &stdout_buffer);
            var server: std.zig.Server = .{
                .out = &stdout_writer.interface,
                .in = undefined, // won't be receiving messages
            };

            try comp.update(root_prog_node);

            var error_bundle = try comp.getAllErrorsAlloc();
            defer error_bundle.deinit(comp.gpa);
            if (error_bundle.errorMessageCount() > 0) {
                try server.serveErrorBundle(error_bundle);
                process.exit(2);
            }
        } else {
            const color = Color.settingFromEnvironment(environ_map);
            updateModule(comp, color, root_prog_node) catch |err| switch (err) {
                error.CompileErrorsReported => process.exit(2),
                else => |e| return e,
            };
        }

        const exe_path = try dirs.global_cache.join(arena, &.{
            "o",
            &Cache.binToHex(comp.digest.?),
            comp.emit_bin.?,
        });
        child_argv.appendAssumeCapacity(exe_path);
    } else {
        child_argv.appendAssumeCapacity(self_exe_path);
        child_argv.appendAssumeCapacity("aro");
    }

    if (options.prepend_cmd) |cmd|
        child_argv.appendAssumeCapacity(cmd);
    if (options.prepend_zig_lib_dir_path)
        child_argv.appendAssumeCapacity(try arena.print("--zig-lib={s}", .{dirs.zig_lib.path orelse "."}));
    if (options.prepend_zig_exe_path)
        child_argv.appendAssumeCapacity(try arena.print("--zig={s}", .{self_exe_path}));
    if (options.prepend_global_cache_path)
        child_argv.appendAssumeCapacity(try arena.print("--global-cache={s}", .{dirs.global_cache.path orelse "."}));
    if (options.prepend_seed)
        child_argv.appendAssumeCapacity(try arena.print("--seed=0x{x}", .{randInt(io, u32)}));

    child_argv.appendSliceAssumeCapacity(args[args_i..]);

    if (EnvVar.ZIG_VERBOSE_CMD.isSet(environ_map)) {
        const cmd: std.zig.SubprocessCommand = .{
            .argv = child_argv.items,
        };
        std.log.info("{f}", .{cmd});
    }

    if (process.can_replace and options.capture == null) {
        _ = try io.lockStderr(&.{}, .no_color);
        const err = process.replace(io, .{ .argv = child_argv.items, .environ_map = environ_map });
        const cmd = try std.mem.join(arena, " ", child_argv.items);
        fatal("the following command failed to execve with {t}:\n{s}", .{ err, cmd });
    }

    const term = t: {
        _ = try io.lockStderr(&.{}, .no_color);
        defer io.unlockStderr();

        var child = std.process.spawn(io, .{
            .argv = child_argv.items,
            .stdin = .inherit,
            .stdout = if (options.capture == null) .inherit else .pipe,
            .stderr = .inherit,
        }) catch |err| fatal("failed to spawn {s}: {t}", .{ child_argv.items[0], err });
        defer child.kill(io);

        if (options.capture) |ptr| {
            var stdout_reader = child.stdout.?.readerStreaming(io, &.{});
            ptr.* = try stdout_reader.interface.allocRemaining(arena, .limited(std.math.maxInt(u32)));
        }

        break :t try child.wait(io);
    };
    if (term.success()) {
        if (options.capture != null) return;
        return cleanExit(io);
    }
    const cmd = try std.mem.join(arena, " ", child_argv.items);
    fatal("the following build command {f}:\n{s}", .{ term, cmd });
}

const info_zen =
    \\
    \\ * Communicate intent precisely.
    \\ * Edge cases matter.
    \\ * Favor reading code over writing code.
    \\ * There is an idiomatic way to do it.
    \\ * Runtime crashes are better than bugs.
    \\ * Compile errors are better than runtime crashes.
    \\ * Incremental improvements.
    \\ * Avoid local maximums.
    \\ * Reduce the amount one must remember.
    \\ * Focus on logic, not style.
    \\ * Resource allocation may fail.
    \\ * Resource deallocation must succeed.
    \\
    \\Together, we serve the users!
    \\
    \\
;

extern fn ZigClangIsLLVMUsingSeparateLibcxx() bool;

extern "c" fn ZigClang_main(argc: c_int, argv: [*:null]?[*:0]u8) c_int;
extern "c" fn ZigLlvmAr_main(argc: c_int, argv: [*:null]?[*:0]u8) c_int;

fn argsCopyZ(alloc: Allocator, args: []const []const u8) ![:null]?[*:0]u8 {
    var argv = try alloc.allocSentinel(?[*:0]u8, args.len, null);
    for (args, 0..) |arg, i| {
        argv[i] = try alloc.dupeSentinel(u8, arg, 0); // TODO If there was an argsAllocZ we could avoid this allocation.
    }
    return argv;
}

pub fn clangMain(alloc: Allocator, args: []const []const u8) error{OutOfMemory}!u8 {
    if (!build_options.have_llvm)
        fatal("`zig cc` and `zig c++` unavailable: compiler built without LLVM extensions", .{});

    var arena_instance = std.heap.ArenaAllocator.init(alloc);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    // Convert the args to the null-terminated format Clang expects.
    const argv = try argsCopyZ(arena, args);
    const exit_code = ZigClang_main(@as(c_int, @intCast(argv.len)), argv.ptr);
    return @as(u8, @bitCast(@as(i8, @truncate(exit_code))));
}

pub fn llvmArMain(alloc: Allocator, args: []const []const u8) error{OutOfMemory}!u8 {
    if (!build_options.have_llvm)
        fatal("`zig ar`, `zig dlltool`, `zig ranlib', and `zig lib` unavailable: compiler built without LLVM extensions", .{});

    var arena_instance = std.heap.ArenaAllocator.init(alloc);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    // Convert the args to the format llvm-ar expects.
    // We intentionally shave off the zig binary at args[0].
    const argv = try argsCopyZ(arena, args[1..]);
    const exit_code = ZigLlvmAr_main(@as(c_int, @intCast(argv.len)), argv.ptr);
    return @as(u8, @bitCast(@as(i8, @truncate(exit_code))));
}

/// The first argument determines which backend is invoked. The options are:
/// * `ld.lld` - ELF
/// * `lld-link` - COFF
/// * `wasm-ld` - WebAssembly
pub fn lldMain(
    alloc: Allocator,
    args: []const []const u8,
    can_exit_early: bool,
) error{OutOfMemory}!u8 {
    if (!build_options.have_llvm)
        fatal("`zig {s}` unavailable: compiler built without LLVM extensions", .{args[0]});

    // Print a warning if lld is called multiple times in the same process,
    // since it may misbehave
    // https://github.com/ziglang/zig/issues/3825
    const CallCounter = struct {
        var count: usize = 0;
    };
    if (CallCounter.count == 1) { // Issue the warning on the first repeat call
        warn("invoking LLD for the second time within the same process because the host OS ({s}) does not support spawning child processes. This sometimes activates LLD bugs", .{@tagName(native_os)});
    }
    CallCounter.count += 1;

    var arena_instance = std.heap.ArenaAllocator.init(alloc);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    // Convert the args to the format LLD expects.
    // We intentionally shave off the zig binary at args[0].
    const argv = try argsCopyZ(arena, args[1..]);
    // "If an error occurs, false will be returned."
    const ok = rc: {
        const llvm = @import("codegen/llvm/bindings.zig");
        const argc = @as(c_int, @intCast(argv.len));
        if (mem.eql(u8, args[1], "ld.lld")) {
            break :rc llvm.LinkELF(argc, argv.ptr, can_exit_early, false);
        } else if (mem.eql(u8, args[1], "lld-link")) {
            break :rc llvm.LinkCOFF(argc, argv.ptr, can_exit_early, false);
        } else if (mem.eql(u8, args[1], "wasm-ld")) {
            break :rc llvm.LinkWasm(argc, argv.ptr, can_exit_early, false);
        } else {
            unreachable;
        }
    };
    return @intFromBool(!ok);
}

const ArgIteratorResponseFile = process.Args.IteratorGeneral(.{ .comments = true, .single_quotes = true });

/// Initialize the arguments from a Response File. "*.rsp"
fn initArgIteratorResponseFile(allocator: Allocator, io: Io, resp_file_path: []const u8) !ArgIteratorResponseFile {
    const max_bytes = 10 * 1024 * 1024; // 10 MiB of command line arguments is a reasonable limit
    const cmd_line = try Io.Dir.cwd().readFileAlloc(io, resp_file_path, allocator, .limited(max_bytes));
    errdefer allocator.free(cmd_line);

    return ArgIteratorResponseFile.initTakeOwnership(allocator, cmd_line);
}

pub const ClangArgIterator = struct {
    has_next: bool,
    zig_equivalent: std.zig.ClangCliParam.ZigEquivalent,
    only_arg: []const u8,
    second_arg: []const u8,
    other_args: []const []const u8,
    argv: []const []const u8,
    next_index: usize,
    root_args: ?*Args,
    arg_iterator_response_file: ArgIteratorResponseFile,
    arena: Allocator,

    const Args = struct {
        next_index: usize,
        argv: []const []const u8,
    };

    fn init(arena: Allocator, argv: []const []const u8) ClangArgIterator {
        return .{
            .next_index = 2, // `zig cc foo` this points to `foo`
            .has_next = argv.len > 2,
            .zig_equivalent = undefined,
            .only_arg = undefined,
            .second_arg = undefined,
            .other_args = undefined,
            .argv = argv,
            .root_args = null,
            .arg_iterator_response_file = undefined,
            .arena = arena,
        };
    }

    fn next(self: *ClangArgIterator, io: Io) !void {
        assert(self.has_next);
        assert(self.next_index < self.argv.len);
        // In this state we know that the parameter we are looking at is a root parameter
        // rather than an argument to a parameter.
        // We adjust the len below when necessary.
        self.other_args = (self.argv.ptr + self.next_index)[0..1];
        var arg = self.argv[self.next_index];
        self.incrementArgIndex();

        if (mem.startsWith(u8, arg, "@")) {
            if (self.root_args != null) return error.NestedResponseFile;

            // This is a "compiler response file". We must parse the file and treat its
            // contents as command line parameters.
            const arena = self.arena;
            const resp_file_path = arg[1..];

            self.arg_iterator_response_file = initArgIteratorResponseFile(arena, io, resp_file_path) catch |err|
                fatal("unable to read response file {q}: {t}", .{ resp_file_path, err });
            // NOTE: The ArgIteratorResponseFile returns tokens from next() that are slices of an
            // internal buffer. This internal buffer is arena allocated, so it is not cleaned up here.

            var resp_arg_list = std.array_list.Managed([]const u8).init(arena);
            defer resp_arg_list.deinit();
            {
                while (self.arg_iterator_response_file.next()) |token| {
                    try resp_arg_list.append(token);
                }

                const args = try arena.create(Args);
                errdefer arena.destroy(args);
                args.* = .{
                    .next_index = self.next_index,
                    .argv = self.argv,
                };
                self.root_args = args;
            }
            const resp_arg_slice = try resp_arg_list.toOwnedSlice();
            self.next_index = 0;
            self.argv = resp_arg_slice;

            if (resp_arg_slice.len == 0) {
                self.resolveRespFileArgs();
                return;
            }

            self.has_next = true;
            self.other_args = (self.argv.ptr + self.next_index)[0..1]; // We adjust len below when necessary.
            arg = self.argv[self.next_index];
            self.incrementArgIndex();
        }

        if (mem.eql(u8, arg, "-") or !mem.startsWith(u8, arg, "-")) {
            self.zig_equivalent = .positional;
            self.only_arg = arg;
            return;
        }

        const clang_args: []const std.zig.ClangCliParam = @import("clang_options.zon");

        find_clang_arg: for (clang_args) |clang_arg| switch (clang_arg.syntax) {
            .flag => {
                const prefix_len = clang_arg.matchEql(arg);
                if (prefix_len > 0) {
                    self.zig_equivalent = clang_arg.ze;
                    self.only_arg = arg[prefix_len..];

                    break :find_clang_arg;
                }
            },
            .joined, .comma_joined => {
                // joined example: --target=foo
                // comma_joined example: -Wl,-soname,libsoundio.so.2
                const prefix_len = clang_arg.matchStartsWith(arg);
                if (prefix_len != 0) {
                    self.zig_equivalent = clang_arg.ze;
                    self.only_arg = arg[prefix_len..]; // This will skip over the "--target=" part.

                    break :find_clang_arg;
                }
            },
            .joined_or_separate => {
                // Examples: `-lfoo`, `-l foo`
                const prefix_len = clang_arg.matchStartsWith(arg);
                if (prefix_len == arg.len) {
                    if (self.next_index >= self.argv.len) {
                        fatal("Expected parameter after {q}", .{arg});
                    }
                    self.only_arg = self.argv[self.next_index];
                    self.incrementArgIndex();
                    self.other_args.len += 1;
                    self.zig_equivalent = clang_arg.ze;

                    break :find_clang_arg;
                } else if (prefix_len != 0) {
                    self.zig_equivalent = clang_arg.ze;
                    self.only_arg = arg[prefix_len..];

                    break :find_clang_arg;
                }
            },
            .joined_and_separate => {
                // Example: `-Xopenmp-target=riscv64-linux-unknown foo`
                const prefix_len = clang_arg.matchStartsWith(arg);
                if (prefix_len != 0) {
                    self.only_arg = arg[prefix_len..];
                    if (self.next_index >= self.argv.len) {
                        fatal("Expected parameter after {q}", .{arg});
                    }
                    self.second_arg = self.argv[self.next_index];
                    self.incrementArgIndex();
                    self.other_args.len += 1;
                    self.zig_equivalent = clang_arg.ze;
                    break :find_clang_arg;
                }
            },
            .separate => if (clang_arg.matchEql(arg) > 0) {
                if (self.next_index >= self.argv.len) {
                    fatal("expected parameter after {q}", .{arg});
                }
                self.only_arg = self.argv[self.next_index];
                self.incrementArgIndex();
                self.other_args.len += 1;
                self.zig_equivalent = clang_arg.ze;
                break :find_clang_arg;
            },
            .remaining_args_joined => {
                const prefix_len = clang_arg.matchStartsWith(arg);
                if (prefix_len != 0) {
                    @panic("TODO");
                }
            },
            .multi_arg => |num_args| if (clang_arg.matchEql(arg) > 0) {
                // Example `-sectcreate <arg1> <arg2> <arg3>`.
                var i: usize = 0;
                while (i < num_args) : (i += 1) {
                    self.incrementArgIndex();
                    self.other_args.len += 1;
                }
                self.zig_equivalent = clang_arg.ze;
                break :find_clang_arg;
            },
        } else {
            fatal("unknown clang option: {q}", .{arg});
        }
    }

    fn incrementArgIndex(self: *ClangArgIterator) void {
        self.next_index += 1;
        self.resolveRespFileArgs();
    }

    fn resolveRespFileArgs(self: *ClangArgIterator) void {
        const arena = self.arena;
        if (self.next_index >= self.argv.len) {
            if (self.root_args) |root_args| {
                self.next_index = root_args.next_index;
                self.argv = root_args.argv;

                arena.destroy(root_args);
                self.root_args = null;
            }
            if (self.next_index >= self.argv.len) {
                self.has_next = false;
            }
        }
    }
};

fn parseCodeModel(arg: []const u8) std.lang.CodeModel {
    return stringToEnum(std.lang.CodeModel, arg) orelse
        fatal("unsupported machine code model: {q}", .{arg});
}

const usage_ast_check =
    \\Usage: zig ast-check [file]
    \\
    \\    Given a .zig source file or .zon file, reports any compile errors
    \\    that can be ascertained on the basis of the source code alone,
    \\    without target information or type checking.
    \\
    \\    If [file] is omitted, stdin is used.
    \\
    \\Options:
    \\  -h, --help            Print this help and exit
    \\  --color [auto|off|on] Enable or disable colored error messages
    \\  --zon                 Treat the input file as ZON, regardless of file extension
    \\  -t                    (debug option) Output ZIR in text form to stdout
    \\
    \\
;

fn cmdAstCheck(arena: Allocator, io: Io, args: []const []const u8, environ_map: *const std.process.Environ.Map) !void {
    const Zir = std.zig.Zir;

    var color: Color = Color.settingFromEnvironment(environ_map);
    var want_output_text = false;
    var force_zon = false;
    var zig_source_path: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (mem.startsWith(u8, arg, "-")) {
            if (mem.eql(u8, arg, "-h") or mem.eql(u8, arg, "--help")) {
                try Io.File.stdout().writeStreamingAll(io, usage_ast_check);
                return cleanExit(io);
            } else if (mem.eql(u8, arg, "-t")) {
                want_output_text = true;
            } else if (mem.eql(u8, arg, "--zon")) {
                force_zon = true;
            } else if (mem.eql(u8, arg, "--color")) {
                if (i + 1 >= args.len) {
                    fatal("expected [auto|on|off] after --color", .{});
                }
                i += 1;
                const next_arg = args[i];
                color = stringToEnum(Color, next_arg) orelse {
                    fatal("expected [auto|on|off] after --color, found {q}", .{next_arg});
                };
            } else {
                fatal("unrecognized parameter: {q}", .{arg});
            }
        } else if (zig_source_path == null) {
            zig_source_path = arg;
        } else {
            fatal("extra positional parameter: {q}", .{arg});
        }
    }

    const display_path = zig_source_path orelse "<stdin>";
    const source: [:0]const u8 = s: {
        var f = if (zig_source_path) |p| file: {
            break :file Io.Dir.cwd().openFile(io, p, .{}) catch |err| {
                fatal("unable to open file {q} for ast-check: {t}", .{ display_path, err });
            };
        } else Io.File.stdin();
        defer if (zig_source_path != null) f.close(io);
        var file_reader: Io.File.Reader = f.reader(io, &stdin_buffer);
        break :s std.zig.readSourceFileToEndAlloc(arena, &file_reader) catch |err| {
            fatal("unable to load file {q} for ast-check: {t}", .{ display_path, err });
        };
    };

    const mode: Ast.Mode = mode: {
        if (force_zon) break :mode .zon;
        if (zig_source_path) |path| {
            if (mem.endsWith(u8, path, ".zon")) {
                break :mode .zon;
            }
        }
        break :mode .zig;
    };

    const tree = try Ast.parse(arena, source, .{ .mode = mode });

    var stdout_writer = Io.File.stdout().writerStreaming(io, &stdout_buffer);
    const stdout_bw = &stdout_writer.interface;
    switch (mode) {
        .zig => {
            const zir = try AstGen.generate(arena, tree);

            if (zir.hasCompileErrors()) {
                var wip_errors: std.zig.ErrorBundle.Wip = undefined;
                try wip_errors.init(arena);
                try wip_errors.addZirErrorMessages(zir, tree, source, display_path);
                var error_bundle = try wip_errors.toOwnedBundle("");
                try error_bundle.renderToStderr(io, .{}, color);
                if (zir.loweringFailed()) {
                    process.exit(1);
                }
            }

            if (!want_output_text) {
                if (zir.hasCompileErrors()) {
                    process.exit(1);
                } else {
                    return cleanExit(io);
                }
            }
            if (!build_options.enable_debug_extensions) {
                fatal("-t option only available in builds of zig with debug extensions", .{});
            }

            {
                const token_bytes = @sizeOf(Ast.TokenList) +
                    tree.tokens.len * (@sizeOf(std.zig.Token.Tag) + @sizeOf(Ast.ByteOffset));
                const tree_bytes = @sizeOf(Ast) + tree.nodes.len *
                    (@sizeOf(Ast.Node.Tag) +
                        @sizeOf(Ast.TokenIndex) +
                        // Here we don't use @sizeOf(Ast.Node.Data) because it would include
                        // the debug safety tag but we want to measure release size.
                        8);
                const instruction_bytes = zir.instructions.len *
                    // Here we don't use @sizeOf(Zir.Inst.Data) because it would include
                    // the debug safety tag but we want to measure release size.
                    (@sizeOf(Zir.Inst.Tag) + 8);
                const extra_bytes = zir.extra.len * @sizeOf(u32);
                const total_bytes = @sizeOf(Zir) + instruction_bytes + extra_bytes +
                    zir.string_bytes.len * @sizeOf(u8);
                // zig fmt: off
                try stdout_bw.print(
                    \\# Source bytes:       {Bi}
                    \\# Tokens:             {} ({Bi})
                    \\# AST Nodes:          {} ({Bi})
                    \\# Total ZIR bytes:    {Bi}
                    \\# Instructions:       {d} ({Bi})
                    \\# String Table Bytes: {}
                    \\# Extra Data Items:   {d} ({Bi})
                    \\
                , .{
                    source.len,
                    tree.tokens.len, token_bytes,
                    tree.nodes.len, tree_bytes,
                    total_bytes,
                    zir.instructions.len, instruction_bytes,
                    zir.string_bytes.len,
                    zir.extra.len, extra_bytes,
                });
                // zig fmt: on
            }

            try @import("print_zir.zig").renderAsText(arena, tree, zir, stdout_bw);
            try stdout_bw.flush();

            if (zir.hasCompileErrors()) {
                process.exit(1);
            } else {
                return cleanExit(io);
            }
        },
        .zon => {
            const zoir = try ZonGen.generate(arena, tree, .{});
            if (zoir.hasCompileErrors()) {
                var wip_errors: std.zig.ErrorBundle.Wip = undefined;
                try wip_errors.init(arena);
                try wip_errors.addZoirErrorMessages(zoir, tree, source, display_path);
                var error_bundle = try wip_errors.toOwnedBundle("");
                error_bundle.renderToStderr(io, .{}, color) catch {};
                process.exit(1);
            }

            if (!want_output_text) {
                return cleanExit(io);
            }

            if (!build_options.enable_debug_extensions) {
                fatal("-t option only available in builds of zig with debug extensions", .{});
            }

            try @import("print_zoir.zig").renderToWriter(zoir, arena, stdout_bw);
            try stdout_bw.flush();
            return cleanExit(io);
        },
    }
}

/// This is only enabled for debug builds.
fn cmdDumpZir(arena: Allocator, io: Io, args: []const []const u8) !void {
    const Zir = std.zig.Zir;

    const cache_file = args[0];

    var f = Io.Dir.cwd().openFile(io, cache_file, .{}) catch |err| {
        fatal("unable to open zir cache file for dumping {q}: {t}", .{ cache_file, err });
    };
    defer f.close(io);

    const zir = try Zcu.loadZirCache(arena, io, f);
    var stdout_writer = Io.File.stdout().writerStreaming(io, &stdout_buffer);
    const stdout_bw = &stdout_writer.interface;
    {
        const instruction_bytes = zir.instructions.len *
            // Here we don't use @sizeOf(Zir.Inst.Data) because it would include
            // the debug safety tag but we want to measure release size.
            (@sizeOf(Zir.Inst.Tag) + 8);
        const extra_bytes = zir.extra.len * @sizeOf(u32);
        const total_bytes = @sizeOf(Zir) + instruction_bytes + extra_bytes +
            zir.string_bytes.len * @sizeOf(u8);
        // zig fmt: off
        try stdout_bw.print(
            \\# Total ZIR bytes:    {Bi}
            \\# Instructions:       {d} ({Bi})
            \\# String Table Bytes: {Bi}
            \\# Extra Data Items:   {d} ({Bi})
            \\
        , .{
            total_bytes,
            zir.instructions.len, instruction_bytes,
            zir.string_bytes.len,
            zir.extra.len, extra_bytes,
        });
        // zig fmt: on
    }

    try @import("print_zir.zig").renderAsText(arena, null, zir, stdout_bw);
    try stdout_bw.flush();
}

/// This is only enabled for debug builds.
fn cmdChangelist(arena: Allocator, io: Io, args: []const []const u8, environ_map: *const std.process.Environ.Map) !void {
    const color: Color = Color.settingFromEnvironment(environ_map);
    const Zir = std.zig.Zir;

    const old_source_path = args[0];
    const new_source_path = args[1];

    const old_source = source: {
        var f = Io.Dir.cwd().openFile(io, old_source_path, .{}) catch |err|
            fatal("unable to open old source file {q}: {t}", .{ old_source_path, err });
        defer f.close(io);
        var file_reader: Io.File.Reader = f.reader(io, &stdin_buffer);
        break :source std.zig.readSourceFileToEndAlloc(arena, &file_reader) catch |err|
            fatal("unable to read old source file {q}: {t}", .{ old_source_path, err });
    };
    const new_source = source: {
        var f = Io.Dir.cwd().openFile(io, new_source_path, .{}) catch |err|
            fatal("unable to open new source file {q}: {t}", .{ new_source_path, err });
        defer f.close(io);
        var file_reader: Io.File.Reader = f.reader(io, &stdin_buffer);
        break :source std.zig.readSourceFileToEndAlloc(arena, &file_reader) catch |err|
            fatal("unable to read new source file {q}: {t}", .{ new_source_path, err });
    };

    const old_tree = try Ast.parse(arena, old_source, .{});
    const old_zir = try AstGen.generate(arena, old_tree);

    if (old_zir.loweringFailed()) {
        var wip_errors: std.zig.ErrorBundle.Wip = undefined;
        try wip_errors.init(arena);
        try wip_errors.addZirErrorMessages(old_zir, old_tree, old_source, old_source_path);
        var error_bundle = try wip_errors.toOwnedBundle("");
        error_bundle.renderToStderr(io, .{}, color) catch {};
        process.exit(1);
    }

    const new_tree = try Ast.parse(arena, new_source, .{});
    const new_zir = try AstGen.generate(arena, new_tree);

    if (new_zir.loweringFailed()) {
        var wip_errors: std.zig.ErrorBundle.Wip = undefined;
        try wip_errors.init(arena);
        try wip_errors.addZirErrorMessages(new_zir, new_tree, new_source, new_source_path);
        var error_bundle = try wip_errors.toOwnedBundle("");
        error_bundle.renderToStderr(io, .{}, color) catch {};
        process.exit(1);
    }

    var inst_map: std.AutoHashMapUnmanaged(Zir.Inst.Index, Zir.Inst.Index) = .empty;
    try Zcu.mapOldZirToNew(arena, old_zir, new_zir, &inst_map);

    var stdout_writer = Io.File.stdout().writerStreaming(io, &stdout_buffer);
    const stdout_bw = &stdout_writer.interface;
    {
        try stdout_bw.print("Instruction mappings:\n", .{});
        var it = inst_map.iterator();
        while (it.next()) |entry| {
            try stdout_bw.print(" %{d} => %{d}\n", .{
                @backingInt(entry.key_ptr.*),
                @backingInt(entry.value_ptr.*),
            });
        }
    }
    try stdout_bw.flush();
}

fn eatIntPrefix(arg: []const u8, base: u8) []const u8 {
    if (arg.len > 2 and arg[0] == '0') {
        switch (std.ascii.toLower(arg[1])) {
            'b' => if (base == 2) return arg[2..],
            'o' => if (base == 8) return arg[2..],
            'x' => if (base == 16) return arg[2..],
            else => {},
        }
    }
    return arg;
}

fn prefixedIntArg(arg: []const u8, prefix: []const u8) ?u64 {
    const number = mem.cutPrefix(u8, arg, prefix) orelse return null;
    return std.fmt.parseUnsigned(u64, number, 0) catch |err| fatal("unable to parse {q}: {t}", .{ arg, err });
}

fn warnAboutForeignBinaries(
    io: Io,
    arena: Allocator,
    arg_mode: ArgMode,
    target: *const std.Target,
    link_libc: bool,
) !void {
    const host_query: std.Target.Query = .{};
    const host_target = std.zig.resolveTargetQueryOrFatal(io, host_query);

    switch (std.zig.system.getExternalExecutor(io, target, .{
        .host_cpu_arch = host_target.cpu.arch,
        .host_os_tag = host_target.os.tag,
        .link_libc = link_libc,
    })) {
        .native => return,
        .rosetta => {
            const host_name = try host_target.zigTriple(arena);
            const foreign_name = try target.zigTriple(arena);
            warn("the host system ({s}) does not appear to be capable of executing binaries from the target ({s}). Consider installing Rosetta.", .{
                host_name, foreign_name,
            });
        },
        .qemu => |qemu| {
            const host_name = try host_target.zigTriple(arena);
            const foreign_name = try target.zigTriple(arena);
            switch (arg_mode) {
                .zig_test => warn(
                    "the host system ({s}) does not appear to be capable of executing binaries " ++
                        "from the target ({s}). Consider using '--test-cmd {s} --test-cmd-bin' " ++
                        "to run the tests",
                    .{ host_name, foreign_name, qemu },
                ),
                else => warn(
                    "the host system ({s}) does not appear to be capable of executing binaries " ++
                        "from the target ({s}). Consider using {q} to run the binary",
                    .{ host_name, foreign_name, qemu },
                ),
            }
        },
        .wine => |wine| {
            const host_name = try host_target.zigTriple(arena);
            const foreign_name = try target.zigTriple(arena);
            switch (arg_mode) {
                .zig_test => warn(
                    "the host system ({s}) does not appear to be capable of executing binaries " ++
                        "from the target ({s}). Consider using '--test-cmd {s} --test-cmd-bin' " ++
                        "to run the tests",
                    .{ host_name, foreign_name, wine },
                ),
                else => warn(
                    "the host system ({s}) does not appear to be capable of executing binaries " ++
                        "from the target ({s}). Consider using {q} to run the binary",
                    .{ host_name, foreign_name, wine },
                ),
            }
        },
        .wasmtime => |wasmtime| {
            const host_name = try host_target.zigTriple(arena);
            const foreign_name = try target.zigTriple(arena);
            switch (arg_mode) {
                .zig_test => warn(
                    "the host system ({s}) does not appear to be capable of executing binaries " ++
                        "from the target ({s}). Consider using '--test-cmd {s} --test-cmd-bin' " ++
                        "to run the tests",
                    .{ host_name, foreign_name, wasmtime },
                ),
                else => warn(
                    "the host system ({s}) does not appear to be capable of executing binaries " ++
                        "from the target ({s}). Consider using {q} to run the binary",
                    .{ host_name, foreign_name, wasmtime },
                ),
            }
        },
        .darling => |darling| {
            const host_name = try host_target.zigTriple(arena);
            const foreign_name = try target.zigTriple(arena);
            switch (arg_mode) {
                .zig_test => warn(
                    "the host system ({s}) does not appear to be capable of executing binaries " ++
                        "from the target ({s}). Consider using '--test-cmd {s} --test-cmd-bin' " ++
                        "to run the tests",
                    .{ host_name, foreign_name, darling },
                ),
                else => warn(
                    "the host system ({s}) does not appear to be capable of executing binaries " ++
                        "from the target ({s}). Consider using {q} to run the binary",
                    .{ host_name, foreign_name, darling },
                ),
            }
        },
        .bad_dl => |foreign_dl| {
            const host_dl = host_target.dynamic_linker.get() orelse "(none)";
            const tip_suffix = switch (arg_mode) {
                .zig_test => ", '--test-no-exec', or '--test-cmd'",
                else => "",
            };
            warn("the host system does not appear to be capable of executing binaries from the target because the host dynamic linker is {q}, while the target dynamic linker is {q}. Consider using '--dynamic-linker'{s}", .{
                host_dl, foreign_dl, tip_suffix,
            });
        },
        .bad_os_or_cpu => {
            const host_name = try host_target.zigTriple(arena);
            const foreign_name = try target.zigTriple(arena);
            const tip_suffix = switch (arg_mode) {
                .zig_test => ". Consider using '--test-no-exec' or '--test-cmd'",
                else => "",
            };
            warn("the host system ({s}) does not appear to be capable of executing binaries from the target ({s}){s}", .{
                host_name, foreign_name, tip_suffix,
            });
        },
    }
}

fn parseSubsystem(arg: []const u8) !std.zig.Subsystem {
    return stringToEnum(std.zig.Subsystem, arg) orelse
        fatal("invalid: --subsystem: {q}. Options are:\n{s}", .{
            arg,
            \\  console
            \\  windows
            \\  posix
            \\  native
            \\  efi_application
            \\  efi_boot_service_driver
            \\  efi_rom
            \\  efi_runtime_driver
            \\
        });
}

/// Model a header searchlist as a group.
/// Silently ignore superfluous search dirs.
/// Warn when a dir is added to multiple searchlists.
const ClangSearchSanitizer = struct {
    map: std.StringHashMapUnmanaged(Membership) = .empty,

    fn reset(self: *@This()) void {
        self.map.clearRetainingCapacity();
    }

    fn addIncludePath(
        self: *@This(),
        ally: Allocator,
        argv: *std.ArrayList([]const u8),
        group: Group,
        arg: []const u8,
        dir: []const u8,
        joined: bool,
    ) !void {
        const gopr = try self.map.getOrPut(ally, dir);
        const m = gopr.value_ptr;
        if (!gopr.found_existing) {
            // init empty membership
            m.* = .{};
        }
        const wtxt = "add {q} to header searchlist '-{s}' conflicts with '-{s}'";
        switch (group) {
            .I => {
                if (m.I) return;
                m.I = true;
                if (m.isystem) warn(wtxt, .{ dir, "I", "isystem" });
                if (m.idirafter) warn(wtxt, .{ dir, "I", "idirafter" });
                if (m.iframework) warn(wtxt, .{ dir, "I", "iframework" });
            },
            .isystem => {
                if (m.isystem) return;
                m.isystem = true;
                if (m.I) warn(wtxt, .{ dir, "isystem", "I" });
                if (m.idirafter) warn(wtxt, .{ dir, "isystem", "idirafter" });
                if (m.iframework) warn(wtxt, .{ dir, "isystem", "iframework" });
            },
            .iwithsysroot => {
                if (m.iwithsysroot) return;
                m.iwithsysroot = true;
                if (m.iframeworkwithsysroot) warn(wtxt, .{ dir, "iwithsysroot", "iframeworkwithsysroot" });
            },
            .idirafter => {
                if (m.idirafter) return;
                m.idirafter = true;
                if (m.I) warn(wtxt, .{ dir, "idirafter", "I" });
                if (m.isystem) warn(wtxt, .{ dir, "idirafter", "isystem" });
                if (m.iframework) warn(wtxt, .{ dir, "idirafter", "iframework" });
            },
            .iframework => {
                if (m.iframework) return;
                m.iframework = true;
                if (m.I) warn(wtxt, .{ dir, "iframework", "I" });
                if (m.isystem) warn(wtxt, .{ dir, "iframework", "isystem" });
                if (m.idirafter) warn(wtxt, .{ dir, "iframework", "idirafter" });
            },
            .iframeworkwithsysroot => {
                if (m.iframeworkwithsysroot) return;
                m.iframeworkwithsysroot = true;
                if (m.iwithsysroot) warn(wtxt, .{ dir, "iframeworkwithsysroot", "iwithsysroot" });
            },
            .embed_dir => {
                if (m.embed_dir) return;
                m.embed_dir = true;
            },
        }
        try argv.ensureUnusedCapacity(ally, 2);
        argv.appendAssumeCapacity(arg);
        if (!joined) argv.appendAssumeCapacity(dir);
    }

    const Group = enum { I, isystem, iwithsysroot, idirafter, iframework, iframeworkwithsysroot, embed_dir };

    const Membership = packed struct {
        I: bool = false,
        isystem: bool = false,
        iwithsysroot: bool = false,
        idirafter: bool = false,
        iframework: bool = false,
        iframeworkwithsysroot: bool = false,
        embed_dir: bool = false,
    };
};

fn accessFrameworkPath(
    io: Io,
    test_path: *std.array_list.Managed(u8),
    checked_paths: *std.array_list.Managed(u8),
    framework_dir_path: []const u8,
    framework_name: []const u8,
) !bool {
    const sep = fs.path.sep_str;

    for (&[_][]const u8{ ".tbd", ".dylib", "" }) |ext| {
        test_path.clearRetainingCapacity();
        try test_path.print("{s}" ++ sep ++ "{s}.framework" ++ sep ++ "{s}{s}", .{
            framework_dir_path, framework_name, framework_name, ext,
        });
        try checked_paths.print("\n {s}", .{test_path.items});
        Io.Dir.cwd().access(io, test_path.items, .{}) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => |e| fatal("unable to search for {s} framework {q}: {t}", .{
                ext, test_path.items, e,
            }),
        };
        return true;
    }

    return false;
}

fn parseRcIncludes(arg: []const u8) std.zig.RcIncludes {
    return stringToEnum(std.zig.RcIncludes, arg) orelse
        fatal("unsupported rc includes type: {q}", .{arg});
}

fn parseOptimizeMode(s: []const u8) std.lang.Optimize {
    return std.lang.Optimize.fromString(s) orelse fatal("unrecognized optimization mode: {q}", .{s});
}

fn parseWasiExecModel(s: []const u8) std.lang.WasiExecModel {
    return stringToEnum(std.lang.WasiExecModel, s) orelse
        fatal("expected [command|reactor] for -mexec-mode=[value], found {q}", .{s});
}

fn parseStackSize(s: []const u8) u64 {
    return std.fmt.parseUnsigned(u64, s, 0) catch |err|
        fatal("unable to parse stack size {q}: {t}", .{ s, err });
}

fn parseImageBase(s: []const u8) u64 {
    return std.fmt.parseUnsigned(u64, s, 0) catch |err|
        fatal("unable to parse image base {q}: {t}", .{ s, err });
}

fn handleModArg(
    arena: Allocator,
    mod_name: []const u8,
    opt_root_src_orig: ?[]const u8,
    create_module: *CreateModule,
    mod_opts: *Module.CreateOptions.Inherited,
    cc_argv: *std.ArrayList([]const u8),
    target_arch_os_abi: *?[]const u8,
    target_mcpu: *?[]const u8,
    dynamic_linker: *?[]const u8,
    deps: *std.ArrayList(CliModule.Dep),
    c_source_files_owner_index: *usize,
    rc_source_files_owner_index: *usize,
    cssan: *ClangSearchSanitizer,
) !void {
    const gop = try create_module.modules.getOrPut(arena, mod_name);

    if (gop.found_existing) {
        fatal("unable to add module {q}: already exists as '{s}{c}{s}'", .{
            mod_name, gop.value_ptr.root_path, fs.path.sep, gop.value_ptr.root_src_path,
        });
    }

    // See duplicate logic: ModCreationGlobalFlags
    if (mod_opts.single_threaded == false)
        create_module.opts.any_non_single_threaded = true;
    if (mod_opts.sanitize_thread == true)
        create_module.opts.any_sanitize_thread = true;
    if (mod_opts.sanitize_c) |sc| switch (sc) {
        .off => {},
        .trap => if (create_module.opts.any_sanitize_c == .off) {
            create_module.opts.any_sanitize_c = .trap;
        },
        .full => create_module.opts.any_sanitize_c = .full,
    };
    if (mod_opts.fuzz == true)
        create_module.opts.any_fuzz = true;
    if (mod_opts.unwind_tables) |uwt| switch (uwt) {
        .none => {},
        .sync, .async => create_module.opts.any_unwind_tables = true,
    };
    if (mod_opts.strip == false)
        create_module.opts.any_non_stripped = true;
    if (mod_opts.error_tracing == true)
        create_module.opts.any_error_tracing = true;

    const root_path: []const u8, const root_src_path: []const u8 = if (opt_root_src_orig) |path| root: {
        create_module.opts.have_zcu = true;
        break :root .{ fs.path.dirname(path) orelse ".", fs.path.basename(path) };
    } else .{ ".", "" };

    gop.value_ptr.* = .{
        .root_path = root_path,
        .root_src_path = root_src_path,
        .cc_argv = try cc_argv.toOwnedSlice(arena),
        .inherited = mod_opts.*,
        .target_arch_os_abi = target_arch_os_abi.*,
        .target_mcpu = target_mcpu.*,
        .dynamic_linker = dynamic_linker.*,
        .deps = try deps.toOwnedSlice(arena),
        .resolved = null,
        .c_source_files_start = c_source_files_owner_index.*,
        .c_source_files_end = create_module.c_source_files.items.len,
        .rc_source_files_start = rc_source_files_owner_index.*,
        .rc_source_files_end = create_module.rc_source_files.items.len,
    };
    cssan.reset();
    mod_opts.* = .{};
    target_arch_os_abi.* = null;
    target_mcpu.* = null;
    dynamic_linker.* = null;
    c_source_files_owner_index.* = create_module.c_source_files.items.len;
    rc_source_files_owner_index.* = create_module.rc_source_files.items.len;
}

fn anyObjectLinkInputs(link_inputs: []const link.UnresolvedInput) bool {
    for (link_inputs) |link_input| switch (link_input) {
        .path_query => |pq| switch (Compilation.classifyFileExt(pq.path.sub_path)) {
            .object, .static_library, .res => return true,
            else => continue,
        },
        else => continue,
    };
    return false;
}

fn addLibDirectoryWarn(io: Io, lib_directories: *std.ArrayList(Directory), path: []const u8) void {
    return addLibDirectoryWarn2(io, lib_directories, path, false);
}

fn addLibDirectoryWarn2(
    io: Io,
    lib_directories: *std.ArrayList(Directory),
    path: []const u8,
    ignore_not_found: bool,
) void {
    lib_directories.appendAssumeCapacity(.{
        .handle = Io.Dir.cwd().openDir(io, path, .{}) catch |err| {
            if (err == error.FileNotFound and ignore_not_found) return;
            warn("unable to open library directory {q}: {t}", .{ path, err });
            return;
        },
        .path = path,
    });
}

pub const globals = struct {
    pub var init: process.Init.Minimal = undefined;
    pub var root_gpa: Allocator = undefined;
    pub var io_impl_ptr: *IoImpl = undefined;
};
pub const IoImpl = switch (build_options.io_mode) {
    .threaded => Io.Threaded,
    .evented => Io.Evented,
};
fn setThreadLimit(arena: std.mem.Allocator, n: usize, io_impl_ptr: *IoImpl) Allocator.Error!void {
    switch (build_options.io_mode) {
        .threaded => {
            // We want a maximum of n total threads to keep the InternPool happy, but
            // the main thread doesn't count towards the limits, so use n-1. Also, the
            // linker can run concurrently, so we need to set both the async *and* the
            // concurrency limit.
            const limit: Io.Limit = .limited(n - 1);
            io_impl_ptr.setAsyncLimit(limit);
            io_impl_ptr.concurrent_limit = limit;
        },
        .evented => {},
    }
    try Zcu.PerThread.Id.allocate(arena, @max(n, 2));
}

pub fn randInt(io: Io, comptime T: type) T {
    var x: T = undefined;
    io.random(@ptrCast(&x));
    return x;
}

fn addDebugLog(arena: Allocator, scope_name: []const u8) error{OutOfMemory}!void {
    if (!build_options.enable_logging) {
        warn("Zig was compiled without logging enabled (-Dlog). --debug-log has no effect.", .{});
    } else {
        try log_scopes.append(arena, scope_name);
    }
}
