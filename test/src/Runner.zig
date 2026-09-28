const assert = std.debug.assert;
const std = @import("std");
const Runner = @This();
const zig_version_string = @import("builtin").zig_version_string;

gpa: std.mem.Allocator,
arena: *std.heap.ArenaAllocator,
io: std.Io,
prog_node: std.Progress.Node,
args: Args,
host: std.Target,
server: std.zig.Server,
eb_wip: std.zig.ErrorBundle.Wip,

const Args = struct {
    @"test": ?struct {
        input_dir: std.zig.Server.Message.InputDir,
        dir: std.Io.Dir,
    },
    manifest_file: ?std.Io.File,
    zig_exe: ?std.Io.File,
    lib_dir: ?std.Io.Dir,
    src_dir: ?std.Io.Dir,
    targets: std.ArrayList(u32),
    target_bytes: std.ArrayList(u8),
    libc_runtimes_dir: ?std.Io.Dir,
    enable_darling: bool,
    enable_qemu: bool,
    enable_rosetta: bool,
    enable_wasmtime: bool,
    enable_wine: bool,
    quiet: bool,

    fn deinit(args: *Args, gpa: std.mem.Allocator) void {
        args.targets.deinit(gpa);
        args.target_bytes.deinit(gpa);
        args.* = undefined;
    }

    fn addTarget(args: *Args, gpa: std.mem.Allocator, target: []const u8) std.mem.Allocator.Error!void {
        try args.target_bytes.ensureUnusedCapacity(gpa, target.len + 1);
        try args.targets.append(gpa, @intCast(args.target_bytes.items.len));
        args.target_bytes.appendSliceAssumeCapacity(target);
        args.target_bytes.appendAssumeCapacity(0);
    }
};

fn deinit(runner: *Runner) void {
    runner.prog_node.end();
    runner.args.deinit(runner.gpa);
    runner.eb_wip.deinit();
    runner.* = undefined;
}

const FailError = error{AlreadyReported} || std.mem.Allocator.Error || std.Io.Cancelable;
fn fail(runner: *Runner, comptime fmt: []const u8, args: anytype) FailError {
    return runner.failString(try runner.eb_wip.printString(fmt, args));
}
fn failString(runner: *Runner, msg: std.zig.ErrorBundle.String) FailError {
    try runner.eb_wip.addRootErrorMessage(.{
        .msg = msg,
    });
    return error.AlreadyReported;
}

pub const ProtocolError = error{
    ServerReadFailed,
    ServerWriteFailed,
    ServerEndOfStream,
} || FailError;
pub fn runServer(runner: *Runner) ProtocolError {
    runner.server.serveStringMessage(.zig_version, zig_version_string) catch |err| switch (err) {
        error.WriteFailed => return error.ServerWriteFailed,
    };
    while (true) {
        _ = runner.arena.reset(.retain_capacity);
        const arena = runner.arena.allocator();
        const hdr = runner.server.receiveMessage() catch |err| switch (err) {
            error.ReadFailed => return error.ServerReadFailed,
            error.EndOfStream => return error.ServerEndOfStream,
        };
        switch (hdr.tag) {
            else => |tag| return runner.fail("unsupported message: {t}", .{tag}),
            .exit => std.process.exit(0),
            .args => {
                const args_body = try arena.alloc(u8, hdr.bytes_len);
                runner.server.in.readSliceAll(args_body) catch unreachable;
                const State = enum {
                    positional,
                    @"--zig",
                    @"--lib",
                    @"--src",
                    @"--target",
                    @"--libc-runtimes",
                };
                var state: State = .positional;
                const state_expected: std.enums.EnumArray(State, enum {
                    path,
                    dir,
                    file,
                    string,
                }) = .init(.{
                    .positional = .path,
                    .@"--zig" = .file,
                    .@"--lib" = .dir,
                    .@"--src" = .dir,
                    .@"--target" = .string,
                    .@"--libc-runtimes" = .dir,
                });
                var input_dir: std.zig.Server.Message.InputDir = .cwd;
                var args_body_offset: usize = 0;
                while (args_body.len - args_body_offset > 0) {
                    const arg: std.zig.Client.Message.Arg =
                        @fromBackingInt(args_body[args_body_offset]);
                    args_body_offset += 1;
                    arg: switch (arg) {
                        .string => {
                            const end = std.mem.findScalarPos(u8, args_body, args_body_offset, 0).?;
                            const string = args_body[args_body_offset..end];
                            args_body_offset = end + 1;
                            switch (state) {
                                .positional => if (std.mem.eql(u8, string, "--target")) {
                                    state = .@"--target";
                                    continue;
                                } else if (std.mem.cutPrefix(u8, string, "--target=")) |target| {
                                    try runner.args.addTarget(runner.gpa, target);
                                } else if (std.mem.eql(u8, string, "--libc-runtimes")) {
                                    state = .@"--libc-runtimes";
                                    continue;
                                } else if (std.mem.eql(u8, string, "-fdarling")) {
                                    runner.args.enable_darling = true;
                                } else if (std.mem.eql(u8, string, "-fqemu")) {
                                    runner.args.enable_qemu = true;
                                } else if (std.mem.eql(u8, string, "-frosetta")) {
                                    runner.args.enable_rosetta = true;
                                } else if (std.mem.eql(u8, string, "-fwasmtime")) {
                                    runner.args.enable_wasmtime = true;
                                } else if (std.mem.eql(u8, string, "-fwine")) {
                                    runner.args.enable_wine = true;
                                } else if (std.mem.eql(u8, string, "--quiet")) {
                                    runner.args.quiet = true;
                                },
                                .@"--target" => try runner.args.addTarget(runner.gpa, string),
                                else => return runner.fail(
                                    "\"{t}\" expected {t}, got {t}",
                                    .{ state, state_expected.get(state), arg },
                                ),
                            }
                        },
                        .prefix => {
                            const end = std.mem.findScalarPos(u8, args_body, args_body_offset, 0).?;
                            const string = args_body[args_body_offset..end];
                            args_body_offset = end + 1;
                            assert(state == .positional);
                            state = if (std.mem.eql(u8, string, "--zig="))
                                .@"--zig"
                            else if (std.mem.eql(u8, string, "--lib="))
                                .@"--lib"
                            else if (std.mem.eql(u8, string, "--src="))
                                .@"--src"
                            else if (std.mem.eql(u8, string, "--libc-runtimes="))
                                .@"--libc-runtimes"
                            else
                                return runner.fail("unsupported arg prefix: {q}", .{string});
                            continue;
                        },
                        .suffix => {
                            const end = std.mem.findScalarPos(u8, args_body, args_body_offset, 0).?;
                            const string = args_body[args_body_offset..end];
                            args_body_offset = end + 1;
                            return runner.fail("unsupported arg suffix: {q}", .{string});
                        },
                        .input_dir => {
                            input_dir = @fromBackingInt(@backingInt(input_dir) + 1);
                            continue :arg .output_dir;
                        },
                        .output_dir => {
                            const dir_handle: *align(1) const std.Io.Dir.Handle = @ptrCast(
                                args_body[args_body_offset..][0..@sizeOf(std.Io.Dir.Handle)],
                            );
                            args_body_offset += @sizeOf(std.Io.Dir.Handle);
                            const dir = runner.io.vtable.inheritParentDir(
                                runner.io.userdata,
                                dir_handle.*,
                            ) catch |err| switch (err) {
                                error.Canceled => |e| return e,
                                else => |e| return runner.fail(
                                    "unable to inherit parent dir: {t}",
                                    .{e},
                                ),
                            };
                            switch (state) {
                                .positional => {
                                    if (runner.args.@"test" != null or
                                        runner.args.manifest_file != null) return runner.fail(
                                        "{t} specified multiple times",
                                        .{state},
                                    );
                                    runner.args.@"test" = .{ .input_dir = input_dir, .dir = dir };
                                    const manifest_path = "manifest";
                                    runner.args.manifest_file = dir.openFile(
                                        runner.io,
                                        manifest_path,
                                        .{},
                                    ) catch |err| switch (err) {
                                        error.Canceled => |e| return e,
                                        else => |e| return runner.fail(
                                            "unable to open manifest file: {t}",
                                            .{e},
                                        ),
                                    };
                                    try runner.discoverInput(input_dir, manifest_path);
                                },
                                .@"--lib" => {
                                    if (runner.args.lib_dir != null) return runner.fail(
                                        "\"{t}\" specified multiple times",
                                        .{state},
                                    );
                                    runner.args.lib_dir = dir;
                                },
                                .@"--src" => {
                                    if (runner.args.src_dir != null) return runner.fail(
                                        "\"{t}\" specified multiple times",
                                        .{state},
                                    );
                                    runner.args.src_dir = dir;
                                },
                                .@"--libc-runtimes" => {
                                    if (runner.args.libc_runtimes_dir != null) return runner.fail(
                                        "\"{t}\" specified multiple times",
                                        .{state},
                                    );
                                    runner.args.libc_runtimes_dir = dir;
                                },
                                else => return runner.fail(
                                    "\"{t}\" expected {t}, got {t}",
                                    .{ state, state_expected.get(state), arg },
                                ),
                            }
                        },
                        .input_file, .input_file_content, .output_file => {
                            const file_handle: *align(1) const std.Io.File.Handle = @ptrCast(
                                args_body[args_body_offset..][0..@sizeOf(std.Io.File.Handle)],
                            );
                            args_body_offset += @sizeOf(std.Io.File.Handle);
                            const file = runner.io.vtable.inheritParentFile(
                                runner.io.userdata,
                                file_handle.*,
                                .{ .nonblocking = false },
                            ) catch |err| switch (err) {
                                error.Canceled => |e| return e,
                                else => |e| return runner.fail(
                                    "unable to inherit parent file: {t}",
                                    .{e},
                                ),
                            };
                            switch (state) {
                                .positional => {
                                    if (runner.args.@"test" != null or
                                        runner.args.manifest_file != null) return runner.fail(
                                        "{t} specified multiple times",
                                        .{state},
                                    );
                                    runner.args.manifest_file = file;
                                },
                                .@"--zig" => {
                                    if (runner.args.zig_exe != null) return runner.fail(
                                        "\"{t}\" specified multiple times",
                                        .{state},
                                    );
                                    runner.args.zig_exe = file;
                                },
                                else => return runner.fail(
                                    "\"{t}\" expected {t}, got {t}",
                                    .{ state, state_expected.get(state), arg },
                                ),
                            }
                        },
                    }
                    state = .positional;
                }
            },
            .query_test_metadata => {
                const expected_panic_msgs = try arena.alloc(u32, runner.args.targets.items.len);
                @memset(expected_panic_msgs, 0);
                runner.server.serveTestMetadata(.{
                    .names = runner.args.targets.items,
                    .expected_panic_msgs = expected_panic_msgs,
                    .string_bytes = runner.args.target_bytes.items,
                }) catch |err| switch (err) {
                    error.WriteFailed => return error.ServerWriteFailed,
                };
            },
            .run_test => {
                const test_index = runner.server.receiveBody_u32() catch unreachable;
                runner.server.serveBodylessMessage(.test_started) catch |err| switch (err) {
                    error.WriteFailed => return error.ServerWriteFailed,
                };
                runner.server.serveTestResults(.{
                    .index = test_index,
                    .flags = .{
                        .status = if (runner.testOne(test_index))
                            .pass
                        else |err| status: switch (err) {
                            error.Canceled,
                            error.OutOfMemory,
                            error.ServerWriteFailed,
                            => |e| return e,
                            error.AlreadyReported => {
                                var eb = try runner.eb_wip.toOwnedBundle("");
                                defer eb.deinit(runner.gpa);
                                assert(eb.errorMessageCount() > 0); // already reported what?
                                runner.server.serveErrorBundle(
                                    .error_bundle,
                                    eb,
                                ) catch |server_err| switch (server_err) {
                                    error.WriteFailed => return error.ServerWriteFailed,
                                };
                                const eb_wip: std.zig.ErrorBundle.Wip = try .init(runner.gpa);
                                runner.eb_wip.deinit();
                                runner.eb_wip = eb_wip;
                                break :status .fail;
                            },
                            error.SkipTest => .skip,
                        },
                        .fuzz = false,
                        .log_err_count = 0,
                        .leak_count = 0,
                    },
                }) catch |err| switch (err) {
                    error.WriteFailed => return error.ServerWriteFailed,
                };
                assert(runner.eb_wip.root_list.items.len == 0); // failed to report
            },
        }
    }
}

fn discoverInput(
    runner: *Runner,
    dir: std.zig.Server.Message.InputDir,
    sub_path: []const u8,
) error{ServerWriteFailed}!void {
    return runner.discoverInputInner(dir, sub_path) catch |err| switch (err) {
        error.WriteFailed => return error.ServerWriteFailed,
    };
}
fn discoverInputInner(
    runner: *Runner,
    dir: std.zig.Server.Message.InputDir,
    sub_path: []const u8,
) std.Io.Writer.Error!void {
    try runner.server.serveMessageHeader(.{
        .tag = .discovered_inputs,
        .bytes_len = @intCast(@sizeOf(std.zig.Server.Message.InputDir) +
            sub_path.len + 1),
    });
    try runner.server.out.writeInt(u32, @backingInt(dir), .little);
    try runner.server.out.writeAll(sub_path);
    try runner.server.out.writeByte(0);
    try runner.server.out.flush();
}

pub const SourceReader = struct {
    const Io = std.Io;

    backing: *std.Io.Reader,
    line_aw: std.Io.Writer.Allocating,
    interface: std.Io.Reader,
    line: u32,
    eb_wip: *std.zig.ErrorBundle.Wip,
    src_path: std.zig.ErrorBundle.String,

    pub fn init(
        reader: *Io.Reader,
        gpa: std.mem.Allocator,
        eb_wip: *std.zig.ErrorBundle.Wip,
        src_path: std.zig.ErrorBundle.String,
    ) SourceReader {
        return .{
            .backing = reader,
            .line_aw = .init(gpa),
            .interface = .{
                .vtable = &.{
                    .stream = stream,
                    .discard = discard,
                    .readVec = readVec,
                    .rebase = rebase,
                },
                .buffer = &.{},
                .seek = 0,
                .end = 0,
            },
            .line = 0,
            .eb_wip = eb_wip,
            .src_path = src_path,
        };
    }
    fn deinit(s: *SourceReader) void {
        s.line_aw.deinit();
    }
    fn stream(r: *Io.Reader, _: *Io.Writer, _: Io.Limit) Io.Reader.StreamError!usize {
        const s: *SourceReader = @fieldParentPtr("interface", r);
        try s.bufferLine();
        return 0;
    }
    fn discard(r: *Io.Reader, limit: Io.Limit) Io.Reader.Error!usize {
        const s: *SourceReader = @fieldParentPtr("interface", r);
        const remaining = r.buffered();
        if (remaining.len > 0) {
            const n = limit.minInt(remaining.len);
            r.toss(n);
            return n;
        }
        try s.bufferLine();
        return 0;
    }
    fn readVec(r: *Io.Reader, _: [][]u8) Io.Reader.Error!usize {
        const s: *SourceReader = @fieldParentPtr("interface", r);
        try s.bufferLine();
        return 0;
    }
    fn rebase(r: *Io.Reader, capacity: usize) Io.Reader.RebaseError!void {
        const s: *SourceReader = @fieldParentPtr("interface", r);
        defer s.updateBuffer();
        s.line_aw.ensureUnusedCapacity(capacity) catch |err| switch (err) {
            error.OutOfMemory => return error.ReadFailed,
        };
    }
    fn updateBuffer(s: *SourceReader) void {
        s.interface.buffer = s.line_aw.writer.buffer;
        s.interface.end = s.line_aw.writer.end;
    }
    fn bufferLine(s: *SourceReader) Io.Reader.Error!void {
        defer s.updateBuffer();
        {
            const written = s.line_aw.written();
            const start = if (std.mem.findScalarLast(u8, written[0..s.interface.seek], '\n')) |newline|
                newline + 1
            else
                0;
            s.line += @intCast(std.mem.countScalar(u8, written[0..start], '\n'));
            const preserve = written[start..];
            @memmove(written[0..preserve.len], preserve);
            s.line_aw.shrinkRetainingCapacity(preserve.len);
            s.interface.seek -= start;
        }
        const n = s.backing.streamDelimiterEnding(&s.line_aw.writer, '\n') catch |err| switch (err) {
            error.ReadFailed => |e| return e,
            error.WriteFailed => return error.ReadFailed,
        };
        if (std.mem.endsWith(u8, s.line_aw.written(), "\r")) s.line_aw.writer.end -= 1;
        const buffered = s.backing.buffered();
        if (n == 0 and buffered.len == 0) return error.EndOfStream;
        if (std.mem.startsWith(u8, buffered, "\n")) {
            s.line_aw.writer.writeByte('\n') catch |err| switch (err) {
                error.WriteFailed => return error.ReadFailed,
            };
            s.backing.toss(1);
        }
    }
    fn fail(
        s: *SourceReader,
        src_loc: []const u8,
        comptime fmt: []const u8,
        args: anytype,
    ) FailError {
        return s.failString(src_loc, try s.eb_wip.printString(fmt, args));
    }
    fn failString(
        s: *SourceReader,
        src_loc: []const u8,
        msg: std.zig.ErrorBundle.String,
    ) FailError {
        const line: u32, const column: u32, const source_line = src_loc: {
            const pos = src_loc.ptr - s.interface.buffer.ptr;
            const end = std.mem.findScalarPos(u8, s.interface.buffer, pos, '\n') orelse
                s.interface.buffer.len;
            const start = if (std.mem.findScalarLast(u8, s.interface.buffer[0..end], '\n')) |newline|
                newline + 1
            else
                0;
            break :src_loc .{
                @intCast(s.line + std.mem.countScalar(u8, s.interface.buffer[0..start], '\n')),
                @intCast(pos - start),
                s.interface.buffer[start..end],
            };
        };
        try s.eb_wip.addRootErrorMessage(.{
            .msg = msg,
            .src_loc = try s.eb_wip.addSourceLocation(.{
                .src_path = s.src_path,
                .line = line,
                .column = column,
                .span_start = column,
                .span_main = column,
                .span_end = @intCast(column + src_loc.len),
                .source_line = try s.eb_wip.addString(source_line),
            }),
        });
        return error.AlreadyReported;
    }
};
pub const DelimitedReader = struct {
    const Io = std.Io;

    unlimited: *Io.Reader,
    remaining: Io.Limit,
    delimiter: []const u8,
    interface: Io.Reader,

    pub fn init(reader: *Io.Reader, delimiter: []const u8, buffer: []u8) DelimitedReader {
        return .{
            .unlimited = reader,
            .remaining = .nothing,
            .delimiter = delimiter,
            .interface = .{
                .vtable = &.{
                    .stream = stream,
                    .discard = discard,
                },
                .buffer = buffer,
                .seek = 0,
                .end = 0,
            },
        };
    }
    fn stream(r: *Io.Reader, w: *Io.Writer, limit: Io.Limit) Io.Reader.StreamError!usize {
        const d: *DelimitedReader = @fieldParentPtr("interface", r);
        const block = try d.unlimited.peekGreedy(d.delimiter.len);
        d.remaining = .limited(std.mem.findPos(u8, block, d.remaining.toInt().?, d.delimiter) orelse
            block.len - d.delimiter.len + 1);
        if (d.remaining == .nothing) return error.EndOfStream;
        const n = try d.unlimited.stream(w, limit.min(d.remaining));
        d.remaining = d.remaining.subtract(n).?;
        return n;
    }
    fn discard(r: *Io.Reader, limit: Io.Limit) Io.Reader.Error!usize {
        const d: *DelimitedReader = @fieldParentPtr("interface", r);
        const block = try d.unlimited.peekGreedy(d.delimiter.len);
        d.remaining = .limited(std.mem.findPos(u8, block, d.remaining.toInt().?, d.delimiter) orelse
            block.len - d.delimiter.len + 1);
        if (d.remaining == .nothing) return error.EndOfStream;
        const n = try d.unlimited.discard(limit.min(d.remaining));
        d.remaining = d.remaining.subtract(n).?;
        return n;
    }
};

const Update = struct {
    target_query: []const u8,
    manifest_sr: SourceReader,
    compiler: ?Compiler,
    src_dir: std.Io.Dir,
    prog_node: std.Progress.Node,
    mtime: std.Io.Timestamp,
    num: usize,
    allow_skip: bool,
};

const TestError = error{
    SkipTest,
} || FailError;
fn testOne(runner: *Runner, test_index: u32) (error{ServerWriteFailed} || TestError)!void {
    const target_query =
        std.mem.sliceTo(runner.args.target_bytes.items[runner.args.targets.items[test_index]..], 0);
    const manifest_file = runner.args.manifest_file orelse
        return runner.fail("missing \"path/to/test\" arg", .{});
    var manifest_buffer: [512]u8 = undefined;
    var manifest_fr = manifest_file.reader(runner.io, &manifest_buffer);
    var update: Update = .{
        .target_query = target_query,
        .manifest_sr = .init(&manifest_fr.interface, runner.gpa, &runner.eb_wip, src_path_string: {
            var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
            const src_path = src_path: {
                break :src_path path_buffer[0 .. manifest_file.realPath(
                    runner.io,
                    &path_buffer,
                ) catch |err| switch (err) {
                    error.Canceled => |e| return e,
                    else => break :src_path "manifest",
                }];
            };
            break :src_path_string try runner.eb_wip.addString(src_path);
        }),
        .compiler = null,
        .src_dir = (runner.args.src_dir orelse
            return runner.fail("missing \"--src=path/to/src\" arg", .{})).createDirPathOpen(
            runner.io,
            target_query,
            .{},
        ) catch |err| switch (err) {
            error.Canceled => |e| return e,
            else => |e| return runner.fail("unable to create {q}: {t}", .{ target_query, e }),
        },
        .prog_node = .none,
        .mtime = .now(runner.io, .real),
        .num = 0,
        .allow_skip = true,
    };
    defer {
        update.manifest_sr.deinit();
        update.src_dir.close(runner.io);
        update.prog_node.end();
    }

    // hack around `std.Io.Reader` interface bugs by ensuring the
    // buffer is larger than the longest supported manifest line
    try update.manifest_sr.line_aw.ensureTotalCapacityPrecise(512);
    update.manifest_sr.updateBuffer();

    var skip_delimiter = false;
    while (update.manifest_sr.interface.takeSentinel('\n')) |line| {
        var line_it = std.mem.tokenizeScalar(u8, line, ' ');
        const cmd_src_loc = line_it.next() orelse continue;
        if (skip_delimiter) {
            assert(std.mem.eql(u8, cmd_src_loc, "#}"));
            skip_delimiter = false;
            const unexpected = line_it.rest();
            if (unexpected.len > 0)
                return update.manifest_sr.fail(unexpected, "unexpected argument {q}", .{unexpected});
            continue;
        }
        const cmd = std.meta.stringToEnum(Command, std.mem.cutPrefix(u8, cmd_src_loc, "#") orelse
            return update.manifest_sr.fail(cmd_src_loc, "expected command", .{})) orelse
            return update.manifest_sr.fail(cmd_src_loc, "unknown command", .{});
        const arg = switch (cmd) {
            .todo, .exe, .lib, .obj, .update => null,
            .skip, .write, .delete, .check => line_it.next() orelse
                return update.manifest_sr.fail(line_it.rest()[0..0], "missing argument", .{}),
        };
        var contents_file: ?std.Io.File = null;
        defer if (contents_file) |file| file.close(runner.io);
        var contents_buffer: [512]u8 = undefined;
        var contents_impl: union(enum) {
            ending: std.Io.Reader,
            dr: DelimitedReader,
            fr: std.Io.File.Reader,
        } = undefined;
        const contents_r: *std.Io.Reader = contents_r: switch (cmd) {
            .skip, .delete => {
                const unexpected = line_it.rest();
                if (unexpected.len > 0) return update.manifest_sr.fail(
                    unexpected,
                    "unexpected argument {q}",
                    .{unexpected},
                );
                contents_impl = .{ .ending = .ending_instance };
                break :contents_r &contents_impl.ending;
            },
            else => {
                const contents_path = line_it.rest();
                if (contents_path.len == 0) {
                    contents_impl = .{ .ending = .ending_instance };
                    break :contents_r &contents_impl.ending;
                }

                if (std.mem.eql(u8, contents_path, "{")) {
                    contents_impl = .{
                        .dr = .init(&update.manifest_sr.interface, "#}", &contents_buffer),
                    };
                    skip_delimiter = true;
                    break :contents_r &contents_impl.dr.interface;
                }

                const args_test = runner.args.@"test" orelse return update.manifest_sr.fail(
                    contents_path,
                    "contents file requires directory test",
                    .{},
                );
                try runner.discoverInput(args_test.input_dir, contents_path);

                contents_file =
                    args_test.dir.openFile(runner.io, contents_path, .{}) catch |err| switch (err) {
                        error.Canceled => |e| return e,
                        else => |e| return update.manifest_sr.fail(
                            contents_path,
                            "unable to open contents file: {t}",
                            .{e},
                        ),
                    };
                contents_impl = .{ .fr = contents_file.?.reader(runner.io, &contents_buffer) };
                break :contents_r &contents_impl.fr.interface;
            },
        };

        runner.handleCommand(&update, cmd_src_loc, cmd, arg, contents_r) catch |err| switch (err) {
            error.Canceled,
            error.OutOfMemory,
            error.AlreadyReported,
            error.SkipTest,
            => |e| return e,
            error.ContentsReadFailed => switch (contents_impl) {
                .ending => unreachable,
                .dr => switch (manifest_fr.err orelse return error.OutOfMemory) {
                    error.Canceled => |e| return e,
                    else => |e| return runner.fail("unable to read manifest: {t}", .{e}),
                },
                .fr => |fr| switch (fr.err.?) {
                    error.Canceled => |e| return e,
                    else => |e| return runner.fail("unable to read contents file: {t}", .{e}),
                },
            },
        };
    } else |err| switch (err) {
        error.ReadFailed => switch (manifest_fr.err orelse return error.OutOfMemory) {
            error.Canceled => |e| return e,
            else => |e| return runner.fail("unable to read manifest: {t}", .{e}),
        },
        error.StreamTooLong => unreachable,
        error.EndOfStream => if (skip_delimiter)
            return runner.fail("manifest missing \"#}}\" delimiter", .{}),
    }
    if (update.compiler) |*comp| {
        if (comp.state != .idle) return runner.fail("missing \"#check\"", .{});
        try comp.exit();
    }
}
const Command = enum { todo, skip, exe, lib, obj, write, delete, update, check };
fn handleCommand(
    runner: *Runner,
    update: *Update,
    cmd_src_loc: []const u8,
    cmd: Command,
    arg: ?[]const u8,
    contents_r: *std.Io.Reader,
) (error{ContentsReadFailed} || TestError)!void {
    var name_buffer: [std.Progress.Node.max_name_len]u8 = undefined;
    const cmd_prog_node = runner.prog_node.start(std.mem.print(&name_buffer, "#{t}{s}{s}", .{
        cmd, if (arg) |_| " " else "", arg orelse "",
    }) catch &name_buffer, 0);
    defer cmd_prog_node.end();

    cmd: switch (cmd) {
        .todo => _ = contents_r.discardRemaining() catch |err| switch (err) {
            error.ReadFailed => {},
        },
        .skip => if (!update.allow_skip) return update.manifest_sr.fail(
            cmd_src_loc,
            "\"#skip\" must appear before other commands",
            .{},
        ) else if (std.mem.eql(u8, update.target_query, arg.?)) return error.SkipTest,
        .exe, .lib, .obj => runner.spawnCompiler(&update.compiler, update.src_dir, switch (cmd) {
            else => unreachable,
            .exe => .Exe,
            .lib => .Lib,
            .obj => .Obj,
        }, contents_r, target: {
            const backend_split = std.mem.findScalarLast(u8, update.target_query, '-') orelse
                return runner.fail("target {q} missing query", .{update.target_query});
            const mode_split =
                std.mem.findScalarLast(u8, update.target_query[0..backend_split], '-') orelse
                return runner.fail("target {q} missing mode", .{update.target_query});
            const triple = update.target_query[0..mode_split];
            const backend_str = update.target_query[backend_split + 1 ..];
            const backend = std.meta.stringToEnum(Compiler.Target.Backend, backend_str) orelse
                return runner.fail("target {q} unknown backend {q}", .{
                    update.target_query, backend_str,
                });
            const mode_str = update.target_query[mode_split + 1 .. backend_split];
            const mode = std.meta.stringToEnum(Compiler.Target.Mode, mode_str) orelse
                return runner.fail("target {q} unknown mode {q}", .{ update.target_query, mode_str });
            break :target .{
                .triple = triple,
                .resolved = std.zig.system.resolveTargetQuery(
                    runner.io,
                    std.Build.parseTargetQuery(.{
                        .arch_os_abi = triple,
                        .object_format = switch (backend) {
                            .sema, .selfhosted, .llvm => null,
                            .cbe => "c",
                        },
                    }) catch |err| switch (err) {
                        error.ParseFailed => return runner.fail("unable to parse triple {q}", .{
                            triple,
                        }),
                    },
                ) catch |err| switch (err) {
                    error.Canceled => |e| return e,
                    else => |e| return runner.fail("unable to resolve target {q}: {t}", .{ triple, e }),
                },
                .mode = mode,
                .backend = backend,
            };
        }) catch |err| switch (err) {
            error.Canceled, error.OutOfMemory, error.AlreadyReported => |e| return e,
            error.ReadFailed => return error.ContentsReadFailed,
        },
        .write => {
            const file = update.src_dir.createFile(runner.io, arg.?, .{}) catch |err| switch (err) {
                error.Canceled => |e| return e,
                else => |e| return update.manifest_sr.fail(arg.?, "unable to create file: {t}", .{e}),
            };
            defer file.close(runner.io);
            var fw_buffer: [512]u8 = undefined;
            var fw = file.writer(runner.io, &fw_buffer);
            _ = contents_r.streamRemaining(&fw.interface) catch |err| switch (err) {
                error.ReadFailed => return error.ContentsReadFailed,
                error.WriteFailed => switch (fw.err.?) {
                    error.Canceled => |e| return e,
                    else => |e| return update.manifest_sr.fail(
                        arg.?,
                        "unable to write file: {t}",
                        .{e},
                    ),
                },
            };
            fw.flush() catch |err| switch (err) {
                error.Canceled => |e| return e,
                else => |e| return update.manifest_sr.fail(
                    arg.?,
                    "unable to write file: {t}",
                    .{e},
                ),
            };
            file.setTimestamps(runner.io, .{ .modify_timestamp = .{
                .new = update.mtime,
            } }) catch |err| switch (err) {
                error.Canceled => |e| return e,
                else => |e| return update.manifest_sr.fail(
                    arg.?,
                    "unable to update file timestamps: {t}",
                    .{e},
                ),
            };
        },
        .delete => update.src_dir.deleteFile(runner.io, arg.?) catch |err| switch (err) {
            error.Canceled => |e| return e,
            else => |e| return update.manifest_sr.fail(arg.?, "unable to delete file: {t}", .{e}),
        },
        .update => {
            const comp = &(update.compiler orelse return update.manifest_sr.fail(
                cmd_src_loc,
                "missing \"#exe\", \"#lib\", or \"#obj\"",
                .{},
            ));
            update.prog_node.end();
            update.prog_node = runner.prog_node.start(
                switch (contents_r.readSliceShort(&name_buffer) catch |err| switch (err) {
                    error.ReadFailed => return error.ContentsReadFailed,
                }) {
                    0 => switch (update.num) {
                        0 => "initial update",
                        else => |num| std.mem.print(&name_buffer, "update {d}", .{num}) catch
                            &name_buffer,
                    },
                    else => |name_len| name_buffer[0..name_len],
                },
                0,
            );
            _ = contents_r.discardRemaining() catch |err| switch (err) {
                error.ReadFailed => return error.ContentsReadFailed,
            };
            if (comp.state != .idle)
                return update.manifest_sr.fail(cmd_src_loc, "missing \"#check\"", .{});
            comp.client.serveBodylessMessage(.update) catch |err| switch (err) {
                error.WriteFailed => switch (comp.fw.err.?) {
                    error.Canceled => |e| return e,
                    else => |e| return runner.fail("unable to send message to compiler: {t}", .{e}),
                },
            };
            comp.state = .update;
            update.mtime = update.mtime.addDuration(.fromSeconds(2));
            update.num += 1;
        },
        .check => {
            const check = std.meta.stringToEnum(Compiler.Check, arg.?) orelse
                return update.manifest_sr.fail(arg.?, "unknown check", .{});
            const expected =
                contents_r.allocRemaining(runner.gpa, .unlimited) catch |err| switch (err) {
                    error.OutOfMemory => |e| return e,
                    error.ReadFailed => return error.ContentsReadFailed,
                    error.StreamTooLong => unreachable, // .unlimited
                };
            defer runner.gpa.free(expected);

            const comp = &(update.compiler orelse return update.manifest_sr.fail(
                cmd_src_loc,
                "missing \"#exe\", \"#lib\", or \"#obj\"",
                .{},
            ));
            if (comp.state != .update)
                return update.manifest_sr.fail(cmd_src_loc, "missing \"#update\"", .{});
            const stderr = comp.mr.reader(1);
            while (try comp.receiveMessage()) |message| switch (message.tag) {
                else => {}, // Ignore other messages,
                .config => {
                    var body_r: std.Io.Reader = .fixed(message.body);
                    comp.config = body_r.takeStruct(std.zig.Server.Message.Config, .little) catch
                        unreachable;
                },
                .emit_digest => {
                    var body_r: std.Io.Reader = .fixed(message.body);
                    _ = body_r.takeStruct(std.zig.Server.Message.EmitDigest, .little) catch
                        unreachable;
                    const digest = body_r.takeArray(std.Build.Cache.bin_digest_len) catch
                        unreachable;
                    try comp.checkSuccess(check, expected, update.src_dir, digest);
                },
                .error_bundle => {
                    const eb = std.zig.Server.allocErrorBundle(
                        runner.arena.allocator(),
                        message.body,
                    ) catch |err| switch (err) {
                        error.OutOfMemory => |e| return e,
                        error.EndOfStream => return runner.fail("error bundle truncated", .{}),
                    };
                    switch (check) {
                        .errors => {
                            var error_aw: std.Io.Writer.Allocating = .init(runner.gpa);
                            defer error_aw.deinit();
                            eb.renderToWriter(.{
                                .include_reference_trace = false,
                                .include_source_line = false,
                                .include_log_text = true,
                            }, &error_aw.writer) catch |err| switch (err) {
                                error.WriteFailed => return error.OutOfMemory,
                            };
                            const actual = error_aw.written();
                            std.mem.replaceScalar(u8, actual, '\\', '/');
                            std.testing.expectEqualStrings(expected, actual) catch |err| switch (err) {
                                error.TestExpectedEqual => return runner.fail(
                                    "errors did not match expected",
                                    .{},
                                ),
                            };
                        },
                        .stdout, .exit, .lldb => if (eb.errorMessageCount() > 0) {
                            eb.renderToStderr(runner.io, .{}, .auto) catch |err| switch (err) {
                                error.Canceled => {},
                                else => {},
                            };
                            return runner.fail("unexpected compile errors", .{});
                        },
                    }
                    comp.state = .idle;
                    break :cmd;
                },
            };

            const buffered_stderr = stderr.buffered();
            if (buffered_stderr.len > 0) {
                if (comp.allow_compiler_stderr) {
                    std.log.info("stderr:\n{s}", .{buffered_stderr});
                } else {
                    return runner.fail("unexpected stderr:\n{s}", .{buffered_stderr});
                }
            }

            try comp.exit();
            return runner.fail("compiler failed to send terminating error_bundle", .{});
        },
    }
    assert(contents_r.discardRemaining() catch |err| switch (err) {
        error.ReadFailed => return error.ContentsReadFailed,
    } == 0);
    switch (cmd) {
        .todo, .skip => {},
        else => update.allow_skip = false,
    }
}

fn spawnCompiler(
    runner: *Runner,
    compiler: *?Compiler,
    src_dir: std.Io.Dir,
    output_mode: std.lang.OutputMode,
    args_r: *std.Io.Reader,
    target: Compiler.Target,
) (std.Io.Reader.ShortError || FailError)!void {
    const gpa = runner.gpa;
    const arena = runner.arena.allocator();
    if (compiler.*) |*comp| {
        try comp.exit();
        compiler.* = null;
    }

    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(gpa);
    try argv.appendSlice(gpa, &.{
        "zig",
        switch (output_mode) {
            .Obj => "build-obj",
            .Exe => "build-exe",
            .Lib => "build-lib",
        },
        "-target",
        target.triple,
        "--cache-dir",
        ".zig-cache",
    });
    switch (target.mode) {
        .whole => {},
        .incremental => try argv.append(gpa, "-fincremental"),
    }
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    if (target.backend) |b| switch (b) {
        .sema => try argv.append(gpa, "-fno-emit-bin"),
        .selfhosted => try argv.append(gpa, "-fno-llvm"),
        .llvm => try argv.append(gpa, "-fllvm"),
        .cbe => try argv.append(gpa, "-ofmt=c"),
    } else try argv.appendSlice(gpa, &.{ "-I", path_buffer[0 .. (runner.args.lib_dir orelse
        return runner.fail("\"--lib=path/to/lib\" arg required with cbe", .{}))
        .realPath(runner.io, &path_buffer) catch |err| switch (err) {
        error.Canceled => |e| return e,
        else => |e| return runner.fail("unable to get lib path: {t}", .{e}),
    }] });
    var need: usize = 1;
    var root_name: ?[]const u8 = null;
    while (true) {
        const done = if (args_r.fill(need)) false else |err| switch (err) {
            error.ReadFailed => |e| return e,
            error.EndOfStream => true,
        };
        const buffered = args_r.buffered();
        const start = std.mem.findNone(u8, buffered, "\n ") orelse buffered.len;
        const end = std.mem.findAnyPos(u8, buffered, start, "\n ") orelse buffered.len;
        if (end - start > 0) {
            const arg = try arena.dupe(u8, buffered[start..end]);
            if (std.mem.cutPrefix(u8, arg, "-M")) |module| {
                var module_name_it = std.mem.splitScalar(u8, module, '=');
                const module_name = module_name_it.next().?;
                root_name = root_name orelse module_name;
            }
            try argv.append(gpa, arg);
            args_r.toss(end);
            need = 1;
        } else {
            args_r.toss(start);
            need = buffered.len - start + 1;
        }
        if (done) break;
    }
    try argv.append(gpa, "--listen=-");

    const out_name = try std.zig.EmitArtifact.bin.cacheName(arena, .{
        .root_name = root_name orelse "root",
        .cpu_arch = target.resolved.cpu.arch,
        .os_tag = target.resolved.os.tag,
        .ofmt = target.resolved.ofmt,
        .abi = target.resolved.abi,
        .output_mode = output_mode,
    });

    var name_buffer: [std.Progress.Node.max_name_len]u8 = undefined;
    const comp_prog_node = runner.prog_node.start(std.mem.print(&name_buffer, "compile {s}", .{
        out_name,
    }) catch &name_buffer, 0);
    errdefer comp_prog_node.end();

    const child = std.process.spawn(runner.io, .{
        .exe = .{ .file = runner.args.zig_exe orelse
            return runner.fail("missing \"--zig=path/to/zig\" arg", .{}) },
        .argv = argv.items,
        .cwd = .{ .dir = src_dir },
        .progress_node = comp_prog_node,
        .stdin = .pipe,
        .stdout = .pipe,
        .stderr = .pipe,
    }) catch |err| switch (err) {
        error.Canceled, error.OutOfMemory => |e| return e,
        else => |e| return runner.fail("unable to spawn compiler: {t}", .{e}),
    };
    compiler.* = .{
        .runner = runner,
        .prog_node = comp_prog_node,
        .allow_compiler_stderr = true,
        .output_mode = output_mode,
        .state = .idle,
        .child = child,
        .fw = undefined,
        .mr_buffer = undefined,
        .mr = undefined,
        .client = undefined,
        .target = target,
        .out_name = out_name,
        .config = null,
    };
    const comp = &compiler.*.?;
    comp.fw = child.stdin.?.writerStreaming(runner.io, &.{});
    comp.mr.init(gpa, runner.io, comp.mr_buffer.toStreams(), &.{
        child.stdout.?, child.stderr.?,
    });
    comp.client = .{ .in = comp.mr.reader(0), .out = &comp.fw.interface };
}
const Compiler = struct {
    runner: *Runner,
    prog_node: std.Progress.Node,
    allow_compiler_stderr: bool,
    output_mode: std.lang.OutputMode,
    state: enum { idle, update },
    child: std.process.Child,
    fw: std.Io.File.Writer,
    mr_buffer: std.Io.File.MultiReader.Buffer(2),
    mr: std.Io.File.MultiReader,
    client: std.zig.Client,
    target: Target,
    out_name: []const u8,
    config: ?std.zig.Server.Message.Config,

    const Target = struct {
        triple: []const u8,
        resolved: std.Target,
        mode: Mode,
        backend: ?Backend,

        const Mode = enum {
            whole,
            incremental,
        };

        const Backend = enum {
            /// Run semantic analysis only. Runtime output will not be tested, but we still verify
            /// that compilation succeeds. Corresponds to `-fno-emit-bin`.
            sema,
            /// Use the self-hosted code generation backend for this target.
            /// Corresponds to `-fno-llvm -fno-lld`.
            selfhosted,
            /// Use the LLVM backend.
            /// Corresponds to `-fllvm -flld`.
            llvm,
            /// Use the C backend. The output is compiled with `zig cc`.
            /// Corresponds to `-ofmt=c`.
            cbe,
        };
    };

    fn receiveMessage(comp: *Compiler) FailError!?struct {
        tag: std.zig.Server.Message.Tag,
        body: []const u8,
    } {
        const header = comp.client.receiveMessageWithMultiReader(
            &comp.mr,
            .none,
        ) catch |err| switch (err) {
            error.Canceled, error.OutOfMemory => |e| return e,
            error.Timeout => unreachable,
            error.EndOfStream => return null,
            else => |e| return comp.runner.fail("unable to receive message: {t}", .{e}),
        };
        const body = comp.client.in.take(header.bytes_len) catch unreachable;
        const stderr = comp.mr.reader(1);
        if (stderr.bufferedLen() > 0) {
            if (comp.allow_compiler_stderr) {
                std.log.info("{t} stderr:\n{s}", .{ header.tag, stderr.buffered() });
            } else {
                return comp.runner.fail("{t} unexpected stderr:\n{s}", .{
                    header.tag, stderr.buffered(),
                });
            }
            stderr.tossBuffered();
        }
        return .{ .tag = header.tag, .body = body };
    }

    const Check = enum { errors, stdout, exit, lldb };
    fn checkSuccess(
        comp: *Compiler,
        check: Check,
        expected: []const u8,
        src_dir: std.Io.Dir,
        digest: *const std.Build.Cache.BinDigest,
    ) FailError!void {
        const runner = comp.runner;
        const gpa = runner.gpa;
        const arena = runner.arena.allocator();
        const io = runner.io;
        const target = &comp.target.resolved;
        const config = &comp.config.?;
        const out_dir = ".zig-cache" ++ std.Io.Dir.path.sep_str ++
            "o" ++ std.Io.Dir.path.sep_str ++ std.Build.Cache.binToHex(digest.*);
        const out_path = try std.Io.Dir.path.join(arena, &.{ out_dir, comp.out_name });
        const bin_path = switch (comp.target.backend.?) {
            .sema => return,
            .selfhosted, .llvm => out_path,
            .cbe => try comp.compileC(src_dir, out_path),
        };
        switch (check) {
            .errors => return,
            .stdout, .exit, .lldb => {},
        }

        var argv: std.ArrayList([]const u8) = .initBuffer(try arena.alloc([]const u8, 4));
        var environ_map: std.process.Environ.Map = .init(gpa);
        defer environ_map.deinit();
        const need_cross_libc =
            target.os.tag == .linux and config.flags.link_libc and config.flags.link_mode == .dynamic;
        const use_executor = use_executor: switch (std.zig.system.getExternalExecutor(io, target, .{
            .host_cpu_arch = runner.host.cpu.arch,
            .host_os_tag = runner.host.os.tag,
            .qemu_fixes_dl = need_cross_libc and runner.args.libc_runtimes_dir != null,
            .link_mode = config.flags.link_mode,
            .link_libc = config.flags.link_libc,
        })) {
            .bad_dl, .bad_os_or_cpu => {
                // This binary cannot be executed on this host.
                if (!runner.args.quiet) std.log.warn("skipping execution because host {q} cannot " ++
                    "execute binaries for foreign target {q}", .{
                    try runner.host.zigTriple(arena), comp.target.triple,
                });
                return;
            },
            .native => false,
            .darling => |executor| if (runner.args.enable_darling) {
                argv.appendAssumeCapacity(executor);
                break :use_executor true;
            } else continue :use_executor .bad_os_or_cpu,
            .qemu => |executor| if (runner.args.enable_qemu) {
                argv.appendAssumeCapacity(executor);
                if (need_cross_libc) {
                    const libc_runtimes_dir = runner.args.libc_runtimes_dir orelse
                        continue :use_executor .bad_os_or_cpu;
                    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
                    const libc_runtimes_path = path_buffer[0 .. libc_runtimes_dir.realPath(
                        runner.io,
                        &path_buffer,
                    ) catch |err| switch (err) {
                        error.Canceled => |e| return e,
                        else => |e| return runner.fail("unable to get libc runtimes path: {t}", .{e}),
                    }];
                    argv.appendSliceAssumeCapacity(&.{ "-L", try std.Io.Dir.path.join(arena, &.{
                        libc_runtimes_path,
                        try if (target.isGnuLibC()) std.zig.target.glibcRuntimeTriple(
                            arena,
                            target.cpu.arch,
                            target.os.tag,
                            target.abi,
                        ) else if (target.isMuslLibC()) std.zig.target.muslRuntimeTriple(
                            arena,
                            target.cpu.arch,
                            target.abi,
                        ) else unreachable,
                    }) });
                }
                break :use_executor true;
            } else continue :use_executor .bad_os_or_cpu,
            .rosetta => if (runner.args.enable_rosetta)
                true
            else
                continue :use_executor .bad_os_or_cpu,
            .wine => |executor| if (runner.args.enable_wine) {
                if (!environ_map.contains("WINEDEBUG")) try environ_map.put("WINEDEBUG", "-all");
                argv.appendAssumeCapacity(executor);
                break :use_executor true;
            } else continue :use_executor .bad_os_or_cpu,
            .wasmtime => |executor| if (runner.args.enable_wasmtime) {
                if (!environ_map.contains("WASMTIME_BACKTRACE_DETAILS"))
                    try environ_map.put("WASMTIME_BACKTRACE_DETAILS", "1");
                argv.appendSliceAssumeCapacity(&.{ executor, "--dir=.", "-Sinherit-env" });
                break :use_executor true;
            } else continue :use_executor .bad_os_or_cpu,
        };
        argv.appendAssumeCapacity(bin_path);

        var name_buffer: [std.Progress.Node.max_name_len]u8 = undefined;
        const run_prog_node = runner.prog_node.start(std.mem.print(&name_buffer, "run {s}", .{
            comp.out_name,
        }) catch &name_buffer, 0);
        defer run_prog_node.end();

        const bin_file = src_dir.openFile(io, bin_path, .{}) catch |err| switch (err) {
            error.Canceled => |e| return e,
            else => |e| return runner.fail("unable to open {q}: {t}", .{ bin_path, e }),
        };
        defer bin_file.close(io);
        switch (check) {
            .errors => unreachable,
            .stdout, .exit => {
                const result = std.process.run(gpa, io, .{
                    .exe = if (use_executor) .search else .{ .file = bin_file },
                    .argv = argv.items,
                    .cwd = .{ .dir = src_dir },
                    .environ_map = &environ_map,
                    .progress_node = run_prog_node,
                }) catch |err| if (use_executor) {
                    // Chances are the foreign executor isn't available. Skip this evaluation.
                    if (!runner.args.quiet) std.log.warn(
                        "skipping execution of {q} via executor for foreign target {q}: {t}",
                        .{ bin_path, comp.target.triple, err },
                    );
                    return;
                } else return runner.fail("unable to run the generated executable {q}: {t}", .{
                    bin_path, err,
                });
                defer {
                    gpa.free(result.stdout);
                    gpa.free(result.stderr);
                }
                switch (result.term) {
                    .exited => |code| switch (check) {
                        .errors, .lldb => unreachable,
                        .stdout => {
                            if (code != 0) return runner.fail(
                                "generated executable {q} failed with code {d}",
                                .{ bin_path, code },
                            );
                            std.testing.expectEqualStrings(
                                expected,
                                result.stdout,
                            ) catch |err| switch (err) {
                                error.TestExpectedEqual => return runner.fail(
                                    "stdout did not match expected",
                                    .{},
                                ),
                            };
                        },
                        .exit => {
                            var actual_code_buffer: [std.fmt.count("{d}", .{std.math.maxInt(u8)})]u8 =
                                undefined;
                            std.testing.expectEqualStrings(
                                expected,
                                std.mem.print(&actual_code_buffer, "{d}", .{code}) catch unreachable,
                            ) catch |err| switch (err) {
                                error.TestExpectedEqual => return runner.fail(
                                    "exit code did not match expected",
                                    .{},
                                ),
                            };
                        },
                    },
                    .signal => |sig| return runner.fail(
                        "generated executable {q} terminated with signal {t}",
                        .{ bin_path, sig },
                    ),
                    .stopped => |sig| return runner.fail(
                        "generated executable {q} stopped with signal {t}",
                        .{ bin_path, sig },
                    ),
                    .unknown => return runner.fail(
                        "generated executable {q} terminated unexpectedly",
                        .{bin_path},
                    ),
                }
                if (!use_executor and result.stderr.len > 0) {
                    std.log.err("generated executable {q} had unexpected stderr:\n{s}", .{
                        bin_path, result.stderr,
                    });
                }
            },
            .lldb => {},
        }
    }

    fn compileC(parent_comp: *Compiler, src_dir: std.Io.Dir, c_path: []const u8) FailError![]const u8 {
        const runner = parent_comp.runner;
        const arena = runner.arena.allocator();
        var compiler: ?Compiler = null;
        var args_r: std.Io.Reader = .fixed(c_path);
        parent_comp.runner.spawnCompiler(&compiler, src_dir, parent_comp.output_mode, &args_r, .{
            .triple = parent_comp.target.triple,
            .resolved = resolved: {
                var resolved = parent_comp.target.resolved;
                resolved.ofmt = .default(resolved.os.tag, resolved.cpu.arch);
                break :resolved resolved;
            },
            .mode = .whole,
            .backend = null,
        }) catch |err| switch (err) {
            error.Canceled, error.OutOfMemory, error.AlreadyReported => |e| return e,
            error.ReadFailed => unreachable, // .fixed
        };
        const comp = &compiler.?;
        comp.client.serveBodylessMessage(.update) catch |err| switch (err) {
            error.WriteFailed => switch (comp.fw.err.?) {
                error.Canceled => |e| return e,
                else => |e| return runner.fail("unable to send message: {t}", .{e}),
            },
        };
        comp.state = .update;
        var out_path: ?[]const u8 = null;
        while (try comp.receiveMessage()) |message| switch (message.tag) {
            else => {}, // Ignore other messages,
            .config => {
                var body_r: std.Io.Reader = .fixed(message.body);
                comp.config =
                    body_r.takeStruct(std.zig.Server.Message.Config, .little) catch unreachable;
            },
            .emit_digest => {
                var body_r: std.Io.Reader = .fixed(message.body);
                _ = body_r.takeStruct(std.zig.Server.Message.EmitDigest, .little) catch unreachable;
                const digest = body_r.takeArray(std.Build.Cache.bin_digest_len) catch unreachable;

                const out_dir = ".zig-cache" ++ std.Io.Dir.path.sep_str ++
                    "o" ++ std.Io.Dir.path.sep_str ++ std.Build.Cache.binToHex(digest.*);
                out_path = try std.Io.Dir.path.join(arena, &.{ out_dir, comp.out_name });
            },
            .error_bundle => {
                const eb = std.zig.Server.allocErrorBundle(
                    runner.arena.allocator(),
                    message.body,
                ) catch |err| switch (err) {
                    error.OutOfMemory => |e| return e,
                    error.EndOfStream => return runner.fail("error bundle truncated", .{}),
                };
                if (eb.errorMessageCount() > 0) {
                    try runner.eb_wip.addBundleAsRoots(eb);
                    return runner.fail("unexpected compile errors", .{});
                }
                comp.state = .idle;
                break;
            },
        };
        try comp.exit();
        return out_path.?;
    }

    fn exit(comp: *Compiler) FailError!void {
        const runner = comp.runner;
        comp.client.serveBodylessMessage(.exit) catch |err| switch (err) {
            error.WriteFailed => switch (comp.fw.err.?) {
                error.Canceled => |e| return e,
                error.BrokenPipe => {},
                else => |e| return comp.runner.fail("unable to send exit: {t}", .{e}),
            },
        };
        comp.child.stdin.?.close(runner.io);
        comp.child.stdin = null;
        while (try comp.receiveMessage()) |_| {}
        if (comp.client.in.bufferedLen() > 0) return runner.fail("unable to receive messages", .{});
        const term = comp.child.wait(runner.io) catch |err|
            return runner.fail("child process failed: {t}", .{err});
        comp.prog_node.end();
        switch (term) {
            .exited => |code| if (code != 0)
                return runner.fail("compiler failed with code {d}", .{code}),
            .signal => |sig| return runner.fail("compiler terminated with signal {t}", .{sig}),
            .stopped => |sig| return runner.fail("compiler stopped unexpectedly with signal {t}", .{
                sig,
            }),
            .unknown => return runner.fail("compiler terminated unexpectedly", .{}),
        }
    }
};

const ClientArgs = struct {
    test_file: std.Io.File,
    test_kind: std.Io.File.Kind,
    zig_exe: std.Io.File,
    lib_dir: std.Io.Dir,
    src_dir: std.Io.Dir,
    targets: std.ArrayList([]const u8),
    keep_src: bool,
    libc_runtimes_dir: ?std.Io.Dir,
    enable_darling: bool,
    enable_qemu: bool,
    enable_rosetta: bool,
    enable_wine: bool,
    enable_wasmtime: bool,
    quiet: bool,
};
pub fn main(init: std.process.Init) (std.mem.Allocator.Error || std.Io.Cancelable)!u8 {
    const fatal = struct {
        fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
            std.log.err(fmt, args);
            std.process.exit(1);
        }
    }.fatal;
    const arena = init.arena.allocator();

    var test_path_arg: ?[]const u8 = null;
    var zig_path_arg: ?[]const u8 = null;
    var lib_path_arg: ?[]const u8 = null;
    var libc_runtimes_path_arg: ?[]const u8 = null;
    var args: ClientArgs = .{
        .test_file = undefined,
        .test_kind = undefined,
        .zig_exe = undefined,
        .lib_dir = undefined,
        .src_dir = undefined,
        .targets = .empty,
        .keep_src = false,
        .libc_runtimes_dir = null,
        .enable_darling = false,
        .enable_qemu = false,
        .enable_rosetta = false,
        .enable_wine = false,
        .enable_wasmtime = false,
        .quiet = false,
    };
    defer args.targets.deinit(init.gpa);

    var arg_it = try init.minimal.args.iterateAllocator(arena);
    const self = arg_it.next().?;
    while (arg_it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--listen=-")) {
            var stdin_buffer: [512]u8 = undefined;
            var stdin: std.Io.File.Reader = .initStreaming(.stdin(), init.io, &stdin_buffer);
            var stdout_buffer: [512]u8 = undefined;
            var stdout: std.Io.File.Writer = .initStreaming(.stdout(), init.io, &stdout_buffer);
            var runner: Runner = .{
                .gpa = init.gpa,
                .arena = init.arena,
                .io = init.io,
                .prog_node = std.Progress.start(init.io, .{}),
                .args = .{
                    .@"test" = null,
                    .manifest_file = null,
                    .zig_exe = null,
                    .lib_dir = null,
                    .src_dir = null,
                    .targets = .empty,
                    .target_bytes = .empty,
                    .libc_runtimes_dir = null,
                    .enable_darling = false,
                    .enable_qemu = false,
                    .enable_rosetta = false,
                    .enable_wasmtime = false,
                    .enable_wine = false,
                    .quiet = false,
                },
                .host = std.zig.system.resolveTargetQuery(init.io, .{}) catch |err| switch (err) {
                    error.Canceled => |e| return e,
                    else => |e| fatal("unable to resolve host target: {t}", .{e}),
                },
                .server = .{
                    .in = &stdin.interface,
                    .out = &stdout.interface,
                },
                .eb_wip = try .init(init.gpa),
            };
            defer runner.deinit();
            switch (runner.runServer()) {
                error.Canceled, error.OutOfMemory => |e| return e,
                error.ServerReadFailed => switch (stdin.err.?) {
                    error.Canceled => |e| return e,
                    else => |e| fatal("unable to receive message: {t}", .{e}),
                },
                error.ServerWriteFailed => switch (stdout.err.?) {
                    error.Canceled => |e| return e,
                    else => |e| fatal("unable to send message: {t}", .{e}),
                },
                error.ServerEndOfStream => fatal("no more messages", .{}),
                error.AlreadyReported => {
                    var eb = try runner.eb_wip.toOwnedBundle("");
                    defer eb.deinit(init.gpa);
                    eb.renderToStderr(runner.io, .{}, .auto) catch |err| switch (err) {
                        error.Canceled => |e| return e,
                        else => {},
                    };
                    std.process.exit(1);
                },
            }
        } else if (std.mem.eql(u8, arg, "--zig")) {
            zig_path_arg = arg_it.next() orelse fatal("missing arg after {q}", .{arg});
        } else if (std.mem.cutPrefix(u8, arg, "--zig=")) |zig_path| {
            zig_path_arg = zig_path;
        } else if (std.mem.eql(u8, arg, "--lib")) {
            lib_path_arg = arg_it.next() orelse fatal("missing arg after {q}", .{arg});
        } else if (std.mem.cutPrefix(u8, arg, "--lib=")) |lib_path| {
            lib_path_arg = lib_path;
        } else if (std.mem.eql(u8, arg, "--target")) {
            try args.targets.append(
                init.gpa,
                try arena.dupe(u8, arg_it.next() orelse fatal("missing arg after {q}", .{arg})),
            );
        } else if (std.mem.cutPrefix(u8, arg, "--target=")) |target| {
            try args.targets.append(init.gpa, try arena.dupe(u8, target));
        } else if (std.mem.eql(u8, arg, "--keep-src")) {
            args.keep_src = true;
        } else if (std.mem.eql(u8, arg, "--libc-runtimes")) {
            libc_runtimes_path_arg = arg_it.next() orelse fatal("missing arg after {q}", .{arg});
        } else if (std.mem.cutPrefix(u8, arg, "--libc-runtimes=")) |libc_runtimes_path| {
            libc_runtimes_path_arg = libc_runtimes_path;
        } else if (std.mem.eql(u8, arg, "-fdarling")) {
            args.enable_darling = true;
        } else if (std.mem.eql(u8, arg, "-fqemu")) {
            args.enable_qemu = true;
        } else if (std.mem.eql(u8, arg, "-frosetta")) {
            args.enable_rosetta = true;
        } else if (std.mem.eql(u8, arg, "-fwine")) {
            args.enable_wine = true;
        } else if (std.mem.eql(u8, arg, "-fwasmtime")) {
            args.enable_wasmtime = true;
        } else if (std.mem.eql(u8, arg, "--quiet")) {
            args.quiet = true;
        } else {
            if (test_path_arg) |_| fatal("unexpected arg {q}", .{arg});
            test_path_arg = arg;
        }
    }

    const test_path = test_path_arg orelse fatal("missing \"path/to/test\" arg", .{});
    const zig_path = zig_path_arg orelse fatal("missing \"--zig=path/to/zig\" arg", .{});
    const lib_path = lib_path_arg orelse fatal("missing \"--lib=path/to/lib\" arg", .{});

    const cwd: std.Io.Dir = .cwd();
    args.test_file = cwd.openFile(init.io, test_path, .{
        .allow_directory = true,
    }) catch |err| switch (err) {
        error.Canceled => |e| return e,
        else => |e| fatal("unable to open {q}: {t}", .{ test_path, e }),
    };
    defer args.test_file.close(init.io);
    args.test_kind = (args.test_file.stat(init.io) catch |err| switch (err) {
        error.Canceled => |e| return e,
        else => |e| fatal("unable to stat {q}: {t}", .{ test_path, e }),
    }).kind;
    args.zig_exe = cwd.openFile(init.io, zig_path, .{}) catch |err| switch (err) {
        error.Canceled => |e| return e,
        else => |e| fatal("unable to open {q}: {t}", .{ zig_path, e }),
    };
    defer args.zig_exe.close(init.io);
    args.lib_dir = cwd.openDir(init.io, lib_path, .{}) catch |err| switch (err) {
        error.Canceled => |e| return e,
        else => |e| fatal("unable to open {q}: {t}", .{ lib_path, e }),
    };
    defer args.lib_dir.close(init.io);
    if (libc_runtimes_path_arg) |libc_runtimes_path| args.libc_runtimes_dir = cwd.openDir(
        init.io,
        libc_runtimes_path,
        .{},
    ) catch |err| switch (err) {
        error.Canceled => |e| return e,
        else => |e| fatal("unable to open {q}: {t}", .{ lib_path, e }),
    };
    defer if (args.libc_runtimes_dir) |libc_runtimes_dir| libc_runtimes_dir.close(init.io);

    const src_dir_path = "src_" ++ std.fmt.hex(rand_int: {
        var rand_int: u64 = undefined;
        init.io.random(@ptrCast(&rand_int));
        break :rand_int rand_int;
    });
    args.src_dir = cwd.createDirPathOpen(init.io, src_dir_path, .{}) catch |err| switch (err) {
        error.Canceled => |e| return e,
        else => |e| fatal("unable to create {q}: {t}", .{ src_dir_path, e }),
    };
    defer {
        args.src_dir.close(init.io);
        if (!args.keep_src) cwd.deleteTree(init.io, src_dir_path) catch |err| {
            std.log.warn("unable to delete tree {q}: {t}", .{ src_dir_path, err });
        };
    }

    var child = std.process.spawn(init.io, .{
        .argv = &.{ self, "--listen=-" },
        .stdin = .pipe,
        .stdout = .pipe,
        .inherit_dirs = &.{ args.lib_dir, args.src_dir },
        .inherit_files = &.{ args.zig_exe, args.test_file },
    }) catch |err| switch (err) {
        error.Canceled, error.OutOfMemory => |e| return e,
        else => |e| fatal("unable to spawn runner: {t}", .{e}),
    };

    var child_reader_buffer: [512]u8 = undefined;
    var child_reader = child.stdout.?.readerStreaming(init.io, &child_reader_buffer);
    var child_writer_buffer: [512]u8 = undefined;
    var child_writer = child.stdin.?.writerStreaming(init.io, &child_writer_buffer);
    var client: std.zig.Client = .{
        .in = &child_reader.interface,
        .out = &child_writer.interface,
    };
    const success = runClient(init.gpa, arena, init.io, &client, &args) catch |err| switch (err) {
        error.OutOfMemory => |e| return e,
        error.ReadFailed => switch (child_reader.err.?) {
            error.Canceled => |e| return e,
            else => |e| fatal("unable to receive message: {t}", .{e}),
        },
        error.WriteFailed => switch (child_writer.err.?) {
            error.Canceled => |e| return e,
            else => |e| fatal("unable to send message: {t}", .{e}),
        },
        error.EndOfStream => fatal("no more messages", .{}),
    };
    _ = child.wait(init.io) catch |err| switch (err) {
        error.Canceled => |e| return e,
        else => |e| fatal("unable to wait for runner: {t}", .{e}),
    };
    return if (success) 0 else 1;
}
fn runClient(
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    io: std.Io,
    client: *std.zig.Client,
    args: *const ClientArgs,
) (std.mem.Allocator.Error || std.Io.Reader.Error || std.Io.Writer.Error)!bool {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_fw: std.Io.File.Writer = .initStreaming(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_fw.interface;
    var stderr_buffer: [512]u8 = undefined;
    var stderr_fw: std.Io.File.Writer = .initStreaming(.stderr(), io, &stderr_buffer);
    const stderr = &stderr_fw.interface;

    var argv: std.ArrayList(u8) = .empty;
    defer argv.deinit(gpa);
    const Arg = std.zig.Client.Message.Arg;

    try argv.append(gpa, @backingInt(@as(Arg, switch (args.test_kind) {
        else => unreachable,
        .file => .input_file,
        .directory => .input_dir,
    })));
    try argv.appendSlice(gpa, @ptrCast(&args.test_file.handle));

    try argv.append(gpa, @backingInt(Arg.prefix));
    try argv.appendSlice(gpa, "--zig=");
    try argv.append(gpa, 0);
    try argv.append(gpa, @backingInt(Arg.input_file));
    try argv.appendSlice(gpa, @ptrCast(&args.zig_exe.handle));

    try argv.append(gpa, @backingInt(Arg.prefix));
    try argv.appendSlice(gpa, "--lib=");
    try argv.append(gpa, 0);
    try argv.append(gpa, @backingInt(Arg.input_dir));
    try argv.appendSlice(gpa, @ptrCast(&args.lib_dir.handle));

    try argv.append(gpa, @backingInt(Arg.prefix));
    try argv.appendSlice(gpa, "--src=");
    try argv.append(gpa, 0);
    try argv.append(gpa, @backingInt(Arg.output_dir));
    try argv.appendSlice(gpa, @ptrCast(&args.src_dir.handle));

    for (args.targets.items) |target| {
        try argv.append(gpa, @backingInt(Arg.string));
        try argv.appendSlice(gpa, "--target");
        try argv.append(gpa, 0);

        try argv.append(gpa, @backingInt(Arg.string));
        try argv.appendSlice(gpa, target);
        try argv.append(gpa, 0);
    }

    if (args.libc_runtimes_dir) |libc_runtimes_dir| {
        try argv.append(gpa, @backingInt(Arg.prefix));
        try argv.appendSlice(gpa, "--libc-runtimes=");
        try argv.append(gpa, 0);
        try argv.append(gpa, @backingInt(Arg.input_dir));
        try argv.appendSlice(gpa, @ptrCast(&libc_runtimes_dir.handle));
    }
    if (args.enable_darling) {
        try argv.append(gpa, @backingInt(Arg.string));
        try argv.appendSlice(gpa, "-fdarling");
        try argv.append(gpa, 0);
    }
    if (args.enable_qemu) {
        try argv.append(gpa, @backingInt(Arg.string));
        try argv.appendSlice(gpa, "-fqemu");
        try argv.append(gpa, 0);
    }
    if (args.enable_rosetta) {
        try argv.append(gpa, @backingInt(Arg.string));
        try argv.appendSlice(gpa, "-frosetta");
        try argv.append(gpa, 0);
    }
    if (args.enable_wine) {
        try argv.append(gpa, @backingInt(Arg.string));
        try argv.appendSlice(gpa, "-fwine");
        try argv.append(gpa, 0);
    }
    if (args.enable_wasmtime) {
        try argv.append(gpa, @backingInt(Arg.string));
        try argv.appendSlice(gpa, "-fwasmtime");
        try argv.append(gpa, 0);
    }

    if (args.quiet) {
        try argv.append(gpa, @backingInt(Arg.string));
        try argv.appendSlice(gpa, "--quiet");
        try argv.append(gpa, 0);
    }

    try client.serveMessageHeader(.{
        .tag = .args,
        .bytes_len = @intCast(argv.items.len),
    });
    try client.out.writeAll(argv.items);

    var success = true;
    var metadata: struct {
        index: u32,
        len: u32,
        names: []u32,
        expected_panic_msgs: []u32,
        string_bytes: []u8,

        fn name(m: *@This()) []const u8 {
            return std.mem.sliceTo(m.string_bytes[m.names[m.index - 1]..], 0);
        }

        fn expectedPanicMsg(m: *@This()) ?[:0]const u8 {
            return switch (m.expected_panic_msgs[m.index - 1]) {
                0 => null,
                else => |offset| m.string_bytes[offset..std.mem.findScalarPos(
                    u8,
                    m.string_bytes,
                    offset,
                    0,
                ).? :0],
            };
        }

        fn next(m: *@This()) ?u32 {
            if (m.len - m.index == 0) return null;
            defer m.index += 1;
            return m.index;
        }
    } = .{ .index = 0, .len = 0, .names = &.{}, .expected_panic_msgs = &.{}, .string_bytes = &.{} };
    try client.serveBodylessMessage(.query_test_metadata);
    while (true) {
        const hdr = try client.receiveMessage();
        switch (hdr.tag) {
            else => try client.in.discardAll(hdr.bytes_len),
            .zig_version => {
                const actual_version = try client.in.take(hdr.bytes_len);
                if (!std.mem.eql(u8, zig_version_string, actual_version)) {
                    try stderr.print(
                        "error: zig version mismatch compiler test runner vs compiler: {q} vs {q}\n",
                        .{ zig_version_string, actual_version },
                    );
                    try stderr.flush();
                    std.process.exit(1);
                }
            },
            .error_bundle => {
                const body = try arena.alloc(u8, hdr.bytes_len);
                try client.in.readSliceAll(body);
                const eb = std.zig.Server.allocErrorBundle(arena, body) catch |err| switch (err) {
                    error.OutOfMemory => |e| return e,
                    error.EndOfStream => {
                        try stderr.writeAll("error bundle truncated\n");
                        try stderr.flush();
                        std.process.exit(1);
                    },
                };
                success = false;
                eb.renderToStderr(io, .{}, .auto) catch {};
            },
            .test_metadata => {
                const tm_hdr =
                    try client.in.takeStruct(std.zig.Server.Message.TestMetadata, .little);
                metadata = .{
                    .index = 0,
                    .len = tm_hdr.tests_len,
                    .names = try arena.alloc(u32, tm_hdr.tests_len),
                    .expected_panic_msgs = try arena.alloc(u32, tm_hdr.tests_len),
                    .string_bytes = try arena.alloc(u8, tm_hdr.string_bytes_len),
                };
                try client.in.readSliceEndian(u32, metadata.names, .little);
                try client.in.readSliceEndian(u32, metadata.expected_panic_msgs, .little);
                try client.in.readSliceAll(metadata.string_bytes);
                try client.serveRunTest(metadata.next() orelse break);
            },
            .test_results => {
                const tr = try client.in.takeStruct(std.zig.Server.Message.TestResults, .little);
                switch (tr.flags.status) {
                    .pass, .skip => {},
                    .fail => success = false,
                }
                try stdout.print("[{t}] {s}\n", .{ tr.flags.status, metadata.name() });
                try stdout.flush();
                try client.serveRunTest(metadata.next() orelse break);
            },
        }
    }
    try client.serveBodylessMessage(.exit);
    return success;
}
