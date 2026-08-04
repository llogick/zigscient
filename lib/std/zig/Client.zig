const Client = @This();

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const Configuration = std.Build.Configuration;
const OutMessage = std.zig.Client.Message;
const InMessage = std.zig.Server.Message;
const Reader = Io.Reader;
const Writer = Io.Writer;

in: *Reader,
out: *Writer,

pub const Message = struct {
    pub const Header = extern struct {
        tag: Tag,
        /// Size of the body only; does not include this Header.
        bytes_len: u32,
    };

    pub const Tag = enum(u32) {
        /// Tells the compiler to shut down cleanly.
        /// No body.
        exit,
        /// Tells the compiler to detect changes in source files and update the
        /// affected output compilation artifacts.
        /// If one of the compilation artifacts is an executable that is
        /// running as a child process, the compiler will wait for it to exit
        /// before performing the update.
        /// No body.
        update,
        /// Tells the compiler to execute the executable as a child process.
        /// No body.
        run,
        /// Tells the compiler to detect changes in source files and update the
        /// affected output compilation artifacts.
        /// If one of the compilation artifacts is an executable that is
        /// running as a child process, the compiler will perform a hot code
        /// swap.
        /// No body.
        hot_update,
        /// Ask the test runner for metadata about all the unit tests that can
        /// be run. Server will respond with a `test_metadata` message.
        /// No body.
        query_test_metadata,
        /// Ask the test runner to run a particular test.
        /// The message body is a u32 test index.
        run_test,
        /// Ask the test runner to start fuzzing a set of test forever or each for a given amount of
        /// iterations. After this is sent, the only allowed message is `new_fuzz_input`.
        ///
        /// The message body is:
        /// - a u8 test limit kind (std.Build.api.fuzz.LimitKind)
        /// - a u64 value whose meaning depends on FuzzLimitKind (either a limit amount or an instance id)
        /// - a u32 number of tests followed by n elements of
        ///   - a u32 test name len.
        ///   - a test name with the above length
        start_fuzzing,
        /// The message body has the same format as in Server.
        new_fuzz_input,

        /// Asks the server to run a list of steps.
        /// Body is a `BuildSteps`.
        /// This message only applies to the build system protocol.
        bsp_build_steps = 0x80000000,

        _,
    };

    /// Trailing:
    /// * step_indices: [step_count]std.Build.Configuration.Step.Index,
    pub const BuildSteps = extern struct {
        step_count: u32,
        flags: Flags,

        pub const Flags = packed struct(u32) {
            /// Can only be enabled when the server declared support for file
            /// watching.
            watch: bool,
            reserved: u31 = 0,
        };
    };

    comptime {
        assert(@sizeOf(std.Build.abi.fuzz.LimitKind) == 1);
    }
};

pub fn receiveMessage(c: *const Client) Reader.Error!InMessage.Header {
    return c.in.takeStruct(InMessage.Header, .little);
}

/// Assumes that `c.in` is a reader in `multi_reader`.
/// Guarantees that the response body will be buffered in `c.in` on success.
pub fn receiveMessageWithMultiReader(
    c: *Client,
    multi_reader: *Io.File.MultiReader,
    timeout: Io.Timeout,
) (Io.File.MultiReader.Error || Io.Timeout.Error)!InMessage.Header {
    while (c.in.bufferedLen() < @sizeOf(InMessage.Header)) {
        multi_reader.fill(64, timeout) catch |err| switch (err) {
            error.Canceled,
            error.Timeout,
            error.ConcurrencyUnavailable,
            error.EndOfStream,
            => |e| return e,
        };
    }
    const header = c.in.takeStruct(InMessage.Header, .little) catch unreachable;
    while (c.in.bufferedLen() < header.bytes_len) {
        try multi_reader.fill(header.bytes_len - c.in.bufferedLen(), timeout);
    }
    try multi_reader.checkAnyError();
    return header;
}

/// Don't forget to flush!
pub fn serveMessageHeader(c: *const Client, header: OutMessage.Header) Writer.Error!void {
    try c.out.writeStruct(header, .little);
}

pub fn serveBodylessMessage(c: *const Client, tag: OutMessage.Tag) Writer.Error!void {
    try c.serveMessageHeader(.{ .tag = tag, .bytes_len = 0 });
    try c.out.flush();
}

pub fn serveRunTest(c: *const Client, index: u32) !void {
    try c.serveMessageHeader(.{
        .tag = .run_test,
        .bytes_len = @sizeOf(u32),
    });
    try c.out.writeInt(u32, index, .little);
    try c.out.flush();
}

pub fn serveRunFuzzTestMessage(
    c: *const Client,
    test_names: []const []const u8,
    kind: std.Build.abi.fuzz.LimitKind,
    amount_or_instance: u64,
) !void {
    try c.serveMessageHeader(.{
        .tag = .start_fuzzing,
        .bytes_len = 1 + 8 + 4 + count: {
            var bytes_len: u32 = @intCast(test_names.len * 4);
            for (test_names) |name| {
                bytes_len += @intCast(name.len);
            }
            break :count bytes_len;
        },
    });
    try c.out.writeByte(@backingInt(kind));
    try c.out.writeInt(u64, amount_or_instance, .little);
    try c.out.writeInt(u32, @intCast(test_names.len), .little);
    for (test_names) |test_name| {
        try c.out.writeInt(u32, @intCast(test_name.len), .little);
        try c.out.writeAll(test_name);
    }
    try c.out.flush();
}

pub fn serveBuildSteps(
    c: *const Client,
    steps: []const Configuration.Step.Index,
    flags: OutMessage.BuildSteps.Flags,
) !void {
    try c.serveMessageHeader(.{
        .tag = .bsp_build_steps,
        .bytes_len = @intCast(@sizeOf(OutMessage.BuildSteps) + steps.len * @sizeOf(Configuration.Step.Index)),
    });
    const body: OutMessage.BuildSteps = .{
        .step_count = @intCast(steps.len),
        .flags = flags,
    };
    try c.out.writeStruct(body, .little);
    try c.out.writeSliceEndian(Configuration.Step.Index, steps, .little);
    try c.out.flush();
}
