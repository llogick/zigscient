const builtin = @import("builtin");
const std = @import("std");
const lsp_server = @import("lsp-server");

const Logger = @This();

level: std.log.Level = if (builtin.mode == .Debug) .debug else .info,

/// Log messages with the LSP 'window/logMessage' message.
lsp_transport: ?*lsp_server.lsp.Transport = null,
/// Log messages to stderr.
dump_to_stderr: bool = true,

pub fn log(
    self: *Logger,
    comptime level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    const scope_txt: []const u8 = comptime @tagName(scope);
    if (!std.mem.startsWith(u8, scope_txt, "lspc_") and level != .err) return;

    const io = std.Options.debug_io;
    const prev = io.swapCancelProtection(.blocked);
    defer _ = io.swapCancelProtection(prev);

    var buffer: [4096]u8 = undefined;
    comptime std.debug.assert(buffer.len >= lsp_server.lsp.minimum_logging_buffer_size);

    if (self.lsp_transport) |transport| {
        const lsp_message_type: lsp_server.lsp.types.window.MessageType = switch (level) {
            .err => .Error,
            .warn => .Warning,
            .info => .Info,
            .debug => .Debug,
        };
        const json_message = lsp_server.lsp.bufPrintLogMessage(&buffer, lsp_message_type, format, args);
        transport.writeJsonMessage(io, json_message) catch |err| switch (err) {
            error.Canceled => unreachable,
            else => {},
        };
    }

    if (@backingInt(level) > @backingInt(self.level)) return;
    if (!self.dump_to_stderr) return;

    const level_txt: []const u8 = switch (level) {
        .err => "err",
        .warn => "wrn",
        .info => "inf",
        .debug => "dbg",
    };

    var writer: std.Io.Writer = .fixed(&buffer);
    const no_space_left = blk: {
        writer.print("{s} ({s:^4}): ", .{ level_txt, scope_txt }) catch break :blk true;
        writer.print(format, args) catch break :blk true;
        writer.writeByte('\n') catch break :blk true;
        break :blk false;
    };
    if (no_space_left) {
        const trailing = "...\n".*;
        writer.undo(trailing.len -| writer.unusedCapacityLen());
        (writer.writableArray(trailing.len) catch unreachable).* = trailing;
    }

    const stderr = io.lockStderr(&.{}, null) catch |err| switch (err) {
        error.Canceled => unreachable,
    };
    defer io.unlockStderr();
    stderr.file_writer.interface.writeAll(writer.buffered()) catch {};
}
