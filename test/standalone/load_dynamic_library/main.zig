const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    const dynlib_name = args[1];

    var lib = try std.DynLib.open(dynlib_name);
    defer lib.close();

    const AddInts = *const fn (i32, i32) callconv(.c) i32;
    const addInts = lib.lookup(AddInts, "addInts").?;
    std.debug.assert(addInts(12, 34) == 46);

    const FortyTwo = *const fn () callconv(.c) i32;
    const fortyTwo = lib.lookup(FortyTwo, "fortyTwo").?;
    std.debug.assert(fortyTwo() == 42);
}
