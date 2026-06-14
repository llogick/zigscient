//! Configuration options related to a specific BldDoc.

const std = @import("std");

pub const Option = struct {
    name: []const u8,
    value: ?[]const u8 = null,

    /// Duplicates the `Option`, copying internal strings. Caller owns returned option with contents
    /// allocated using `allocator`.
    pub fn dupe(self: Option, allocator: std.mem.Allocator) error{OutOfMemory}!Option {
        const copy_name = try allocator.dupe(u8, self.name);
        errdefer allocator.free(copy_name);
        const copy_value = if (self.value) |val|
            try allocator.dupe(u8, val)
        else
            null;
        return .{
            .name = copy_name,
            .value = copy_value,
        };
    }

    /// Formats the `Option` as a command line parameter compatible with `zig build`. This will either be
    /// `-Dname=value` or `-Dname`. Caller owns returned slice allocated using `allocator`.
    pub fn formatParam(self: Option, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
        if (self.value) |val| {
            return try std.fmt.allocPrint(allocator, "-D{s}={s}", .{ self.name, val });
        } else {
            return try std.fmt.allocPrint(allocator, "-D{s}", .{self.name});
        }
    }
};

/// If provided this path is used when resolving `@import("builtin")`
/// It is relative to the directory containing the `build.zig`
///
/// This file should contain the output of:
/// `zig build-exe/build-lib/build-obj --show-builtin <options>`
relative_builtin_path: ?[]const u8 = null,

/// If provided, this list of options will be passed to `build.zig`.
build_options: ?[]Option = null,

/// Index into the CompileSteps/roots array
roots_index: ?u32 = null,
