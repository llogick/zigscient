const lang = @import("std").lang;

fn al() comptime_int {
    return 16;
}

fn as() lang.AddressSpace {
    return .generic;
}

fn ls() []const u8 {
    return "text";
}

fn cc() lang.CallingConvention {
    return .c;
}

fn rv() type {
    return void;
}

extern var a: u64 align(al()) addrspace(as()) linksection(ls());
extern fn b() align(al()) addrspace(as()) linksection(ls()) callconv(cc()) rv();
// Intentionally not `export` so it is never analyzed since the qualifiers are
// not valid for all targets. The main point of this test is checking that Zir
// generation is done correctly for these, so the above is not an issue.
fn c() align(al()) addrspace(as()) linksection(ls()) callconv(cc()) rv() {
    const v: struct {
        x: u32,
        y: u32,
    } align(al()) = undefined;
    const ta: u64, const tb: struct {
        x: u32,
        y: u32,
    } align(al()) = .{ 0, .{ .x = 10, .y = 20 } };
    _ = v;
    _ = a;
    _ = b;
    _ = ta;
    _ = tb;
}

// compile
// output_mode=Obj
