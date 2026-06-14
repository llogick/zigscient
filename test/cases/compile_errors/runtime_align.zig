var alignment: u29 = 4;

var global: u8 align(alignment) = 0;
export fn globalWithRuntimeAlign() u8 {
    return global;
}

export fn localWithRuntimeAlign() u8 {
    const local: u8 align(alignment) = 0;
    return local;
}

export fn destructureWithRuntimeAlign() u8 {
    const de: u8 align(alignment), const structure align(alignment) = .{ 0, 0 };
    return de | structure;
}

export fn structFieldWithRuntimeAlign() u8 {
    const @"struct": struct { field: u8 align(alignment) } = .{ .field = 0 };
    return @"struct".field;
}

export fn unionFieldWithRuntimeAlign() u8 {
    const @"union": union { field: u8 align(alignment) } = .{ .field = 0 };
    return @"union".field;
}

export fn pointerWithRuntimeAlign() u8 {
    const ptr: *align(alignment) u8 = &global;
    return ptr.*;
}

// error
//
// :3:22: error: unable to resolve comptime value
// :3:22: note: alignment must be comptime-known
// :9:27: error: unable to resolve comptime value
// :9:27: note: alignment must be comptime-known
// :14:24: error: unable to resolve comptime value
// :14:24: note: alignment must be comptime-known
// :19:47: error: unable to resolve comptime value
// :19:47: note: alignment must be comptime-known
// :24:45: error: unable to resolve comptime value
// :24:45: note: alignment must be comptime-known
// :29:23: error: unable to resolve comptime value
// :29:23: note: alignment must be comptime-known
