const Inner = extern struct { a: u32 };
const Outer = extern struct { a: u32, b: Inner };

export fn main() callconv(.kernel) void {
    var outer: Outer = undefined;
    const inner: *Inner = @ptrCast(&outer);
    _ = &inner;
}

// error
// backend=selfhosted
// target=spirv32-vulkan
//
// :6:27: error: cannot cast pointer '*tmp.Outer' to '*tmp.Inner'
// :6:27: note: 'tmp.Inner' must appear at offset 0 inside 'tmp.Outer'
