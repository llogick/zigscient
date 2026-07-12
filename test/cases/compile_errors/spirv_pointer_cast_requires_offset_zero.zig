const A = extern struct { x: u32, y: u32 };
const B = extern struct { a: u64 };

const a = @extern(*addrspace(.uniform) const A, .{
    .name = "a",
    .decoration = .{ .descriptor = .{ .set = 0, .binding = 0 } },
});

export fn main() callconv(.kernel) void {
    const b: *addrspace(.uniform) const B = @ptrCast(a);
    _ = &b;
}

// error
// backend=selfhosted
// target=spirv32-vulkan
//
// :10:44: error: cannot cast pointer '*addrspace(.uniform) const A' to '*addrspace(.uniform) const B'
// :10:44: note: 'B' must appear at offset 0 inside 'A'
// :10:44: note: 'uniform' pointers can only reach nested types through a first struct field or an array element
