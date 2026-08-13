//! LSP Server Main
//! Setup std_options, logging, Allocator and IO

const builtin = @import("builtin");
const native_os = builtin.os.tag;

const build_options = @import("build_options");
const compiler = @import("compiler");
const ls_kit = @import("lsp-server");

const std = @import("std");
const mem = std.mem;
const process = std.process;
const fatal = process.fatal;
const Allocator = mem.Allocator;

const Logger = ls_kit.Logger;
const cli = ls_kit.cli;
const lsp = ls_kit.lsp;

pub const std_options: std.Options = .{
    // Always set this to debug to make std.log call into our handler,
    // then observe the runtime `level` value in the `logger`
    .log_level = .debug,
    .logFn = logFn,
};

var logger: Logger = .{};
fn logFn(
    comptime level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    Logger.log(&logger, level, scope, format, args);
}

const log = std.log.scoped(.ls_main);

pub fn main(init: std.process.Init.Minimal) anyerror!u8 {
    var bscs: *Basics = try .init(init);
    defer bscs.deinit();

    var environ_map = init.environ.createMap(bscs.arena) catch |err| fatal("failed to parse environment: {t}", .{err});

    const args = try init.args.toSlice(bscs.arena);
    if (args.len > 0) compiler.crash_report.zig_argv0 = args[0];
    if (args.len > 1) {
        if (mem.eql(u8, args[1], "maker")) {
            try ls_kit.Maker.main(init);
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
                .threaded => .init(bscs.root_gpa, .{
                    .stack_size = compiler.thread_stack_size,

                    .argv0 = .init(init.args),
                    .environ = init.environ,
                }),
                .evented => try .init(bscs.root_gpa, .{
                    .argv0 = .init(init.args),
                    .environ = init.environ,

                    .backing_allocator_needs_mutex = false,
                }),
            };
            defer compiler_io_impl.deinit();
            compiler.globals.io_impl_ptr = &compiler_io_impl;
            const compiler_io = compiler_io_impl.io();

            if (compiler.tracy.enable_allocation) {
                var tracy_allocator: compiler.tracy.Allocator = .{ .parent_allocator = bscs.gpa };
                try compiler.mainArgs(tracy_allocator.interface(), bscs.arena, compiler_io, args, &environ_map);
                return 0;
            }

            if (native_os == .wasi) {
                compiler.preopens = try .init(bscs.arena);
            }

            try compiler.mainArgs(bscs.gpa, bscs.arena, compiler_io, args, &environ_map);
            return 0;
        }
    }

    const cli_opts: cli.Options = try .parseArgs(bscs.io, bscs.arena, &environ_map, init.args);

    const read_buffer = try bscs.arena.alloc(u8, 1024 * 4);
    var stdio: lsp.Transport.Stdio = .init(read_buffer, .stdin(), .stdout());
    var thread_safe_stdio: lsp.ThreadSafeTransport(.{
        .thread_safe_read = false,
        .thread_safe_write = true,
    }) = .init(&stdio.transport);
    const jsonio: *lsp.Transport = &thread_safe_stdio.transport;

    logger.lsp_transport = if (cli_opts.disable_logging_to_jsonio) null else jsonio;
    logger.dump_to_stderr = cli_opts.enable_logging_to_stderr;
    logger.level = cli_opts.log_level orelse logger.level;
    defer {
        logger.lsp_transport = null;
        logger.dump_to_stderr = true;
    }

    const self_file_path = sp: {
        if (std.fs.path.isAbsolute(cli_opts.argv0)) break :sp cli_opts.argv0;
        const cur_path = std.process.currentPathAlloc(bscs.io, bscs.arena) catch break :sp null;
        break :sp std.fs.path.resolve(bscs.arena, &.{ cur_path, cli_opts.argv0 }) catch null;
    };

    log.info("Hello/", .{});
    log.info("", .{});
    log.info("Zigscient {s} ({t}) [gpa: {s}, io: {t}] @", .{
        build_options.version_string,
        builtin.mode,
        bscs.gpa_name,
        build_options.io_mode,
    });
    log.info("{q}", .{cli_opts.argv0});
    log.info("", .{});

    var settman: ls_kit.settings_handler.Manager = try .init(bscs.io, bscs.gpa, &environ_map, self_file_path);
    defer settman.deinit();

    const server: *ls_kit.Server = try .create(.{
        .io = bscs.io,
        .allocator = bscs.gpa,
        .transport = jsonio,
        .config_manager = &settman,
    });
    defer server.destroy();

    try settman.loadValues(server, cli_opts.settings_file_path);
    try ls_kit.settings_handler.resolveConfiguration(server);

    try server.loop();

    return switch (server.status) {
        .exiting_success => 0,
        .exiting_failure => 1,
        else => fatal("unexpected server.status {t}", .{server.status}),
    };
}

const Basics = struct {
    gpa_name: []const u8,
    root_gpa: Allocator,
    gpa: Allocator,

    arena_instance: std.heap.ArenaAllocator,
    arena: Allocator,

    io_impl: compiler.IoImpl,
    io: std.Io,

    pub fn init(min_init: process.Init.Minimal) anyerror!*@This() {
        const root_gpa, //
        const gpa_name =
            if (safe_allocator.do_use) .{
                safe_allocator.instance.allocator(),
                "safe",
            } else if (native_os == .wasi) .{
                std.heap.wasm_allocator,
                "wasm",
            } else if (builtin.link_libc) .{
                std.heap.c_allocator,
                "libc",
            } else .{
                std.heap.smp_allocator,
                "smp",
            };

        compiler.globals.init = min_init;
        compiler.globals.root_gpa = root_gpa;

        var io_impl: compiler.IoImpl = switch (build_options.io_mode) {
            .threaded => .init(root_gpa, .{
                .stack_size = compiler.thread_stack_size,

                .argv0 = .init(min_init.args),
                .environ = min_init.environ,
            }),
            .evented => try .init(root_gpa, .{
                .argv0 = .init(min_init.args),
                .environ = min_init.environ,

                .backing_allocator_needs_mutex = false,
            }),
        };
        errdefer io_impl.deinit();

        const gpa = switch (build_options.io_mode) {
            .threaded => root_gpa,
            .evented => io_impl.allocator(),
        };

        var arena_instance = std.heap.ArenaAllocator.init(gpa);
        errdefer arena_instance.deinit();
        const arena = arena_instance.allocator();

        var bscs = try arena.create(@This());

        bscs.gpa_name = gpa_name;
        bscs.root_gpa = root_gpa;
        bscs.gpa = gpa;

        bscs.arena_instance = arena_instance;
        bscs.arena = bscs.arena_instance.allocator();

        bscs.io_impl = io_impl;
        bscs.io = bscs.io_impl.io();

        return bscs;
    }

    pub fn deinit(bscs: *@This()) void {
        bscs.io_impl.deinit();
        bscs.arena_instance.deinit();
        if (safe_allocator.do_use) {
            _ = safe_allocator.instance.deinit();
        }
    }
};

const safe_allocator = struct {
    var instance: std.heap.SafeAllocator = .init(std.heap.page_allocator, .{
        .stack_trace_frames = build_options.mem_leak_frames,
    });
    const do_use = build_options.debug_gpa or
        (native_os != .wasi and !builtin.link_libc and switch (builtin.mode) {
            .debug, .safe => true,
            .fast, .small => false,
        });
};
