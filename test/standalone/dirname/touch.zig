//! Creates a file at the given path, if it doesn't already exist.
//!
//! ```
//! touch <path>
//! ```
//!
//! Path must be absolute.

const std = @import("std");
const Io = std.Io;

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var args = try init.minimal.args.iterateAllocator(init.gpa);
    defer args.deinit();
    _ = args.next().?; // skip binary name

    const path = args.next() orelse {
        std.log.err("missing <path> argument", .{});
        return error.BadUsage;
    };

    const dir_path = Io.Dir.path.dirname(path).?;
    const basename = Io.Dir.path.basename(path);

    var dir = try Io.Dir.cwd().openDir(io, dir_path, .{});
    defer dir.close(io);

    var file = try dir.createFile(io, basename, .{ .truncate = false });
    file.close(io);
}
