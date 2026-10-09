const Error = error{ OutOfMemory, ReadFailed };
const err: Error = error.OutOfMemory;

export fn a() void {
    _ = switch (err) {
        error.ReadFailed => 2,
        error.OutOfMemory => |*val| @intFromError(val.*),
    };
}

export fn b() void {
    _ = switch (err) {
        error.ReadFailed => 2,
        error.OutOfMemory => |_, tag| @intFromEnum(tag),
    };
}

// error
//
// :7:31: error: error set cannot be captured by reference
// :14:34: error: cannot capture tag of non-union type 'error{OutOfMemory,ReadFailed}'
