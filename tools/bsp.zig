//! CLI tool to interface with the build system protocol (zig build --listen=-)

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Configuration = std.Build.Configuration;
const Client = std.zig.Client;
const Server = std.zig.Server;
const log = std.log.scoped(.bsp);

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    const arena = init.arena.allocator();

    var maker_args: std.ArrayList([]const u8) = .empty;

    const args = try init.minimal.args.toSlice(arena);
    for (args[1..]) |arg| {
        try maker_args.append(arena, try arena.dupe(u8, arg));
    }
    if (maker_args.items.len < 1) try maker_args.append(arena, "zig");
    if (maker_args.items.len < 2) try maker_args.append(arena, "build");
    if (!std.mem.eql(u8, maker_args.last().?.*, "--listen=-")) try maker_args.append(arena, "--listen=-");

    log.debug("cmd: {f}", .{std.zig.SubprocessCommand{
        .argv = maker_args.items,
    }});

    var child_process = std.process.spawn(io, .{
        .argv = maker_args.items,
        .stdin = .pipe,
        .stdout = .pipe,
        .stderr = .pipe,
    }) catch |err| std.debug.panic("failed to spawn process: {}", .{err});
    errdefer child_process.kill(io);

    var multi_reader_buffer: Io.File.MultiReader.Buffer(2) = undefined;
    var multi_reader: Io.File.MultiReader = undefined;
    defer multi_reader.deinit();
    multi_reader.init(
        gpa,
        io,
        multi_reader_buffer.toStreams(),
        &.{ child_process.stdout.?, child_process.stderr.? },
    );
    const client_stdout = multi_reader.reader(0);
    const client_stderr = multi_reader.reader(1);

    var client_stdout_buffer: [256]u8 = undefined;
    var client_stdout_writer = child_process.stdin.?.writerStreaming(io, &client_stdout_buffer);

    var client: Client = .{
        .in = client_stdout,
        .out = &client_stdout_writer.interface,
    };

    const err = blk: {
        const handshake: Server.Message.Handshake = handshake: {
            const header = client.receiveMessageWithMultiReader(&multi_reader, .none) catch |err| switch (err) {
                error.Canceled, error.ConcurrencyUnavailable => |e| return e,
                error.Timeout => unreachable,
                else => |e| {
                    log.err("failed to receive message: {t}", .{err});
                    break :blk e;
                },
            };
            const body = client_stdout.take(header.bytes_len) catch unreachable;
            log.debug("received {f} ({d} bytes)", .{ fmtEnum(header.tag), body.len });

            if (header.tag != .bsp_handshake) {
                log.err("received unexpected message: {f}", .{fmtEnum(header.tag)});
                return error.UnexpectedMessage;
            }

            var r: Io.Reader = .fixed(body);
            break :handshake try r.takeStruct(Server.Message.Handshake, .little);
        };
        _ = handshake;

        var conf_arena_allocator: std.heap.ArenaAllocator = .init(gpa);
        defer conf_arena_allocator.deinit();
        const conf_arena = conf_arena_allocator.allocator();

        const configuration = configuration: {
            const header = client.receiveMessageWithMultiReader(&multi_reader, .none) catch |err| switch (err) {
                error.Canceled, error.ConcurrencyUnavailable => |e| return e,
                error.Timeout => unreachable,
                else => |e| {
                    log.err("failed to receive message: {t}", .{err});
                    break :blk e;
                },
            };
            const body = client_stdout.take(header.bytes_len) catch unreachable;
            log.debug("received {t} ({d} bytes)", .{ header.tag, body.len });

            if (header.tag != .bsp_configuration) {
                log.err("received unexpected message: {f}", .{fmtEnum(header.tag)});
                return error.UnexpectedMessage;
            }

            const configuration_path = body;
            var file = Io.Dir.cwd().openFile(io, configuration_path, .{}) catch |err|
                std.debug.panic("failed to open configuration file {q}: {t}", .{ configuration_path, err });
            defer file.close(io);
            break :configuration Configuration.loadFile(conf_arena, io, file) catch |err|
                std.debug.panic("failed to load configuration file {q}: {t}", .{ configuration_path, err });
        };
        const c = &configuration;

        var top_level_steps: std.array_hash_map.String(Configuration.Step.Index) = .empty;
        defer top_level_steps.deinit(gpa);

        for (c.steps, 0..) |*conf_step, step_index_usize| {
            if (conf_step.owner != .root) continue;
            const step_index: Configuration.Step.Index = @fromBackingInt(@intCast(step_index_usize));
            const flags = conf_step.flags(c);
            if (flags.tag != .top_level) continue;
            const name = step_index.ptr(c).name.slice(c);
            try top_level_steps.putNoClobber(gpa, name, step_index);
        }

        std.debug.print("Steps:\n", .{});
        for (top_level_steps.keys()) |name| {
            std.debug.print("  - {q}\n", .{name});
        }
        std.debug.print(
            \\Available Commands:
            \\  - build [step names / step indices]
            \\  - watch [step names / step indices]
            \\  - exit
            \\
        , .{});

        var stdin_reader_buffer: [256]u8 = undefined;
        var stdin_reader = Io.File.stdin().reader(io, &stdin_reader_buffer);
        const stdin = &stdin_reader.interface;

        while (true) {
            try Io.File.stdout().writeStreamingAll(io, "> ");
            const command = try stdin.takeDelimiterExclusive('\n');
            stdin.toss(1);
            if (std.mem.startsWith(u8, command, "build") or
                std.mem.startsWith(u8, command, "watch"))
            {
                var steps: std.ArrayList(Configuration.Step.Index) = .empty;
                defer steps.deinit(gpa);

                const watch = std.mem.startsWith(u8, command, "watch");

                if (std.mem.cutPrefix(u8, command, "build ") orelse
                    std.mem.cutPrefix(u8, command, "watch ")) |command_args|
                {
                    var it = std.mem.tokenizeScalar(u8, command_args, ' ');
                    while (it.next()) |arg| {
                        const step: Configuration.Step.Index =
                            if (std.fmt.parseInt(u32, arg, 10)) |i|
                                @fromBackingInt(i)
                            else |_|
                                top_level_steps.get(arg) orelse std.debug.panic("unexpected step name or index", .{});
                        try steps.append(gpa, step);
                    }
                }

                if (steps.items.len < 1) {
                    try steps.append(gpa, c.default_step);
                }

                try client.serveBuildSteps(steps.items, .{ .watch = watch });

                while (true) {
                    const header: Server.Message.Header = client.receiveMessageWithMultiReader(&multi_reader, .none) catch |err| switch (err) {
                        error.Canceled, error.ConcurrencyUnavailable => |e| return e,
                        error.Timeout => unreachable,
                        else => |e| {
                            log.err("failed to receive message: {t}", .{err});
                            break :blk e;
                        },
                    };
                    const body = client_stdout.take(header.bytes_len) catch unreachable;
                    log.debug("received {f} ({d} bytes)", .{ fmtEnum(header.tag), body.len });

                    switch (header.tag) {
                        .bsp_build_started => {},
                        .bsp_build_completed => if (!watch) break,
                        .bsp_step_started => {},
                        .bsp_step_completed => {},
                        .bsp_configuration => @panic("TODO"),
                        else => std.debug.panic("received unexpected message: {f}", .{fmtEnum(header.tag)}),
                    }
                }
                continue;
            } else if (std.mem.eql(u8, command, "exit")) {
                try client.serveBodylessMessage(.exit);
                break;
            } else {
                log.err("unknown command: {q}", .{command});
                continue;
            }
        }
    };

    try multi_reader.fillRemaining(.none);

    if (client_stderr.bufferedLen() > 0) {
        log.err("stderr:\n{s}\n", .{client_stderr.buffered()});
    }

    try err;

    const term = try child_process.wait(io);

    if (!term.success()) {
        log.err("maker {f}", .{term});
    }
}

const FormatEnum = union(enum) {
    named: []const u8,
    unnamed: usize,

    pub fn format(
        e: FormatEnum,
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        switch (e) {
            .named => |name| {
                try writer.writeByte('.');
                try writer.writeAll(name);
            },
            .unnamed => |number| try writer.print("0x{x}", .{number}),
        }
    }
};

fn fmtEnum(e: anytype) FormatEnum {
    if (std.enums.tagName(@TypeOf(e), e)) |name| {
        return .{ .named = name };
    } else {
        return .{ .unnamed = @backingInt(e) };
    }
}
