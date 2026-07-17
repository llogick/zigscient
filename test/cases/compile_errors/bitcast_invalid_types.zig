const y: u32 = 0;

export fn entry1() void {
    _ = @as(comptime_float, @bitCast(y));
}
export fn entry2() void {
    const x: comptime_float = undefined;
    _ = @as(u32, @bitCast(x));
}

export fn entry3() void {
    _ = @as(comptime_int, @bitCast(y));
}
export fn entry4() void {
    const x: comptime_int = undefined;
    _ = @as(u32, @bitCast(x));
}

export fn entry5() void {
    _ = @as(@EnumLiteral(), @bitCast(y));
}
export fn entry6() void {
    const x: @EnumLiteral() = undefined;
    _ = @as(u32, @bitCast(x));
}

export fn entry7() void {
    _ = @as(error{}, @bitCast(y));
}
export fn entry8() void {
    const x: error{} = undefined;
    _ = @as(u32, @bitCast(x));
}

export fn entry9() void {
    _ = @as(?(anyerror!u32), @bitCast(y));
}
export fn entry10() void {
    const x: anyerror!u32 = undefined;
    _ = @as(u32, @bitCast(x));
}

export fn entry11() void {
    _ = @as(fn () void, @bitCast(y));
}
export fn entry12() void {
    const x: fn () void = undefined;
    _ = @as(u32, @bitCast(x));
}

export fn entry13() void {
    _ = @as(noreturn, @bitCast(y));
}

export fn entry14() void {
    _ = @as(@TypeOf(null), @bitCast(y));
}
export fn entry15() void {
    const x: @TypeOf(null) = undefined;
    _ = @as(u32, @bitCast(x));
}

export fn entry16() void {
    const O = opaque {};
    _ = @as(O, @bitCast(y));
}

export fn entry17() void {
    _ = @as(??u32, @bitCast(y));
}
export fn entry18() void {
    const x: ?u32 = undefined;
    _ = @as(u32, @bitCast(x));
}

export fn entry19() void {
    _ = @as(type, @bitCast(y));
}
export fn entry20() void {
    const x: type = undefined;
    _ = @as(u32, @bitCast(x));
}

export fn entry21() void {
    _ = @as(@TypeOf(undefined), @bitCast(y));
}
export fn entry22() void {
    const x: @TypeOf(undefined) = undefined;
    _ = @as(u32, @bitCast(x));
}

export fn entry23() void {
    _ = @as(void, @bitCast(y));
}
export fn entry24() void {
    const x: void = undefined;
    _ = @as(u32, @bitCast(x));
}

export fn entry25() void {
    _ = @as(*u8, @bitCast(y));
}
export fn entry26() void {
    const x: *u8 = undefined;
    _ = @as(u32, @bitCast(x));
}

export fn entry27() void {
    _ = @as(*u8, @bitCast(@as(*u32, @ptrFromInt(y))));
}
export fn entry28() void {
    const x: *u8 = undefined;
    _ = @as(*u32, @bitCast(x));
}

export fn entry29() void {
    const S = struct { x: u32 };
    _ = @as(S, @bitCast(y));
}
export fn entry30() void {
    const S = struct { x: u32 };
    const x: S = undefined;
    _ = @as(u32, @bitCast(x));
}

export fn entry31() void {
    const U = union { x: u32 };
    _ = @as(U, @bitCast(y));
}
export fn entry32() void {
    const U = union { x: u32 };
    const x: U = undefined;
    _ = @as(u32, @bitCast(x));
}

export fn entry33() void {
    const S = struct { x: u32 };
    _ = @as([10]S, @bitCast(y));
}
export fn entry34() void {
    const S = struct { x: u32 };
    const x: [10]S = undefined;
    _ = @as(u32, @bitCast(x));
}

export fn entry35() void {
    const E = enum {};
    _ = @as(E, @bitCast(y));
}

export fn entry36() void {
    const E = enum { a, b, c };
    _ = @as(E, @bitCast(y));
}

// error
//
// :4:29: error: cannot @bitCast to 'comptime_float'
// :8:27: error: cannot @bitCast from 'comptime_float'
// :12:27: error: cannot @bitCast to 'comptime_int'
// :16:27: error: cannot @bitCast from 'comptime_int'
// :20:29: error: cannot @bitCast to '@EnumLiteral()'
// :24:27: error: cannot @bitCast from '@EnumLiteral()'
// :28:22: error: cannot @bitCast to 'error{}'
// :32:27: error: cannot @bitCast from 'error{}'
// :36:30: error: cannot @bitCast to 'anyerror!u32'
// :40:27: error: cannot @bitCast from 'anyerror!u32'
// :44:25: error: cannot @bitCast to 'fn () void'
// :48:27: error: cannot @bitCast from 'fn () void'
// :52:23: error: cannot @bitCast to 'noreturn'
// :56:28: error: cannot @bitCast to '@TypeOf(null)'
// :60:27: error: cannot @bitCast from '@TypeOf(null)'
// :65:16: error: cannot @bitCast to 'tmp.entry16.O'
// :64:15: note: opaque declared here
// :69:20: error: cannot @bitCast to '?u32'
// :69:20: note: use @ptrFromInt to cast from 'u32'
// :73:27: error: cannot @bitCast from '?u32'
// :73:27: note: use @intFromPtr to cast to 'u32'
// :77:19: error: cannot @bitCast to 'type'
// :81:27: error: cannot @bitCast from 'type'
// :85:33: error: cannot @bitCast to '@TypeOf(undefined)'
// :89:27: error: cannot @bitCast from '@TypeOf(undefined)'
// :93:19: error: @bitCast size mismatch: destination type 'void' has 0 bits but source type 'u32' has 32 bits
// :97:18: error: @bitCast size mismatch: destination type 'u32' has 32 bits but source type 'void' has 0 bits
// :101:18: error: cannot @bitCast to '*u8'
// :101:18: note: use @ptrFromInt to cast from 'u32'
// :105:27: error: cannot @bitCast from '*u8'
// :105:27: note: use @intFromPtr to cast to 'u32'
// :109:49: error: pointer type '*u32' does not allow address zero
// :113:19: error: cannot @bitCast to '*u32'
// :113:19: note: use @ptrCast to cast from '*u8'
// :118:16: error: cannot @bitCast to 'tmp.entry29.S'
// :117:15: note: struct declared here
// :123:27: error: cannot @bitCast from 'tmp.entry30.S'
// :121:15: note: struct declared here
// :128:16: error: cannot @bitCast to 'tmp.entry31.U'
// :127:15: note: union declared here
// :133:27: error: cannot @bitCast from 'tmp.entry32.U'
// :131:15: note: union declared here
// :138:20: error: cannot @bitCast to '[10]tmp.entry33.S'
// :143:27: error: cannot @bitCast from '[10]tmp.entry34.S'
// :148:16: error: cannot @bitCast to 'tmp.entry35.E'
// :147:15: note: enum declared here
// :153:16: error: cannot @bitCast to 'tmp.entry36.E'
// :152:15: note: enum declared here
