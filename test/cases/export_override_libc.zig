/// This implementation is intentionally incorrect so we can check that it is
/// called instead of the libc symbol.
export fn isdigit(c: c_int) c_int {
    return @intFromBool(c == '0');
}

pub fn main() void {
    const static = struct {
        extern fn isdigit(c_int) c_int;
    };
    if (static.isdigit('0') == 0) @panic("override failed: isdigit('0') == 0");
    if (static.isdigit('1') != 0) @panic("override failed: isdigit('1') != 0");
}

// run
// link_libc=true
