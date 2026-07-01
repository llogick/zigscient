//! LSP Server Main
//! Setup std_options, logging, Allocator and IO

const builtin = @import("builtin");
const native_os = builtin.os.tag;

const build_options = @import("build_options");
const lsp_server = @import("lsp-server");
const compiler = @import("compiler");

const std = @import("std");
const mem = std.mem;
const process = std.process;
const fatal = process.fatal;
const Allocator = mem.Allocator;

const Logger = lsp_server.Logger;
const cli = lsp_server.cli;
const lsp = lsp_server.lsp;

var logger: Logger = .{};
fn logFn(
    comptime level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    Logger.log(&logger, level, scope, format, args);
}

pub const std_options: std.Options = .{
    // Always set this to debug to make std.log call into our handler,
    // then observe the runtime `level` value in the `logger`
    .log_level = .debug,
    .logFn = logFn,
};

const log = std.log.scoped(.lspc_main);

const use_safe_allocator = build_options.debug_gpa or
    (native_os != .wasi and !builtin.link_libc and switch (builtin.mode) {
        .Debug, .ReleaseSafe => true,
        .ReleaseFast, .ReleaseSmall => false,
    });

// TODO: The `align(@alignOf(std.heap.SafeAllocator))` can be removed the next time zig1.wasm is updated
var safe_allocator: std.heap.SafeAllocator align(@alignOf(std.heap.SafeAllocator)) = .init(std.heap.page_allocator, .{
    .stack_trace_frames = build_options.mem_leak_frames,
});

pub fn main(init: std.process.Init.Minimal) anyerror!u8 {
    var allocator_name: []const u8 = "Undefined";
    var root_gpa: Allocator = undefined;
    if (use_safe_allocator) {
        root_gpa = safe_allocator.allocator();
        allocator_name = "safe";
    } else if (native_os == .wasi) {
        root_gpa = std.heap.wasm_allocator;
        allocator_name = "wasm";
    } else if (builtin.link_libc) {
        root_gpa = std.heap.c_allocator;
        allocator_name = "libc";
    } else {
        root_gpa = std.heap.smp_allocator;
        allocator_name = "smp";
    }
    defer if (use_safe_allocator) {
        _ = safe_allocator.deinit();
    };

    compiler.globals.init = init;
    compiler.globals.root_gpa = root_gpa;

    var io_impl: compiler.IoImpl = switch (build_options.io_mode) {
        .threaded => .init(root_gpa, .{
            .stack_size = compiler.thread_stack_size,

            .argv0 = .init(init.args),
            .environ = init.environ,
        }),
        .evented => try .init(root_gpa, .{
            .argv0 = .init(init.args),
            .environ = init.environ,

            .backing_allocator_needs_mutex = false,
        }),
    };
    defer io_impl.deinit();
    const io = io_impl.io();

    const gpa = switch (build_options.io_mode) {
        .threaded => root_gpa,
        .evented => io_impl.allocator(),
    };

    var arena_instance = std.heap.ArenaAllocator.init(gpa);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    const args = try init.args.toSlice(arena);

    if (args.len > 0) compiler.crash_report.zig_argv0 = args[0];

    var environ_map = init.environ.createMap(arena) catch |err| fatal("failed to parse environment: {t}", .{err});

    if (args.len > 1) {
        if (mem.eql(u8, args[1], "maker")) {
            try lsp_server.Maker.main(init);
            return 0;
        }
        if (mem.eql(u8, args[1], "zig")) {
            if (args.len <= 2) {
                if (build_options.dev != .full) {
                    log.info(
                        \\
                        \\This is a limited build, '{t}', of the Zig compiler,
                        \\only `zig build-* -fno-emit-bin` commands available.
                    , .{build_options.dev});
                } else {
                    log.info("{s}", .{compiler.usage});
                }
                fatal("expected command argument", .{});
            }

            var compiler_io_impl: compiler.IoImpl = switch (build_options.io_mode) {
                .threaded => .init(root_gpa, .{
                    .stack_size = compiler.thread_stack_size,

                    .argv0 = .init(init.args),
                    .environ = init.environ,
                }),
                .evented => try .init(root_gpa, .{
                    .argv0 = .init(init.args),
                    .environ = init.environ,

                    .backing_allocator_needs_mutex = false,
                }),
            };
            defer compiler_io_impl.deinit();
            compiler.globals.io_impl_ptr = &compiler_io_impl;
            const compiler_io = compiler_io_impl.io();

            if (compiler.tracy.enable_allocation) {
                var tracy_allocator: compiler.tracy.Allocator = .{ .parent_allocator = gpa };
                try compiler.mainArgs(tracy_allocator.interface(), arena, compiler_io, args, &environ_map);
                return 0;
            }

            if (native_os == .wasi) {
                compiler.preopens = try .init(arena);
            }

            try compiler.mainArgs(gpa, arena, compiler_io, args, &environ_map);
            return 0;
        }
    }

    const cli_opts: cli.Options = try .parseArgs(io, gpa, &environ_map, init.args);
    defer cli_opts.deinit(gpa);

    const read_buffer = try gpa.alloc(u8, 4096);
    defer gpa.free(read_buffer);

    var stdio_transport: lsp.Transport.Stdio = .init(read_buffer, .stdin(), .stdout());

    var thread_safe_transport: lsp.ThreadSafeTransport(.{
        .thread_safe_read = false,
        .thread_safe_write = true,
    }) = .init(&stdio_transport.transport);

    const transport: *lsp.Transport = &thread_safe_transport.transport;

    logger.lsp_transport = if (cli_opts.disable_lsp_logs) null else transport;
    logger.dump_to_stderr = cli_opts.enable_stderr_logs;
    logger.level = cli_opts.log_level orelse logger.level;
    defer {
        logger.lsp_transport = null;
        logger.dump_to_stderr = true;
    }

    const self_file_path = sp: {
        if (std.fs.path.isAbsolute(cli_opts.argv0)) break :sp cli_opts.argv0;
        const cur_path = std.process.currentPathAlloc(io, arena) catch break :sp null;
        break :sp std.fs.path.resolve(arena, &.{ cur_path, cli_opts.argv0 }) catch null;
    };

    log.info("Hello/", .{});
    log.info("", .{});
    log.info("Zigscient {s} ({t}) [gpa: {s}, io: {t}] @", .{
        build_options.version_string,
        builtin.mode,
        allocator_name,
        build_options.io_mode,
    });
    log.info("{q}", .{cli_opts.argv0});
    log.info("", .{});

    if (self_file_path == null) log.warn("Could not determine path to self; Only minimal Build System support available.", .{});

    var config_manager: lsp_server.settings_handler.Manager = try .init(io, gpa, &environ_map, self_file_path);
    defer config_manager.deinit();

    const server: *lsp_server.Server = try .create(.{
        .io = io,
        .allocator = gpa,
        .transport = transport,
        .config_manager = &config_manager,
    });
    defer server.destroy();

    try lsp_server.settings_handler.loadConfiguration(io, gpa, &environ_map, server, cli_opts.config_path);
    try lsp_server.settings_handler.resolveConfiguration(server);

    try server.loop();

    return switch (server.status) {
        .exiting_success => 0,
        .exiting_failure => 1,
        else => fatal("unexpected server.status {t}", .{server.status}),
    };
}
