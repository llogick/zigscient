const WebServer = @This();

const builtin = @import("builtin");

const std = @import("std");
const Allocator = std.mem.Allocator;
const Cache = std.Build.Cache;
const Configuration = std.Build.Configuration;
const Io = std.Io;
const abi = std.Build.abi;
const assert = std.debug.assert;
const http = std.http;
const log = std.log.scoped(.web_server);
const mem = std.mem;
const net = std.Io.net;

const Maker = @import("../Maker.zig");
const Fuzz = @import("Fuzz.zig");
const Graph = @import("Graph.zig");
const Step = @import("Step.zig");

graph: *const Graph,
listen_address: net.IpAddress,
root_prog_node: std.Progress.Node,

tcp_server: ?net.Server,
serve_task: ?Io.Future(Io.Cancelable!void),

/// Uses `Io.Clock.awake`.
base_timestamp: Io.Timestamp,

fuzz: ?Fuzz,

build_status: std.atomic.Value(abi.BuildStatus),
/// When an event occurs which means WebSocket clients should be sent updates, call `notifyUpdate`
/// to increment this value. Each client thread waits for this increment with `Io.futexWaitTimeout`, so
/// `notifyUpdate` will wake those threads. Updates are sent on a short interval regardless, so it
/// is recommended to only use `notifyUpdate` for changes which the user should see immediately. For
/// instance, we do not call `notifyUpdate` when the number of "unique runs" in the fuzzer changes,
/// because this value changes quickly so this would result in constantly spamming all clients with
/// an unreasonable number of packets.
update_id: std.atomic.Value(u32),

runner_request_mutex: Io.Mutex,
runner_request_ready_cond: Io.Condition,
runner_request_empty_cond: Io.Condition,
runner_request: ?RunnerRequest,

configured: ?Configured,

const Configured = struct {
    maker: *Maker,
    /// The "step name" data which trails `abi.Hello`, for the steps in `all_steps`.
    step_names_trailing: []u8,
    /// The bit-packed "step status" data. Values are `abi.StepUpdate.Status`. LSBs are earlier steps.
    /// Accessed atomically.
    step_status_bits: []u8,

    time_report_mutex: Io.Mutex,
    time_report_msgs: [][]u8,
    time_report_update_times: []i64,
};

/// If a client is not explicitly notified of changes with `notifyUpdate`, it will be sent updates
/// on a fixed interval of this many milliseconds.
const default_update_interval_ms = 500;

pub const base_clock: Io.Clock = .awake;

/// Thread-safe. Triggers updates to be sent to connected WebSocket clients; see `update_id`.
pub fn notifyUpdate(ws: *WebServer) void {
    const io = ws.graph.io;
    _ = ws.update_id.rmw(.Add, 1, .release);
    io.futexWake(u32, &ws.update_id.raw, 16);
}

pub const Options = struct {
    graph: *const Graph,
    root_prog_node: std.Progress.Node,
    listen_address: net.IpAddress,
    base_timestamp: Io.Clock.Timestamp,
};

pub fn init(opts: Options) WebServer {
    // The upcoming `Io` interface should allow us to use `Io.async` and `Io.concurrent`
    // instead of threads, so that the web server can function in single-threaded builds.
    comptime assert(!builtin.single_threaded);
    assert(opts.base_timestamp.clock == base_clock);
    return .{
        .graph = opts.graph,
        .listen_address = opts.listen_address,
        .root_prog_node = opts.root_prog_node,

        .tcp_server = null,
        .serve_task = null,

        .base_timestamp = opts.base_timestamp.raw,

        .fuzz = null,

        .build_status = .init(.idle),
        .update_id = .init(0),

        .runner_request_mutex = .init,
        .runner_request_ready_cond = .init,
        .runner_request_empty_cond = .init,
        .runner_request = null,

        .configured = null,
    };
}

pub fn deinit(ws: *WebServer) void {
    const graph = ws.graph;
    const io = graph.io;

    if (ws.fuzz) |*f| f.deinit();

    ws.releaseConfigured();

    if (ws.serve_task) |t| {
        if (ws.tcp_server) |*s| s.stream.close(io);
        t.await();
    }
    if (ws.tcp_server) |*s| s.deinit();
}

fn releaseConfigured(ws: *WebServer) void {
    if (ws.configured) |*configured| {
        const gpa = configured.maker.gpa;
        gpa.free(configured.step_names_trailing);
        gpa.free(configured.step_status_bits);
        for (configured.time_report_msgs) |msg| gpa.free(msg);
        gpa.free(configured.time_report_msgs);
        gpa.free(configured.time_report_update_times);
        gpa.free(configured.step_names_trailing);
        ws.configured = null;
    }
}

pub fn updateConfiguration(ws: *WebServer, maker: *Maker) !void {
    const graph = ws.graph;
    const gpa = maker.gpa;
    const all_steps = maker.step_stack.keys();
    const c = &maker.scanned_config.configuration;

    const step_names_trailing = try gpa.alloc(u8, len: {
        var name_bytes: usize = 0;
        for (all_steps) |step_index| name_bytes += step_index.ptr(c).name.slice(c).len;
        break :len name_bytes + all_steps.len * 4;
    });
    errdefer gpa.free(step_names_trailing);

    {
        const step_name_lens: []align(1) u32 = @ptrCast(step_names_trailing[0 .. all_steps.len * 4]);
        var idx: usize = all_steps.len * 4;
        for (all_steps, step_name_lens) |step_index, *name_len| {
            const step_name = step_index.ptr(c).name.slice(c);
            name_len.* = @intCast(step_name.len);
            @memcpy(step_names_trailing[idx..][0..step_name.len], step_name);
            idx += step_name.len;
        }
        assert(idx == step_names_trailing.len);
    }

    const step_status_bits = try gpa.alloc(u8, @divCeil(all_steps.len, 4));
    errdefer gpa.free(step_status_bits);
    @memset(step_status_bits, 0);

    const time_reports_len: usize = if (graph.time_report) all_steps.len else 0;
    const time_report_msgs = try gpa.alloc([]u8, time_reports_len);
    errdefer gpa.free(time_report_msgs);
    const time_report_update_times = try gpa.alloc(i64, time_reports_len);
    errdefer gpa.free(time_report_update_times);
    @memset(time_report_msgs, &.{});
    @memset(time_report_update_times, std.math.minInt(i64));

    ws.releaseConfigured();

    ws.configured = .{
        .maker = maker,
        .step_names_trailing = step_names_trailing,
        .step_status_bits = step_status_bits,
        .time_report_mutex = .init,
        .time_report_msgs = time_report_msgs,
        .time_report_update_times = time_report_update_times,
    };
}

pub fn start(ws: *WebServer) error{AlreadyReported}!void {
    assert(ws.tcp_server == null);
    assert(ws.serve_task == null);
    const graph = ws.graph;
    const io = graph.io;

    ws.tcp_server = ws.listen_address.listen(io, .{ .reuse_address = true }) catch |err| {
        log.err("failed to listen to port {d}: {t}", .{ ws.listen_address.getPort(), err });
        return error.AlreadyReported;
    };
    ws.serve_task = io.concurrent(serve, .{ws}) catch |err| {
        log.err("unable to spawn web server thread: {t}", .{err});
        ws.tcp_server.?.deinit(io);
        ws.tcp_server = null;
        return error.AlreadyReported;
    };

    log.info("web interface listening at http://{f}/", .{ws.tcp_server.?.socket.address});
    if (ws.listen_address.getPort() == 0) {
        log.info("hint: pass '--webui={f}' to use the same port next time", .{ws.tcp_server.?.socket.address});
    }
}
fn serve(ws: *WebServer) Io.Cancelable!void {
    const graph = ws.graph;
    const io = graph.io;

    var group: Io.Group = .init;
    defer group.cancel(io);

    while (true) {
        var stream = ws.tcp_server.?.accept(io) catch |err| switch (err) {
            error.Canceled => |e| return e,
            else => |e| {
                log.err("failed to accept connection: {t}", .{e});
                return;
            },
        };
        group.concurrent(io, accept, .{ ws, stream }) catch |err| {
            log.err("unable to spawn connection thread: {t}", .{err});
            stream.close(io);
            continue;
        };
    }
}

pub fn startBuild(ws: *WebServer) void {
    if (ws.fuzz) |*fuzz| {
        fuzz.deinit();
        ws.fuzz = null;
    }
    const configured = &ws.configured.?;
    for (configured.step_status_bits) |*bits| @atomicStore(u8, bits, 0, .monotonic);
    ws.build_status.store(.running, .monotonic);
    ws.notifyUpdate();
}

pub fn updateStepStatus(
    ws: *WebServer,
    step_index: Configuration.Step.Index,
    new_status: abi.StepUpdate.Status,
) void {
    const configured = &ws.configured.?;
    const maker = configured.maker;
    const all_steps = maker.step_stack.keys();
    const step_idx: u32 = for (all_steps, 0..) |s, i| {
        if (s == step_index) break @intCast(i);
    } else unreachable;
    const ptr = &configured.step_status_bits[step_idx / 4];
    const bit_offset: u3 = @intCast((step_idx % 4) * 2);
    const old_bits: u2 = @truncate(@atomicLoad(u8, ptr, .monotonic) >> bit_offset);
    const mask = @as(u8, @backingInt(new_status) ^ old_bits) << bit_offset;
    _ = @atomicRmw(u8, ptr, .Xor, mask, .monotonic);
    ws.notifyUpdate();
}

pub fn finishBuild(ws: *WebServer, opts: struct {
    fuzz: bool,
}) void {
    const configured = &ws.configured.?;
    const maker = configured.maker;
    const all_steps = maker.step_stack.keys();

    if (opts.fuzz) {
        switch (builtin.os.tag) {
            // Current implementation depends on two things that need to be ported to Windows:
            // * Memory-mapping to share data between the fuzzer and build runner.
            // * COFF/PE support added to `std.debug.Info` (it needs a batching API for resolving
            //   many addresses to source locations).
            .windows => std.process.fatal("--fuzz not yet implemented for {t}", .{builtin.os.tag}),
            else => {},
        }
        if (@bitSizeOf(usize) != 64) {
            // Current implementation depends on posix.mmap()'s second
            // parameter, `length: usize`, being compatible with file system's
            // u64 return value. This is not the case on 32-bit platforms.
            // Affects or affected by issues #5185, #22523, and #22464.
            std.process.fatal("--fuzz not yet implemented on {d}-bit platforms", .{@bitSizeOf(usize)});
        }

        assert(ws.fuzz == null);

        ws.build_status.store(.fuzz_init, .monotonic);
        ws.notifyUpdate();

        ws.fuzz = Fuzz.init(maker, all_steps, ws.root_prog_node, .{ .forever = .{ .ws = ws } }) catch |err|
            std.process.fatal("failed to start fuzzer: {t}", .{err});
        ws.fuzz.?.start();
    }

    ws.build_status.store(if (maker.watch) .watching else .idle, .monotonic);
    ws.notifyUpdate();
}

pub fn now(ws: *const WebServer) i64 {
    const graph = ws.graph;
    const io = graph.io;
    const ts = base_clock.now(io);
    return @intCast(ws.base_timestamp.durationTo(ts).toNanoseconds());
}

fn accept(ws: *WebServer, stream: net.Stream) void {
    const graph = ws.graph;
    const io = graph.io;

    defer {
        // `net.Stream.close` wants to helpfully overwrite `stream` with
        // `undefined`, but it cannot do so since it is an immutable parameter.
        var copy = stream;
        copy.close(io);
    }
    var send_buffer: [4096]u8 = undefined;
    var recv_buffer: [4096]u8 = undefined;
    var connection_reader = stream.reader(io, &recv_buffer);
    var connection_writer = stream.writer(io, &send_buffer);
    var server: http.Server = .init(&connection_reader.interface, &connection_writer.interface);

    while (true) {
        var request = server.receiveHead() catch |err| switch (err) {
            error.HttpConnectionClosing => return,
            else => return log.err("failed to receive http request: {t}", .{err}),
        };
        switch (request.upgradeRequested()) {
            .websocket => |opt_key| {
                const key = opt_key orelse return log.err("missing websocket key", .{});
                var web_socket = request.respondWebSocket(.{ .key = key }) catch {
                    return log.err("failed to respond web socket: {t}", .{connection_writer.err.?});
                };
                ws.serveWebSocket(&web_socket) catch |err| {
                    log.err("failed to serve websocket: {t}", .{err});
                    return;
                };
                comptime unreachable;
            },
            .other => |name| return log.err("unknown upgrade request: {s}", .{name}),
            .none => {
                ws.serveRequest(&request) catch |err| switch (err) {
                    error.AlreadyReported => return,
                    else => {
                        log.err("failed to serve '{s}': {t}", .{ request.head.target, err });
                        return;
                    },
                };
            },
        }
    }
}

fn serveWebSocket(ws: *WebServer, sock: *http.Server.WebSocket) !noreturn {
    const graph = ws.graph;
    const gpa = graph.cache.gpa;
    const io = graph.io;
    log.err("TODO serve a different message when the configuration changes", .{});
    const configured = &ws.configured.?;
    const maker = configured.maker;
    const all_steps = maker.step_stack.keys();

    var prev_build_status = ws.build_status.load(.monotonic);

    const prev_step_status_bits = try gpa.alloc(u8, configured.step_status_bits.len);
    defer gpa.free(prev_step_status_bits);
    for (prev_step_status_bits, configured.step_status_bits) |*copy, *shared| {
        copy.* = @atomicLoad(u8, shared, .monotonic);
    }

    var recv_thread = try io.concurrent(recvWebSocketMessages, .{ ws, sock });
    defer recv_thread.cancel(io);

    {
        const hello_header: abi.Hello = .{
            .status = prev_build_status,
            .flags = .{
                .time_report = graph.time_report,
            },
            .timestamp = ws.now(),
            .steps_len = @intCast(all_steps.len),
        };
        var bufs: [3][]const u8 = .{ @ptrCast(&hello_header), configured.step_names_trailing, prev_step_status_bits };
        try sock.writeMessageVec(&bufs, .binary);
    }

    var prev_fuzz: Fuzz.Previous = .init;
    var prev_time: i64 = std.math.minInt(i64);
    while (true) {
        const start_time = ws.now();
        const start_update_id = ws.update_id.load(.acquire);

        if (ws.fuzz) |*fuzz| {
            try fuzz.sendUpdate(sock, &prev_fuzz);
        }

        {
            try configured.time_report_mutex.lock(io);
            defer configured.time_report_mutex.unlock(io);
            for (configured.time_report_msgs, configured.time_report_update_times) |msg, update_time| {
                if (update_time <= prev_time) continue;
                // We want to send `msg`, but shouldn't block `configured.time_report_mutex` while we do, so
                // that we don't hold up the build system on the client accepting this packet.
                const owned_msg = try gpa.dupe(u8, msg);
                defer gpa.free(owned_msg);
                // Temporarily unlock, then re-lock after the message is sent.
                configured.time_report_mutex.unlock(io);
                defer configured.time_report_mutex.lockUncancelable(io);
                try sock.writeMessage(owned_msg, .binary);
            }
        }

        {
            const build_status = ws.build_status.load(.monotonic);
            if (build_status != prev_build_status) {
                prev_build_status = build_status;
                const msg: abi.StatusUpdate = .{ .new = build_status };
                try sock.writeMessage(@ptrCast(&msg), .binary);
            }
        }

        for (prev_step_status_bits, configured.step_status_bits, 0..) |*prev_byte, *shared, byte_idx| {
            const cur_byte = @atomicLoad(u8, shared, .monotonic);
            if (prev_byte.* == cur_byte) continue;
            const cur: [4]abi.StepUpdate.Status = .{
                @fromBackingInt(@intCast(@as(u2, @truncate(cur_byte >> 0)))),
                @fromBackingInt(@intCast(@as(u2, @truncate(cur_byte >> 2)))),
                @fromBackingInt(@intCast(@as(u2, @truncate(cur_byte >> 4)))),
                @fromBackingInt(@intCast(@as(u2, @truncate(cur_byte >> 6)))),
            };
            const prev: [4]abi.StepUpdate.Status = .{
                @fromBackingInt(@intCast(@as(u2, @truncate(prev_byte.* >> 0)))),
                @fromBackingInt(@intCast(@as(u2, @truncate(prev_byte.* >> 2)))),
                @fromBackingInt(@intCast(@as(u2, @truncate(prev_byte.* >> 4)))),
                @fromBackingInt(@intCast(@as(u2, @truncate(prev_byte.* >> 6)))),
            };
            for (cur, prev, byte_idx * 4..) |cur_status, prev_status, step_idx| {
                const msg: abi.StepUpdate = .{ .step_idx = @intCast(step_idx), .bits = .{ .status = cur_status } };
                if (cur_status != prev_status) try sock.writeMessage(@ptrCast(&msg), .binary);
            }
            prev_byte.* = cur_byte;
        }

        prev_time = start_time;

        const old_cp = io.swapCancelProtection(.blocked);
        defer _ = io.swapCancelProtection(old_cp);
        io.futexWaitTimeout(
            u32,
            &ws.update_id.raw,
            start_update_id,
            .{ .duration = .{
                .clock = .awake,
                .raw = .fromMilliseconds(default_update_interval_ms),
            } },
        ) catch |err| switch (err) {
            error.Canceled => unreachable,
        };
    }
}
fn recvWebSocketMessages(ws: *WebServer, sock: *http.Server.WebSocket) void {
    const graph = ws.graph;
    const io = graph.io;

    while (true) {
        const msg = sock.readSmallMessage() catch return;
        if (msg.opcode != .binary) continue;
        if (msg.data.len == 0) continue;
        const tag: abi.ToServerTag = @fromBackingInt(@intCast(msg.data[0]));
        switch (tag) {
            _ => continue,
            .rebuild => while (true) {
                ws.runner_request_mutex.lock(io) catch |err| switch (err) {
                    error.Canceled => return,
                };
                defer ws.runner_request_mutex.unlock(io);
                if (ws.runner_request == null) {
                    ws.runner_request = .rebuild;
                    ws.runner_request_ready_cond.signal(io);
                    break;
                }
                ws.runner_request_empty_cond.wait(io, &ws.runner_request_mutex) catch return;
            },
        }
    }
}

fn serveRequest(ws: *WebServer, req: *http.Server.Request) !void {
    // Strip an optional leading '/debug' component from the request.
    const target: []const u8, const debug: bool = target: {
        if (mem.eql(u8, req.head.target, "/debug")) break :target .{ "/", true };
        if (mem.eql(u8, req.head.target, "/debug/")) break :target .{ "/", true };
        if (mem.startsWith(u8, req.head.target, "/debug/")) break :target .{ req.head.target["/debug".len..], true };
        break :target .{ req.head.target, false };
    };

    if (mem.eql(u8, target, "/")) return serveLibFile(ws, req, "build-web/index.html", "text/html");
    if (mem.eql(u8, target, "/main.js")) return serveLibFile(ws, req, "build-web/main.js", "application/javascript");
    if (mem.eql(u8, target, "/style.css")) return serveLibFile(ws, req, "build-web/style.css", "text/css");
    if (mem.eql(u8, target, "/time_report.css")) return serveLibFile(ws, req, "build-web/time_report.css", "text/css");
    if (mem.eql(u8, target, "/main.wasm")) return serveClientWasm(ws, req, if (debug) .Debug else .ReleaseFast);

    if (ws.fuzz) |*fuzz| {
        if (mem.eql(u8, target, "/sources.tar")) return fuzz.serveSourcesTar(req);
    }

    try req.respond("not found", .{
        .status = .not_found,
        .extra_headers = &.{
            .{ .name = "Content-Type", .value = "text/plain" },
        },
    });
}

fn serveLibFile(
    ws: *WebServer,
    request: *http.Server.Request,
    sub_path: []const u8,
    content_type: []const u8,
) !void {
    const graph = ws.graph;

    return serveFile(ws, request, .{
        .root_dir = graph.zig_lib_directory,
        .sub_path = sub_path,
    }, content_type);
}
fn serveClientWasm(
    ws: *WebServer,
    req: *http.Server.Request,
    optimize_mode: std.builtin.OptimizeMode,
) !void {
    const gpa = ws.graph.cache.gpa;

    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // We always rebuild the wasm on-the-fly, so that if it is edited the user can just refresh the page.
    const bin_path = try buildClientWasm(ws, arena, optimize_mode);
    return serveFile(ws, req, bin_path, "application/wasm");
}

pub fn serveFile(
    ws: *WebServer,
    request: *http.Server.Request,
    path: Cache.Path,
    content_type: []const u8,
) !void {
    const graph = ws.graph;
    const gpa = graph.cache.gpa;
    const io = graph.io;

    // The desired API is actually sendfile, which will require enhancing http.Server.
    // We load the file with every request so that the user can make changes to the file
    // and refresh the HTML page without restarting this server.
    const file_contents = path.root_dir.handle.readFileAlloc(io, path.sub_path, gpa, .limited(10 * 1024 * 1024)) catch |err| {
        log.err("failed to read '{f}': {t}", .{ path, err });
        return error.AlreadyReported;
    };
    defer gpa.free(file_contents);
    try request.respond(file_contents, .{
        .extra_headers = &.{
            .{ .name = "Content-Type", .value = content_type },
            cache_control_header,
        },
    });
}
pub fn serveTarFile(ws: *WebServer, request: *http.Server.Request, paths: []const Cache.Path) !void {
    const graph = ws.graph;
    const io = graph.io;

    var send_buffer: [0x4000]u8 = undefined;
    var response = try request.respondStreaming(&send_buffer, .{
        .respond_options = .{
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = "application/x-tar" },
                cache_control_header,
            },
        },
    });

    var archiver: std.tar.Writer = .{ .underlying_writer = &response.writer };

    for (paths) |path| {
        var file = path.root_dir.handle.openFile(io, path.sub_path, .{}) catch |err| {
            log.err("failed to open '{f}': {s}", .{ path, @errorName(err) });
            continue;
        };
        defer file.close(io);
        const stat = try file.stat(io);
        var read_buffer: [1024]u8 = undefined;
        var file_reader: Io.File.Reader = .initSize(file, io, &read_buffer, stat.size);

        archiver.prefix = path.root_dir.path orelse graph.cache.cwd;
        try archiver.writeFile(path.sub_path, &file_reader, @intCast(stat.mtime.toSeconds()));
    }

    // intentionally not calling `archiver.finishPedantically`
    try response.end();
}

fn buildClientWasm(ws: *WebServer, arena: Allocator, optimize: std.builtin.OptimizeMode) !Cache.Path {
    const root_name = "build-web";
    const arch_os_abi = "wasm32-freestanding";
    const cpu_features = "baseline+atomics+bulk_memory+multivalue+mutable_globals+nontrapping_fptoint+reference_types+sign_ext";

    const graph = ws.graph;
    const gpa = graph.cache.gpa;
    const io = graph.io;

    const main_src_path: Cache.Path = .{
        .root_dir = graph.zig_lib_directory,
        .sub_path = "build-web/main.zig",
    };
    const walk_src_path: Cache.Path = .{
        .root_dir = graph.zig_lib_directory,
        .sub_path = "docs/wasm/Walk.zig",
    };
    const html_render_src_path: Cache.Path = .{
        .root_dir = graph.zig_lib_directory,
        .sub_path = "docs/wasm/html_render.zig",
    };

    var argv: std.ArrayList([]const u8) = .empty;

    try argv.appendSlice(arena, &.{
        graph.zig_exe, "build-exe", //
        "-fno-entry", //
        "-O", @tagName(optimize), //
        "-target", arch_os_abi, //
        "-mcpu", cpu_features, //
        "--cache-dir", graph.global_cache_root.path orelse ".", //
        "--global-cache-dir", graph.global_cache_root.path orelse ".", //
        "--zig-lib-dir", graph.zig_lib_directory.path orelse ".", //
        "--name", root_name, //
        "-rdynamic", //
        "-fsingle-threaded", //
        "--dep", "Walk", //
        "--dep", "html_render", //
        try std.fmt.allocPrint(arena, "-Mroot={f}", .{main_src_path}), //
        try std.fmt.allocPrint(arena, "-MWalk={f}", .{walk_src_path}), //
        "--dep", "Walk", //
        try std.fmt.allocPrint(arena, "-Mhtml_render={f}", .{html_render_src_path}), //
        "--listen=-",
    });

    const compile_prog_node = ws.root_prog_node.start("Compile WebAssembly Component", 0);
    defer compile_prog_node.end();

    const result = try std.zig.buildExeSubprocess(gpa, io, .{
        .argv = argv.items,
        .cache_root = graph.global_cache_root,
        .root_name = root_name,
        .arch_os_abi = arch_os_abi,
        .cpu_features = cpu_features,
        .progress_node = compile_prog_node,
    });
    if (!result.cache_hit) log.info("source changes detected; rebuilt wasm component", .{});
    return result.path;
}

pub fn updateTimeReportCompile(ws: *WebServer, opts: struct {
    compile_step: Configuration.Step.Index,

    use_llvm: bool,
    stats: abi.time_report.CompileResult.Stats,
    ns_total: u64,

    llvm_pass_timings_len: u32,
    files_len: u32,
    decls_len: u32,

    /// The trailing data of `abi.time_report.CompileResult`, except the step name.
    trailing: []const u8,
}) void {
    const graph = ws.graph;
    const io = graph.io;
    const configured = &ws.configured.?;
    const maker = configured.maker;
    const gpa = maker.gpa;
    const all_steps = maker.step_stack.keys();

    const step_idx: u32 = for (all_steps, 0..) |s, i| {
        if (s == opts.compile_step) break @intCast(i);
    } else unreachable;

    const old_buf = old: {
        configured.time_report_mutex.lock(io) catch return;
        defer configured.time_report_mutex.unlock(io);
        const old = configured.time_report_msgs[step_idx];
        configured.time_report_msgs[step_idx] = &.{};
        break :old old;
    };
    const buf = gpa.realloc(old_buf, @sizeOf(abi.time_report.CompileResult) + opts.trailing.len) catch @panic("out of memory");

    const out_header: *align(1) abi.time_report.CompileResult = @ptrCast(buf[0..@sizeOf(abi.time_report.CompileResult)]);
    out_header.* = .{
        .step_idx = step_idx,
        .flags = .{
            .use_llvm = opts.use_llvm,
        },
        .stats = opts.stats,
        .ns_total = opts.ns_total,
        .llvm_pass_timings_len = opts.llvm_pass_timings_len,
        .files_len = opts.files_len,
        .decls_len = opts.decls_len,
    };
    @memcpy(buf[@sizeOf(abi.time_report.CompileResult)..], opts.trailing);

    {
        configured.time_report_mutex.lock(io) catch return;
        defer configured.time_report_mutex.unlock(io);
        assert(configured.time_report_msgs[step_idx].len == 0);
        configured.time_report_msgs[step_idx] = buf;
        configured.time_report_update_times[step_idx] = ws.now();
    }
    ws.notifyUpdate();
}

pub fn updateTimeReportGeneric(ws: *WebServer, step_index: Configuration.Step.Index, duration: Io.Duration) void {
    const graph = ws.graph;
    const io = graph.io;
    const configured = &ws.configured.?;
    const maker = configured.maker;
    const gpa = maker.gpa;
    const all_steps = maker.step_stack.keys();

    const step_idx: u32 = for (all_steps, 0..) |s, i| {
        if (s == step_index) break @intCast(i);
    } else unreachable;

    const old_buf = old: {
        configured.time_report_mutex.lock(io) catch return;
        defer configured.time_report_mutex.unlock(io);
        const old = configured.time_report_msgs[step_idx];
        configured.time_report_msgs[step_idx] = &.{};
        break :old old;
    };
    const buf = gpa.realloc(old_buf, @sizeOf(abi.time_report.GenericResult)) catch @panic("out of memory");
    const out: *align(1) abi.time_report.GenericResult = @ptrCast(buf);
    out.* = .{
        .step_idx = step_idx,
        .ns_total = @intCast(duration.toNanoseconds()),
    };
    {
        configured.time_report_mutex.lock(io) catch return;
        defer configured.time_report_mutex.unlock(io);
        assert(configured.time_report_msgs[step_idx].len == 0);
        configured.time_report_msgs[step_idx] = buf;
        configured.time_report_update_times[step_idx] = ws.now();
    }
    ws.notifyUpdate();
}

pub fn updateTimeReportRunTest(
    ws: *WebServer,
    run_step_index: Configuration.Step.Index,
    tests: *const Step.Run.CachedTestMetadata,
    ns_per_test: []const u64,
) void {
    const graph = ws.graph;
    const io = graph.io;
    const configured = &ws.configured.?;
    const maker = configured.maker;
    const gpa = maker.gpa;
    const all_steps = maker.step_stack.keys();

    const step_idx: u32 = for (all_steps, 0..) |s, i| {
        if (s == run_step_index) break @intCast(i);
    } else unreachable;

    assert(tests.names.len == ns_per_test.len);
    const tests_len: u32 = @intCast(tests.names.len);

    const new_len: usize = len: {
        var names_len: usize = 0;
        for (0..tests_len) |i| {
            names_len += tests.testName(@intCast(i)).len + 1;
        }
        break :len @sizeOf(abi.time_report.RunTestResult) + names_len + 8 * tests_len;
    };
    const old_buf = old: {
        configured.time_report_mutex.lock(io) catch return;
        defer configured.time_report_mutex.unlock(io);
        const old = configured.time_report_msgs[step_idx];
        configured.time_report_msgs[step_idx] = &.{};
        break :old old;
    };
    const buf = gpa.realloc(old_buf, new_len) catch @panic("out of memory");

    const out_header: *align(1) abi.time_report.RunTestResult = @ptrCast(buf[0..@sizeOf(abi.time_report.RunTestResult)]);
    out_header.* = .{
        .step_idx = step_idx,
        .tests_len = tests_len,
    };
    var offset: usize = @sizeOf(abi.time_report.RunTestResult);
    const ns_per_test_out: []align(1) u64 = @ptrCast(buf[offset..][0 .. tests_len * 8]);
    @memcpy(ns_per_test_out, ns_per_test);
    offset += tests_len * 8;
    for (0..tests_len) |i| {
        const name = tests.testName(@intCast(i));
        @memcpy(buf[offset..][0..name.len], name);
        buf[offset..][name.len] = 0;
        offset += name.len + 1;
    }
    assert(offset == buf.len);

    {
        configured.time_report_mutex.lock(io) catch return;
        defer configured.time_report_mutex.unlock(io);
        assert(configured.time_report_msgs[step_idx].len == 0);
        configured.time_report_msgs[step_idx] = buf;
        configured.time_report_update_times[step_idx] = ws.now();
    }
    ws.notifyUpdate();
}

const RunnerRequest = union(enum) {
    rebuild,
};
pub fn getRunnerRequest(ws: *WebServer) ?RunnerRequest {
    const io = ws.graph.io;
    ws.runner_request_mutex.lock(io) catch return;
    defer ws.runner_request_mutex.unlock(io);
    if (ws.runner_request) |req| {
        ws.runner_request = null;
        ws.runner_request_empty_cond.signal();
        return req;
    }
    return null;
}
pub fn wait(ws: *WebServer) Io.Cancelable!RunnerRequest {
    const io = ws.graph.io;
    try ws.runner_request_mutex.lock(io);
    defer ws.runner_request_mutex.unlock(io);
    while (true) {
        if (ws.runner_request) |req| {
            ws.runner_request = null;
            ws.runner_request_empty_cond.signal(io);
            return req;
        }
        try ws.runner_request_ready_cond.wait(io, &ws.runner_request_mutex);
    }
}

const cache_control_header: http.Header = .{
    .name = "Cache-Control",
    .value = "max-age=0, must-revalidate",
};
