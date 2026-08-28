export fn scalar() void {
    _ = @as(f32, 1.5) <<| 2;
}

export fn vector() void {
    _ = @Vector(2, f32){ 1.5, 2.5 } <<| @Vector(2, u8){ 1, 1 };
}

// error
//
// :2:9: error: bit shifting operation expected integer type, found 'f32'
// :6:24: error: bit shifting operation expected integer type, found 'f32'
