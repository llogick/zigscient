const Server = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const Cache = std.Build.Cache;
const OutMessage = std.zig.Server.Message;
const InMessage = std.zig.Client.Message;
const Reader = std.Io.Reader;
const Writer = std.Io.Writer;

in: *Reader,
out: *Writer,

/// The ABI version of the build system protocol. Will be bumped whenever a
/// backwards incompatible changes to the protocol is made.
///
/// Does not apply to the internal compiler protocol or test runner.
///
/// See `version` in `Message.Handshake`.
pub const build_system_version: u32 = 1;

pub const Message = struct {
    pub const Header = extern struct {
        tag: Tag,
        /// Size of the body only; does not include this Header.
        bytes_len: u32,
    };

    pub const Tag = enum(u32) {
        /// Body is a UTF-8 string.
        zig_version,
        /// Body is an ErrorBundle.
        error_bundle,
        /// Body is a EmitDigest.
        emit_digest,
        /// Body is a TestMetadata
        test_metadata,
        /// Body is a TestResults
        test_results,
        /// Does not have a body.
        /// Notifies the build runner that the next test (requested by `Client.Message.Tag.run_test`)
        /// is starting execution. This message helps to ensure that the timestamp used by the build
        /// runner to enforce unit test time limits is relatively accurate under extreme system load
        /// (where there may be a non-trivial delay before the test process is scheduled).
        test_started,
        /// Body is a series of strings, delimited by null bytes.
        /// Each string is a prefixed file path.
        /// The first byte indicates the file prefix path (see prefixes fields
        /// of Cache). This byte is sent over the wire incremented so that null
        /// bytes are not confused with string terminators.
        /// The remaining bytes is the file path relative to that prefix.
        /// The prefixes are hard-coded in Compilation.create (cwd, zig lib dir, local cache dir)
        file_system_inputs,
        /// Body is:
        /// - a u64le that indicates the file path within the cache used
        ///   to store coverage information. The integer is a hash of the PCs
        ///   stored within that file.
        /// - u64le of total runs accumulated
        /// - u64le of unique runs accumulated
        /// - u64le of coverage accumulated
        coverage_id,
        /// Body is a u64le that indicates the function pointer virtual memory
        /// address of the fuzz unit test. This is used to provide a starting
        /// point to view coverage.
        fuzz_start_addr,
        /// Body is:
        /// - u32le test index.
        fuzz_test_change,
        /// Body is:
        /// - u32le test index
        /// - input in remaining bytes
        broadcast_fuzz_input,
        /// Body is a TimeReport.
        time_report,

        /// The first message sent by the server over the build system protocol.
        /// Body is a `Handshake`.
        /// This message only applies to the build system protocol.
        bsp_handshake = 0x80000000,
        /// Notifies that a new configuration file is available.
        /// Body is a cwd relative path to the configuration file.
        /// This message only applies to the build system protocol.
        bsp_configuration,
        /// Does not have a body.
        /// This message only applies to the build system protocol.
        bsp_build_started,
        /// Does not have a body.
        /// This message only applies to the build system protocol.
        bsp_build_completed,
        /// Body is a `Configuration.Step.Index`.
        /// This message only applies to the build system protocol.
        bsp_step_started,
        /// Body is a `BuildStepCompleted`.
        /// This message only applies to the build system protocol.
        bsp_step_completed,

        _,
    };

    /// Trailing:
    /// * base_paths: BasePaths,
    pub const Handshake = extern struct {
        /// See `build_system_version`.
        version: u32,
        flags: Flags,

        pub const Flags = packed struct(u32) {
            file_system_watch_supported: bool,
            _: u31 = 0,
        };
    };

    /// Trailing:
    /// * error_bundle: ErrorBundle,
    pub const BuildStepCompleted = extern struct {
        step_index: std.Build.Configuration.Step.Index,
        status: Status,
        error_bundle: ErrorBundle,
        // TODO result_error_msgs
        // TODO result_stderr
        // TODO result_peak_rss
        // TODO result_duration_ns

        pub const Status = enum(u32) {
            success,
            failure,
            skipped,
            skipped_oom,
        };
    };

    pub const PathPrefix = enum(u8) {
        cwd,
        zig_lib,
        local_cache,
        global_cache,
        build_root,
    };

    /// Trailing:
    /// * extra: [extra_len]u32,
    /// * string_bytes: [string_bytes_len]u8,
    /// See `std.zig.ErrorBundle`.
    pub const ErrorBundle = extern struct {
        extra_len: u32,
        string_bytes_len: u32,
    };

    /// Trailing:
    /// * name: [tests_len]u32
    ///   - null-terminated string_bytes index
    /// * expected_panic_msg: [tests_len]u32,
    ///   - null-terminated string_bytes index
    ///   - 0 means does not expect panic
    /// * string_bytes: [string_bytes_len]u8,
    pub const TestMetadata = extern struct {
        string_bytes_len: u32,
        tests_len: u32,
    };

    pub const TestResults = extern struct {
        index: u32,
        flags: Flags align(4),

        pub const Flags = packed struct(u64) {
            status: Status,
            fuzz: bool,
            log_err_count: u30,
            leak_count: u31,
        };

        pub const Status = enum(u2) { pass, fail, skip };
    };

    /// Trailing is the same as in `std.Build.abi.time_report.CompileResult`, excluding `step_name`.
    pub const TimeReport = extern struct {
        stats: std.Build.abi.time_report.CompileResult.Stats align(4),
        llvm_pass_timings_len: u32,
        files_len: u32,
        decls_len: u32,
        flags: Flags,
        pub const Flags = packed struct(u32) {
            use_llvm: bool,
            _: u31 = 0,
        };
    };

    /// Trailing:
    /// * the hex digest of the cache directory within the /o/ subdirectory.
    pub const EmitDigest = extern struct {
        flags: Flags,

        pub const Flags = packed struct(u8) {
            cache_hit: bool,
            reserved: u7 = 0,
        };
    };
};

pub fn receiveMessage(s: *Server) !InMessage.Header {
    return s.in.takeStruct(InMessage.Header, .little);
}

pub fn receiveBody_u8(s: *Server) !u8 {
    return s.in.takeInt(u8, .little);
}
pub fn receiveBody_u32(s: *Server) !u32 {
    return s.in.takeInt(u32, .little);
}
pub fn receiveBody_u64(s: *Server) !u64 {
    return s.in.takeInt(u64, .little);
}

pub fn serveStringMessage(s: *Server, tag: OutMessage.Tag, msg: []const u8) !void {
    try s.serveMessageHeader(.{
        .tag = tag,
        .bytes_len = @intCast(msg.len),
    });
    try s.out.writeAll(msg);
    try s.out.flush();
}

/// Don't forget to flush!
pub fn serveMessageHeader(s: *const Server, header: OutMessage.Header) !void {
    try s.out.writeStruct(header, .little);
}

pub fn serveBodylessMessage(s: *const Server, tag: OutMessage.Tag) Writer.Error!void {
    try s.serveMessageHeader(.{ .tag = tag, .bytes_len = 0 });
    try s.out.flush();
}

pub fn serveU32Message(s: *const Server, tag: OutMessage.Tag, int: u32) !void {
    try serveMessageHeader(s, .{
        .tag = tag,
        .bytes_len = @sizeOf(u32),
    });
    try s.out.writeInt(u32, int, .little);
    try s.out.flush();
}

pub fn serveU64Message(s: *const Server, tag: OutMessage.Tag, int: u64) !void {
    assert(tag != .coverage_id);
    try serveMessageHeader(s, .{
        .tag = tag,
        .bytes_len = @sizeOf(u64),
    });
    try s.out.writeInt(u64, int, .little);
    try s.out.flush();
}

pub fn serveCoverageIdMessage(s: *const Server, id: u64, runs: u64, unique: u64, cov: u64) !void {
    try serveMessageHeader(s, .{
        .tag = .coverage_id,
        .bytes_len = @sizeOf(u64) + @sizeOf(u64) + @sizeOf(u64) + @sizeOf(u64),
    });
    try s.out.writeInt(u64, id, .little);
    try s.out.writeInt(u64, runs, .little);
    try s.out.writeInt(u64, unique, .little);
    try s.out.writeInt(u64, cov, .little);
    try s.out.flush();
}

pub fn serveBroadcastFuzzInputMessage(s: *const Server, test_i: u32, bytes: []const u8) !void {
    try s.serveMessageHeader(.{
        .tag = .broadcast_fuzz_input,
        .bytes_len = @sizeOf(u32) + @as(u32, @intCast(bytes.len)),
    });
    try s.out.writeInt(u32, test_i, .little);
    try s.out.writeAll(bytes);
    try s.out.flush();
}

pub fn serveEmitDigest(
    s: *Server,
    digest: *const [Cache.bin_digest_len]u8,
    header: OutMessage.EmitDigest,
) !void {
    try s.serveMessageHeader(.{
        .tag = .emit_digest,
        .bytes_len = @intCast(digest.len + @sizeOf(OutMessage.EmitDigest)),
    });
    try s.out.writeStruct(header, .little);
    try s.out.writeAll(digest);
    try s.out.flush();
}

pub fn serveTestResults(s: *Server, msg: OutMessage.TestResults) !void {
    try s.serveMessageHeader(.{
        .tag = .test_results,
        .bytes_len = @intCast(@sizeOf(OutMessage.TestResults)),
    });
    try s.out.writeStruct(msg, .little);
    try s.out.flush();
}

pub fn serveErrorBundle(s: *Server, error_bundle: std.zig.ErrorBundle) !void {
    const eb_hdr: OutMessage.ErrorBundle = .{
        .extra_len = @intCast(error_bundle.extra.len),
        .string_bytes_len = @intCast(error_bundle.string_bytes.len),
    };
    const bytes_len = @sizeOf(OutMessage.ErrorBundle) +
        4 * error_bundle.extra.len + error_bundle.string_bytes.len;
    try s.serveMessageHeader(.{
        .tag = .error_bundle,
        .bytes_len = @intCast(bytes_len),
    });
    try s.out.writeStruct(eb_hdr, .little);
    try s.out.writeSliceEndian(u32, error_bundle.extra, .little);
    try s.out.writeAll(error_bundle.string_bytes);
    try s.out.flush();
}

pub fn allocErrorBundle(gpa: Allocator, body: []const u8) error{ OutOfMemory, EndOfStream }!std.zig.ErrorBundle {
    var r: Reader = .fixed(body);
    const hdr = r.takeStruct(OutMessage.ErrorBundle, .little) catch |err| switch (err) {
        error.EndOfStream => |e| return e,
        error.ReadFailed => unreachable,
    };

    var eb: std.zig.ErrorBundle = .{
        .string_bytes = &.{},
        .extra = &.{},
    };
    errdefer eb.deinit(gpa);

    const extra = try gpa.alloc(u32, hdr.extra_len);
    eb.extra = extra;
    const string_bytes = try gpa.alloc(u8, hdr.string_bytes_len);
    eb.string_bytes = string_bytes;

    r.readSliceEndian(u32, extra, .little) catch |err| switch (err) {
        error.EndOfStream => |e| return e,
        error.ReadFailed => unreachable,
    };
    r.readSliceAll(string_bytes) catch |err| switch (err) {
        error.EndOfStream => |e| return e,
        error.ReadFailed => unreachable,
    };

    return eb;
}

pub const TestMetadata = struct {
    names: []const u32,
    expected_panic_msgs: []const u32,
    string_bytes: []const u8,
};

pub fn serveTestMetadata(s: *Server, test_metadata: TestMetadata) !void {
    const header: OutMessage.TestMetadata = .{
        .tests_len = @intCast(test_metadata.names.len),
        .string_bytes_len = @intCast(test_metadata.string_bytes.len),
    };
    const trailing = 2;
    const bytes_len = @sizeOf(OutMessage.TestMetadata) +
        trailing * @sizeOf(u32) * test_metadata.names.len + test_metadata.string_bytes.len;

    try s.serveMessageHeader(.{
        .tag = .test_metadata,
        .bytes_len = @intCast(bytes_len),
    });
    try s.out.writeStruct(header, .little);
    try s.out.writeSliceEndian(u32, test_metadata.names, .little);
    try s.out.writeSliceEndian(u32, test_metadata.expected_panic_msgs, .little);
    try s.out.writeAll(test_metadata.string_bytes);
    try s.out.flush();
}
