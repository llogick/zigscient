const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();

    var iter = try init.minimal.args.iterateAllocator(arena);
    std.debug.assert(iter.skip());
    while (iter.next()) |arg| {
        const path_prefix = "path^";
        const path_suffix = "$";
        if (std.mem.startsWith(u8, arg, path_prefix) and std.mem.endsWith(u8, arg, path_suffix)) {
            // If we're a path, log whether we're absolute or relative, and log the basename
            const path = arg[path_prefix.len..][0 .. arg.len - path_prefix.len - path_suffix.len];
            if (std.fs.path.isAbsolute(path)) {
                std.debug.print("abs ", .{});
            } else {
                std.debug.print("rel ", .{});
            }
            std.debug.print("{s}\n", .{std.fs.path.basename(path)});

            // Create an empty dep file if necessary
            if (std.mem.endsWith(u8, path, ".d")) {
                const file = try std.Io.Dir.cwd().createFile(io, path, .{});
                defer file.close(io);
            }
        } else {
            // If it's not a path, log the arg as is
            std.debug.print("{s}\n", .{arg});
        }
    }
}
