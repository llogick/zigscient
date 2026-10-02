const std = @import("std");
const Elem0 = struct { u32, u8, u16 };
const Elem1 = struct { a: u32, b: u8, c: u16 };
fn testMultiArrayList(
    list0: std.MultiArrayList(Elem0),
    slice0: std.MultiArrayList(Elem0).Slice,
    list1: std.MultiArrayList(Elem1),
    slice1: std.MultiArrayList(Elem1).Slice,
) void {
    _ = .{ list0, slice0, list1, slice1 };
}
pub fn main() !void {
    var list0: std.MultiArrayList(Elem0) = .{};
    defer list0.deinit(std.heap.page_allocator);
    try list0.setCapacity(std.heap.page_allocator, 8);
    list0.appendAssumeCapacity(.{ 1, 2, 3 });
    list0.appendAssumeCapacity(.{ 4, 5, 6 });
    list0.appendAssumeCapacity(.{ 7, 8, 9 });
    const slice0 = list0.slice();

    var list1: std.MultiArrayList(Elem1) = .{};
    defer list1.deinit(std.heap.page_allocator);
    try list1.setCapacity(std.heap.page_allocator, 12);
    list1.appendAssumeCapacity(.{ .a = 1, .b = 2, .c = 3 });
    list1.appendAssumeCapacity(.{ .a = 4, .b = 5, .c = 6 });
    list1.appendAssumeCapacity(.{ .a = 7, .b = 8, .c = 9 });
    const slice1 = list1.slice();

    testMultiArrayList(list0, slice0, list1, slice1);
}
